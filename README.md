[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://projecttorreypines.github.io/IFE.jl/dev/)

# IFE.jl

Inertial fusion energy modeling on top of [FUSE](https://github.com/ProjectTorreyPines/FUSE.jl), kept in its own package.

FUSE's actors, initialization and study tooling all dispatch on the abstract `IMAS.DD`. IFE.jl uses that to add an inertial-confinement workflow without editing FUSE: it works on [`IFEdd.dd`](https://github.com/ProjectTorreyPines/IFEdd.jl), a satellite data dictionary that carries the IFE-specific IDSs (`driver`, a spherical `build`, …) alongside the standard ones it needs, and defines its own slim `ParametersInits` / `ParametersActors` containers so an IFE `act` is not weighed down by seventy tokamak actors.

## What it provides

- `FUSE.case_parameters(:IFE)` — a spherically symmetric demo case (target, driver, radial build)
- `IFE.init!` — populates an `IFEdd.dd` from `ini`/`act`
- `IFE.ActorTransport`, `IFE.ActorBlanket`, `IFE.ActorCosting` — 0-D gain model, TBR optimization, plant costing with uncertainty propagation
- an `IFEdd.dd` method for `FUSE.ActorPowerNeeds`, and one for `IMAS.extract` that reports IFE metrics (driver energy, duty cycle, target gain, …) instead of tokamak ones
- `FUSE.StudyDatabaseGenerator` scans over IFE cases, via its `dd_type` option

Nothing is exported. As with FUSE, everything is used module-qualified: `IFE.ActorCosting`, `IFE.init!`, `IFE.ParametersInits`.

## Quick start

```julia
using FUSE, IFE, IFEdd, IMAS

ini, act = FUSE.case_parameters(:IFE)
dd = IFEdd.dd()
IFE.init!(dd, ini, act)

IFE.ActorTransport(dd, act)     # 0-D gain model   -> core_profiles
IFE.ActorBlanket(dd, act)       # TBR optimization -> blanket, neutronics
FUSE.ActorPowerNeeds(dd, act)   # wall-plug power  -> balance_of_plant
IFE.ActorCosting(dd, act)       # plant costing    -> costing

IMAS.extract(dd)                # IFE's 28 metrics, tiled by the REPL
```

See [`examples/basic_ife_case.jl`](examples/basic_ife_case.jl) for the annotated version, and [`examples/study_pellet_simple_scan.jl`](examples/study_pellet_simple_scan.jl) for a parameter scan on workers.

## Installation

Private, pre-release. `Project.toml` resolves FUSE, IFEdd, IMAS and IMASdd from GitHub through `[sources]` (Julia ≥ 1.11), so a fresh clone fetches them without a committed Manifest. IFEdd, IMAS and IMASdd come from `master`; FUSE comes from `feat/study_ini_act_type`, which lets the study examples read a database back into IFE's `ini`/`act` containers — move it to `master` once that branch is merged. Branches move, so two clones made at different times can resolve different commits:

```sh
git clone https://github.com/ProjectTorreyPines/IFE.jl.git
cd IFE.jl
JULIA_PKG_USE_CLI_GIT=true julia --project -e 'using Pkg; Pkg.instantiate()'
```

IFEdd is a private repository. `JULIA_PKG_USE_CLI_GIT=true` makes Pkg clone with the `git` command line, so the credentials your `git` already uses for `ProjectTorreyPines/IFEdd.jl` apply; Pkg's built-in git does not see them.

`] dev` of a local checkout rewrites that package's `[sources]` entry to a local `path`; keep that change out of commits. To go back, restore `Project.toml` with git and run `] resolve` (`] free` refuses unregistered packages such as IFEdd).
