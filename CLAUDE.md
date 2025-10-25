# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SPHinXsys (pronunciation: s'finksis) is an acronym for **S**moothed **P**article **H**ydrodynamics for **in**dustrial comple**X** **sys**tems. It's a multi-physics library using SPH as the underlying numerical method for both particle-based and mesh-based discretization. The library supports simulation and optimization simultaneously within a unified computational framework.

Key capabilities:
- Fluid dynamics, solid mechanics, FSI (fluid-structure interaction)
- Fully compatible with classical FVM (finite volume method)
- Target-driven optimization
- Level set techniques for geometry processing (handles leaky CAD models)
- Python interface for scripting and CI/CD

## Build System

### CMake Configuration

The project uses CMake (minimum 3.16) with several build options:

```bash
# Configure with options
cmake -DSPHINXSYS_2D=ON \
      -DSPHINXSYS_3D=ON \
      -DSPHINXSYS_BUILD_TESTS=ON \
      -DSPHINXSYS_USE_FLOAT=OFF \
      -DSPHINXSYS_USE_SYCL=OFF \
      -DSPHINXSYS_MODULE_OPENCASCADE=OFF \
      ..

# Build
cmake --build . --config Release

# Run tests
ctest --output-on-failure
```

### Build Options
- `SPHINXSYS_2D`: Build 2D library (default: ON)
- `SPHINXSYS_3D`: Build 3D library (default: ON)
- `SPHINXSYS_BUILD_TESTS`: Build test cases (default: ON)
- `SPHINXSYS_USE_FLOAT`: Use float instead of double (default: OFF)
- `SPHINXSYS_USE_SIMD`: Enable SIMD instructions (default: OFF)
- `SPHINXSYS_USE_SYCL`: Enable SYCL acceleration (requires IntelLLVM compiler)
- `SPHINXSYS_MODULE_OPENCASCADE`: Enable OpenCASCADE extension (default: OFF)

### Dependencies

Required dependencies (managed via vcpkg or system package manager):
- **Simbody**: Multi-body dynamics
- **Eigen3**: Linear algebra
- **TBB**: Threading Building Blocks for parallelization
- **Boost**: Geometry and program_options
- **spdlog**: Logging library

## Code Architecture

### Directory Structure

```
SPHinXsys/
├── src/
│   ├── shared/              # Code shared between 2D and 3D
│   │   ├── bodies/          # SPHBody and body-related classes
│   │   ├── particles/       # Particle data structures
│   │   ├── materials/       # Material models (fluid, solid, etc.)
│   │   ├── geometries/      # Shape definitions and level sets
│   │   ├── meshes/          # Cell-linked lists and mesh structures
│   │   ├── kernels/         # SPH kernel functions
│   │   ├── body_relations/  # Topological connections between bodies
│   │   ├── particle_dynamics/  # Physical dynamics implementations
│   │   │   ├── fluid_dynamics/
│   │   │   ├── solid_dynamics/
│   │   │   ├── general_dynamics/
│   │   │   ├── diffusion_reaction_dynamics/
│   │   │   └── ...
│   │   └── io_system/       # I/O operations
│   ├── for_2D_build/        # 2D-specific implementations
│   └── for_3D_build/        # 3D-specific implementations
├── tests/
│   ├── 2d_examples/         # 2D test cases
│   ├── 3d_examples/         # 3D test cases
│   ├── optimization/        # Optimization examples
│   └── unit_tests_src/      # Unit tests
├── modules/                 # Optional extension modules
│   ├── opencascade/         # OpenCASCADE integration
│   └── structural_simulation/
└── PythonScriptStore/       # Python utilities and regression tests
```

### Core Architectural Concepts

**Two-Component Design:**

1. **Modeling Classes** (Data structures):
   - `SPHBody`: Represents a physical body in the simulation
   - `BaseParticles`: Particle data (position, velocity, density, etc.)
   - `Material`: Material properties (weakly compressible fluid, elastic solid, etc.)
   - `ParticleConfiguration`: Neighbor relationships and configurations

2. **Physical Dynamics** (Algorithms):
   - All dynamics derive from `ParticleDynamics` base class
   - **Inner dynamics**: Particle interactions within a single body
   - **Contact dynamics**: Interactions between different bodies
   - Examples: pressure relaxation, density summation, viscous forces

**Dimension Handling:**
- Shared code goes in `src/shared/`
- Dimension-specific code creates same-named folders in `for_2D_build/` and `for_3D_build/`
- Type aliases (`Vec2d`/`Vec3d`, `Real`) handle dimensional differences

### Key Design Patterns

**Particle Dynamics Hierarchy:**
```
ParticleDynamics (base)
├── SimpleDynamics      # No particle interaction
├── InteractionDynamics # Particle-particle interaction
│   ├── InteractionWithUpdate  # Immediate update
│   └── InteractionSplit       # Split update pattern
└── ReduceDynamics      # Global reduction operations
```

**Verlet Time Integration:**
- Uses split integration: `Integration1stHalf` and `Integration2ndHalf`
- First half: Update velocity and position using pressure/forces
- Second half: Update density using divergence of velocity
- Allows stable explicit time integration for weakly compressible flows

## Writing Test Cases

Each test case should:
1. Create a unique folder in `tests/2d_examples/` or `tests/3d_examples/`
2. Include a CMakeLists.txt:
   ```cmake
   STRING(REGEX REPLACE ".*/(.*)" "\\1" CURRENT_FOLDER ${CMAKE_CURRENT_SOURCE_DIR})
   PROJECT("${CURRENT_FOLDER}")

   set(DIR_SRCS your_case.cpp)
   add_executable(${PROJECT_NAME} ${DIR_SRCS})
   target_link_libraries(${PROJECT_NAME} sphinxsys_2d)  # or sphinxsys_3d
   ```
3. Use Google Test framework for validation:
   ```cpp
   #include <gtest/gtest.h>

   TEST(test_name, case_name) {
       // simulation code
       // validation with EXPECT_NEAR, EXPECT_LT, etc.
   }

   int main(int ac, char *av[]) {
       testing::InitGoogleTest(&ac, av);
       return RUN_ALL_TESTS();
   }
   ```

## Typical Simulation Workflow

1. **Define geometry**: Create shape classes or use level sets
2. **Create SPH system**: `SPHSystem sph_system(domain_bounds, resolution)`
3. **Create bodies**: `FluidBody`, `SolidBody`, `ObserverBody`
4. **Define materials**: Assign material properties to bodies
5. **Generate particles**: Lattice, surface, or custom generation
6. **Define body relations**: Inner relations, contact relations
7. **Define dynamics**: Pressure relaxation, viscous forces, time stepping
8. **Initialize**: Cell linked lists, configurations, initial conditions
9. **Main loop**: Time integration with output at intervals
10. **Validation**: Compare with analytical solutions or expected behavior

Example structure:
```cpp
// Geometry and parameters
const Real DL = 10.0, DH = 2.0;

// Create system
SPHSystem sph_system(system_domain_bounds, resolution_ref);

// Create bodies
FluidBody water_block(sph_system, makeShared<WaterBlock>(...));
water_block.defineClosure<WeaklyCompressibleFluid, Viscosity>(...);
water_block.generateParticles<BaseParticles, Lattice>();

// Body relations
InnerRelation water_inner(water_block);
ContactRelation water_contact(water_block, {&wall});

// Dynamics
Dynamics1Level<fluid_dynamics::Integration1stHalf> pressure_relaxation(water_inner);
Dynamics1Level<fluid_dynamics::Integration2ndHalf> density_relaxation(water_inner);
ReduceDynamics<fluid_dynamics::AcousticTimeStep> get_time_step(water_block);

// Initialize
sph_system.initializeSystemCellLinkedLists();
sph_system.initializeSystemConfigurations();

// Main loop
while (physical_time < end_time) {
    Real dt = get_time_step.exec();
    pressure_relaxation.exec(dt);
    density_relaxation.exec(dt);
    physical_time += dt;
}
```

## Code Style

Follows [Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html) with customizations in `.clang-format`:
- 4-space indentation (no tabs)
- Allman brace style (braces on new line)
- No column limit
- No single-line if statements

Format code:
```bash
clang-format -i your_file.cpp
```

## Testing and CI

### Running Tests
```bash
# Run all tests
ctest --output-on-failure

# Run specific test
ctest -R test_name -V

# Run with parallel execution (control with CTEST_PARALLEL_LEVEL)
ctest -j4
```

### Regression Testing
Python scripts in `PythonScriptStore/RegressionTest/` automate regression testing:
```bash
python regression_test_base_tool.py
```

### CI Pipeline
GitHub Actions workflow (`.github/workflows/ci.yml`) runs on:
- Push to master
- Pull requests to master
- Supports Linux, Windows, macOS
- Tests both 2D and 3D builds
- Includes SYCL acceleration tests

## Python Interface

SPHinXsys provides Python bindings for:
- Running simulations from Python scripts
- Regression testing automation
- Post-processing and analysis

Example usage can be found in `tests/test_python_interface/`.

## Common Pitfalls

1. **Dimension mismatch**: Ensure 2D tests link `sphinxsys_2d`, 3D tests link `sphinxsys_3d`
2. **Periodic boundaries**: Apply periodic conditions after mesh build but before configuration build
3. **Time step stability**: Use both advection time step (`AdvectionViscousTimeStep`) and acoustic time step (`AcousticTimeStep`)
4. **Shell normals**: Verify shell normals point in correct direction (from fluid to shell or vice versa)
5. **Configuration updates**: Update configurations after sorting or topology changes

## Documentation and Resources

- Project website: https://www.sphinxsys.org
- API documentation: https://xiangyu-hu.github.io/SPHinXsys/
- Tutorials: https://www.sphinxsys.org/html/sphinx_index.html
- Publications: See `assets/publication.md` for theory and algorithms

## Contributing

1. Fork the repository
2. Create a branch for your feature/fix
3. Follow the code style guide
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

Commit messages should:
- Use present tense ("Add feature" not "Added feature")
- Limit first line to 72 characters
- Reference issues/PRs after first line
- Use `[ci skip]` for documentation-only changes
