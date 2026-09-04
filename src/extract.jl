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
"""
function duty_cycle(ife::IFEdd.dd)
    isempty(ife.driver.beam) && return NaN
    isempty(ife.driver.time) && return NaN
    tau = ife.driver.beam[1].pulse_length    # s
    T_rep = ife.driver.time[end]             # s
    return tau / T_rep
end

"""
    ExtractFunctionsLibrary

IFE's scalar extract library: 28 `IMAS.ExtractFunction` entries in seven groups
(`:driver`, `:target`, `:plasma_peak`, `:power_avg`, `:neutronics`, `:bop`, `:costing`).

`IMAS.extract(dd::IFEdd.dd)` uses it in place of the tokamak library, and it is what
an IFE study passes as `FUSE.StudyDatabaseGenerator(...; extract_library=...)`.
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

    # --- hot-state (peak) plasma quantities at dd.global_time = τ_pulse ---
    EF(:plasma_peak, :Te0_peak,  "keV", dd -> dd.core_profiles.profiles_1d[].electrons.temperature[1] / 1e3)
    EF(:plasma_peak, :ne0_peak,  "m⁻³", dd -> dd.core_profiles.profiles_1d[].electrons.density_thermal[1])
    EF(:plasma_peak, :P_fus_peak,"GW",  dd -> IMAS.fusion_power(dd) / 1e9)

    # --- duty-cycle-averaged power quantities ---
    EF(:power_avg, :P_fus_avg,    "MW",  dd -> IMAS.fusion_power(dd) / 1e6 * duty_cycle(dd))
    EF(:power_avg, :P_neutron_avg,"MW",  dd -> IMAS.fusion_neutron_power(dd) / 1e6 * duty_cycle(dd))
    EF(:power_avg, :P_alpha_avg,  "MW",  dd -> IMAS.fusion_plasma_power(dd) / 1e6 * duty_cycle(dd))
    EF(:power_avg, :Q_target,     "-",   dd -> IEFL[:P_fus_avg](dd) / IEFL[:P_driver_avg](dd))

    # --- neutronics ---
    EF(:neutronics, :TBR,         "-",   dd -> IMAS.@ddtime(dd.blanket.tritium_breeding_ratio))
    EF(:neutronics, :peak_wall_flux_avg, "MW/m²", dd -> begin
        dc = duty_cycle(dd)
        maximum(sqrt.(dd.neutronics.time_slice[].wall_loading.flux_r .^ 2 .+
                      dd.neutronics.time_slice[].wall_loading.flux_z .^ 2)) / 1e6 * dc
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
    IMAS.extract(dd::IFEdd.dd)

Extend `IMAS.extract` for an IFE container: extract key scalar quantities for an IFE case from `dd`.

Power quantities (fusion, neutron, alpha, wall flux) are duty-cycle-averaged:
`<P> = P_peak × (τ_pulse / T_rep)`.

Returns an `OrderedDict{Symbol,IMAS.ExtractFunction}` — the same type as
`IMAS.extract(dd)` — so the standard `show`, `print_tiled` and HDF5 save
methods all apply.

# Groups
- `:driver`      — driver beam energy, repetition rate, pulse length, efficiencies
- `:target`      — pellet geometry and repetition rate
- `:plasma_peak` — hot-state plasma quantities at `dd.global_time = τ_pulse`
- `:power_avg`   — duty-cycle-averaged power and target gain Q
- `:neutronics`  — TBR and cycle-averaged peak wall flux
- `:bop`         — balance-of-plant electric output and efficiency
- `:costing`     — capital cost and levelized cost of electricity
"""
function IMAS.extract(dd::IFEdd.dd)
    return IMAS.extract(dd, ExtractFunctionsLibrary)
end
