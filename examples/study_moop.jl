# =============================================================================
# IFE multi-objective optimization using FUSE's `StudyMultiObjectiveOptimizer`.
#
# Trades net electric power against levelized cost of electricity over the
# driver and pellet design space, with a floor on net electric power.
#
# Unlike `StudyDatabaseGenerator`, the optimizer has no `dd_type` option: the
# workflow builds the container itself and returns it, so it builds an
# `IFEdd.dd`. FUSE's optimization engine then evaluates the objectives and
# constraints on it and records `IMAS.extract(dd, :all)` per case, which IFE
# extends for `IFEdd.dd`: IFE's metric set plus the objectives and constraints.
# =============================================================================

using FUSE, IFE, IFEdd
using Logging: Info, Error
FUSE.logging(Info; actors=Error)

# -----------------------------------------------------------------------------
# 1. Baseline IFE design point
# -----------------------------------------------------------------------------
ini, act = FUSE.case_parameters(:IFE)

ini.general.casename = "IFE-MOOP"
ini.general.description = "IFE multi-objective optimization"

# --- Driver ---
ini.driver.n_drivers = 16
ini.driver.energy = 2e6                 # [J] (2 MJ)
ini.driver.efficiency_conversion = 0.1
ini.driver.pulse_length = 3e-8          # [s] (30 ns)

# --- Pellet / target ---
ini.pellet.rep_rate = 10.0              # [Hz]
ini.pellet.ablator_thickness = 5e-4     # [m]
ini.pellet.fuel_radius = 500e-6         # [m]

# --- Balance of plant / requirements ---
ini.bop.cycle_type = :rankine
ini.requirements.tritium_breeding_ratio = 1.1
ini.requirements.power_electric_net = 100e6 # [W] floor used by the min_power_electric_net constraint

# IFE.ActorCosting is IFE's own costing group, so there is no `model` switch to
# set and no separate `ActorCostingIFE` group.
act.ActorCosting.cost_per_pellet = :GA

# -----------------------------------------------------------------------------
# 2. Optimization parameters (design space)
# -----------------------------------------------------------------------------
# Each `x ↔ [lo, hi]` marks an input to be varied by the optimizer.
# These knobs drive fusion yield (→ net electric power) and the
# driver/target cost (→ levelized CoE), giving a real trade-off.
ini.driver.energy                = ini.driver.energy                ↔ [1.0e6, 4.0e6]    # [J]
ini.driver.efficiency_conversion = ini.driver.efficiency_conversion ↔ [0.05, 0.20]
ini.pellet.rep_rate              = ini.pellet.rep_rate              ↔ [5.0, 20.0]       # [Hz]
ini.pellet.fuel_radius           = ini.pellet.fuel_radius           ↔ [300e-6, 800e-6]  # [m]
ini.pellet.ablator_thickness     = ini.pellet.ablator_thickness     ↔ [3e-4, 8e-4]      # [m]

# -----------------------------------------------------------------------------
# 3. Objective & constraint functions
# -----------------------------------------------------------------------------
FUSE.IMAS.update_ObjectiveFunctionsLibrary!()
FUSE.IMAS.update_ConstraintFunctionsLibrary!()

OFL = deepcopy(FUSE.IMAS.ObjectiveFunctionsLibrary)
CFL = deepcopy(FUSE.IMAS.ConstraintFunctionsLibrary)

# Canonical reactor trade-off: more net electricity vs. cheaper electricity.
objective_functions = [
    OFL[:max_power_electric_net],   # dd.balance_of_plant.power_electric_net
    OFL[:min_levelized_CoE],        # dd.costing.levelized_CoE
]

# Require a minimum net electric power (uses ini.requirements.power_electric_net).
constraint_functions = [
    CFL[:min_power_electric_net],
]

println("== OBJECTIVE FUNCTIONS ==")
display(objective_functions)
println()
println("== CONSTRAINT FUNCTIONS ==")
display(constraint_functions)
println()

# -----------------------------------------------------------------------------
# 4. Study setup
# -----------------------------------------------------------------------------
sty = FUSE.study_parameters(:MultiObjectiveOptimizer)

# IFE runs are fast, so this is comfortable to run locally.
# Switch to your cluster (e.g. "omega"/"saga") and bump n_workers for big runs.
sty.server = "localhost"
sty.n_workers = 8

sty.save_folder = mkpath(joinpath(pwd(), "ife_moop_run"))

sty.restart_workers_after_n_generations = 0  # default: release workers when the study finishes

sty.population_size = 20
sty.number_of_generations = 10
# For a realistic study use population_size ~ 200-300 and number_of_generations ~ 100.

# The constructor starts the `sty.n_workers` workers.
study = FUSE.StudyMultiObjectiveOptimizer(sty, ini, act, constraint_functions, objective_functions)

# -----------------------------------------------------------------------------
# 5. Per-point workflow: run the IFE actor chain and return dd
# -----------------------------------------------------------------------------
# Workers need whatever the workflow names, so load the packages on them now
# that they exist.
using Distributed
@everywhere using FUSE, IFE, IFEdd

@everywhere function optimization_workflow(ini::FUSE.ParametersAllInits, act::FUSE.ParametersAllActors)
    dd = IFEdd.dd()
    IFE.init!(dd, ini, act)
    IFE.ActorTransport(dd, act)
    IFE.ActorBlanket(dd, act)
    IFE.ActorBalanceOfPlant(dd, act)
    IFE.ActorCosting(dd, act)
    return dd
end

study.workflow = optimization_workflow

# -----------------------------------------------------------------------------
# 6. Run
# -----------------------------------------------------------------------------
FUSE.run(study)
