# IFEParametersActors — slim IFE-flavored version of `FUSE.ParametersActors`.
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
#   ActorCosting        → init_costing!(dd, act.ActorCosting) baseline
#   ActorCostingIFE     → IFE plant cost
#   ActorIFEBlanket     → IFE blanket TBR / neutronics
#   ActorIFETransport   → IFE 0-D gain model
#   ActorPowerNeeds     → FUSE actor, IFEdd dispatches on IFEdd.dd
#
# Plausibly useful soon (magnetic-agnostic, plant-level):
#   ActorBalanceOfPlant → BOP electric/thermal flow
#   ActorThermalPlant   → thermal cycle modelling

mutable struct IFEParametersActors{T<:Real} <: AbstractIFEParametersActors{T}
    _parent::WeakRef
    _name::Symbol
    # Used by the IFE workflow today
    ActorCosting::FUSE.FUSEparameters__ActorCosting{T}
    ActorCostingIFE::FUSEparameters__ActorCostingIFE{T}
    ActorIFEBlanket::FUSEparameters__ActorIFEBlanket{T}
    ActorIFETransport::FUSEparameters__ActorIFETransport{T}
    ActorPowerNeeds::FUSE.FUSEparameters__ActorPowerNeeds{T}
    # Plant-level, magnetic-agnostic — kept for future IFE use
    ActorBalanceOfPlant::FUSE.FUSEparameters__ActorBalanceOfPlant{T}
    ActorThermalPlant::FUSE.FUSEparameters__ActorThermalPlant{T}
end

function IFEParametersActors{T}() where {T<:Real}
    act = IFEParametersActors{T}(
        WeakRef(nothing),
        :act,
        FUSE.FUSEparameters__ActorCosting{T}(),
        FUSEparameters__ActorCostingIFE{T}(),
        FUSEparameters__ActorIFEBlanket{T}(),
        FUSEparameters__ActorIFETransport{T}(),
        FUSE.FUSEparameters__ActorPowerNeeds{T}(),
        FUSE.FUSEparameters__ActorBalanceOfPlant{T}(),
        FUSE.FUSEparameters__ActorThermalPlant{T}(),
    )
    FUSE.setup_parameters!(act)
    return act
end

IFEParametersActors() = IFEParametersActors{Float64}()
