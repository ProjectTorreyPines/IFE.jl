# ActorCosting — IFE plant costing (PROCESS methodology + ARIES accounts).
#
# Ported from joey_fork/FUSE.jl/src/actors/costing/ife_costing_actor.jl.
# Single-container signature: `dd::IFEdd.dd`. Helpers (DollarAdjust, future_dollars,
# bop_powers, cost_*_ARIES) are accessed via FUSE namespace and rely on the
# Phase 3 signature relaxations on FUSE side.

# Cost entries are pinned to `Measurement{Float64}` rather than the container's `T`:
# `act` is an `ParametersActors{Float64}`, so `Entry{T}` would resolve to
# `Entry{Float64}` and could not hold a `±` value. Pinning keeps the field types
# concrete and inference-stable regardless of `P`. Defaults follow joey.
FUSE.@actor_parameters_struct ActorCosting{T} begin
    # Plant economics. Same definitions as `FUSE.ActorCosting`; owned here so an
    # IFE `act` carries one costing parameter group, not two.
    construction_start_year::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("year", "Year that plant construction begins"; default=Dates.year(Dates.now()) + 10.0 ± 5.0)
    future_inflation_rate::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("-", "Predicted average rate of future inflation"; default=0.025 ± 0.0125)
    plant_lifetime::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("year", "Lifetime of the plant"; default=35.0 ± 5.0)
    availability::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("-", "Availability fraction of the plant"; default=0.8 ± 0.1)
    # IFE plant
    land_space::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("acres", "Plant site space required"; default=1000.0 ± 100.0)
    building_volume::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("m^3", "Volume of the IFE building"; default=140e3 ± 14e3)
    interest_rate::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("-", "Annual interest rate fraction of direct capital cost"; default=0.05 ± 0.01)
    indirect_cost_rate::FUSE.Entry{Measurement{Float64}} = FUSE.Entry{Measurement{Float64}}("-",
        "Indirect cost associated with construction, equipment, services, engineering construction management and owners cost";
        default=0.4 ± 0.01)
    escalation_fraction::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("-", "Yearly escalation fraction based on risk assessment"; default=0.05 ± 0.01)
    blanket_lifetime::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("year", "Lifetime of the blanket"; default=7.0 ± 1.0)
    driver_cost_fixed::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("M\$", "Fixed capital cost of IFE driver system at zero drive energy (1990 US\$)"; default=154.3 ± 30.0)
    driver_cost_per_MJ::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("M\$/MJ", "Variable capital cost of IFE driver per MJ of drive energy (1990 US\$)"; default=111.4 ± 20.0)
    cost_per_pellet::FUSE.Entry{Measurement{Float64}} =
        FUSE.Entry{Measurement{Float64}}("\$", "Target fabrication cost per pellet"; default=0.0 ± 0.0)
end

# `ddR` is the uncertainty workspace: costs are computed on a `Measurement{Float64}`
# promotion of the user's container, then written back as nominal values in
# `_finalize`. Mirrors `FUSE.ActorCosting`, which promotes with the same
# `get_timeslice` call and pins its sub-actor to `Measurement{Float64}`.
#
# `get_timeslice` builds the result via `Base.typename(typeof(ids)).wrapper{el_type}`,
# so its return type is not inferrable. Declaring `ddR` as a concrete type stops that
# instability at the struct boundary: it costs one dynamic dispatch in the constructor
# and leaves the whole of `_step` operating on concrete types.
mutable struct ActorCosting{D,P} <: FUSE.SingleAbstractActor{D,P}
    dd::IFEdd.dd{D}
    par::FUSE.OverrideParameters{P,FUSEparameters__ActorCosting{P}}
    ddR::IFEdd.dd{Measurement{Float64}}
    function ActorCosting(dd::IFEdd.dd{D}, par::FUSEparameters__ActorCosting{P}; kw...) where {D<:Real,P<:Real}
        FUSE.logging_actor_init(ActorCosting)
        par = FUSE.OverrideParameters(par; kw...)
        empty!(dd.costing)
        ddR = IMAS.get_timeslice(Measurement{Float64}, dd)
        FUSE.copy_workflow!(ddR, dd)
        # Costing baseline, uncertainties intact: this is the copy the cost model reads.
        ddR.costing.construction_start_year = par.construction_start_year
        ddR.costing.future.inflation_rate = par.future_inflation_rate
        ddR.costing.plant_lifetime = par.plant_lifetime
        ddR.costing.availability = par.availability
        return new{D,P}(dd, par, ddR)
    end
end

"""
    ActorCosting(dd::IFEdd.dd, act::AbstractParametersActors; kw...)

Estimates fusion power plant costs for an IFE (Inertial Fusion Energy) plant using the
PROCESS IFE costing methodology adapted to the ARIES cost account structure.

**Direct Capital Costs:**
- IFE reactor systems: all build layers (chamber, wall, blanket, shield, vessel) via volume-based unit costs
- Driver system: linear cost model as a function of total drive energy, based on PROCESS defaults
- Facility infrastructure: land, buildings, hot cells, heat transfer systems (shared with ARIES)
- Balance of plant: power conversion equipment, electrical systems, fuel handling

**Operating Costs:**
- Tritium handling and fuel cycle operations
- Maintenance and operations scaled to plant capacity
- Blanket module replacement based on lifetime parameters

**Decommissioning Costs:**
- End-of-life plant dismantling and waste management

The driver cost model follows the PROCESS generic/laser driver formulation:
`driver_cost = n_drivers * (driver_cost_fixed + driver_cost_per_MJ * E_drive_MJ)`
where `E_drive_MJ` is the total drive energy per shot in MJ and `n_drivers` is the
number of beams in `dd.driver`.

Default cost coefficients (`driver_cost_fixed = 154.3 M\$`, `driver_cost_per_MJ = 111.4 M\$/MJ`)
are taken from PROCESS IFE defaults (1990 US\$) and are inflation-adjusted to future dollars.

!!! note

    Results are stored in `dd.costing` with detailed breakdown by system and subsystem.
    Cost coefficients for PROCESS defaults are from Ref: Kovari et al., Fusion Eng. Des. (2014).
"""
function ActorCosting(dd::IFEdd.dd, act::AbstractParametersActors; kw...)
    actor = ActorCosting(dd, act.ActorCosting; kw...)
    FUSE.step(actor)
    FUSE.finalize(actor)
    return actor
end

function FUSE._step(actor::ActorCosting)
    dd = actor.ddR
    par = actor.par
    cst = dd.costing

    cost_direct = cst.cost_direct_capital
    cost_ops = cst.cost_operations
    cost_decom = cst.cost_decommissioning

    da = FUSE.DollarAdjust(dd)

    power_thermal, power_electric_generated, power_electric_net = FUSE.bop_powers(dd.balance_of_plant)

    ###### Direct Capital ######

    ### IFE reactor systems
    reactor = resize!(cost_direct.system, "name" => "reactor")

    for layer in dd.build.layer
        c = cost_direct_capital_IFE(layer, da)
        if c > 0.0
            sub = resize!(reactor.subsystem, "name" => layer.name)
            sub.cost = c
        end
    end

    # Driver system
    if !isempty(dd.driver.beam)
        da.year_assessed = 1990
        total_energy_MJ = sum(beam.energy for beam in dd.driver.beam) / 1e6
        n_drivers = length(dd.driver.beam)
        driver_cost = FUSE.future_dollars(n_drivers * (par.driver_cost_fixed + par.driver_cost_per_MJ * total_energy_MJ), da)
        sub = resize!(reactor.subsystem, "name" => "driver system")
        sub.cost = driver_cost
    end

    ### Facility
    sys = resize!(cost_direct.system, "name" => "facility")

    for item in vcat(:land, :buildings, :hot_cell, :heat_transfer_loop_materials, :balance_of_plant_equipment, :fuel_cycle_rad_handling)
        sub = resize!(sys.subsystem, "name" => replace(string(item), "_" => " "))
        if item == :land
            sub.cost = FUSE.cost_direct_capital_ARIES(item, par.land_space, power_electric_generated, da)
        elseif item == :buildings
            sub.cost = FUSE.cost_direct_capital_ARIES(item, par.building_volume,
                par.land_space, power_electric_generated,
                power_thermal, power_electric_net, da)
        elseif item == :hot_cell
            sub.cost = FUSE.cost_direct_capital_ARIES(item, par.building_volume, da)
        elseif item == :heat_transfer_loop_materials
            sub.cost = FUSE.cost_direct_capital_ARIES(item, power_thermal, da)
        elseif item == :balance_of_plant_equipment
            sub.cost = FUSE.cost_direct_capital_ARIES(item, power_thermal, power_electric_generated, da, dd)
        elseif item == :fuel_cycle_rad_handling
            sub.cost = FUSE.cost_direct_capital_ARIES(item, power_thermal, power_electric_net, da)
        end
    end

    ###### Operations ######
    sys = resize!(cost_ops.system, "name" => "tritium handling")
    sys.yearly_cost = FUSE.cost_operations_ARIES(:tritium_handling, da)

    sys = resize!(cost_ops.system, "name" => "maintenance and operators")
    sys.yearly_cost = FUSE.cost_operations_ARIES(:operation_maintenance, power_electric_generated, da)

    sys = resize!(cost_ops.system, "name" => "replacements")
    blanket_idx = findfirst(item -> item.name == "blanket", reactor.subsystem)
    blanket_cost = blanket_idx !== nothing ? reactor.subsystem[blanket_idx].cost : nothing
    sub = resize!(sys.subsystem, "name" => "blanket_replacement")
    sub.yearly_cost = FUSE.cost_operations_ARIES(:blanket_replacement, blanket_cost, par.blanket_lifetime, da)

    rep_rate = isempty(dd.pellets.time_slice) ? zero(eltype(dd)) : dd.pellets.time_slice[].pellet[1].frequency
    pellet_yearly_cost = par.cost_per_pellet * rep_rate * 3600.0 * 24.0 * 365.0 * cst.availability / 1e6  # M$
    da.year_assessed = 2024
    sys = resize!(cost_ops.system, "name" => "target fabrication")
    sys.yearly_cost = FUSE.future_dollars(pellet_yearly_cost, da)

    ###### Decommissioning ######
    sys = resize!(cost_decom.system, "name" => "decommissioning")
    sys.cost = FUSE.cost_decomissioning_ARIES(:decom_wild_guess, cst.plant_lifetime, da)

    ###### Total cost over lifetime ######
    capital_cost_rate = par.interest_rate / (1.0 - (1.0 + par.interest_rate)^(-1.0 * cst.plant_lifetime))
    yearly_cost = (capital_cost_rate * cost_direct.cost + cost_ops.yearly_cost + cost_decom.cost / cst.plant_lifetime)
    annual_growth_rate = (1.0 + par.escalation_fraction) * (1.0 + par.indirect_cost_rate)
    cst.cost_lifetime = annual_growth_rate * yearly_cost * cst.plant_lifetime

    ###### Levelized Cost Of Electricity ######
    cst.levelized_CoE = (cst.cost_lifetime * 1E6) / (cst.plant_lifetime * 24 * 365 * power_electric_net / 1e3 * cst.availability)

    return actor
end

"""
    _finalize(actor::ActorCosting)

Sort cost systems and subsystems by magnitude (descending) for easy inspection.
"""
function FUSE._finalize(actor::ActorCosting)
    sort!(actor.ddR.costing.cost_direct_capital.system; by=x -> x.cost, rev=true)
    for sys in actor.ddR.costing.cost_direct_capital.system
        sort!(sys.subsystem; by=x -> x.cost, rev=true)
    end
    # `fill!` drops the uncertainty component, leaving nominal values in the
    # user's Float64 container. The full distributions stay on `actor.ddR`.
    fill!(actor.dd.costing, actor.ddR.costing)
    return actor
end

#= ========================= =#
#  IFE direct capital costs   #
#= ========================= =#
function cost_direct_capital_IFE(layer::IFEdd.AbstractIFEBuildLayer, da::FUSE.DollarAdjust{T}) where {T<:Real}
    da.year_assessed = 2016
    ltype = layer.type
    if ltype == Int(IMAS._plasma_)
        return zero(T)
    elseif ltype == Int(IMAS._blanket_)
        cost = layer.volume * 0.75
    elseif ltype == Int(IMAS._shield_)
        cost = layer.volume * 0.29
    elseif ltype ∈ (Int(IMAS._wall_), Int(IMAS._vessel_))
        cost = layer.volume * 0.36
    else
        return zero(T)
    end
    return FUSE.future_dollars(cost, da)
end
