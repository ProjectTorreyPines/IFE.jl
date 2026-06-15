# IFE-owned abstract supertypes for parameter containers.
#
# Lives in its own file so it can be included BEFORE the actor files (which
# use these abstracts in their outer-constructor signatures) and BEFORE the
# concrete container structs (`IFEParametersInits`, `IFEParametersActors`)
# which inherit from them.
#
# These let IFE-specific functions (`init_ife!`, `ActorIFETransport`, …)
# narrow their `ini` / `act` arguments from the broad `FUSE.ParametersAllInits`
# / `FUSE.ParametersAllActors` down to "anything claiming to be an IFE
# container", while still satisfying FUSE's generic dispatch surface for
# shared helpers (`init_balance_of_plant!`, `init_requirements!`, `rand`, …).
#
# Add new concrete subtypes (e.g. a full mirror of FUSE.ParametersInits/Actors,
# or scenario-specific flavours) without modifying this file.

"""
    AbstractIFEParametersInits{T<:Real} <: FUSE.ParametersAllInits{T}

IFE-owned abstract supertype for IFE init-parameter containers.
"""
abstract type AbstractIFEParametersInits{T<:Real} <: FUSE.ParametersAllInits{T} end

"""
    AbstractIFEParametersActors{T<:Real} <: FUSE.ParametersAllActors{T}

IFE-owned abstract supertype for IFE actor-parameter containers.
"""
abstract type AbstractIFEParametersActors{T<:Real} <: FUSE.ParametersAllActors{T} end
