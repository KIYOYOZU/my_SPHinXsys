/**
 * @file  test_3d_channel_flow.cpp
 * @brief Three-dimensional plane Poiseuille flow driven by a constant body force.
 * @details The case extends the 2D channel-flow reference to 3D by extruding the spanwise
 *          direction and applying periodic boundaries along the streamwise (x) and spanwise (z)
 *          directions while enforcing no-slip conditions on the top and bottom walls (y direction).
 *          The objective is to reach a steady laminar parabolic profile and compare it against
 *          the analytical solution through observer probes.
 * @author Codex
 */

#include "sphinxsys.h"
#include <gtest/gtest.h>
#include <chrono>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <sstream>

using namespace SPH;

//------------------------------------------------------------------------------
//  Geometry parameters and numerical setup.
//------------------------------------------------------------------------------
const Real DL = 10.0; /**< Channel length along x. */
const Real DH = 2.0;  /**< Channel height along y (wall-normal). */
const Real DW = 1.0;  /**< Channel width along z (spanwise). */

//------------------------------------------------------------------------------
//  Global fluid properties.
//------------------------------------------------------------------------------
const Real rho0_f = 1.0;        /**< Reference density. */
const Real U_bulk = 1.0;        /**< Bulk (average) velocity magnitude. */
const Real flow_direction_initial = 1.0; /**< Initial streamwise sign (+1 forward, -1 reverse). */
const Real flow_direction_body = -1.0;   /**< Body-force / steady solution sign. */
const Real c_f = 10.0 * U_bulk; /**< Artificial sound speed (weakly compressible, uses magnitude). */
const Real Re = 100.0;          /**< Reynolds number based on DH and U_bulk magnitude. */
const Real mu_f = rho0_f * U_bulk * DH / Re; /**< Dynamic viscosity. */

//------------------------------------------------------------------------------
//  Case-dependent geometries and helpers.
//------------------------------------------------------------------------------
namespace SPH
{
class ChannelGeometry : public ComplexShape
{
  public:
    explicit ChannelGeometry(const std::string &shape_name) : ComplexShape(shape_name)
    {
        Transform translation(Vecd(0.5 * DL, 0.5 * DH, 0.0));
        Vecd halfsize(0.5 * DL, 0.5 * DH, 0.5 * DW);
        add<GeometricShapeBox>(translation, halfsize);
    }
};

class WallBoundary;
template <>
class ParticleGenerator<SurfaceParticles, WallBoundary> : public ParticleGenerator<SurfaceParticles>
{
    Real resolution_ref_;
    Real wall_thickness_;
    Real sponge_length_;
    Real span_extension_;

  public:
    explicit ParticleGenerator(SPHBody &sph_body, SurfaceParticles &surface_particles,
                               Real resolution_ref, Real wall_thickness)
        : ParticleGenerator<SurfaceParticles>(sph_body, surface_particles),
          resolution_ref_(resolution_ref),
          wall_thickness_(wall_thickness),
          sponge_length_(20.0 * resolution_ref),
          span_extension_(4.0 * resolution_ref) {};

    void prepareGeometricData() override
    {
        const int particle_number_x = int((DL + 2.0 * sponge_length_) / resolution_ref_);
        const int particle_number_z = int((DW + 2.0 * span_extension_) / resolution_ref_);

        for (int i = 0; i < particle_number_x; ++i)
        {
            const Real x = -sponge_length_ + (static_cast<Real>(i) + 0.5) * resolution_ref_;
            for (int k = 0; k < particle_number_z; ++k)
            {
                const Real z = -0.5 * DW - span_extension_ + (static_cast<Real>(k) + 0.5) * resolution_ref_;

                const Vecd top_position(x, DH + 0.5 * resolution_ref_, z);
                addPositionAndVolumetricMeasure(top_position, resolution_ref_ * resolution_ref_);
                addSurfaceProperties(Vecd(0.0, 1.0, 0.0), wall_thickness_);

                const Vecd bottom_position(x, -0.5 * resolution_ref_, z);
                addPositionAndVolumetricMeasure(bottom_position, resolution_ref_ * resolution_ref_);
                addSurfaceProperties(Vecd(0.0, -1.0, 0.0), wall_thickness_);
            }
        }
    }
};

StdVec<Vecd> createCenterlineObservationPoints(size_t number_of_points, Real resolution_ref)
{
    StdVec<Vecd> observation_points;
    const Real margin = 4.0 * resolution_ref;
    const Real start = margin;
    const Real end = DL - margin;
    const Real y = 0.5 * DH;
    const Real z = 0.0;

    for (size_t i = 0; i < number_of_points; ++i)
    {
        const Real xi = start + (end - start) * static_cast<Real>(i) / static_cast<Real>(number_of_points - 1);
        observation_points.emplace_back(Vecd(xi, y, z));
    }
    return observation_points;
}

StdVec<Vecd> createWallNormalObservationPoints(size_t number_of_points, Real resolution_ref)
{
    StdVec<Vecd> observation_points;
    const Real x = 0.5 * DL;
    const Real z = 0.0;
    const Real padding = 4.0 * resolution_ref;

    for (size_t i = 0; i < number_of_points; ++i)
    {
        const Real yi = padding + (DH - 2.0 * padding) * static_cast<Real>(i) / static_cast<Real>(number_of_points - 1);
        observation_points.emplace_back(Vecd(x, yi, z));
    }
    return observation_points;
}

StdVec<Vecd> createSpanwiseObservationPoints(size_t number_of_points, Real resolution_ref)
{
    StdVec<Vecd> observation_points;
    const Real x = 0.5 * DL;
    const Real y = 0.5 * DH;
    const Real margin = 4.0 * resolution_ref;
    const Real start = -0.5 * DW + margin;
    const Real end = 0.5 * DW - margin;
    for (size_t i = 0; i < number_of_points; ++i)
    {
        const Real zi = start + (end - start) * static_cast<Real>(i) / static_cast<Real>(number_of_points - 1);
        observation_points.emplace_back(Vecd(x, y, zi));
    }
    return observation_points;
}
} // namespace SPH

//------------------------------------------------------------------------------
//  Case-dependent initial condition.
//------------------------------------------------------------------------------
class InitialVelocity : public fluid_dynamics::FluidInitialCondition
{
  public:
    explicit InitialVelocity(SPHBody &sph_body)
        : fluid_dynamics::FluidInitialCondition(sph_body) {};

    void update(size_t index_i, Real dt)
    {
        vel_[index_i] = Vecd(flow_direction_initial * U_bulk, 0.0, 0.0);
    }
};

//------------------------------------------------------------------------------
//  Analytical solution helpers.
//------------------------------------------------------------------------------
Vecd analytical_velocity_profile(const Vecd &position)
{
    const Real y_hat = 2.0 * position[1] / DH - 1.0;
    const Real u = 1.5 * flow_direction_body * U_bulk * (1.0 - y_hat * y_hat);
    return Vecd(u, 0.0, 0.0);
}

//------------------------------------------------------------------------------
void channel_flow_3d(const Real resolution_ref, const Real wall_thickness)
{
    const Real BW = 4.0 * resolution_ref;

    BoundingBox system_domain_bounds(
        Vecd(-20.0 * resolution_ref, -wall_thickness, -0.5 * DW - BW),
        Vecd(DL + 20.0 * resolution_ref, DH + wall_thickness, 0.5 * DW + BW));

    SPHSystem sph_system(system_domain_bounds, resolution_ref);
    sph_system.setRunParticleRelaxation(false);
    sph_system.setReloadParticles(false);

    FluidBody channel_fluid(sph_system, makeShared<ChannelGeometry>("ChannelFluid"));
    channel_fluid.defineClosure<WeaklyCompressibleFluid, Viscosity>(ConstructArgs(rho0_f, c_f), mu_f);
    channel_fluid.generateParticles<BaseParticles, Lattice>();

    SolidBody wall_boundary(sph_system, makeShared<DefaultShape>("ChannelWall"));
    wall_boundary.defineMaterial<Solid>();
    wall_boundary.generateParticles<SurfaceParticles, WallBoundary>(resolution_ref, wall_thickness);

    ObserverBody axial_observer(sph_system, "CenterlineObserver");
    axial_observer.generateParticles<ObserverParticles>(createCenterlineObservationPoints(41, resolution_ref));

    ObserverBody wall_normal_observer(sph_system, "WallNormalObserver");
    wall_normal_observer.generateParticles<ObserverParticles>(createWallNormalObservationPoints(51, resolution_ref));

    ObserverBody spanwise_observer(sph_system, "SpanwiseObserver");
    spanwise_observer.generateParticles<ObserverParticles>(createSpanwiseObservationPoints(21, resolution_ref));

    InnerRelation fluid_inner(channel_fluid);
    ShellInnerRelationWithContactKernel wall_curvature(wall_boundary, channel_fluid);
    SimpleDynamics<thin_structure_dynamics::AverageShellCurvature> shell_curvature(wall_curvature);
    ContactRelationFromShellToFluid fluid_contact(channel_fluid, {&wall_boundary}, {false});
    ContactRelation axial_contact(axial_observer, {&channel_fluid});
    ContactRelation wall_normal_contact(wall_normal_observer, {&channel_fluid});
    ContactRelation spanwise_contact(spanwise_observer, {&channel_fluid});

    ComplexRelation fluid_complex(fluid_inner, fluid_contact);

    Dynamics1Level<fluid_dynamics::Integration1stHalfWithWallRiemann> pressure_relaxation(fluid_inner, fluid_contact);
    Dynamics1Level<fluid_dynamics::Integration2ndHalfWithWallNoRiemann> density_relaxation(fluid_inner, fluid_contact);
    InteractionWithUpdate<fluid_dynamics::DensitySummationComplex> update_density(fluid_inner, fluid_contact);
    ReduceDynamics<fluid_dynamics::AdvectionViscousTimeStep> get_advection_dt(channel_fluid, 1.5 * U_bulk);
    ReduceDynamics<fluid_dynamics::AcousticTimeStep> get_acoustic_dt(channel_fluid);
    InteractionWithUpdate<fluid_dynamics::TransportVelocityCorrectionComplex<AllParticles>> transport_correction(fluid_inner, fluid_contact);
    InteractionWithUpdate<fluid_dynamics::ViscousForceWithWall> viscous_acceleration(fluid_inner, fluid_contact);
    ParticleSorting particle_sorting(channel_fluid);

    // Body-force drive derived from plane Poiseuille solution:
    // |U_bulk| = (|f_x| * DH^2) / (12 * nu) with nu = mu_f / rho0_f.
    const Real body_force_magnitude = 12.0 * mu_f * U_bulk / (rho0_f * DH * DH);
    const Real body_force = flow_direction_body * body_force_magnitude;
    Gravity gravity(Vecd(body_force, 0.0, 0.0));
    SimpleDynamics<GravityForce<Gravity>> constant_body_force(channel_fluid, gravity);

    PeriodicAlongAxis periodic_along_x(channel_fluid.getSPHBodyBounds(), xAxis);
    PeriodicAlongAxis periodic_along_z(channel_fluid.getSPHBodyBounds(), zAxis);
    PeriodicConditionUsingCellLinkedList periodic_condition_x(channel_fluid, periodic_along_x);
    PeriodicConditionUsingCellLinkedList periodic_condition_z(channel_fluid, periodic_along_z);

    sph_system.initializeSystemCellLinkedLists();
    periodic_condition_x.update_cell_linked_list_.exec();
    periodic_condition_z.update_cell_linked_list_.exec();
    sph_system.initializeSystemConfigurations();
    shell_curvature.exec();
    fluid_complex.updateConfiguration();

    SimpleDynamics<InitialVelocity> initial_velocity(channel_fluid);
    initial_velocity.exec();

    Real &physical_time = *sph_system.getSystemVariableDataByName<Real>("PhysicalTime");
    size_t number_of_iterations = 0;
    const int screen_output_interval = 100;
    const Real end_time = 100.0; /**< Extended run to observe long-term steady behavior. */
    const Real output_interval = end_time / 200.0;

    TickCount t1 = TickCount::now();
    TimeInterval interval;
    const auto wall_clock_start = std::chrono::steady_clock::now();
    const auto system_time_start = std::chrono::system_clock::now();

    BodyStatesRecordingToVtp write_states(sph_system);
    ObservedQuantityRecording<Vecd> write_centerline_velocity("Velocity", axial_contact);
    ObservedQuantityRecording<Vecd> write_wall_normal_velocity("Velocity", wall_normal_contact);
    ObservedQuantityRecording<Vecd> write_spanwise_velocity("Velocity", spanwise_contact);
    ReducedQuantityRecording<TotalKineticEnergy> write_kinetic_energy(channel_fluid);

    write_states.writeToFile();

    while (physical_time < end_time)
    {
        Real integration_time = 0.0;
        while (integration_time < output_interval)
        {
            const Real Dt = get_advection_dt.exec();
            update_density.exec();
            viscous_acceleration.exec();
            transport_correction.exec();

            size_t inner_ite_dt = 0;
            Real relaxation_time = 0.0;
            while (relaxation_time < Dt)
            {
                const Real dt = SMIN(get_acoustic_dt.exec(), Dt - relaxation_time);
                pressure_relaxation.exec(dt);
                constant_body_force.exec(dt);
                density_relaxation.exec(dt);

                relaxation_time += dt;
                integration_time += dt;
                physical_time += dt;
                inner_ite_dt++;
            }

            if (number_of_iterations % screen_output_interval == 0)
            {
                write_kinetic_energy.writeToFile(number_of_iterations);
                std::cout << std::fixed << std::setprecision(6)
                          << "[Iteration " << number_of_iterations << "] "
                          << "t = " << physical_time << ", Dt = " << Dt
                          << ", sub-steps = " << inner_ite_dt << std::endl;
            }
            number_of_iterations++;

            periodic_condition_x.bounding_.exec();
            periodic_condition_z.bounding_.exec();
            if (number_of_iterations % 200 == 0 && number_of_iterations != 1)
            {
                particle_sorting.exec();
            }
            channel_fluid.updateCellLinkedList();
            periodic_condition_x.update_cell_linked_list_.exec();
            periodic_condition_z.update_cell_linked_list_.exec();
            fluid_complex.updateConfiguration();
        }

        TickCount t2 = TickCount::now();
        write_states.writeToFile();
        axial_contact.updateConfiguration();
        wall_normal_contact.updateConfiguration();
        spanwise_contact.updateConfiguration();
        write_centerline_velocity.writeToFile(number_of_iterations);
        write_wall_normal_velocity.writeToFile(number_of_iterations);
        write_spanwise_velocity.writeToFile(number_of_iterations);
        TickCount t3 = TickCount::now();
        interval += t3 - t2;
    }

    TickCount t4 = TickCount::now();
    TimeInterval computation_time = t4 - t1 - interval;
    const auto wall_clock_end = std::chrono::steady_clock::now();
    const auto system_time_end = std::chrono::system_clock::now();
    const double wall_clock_seconds = std::chrono::duration<double>(wall_clock_end - wall_clock_start).count();

    std::cout << "Total wall time: " << computation_time.seconds() << " seconds." << std::endl;
    std::cout << "Wall-clock duration (steady_clock): " << wall_clock_seconds << " seconds." << std::endl;

    auto format_time = [](std::chrono::system_clock::time_point tp) {
        std::time_t tt = std::chrono::system_clock::to_time_t(tp);
        std::tm tm{};
#ifdef _WIN32
        localtime_s(&tm, &tt);
#else
        localtime_r(&tt, &tm);
#endif
        std::ostringstream oss;
        oss << std::put_time(&tm, "%Y-%m-%d %H:%M:%S");
        return oss.str();
    };

    std::ofstream timing_log("output/timing_summary.txt", std::ios::app);
    if (timing_log.is_open())
    {
        timing_log << "=== run @ " << format_time(system_time_start) << " ===\n";
        timing_log << "simulation_end_time = " << end_time << " s\n";
        timing_log << "wall_time_tickcount = " << computation_time.seconds() << " s\n";
        timing_log << "wall_time_steady_clock = " << wall_clock_seconds << " s\n";
        timing_log << "finish_at = " << format_time(system_time_end) << "\n\n";
    }

    BaseParticles &centerline_particles = axial_observer.getBaseParticles();
    Vecd *centerline_positions = centerline_particles.ParticlePositions();
    Vecd *centerline_velocity = centerline_particles.getVariableDataByName<Vecd>("Velocity");
    for (size_t i = 0; i < centerline_particles.TotalRealParticles(); ++i)
    {
        const Vecd target_velocity = analytical_velocity_profile(centerline_positions[i]);
        EXPECT_NEAR(target_velocity[0], centerline_velocity[i][0], 0.05 * U_bulk);
    }

    BaseParticles &wall_normal_particles = wall_normal_observer.getBaseParticles();
    Vecd *wall_normal_positions = wall_normal_particles.ParticlePositions();
    Vecd *wall_normal_velocity = wall_normal_particles.getVariableDataByName<Vecd>("Velocity");
    for (size_t i = 0; i < wall_normal_particles.TotalRealParticles(); ++i)
    {
        const Vecd target_velocity = analytical_velocity_profile(wall_normal_positions[i]);
        EXPECT_NEAR(target_velocity[0], wall_normal_velocity[i][0], 0.05 * U_bulk);
        EXPECT_NEAR(0.0, wall_normal_velocity[i][1], 2e-2);
        EXPECT_NEAR(0.0, wall_normal_velocity[i][2], 2e-2);
    }
}

TEST(test_3d_channel_flow, laminar_profile)
{
    const Real resolution_ref = 0.05;
    const Real wall_thickness = 10.0 * resolution_ref;
    channel_flow_3d(resolution_ref, wall_thickness);
}

int main(int ac, char *av[])
{
    testing::InitGoogleTest(&ac, av);
    return RUN_ALL_TESTS();
}
