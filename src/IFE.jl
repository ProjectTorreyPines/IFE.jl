"""
    IFE

IFE (Inertial Fusion Energy) orchestration package built on top of `IFEdd`
(data dictionary) and `FUSE` (actor framework + scaffolding).

Provides:
- IFE init parameter groups (`FUSEparameters__pellet`, `IFE__driver`)
- IFE parameter containers (`ParametersInits`, `ParametersActors`)
- IFE actors (`ActorBlanket`, `ActorTransport`, `ActorCosting`)
  defined via FUSE's `@actor_parameters_struct` macro
- Dispatch override on `FUSE.ActorPowerNeeds` for `dd::IFEdd.dd`
- `FUSE.case_parameters(::Val{:IFE})` registration
- `init!`, `IMAS.extract`

All IFE-specific dispatches dispatch on at least one type owned by `IFE` or
`IFEdd` (e.g. `IFEdd.dd`, `IFEdd.driver`, `FUSEparameters__ActorIFE*`), so
adding methods to `FUSE.*` / `IMAS.*` functions is not type piracy.

Data containers and IDS types live in `IFEdd`; this package only adds
parameters, actors, init logic, cases, and extract — i.e. orchestration.

Load order matters (mirrors FUSE's actor → parameter container pattern):
1. `parameters.jl`             — IFE init parameter groups
2. `parameters_inits.jl`       — ParametersInits container
3. IFE actor files             — each defines a `FUSE.ParametersActor` subtype
4. `parameters_actors.jl`      — ParametersActors container (after actors,
                                 whose parameter structs its fields reference)
5. `extract.jl`                — `IMAS.extract` method for `IFEdd.dd`
"""
module IFE

using IMASdd
using IMAS
using FUSE
import Dates
using Measurements: Measurement, ±
using IFEdd
# IFEdd exports nothing. Dispatch signatures and type references throughout
# this package qualify as `IFEdd.X` (e.g. `IFEdd.dd`, `IFEdd.driver`,
# `IFEdd.build__layer`) so the IFE/IMAS distinction stays visible at every
# call site.
using Printf: @sprintf

# IFE-owned abstract supertypes — must precede any file that uses them
# in dispatch signatures (actor outer constructors, init!, …).
include("abstract_params.jl")

# IFE-specific init parameter groups.
include("parameters.jl")

# Parameter container for FUSE.ParametersAllInits.
include("parameters_inits.jl")

# IFE actors (each defines a FUSE.ParametersActor subtype).
include("actor_blanket.jl")
include("actor_transport.jl")
include("actor_costing.jl")
include("power_needs.jl")
include("case.jl")

# Parameter container for FUSE.ParametersAllActors — must follow the actor
# files, whose parameter structs its fields reference.
include("parameters_actors.jl")

# IFE scalar extract functions.
include("extract.jl")

# Nothing is exported: like FUSE, everything is used module-qualified
# (`IFE.ActorCosting`, `IFE.init!`, `IFE.ParametersInits`). The generic names
# only make sense with the `IFE.` prefix in front of them.

end # module
