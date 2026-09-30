# TrickeyGain — Trickey et al. (2024) laser-direct-drive gain scalings.
#
# Ported verbatim from the FUSE `ife` branch (src/actors/transport/ife_transport_actor.jl,
# commit e534f56b4). Used by `ActorTransport`.

"""
TrickeyGain

Julia implementation of the laser-direct-drive gain scaling model of

    W. Trickey, V. N. Goncharov, R. Betti, E. M. Campbell, T. J. B. Collins,
    and R. K. Follett, "The physics of gain relevant to inertial fusion
    energy target designs," Phys. Plasmas 31, 012702 (2024).
    https://doi.org/10.1063/5.0167405

The model is a set of power-law scaling relations fitted to a database of
1D LILAC implosions (351 nm, DT-wetted-foam capsules, no CBET, with
optional one- or two-stage focal-spot zooming).

Throughout, the paper's unit convention is used internally:
    energy E_laser      [MJ]
    ablation pressure   [100 Mbar]
    intensity I         [1e15 W/cm^2]
    velocity v_imp      [300 km/s]
    mass                [mg]
Public inputs/outputs use plain lab units (MJ, Mbar, W/cm^2, km/s, mg, um).

Key equations implemented (numbers refer to the paper):
    (14)-(16) ablation pressure vs incident intensity (zoom options)
    (28)      tau parameter:        tau = 48.1 v^2.43 / (p_a^0.275 alpha^0.46)
    (13)      unablated fuel mass:  M_f = 0.678 E p_a^0.42 / (I_out v^1.21) alpha^0.18
    (21)      areal density:        rhoR = 1.85 E^0.33 p_a^0.41 I_out^-0.33 v^0.16 alpha^-0.55
    (30)      minimum (ignition-threshold) implosion velocity
    (35)      IFAR = 30.7 p_a^-0.51 alpha^-0.78 v^2.90
    (1)       gain G = f_burn * eps_DT * M_f / E_laser,  f_burn = rhoR/(rhoR + H_B)
    (3),(10),(11) geometry: relate pellet radius, laser energy, and intensity
"""
module TrickeyGain

export IFEDesign, design, design_from_intensity, ablation_pressure

const EPS_DT  = 271.0   # MJ/mg, DT fusion neutron specific energy (271 TJ/kg)
const H_B     = 6.67    # g/cm^2, burnup parameter, f_burn = rhoR/(rhoR + H_B)
const RHO_AVG = 0.277   # g/cm^3, average in-flight shell density (Sec. IV A)

# --- Ablation pressure vs incident (outer-surface) intensity, Eqs. (14)-(16) ---
# I15 in 1e15 W/cm^2, returns Mbar. :cbet is the legacy scaling with
# cross-beam energy transfer included (Ref. 41 in the paper), for comparison.
function ablation_pressure(I15; zoom::Symbol = :two_stage)
    zoom === :none      && return 238.0 * I15^0.72
    zoom === :one_stage && return 328.0 * I15^0.75
    zoom === :two_stage && return 371.0 * I15^0.75
    zoom === :cbet      && return  82.0 * I15^0.57
    throw(ArgumentError("zoom must be :none, :one_stage, :two_stage, or :cbet"))
end

# --- Internal scalings in paper units (E [MJ], pa [100 Mbar], I [1e15 W/cm^2],
#     v [300 km/s], M [mg]) ---

# Eq. (28): ratio of acceleration time to shell sound-transit time
tau_param(v, pa, alpha) = 48.1 * v^2.43 / (pa^0.275 * alpha^0.46)

# Eq. (13): unablated fuel mass [mg]
fuel_mass(E, pa, Iout, v, alpha) = 0.678 * E * pa^0.42 / (Iout * v^1.21) * alpha^0.18

# Eq. (21): peak fuel areal density [g/cm^2]
areal_density(E, pa, Iout, v, alpha) =
    1.85 * E^0.33 * pa^0.41 * Iout^-0.33 * v^0.16 * alpha^-0.55

# Eq. (35): in-flight aspect ratio
ifar(pa, v, alpha) = 30.7 * pa^-0.51 * alpha^-0.78 * v^2.90

# Eq. (11): ratio of inner-surface to outer-surface intensity, I0/Iout
intensity_ratio(pa, v, alpha) = (1 + 0.623 * pa^1.11 / (v^2.90 * alpha^0.18))^(2 / 3)

# Eq. (30): minimum implosion velocity for ignition [300 km/s units].
# tau depends on v, so solve the fixed point by iteration.
function v_min_ignition(E, pa, Iout, alpha)
    base = 0.887 * (alpha^(12 / 5) * Iout / (pa^(7 / 5) * E))^(1 / 9)
    v = base
    for _ in 1:100
        vnew = base * (1.20 + 0.042 * tau_param(v, pa, alpha))^(4 / 15)
        abs(vnew - v) < 1e-10 && return vnew
        v = vnew
    end
    return v
end

# Eq. (3) with I0 = P_laser/(4*pi*R0^2): 4*pi*R0^3 * I0 = E_laser * v_imp.
# Inner radius R0 [m] from paper-unit inputs.
inner_radius_m(E, v, I0) = ((E * 1e6) * (v * 3e5) / (4pi * I0 * 1e19))^(1 / 3)

"""
Result of a Trickey et al. design-point evaluation. All fields in lab units.
"""
struct IFEDesign
    E_laser::Float64   # MJ
    alpha::Float64     # fuel adiabat
    zoom::Symbol
    R_out::Float64     # um, initial pellet outer radius
    R_0::Float64       # um, initial shell inner radius (Eq. 3 estimate)
    I_out::Float64     # W/cm^2, peak intensity at initial outer surface
    p_a::Float64       # Mbar, ablation pressure
    v_imp::Float64     # km/s, implosion velocity used
    v_min::Float64     # km/s, ignition-threshold velocity (Eq. 30)
    tau::Float64       # acceleration/sound-transit time ratio (Eq. 28)
    M_0::Float64       # mg, initial shell mass (Eq. 9)
    M_f::Float64       # mg, unablated fuel mass (Eq. 13)
    rhoR::Float64      # g/cm^2, peak fuel areal density (Eq. 21)
    f_burn::Float64    # burnup fraction
    IFAR::Float64      # in-flight aspect ratio (Eq. 35)
    gain::Float64      # target gain (Eq. 1)
end

function Base.show(io::IO, ::MIME"text/plain", d::IFEDesign)
    println(io, "Trickey et al. (2024) IFE design point")
    println(io, "  inputs:  E_laser = $(round(d.E_laser, digits = 3)) MJ, ",
        "adiabat = $(round(d.alpha, digits = 2)), zoom = $(d.zoom)")
    println(io, "  pellet:  R_out = $(round(d.R_out, digits = 0)) um, ",
        "R_0 = $(round(d.R_0, digits = 0)) um, M_0 = $(round(d.M_0, digits = 2)) mg")
    println(io, "  drive:   I_out = $(round(d.I_out / 1e15, digits = 3))e15 W/cm^2, ",
        "p_a = $(round(d.p_a, digits = 0)) Mbar")
    println(io, "  shell:   v_imp = $(round(d.v_imp, digits = 0)) km/s ",
        "(v_min = $(round(d.v_min, digits = 0))), tau = $(round(d.tau, digits = 1)), ",
        "IFAR = $(round(d.IFAR, digits = 1))")
    println(io, "  fuel:    M_f = $(round(d.M_f, digits = 2)) mg, ",
        "rhoR = $(round(d.rhoR, digits = 2)) g/cm^2, ",
        "f_burn = $(round(d.f_burn, digits = 3))")
    print(io,   "  gain:    G = $(round(d.gain, digits = 1))")
end

"""
    design_from_intensity(E_laser, alpha, I_out; zoom = :two_stage, v_imp = nothing)

Evaluate the model with intensity as the drive input, as in the paper's
design-space scans (Figs. 9 and 10).

  - `E_laser` [MJ], `alpha` (fuel adiabat, ~1-7), `I_out` [W/cm^2]
  - `zoom`: `:none`, `:one_stage`, `:two_stage`, or `:cbet`
  - `v_imp` [km/s]: implosion velocity; defaults to the ignition-threshold
    minimum velocity of Eq. (30), the paper's design philosophy for
    maximizing fuel mass and gain.
"""
function design_from_intensity(E_laser, alpha, I_out;
        zoom::Symbol = :two_stage, v_imp = nothing, warn::Bool = true)
    E = float(E_laser)
    I15 = I_out / 1e15
    pa = ablation_pressure(I15; zoom) / 100      # -> 100 Mbar units

    warn && !(0.3 <= I15 <= 3.5) &&
        @warn "intensity outside the ~0.5-3e15 W/cm^2 range of the simulation database; fits are extrapolating" I_out
    vmin = v_min_ignition(E, pa, I15, alpha)
    v = v_imp === nothing ? vmin : v_imp / 300
    warn && v < vmin && @warn "v_imp below ignition-threshold velocity" v_imp = v * 300 v_min = vmin * 300

    t   = tau_param(v, pa, alpha)
    Mf  = fuel_mass(E, pa, I15, v, alpha)
    rR  = areal_density(E, pa, I15, v, alpha)
    fb  = rR / (rR + H_B)
    G   = fb * EPS_DT * Mf / E

    # Geometry: inner radius from Eq. (3), outer radius from Eq. (11),
    # initial mass from Eq. (9)
    ratio = intensity_ratio(pa, v, alpha)        # I0/Iout = (Rout/R0)^2
    R0_m = inner_radius_m(E, v, I15 * ratio)
    Rout_m = R0_m * sqrt(ratio)
    M0 = 4pi / 3 * RHO_AVG * ((Rout_m * 100)^3 - (R0_m * 100)^3) * 1e3   # g/cm^3 * cm^3 -> mg

    warn && Mf > M0 && @warn "unablated mass exceeds initial shell mass; scaling laws are outside their fitted range" M_f = Mf M_0 = M0

    return IFEDesign(E, alpha, zoom, Rout_m * 1e6, R0_m * 1e6, I_out, pa * 100,
        v * 300, vmin * 300, t, M0, Mf, rR, fb, ifar(pa, v, alpha), G)
end

"""
    design(E_laser, alpha, R_out; zoom = :two_stage, v_imp = nothing)

Evaluate the model with the pellet size as the drive input.

  - `E_laser` [MJ], `alpha` (fuel adiabat), `R_out` [um] initial outer radius
  - `zoom`, `v_imp`: as in [`design_from_intensity`](@ref)

The on-target intensity is found by bisection so that the pellet radius
implied by the geometry relations [Eqs. (3) and (11)] matches `R_out`:
bigger pellets intercept the laser at lower intensity. The database spans
inner radii of 750-1350 um and intensities of ~0.5-3e15 W/cm^2; results
far outside that range extrapolate the fits.
"""
function design(E_laser, alpha, R_out; zoom::Symbol = :two_stage, v_imp = nothing)
    target = float(R_out)
    radius(I15) = design_from_intensity(E_laser, alpha, I15 * 1e15;
        zoom, v_imp, warn = false).R_out

    lo, hi = 0.01, 50.0   # 1e15 W/cm^2; R_out is monotonically decreasing in I
    radius(lo) < target && throw(ArgumentError(
        "pellet radius $(target) um too large for $(E_laser) MJ (intensity below $(lo)e15 W/cm^2)"))
    radius(hi) > target && throw(ArgumentError(
        "pellet radius $(target) um too small for $(E_laser) MJ (intensity above $(hi)e15 W/cm^2)"))
    for _ in 1:200
        mid = sqrt(lo * hi)
        radius(mid) > target ? (lo = mid) : (hi = mid)
        hi / lo - 1 < 1e-12 && break
    end
    return design_from_intensity(E_laser, alpha, sqrt(lo * hi) * 1e15; zoom, v_imp)
end

end # module
