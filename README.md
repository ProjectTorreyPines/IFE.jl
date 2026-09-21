[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://projecttorreypines.github.io/IFE.jl/dev/)

# IFE.jl

Inertial fusion energy modeling on top of [FUSE](https://github.com/ProjectTorreyPines/FUSE.jl).

FUSE dispatches on the abstract `IMAS.DD`, so IFE.jl adds an inertial-confinement workflow without editing FUSE. It runs on [`IFEdd.dd`](https://github.com/ProjectTorreyPines/IFEdd.jl), a satellite data dictionary carrying the IFE-specific IDS.

## Install

```sh
git clone https://github.com/ProjectTorreyPines/IFE.jl.git
cd IFE.jl
JULIA_PKG_USE_CLI_GIT=true julia --project -e 'using Pkg; Pkg.instantiate()'
```

`[sources]` resolves FUSE, IFEdd, IMAS and IMASdd from GitHub, so no Manifest is committed. `JULIA_PKG_USE_CLI_GIT=true` is required because IFEdd is private.

## Use

```julia
using FUSE, IFE, IFEdd, IMAS, Plots

ini, act = FUSE.case_parameters(:IFE)
dd = IFEdd.dd()
IFE.init!(dd, ini, act)

IFE.ActorTransport(dd, act)     # 0-D gain model   -> core_profiles
IFE.ActorBlanket(dd, act)       # TBR optimization -> blanket, neutronics
FUSE.ActorPowerNeeds(dd, act)   # wall-plug power  -> balance_of_plant
IFE.ActorCosting(dd, act)       # plant costing    -> costing

IMAS.extract(dd)                # IFE metrics, tiled by the REPL
plot(dd)                        # chamber cross-section
```

Nothing is exported; everything is module-qualified.

See [`examples/`](examples/) for a single case and two parameter scans, and the [documentation](https://projecttorreypines.github.io/IFE.jl/dev/) for the API.
