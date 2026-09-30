# =============================================================================
# The smallest complete IFE run: one case, no scan, no workers.
# =============================================================================
using FUSE, IFE, IFEdd, IMAS

# -----------------------------------------------------------------------------
# 1. Case parameters. `ini` describes the machine, `act` the actor settings.
#    Both are IFE containers (`IFE.ParametersInits`, `IFE.ParametersActors`),
#    slimmed down from FUSE's tokamak ones.
# -----------------------------------------------------------------------------
ini, act = FUSE.case_parameters(:IFE)

@show ini.driver.energy            # J, laser energy on target
@show ini.pellet.ablator_material

# -----------------------------------------------------------------------------
# 2. An empty IFE data dictionary. `IFEdd.dd <: IMAS.DD`, so every IMAS/FUSE
#    function that dispatches on the abstract type works on it unchanged.
# -----------------------------------------------------------------------------
dd = IFEdd.dd()

# -----------------------------------------------------------------------------
# 3. Populate it from ini/act: build layers, driver beams, pellet, profiles.
# -----------------------------------------------------------------------------
IFE.init!(dd, ini, act)

# -----------------------------------------------------------------------------
# 4. The actor chain, all IFE's own. ActorBalanceOfPlant runs FUSE's thermal
#    cycle and IFE's power needs (FUSE.ActorPowerNeeds, via an `IFEdd.dd` method).
# -----------------------------------------------------------------------------
IFE.ActorTransport(dd, act)      # 0-D gain model   -> core_profiles
IFE.ActorBlanket(dd, act)        # TBR optimization -> blanket, neutronics
IFE.ActorBalanceOfPlant(dd, act) # thermal cycle + wall-plug power -> balance_of_plant
IFE.ActorCosting(dd, act)        # plant costing (propagates uncertainty)

# -----------------------------------------------------------------------------
# 5. Key numbers, then the full IFE metric set. IFE does not define its own
#    `extract`: it adds an `IMAS.extract` method for `IFEdd.dd`, so the ordinary
#    call returns IFE's 28 metrics instead of the tokamak ones.
# -----------------------------------------------------------------------------
@show IMAS.fusion_power(dd) / 1e6          # MW, peak
@show IFE.duty_cycle(dd)                   # τ_pulse / T_rep
@show dd.costing.cost_direct_capital.cost  # M$

xtract = IMAS.extract(dd)                  # an OrderedDict you can index
@show xtract[:Q_target].value

# The REPL prints this by itself; a script has to ask. `display` reaches the
# same tiled table `IMAS.print_tiled` writes — it is what `show` calls.
display(xtract)

# -----------------------------------------------------------------------------
# 6. Figures. Loading Plots activates IFEdd's recipe extension, so the IFE-owned
#    IDS draw themselves. The recipes live in IFEdd next to the schema they
#    read, and Plots is their only trigger — IMAS is not involved.
# -----------------------------------------------------------------------------
using Plots

chamber = plot(dd)                  # layers, driver beams, target capsule
build_cx = plot(dd.build)           # the concentric build on its own
build_radial = plot(dd.build; cx=false)   # the same build as a radial bar chart
power = plot(dd.driver)             # wall plug -> launched -> absorbed

# `plot` only builds the object when this file is run as a script, so write the
# figure out as well — that also makes the example checkable without a display.
figure = plot(chamber, power; layout=(1, 2), size=(1100, 450))
savefig(figure, "ife_basic_case.png")
@info "wrote ife_basic_case.png" n_layers = length(dd.build.layer) n_beams = length(dd.driver.beam)
