# =============================================================================
# Simple 1-parameter random scan: only `driver.energy` varies.
# Mirrors examples/study_pellet_scan.jl but with a single `↔` distribution so
# the var-vs-output correlation is unambiguous in the postprocessing plots.
# =============================================================================

using Distributed
addprocs(Threads.nthreads())

# Workers need whatever the workflow callback below names. `@everywhere` also
# runs on the main process, so this one block covers the setup and the
# postprocessing too.
@everywhere using FUSE, IFE, IFEdd

# -----------------------------------------------------------------------------
# 1. IFE case + ONE scan parameter
# -----------------------------------------------------------------------------
ini, act = FUSE.case_parameters(:IFE)

# Sweep only driver.energy. Everything else stays at defaults so the
# scatter Pfusion vs driver.energy isn't muddied by other variations.
ini.driver.energy = 1.8e6 ↔ [1.0e6, 3.0e6]    # uniform 1–3 MJ

# -----------------------------------------------------------------------------
# 2. Study setup
# -----------------------------------------------------------------------------
sty = FUSE.study_parameters(:DatabaseGenerator)
sty.server         = "localhost"
sty.n_workers      = length(workers())
sty.file_save_mode = :overwrite
sty.save_folder    = "scan_simple"
sty.save_dd        = true
sty.n_simulations  = 50
sty.database_policy = :single_hdf5

isdir(sty.save_folder) && rm(sty.save_folder; recursive=true)
mkpath(sty.save_folder)

# -----------------------------------------------------------------------------
# 3. Workflow callback (same actor sequence as the full scan example)
# -----------------------------------------------------------------------------
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
# 4. Run
# -----------------------------------------------------------------------------
study = FUSE.StudyDatabaseGenerator(sty, ini, act; dd_type=IFEdd.dd)
study.workflow = workflow_pellet_scan
FUSE.run(study)

# -----------------------------------------------------------------------------
# 5. Postprocess — pull input from saved ini (not in study.dataframe), pair
#    with Pfusion / cost output, plot correlation.
# -----------------------------------------------------------------------------
case_names = ["/case$(lpad(i, length(string(sty.n_simulations)), "0"))" for i in 1:sty.n_simulations]
db = FUSE.load_study_database(joinpath(sty.save_folder, "database.h5"), case_names;
                              ini_type=IFE.ParametersInits, act_type=IFE.ParametersActors)

E_drive  = [sum(b.energy for b in item.dd.driver.beam) for item in db.items]   # J
Pfus     = db.df[:, "Pfusion"]                                                     # W
cost_lif = db.df[:, "capital_cost"]                                                # G$

inis = [item.ini for item in db.items]

@info "Scan summary" N=length(E_drive) E_min_MJ=minimum(E_drive)/1e6 E_max_MJ=maximum(E_drive)/1e6 Pfus_min_GW=minimum(Pfus)/1e9 Pfus_max_GW=maximum(Pfus)/1e9

# -----------------------------------------------------------------------------
# 6. Plot. Loading Plots also activates IFEdd's recipe extension, so the
#    containers read back out of the database draw themselves.
# -----------------------------------------------------------------------------
using Plots

# The scan inputs: where the 50 cases landed in `ini.driver.energy`, against the
# distribution they were drawn from. The recipe is SimulationParameters' own —
# it dispatches on `AbstractParameters`, which IFE's `ParametersInits` subtypes,
# so the scan inputs plot with nothing IFE-specific involved.
inis_fig = plot(inis; each_size=(800, 500))

p1 = scatter(E_drive ./ 1e6, Pfus ./ 1e9;
             xlabel="Driver energy [MJ]", ylabel="P_fusion [GW]",
             label="", title="IFE 1-param scan")
p2 = scatter(E_drive ./ 1e6, cost_lif;
             xlabel="Driver energy [MJ]", ylabel="Capital cost [G\$]",
             label="")
scan_fig = plot(p1, p2; layout=(1,2), size=(900, 350))

# `item.dd` is a full `IFEdd.dd` rebuilt from HDF5, so the IFE-owned IDS plot
# exactly as they do before saving — the round trip, end to end.
weakest, strongest = argmin(E_drive), argmax(E_drive)
case_fig = plot(plot(db.items[weakest].dd; title="Lowest drive energy"),
                plot(db.items[strongest].dd; title="Highest drive energy");
                layout=(1, 2), size=(1100, 450))

savefig(inis_fig, joinpath(sty.save_folder, "scan_inputs.png"))
savefig(scan_fig, joinpath(sty.save_folder, "scan_summary.png"))
savefig(case_fig, joinpath(sty.save_folder, "chamber_extremes.png"))
@info "wrote figures" folder = sty.save_folder
