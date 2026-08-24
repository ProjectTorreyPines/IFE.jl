"""
    IFE

IFE (Inertial Fusion Energy) orchestration package built on top of `IFEdd`
(data dictionary) and `FUSE` (actor framework + scaffolding).

Provides:
- IFE init parameter groups (`FUSEparameters__IFE__pellet`, `IFE__driver`)
- IFE parameter containers (`IFEParametersInits`, `IFEParametersActors`)
- IFE actors (`ActorIFEBlanket`, `ActorIFETransport`, `ActorCostingIFE`)
  defined via FUSE's `@actor_parameters_struct` macro
- Dispatch override on `FUSE.ActorPowerNeeds` for `dd::IFEdd.dd`
- `FUSE.case_parameters(::Val{:IFE})` registration
- `init_ife!`, `init_costing!`, `extract_ife`

All IFE-specific dispatches dispatch on at least one type owned by `IFE` or
`IFEdd` (e.g. `IFEdd.dd`, `IFEdd.driver`, `FUSEparameters__ActorIFE*`), so
adding methods to `FUSE.*` / `IMAS.*` functions is not type piracy.

Data containers and IDS types live in `IFEdd`; this package only adds
parameters, actors, init logic, cases, and extract — i.e. orchestration.

Load order matters (mirrors FUSE's actor → parameter container pattern):
1. `parameters_ife.jl`         — IFE init parameter groups
2. `parameters_inits_ife.jl`   — IFEParametersInits container
3. IFE actor files             — each defines a `FUSE.ParametersActor` subtype
4. `parameters_actors_ife.jl`  — IFEParametersActors container (after actors,
                                 so `@insert_subtype_members` sees them)
5. `extract_ife.jl`            — IFE scalar extract functions
"""
module IFE

using IMASdd
using IMAS
using FUSE
using FUSE: ±
using IFEdd
# IFEdd exports nothing. Dispatch signatures and type references throughout
# this package qualify as `IFEdd.X` (e.g. `IFEdd.dd`, `IFEdd.driver`,
# `IFEdd.build__layer`) so the IFE/IMAS distinction stays visible at every
# call site.
using Printf: @sprintf

# IFE-owned abstract supertypes — must precede any file that uses them
# in dispatch signatures (actor outer constructors, init_ife!, …).
include("abstract_ife_params.jl")

# IFE-specific init parameter groups.
include("parameters_ife.jl")

# Parameter container for FUSE.ParametersAllInits.
include("parameters_inits_ife.jl")

# IFE actors (each defines a FUSE.ParametersActor subtype).
include("actor_ife_blanket.jl")
include("actor_ife_transport.jl")
include("actor_costing_ife.jl")
include("power_needs_ife.jl")
include("case_ife.jl")

# Parameter container for FUSE.ParametersAllActors — must follow IFE actor
# files so `@insert_subtype_members FUSE.ParametersActor` enumerates them.
include("parameters_actors_ife.jl")

# IFE scalar extract functions.
include("extract_ife.jl")

export FUSEparameters__IFE__pellet, FUSEparameters__IFE__driver
export AbstractIFEParametersInits, AbstractIFEParametersActors
export IFEParametersInits, IFEParametersActors
export ActorIFEBlanket, FUSEparameters__ActorIFEBlanket
export ActorIFETransport, FUSEparameters__ActorIFETransport
export ActorCostingIFE, FUSEparameters__ActorCostingIFE
export init_ife!, init_costing!
export ife_duty_cycle, extract_ife

end # module
