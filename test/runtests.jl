using Test
using IFE
using IFEdd
using IMASdd
using IMAS
using FUSE
import Measurements

# Workflow for the StudyDatabaseGenerator testset. Top level so it is an ordinary
# function. The study only needs a populated container; the full actor sequence
# is covered by "End-to-end IFE workflow".
study_workflow(dd::IFEdd.dd, ini::FUSE.ParametersAllInits, act::FUSE.ParametersAllActors) = IFE.init!(dd, ini, act)

@testset "IFE" begin

    @testset "Module loading — IFE-side symbols" begin
        # Actors
        @test isdefined(IFE, :ActorBlanket)
        @test isdefined(IFE, :FUSEparameters__ActorBlanket)
        @test isdefined(IFE, :ActorTransport)
        @test isdefined(IFE, :ActorCosting)

        # Init parameter groups
        @test isdefined(IFE, :FUSEparameters__pellet)
        @test isdefined(IFE, :FUSEparameters__driver)

        # Containers + workflow
        @test isdefined(IFE, :ParametersInits)
        @test isdefined(IFE, :ParametersActors)
        @test isdefined(IFE, :init!)
        @test isdefined(IFE, :duty_cycle)
        # extract is a method on IMAS.extract, not an IFE-owned name
        @test hasmethod(IMAS.extract, (IFEdd.dd,))
    end

    @testset "duty_cycle — IFE-only computation" begin
        d = IFEdd.dd()
        # Empty driver returns NaN
        @test isnan(IFE.duty_cycle(d))
    end

    @testset "Actor parameter structs instantiate" begin
        par_blanket = IFE.FUSEparameters__ActorBlanket{Float64}()
        @test par_blanket isa FUSE.ParametersActor{Float64}
    end

    @testset "ParametersInits — slim IFE groups" begin
        ini = IFE.ParametersInits()
        # Concrete + abstract type hierarchy
        @test ini isa IFE.ParametersInits{Float64}
        @test ini isa IFE.AbstractParametersInits{Float64}
        @test ini isa FUSE.ParametersAllInits{Float64}
        # Groups that IFE workflow reads
        @test ini.general isa FUSE.FUSEparameters__general{Float64}
        @test ini.time isa FUSE.FUSEparameters__time{Float64}
        @test ini.core_profiles isa FUSE.FUSEparameters__core_profiles{Float64}
        @test ini.requirements isa FUSE.FUSEparameters__requirements{Float64}
        @test ini.bop isa FUSE.FUSEparameters__balance_of_plant{Float64}
        # IFE-specific groups
        @test ini.pellet isa IFE.FUSEparameters__pellet{Float64}
        @test ini.driver isa IFE.FUSEparameters__driver{Float64}
        # Default values from port
        @test ini.pellet.fuel_radius == 100e-6
        @test ini.driver.energy == 1.8e6
        # Magnetic-only groups must NOT be present in slim container
        for f in (:equilibrium, :pf_active, :tf, :oh, :build, :hcd, :rampup,
                  :nb_unit, :ec_launcher, :ic_antenna, :lh_antenna, :pellet_launcher)
            @test !hasproperty(ini, f)
        end
    end

    @testset "ParametersActors — slim IFE actor list" begin
        act = IFE.ParametersActors()
        # Concrete + abstract type hierarchy
        @test act isa IFE.ParametersActors{Float64}
        @test act isa IFE.AbstractParametersActors{Float64}
        @test act isa FUSE.ParametersAllActors{Float64}
        # IFE-specific actors must be present
        @test act.ActorBlanket isa IFE.FUSEparameters__ActorBlanket{Float64}
        @test act.ActorTransport isa IFE.FUSEparameters__ActorTransport{Float64}
        @test act.ActorCosting isa IFE.FUSEparameters__ActorCosting{Float64}
        # IFE's own costing group, not FUSE's: one costing parameter group per act
        @test !(act.ActorCosting isa FUSE.FUSEparameters__ActorCosting)
        # FUSE actors used by IFE workflow
        @test act.ActorPowerNeeds isa FUSE.ParametersActor
        # Plant-level magnetic-agnostic actors kept for future use
        @test act.ActorBalanceOfPlant isa FUSE.ParametersActor
        @test act.ActorThermalPlant isa FUSE.ParametersActor
        # Magnetic-only actors must NOT be present in slim container
        for a in (:ActorEquilibrium, :ActorCHEASE, :ActorFRESCO, :ActorPedestal,
                  :ActorFluxMatcher, :ActorTFcoils, :ActorCostingARIES,
                  :ActorCostingSheffield)
            @test !hasproperty(act, a)
        end
    end

    @testset "ActorPowerNeeds — IFE outer constructor dispatch" begin
        d = IFEdd.dd()
        act = IFE.ParametersActors()
        # IFE registers `ActorPowerNeeds(dd::IFEdd.dd, act::ParametersAllActors)`
        # which should be more specific than FUSE's `(dd::IMAS.DD, act::ParametersAllActors)`.
        m = which(FUSE.ActorPowerNeeds, (typeof(d), typeof(act)))
        @test m isa Method
        # The chosen method must come from IFE, not FUSE
        @test parentmodule(m) === IFE
    end

    @testset "IMAS function dispatch on IFEdd.dd (signature relaxation)" begin
        d = IFEdd.dd()
        # fusion_power / fusion_neutron_power / fusion_energy must accept IFEdd.dd
        # after IMAS-side signature relaxation (::IMAS.dd → ::IMAS.DD).
        @test which(IMAS.fusion_power, (typeof(d),)) isa Method
        @test which(IMAS.fusion_neutron_power, (typeof(d),)) isa Method
        @test which(IMAS.fusion_energy, (typeof(d),)) isa Method

        # And the standard IMAS.dd dispatch must still work (no regression).
        std_dd = IMAS.dd()
        @test which(IMAS.fusion_power, (typeof(std_dd),)) isa Method
    end

    @testset "ExtractFunctionsLibrary — shape and grouping" begin
        # Same shape as joey's: 28 entries across seven groups, returned as
        # `ExtractFunction`s so IMAS's show / print_tiled / HDF5 save all apply.
        @test length(IFE.ExtractFunctionsLibrary) == 28
        groups = unique(xf.group for xf in values(IFE.ExtractFunctionsLibrary))
        @test Set(groups) == Set([:driver, :target, :plasma_peak, :power_avg,
                                  :neutronics, :bop, :costing])

        # An unpopulated container must not throw — failures are recorded per entry.
        out = IMAS.extract(IFEdd.dd())
        @test out isa AbstractDict{Symbol,IMAS.ExtractFunction}
        @test length(out) == 28
    end

    @testset "Standard FUSE/IMAS path unaffected by IFE loading" begin
        # With IFE loaded, calls on standard IMAS.dd + FUSE.ParametersInits/Actors
        # must still dispatch to FUSE/IMAS native methods, never IFE.

        std_dd = IMAS.dd()
        std_ini = FUSE.ParametersInits()
        std_act = FUSE.ParametersActors()

        # Standard ini/act must not carry IFE fields
        @test !hasproperty(std_ini, :pellet)
        @test !hasproperty(std_ini, :driver)
        @test !hasproperty(std_act, :ActorTransport)
        # These names are shared with FUSE by design; the types must stay FUSE's.
        @test std_act.ActorBlanket isa FUSE.FUSEparameters__ActorBlanket
        @test !(std_act.ActorBlanket isa IFE.FUSEparameters__ActorBlanket)
        @test std_act.ActorCosting isa FUSE.FUSEparameters__ActorCosting
        @test !(std_act.ActorCosting isa IFE.FUSEparameters__ActorCosting)

        # ActorPowerNeeds(::IMAS.dd, ::FUSE.ParametersActors) must dispatch to FUSE,
        # not the IFE outer constructor.
        m_apn = which(FUSE.ActorPowerNeeds, (typeof(std_dd), typeof(std_act)))
        @test parentmodule(m_apn) === FUSE

        # Standard model options on ActorPowerNeeds Switch remain unchanged.
        @test_throws Exception std_act.ActorPowerNeeds.model = :IFE
        std_act.ActorPowerNeeds.model = :FUSE
        @test std_act.ActorPowerNeeds.model == :FUSE
        std_act.ActorPowerNeeds.model = :EU_DEMO
        @test std_act.ActorPowerNeeds.model == :EU_DEMO
        std_act.ActorPowerNeeds.model = :thermal_power_fraction
        @test std_act.ActorPowerNeeds.model == :thermal_power_fraction

        # IMAS fusion functions on standard IMAS.dd still resolve to IMAS-owned
        # methods (not pirated by IFE).
        m_fp = which(IMAS.fusion_power, (typeof(std_dd),))
        @test parentmodule(m_fp) === IMAS

        # case_parameters: IFE registers exactly one Val{:IFE} method.
        m_case = which(FUSE.case_parameters, (Val{:IFE},))
        @test parentmodule(m_case) === IFE
        n_case_methods = count(m -> parentmodule(m) === IFE,
                                   methods(FUSE.case_parameters))
        @test n_case_methods == 1
    end

    @testset "End-to-end IFE workflow" begin
        # 1. case_parameters returns IFE-flavored ini/act
        ini, act = FUSE.case_parameters(:IFE)
        @test ini isa IFE.ParametersInits
        @test act isa IFE.ParametersActors
        @test ini.driver.energy == 1.8e6

        # 2. init! populates IFEdd.dd
        dd = IFEdd.dd()
        IFE.init!(dd, ini, act)
        @test length(dd.build.layer) == 5
        @test length(dd.driver.beam) == 1
        @test !isempty(dd.pellets.launcher)
        @test !isempty(dd.core_profiles.profiles_1d)
        @test !isempty(dd.core_sources.source)
        @test dd.requirements.tritium_breeding_ratio == 1.05

        # 3. IFE-only electricity dispatch works
        P_wallplug = FUSE.electricity(dd.driver)
        @test P_wallplug > 0.0
        @test isfinite(P_wallplug)

        # 4. duty_cycle returns a valid fraction
        @test 0.0 < IFE.duty_cycle(dd) < 1.0

        # 5. ActorTransport runs (0-D gain model).
        IFE.ActorTransport(dd, act)
        @test length(dd.core_profiles.time) >= length(dd.driver.time)
        cp1d_peak = dd.core_profiles.profiles_1d[dd.global_time]
        @test maximum(cp1d_peak.electrons.temperature) > ini.pellet.Te_core

        # 6. ActorBlanket runs (TBR optimization)
        IFE.ActorBlanket(dd, act)
        @test !isempty(dd.blanket.module)
        @test !IMASdd.ismissing(dd.blanket.module[1].time_slice[1], :tritium_breeding_ratio)
        @test !isempty(dd.neutronics.first_wall.r)

        # 7. ActorPowerNeeds with IFE dispatch override.
        FUSE.ActorPowerNeeds(dd, act)
        bop_systems = dd.balance_of_plant.power_electric_plant_operation.system
        @test !isempty(bop_systems)
        hcd_idx = findfirst(s -> s.name == "HCD", bop_systems)
        @test hcd_idx !== nothing

        # 8. ActorCosting runs and applies its own costing baseline.
        costing = IFE.ActorCosting(dd, act)
        @test dd.costing.cost_lifetime > 0.0

        # Cost uncertainty propagates on the promoted workspace and is dropped
        # on the way back into the plain-Float64 container.
        @test costing.ddR isa IFEdd.dd{Measurements.Measurement{Float64}}
        capital_R = costing.ddR.costing.cost_direct_capital.cost
        @test Measurements.uncertainty(capital_R) > 0.0
        @test Measurements.uncertainty(costing.ddR.costing.cost_lifetime) > 0.0
        @test dd.costing.cost_direct_capital.cost isa Float64
        @test dd.costing.cost_direct_capital.cost ≈ Measurements.value(capital_R)

        # Every actor field must stay concrete: `get_timeslice` is not inferrable,
        # so the struct boundary is what keeps `_step` type-stable.
        @test all(isconcretetype(fieldtype(typeof(costing), f)) for f in fieldnames(typeof(costing)))

        # 9. Extract reproduces joey's metric set on a populated container.
        # Everything outside `:bop` must evaluate; the `:bop` group stays empty
        # until a thermal cycle runs and fills `balance_of_plant.power_plant`.
        xtract = IMAS.extract(dd)
        failed = [k for (k, xf) in xtract if xf.error !== nothing]
        @test all(xtract[k].group === :bop for k in failed)
        @test count(xf -> xf.error === nothing, values(xtract)) == 24

        @test xtract[:E_driver].value ≈ ini.driver.energy / 1e6
        @test xtract[:n_beams].value == length(dd.driver.beam)
        @test xtract[:ablator].value == ini.pellet.ablator_material
        @test 0.0 < xtract[:duty_cycle].value < 1.0
        @test xtract[:Q_target].value > 0.0
        @test xtract[:TBR].value > 0.0
    end

    @testset "StudyDatabaseGenerator on IFEdd.dd" begin
        # FUSE's study runner builds the container itself, so unlike the actors
        # it cannot be reached by dispatch — `dd_type` is what lets it build an
        # `IFEdd.dd`. Nothing else here covers that FUSE-side path.
        ini, act = FUSE.case_parameters(:IFE)

        sty = FUSE.study_parameters(:DatabaseGenerator)
        sty.server = "localhost"
        sty.n_workers = 0 # master process only; pmap distribution is FUSE's concern
        sty.file_save_mode = :overwrite
        sty.save_folder = mktempdir()
        sty.n_simulations = 1
        sty.database_policy = :single_hdf5

        study = FUSE.StudyDatabaseGenerator(sty, ini, act; dd_type=IFEdd.dd)
        @test study.dd_type === IFEdd.dd
        study.workflow = study_workflow

        FUSE.run(study)
        @test study.dataframe[1, :status] == "success"

        # The saved container comes back as `IFEdd.dd`: FUSE resolves the type
        # from the file's `concrete_type` attribute. `pattern` skips ini/act,
        # whose reader still hardcodes `FUSE.ParametersInits`.
        db = FUSE.load_study_database(joinpath(sty.save_folder, "database.h5"), ["/case1"]; pattern=r"^dd")
        @test db.items[1].dd isa IFEdd.dd
    end

end
