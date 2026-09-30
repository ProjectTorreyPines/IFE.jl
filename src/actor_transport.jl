# ActorTransport — 0-D IFE transport (Trickey et al. 2024 gain model).
#
# Ported from joey_fork/FUSE.jl/src/actors/transport/ife_transport_actor.jl,
# synced with the FUSE `ife` branch through commit e534f56b4. Sole adaptation: signature dispatches on `IFEdd.dd` instead of `IMAS.dd`.
# The `IFEdd.dd` container embeds `core_profiles`, `core_sources`, `pellets`,
# and the IFE-specific `driver` — all that this actor reads/writes.

FUSE.@actor_parameters_struct ActorTransport{T} begin
    adiabat::FUSE.Entry{T} = FUSE.Entry{T}("-", "Adiabat of the compressed shell"; default=2.5)
    zoom::FUSE.Switch{Symbol} = FUSE.Switch{Symbol}([:none, :one_stage, :two_stage, :cbet], "-", "Focal-spot zooming option for ablation-pressure scaling"; default=:none)
    verbose::FUSE.Entry{Bool} = FUSE.act_common_parameters(; verbose=false)
end

mutable struct ActorTransport{D,P} <: FUSE.SingleAbstractActor{D,P}
    dd::IFEdd.dd{D}
    par::FUSE.OverrideParameters{P,FUSEparameters__ActorTransport{P}}
    function ActorTransport(dd::IFEdd.dd{D}, par::FUSEparameters__ActorTransport{P}; kw...) where {D<:Real,P<:Real}
        FUSE.logging_actor_init(ActorTransport)
        par = FUSE.OverrideParameters(par; kw...)
        return new{D,P}(dd, par)
    end
end

"""
    ActorTransport(dd::IFEdd.dd, act::AbstractParametersActors; kw...)

Fills `dd.core_profiles` with a time history that mirrors the `dd.driver`
pulse trace: slices where any beam has `power_launched > 0` receive hot
compressed profiles, the rest receive the cold initial profiles.

The 0-D gain model is the `TrickeyGain` module (Trickey et al., Phys. Plasmas 31,
012702, 2024): `TrickeyGain.design(E_laser, adiabat, R_pellet)` bisects for the
on-target intensity consistent with the pellet radius, evaluates the paper's
scaling laws at the ignition-threshold implosion velocity (Eq. 30), and returns
gain, areal density, burn fraction, unablated fuel mass, and IFAR. Derived target
physics is written to `dd.summary.target`.

Each beam's `pulse_length` is overwritten with the model-implied drive duration
`τ = R₀ / v_imp` (Eq. 3); the `power_launched` traces are left untouched so they
keep integrating to the beam energy on the driver time grid.

The hot temperature scale is found once via bisection so that the per-shot fusion
energy — the hot-slice fusion power integrated over the pulse trace's on-window —
equals the model yield `G × E_laser`. This makes the cycle-averaged fusion power
seen by downstream actors exact regardless of the time-grid resolution. If the
yield is unreachable via temperature scaling of the compressed profiles, the actor
errors rather than silently capping.

Stores data in `dd.core_profiles`, `dd.core_sources`, `dd.summary` and `dd.driver`.
"""
function ActorTransport(dd::IFEdd.dd, act::AbstractParametersActors; kw...)
    actor = ActorTransport(dd, act.ActorTransport; kw...)
    FUSE.step(actor)
    FUSE.finalize(actor)
    return actor
end

function FUSE._step(actor::ActorTransport)
    dd = actor.dd
    par = actor.par

    # --- read driver inputs ---
    isempty(dd.driver.beam) && return actor
    beam = dd.driver.beam[1]
    (IMASdd.ismissing(beam, :energy) || IMASdd.ismissing(beam, :pulse_length)) && return actor
    E_laser = sum(b.energy for b in dd.driver.beam)  # total J per shot (all beams)

    # --- read target radius ---
    isempty(dd.pellets.launcher) && return actor
    launcher = dd.pellets.launcher[1]
    (IMASdd.ismissing(launcher.shape, :size) || isempty(launcher.shape.size)) && return actor
    R = launcher.shape.size[1]  # m

    # --- 0-D gain model (Trickey et al. 2024) ---
    d = TrickeyGain.design(E_laser / 1e6, par.adiabat, R * 1e6; zoom=par.zoom)

    I_SI     = d.I_out * 1e4    # W/cm² → W/m²
    P_abl    = d.p_a * 1e11     # Mbar  → Pa
    v_imp    = d.v_imp * 1e3    # km/s  → m/s
    rhoR_SI  = d.rhoR * 10.0    # g/cm² → kg/m²
    m_fuel   = d.M_f * 1e-6     # mg    → kg
    fb       = d.f_burn
    G        = d.gain

    # --- enforce pulse length consistent with the gain model ---
    # Eq. 3 (4π R0³ I0 = E_laser v_imp) implies a drive duration τ = R0 / v_imp:
    # the time the laser delivers E_laser at the intensity the model was evaluated at.
    # power_launched is left untouched: the trace integrates to the beam energy on
    # the driver time grid, which is what downstream cycle-averaging sees.
    tau = (d.R_0 * 1e-6) / v_imp    # s
    for b in dd.driver.beam
        b.pulse_length = tau
    end

    # --- per-shot fusion energy target ---
    # Match energy, not instantaneous power: downstream actors (e.g. ActorBlanket)
    # cycle-average the fusion power by trapezoidal integration over the time grid,
    # so the hot-slice power must spread the model yield G·E_laser over the trace's
    # on-window for the per-shot fusion energy to come out exactly G·E_laser.
    driver_times = dd.driver.time
    laser_on = [sum(b.power_launched[i] for b in dd.driver.beam) > 0 ? 1.0 : 0.0 for i in eachindex(driver_times)]
    dt_hot = FUSE.trapz(driver_times, laser_on)   # s, effective on-window of the pulse trace
    dt_hot > 0.0 || return actor                  # no laser power at any time point
    P_fus_target = G * E_laser / dt_hot           # W on hot slices → ∫P_fus dt = G·E_laser per shot

    # --- ensure core_profiles has a slice for every driver time point ---
    for t in driver_times
        if !(t in dd.core_profiles.time)
            IMAS.new_timeslice!(dd.core_profiles, t)
            IMAS.new_timeslice!(dd.core_sources, t)
        end
    end

    # --- cold base profiles from the first (initial) time slice ---
    # Copy before bisection can overwrite any slice.
    cp1d_init  = dd.core_profiles.profiles_1d[dd.core_profiles.time[1]]
    Te_cold    = copy(cp1d_init.electrons.temperature)
    Ti_cold    = [copy(ion.temperature) for ion in cp1d_init.ion]
    ne_cold    = copy(cp1d_init.electrons.density_thermal)
    ni_cold    = [copy(ion.density_thermal) for ion in cp1d_init.ion]
    V_cold     = copy(cp1d_init.grid.volume)
    A_cold     = copy(cp1d_init.grid.area)

    # --- compressed fuel sphere radius from areal density + mass conservation ---
    # rho_c * R_c = rhoR  and  m_fuel = rho_c * (4π/3) * R_c^3
    # → R_c = sqrt(3 * m_fuel / (4π * rhoR_SI))
    # m_fuel is the model's unablated fuel mass (Eq. 13), self-consistent with rhoR.
    R_c = sqrt(3.0 * m_fuel / (4π * rhoR_SI))
    isfinite(R_c) && R_c > 0 || (R_c = R)  # fallback: no compression
    rho_tor = cp1d_init.grid.rho_tor_norm
    V_hot = @. (4π / 3) * (rho_tor * R_c)^3
    A_hot = @. 4π * (rho_tor * R_c)^2

    # Density scales with the compression ratio (particle conservation)
    density_scale = V_cold[end] / V_hot[end]   # = (R_uncompressed / R_c)^3
    ne_hot = ne_cold .* density_scale
    ni_hot = [ni_cold[k] .* density_scale for k in eachindex(ni_cold)]

    # --- bisect on the first laser-on slice to find the hot temperature scale ---
    i_on = findfirst(i -> sum(b.power_launched[i] for b in dd.driver.beam) > 0,
                     eachindex(driver_times))
    isnothing(i_on) && return actor   # no laser power at any time point

    t_on = driver_times[i_on]
    dd.global_time = t_on
    cp1d_work = dd.core_profiles.profiles_1d[t_on]

    # Pre-set compressed geometry and density so the bisection sees the hot-state density.
    cp1d_work.electrons.density_thermal = ne_hot
    cp1d_work.grid.volume = V_hot
    cp1d_work.grid.area   = A_hot
    for (k, ion) in enumerate(cp1d_work.ion)
        ion.density_thermal = ni_hot[k]
    end

    function set_scale!(α)
        cp1d_work.electrons.temperature = Te_cold .* α
        for (k, ion) in enumerate(cp1d_work.ion)
            ion.temperature = Ti_cold[k] .* α
        end
    end

    function P_fus_at_scale(α)
        set_scale!(α)
        IMAS.fusion_source!(dd.core_sources, dd.core_profiles)
        return IMAS.fusion_power(dd)
    end

    # bracket: expand upper bound until fusion power exceeds target or overflows
    α_lo, α_hi = 0.0, 1.0
    P_hi = P_fus_at_scale(α_hi)
    P_hi_prev = P_hi
    for _ in 1:200
        P_hi >= P_fus_target && break
        α_hi *= 2.0
        P_hi = P_fus_at_scale(α_hi)
        # stop if power is NaN or started decreasing (past <σv> peak)
        (isnan(P_hi) || P_hi < P_hi_prev) && (α_hi /= 2.0; P_hi = P_hi_prev; break)
        P_hi_prev = P_hi
    end
    if P_hi < P_fus_target
        error("ActorTransport: target fusion power $(round(P_fus_target/1e12; digits=2)) TW " *
              "(yield G·E = $(round(G * E_laser / 1e6; digits=2)) MJ over $(round(dt_hot*1e9; digits=2)) ns) " *
              "is unreachable via temperature scaling of the compressed profiles " *
              "(max achievable: $(round(P_hi/1e12; digits=3)) TW). " *
              "The design point cannot be represented in core_profiles; revisit target/driver parameters.")
    end
    # bisect to rtol ~ 1e-6
    for _ in 1:60
        α_mid = (α_lo + α_hi) / 2
        (α_hi - α_lo) / α_hi < 1e-6 && break
        P_fus_at_scale(α_mid) < P_fus_target ? (α_lo = α_mid) : (α_hi = α_mid)
    end
    α_final = (α_lo + α_hi) / 2
    Te_hot = Te_cold .* α_final
    Ti_hot = [Ti_cold[k] .* α_final for k in eachindex(Ti_cold)]

    # --- write derived target physics to dd.summary.target ---
    tgt = dd.summary.target
    tgt.intensity          = I_SI
    tgt.ablation_pressure  = P_abl
    tgt.implosion_velocity = v_imp
    tgt.areal_density      = rhoR_SI
    tgt.burn_fraction      = fb
    tgt.gain               = G
    tgt.compressed_radius  = R_c
    tgt.ifar               = d.IFAR
    tgt.convergence_ratio  = R / R_c
    tgt.temperature_scale  = α_final

    # --- fill every time slice: hot when laser is on, cold otherwise ---
    t_last_on = t_on
    for (i, t) in enumerate(driver_times)
        P_laser = sum(b.power_launched[i] for b in dd.driver.beam)
        dd.global_time = t
        cp1d = dd.core_profiles.profiles_1d[t]
        if P_laser > 0
            cp1d.electrons.temperature    = Te_hot
            cp1d.electrons.density_thermal = ne_hot
            for (k, ion) in enumerate(cp1d.ion)
                ion.temperature    = Ti_hot[k]
                ion.density_thermal = ni_hot[k]
            end
            cp1d.grid.volume = V_hot
            cp1d.grid.area   = A_hot
            t_last_on = t
        else
            cp1d.electrons.temperature    = Te_cold
            cp1d.electrons.density_thermal = ne_cold
            for (k, ion) in enumerate(cp1d.ion)
                ion.temperature    = Ti_cold[k]
                ion.density_thermal = ni_cold[k]
            end
            cp1d.grid.volume = V_cold
            cp1d.grid.area   = A_cold
        end
        IMAS.fusion_source!(dd.core_sources, dd.core_profiles)
    end

    # Leave global_time at the last laser-on slice (hot state)
    dd.global_time = t_last_on

    if par.verbose
        P_fus_final = IMAS.fusion_power(dd)
        @info "ActorTransport: I=$(round(d.I_out/1e15; digits=2))×10¹⁵ W/cm², pa=$(round(d.p_a; digits=1)) Mbar, v=$(round(d.v_imp; digits=0)) km/s (v_min=$(round(d.v_min; digits=0))), τ_pulse=$(round(tau*1e9; digits=2)) ns, τ=$(round(d.tau; digits=1)), IFAR=$(round(d.IFAR; digits=1)), M_f=$(round(d.M_f; digits=2)) mg, ρR=$(round(d.rhoR; digits=2)) g/cm², fb=$(round(fb; digits=3)), G=$(round(G; digits=1)), yield=$(round(G * E_laser / 1e6; digits=1)) MJ over $(round(dt_hot*1e9; digits=2)) ns, T_scale=$(round(α_final; digits=4)), P_fus=$(round(P_fus_final/1e12; digits=2)) TW"
    end

    return actor
end
