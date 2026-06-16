using Test
using IFE
using IFEdd
using IMASdd
using IMAS
using FUSE

@testset "IFE" begin

    @testset "Module loading — IFE-side symbols" begin
        # Actors
        @test isdefined(IFE, :ActorIFEAblation)
        @test isdefined(IFE, :FUSEparameters__ActorIFEAblation)
        @test isdefined(IFE, :ActorIFEBlanket)
        @test isdefined(IFE, :FUSEparameters__ActorIFEBlanket)
        @test isdefined(IFE, :ActorIFETransport)
        @test isdefined(IFE, :ActorCostingIFE)

        # Init parameter groups
        @test isdefined(IFE, :FUSEparameters__IFE__pellet)
        @test isdefined(IFE, :FUSEparameters__IFE__driver)

        # Containers + workflow
        @test isdefined(IFE, :IFEParametersInits)
        @test isdefined(IFE, :IFEParametersActors)
        @test isdefined(IFE, :init_ife!)
        @test isdefined(IFE, :init_costing!)
        @test isdefined(IFE, :ife_duty_cycle)
        @test isdefined(IFE, :extract_ife)
    end

    @testset "ife_duty_cycle — IFE-only computation" begin
        d = IFEdd.dd()
        # Empty driver returns NaN
        @test isnan(IFE.ife_duty_cycle(d))
    end

    @testset "Actor parameter structs instantiate" begin
        par_ablation = IFE.FUSEparameters__ActorIFEAblation{Float64}()
        @test par_ablation isa FUSE.ParametersActor{Float64}

        par_blanket = IFE.FUSEparameters__ActorIFEBlanket{Float64}()
        @test par_blanket isa FUSE.ParametersActor{Float64}
    end

    @testset "IFEParametersInits — slim IFE groups" begin
        ini = IFE.IFEParametersInits()
        # Concrete + abstract type hierarchy
        @test ini isa IFE.IFEParametersInits{Float64}
        @test ini isa IFE.AbstractIFEParametersInits{Float64}
        @test ini isa FUSE.ParametersAllInits{Float64}
        # Groups that IFE workflow reads
        @test ini.general isa FUSE.FUSEparameters__general{Float64}
        @test ini.time isa FUSE.FUSEparameters__time{Float64}
        @test ini.core_profiles isa FUSE.FUSEparameters__core_profiles{Float64}
        @test ini.requirements isa FUSE.FUSEparameters__requirements{Float64}
        @test ini.bop isa FUSE.FUSEparameters__balance_of_plant{Float64}
        # IFE-specific groups
        @test ini.pellet isa IFE.FUSEparameters__IFE__pellet{Float64}
        @test ini.driver isa IFE.FUSEparameters__IFE__driver{Float64}
        # Default values from port
        @test ini.pellet.fuel_radius == 100e-6
        @test ini.driver.energy == 1.8e6
        # Magnetic-only groups must NOT be present in slim container
        for f in (:equilibrium, :pf_active, :tf, :oh, :build, :hcd, :rampup,
                  :nb_unit, :ec_launcher, :ic_antenna, :lh_antenna, :pellet_launcher)
            @test !hasproperty(ini, f)
        end
    end

    @testset "IFEParametersActors — slim IFE actor list" begin
        act = IFE.IFEParametersActors()
        # Concrete + abstract type hierarchy
        @test act isa IFE.IFEParametersActors{Float64}
        @test act isa IFE.AbstractIFEParametersActors{Float64}
        @test act isa FUSE.ParametersAllActors{Float64}
        # IFE-specific actors must be present
        @test act.ActorIFEAblation isa IFE.FUSEparameters__ActorIFEAblation{Float64}
        @test act.ActorIFEBlanket isa IFE.FUSEparameters__ActorIFEBlanket{Float64}
        @test act.ActorIFETransport isa IFE.FUSEparameters__ActorIFETransport{Float64}
        @test act.ActorCostingIFE isa IFE.FUSEparameters__ActorCostingIFE{Float64}
        # FUSE actors used by IFE workflow
        @test act.ActorCosting isa FUSE.ParametersActor
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
        act = IFE.IFEParametersActors()
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

    @testset "extract_ife stub — two-container signature" begin
        dd = IMAS.dd()
        ife = IFEdd.dd()
        out = IFE.extract_ife(dd, ife)
        @test out isa AbstractDict
        @test haskey(out, :duty_cycle)
        @test isnan(out[:duty_cycle])  # empty driver
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
        @test !hasproperty(std_act, :ActorIFEAblation)
        @test !hasproperty(std_act, :ActorIFEBlanket)
        @test !hasproperty(std_act, :ActorIFETransport)
        @test !hasproperty(std_act, :ActorCostingIFE)

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
        m_ife = which(FUSE.case_parameters, (Val{:IFE},))
        @test parentmodule(m_ife) === IFE
        n_ife_case_methods = count(m -> parentmodule(m) === IFE,
                                   methods(FUSE.case_parameters))
        @test n_ife_case_methods == 1
    end

    @testset "End-to-end IFE workflow" begin
        # 1. case_parameters returns IFE-flavored ini/act
        ini, act = FUSE.case_parameters(:IFE)
        @test ini isa IFE.IFEParametersInits
        @test act isa IFE.IFEParametersActors
        @test ini.driver.energy == 1.8e6

        # 2. init_ife! populates IFEdd.dd
        dd = IFEdd.dd()
        IFE.init_ife!(dd, ini, act)
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

        # 4. ife_duty_cycle returns a valid fraction
        @test 0.0 < IFE.ife_duty_cycle(dd) < 1.0

        # 5. ActorIFETransport runs (0-D gain model).
        IFE.ActorIFETransport(dd, act)
        @test length(dd.core_profiles.time) >= length(dd.driver.time)
        cp1d_peak = dd.core_profiles.profiles_1d[dd.global_time]
        @test maximum(cp1d_peak.electrons.temperature) > ini.pellet.Te_core

        # 6. ActorIFEBlanket runs (TBR optimization)
        IFE.ActorIFEBlanket(dd, act)
        @test !isempty(dd.blanket.module)
        @test !IMASdd.ismissing(dd.blanket.module[1].time_slice[1], :tritium_breeding_ratio)
        @test !isempty(dd.neutronics.first_wall.r)

        # 7. ActorPowerNeeds with IFE dispatch override.
        FUSE.ActorPowerNeeds(dd, act)
        bop_systems = dd.balance_of_plant.power_electric_plant_operation.system
        @test !isempty(bop_systems)
        hcd_idx = findfirst(s -> s.name == "HCD", bop_systems)
        @test hcd_idx !== nothing

        # 8. ActorCostingIFE runs. Caller is responsible for costing baseline.
        IFE.init_costing!(dd, act.ActorCosting)
        IFE.ActorCostingIFE(dd, act)
        @test dd.costing.cost_lifetime > 0.0
        @test dd.costing.levelized_CoE > 0.0
    end

end
