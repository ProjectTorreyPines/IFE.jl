# ActorBalanceOfPlant — IFE balance of plant (thermal cycle + plant electricity needs).
#
# IFE-owned counterpart of `FUSE.ActorBalanceOfPlant`, which cannot run on an
# `IFEdd.dd` for three reasons, each handled here:
#
#   1. Its constructor reads `dd.divertors`, which `IFEdd.dd` does not have.
#      IFE has no divertor, so the divertor heat load is zero.
#   2. With no divertor and no radiation source in `core_sources`, the divertor
#      and wall heat loads are both zero, and `BalanceOfPlantSurrogate` computes
#      `divertor / (divertor + wall)` = 0/0 and fails its own range assertion.
#      The wall heat load is floored at a negligible value to keep that defined.
#   3. Its `_step` steps the power-needs sub-actor through `FUSE._step(::ActorPowerNeeds)`,
#      the magnetic-confinement path (cryostat, pf_active, no driver). This actor
#      steps it with IFE's `_step_power_needs!` (driver, tritium handling) instead.
#
# The thermal cycle itself is FUSE's `ActorThermalPlant`, which only reads the
# heat loads set in `balance_of_plant.power_plant.heat_load`.

# Floor on the wall heat load passed to the thermal cycle [W]; see (2) above.
const WALL_HEAT_LOAD_FLOOR = 1e-6

FUSE.@actor_parameters_struct ActorBalanceOfPlant{T} begin
end

mutable struct ActorBalanceOfPlant{D,P} <: FUSE.CompoundAbstractActor{D,P}
    dd::IFEdd.dd{D}
    par::FUSE.OverrideParameters{P,FUSEparameters__ActorBalanceOfPlant{P}}
    thermal_plant_actor::FUSE.ActorThermalPlant{D,P}
    power_needs_actor::FUSE.ActorPowerNeeds{D,P}
    function ActorBalanceOfPlant(dd::IFEdd.dd{D}, par::FUSEparameters__ActorBalanceOfPlant{P}, act::AbstractParametersActors{P}; kw...) where {D<:Real,P<:Real}
        FUSE.logging_actor_init(ActorBalanceOfPlant)
        par = FUSE.OverrideParameters(par; kw...)
        thermal_plant_actor = FUSE.ActorThermalPlant(dd, act.ActorThermalPlant, act)
        power_needs_actor = FUSE.ActorPowerNeeds(dd, act.ActorPowerNeeds)
        return new{D,P}(dd, par, thermal_plant_actor, power_needs_actor)
    end
end

"""
    ActorBalanceOfPlant(dd::IFEdd.dd, act::AbstractParametersActors; kw...)

Balance of plant for an IFE plant. Sets the thermal cycle heat loads from IFE
sources (breeder from `dd.blanket`, no divertor, wall from `dd.core_sources`
radiation), runs `FUSE.ActorThermalPlant` for the electric power generated, and
fills the plant's electricity consumption with the IFE power-needs model (driver
wall-plug power, tritium handling).

Stores data in `dd.balance_of_plant`.
"""
function ActorBalanceOfPlant(dd::IFEdd.dd, act::AbstractParametersActors; kw...)
    actor = ActorBalanceOfPlant(dd, act.ActorBalanceOfPlant, act; kw...)
    FUSE.step(actor)
    FUSE.finalize(actor)
    return actor
end

function FUSE._step(actor::ActorBalanceOfPlant)
    dd = actor.dd

    bop = dd.balance_of_plant
    IMAS.@ddtime(bop.time = dd.global_time)

    # heat sources: breeder only, IFE has no divertor
    breeder_heat_load = isempty(dd.blanket.module) ? 0.0 : sum(bmod.time_slice[].power_thermal_extracted for bmod in dd.blanket.module)
    IMAS.@ddtime(bop.power_plant.heat_load.breeder = breeder_heat_load)
    IMAS.@ddtime(bop.power_plant.heat_load.divertor = 0.0)
    wall_heat_load = max(abs(IMAS.radiation_losses(dd.core_sources)), WALL_HEAT_LOAD_FLOOR)
    IMAS.@ddtime(bop.power_plant.heat_load.wall = wall_heat_load)

    FUSE.finalize(FUSE.step(actor.thermal_plant_actor))

    _step_power_needs!(actor.power_needs_actor)
    FUSE.finalize(actor.power_needs_actor)

    return actor
end
