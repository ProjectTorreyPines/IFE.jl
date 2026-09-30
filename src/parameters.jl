# IFE-specific init parameter groups.
#
# Type names use the `FUSEparameters__IFE__<group>` convention:
#   • `FUSEparameters__` — signals "FUSE parameter-framework subtype" (these
#     structs `<: FUSE.ParametersInit{T}` and integrate with FUSE's rand /
#     setup_parameters! / OverrideParameters machinery).
#   • `IFE__` — sub-namespace marker for the IFE module; lets a grep of
#     `IFE__` enumerate every IFE-defined parameter group, and disambiguates
#     these from FUSE's own `FUSEparameters__<group>` (general, equilibrium, …).
#   • `<group>` — the short field name as it appears in the container
#     (e.g. `ini.pellet`, `ini.driver`).
#
# The `FUSE.@insert_subtype_members` macro splits type names on `__` and takes
# the last segment, so this naming yields the right field names automatically;
# the slim container hand-lists the fields anyway.

Base.@kwdef mutable struct FUSEparameters__pellet{T} <: FUSE.ParametersInit{T}
    _parent::WeakRef = WeakRef(nothing)
    _name::Symbol = :pellet
    fuel_radius::FUSE.Entry{T} = FUSE.Entry{T}("m", "Total fuel radius (hot spot + DT ice layer)";
        default=1000e-6, check=x -> @assert x > 0.0 "must be: fuel_radius > 0.0")
    hotspot_fraction::FUSE.Entry{T} = FUSE.Entry{T}("-", "Fraction of fuel_radius occupied by the hot spot (rpellet = hotspot_fraction * fuel_radius)";
        default=0.3, check=x -> @assert 0.0 < x < 1.0 "must be: 0 < hotspot_fraction < 1")
    ablator_thickness::FUSE.Entry{T} = FUSE.Entry{T}("m", "Thickness of the outer ablator shell";
        default=400e-6, check=x -> @assert x > 0.0 "must be: ablator_thickness > 0.0")
    ablator_material::FUSE.Entry{String} = FUSE.Entry{String}("-", "Ablator material label (e.g. \"CH\", \"Be\", \"HDC\")";
        default="HDC")
    rep_rate::FUSE.Entry{T} = FUSE.Entry{T}("Hz", "Target repetition rate";
        default=10.0, check=x -> @assert x > 0.0 "must be: rep_rate > 0.0")
    Te_core::FUSE.Entry{T} = FUSE.Entry{T}("eV", "Cold initial pellet temperature";
        default=0.05, check=x -> @assert x > 0.0 "must be: Te_core > 0.0")
end

Base.@kwdef mutable struct FUSEparameters__driver{T} <: FUSE.ParametersInit{T}
    _parent::WeakRef = WeakRef(nothing)
    _name::Symbol = :driver
    n_drivers::FUSE.Entry{Int} = FUSE.Entry{Int}("-", "Number of driver beams (total energy split equally among them)";
        default=1, check=x -> @assert x >= 1 "must be: n_drivers >= 1")
    energy::FUSE.Entry{T} = FUSE.Entry{T}("J", "Total driver energy per pulse delivered to target";
        default=1.8e6, check=x -> @assert x > 0.0 "must be: energy > 0.0")
    wavelength::FUSE.Entry{T} = FUSE.Entry{T}("m", "Driver wavelength (e.g. 351e-9 for UV laser)";
        default=351e-9, check=x -> @assert x > 0.0 "must be: wavelength > 0.0")
    pulse_length::FUSE.Entry{T} = FUSE.Entry{T}("s", "Driver pulse duration";
        default=10e-9, check=x -> @assert x > 0.0 "must be: pulse_length > 0.0")
    efficiency_conversion::FUSE.Entry{T} = FUSE.Entry{T}("-", "Wall-plug to driver efficiency";
        default=0.10, check=x -> @assert 0.0 < x <= 1.0 "must be: 0.0 < efficiency_conversion <= 1.0")
    efficiency_coupling::FUSE.Entry{T} = FUSE.Entry{T}("-", "Driver to target coupling efficiency";
        default=0.85, check=x -> @assert 0.0 < x <= 1.0 "must be: 0.0 < efficiency_coupling <= 1.0")
end
