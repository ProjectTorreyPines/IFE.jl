# ParametersActors — slim IFE-flavored version of `FUSE.ParametersActors`.
#
# FUSE.ParametersActors uses `FUSE.@insert_subtype_members FUSE.ParametersActor`
# which enumerates *all* `FUSE.ParametersActor` subtypes registered at struct
# definition time (~70 actors covering magnetic equilibrium, current drive,
# flux matching, ARIES/Sheffield costing internals, etc.). IFE workflows touch
# almost none of those, so the macro-expanded container pollutes
# `propertynames(act)`, `rand(act)`, and serialization.
#
# Instead we hand-list the actors actually used by IFE plus a couple of
# magnetic-agnostic plant-level ones that IFE workflows are likely to invoke
# next. Extend this list (and the constructor below) as new actors become
# relevant — every name must resolve to a concrete `FUSE.ParametersActor`
# subtype.
#
# Used by IFE workflow today:
#   ActorCosting        → IFE plant cost (IFE.ActorCosting, not FUSE's)
#   ActorBlanket     → IFE blanket TBR / neutronics
#   ActorTransport   → IFE 0-D gain model
#   ActorPowerNeeds     → FUSE actor, IFEdd dispatches on IFEdd.dd
#
# Plausibly useful soon (magnetic-agnostic, plant-level):
#   ActorBalanceOfPlant → BOP electric/thermal flow
#   ActorThermalPlant   → thermal cycle modelling

mutable struct ParametersActors{T<:Real} <: AbstractParametersActors{T}
    _parent::WeakRef
    _name::Symbol
    # Used by the IFE workflow today
    ActorCosting::FUSEparameters__ActorCosting{T}
    ActorBlanket::FUSEparameters__ActorBlanket{T}
    ActorTransport::FUSEparameters__ActorTransport{T}
    ActorPowerNeeds::FUSE.FUSEparameters__ActorPowerNeeds{T}
    # Plant-level, magnetic-agnostic — kept for future IFE use
    ActorBalanceOfPlant::FUSE.FUSEparameters__ActorBalanceOfPlant{T}
    ActorThermalPlant::FUSE.FUSEparameters__ActorThermalPlant{T}
end

function ParametersActors{T}() where {T<:Real}
    act = ParametersActors{T}(
        WeakRef(nothing),
        :act,
        FUSEparameters__ActorCosting{T}(),
        FUSEparameters__ActorBlanket{T}(),
        FUSEparameters__ActorTransport{T}(),
        FUSE.FUSEparameters__ActorPowerNeeds{T}(),
        FUSE.FUSEparameters__ActorBalanceOfPlant{T}(),
        FUSE.FUSEparameters__ActorThermalPlant{T}(),
    )
    FUSE.setup_parameters!(act)
    return act
end

ParametersActors() = ParametersActors{Float64}()
