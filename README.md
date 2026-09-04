[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://projecttorreypines.github.io/IFE.jl/dev/)

# IFE.jl

Inertial fusion energy modeling on top of [FUSE](https://github.com/ProjectTorreyPines/FUSE.jl), kept in its own package.

FUSE's actors, initialization and study tooling all dispatch on the abstract `IMAS.DD`. IFE.jl uses that to add an inertial-confinement workflow without editing FUSE: it works on [`IFEdd.dd`](https://github.com/ProjectTorreyPines/IFEdd.jl), a satellite data dictionary that carries the IFE-specific IDSs (`driver`, a spherical `build`, …) alongside the standard ones it needs, and defines its own slim `ParametersInits` / `ParametersActors` containers so an IFE `act` is not weighed down by seventy tokamak actors.

## What it provides

- `FUSE.case_parameters(:IFE)` — a spherically symmetric demo case (target, driver, radial build)
- `IFE.init!` — populates an `IFEdd.dd` from `ini`/`act`
- `IFE.ActorTransport`, `IFE.ActorBlanket`, `IFE.ActorCosting` — 0-D gain model, TBR optimization, plant costing with uncertainty propagation
- an `IFEdd.dd` method for `FUSE.ActorPowerNeeds`, and one for `IMAS.extract` that reports IFE metrics (driver energy, duty cycle, target gain, …) instead of tokamak ones
- `FUSE.StudyDatabaseGenerator` scans over IFE cases, via its `dd_type` and `extract_library` options

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

IMAS.print_tiled(IMAS.extract(dd))
```

See [`examples/basic_ife_case.jl`](examples/basic_ife_case.jl) for the annotated version, and [`examples/study_pellet_simple_scan.jl`](examples/study_pellet_simple_scan.jl) for a parameter scan on workers.

## Status

Private, pre-release. The study examples need a FUSE that accepts `dd_type` on `StudyDatabaseGenerator` (FUSE branch `feat/study_dd_type`); until that is merged and released, develop FUSE from that branch.

## Development

```julia
] dev IFEdd IFE
] test IFE
```
