# ParametersInits — slim IFE-flavored version of `FUSE.ParametersInits`.
#
# Only the parameter groups actually read by the IFE workflow (case_parameters,
# init!, init_costing!, IFE actors) plus the two FUSE init helpers we reuse
# (`init_balance_of_plant!`, `init_requirements!`) are kept. Magnetic-specific
# groups (equilibrium, tf, pf_active, oh, build, HCD launchers, …) are dropped
# because the IFE workflow never touches them and they only bloat
# `propertynames(ini)`, `rand(ini)`, serialization output, and reader cognition.
#
# Used by IFE workflow:
#   general       → init_from, casename
#   time          → simulation_start, pulse_shedule_time_basis (required by
#                   FUSE/SimulationParameters generic helpers — global_time,
#                   time_range, plot recipes)
#   core_profiles → ngrid
#   requirements  → tritium_breeding_ratio (and iterated by init_requirements!)
#   bop           → cycle_type (read by FUSE.init_balance_of_plant!)
#   pellet        → IFE-specific (fuel_radius, ablator_*, Te_core, rep_rate, …)
#   driver        → IFE-specific (energy, wavelength, n_drivers, efficiencies, …)
#
# To enable an additional FUSE field, add it here AND in the constructor below.
# All groups remain `FUSE.ParametersAllInits{T}` subtype-compatible.

mutable struct ParametersInits{T<:Real} <: AbstractParametersInits{T}
    _parent::WeakRef
    _name::Symbol
    # FUSE.ParametersInits groups that IFE actually uses
    general::FUSE.FUSEparameters__general{T}
    # `time` is required by FUSE/SimulationParameters' generic helpers
    # (`global_time(::ParametersAllInits)`, `time_range(...)`, plot recipes
    # via `plot_par(par; time0=global_time(par))`). Keeping the field here
    # avoids piracy on SimulationParameters' methods.
    time::FUSE.FUSEparameters__time{T}
    core_profiles::FUSE.FUSEparameters__core_profiles{T}
    bop::FUSE.FUSEparameters__balance_of_plant{T}
    requirements::FUSE.FUSEparameters__requirements{T}
    # IFE-specific groups. Field names are slim (`ini.pellet`, `ini.driver`)
    # since the container is already IFE-flavored. The underlying types keep
    # the `__IFE__` sub-namespace marker for grep/debug clarity.
    pellet::FUSEparameters__pellet{T}
    driver::FUSEparameters__driver{T}
end

function ParametersInits{T}() where {T<:Real}
    ini = ParametersInits{T}(
        WeakRef(nothing),
        :ini,
        FUSE.FUSEparameters__general{T}(),
        FUSE.FUSEparameters__time{T}(),
        FUSE.FUSEparameters__core_profiles{T}(),
        FUSE.FUSEparameters__balance_of_plant{T}(),
        FUSE.FUSEparameters__requirements{T}(),
        FUSEparameters__pellet{T}(),
        FUSEparameters__driver{T}(),
    )
    FUSE.setup_parameters!(ini)
    return ini
end

ParametersInits() = ParametersInits{Float64}()
