# =============================================================================
# IFE pellet-size database scan using FUSE's `StudyDatabaseGenerator`.
#
# Pure-Julia equivalent of FuseExamples/study_database_generator.ipynb,
# adapted for the IFE workflow (IFEdd.dd + IFE actors).
#
# Run from any environment that has FUSE, IFE, IFEdd, IMAS, IMASdd dev'd:
#   julia --project=/Users/yoo/.julia/dev/IFE examples/study_pellet_scan.jl
#
# What this demonstrates
#   1. `FUSE.case_parameters(:IFE)` returns an ParametersInits / Actors pair
#   2. The same `↔` distribution syntax FUSE uses for ITER scans works on
#      IFE-specific parameters (pellet, driver) — they're FUSE
#      ParametersInit subtypes and `rand(ini)` handles them generically
#   3. `FUSE.StudyDatabaseGenerator{T, D<:IMAS.DD}` is parameterized on the
#      DD subtype. Passing `dd_type=IFEdd.dd` to the outer constructor
#      tells `run_case` to build a `IFEdd.dd()` (instead of the default
#      `IMAS.dd()`) before invoking the workflow.
#   4. A user-provided workflow function plugs in the IFE actor sequence.
#   5. FUSE's own save mechanism writes the full `IFEdd.dd` to `database.h5`
#      per case, and `IMAS.extract(dd, :all)` populates `study.dataframe`
#      with the IFE-relevant scalar columns (Pfusion, TBR, cost_lifetime,
#      levelized_CoE, …). No sidecar JSON needed.
#
# Outputs
#   study.dataframe          — N rows × ~140 cols (one row per case). Most
#                              cols are magnetic-specific (NaN for IFE);
#                              the IFE-relevant cols include Pfusion,
#                              neutrons_peak, TBR, capital_cost,
#                              levelized_CoE, thermal_cycle_type, …
#   <save_folder>/database.h5 — full IFEdd.dd + ini + act per case (HDF5).
#                              Load a case via
#                              `dd, ini, act = FUSE.load(joinpath(save_folder, "case1"))`.
#   <save_folder>/extract.csv — CSV mirror of study.dataframe (cross-session).
# =============================================================================

using Distributed
addprocs(Threads.nthreads())

# Single-process by default; users can `addprocs(4)` for parallel.
# All `@everywhere` blocks below are no-ops on the main process when no
# workers are added, but still let the same script scale up unchanged.

@everywhere begin
    using FUSE
    using IFE
    using IFEdd
    using IMAS
    using IMASdd

    # Reuse FUSE's transitive deps so this script needs no extra packages
    # in the IFE environment. Same idiom the FuseExamples notebooks use.
    const DataFrame = FUSE.DataFrames.DataFrame
    const nrow = FUSE.DataFrames.nrow
    const ncol = FUSE.DataFrames.ncol

    import FUSE: ProgressMeter
    using Logging: Info, Error
    using FUSE.SimulationParameters.Distributions
end

FUSE.logging(Info; actors=Error)

# -----------------------------------------------------------------------------
# 1. IFE case + scan distributions
# -----------------------------------------------------------------------------
# The IFE case sets sensible defaults for pellet, driver, requirements.
ini, act = FUSE.case_parameters(:IFE)

# Add scan distributions using FUSE's `↔` operator.
#   `value ↔ [low, high]`         — uniform distribution
#   `value ↔ truncated(Normal(...))` — Gaussian (requires Distributions.jl)
#   `value ↔ (option_a, option_b)` — categorical
#
# These syntactic forms come from FUSE's SimulationParameters and work on any
# `Entry{T}` field — they don't care whether the parameter group is magnetic
# (ini.equilibrium.B0) or IFE (ini.pellet.fuel_radius).
ini.pellet.ablator_thickness  = 900e-6 ↔ [700e-6, 1100e-6]  # m
ini.pellet.hotspot_fraction   = 0.30   ↔ [0.20, 0.40]

ini.driver.energy = 1.8e6  ↔ truncated(Normal(1.8e6,0.4e6),lower=1e6, upper=2.5e6)

thin_fuel_r = truncated(Normal(60e-6,10e-6), lower=40e-6, upper=80e-6)
thick_fuel_r = truncated(Normal(140e-6, 20e-6), lower=100e-6, upper=200e-6)
thin_fuel_portion = 0.3
thick_fuel_portion = 0.7
mixed_two_Normals =  MixtureModel([thin_fuel_r, thick_fuel_r], [thin_fuel_portion, thick_fuel_portion])

ini.pellet.fuel_radius        = 100e-6 ↔ mixed_two_Normals   # m   (target radius)


# -----------------------------------------------------------------------------
# 2. Sanity check — run one sampled case before launching the study
# -----------------------------------------------------------------------------
function _single_case_demo(ini, act)
    ini_test = rand(ini)
    dd = IFEdd.dd()
    IFE.init!(dd, ini_test, act)
    IFE.ActorTransport(dd, act)
    IFE.ActorBlanket(dd, act)
    FUSE.ActorPowerNeeds(dd, act)
    IFE.ActorCosting(dd, act)
    @info "Single test case" fuel_radius=ini_test.pellet.fuel_radius driver_energy=ini_test.driver.energy cost_lifetime_GUSD=round(dd.costing.cost_lifetime/1e3; digits=2) CoE=round(dd.costing.levelized_CoE; digits=4)
    return dd
end
# Pre-flight sanity check: run ONE sampled case through the same actor sequence
# the study workflow will execute, to catch errors early (5s vs the full study
# wall-clock). Mirrors `dd = IMAS.dd(); ini_test = rand(ini); FUSE.init(...);
# FUSE.digest(dd)` from the FuseExamples notebook. dd is discarded — this only
# verifies that the pipeline survives one random sample of `ini`.
_single_case_demo(ini, act)

# -----------------------------------------------------------------------------
# 3. Study parameters
# -----------------------------------------------------------------------------
sty = FUSE.study_parameters(:DatabaseGenerator)
sty.server         = "localhost"
sty.n_workers      = length(workers())   # 1 by default; addprocs(N) before running for parallel
sty.file_save_mode = :overwrite
# sty.save_folder    = mktempdir(; prefix="ife_pellet_scan_")
sty.save_folder    = "test_ife_study"
sty.save_dd        = true               # save IFEdd.dd per case
sty.n_simulations  = 100
# `:single_hdf5` merges everything into one `database.h5` (per-case dd / ini /
# act + study.dataframe + extract.csv) — convenient single-file artifact.
# Use `:separate_folders` if you want per-case directories on disk instead.
sty.database_policy = :single_hdf5

# StudyDatabaseGenerator's single-ini constructor does not call
# `check_and_create_file_save_mode` (only the Vector-ini constructor does);
# make sure the save folder exists before run_case mkdirs anything below it.
isdir(sty.save_folder) && rm(sty.save_folder; recursive=true)
mkpath(sty.save_folder)
@info "Study output folder: $(sty.save_folder)"



# -----------------------------------------------------------------------------
# 4. Workflow callback
# -----------------------------------------------------------------------------
# Because we passed `dd_type=IFEdd.dd` below, `run_case` constructs a
# real `IFEdd.dd` and hands it to us. We populate it in place; FUSE's `run_case`
# then takes care of:
#   • `IMAS.extract(dd, :all)` → one row of `study.dataframe` per case
#     (IFE-relevant scalars: Pfusion, TBR, cost_lifetime, levelized_CoE, …)
#   • `save_study_database(...)` → full `IFEdd.dd` + ini + act into `database.h5`
@everywhere function workflow_pellet_scan(
    dd::IFEdd.dd,
    ini::FUSE.ParametersAllInits,
    act::FUSE.ParametersAllActors,
)
    IFE.init!(dd, ini, act)
    IFE.ActorTransport(dd, act)
    IFE.ActorBlanket(dd, act)
    FUSE.ActorPowerNeeds(dd, act)
    IFE.ActorCosting(dd, act)
    return nothing
end

# -----------------------------------------------------------------------------
# 5. Build + run the study
# -----------------------------------------------------------------------------
study = FUSE.StudyDatabaseGenerator(sty, ini, act; dd_type=IFEdd.dd)
study.workflow = workflow_pellet_scan
@info "Study type: $(typeof(study))"

@info "Running $(sty.n_simulations) IFE pellet-scan simulations…"
FUSE.run(study)

# -----------------------------------------------------------------------------
# 6. Results — `study.dataframe`
# -----------------------------------------------------------------------------
# FUSE's run_case populated this with `IMAS.extract(dd, :all)` per case. Most
# of the ~140 columns are magnetic-specific and are NaN/missing for IFE; we
# filter to the columns that actually have data so the summary is readable.
df = study.dataframe

function relevant_columns(df)
    keep = String[]
    for c in names(df)
        vals = df[!, c]
        if any(x -> !ismissing(x) && (x isa AbstractString || x isa Symbol || !isnan(x)), vals)
            push!(keep, c)
        end
    end
    return keep
end

useful = relevant_columns(df)
@info "study.dataframe: $(nrow(df)) cases × $(ncol(df)) cols total; $(length(useful)) cols with non-NaN data"

println()
@info "IFE-relevant columns:"
show(stdout, MIME"text/plain"(), df[!, useful])
println()

# -----------------------------------------------------------------------------
# 7. Loading a single case's full IFEdd.dd from database.h5
# -----------------------------------------------------------------------------
# For deep inspection of any case beyond the scalar summary above, load the
# full container tree from HDF5:
#
#   case_path = joinpath(sty.save_folder, "database.h5", df.gparent[1])
#   dd, ini_case, act_case = FUSE.load(case_path)
#
# `dd` is the per-case `IFEdd.dd` with build, driver, blanket, costing,
# core_profiles, balance_of_plant, etc. all populated.



## Plot
using Plots

db = FUSE.load_study_database("test_ife_study/database.h5");

df = db.df;

inis = [db.items[k].ini for k in 1:length(db.items)]
acts = [db.items[k].act for k in 1:length(db.items)]
dds = [db.items[k].dd for k in 1:length(db.items)]


driver_energy = [sum(b.energy for b in item.dd.driver.beam) for item in db.items]   # J
fuel_radius   = [item.ini.pellet.fuel_radius for item in db.items]                       # m
ablator_th    = [item.ini.pellet.ablator_thickness for item in db.items]                 # m
hotspot_frac  = [item.ini.pellet.hotspot_fraction for item in db.items]                  # -

Pfusion       = db.df[:, "Pfusion"]
TBR           = db.df[:, "TBR"]
cost_lifetime = db.df[:, "capital_cost"]





plot(inis; legend=:none)


# Plot 1: drive → fusion
scatter(driver_energy ./ 1e6, Pfusion ./ 1e9;
        zcolor = fuel_radius .* 1e6,
        xlabel = "Driver energy [MJ]",
        ylabel = "P_fusion [GW]",
        colorbar_title = "Fuel radius [µm]",
        label = "")

# Plot 2: design space heatmap
scatter(fuel_radius .* 1e6, driver_energy ./ 1e6;
        zcolor = cost_lifetime,
        xlabel = "Fuel radius [µm]",
        ylabel = "Driver energy [MJ]",
        colorbar_title = "Capital cost [G\$]",
        label = "")

# Plot 3: derived gain
pulse_length = [item.ini.driver.pulse_length for item in db.items]
gain = Pfusion .* pulse_length ./ driver_energy
scatter(fuel_radius .* 1e6, gain;
        zcolor = driver_energy ./ 1e6,
        xlabel = "Fuel radius [µm]",
        ylabel = "Gain = P_fus·τ / E_drive",
        colorbar_title = "Driver energy [MJ]",
        label = "")

