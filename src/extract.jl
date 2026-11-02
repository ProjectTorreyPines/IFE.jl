# IFE-specific extract functions.
#
# Ported from joey_fork/IMAS.jl/src/extract/extract_ife.jl. joey's monolithic
# `IMAS.dd` carried both the standard IDS and the IFE IDS, so every extract
# closure took a single `dd`. `IFEdd.dd` embeds the standard IDS subset it
# needs, so the same single-argument shape carries over unchanged — the only
# rename is `dd.ife_driver` -> `dd.driver`.
#
# `IMAS.ExtractFunction` and `IMAS.extract` both dispatch on the abstract
# `IMAS.DD`, so they accept a satellite container with no change on the IMAS
# side. Entries that raise are recorded on the `ExtractFunction` rather than
# propagating, which is how a partially populated `dd` still extracts.

using OrderedCollections: OrderedDict

"""
    duty_cycle(ife::IFEdd.dd) -> Float64

Return the IFE duty cycle `τ_pulse / T_rep` from `ife.driver`.
Returns `NaN` if the driver is not populated.

This describes the drive, not the simulated burn: `ActorTransport` overwrites
`pulse_length` with the gain model's drive duration, which differs from the on-window
of the pulse trace that the fusion power is spread over. To cycle-average a power,
use [`cycle_average`](@ref), not this ratio.
"""
function duty_cycle(ife::IFEdd.dd)
    isempty(ife.driver.beam) && return NaN
    isempty(ife.driver.time) && return NaN
    tau = ife.driver.beam[1].pulse_length    # s
    T_rep = ife.driver.time[end]             # s
    return tau / T_rep
end

"""
    cycle_average(power, ife::IFEdd.dd) -> Float64

Average `power(cp1d)` over one repetition period by integrating over the
`core_profiles` time slices, the same way `ActorBlanket` averages the neutron power.
"""
function cycle_average(power::Function, ife::IFEdd.dd)
    times = ife.core_profiles.time
    powers = [power(ife.core_profiles.profiles_1d[t]) for t in times]
    return FUSE.trapz(times, powers) / (times[end] - times[1])
end

"""
    ExtractFunctionsLibrary

IFE's scalar extract library: 29 `IMAS.ExtractFunction` entries in seven groups
(`:driver`, `:target`, `:plasma_peak`, `:power_avg`, `:neutronics`, `:bop`, `:costing`).

`IMAS.extract(dd::IFEdd.dd)` uses it in place of the tokamak library.
Rebuilt in place by [`update_ExtractFunctionsLibrary!`](@ref).
"""
const ExtractFunctionsLibrary = OrderedDict{Symbol,IMAS.ExtractFunction}()

"""
    update_ExtractFunctionsLibrary!()

Rebuild [`ExtractFunctionsLibrary`](@ref) in place.
"""
function update_ExtractFunctionsLibrary!()
    IEFL = ExtractFunctionsLibrary
    empty!(IEFL)

    function EF(group::Symbol, name::Symbol, units::String, func::Function)
        xfun = IMAS.ExtractFunction(group, name, units, func)
        IEFL[name] = xfun
        return xfun
    end

    #! format: off

    # --- driver ---
    EF(:driver, :E_driver,       "MJ",  dd -> sum(b.energy for b in dd.driver.beam) / 1e6)
    EF(:driver, :rep_rate,       "Hz",  dd -> 1.0 / dd.driver.time[end])
    EF(:driver, :tau_pulse,      "ns",  dd -> dd.driver.beam[1].pulse_length * 1e9)
    EF(:driver, :duty_cycle,     "-",   dd -> duty_cycle(dd))
    EF(:driver, :n_beams,        "-",   dd -> Float64(length(dd.driver.beam)))
    EF(:driver, :eta_conversion, "-",   dd -> dd.driver.beam[1].efficiency.conversion)
    EF(:driver, :eta_coupling,   "-",   dd -> dd.driver.beam[1].efficiency.coupling)
    EF(:driver, :P_driver_avg,   "MW",  dd -> IEFL[:E_driver](dd) * IEFL[:rep_rate](dd))

    # --- target ---
    EF(:target, :R_target,       "mm",  dd -> dd.pellets.launcher[1].shape.size[1] * 1e3)
    EF(:target, :R_fuel,         "mm",  dd -> begin
        layer = dd.pellets.time_slice[].pellet[1].layer
        (layer[1].thickness + layer[2].thickness) * 1e3
    end)
    EF(:target, :R_hotspot,      "mm",  dd -> dd.pellets.time_slice[].pellet[1].layer[1].thickness * 1e3)
    EF(:target, :ablator,        "-",   dd -> dd.pellets.time_slice[].pellet[1].layer[3].species[1].label)
    EF(:target, :rep_rate_pellet,"Hz",  dd -> dd.pellets.time_slice[].pellet[1].frequency)
    EF(:target, :IFAR,           "-",   dd -> dd.summary.target.ifar)

    # --- hot-state (peak) plasma quantities at dd.global_time = τ_pulse ---
    EF(:plasma_peak, :Te0_peak,  "keV", dd -> dd.core_profiles.profiles_1d[].electrons.temperature[1] / 1e3)
    EF(:plasma_peak, :ne0_peak,  "m⁻³", dd -> dd.core_profiles.profiles_1d[].electrons.density_thermal[1])
    EF(:plasma_peak, :P_fus_peak,"GW",  dd -> IMAS.fusion_power(dd) / 1e9)

    # --- cycle-averaged power quantities ---
    EF(:power_avg, :P_fus_avg,    "MW",  dd -> cycle_average(IMAS.fusion_power, dd) / 1e6)
    EF(:power_avg, :P_neutron_avg,"MW",  dd -> cycle_average(IMAS.fusion_neutron_power, dd) / 1e6)
    EF(:power_avg, :P_alpha_avg,  "MW",  dd -> cycle_average(IMAS.fusion_plasma_power, dd) / 1e6)
    EF(:power_avg, :Q_target,     "-",   dd -> IEFL[:P_fus_avg](dd) / IEFL[:P_driver_avg](dd))

    # --- neutronics ---
    EF(:neutronics, :TBR,         "-",   dd -> IMAS.@ddtime(dd.blanket.tritium_breeding_ratio))
    # `wall_loading` is already cycle-averaged by ActorBlanket
    EF(:neutronics, :peak_wall_flux_avg, "MW/m²", dd -> begin
        maximum(sqrt.(dd.neutronics.time_slice[].wall_loading.flux_r .^ 2 .+
                      dd.neutronics.time_slice[].wall_loading.flux_z .^ 2)) / 1e6
    end)

    # --- balance of plant ---
    EF(:bop, :P_electric_generated, "MW",  dd -> IMAS.@ddtime(dd.balance_of_plant.power_plant.power_electric_generated) / 1e6)
    EF(:bop, :P_electric_net,       "MW",  dd -> IMAS.@ddtime(dd.balance_of_plant.power_electric_net) / 1e6)
    EF(:bop, :Q_plant,              "-",   dd -> IMAS.@ddtime(dd.balance_of_plant.Q_plant))
    EF(:bop, :eta_thermal,          "%",   dd -> IMAS.@ddtime(dd.balance_of_plant.thermal_efficiency_plant) * 100.0)

    # --- costing ---
    EF(:costing, :capital_cost,   "\$B",    dd -> dd.costing.cost_direct_capital.cost / 1e3)
    EF(:costing, :levelized_CoE,  "\$/kWh", dd -> dd.costing.levelized_CoE)

    #! format: on

    return IEFL
end
update_ExtractFunctionsLibrary!()

"""
    add_ConstraintFunctions!()

Add IFE's constraints to `IMAS.ConstraintFunctionsLibrary`: `:max_ifar`, which limits
the in-flight aspect ratio to below 30.

`IMAS.update_ConstraintFunctionsLibrary!()` empties that library and rebuilds it from
the IMAS list, so call this after it. `IMAS.extract(dd, :all)` and `:moopt` call this
themselves, so the `max_ifar` column does not depend on the call order.
"""
function add_ConstraintFunctions!()
    if !haskey(IMAS.ConstraintFunctionsLibrary, :max_ifar)
        IMAS.ConstraintFunction(:max_ifar, "-", dd -> dd.summary.target.ifar, <, 30.0)
    end
    return IMAS.ConstraintFunctionsLibrary
end

"""
    IMAS.extract(dd::IFEdd.dd)

Extend `IMAS.extract` for an IFE container: extract key scalar quantities for an IFE case from `dd`.

Power quantities (fusion, neutron, alpha, wall flux) are cycle-averaged by integrating
over the time slices, so `Q_target` equals the target gain from `ActorTransport`.

Returns an `OrderedDict{Symbol,IMAS.ExtractFunction}` — the same type as
`IMAS.extract(dd)` — so the standard `show`, `print_tiled` and HDF5 save
methods all apply.

# Groups
- `:driver`      — driver beam energy, repetition rate, pulse length, efficiencies
- `:target`      — pellet geometry and repetition rate
- `:plasma_peak` — hot-state plasma quantities at `dd.global_time = τ_pulse`
- `:power_avg`   — cycle-averaged power and target gain Q
- `:neutronics`  — TBR and cycle-averaged peak wall flux
- `:bop`         — balance-of-plant electric output and efficiency
- `:costing`     — capital cost and levelized cost of electricity
"""
function IMAS.extract(dd::IFEdd.dd)
    return IMAS.extract(dd, :extract)
end

"""
    IMAS.extract(dd::IFEdd.dd, library::Symbol)

Same `library` options as `IMAS.extract(dd::IMAS.DD, library)`, with IFE's
[`ExtractFunctionsLibrary`](@ref) in place of the tokamak one:

  - `:extract` => `ExtractFunctionsLibrary`
  - `:moopt` => `IMAS.ConstraintFunctionsLibrary` + `IMAS.ObjectiveFunctionsLibrary`
  - `:all` => `ExtractFunctionsLibrary` + both of the above

FUSE's study runners call `IMAS.extract(dd, :all)` for each case, so this is what
fills `study.dataframe` and `extract.csv` when the workflow runs on an `IFEdd.dd`.
"""
function IMAS.extract(dd::IFEdd.dd, library::Symbol)
    @assert library in (:extract, :moopt, :all) "library must be :extract, :moopt or :all"
    library == :extract && return IMAS.extract(dd, ExtractFunctionsLibrary)
    add_ConstraintFunctions!()
    xtract = OrderedDict{Symbol,IMAS.ExtractFunction}()
    if library == :all
        merge!(xtract, ExtractFunctionsLibrary)
    end
    for cnst in values(IMAS.ConstraintFunctionsLibrary)
        xtract[cnst.name] = IMAS.ExtractFunction(:constraints, cnst.name, "-", dd -> cnst(dd))
    end
    for objf in values(IMAS.ObjectiveFunctionsLibrary)
        xtract[objf.name] = IMAS.ExtractFunction(:objectives, objf.name, "-", dd -> objf(dd))
    end
    return IMAS.extract(dd, xtract)
end
