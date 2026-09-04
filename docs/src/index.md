# IFE.jl

Inertial fusion energy modeling on top of FUSE, kept in its own package.

FUSE's actors, initialization and study tooling all dispatch on the abstract
`IMAS.DD`. IFE.jl uses that to add an inertial-confinement workflow without
editing FUSE: it works on `IFEdd.dd`, a satellite data dictionary carrying the
IFE-specific IDSs (`driver`, a spherical `build`, …) next to the standard ones
it needs, and defines its own slim `ParametersInits` / `ParametersActors`
containers.

Nothing is exported. As with FUSE, everything is used module-qualified.

## A complete run

One case, no scan, no workers. This block is executed when the docs are built.

```@example basic
using FUSE, IFE, IFEdd, IMAS

ini, act = FUSE.case_parameters(:IFE)
dd = IFEdd.dd()
IFE.init!(dd, ini, act)

IFE.ActorTransport(dd, act)     # 0-D gain model   -> core_profiles
IFE.ActorBlanket(dd, act)       # TBR optimization -> blanket, neutronics
FUSE.ActorPowerNeeds(dd, act)   # wall-plug power  -> balance_of_plant
IFE.ActorCosting(dd, act)       # plant costing    -> costing
nothing # hide
```

`IMAS.extract` on an `IFEdd.dd` uses `IFE.ExtractFunctionsLibrary` — driver
energy, duty cycle, target gain, TBR, capital cost — rather than the tokamak
library:

```@example basic
IMAS.print_tiled(IMAS.extract(dd); terminal_width=100)
```

## How it fits FUSE

| FUSE machinery | how IFE reaches it |
|---|---|
| `FUSE.case_parameters` | a `Val{:IFE}` method |
| `FUSE.ActorPowerNeeds` | a method for `dd::IFEdd.dd` |
| `IMAS.extract` | a method for `dd::IFEdd.dd` |
| `FUSE.StudyDatabaseGenerator` | its `dd_type` and `extract_library` options |
| `FUSE.ParametersAllInits` / `ParametersAllActors` | `IFE.ParametersInits` / `IFE.ParametersActors` are concrete subtypes |

Where FUSE dispatches on the abstract type, IFE adds a method. Where FUSE used to
construct `IMAS.dd()` itself — the study runner — it now takes the container
type as an option instead. FUSE itself is not edited.
