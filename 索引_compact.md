# 📂 SPHinXsys 功能-代码映射报告

## 🏗️ 项目概览
- **项目类型**: C++ 多物理场仿真库 (Multi-physics Simulation Library)
- **技术栈**: C++, CMake, SPH (Smoothed Particle Hydrodynamics), Google Test, Simbody, Eigen3, TBB
- **架构模式**: 两组件设计 (建模类 + 物理动力学算法) + 维度分离 (2D/3D)
- **生成时间**: 2025-10-17

## 📑 功能分类索引

1. [核心 SPH 系统](#1-核心-sph-系统)
2. [物理体类型 (Bodies)](#2-物理体类型-bodies)
3. [材料模型 (Materials)](#3-材料模型-materials)
4. [粒子动力学 (Particle Dynamics)](#4-粒子动力学-particle-dynamics)
5. [时间积分方法](#5-时间积分方法)
6. [边界条件](#6-边界条件)
7. [体间关系 (Body Relations)](#7-体间关系-body-relations)
8. [粒子生成器](#8-粒子生成器)
9. [SPH 核函数 (Kernels)](#9-sph-核函数-kernels)
10. [几何形状与网格](#10-几何形状与网格)
11. [输入输出系统 (I/O)](#11-输入输出系统-io)
12. [测试案例库](#12-测试案例库)
13. [构建系统与配置](#13-构建系统与配置)
14. [Python 接口](#14-python-接口)
15. [优化与自适应](#15-优化与自适应)

---

## 1. 核心 SPH 系统

### SPH 系统总入口

**关键词**:
- 主: 创建 SPH 仿真系统, 初始化 SPHinXsys, 设置仿真环境
- 别: SPH 框架搭建, 仿真系统初始化, 创建仿真域

**定位**:
- 主: `src/shared/sphinxsys_system/sph_system.hpp`：SPH 系统核心类定义
- 总头: `src/shared/include/sphinxsys.h`：用户代码应包含的唯一头文件
- 求解: `src/shared/sphinxsys_system/sph_solver.h`：高层求解器封装

**片段**:
- 代码形式: `SPHSystem sph_system(system_domain_bounds, resolution_ref);`
- 用法: 在 `main()` 函数中首先创建

**修改**:
- 修改域边界: 编辑测试案例中的 `BoundingBox system_domain_bounds` 定义
- 修改分辨率: 调整 `resolution_ref` 参数
- 增加系统级配置: 编辑 `src/shared/sphinxsys_system/` 下的文件

**参考**: 构建指南§4.2.4 SPH系统初始化、§4.2.1几何参数定义

---

### 系统初始化流程

**关键词**:
- 主: 初始化网格和配置, 设置粒子邻居关系
- 别: 初始化单元链表, 构建粒子配置, 初始化仿真环境

**定位**:
- 主: `src/shared/sphinxsys_system/sph_system.hpp`：`initializeSystemCellLinkedLists()`, `initializeSystemConfigurations()`
- 调用位置: 测试案例的主函数中 (例如 `tests/2d_examples/test_2d_channel_flow_fluid_shell/channel_flow_shell.cpp` 第 240-245 行)

**片段**:
```cpp
sph_system.initializeSystemCellLinkedLists();
periodic_condition.update_cell_linked_list_.exec();
sph_system.initializeSystemConfigurations();
```

**修改**:
- 修改初始化顺序: 编辑测试案例中初始化部分的调用顺序
- 增加周期边界: 在 `initializeSystemCellLinkedLists()` 后、`initializeSystemConfigurations()` 前调用周期条件

**参考**: 构建指南§4.2.8初始化操作、§5.4.1周期边界条件、§8-Q3常见问题

---

## 2. 物理体类型 (Bodies)

### 流体体 (Fluid Body)

**关键词**:
- 主: 创建流体域, 定义水体, 设置流体区域
- 别: 流体块, 液体体, 可压缩流体, 不可压缩流体

**定位**:
- 主: `src/shared/bodies/fluid_body.h`：`FluidBody` 类定义
- 汇总头文件: `src/shared/bodies/all_bodies.h`：包含所有体类型
- 使用示例: `tests/2d_examples/test_2d_channel_flow_fluid_shell/channel_flow_shell.cpp` 第 158 行

**片段**:
```cpp
FluidBody water_block(sph_system, makeShared<WaterBlock>(...));
water_block.defineClosure<WeaklyCompressibleFluid, Viscosity>(ConstructArgs(rho0_f, c_f), mu_f);
water_block.generateParticles<BaseParticles, Lattice>();
```

**修改**:
- 修改流体材料: 编辑 `defineClosure<>` 模板参数 (如 `WeaklyCompressibleFluid`, `CompressibleFluid`)
- 修改流体属性: 调整 `ConstructArgs(rho0_f, c_f)` 中的密度和声速参数
- 修改粘性: 调整 `mu_f` 粘性系数

**参考**: 构建指南§4.2.5 Body创建和粒子生成、§4.2.2材料参数定义、§5.1纯流体模拟

---

### 固体体 (Solid Body)

**关键词**:
- 主: 创建固体结构, 定义弹性固体, 设置刚体
- 别: 弹性体, 结构体, 变形固体, 壳体

**定位**:
- 主: `src/shared/bodies/solid_body.h`：`SolidBody` 类定义
- 壳体粒子: `src/shared/particles/surface_particles.h`：`SurfaceParticles` 用于薄壳结构
- 使用示例: `tests/2d_examples/test_2d_channel_flow_fluid_shell/channel_flow_shell.cpp` 第 162-164 行

**片段**:
```cpp
SolidBody wall_boundary(sph_system, makeShared<DefaultShape>(Wall));
wall_boundary.defineMaterial<Solid>();
wall_boundary.generateParticles<SurfaceParticles, WallBoundary>(resolution_ref, wall_thickness);
```

**修改**:
- 修改固体材料: 编辑 `defineMaterial<>` 模板参数 (如 `LinearElasticSolid`, `NeoHookeanSolid`)
- 修改材料参数: 在 `defineMaterial<>` 中传递杨氏模量、泊松比等参数
- 修改粒子生成: 选择 `BaseParticles` (体粒子) 或 `SurfaceParticles` (表面粒子)

**参考**: 构建指南§4.2.5 Body创建和粒子生成、§5.2流体-壳层耦合、§5.3流体-固体耦合

---

### 观测体 (Observer Body)

**关键词**:
- 主: 创建观测点, 定义测量位置, 设置监控点
- 别: 探针, 传感器, 观察器, 数据采集点

**定位**:
- 主: `src/shared/bodies/observer_body.h`：`ObserverBody` 类定义
- 粒子类型: `src/shared/particles/observer_particles.h`：`ObserverParticles`
- 使用示例: `tests/2d_examples/test_2d_channel_flow_fluid_shell/channel_flow_shell.cpp` 第 166-170 行

**片段**:
```cpp
ObserverBody fluid_axial_observer(sph_system, FluidAxialObserver);
fluid_axial_observer.generateParticles<ObserverParticles>(createFluidAxialObservationPoints(resolution_ref));
```

**修改**:
- 修改观测点位置: 编辑辅助函数 (如 `createFluidAxialObservationPoints()`) 中的坐标计算
- 增加观测点数量: 调整辅助函数中的循环次数或点列表

**参考**: 构建指南§4.2.5 Body创建和粒子生成、§7.1添加观测点、§3.5.5观测与输出

---

### 复杂体 (Complex Bodies)

**关键词**:
- 主: 创建树状结构, 定义非结构化网格体, 设置次级结构
- 别: 复合体, 网格体, 树形体, 血管网络

**定位**:
- 汇总头文件: `src/shared/bodies/complex_bodies/all_complex_bodies.h`
- 树状体: `src/shared/bodies/complex_bodies/tree_body.h`：`TreeBody` 用于血管等树状结构
- 非结构网格: `src/shared/bodies/complex_bodies/unstructured_mesh.h`：`UnstructuredMesh`
- 网格辅助: `src/shared/bodies/complex_bodies/mesh_helper.h`

**修改**:
- 使用树状体: 参考 `tests/3d_examples/test_3d_network/` 测试案例
- 使用非结构网格: 参考心脏模拟案例 `tests/3d_examples/test_3d_heart_*/`

---

## 3. 材料模型 (Materials)

### 弱可压缩流体 (Weakly Compressible Fluid)

**关键词**:
- 主: 设置水的材料属性, 定义弱可压缩流体
- 别: 不可压缩流近似, WCSPH 流体, 液态水

**定位**:
- 主: `src/shared/physical_closure/materials/weakly_compressible_fluid.h`：`WeaklyCompressibleFluid` 类
- 汇总头文件: `src/shared/physical_closure/materials/all_materials.h`
- 使用示例: 测试案例中的 `defineClosure<WeaklyCompressibleFluid, ...>` 调用

**片段**:
```cpp
water_block.defineClosure<WeaklyCompressibleFluid, Viscosity>(ConstructArgs(rho0_f, c_f), mu_f);
```

**修改**:
- 修改参考密度: 调整 `rho0_f` 参数
- 修改参考声速: 调整 `c_f` 参数 (通常设为 10 倍特征速度)
- 增加粘性: 添加 `Viscosity` 闭包并传递 `mu_f` 参数

**参考**: 构建指南§4.2.2材料参数定义、§5.1.2完整代码示例、§8-Q2声速确定

---

### 可压缩流体 (Compressible Fluid)

**关键词**:
- 主: 设置气体材料, 定义可压缩流体, 欧拉流动
- 别: 空气, 超音速流动, 激波

**定位**:
- 主: `src/shared/physical_closure/materials/compressible_fluid.h`：`CompressibleFluid` 类
- 黎曼求解器: `src/shared/physical_closure/materials/riemann_solver.h`：激波捕捉用黎曼求解器

**修改**:
- 使用可压缩流体: 参考 `tests/2d_examples/test_2d_eulerian_supersonic_flow_new_BC/` 案例
- 修改状态方程: 编辑 `CompressibleFluid` 类中的 EOS 定义

---

### 弹性固体材料 (Elastic Solid)

**关键词**:
- 主: 设置弹性材料属性, 定义线性弹性固体, 超弹性材料
- 别: 橡胶材料, 金属弹性, 生物组织

**定位**:
- 主: `src/shared/physical_closure/materials/elastic_solid.h`：`LinearElasticSolid`, `NeoHookeanSolid` 等
- 复杂固体: `src/shared/physical_closure/materials/complex_solid.h`：肌肉等复杂固体
- 非弹性: `src/shared/physical_closure/materials/inelastic_solid.h`：塑性等非弹性行为

**片段**:
```cpp
shell_boundary.defineMaterial<LinearElasticSolid>(rho_s, Youngs_modulus, poisson_ratio);
```

**修改**:
- 修改杨氏模量: 调整第二个参数 (如 `1e3`, `1e6`)
- 修改泊松比: 调整第三个参数 (如 `0.3`, `0.45`)
- 使用超弹性: 将 `LinearElasticSolid` 改为 `NeoHookeanSolid`

---

### 粘性模型 (Viscosity)

**关键词**:
- 主: 设置流体粘性, 定义粘度, 非牛顿流体
- 别: 动力粘度, 运动粘度, 粘性系数

**定位**:
- 主: `src/shared/physical_closure/materials/viscosity.h`：`Viscosity` 类
- 非牛顿: `src/shared/particle_dynamics/fluid_dynamics/non_newtonian_dynamics.h`：非牛顿流体动力学

**修改**:
- 修改粘性系数: 在 `defineClosure<>` 中传递 `mu_f` 参数
- 计算雷诺数相关粘性: 使用公式 `mu_f = rho0_f * U_f * L / Re`

---

### 扩散-反应材料

**关键词**:
- 主: 设置扩散系数, 定义化学反应, 热传导
- 别: 浓度扩散, 电生理反应, 温度场

**定位**:
- 主: `src/shared/physical_closure/materials/diffusion_reaction.h`：`DiffusionReaction` 类
- 动力学: `src/shared/particle_dynamics/diffusion_reaction_dynamics/`：扩散反应动力学算法

**修改**:
- 参考案例: `tests/2d_examples/test_2d_diffusion*/` 扩散系列案例
- 电生理: `tests/2d_examples/test_2d_depolarization/` 去极化案例

---

## 4. 粒子动力学 (Particle Dynamics)

### 粒子动力学基类层次

**关键词**:
- 主: 粒子交互算法, 动力学计算, 物理过程求解
- 别: SPH 算子, 数值方法, 离散化算法

**定位**:
- 基类头文件: `src/shared/particle_dynamics/base_particle_dynamics.h`：`DataDelegateInner`, `DataDelegateContact`
- 汇总头文件: `src/shared/particle_dynamics/all_particle_dynamics.h`
- 实现文件: `src/shared/particle_dynamics/base_local_dynamics.h`：局部动力学接口

**片段**:
- **SimpleDynamics**: 无粒子交互 (如初始条件、体力)
- **InteractionDynamics**: 粒子间交互
- **ReduceDynamics**: 全局归约操作 (如时间步计算)

**修改**:
- 继承体系:
  ```
  ParticleDynamics (基类)
  ├── SimpleDynamics      # 例: InitialVelocity, GravityForce
  ├── InteractionDynamics # 例: ViscousForce, PressureRelaxation
  │   ├── InteractionWithUpdate
  │   └── InteractionSplit
  └── ReduceDynamics      # 例: AcousticTimeStep, MaximumSpeed
  ```

---

### 流体动力学算法

**关键词**:
- 主: 流体压力计算, 密度松弛, 粘性力, 速度梯度
- 别: Navier-Stokes 求解, 流体演化, 流动模拟

**定位**:
- 汇总头文件: `src/shared/particle_dynamics/fluid_dynamics/all_fluid_dynamics.h`
- 时间积分: `src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp`：`Integration1stHalf`, `Integration2ndHalf`
- 密度求和: `src/shared/particle_dynamics/fluid_dynamics/density_summation.hpp`：`DensitySummationComplex`
- 粘性力: `src/shared/particle_dynamics/fluid_dynamics/viscous_dynamics.hpp`：`ViscousForceWithWall`
- 时间步: `src/shared/particle_dynamics/fluid_dynamics/fluid_time_step.h`：`AcousticTimeStep`, `AdvectionViscousTimeStep`
- 边界: `src/shared/particle_dynamics/fluid_dynamics/all_fluid_boundaries.h`：流体边界条件
- 欧拉流: `src/shared/particle_dynamics/fluid_dynamics/all_eulerian_fluid_dynamics.h`：可压缩欧拉流动

**片段**:
```cpp
Dynamics1Level<fluid_dynamics::Integration1stHalfWithWallRiemann> pressure_relaxation(water_block_inner, water_block_contact);
Dynamics1Level<fluid_dynamics::Integration2ndHalfWithWallNoRiemann> density_relaxation(water_block_inner, water_block_contact);
InteractionWithUpdate<fluid_dynamics::ViscousForceWithWall> viscous_acceleration(water_block_inner, water_block_contact);
ReduceDynamics<fluid_dynamics::AcousticTimeStep> get_fluid_time_step_size(water_block);
```

**修改**:
- 修改压力松弛: 编辑 `src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp`
- 修改粘性算法: 编辑 `src/shared/particle_dynamics/fluid_dynamics/viscous_dynamics.hpp`
- 增加表面张力: 使用 `src/shared/particle_dynamics/fluid_dynamics/surface_tension.hpp`
- 修改速度修正: 编辑 `src/shared/particle_dynamics/fluid_dynamics/transport_velocity_correction.hpp`

**参考**: 构建指南§4.2.7 Dynamics定义、§4.3粒子动力学体系详解、§4.3.3流体动力学算法链、§11核心算法详解

---

### 固体动力学算法

**关键词**:
- 主: 结构应力计算, 弹性变形, 固体时间积分, 薄壳动力学
- 别: 结构力学求解, 固体演化, 变形分析

**定位**:
- 汇总头文件: `src/shared/particle_dynamics/solid_dynamics/all_solid_dynamics.h`
- 弹性动力学: `src/shared/particle_dynamics/solid_dynamics/elastic_dynamics.h`：弹性固体应力计算
- 薄结构: `src/shared/particle_dynamics/solid_dynamics/thin_structure_dynamics.h`：壳、板、梁动力学
- 约束: `src/shared/particle_dynamics/solid_dynamics/constraint_dynamics.hpp`：边界约束
- 接触: `src/shared/particle_dynamics/solid_dynamics/all_contact_dynamics.h`：固体接触
- 加载: `src/shared/particle_dynamics/solid_dynamics/loading_dynamics.h`：外部载荷
- FSI: `src/shared/particle_dynamics/solid_dynamics/fluid_structure_interaction.hpp`：流固耦合

**片段**:
```cpp
SimpleDynamics<thin_structure_dynamics::AverageShellCurvature> shell_curvature(shell_curvature_inner);
```

**修改**:
- 修改应力计算: 编辑 `elastic_dynamics.h` 中的应力更新方法
- 增加约束条件: 使用 `constraint_dynamics.hpp` 中的约束类
- 薄壳分析: 使用 `thin_structure_dynamics.h` 中的壳体算法

---

### 通用动力学算法

**关键词**:
- 主: 初始条件设置, 体力加载, 周期边界, 粒子排序
- 别: 通用物理过程, 辅助算法, 配置更新

**定位**:
- 汇总头文件: `src/shared/particle_dynamics/general_dynamics/all_general_dynamics.h`
- 外力: `src/shared/particle_dynamics/external_force/external_force.h`：`GravityForce`, `ExternalForce`
- 配置动力学: `src/shared/particle_dynamics/configuration_dynamics/all_configuration_dynamics.h`
- 粒子排序: `src/shared/particle_dynamics/configuration_dynamics/particle_sorting.h`：`ParticleSorting`

**片段**:
```cpp
Gravity gravity(Vecd(fx, 0.0));
SimpleDynamics<GravityForce<Gravity>> constant_gravity(water_block, gravity);
ParticleSorting particle_sorting(water_block);
```

**修改**:
- 修改重力方向: 编辑 `Gravity` 构造中的向量参数
- 增加粒子排序: 在主循环中定期调用 `particle_sorting.exec()`

---

### 扩散反应动力学

**关键词**:
- 主: 扩散方程求解, 化学反应, 热传导
- 别: 浓度演化, 电生理模拟, 温度场计算

**定位**:
- 汇总头文件: `src/shared/particle_dynamics/diffusion_reaction_dynamics/all_diffusion_reaction_dynamics.h`
- 扩散: `src/shared/particle_dynamics/diffusion_reaction_dynamics/diffusion_dynamics.h`
- 反应: `src/shared/particle_dynamics/diffusion_reaction_dynamics/reaction_dynamics.h`

**修改**:
- 参考扩散案例: `tests/2d_examples/test_2d_diffusion*/`

---

### 电生理动力学

**关键词**:
- 主: 心脏电活动, 去极化模拟, 电生理传播
- 别: 离子通道, 动作电位, 电兴奋传导

**定位**:
- 主: `src/shared/particle_dynamics/electro_physiology/electro_physiology.h`

**修改**:
- 参考案例: `tests/2d_examples/test_2d_depolarization/`, `tests/3d_examples/test_3d_heart_*/`

---

### 肌肉激活动力学

**关键词**:
- 主: 肌肉收缩模拟, 主动力产生, 肌纤维激活
- 别: 生物力学, 心肌收缩, 骨骼肌

**定位**:
- 主: `src/shared/particle_dynamics/active_muscle_dynamics/active_muscle_dynamics.h`

**修改**:
- 参考案例: `tests/3d_examples/test_3d_muscle_*/`, `tests/3d_examples/test_3d_heart_electromechanics/`

---

### 连续介质动力学

**关键词**:
- 主: 连续介质力学, 应力-应变关系, 本构模型
- 别: 固体流体统一框架, 广义连续介质

**定位**:
- 汇总头文件: `src/shared/particle_dynamics/continuum_dynamics/all_continuum_dynamics.h`
- 基础: `src/shared/particle_dynamics/continuum_dynamics/base_continuum_dynamics.h`
- 积分: `src/shared/particle_dynamics/continuum_dynamics/continuum_integration.h`

---

## 5. 时间积分方法

### Verlet 分步时间积分

**关键词**:
- 主: Verlet 时间推进, 分步积分, 压力松弛-密度松弛
- 别: 两步法, 预测-修正, 半步积分

**定位**:
- 流体第一半步: `src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp`：`Integration1stHalf`
- 流体第二半步: `src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp`：`Integration2ndHalf`
- 使用位置: 测试案例主循环中

**片段**:
```cpp
Dynamics1Level<fluid_dynamics::Integration1stHalfWithWallRiemann> pressure_relaxation(water_block_inner, water_block_contact);
Dynamics1Level<fluid_dynamics::Integration2ndHalfWithWallNoRiemann> density_relaxation(water_block_inner, water_block_contact);

// 主循环中:
pressure_relaxation.exec(dt);
constant_gravity.exec(dt);
density_relaxation.exec(dt);
```

**修改**:
- 修改第一半步: 编辑 `Integration1stHalf` 类 (更新速度、位置，使用压力/力)
- 修改第二半步: 编辑 `Integration2ndHalf` 类 (更新密度，使用速度散度)
- 选择是否使用黎曼求解器: 使用 `WithWallRiemann` 或 `WithWallNoRiemann` 版本

---

### 时间步长计算

**关键词**:
- 主: 计算时间步, CFL 条件, 声速时间步, 对流时间步
- 别: 自适应时间步, 稳定性时间步, dt 计算

**定位**:
- 声速时间步: `src/shared/particle_dynamics/fluid_dynamics/fluid_time_step.h`：`AcousticTimeStep`
- 对流粘性时间步: `src/shared/particle_dynamics/fluid_dynamics/fluid_time_step.h`：`AdvectionViscousTimeStep`
- 使用位置: 测试案例主循环中

**片段**:
```cpp
ReduceDynamics<fluid_dynamics::AcousticTimeStep> get_fluid_time_step_size(water_block);
ReduceDynamics<fluid_dynamics::AdvectionViscousTimeStep> get_fluid_advection_time_step_size(water_block, 1.5 * U_f);

// 主循环中:
Real Dt = get_fluid_advection_time_step_size.exec();  // 外层大时间步
Real dt = get_fluid_time_step_size.exec();            // 内层小时间步
```

**修改**:
- 修改 CFL 系数: 在时间步类的构造中调整系数参数
- 调整参考速度: 在 `AdvectionViscousTimeStep` 构造中传递不同的 `U_ref`
- 修改时间步公式: 编辑 `src/shared/particle_dynamics/fluid_dynamics/fluid_time_step.h`

---

## 6. 边界条件

### 周期边界条件

**关键词**:
- 主: 设置周期边界, 循环边界, 周期性流动
- 别: 周期域, 循环条件, 无限域模拟

**定位**:
- 主: `src/shared/particle_dynamics/general_dynamics/boundary_condition/`：边界条件相关
- 使用示例: `tests/2d_examples/test_2d_channel_flow_fluid_shell/channel_flow_shell.cpp` 第 220-221 行

**片段**:
```cpp
PeriodicAlongAxis periodic_along_x(water_block.getSPHBodyBounds(), xAxis);
PeriodicConditionUsingCellLinkedList periodic_condition(water_block, periodic_along_x);

// 初始化时:
sph_system.initializeSystemCellLinkedLists();
periodic_condition.update_cell_linked_list_.exec();  // 在配置构建前
sph_system.initializeSystemConfigurations();

// 主循环中:
periodic_condition.bounding_.exec();                 // 粒子位置周期化
water_block.updateCellLinkedList();
periodic_condition.update_cell_linked_list_.exec();  // 单元链表周期化
```

**修改**:
- 修改周期方向: 将 `xAxis` 改为 `yAxis` 或 `zAxis`
- 多方向周期: 创建多个 `PeriodicAlongAxis` 和 `PeriodicCondition` 对象

**参考**: 构建指南§5.4.1周期边界条件、§5.1.3关键代码解析、§3.5.4边界条件快速定位、§8-Q3周期边界如何应用

---

### 流入流出边界

**关键词**:
- 主: 入口速度条件, 出口压力条件, 粒子注入, 粒子删除
- 别: 开放边界, Dirichlet 边界, Neumann 边界

**定位**:
- 流体边界汇总: `src/shared/particle_dynamics/fluid_dynamics/all_fluid_boundaries.h`
- 发射器注入: 在 3D Poiseuille 案例中：`EmitterInflowInjection`
- 入流速度条件: `InflowVelocityCondition`
- 出流删除: `DisposerOutflowDeletion`

**片段**:
```cpp
// 定义入流速度函数
struct InflowVelocity {
    Vec3d operator()(Vec3d &position, Vec3d &velocity, Real current_time) {
        // 返回目标速度
    }
};

// 创建边界区域
AlignedBoxByParticle emitter(water_block, AlignedBox(...));
SimpleDynamics<fluid_dynamics::EmitterInflowInjection> emitter_inflow_injection(emitter, inlet_particle_buffer);

AlignedBoxByCell emitter_buffer(water_block, AlignedBox(...));
SimpleDynamics<fluid_dynamics::InflowVelocityCondition<InflowVelocity>> emitter_buffer_inflow_condition(emitter_buffer);

AlignedBoxByCell disposer(water_block, AlignedBox(...));
SimpleDynamics<fluid_dynamics::DisposerOutflowDeletion> disposer_outflow_deletion(disposer);
```

**修改**:
- 修改入流速度剖面: 编辑 `InflowVelocity::operator()` 中的速度计算公式
- 修改入流区域: 调整 `AlignedBox` 的位置和大小参数
- 修改出流区域: 调整 `disposer` 的 `AlignedBox` 定义

**参考**: 构建指南§5.4.3入流/出流边界条件、§3.5.4边界条件快速定位、§8-Q5入流出流如何处理

---

### 壁面边界条件

**关键词**:
- 主: 固壁边界, 无滑移壁面, 流固交互
- 别: 刚性壁面, 滑移/无滑移, 壁面粘性

**定位**:
- 流固接触关系: `src/shared/body_relations/contact_body_relation.h`：`ContactRelationFromShellToFluid`
- 壁面黎曼求解: 在积分算法中：`Integration1stHalfWithWallRiemann`
- 壁面粘性: `src/shared/particle_dynamics/fluid_dynamics/viscous_dynamics.hpp`：`ViscousForceWithWall`

**片段**:
```cpp
ContactRelationFromShellToFluid water_block_contact(water_block, {&wall_boundary}, {false});
Dynamics1Level<fluid_dynamics::Integration1stHalfWithWallRiemann> pressure_relaxation(water_block_inner, water_block_contact);
InteractionWithUpdate<fluid_dynamics::ViscousForceWithWall> viscous_acceleration(water_block_inner, water_block_contact);
```

**修改**:
- 法向修正: 调整 `ContactRelationFromShellToFluid` 构造中的 `{false}` 参数 (true 表示需要修正法向)
- 选择黎曼求解器: 使用 `WithWallRiemann` (高速流) 或 `WithWallNoRiemann` (低速流)

**参考**: 构建指南§5.4.2壁面边界条件、§3.5.4边界条件快速定位、§8-Q4壁面边界如何设置

---

### 扩散边界条件

**关键词**:
- 主: Neumann 边界, Robin 边界, Dirichlet 边界
- 别: 绝热边界, 热流边界, 固定浓度边界

**定位**:
- 扩散动力学: `src/shared/particle_dynamics/diffusion_reaction_dynamics/diffusion_dynamics.h`

**修改**:
- 参考案例: `tests/2d_examples/test_2d_diffusion_NeumannBC/`, `test_2d_diffusion_RobinBC/`

---

## 7. 体间关系 (Body Relations)

### 内部关系 (Inner Relation)

**关键词**:
- 主: 体内粒子交互, 自身邻居关系, 单体内部关系
- 别: 内部配置, 邻居搜索, 拓扑连接

**定位**:
- 主: `src/shared/body_relations/inner_body_relation.h`：`InnerRelation`
- 汇总头文件: `src/shared/body_relations/all_body_relations.h`
- 使用示例: 测试案例中的 `InnerRelation water_block_inner(water_block);`

**片段**:
```cpp
InnerRelation water_block_inner(water_block);
// 用于只涉及流体自身粒子交互的动力学
Dynamics1Level<...> pressure_relaxation(water_block_inner);
```

**修改**:
- 基本用法: 对每个需要粒子交互的体创建 `InnerRelation`

---

### 接触关系 (Contact Relation)

**关键词**:
- 主: 体间粒子交互, 流固接触, 多体耦合
- 别: 接触配置, 多体关系, 外部邻居

**定位**:
- 主: `src/shared/body_relations/contact_body_relation.h`：`ContactRelation`, `ContactRelationFromShellToFluid`
- 使用示例: 测试案例中的 `ContactRelation` 定义

**片段**:
```cpp
ContactRelationFromShellToFluid water_block_contact(water_block, {&wall_boundary}, {false});
ContactRelation fluid_observer_contact(fluid_observer, {&water_block});

// 用于涉及多个体的动力学
Dynamics1Level<...> pressure_relaxation(water_block_inner, water_block_contact);
```

**修改**:
- 流固接触: 使用 `ContactRelationFromShellToFluid`
- 观测体接触: 使用普通 `ContactRelation`
- 多个接触体: 在列表中添加多个体指针 `{&body1, &body2, ...}`

---

### 复合关系 (Complex Relation)

**关键词**:
- 主: 内部+接触关系, 复合拓扑, 多种交互
- 别: 组合关系, 混合关系

**定位**:
- 主: `src/shared/body_relations/complex_body_relation.h`：`ComplexRelation`
- 使用示例: `ComplexRelation water_block_complex(water_block_inner, water_block_contact);`

**片段**:
```cpp
ComplexRelation water_block_complex(water_block_inner, water_block_contact);
// 用于配置更新等需要同时考虑内部和接触的操作
water_block_complex.updateConfiguration();
```

**修改**:
- 基本用法: 组合已定义的 `InnerRelation` 和 `ContactRelation`
- 配置更新: 调用 `updateConfiguration()` 刷新邻居列表

---

### 壳体特殊关系

**关键词**:
- 主: 壳体曲率计算, 壳体-流体接触, 薄结构关系
- 别: 壳体内部关系, 表面关系

**定位**:
- 主: `src/shared/body_relations/`：`ShellInnerRelationWithContactKernel`
- 使用示例: 测试案例中的 `ShellInnerRelationWithContactKernel` 定义

**片段**:
```cpp
ShellInnerRelationWithContactKernel shell_curvature_inner(wall_boundary, water_block);
SimpleDynamics<thin_structure_dynamics::AverageShellCurvature> shell_curvature(shell_curvature_inner);
```

**修改**:
- 用于计算壳体曲率时需要考虑流体侧的核函数

---

## 8. 粒子生成器

### 晶格生成 (Lattice)

**关键词**:
- 主: 规则网格生成粒子, 晶格填充, 均匀分布粒子
- 别: 直角网格, 笛卡尔网格, 均匀粒子

**定位**:
- 汇总头文件: `src/shared/particle_generator/all_particle_generators.h`
- 晶格生成器: `src/shared/particle_generator/` 下的晶格相关文件
- 使用示例: `water_block.generateParticles<BaseParticles, Lattice>();`

**片段**:
```cpp
FluidBody water_block(sph_system, water_block_shape);
water_block.generateParticles<BaseParticles, Lattice>();
```

**修改**:
- 基本用法: 使用 `Lattice` 生成器自动填充封闭形状

**参考**: 构建指南§4.2.5 Body创建和粒子生成、§5.1.2完整代码示例

---

### 表面粒子生成

**关键词**:
- 主: 壳体粒子生成, 表面离散化, 薄壁粒子
- 别: 壳粒子, 面元粒子, 曲面粒子

**定位**:
- 使用示例: 测试案例中的自定义 `ParticleGenerator` 特化

**片段**:
```cpp
// 自定义粒子生成器特化
class WallBoundary;
template <>
class ParticleGenerator<SurfaceParticles, WallBoundary> : public ParticleGenerator<SurfaceParticles> {
    void prepareGeometricData() override {
        // 手动添加粒子位置、法向、厚度
        addPositionAndVolumetricMeasure(position, volume);
        addSurfaceProperties(normal, thickness);
    }
};

// 使用
wall_boundary.generateParticles<SurfaceParticles, WallBoundary>(resolution_ref, wall_thickness);
```

**修改**:
- 修改粒子分布: 编辑 `prepareGeometricData()` 中的循环逻辑
- 修改法向: 调整 `addSurfaceProperties()` 中的法向向量计算
- 修改厚度: 调整 `shell_thickness` 参数

**参考**: 构建指南§5.2.2关键代码段、§3.5.6自定义粒子生成器、§8-Q7壳层法向方向

---

### 观测粒子生成

**关键词**:
- 主: 定义观测点坐标, 手动指定位置, 探针布置
- 别: 监测点生成, 采样点设置

**定位**:
- 使用示例: 测试案例中的辅助函数 (如 `createFluidAxialObservationPoints()`)

**片段**:
```cpp
StdVec<Vecd> createFluidAxialObservationPoints(Real resolution_ref) {
    StdVec<Vecd> observation_points;
    for (size_t i = 0; i < number_observation_points; ++i) {
        Vec2d point_coordinate(x, y);
        observation_points.push_back(point_coordinate);
    }
    return observation_points;
}

ObserverBody fluid_observer(sph_system, Observer);
fluid_observer.generateParticles<ObserverParticles>(createFluidAxialObservationPoints(resolution_ref));
```

**修改**:
- 修改观测点位置: 编辑辅助函数中的坐标计算
- 修改观测点数量: 调整循环次数

---

### 粒子松弛生成

**关键词**:
- 主: 粒子松弛优化, 初始粒子分布优化, 预处理粒子
- 别: 粒子重排, 初始化松弛

**定位**:
- 汇总头文件: `src/shared/particle_dynamics/relax_dynamics/`：粒子松弛动力学

**修改**:
- 参考案例: `tests/3d_examples/test_3d_particle_relaxation/`

**参考**: 构建指南§5.3.3粒子松弛流程、§3.5.6粒子松弛与重载、§4.2.3.2 Level Set几何定义

---

## 9. SPH 核函数 (Kernels)

### 核函数类型

**关键词**:
- 主: 选择 SPH 核函数, 光滑核, 权重函数
- 别: 插值核, 平滑函数, 影响函数

**定位**:
- 汇总头文件: `src/shared/kernels/all_kernels.h`
- 基类: `src/shared/kernels/base_kernel.h`：`Kernel` 基类
- 三次 B 样条: `src/shared/kernels/kernel_cubic_B_spline.h`：`KernelCubicBSpline` (默认)
- Wendland C2: `src/shared/kernels/kernel_wendland_c2.h`：`KernelWendlandC2`
- 双曲核: `src/shared/kernels/kernel_hyperbolic.h`
- 二次核: `src/shared/kernels/kernel_quadratic.h`
- Laguerre-Gauss: `src/shared/kernels/kernel_laguerre_gauss.h`
- 表格核: `src/shared/kernels/kernel_tabulated.h`：预计算核
- 各向异性核: `src/shared/kernels/anisotropic_kernel.h`

**片段**:
- 默认使用三次 B 样条核，无需显式指定
- 特殊需求时在 SPH 系统或自适应中指定

**修改**:
- 修改核函数类型: 在 SPH 系统或自适应对象构造时指定不同的核类型
- 查看核函数性质: 各核函数文件中定义了支持半径、核值计算等

---

## 10. 几何形状与网格

### 几何形状定义

**关键词**:
- 主: 定义仿真域形状, 几何建模, 创建复杂形状
- 别: 形状定义, 区域划分, 几何体

**定位**:
- 汇总头文件: `src/shared/geometries/all_geometries.h`
- 基础几何: `src/shared/geometries/base_geometry.h`
- 几何形状: `src/shared/geometries/geometric_shape.h`：基本几何体 (球、盒、圆柱等)
- 复杂几何: `src/shared/geometries/complex_geometry.h`：组合几何体
- 水平集: `src/shared/geometries/level_set.h`, `level_set_shape.h`：水平集方法
- 几何元素: `src/shared/geometries/geometric_element.h`
- 变换几何: `src/shared/geometries/transform_geometry.h`
- 映射形状: `src/shared/geometries/mapping_shape.h`

**片段**:
```cpp
// 多边形形状
class WaterBlock : public MultiPolygonShape {
    explicit WaterBlock(const std::vector<Vecd> &shape, const std::string &shape_name)
        : MultiPolygonShape(shape_name) {
        multi_polygon_.addAPolygon(shape, ShapeBooleanOps::add);
    }
};

// 复杂形状组合
auto water_block_shape = makeShared<ComplexShape>(WaterBody);
water_block_shape->add<TriangleMeshShapeCylinder>(...);

// 默认形状 (用于手动粒子生成)
SolidBody wall(sph_system, makeShared<DefaultShape>(Wall));
```

**修改**:
- 定义 2D 多边形: 创建顶点列表，使用 `MultiPolygonShape`
- 定义 3D 几何: 使用 `ComplexShape` 添加基本几何体 (如 `TriangleMeshShapeCylinder`)
- 布尔运算: 使用 `ShapeBooleanOps::add`, `subtract`, `intersect`

**参考**: 构建指南§4.2.3几何形状定义、§4.2.3.2 Level Set几何定义、§3.5.2材料与几何

---

### 网格与单元链表

**关键词**:
- 主: 背景网格, 单元链表, 邻居搜索网格
- 别: 空间分割, 网格加速, 桶排序

**定位**:
- 基础网格: `src/shared/meshes/base_mesh.h`
- 单元链表: `src/shared/meshes/cell_linked_list.h`：`CellLinkedList`
- 网格迭代器: `src/shared/meshes/mesh_iterators.h`
- 稀疏网格: `src/shared/meshes/sparse_storage_mesh/`：数据包网格

**修改**:
- 网格自动管理: SPH 系统根据分辨率自动创建和更新
- 手动更新: 在主循环中调用 `body.updateCellLinkedList()`

---

## 11. 输入输出系统 (I/O)

### VTP 文件输出 (ParaView)

**关键词**:
- 主: 输出仿真结果, 导出 VTP 文件, ParaView 可视化
- 别: 保存状态, 写入文件, 结果输出

**定位**:
- 汇总头文件: `src/shared/io_system/all_io.h`
- VTP 输出: `src/shared/io_system/io_vtk.h`：`BodyStatesRecordingToVtp`
- VTK 网格: `src/shared/io_system/io_vtk_mesh.h`
- 观测输出: `src/shared/io_system/io_observation.h`：`ObservedQuantityRecording`
- PLT 输出: `src/shared/io_system/io_plt.h`：Tecplot 格式
- 日志: `src/shared/io_system/io_log.h`

**片段**:
```cpp
BodyStatesRecordingToVtp write_real_body_states(sph_system);
write_real_body_states.addToWrite<Real>(wall_boundary, Average1stPrincipleCurvature);

// 主循环中
write_real_body_states.writeToFile();        // 自动递增时间步
write_real_body_states.writeToFile(0);       // 指定时间步号
```

**修改**:
- 增加输出变量: 使用 `addToWrite<Type>(body, VariableName)`
- 修改输出频率: 调整主循环中的 `output_interval` 或输出条件
- 输出位置: 默认输出到 `output/` 目录下

**参考**: 构建指南§7.2数据输出和可视化、§3.5.5观测与输出、§4.2.9主时间循环

---

### 观测数据输出

**关键词**:
- 主: 导出观测点数据, 探针数据输出, 时间历程数据
- 别: 监测数据, 采样输出, 点数据

**定位**:
- 主: `src/shared/io_system/io_observation.h`：`ObservedQuantityRecording`
- 使用示例: 测试案例中的 `write_fluid_velocity`

**片段**:
```cpp
ObservedQuantityRecording<Vecd> write_fluid_velocity(Velocity, fluid_observer_contact);

// 主循环中
fluid_observer_contact.updateConfiguration();          // 先更新观测体配置
write_fluid_velocity.writeToFile(number_of_iterations); // 输出到文件
```

**修改**:
- 修改观测变量: 将 `Velocity` 改为其他变量名 (如 `Pressure`, `Density`)
- 输出多个变量: 创建多个 `ObservedQuantityRecording` 对象

**参考**: 构建指南§7.1添加观测点、§7.2数据输出和可视化、§3.5.5观测与输出

---

### SimBody 输出 (多体动力学)

**关键词**:
- 主: 导出多体动力学数据, SimBody 状态输出
- 别: 刚体运动输出, 关节状态

**定位**:
- 主: `src/shared/io_system/io_simbody.h`
- SimBody 集成: `src/shared/simbody_sphinxsys/`：SPH 与 SimBody 的集成

**修改**:
- 参考案例: 包含多体动力学的测试案例

---

## 12. 测试案例库

### 2D 流体案例

**关键词**:
- 主: 2D 流动模拟案例, 二维流体算例, 平面流动
- 别: 2D 示例, 二维测试

**定位**:
- 目录: `tests/2d_examples/`
- 案例数量: 约 69 个案例

**典型案例**:
- **通道流 + 壳体**: `test_2d_channel_flow_fluid_shell/`：Poiseuille 流动，流固交互
- **溃坝**: `test_2d_dambreak/`：经典溃坝问题
- **翼型绕流**: `test_2d_airfoil/`：翼型空气动力学
- **圆柱绕流**: `test_2d_flow_around_cylinder/`：卡门涡街
- **液滴冲击**: `test_2d_droplet_impact/`：表面张力
- **扩散系列**: `test_2d_diffusion*/`：各类边界条件的扩散问题
- **弹性门**: `test_2d_elastic_gate/`：FSI 问题
- **欧拉流动**: `test_2d_eulerian_*/`：可压缩流动
- **激波管**: `test_1d_shock_tube/`：1D 激波问题

**修改**:
- 学习流程: 从简单案例 (如 `test_2d_channel_flow_fluid_shell`) 开始
- 创建新案例: 复制相似案例，修改几何、材料、边界条件

---

### 3D 流体案例

**关键词**:
- 主: 3D 流动模拟案例, 三维流体算例, 空间流动
- 别: 3D 示例, 三维测试

**定位**:
- 目录: `tests/3d_examples/`
- 案例数量: 约 41 个案例

**典型案例**:
- **Poiseuille 流 + 壳体**: `test_3d_poiseuille_flow_shell/`：3D 管流，流固交互
- **FVM 通道流**: `test_3d_FVM_incompressible_channel_flow/`：FVM 兼容性
- **溃坝**: `test_3d_dambreak/`, `test_3d_dambreak_elastic_plate_shell/`：3D 溃坝及 FSI
- **心脏模拟**: `test_3d_heart_*/`：电生理、机械耦合
- **肌肉激活**: `test_3d_muscle_*/`：主动肌肉动力学
- **结构力学**: `test_3d_arch/`, `test_3d_beam_*/`, `test_3d_*_plate/`：固体力学

**修改**:
- 3D 特殊性: 注意 3D 的计算量，调整分辨率和结束时间
- 并行加速: 使用 TBB 并行，考虑 SYCL 加速

---

### 优化案例

**关键词**:
- 主: 形状优化案例, 拓扑优化, 参数优化
- 别: 优化算例, 反问题求解

**定位**:
- 目录: `tests/optimization/`
- 优化动力学: `src/shared/particle_dynamics/diffusion_optimization_dynamics/`：优化算法

**修改**:
- 参考优化案例进行目标驱动的设计优化

---

### 单元测试

**关键词**:
- 主: 单元测试, 功能测试, 模块测试
- 别: UT, Google Test

**定位**:
- 目录: `tests/unit_tests_src/`

**修改**:
- 使用 Google Test 框架进行功能验证

---

## 13. 构建系统与配置

### CMake 构建配置

**关键词**:
- 主: 配置编译选项, CMake 设置, 构建系统
- 别: 编译配置, 构建脚本

**定位**:
- 根 CMakeLists: `CMakeLists.txt`：项目主构建文件
- CMake 模块: `cmake/`：查找依赖、编译选项等
- 测试案例 CMake: `tests/2d_examples/test_*/CMakeLists.txt`：各案例的构建脚本

**片段**:
```cmake
# 典型测试案例 CMakeLists.txt
STRING(REGEX REPLACE .*/(.*) \\1 CURRENT_FOLDER ${CMAKE_CURRENT_SOURCE_DIR})
PROJECT(${CURRENT_FOLDER})

set(DIR_SRCS your_case.cpp)
add_executable(${PROJECT_NAME} ${DIR_SRCS})
target_link_libraries(${PROJECT_NAME} sphinxsys_2d)  # 或 sphinxsys_3d
```

**修改**:
- 启用 2D: `cmake -DSPHINXSYS_2D=ON ..`
- 启用 3D: `cmake -DSPHINXSYS_3D=ON ..`
- 启用测试: `cmake -DSPHINXSYS_BUILD_TESTS=ON ..`
- 使用浮点: `cmake -DSPHINXSYS_USE_FLOAT=ON ..`
- 启用 SYCL: `cmake -DSPHINXSYS_USE_SYCL=ON ..` (需 Intel LLVM 编译器)
- OpenCASCADE: `cmake -DSPHINXSYS_MODULE_OPENCASCADE=ON ..`

**参考**: 构建指南§6 CMakeLists.txt配置指南、§6.1标准2D案例模板、§6.2标准3D案例模板、§6.4关键配置项说明

---

### 维度处理机制

**关键词**:
- 主: 2D/3D 代码分离, 维度相关代码, 维度适配
- 别: 维度处理, 2D3D 统一

**定位**:
- 共享代码: `src/shared/`：2D 和 3D 共享的代码
- 2D 专用: `src/for_2D_build/`：2D 特化实现
- 3D 专用: `src/for_3D_build/`：3D 特化实现
- 类型别名: 通过 `Vecd` (Vec2d/Vec3d), `Real` 等类型别名处理维度差异

**修改**:
- 共享逻辑: 放在 `src/shared/`
- 维度特定: 创建同名目录/文件在 `for_2D_build/` 和 `for_3D_build/`

---

### 依赖库管理

**关键词**:
- 主: 安装依赖库, vcpkg 管理, 第三方库
- 别: 依赖项, 外部库

**定位**:
- 文档: `README.md`, `CLAUDE.md` 中列出依赖
- vcpkg 清单: 如果使用 vcpkg manifest 模式

**必需依赖**:
- **Simbody**: 多体动力学
- **Eigen3**: 线性代数
- **TBB**: 并行计算
- **Boost**: 几何和程序选项
- **spdlog**: 日志记录
- **Google Test**: 测试框架

**修改**:
- 使用 vcpkg: `vcpkg install simbody eigen3 tbb boost-geometry boost-program-options spdlog gtest`
- 或使用系统包管理器安装

---

## 14. Python 接口

### Python 绑定

**关键词**:
- 主: Python API, Python 脚本调用, Python 接口
- 别: pybind11, Python 绑定

**定位**:
- Python 脚本: `PythonScriptStore/`：Python 工具和回归测试
- 回归测试: `PythonScriptStore/RegressionTest/`：自动化回归测试脚本
- 测试案例: `tests/test_python_interface/`

**修改**:
- 运行回归测试: `python PythonScriptStore/RegressionTest/regression_test_base_tool.py`

---

## 15. 优化与自适应

### 自适应分辨率

**关键词**:
- 主: 自适应网格, 变分辨率, 局部加密
- 别: AMR, 自适应细化

**定位**:
- 自适应: `src/shared/adaptations/adaptation.h`：`SPHAdaptation` 自适应策略

**片段**:
```cpp
shell_boundary.defineAdaptation<SPH::SPHAdaptation>(1.15, resolution_ref / resolution_shell);
```

**修改**:
- 修改自适应参数: 调整自适应构造中的系数

---

### 粒子排序优化

**关键词**:
- 主: 粒子重排序, 缓存优化, 空间局部性
- 别: Z 曲线排序, 性能优化

**定位**:
- 主: `src/shared/particle_dynamics/configuration_dynamics/particle_sorting.h`：`ParticleSorting`

**片段**:
```cpp
ParticleSorting particle_sorting(water_block);

// 主循环中定期执行
if (number_of_iterations % 100 == 0 && number_of_iterations != 1) {
    particle_sorting.exec();
}
```

**修改**:
- 修改排序频率: 调整主循环中的排序条件 (如每 100 步或 200 步)
- 排序后刷新: 调用 `updateCellLinkedList()` 和 `updateConfiguration()`

---

### SYCL 加速

**关键词**:
- 主: GPU 加速, SYCL 并行, 异构计算
- 别: Intel GPU, OneAPI, 加速计算

**定位**:
- SYCL 头文件: `src/shared/include/sphinxsys.h` 中的 `#if SPHINXSYS_USE_SYCL` 部分
- SYCL 实现: `src/shared/shared_ck/`：SYCL 计算核
- 编译选项: `cmake -DSPHINXSYS_USE_SYCL=ON`

**修改**:
- 需要 Intel LLVM 编译器和 OneAPI
- 启用 SYCL: 在 CMake 配置时添加 `-DSPHINXSYS_USE_SYCL=ON`

---

## 16. 回归测试与 CI/CD

### Google Test 集成

**关键词**:
- 主: 自动化验证, 单元测试, 集成测试
- 别: GTest, 测试框架, 断言验证

**定位**:
- 测试宏: `#include <gtest/gtest.h>`
- 测试定义: 各测试案例的 `TEST()` 宏
- 主函数: `testing::InitGoogleTest(&ac, av); return RUN_ALL_TESTS();`

**片段**:
```cpp
#include <gtest/gtest.h>

TEST(test_suite_name, test_case_name) {
    // 仿真代码
    // ...

    // 验证
    EXPECT_NEAR(simulation_value, analytical_value, tolerance);
    EXPECT_LT(error, max_error);
}

int main(int ac, char *av[]) {
    testing::InitGoogleTest(&ac, av);
    return RUN_ALL_TESTS();
}
```

**修改**:
- 增加验证: 使用 `EXPECT_*` 或 `ASSERT_*` 宏
- 创建多个测试: 定义多个 `TEST()` 块
- 禁用测试: 使用 `TEST(DISABLED_suite, case)` 前缀

**参考**: 构建指南§6.3 Google Test集成模板、§7.3 Google Test集成方法、§5.2.2关键代码段

---

### CI/CD 流程

**关键词**:
- 主: 持续集成, 自动化测试, GitHub Actions
- 别: CI 流水线, 自动构建

**定位**:
- CI 配置: `.github/workflows/ci.yml`：GitHub Actions 工作流
- 回归测试: `PythonScriptStore/RegressionTest/`：Python 回归测试脚本

**修改**:
- 触发条件: 推送到 master 或针对 master 的 PR
- 测试平台: Linux, Windows, macOS
- 测试内容: 2D/3D 构建、测试运行、SYCL 加速测试

---

## 17. 常见问题快速定位

### 如何修改流体速度

**定位**:
- 初始速度: 创建继承自 `fluid_dynamics::FluidInitialCondition` 的类，在 `update()` 中设置 `vel_[index_i]`
- 入流速度: 定义 `InflowVelocity` 函数对象，在 `operator()` 中返回目标速度
- 示例: `tests/2d_examples/test_2d_channel_flow_fluid_shell/channel_flow_shell.cpp` 第 115-127 行

**参考**: 构建指南§5.2.2初始速度条件、§5.4.3入流速度定义、§3.5.6自定义初始条件、§8-Q6如何添加自定义初始条件

---

### 如何修改材料属性

**定位**:
- 流体: 在 `defineClosure<WeaklyCompressibleFluid, ...>` 中修改 `rho0_f`, `c_f`, `mu_f`
- 固体: 在 `defineMaterial<LinearElasticSolid>` 中修改 `E`, `nu`
- 示例: 测试案例的材料参数定义部分

**参考**: 构建指南§4.2.2材料参数定义、§3.5.1基础设置、§3.5.2材料与几何

---

### 如何修改边界条件

**定位**:
- 周期边界: 使用 `PeriodicConditionUsingCellLinkedList`
- 入流出流: 使用 `EmitterInflowInjection`, `InflowVelocityCondition`, `DisposerOutflowDeletion`
- 壁面: 使用 `ContactRelationFromShellToFluid` + `WithWall*` 动力学
- 示例: 各测试案例的边界条件部分

**参考**: 构建指南§5.4边界条件完整指南、§5.4.5边界条件选择决策树、§3.5.4边界条件快速定位、§8常见问题FAQ

---

### 如何修改时间步长

**定位**:
- 自动计算: `ReduceDynamics<fluid_dynamics::AcousticTimeStep>` 和 `AdvectionViscousTimeStep`
- 手动设置: 直接在主循环中赋值 `Real dt = ...;`
- CFL 系数: 在时间步类内部调整
- 示例: 测试案例主循环中的时间步计算

**参考**: 构建指南§4.2.7时间步长计算、§4.2.9主时间循环、§3.5.3动力学算法、§11.1.1时间步长计算

---

### 如何输出更多变量

**定位**:
- 体状态: `write_real_body_states.addToWrite<Type>(body, VariableName)`
- 观测点: 创建 `ObservedQuantityRecording<Type>` 对象
- 示例: 测试案例的 I/O 定义部分

**参考**: 构建指南§7.2数据输出和可视化、§7.1添加观测点、§3.5.5观测与输出

---

### 如何创建新的测试案例

**定位**:
1. 创建目录: `tests/2d_examples/test_my_case/`
2. 创建源文件: `my_case.cpp`
3. 创建 CMakeLists.txt (参考现有案例)
4. 包含头文件: `#include sphinxsys.h`
5. 定义几何、材料、边界条件
6. 主循环中执行动力学
7. Google Test 验证

**参考**: 构建指南§4主程序编写指南、§5典型案例模式、§6 CMakeLists.txt配置指南、§9参考案例索引、§13.2推荐学习路径

---

## 附录: 文件路径速查表

### 核心头文件
- **总入口**: `src/shared/include/sphinxsys.h`
- **体类型**: `src/shared/bodies/all_bodies.h`
- **材料**: `src/shared/physical_closure/all_closures.h`
- **动力学**: `src/shared/particle_dynamics/all_physical_dynamics.h`
- **流体**: `src/shared/particle_dynamics/fluid_dynamics/all_fluid_dynamics.h`
- **固体**: `src/shared/particle_dynamics/solid_dynamics/all_solid_dynamics.h`
- **I/O**: `src/shared/io_system/all_io.h`
- **核函数**: `src/shared/kernels/all_kernels.h`
- **几何**: `src/shared/geometries/all_geometries.h`

### 典型测试案例
- **2D 通道流**: `tests/2d_examples/test_2d_channel_flow_fluid_shell/channel_flow_shell.cpp`
- **3D Poiseuille**: `tests/3d_examples/test_3d_poiseuille_flow_shell/poiseuille_flow_shell.cpp`
- **3D FVM**: `tests/3d_examples/test_3d_FVM_incompressible_channel_flow/`

---

## 使用建议

### 对于初学者
1. 从阅读 `CLAUDE.md` 和 `README.md` 开始
2. 学习简单的 2D 案例 (如 `test_2d_channel_flow_fluid_shell`)
3. 理解 SPHinXsys 的工作流程: 几何 → 体 → 材料 → 关系 → 动力学 → 初始化 → 主循环
4. 修改参数 (分辨率、材料属性) 观察效果

### 对于开发者
1. 熟悉两组件设计: 建模类 (数据结构) + 物理动力学 (算法)
2. 掌握维度处理机制: `src/shared/`, `src/for_2D_build/`, `src/for_3D_build/`
3. 遵循 Google C++ 风格指南
4. 使用 Google Test 进行验证
5. 查看 API 文档: https://xiangyu-hu.github.io/SPHinXsys/

### 对于 AI 辅助编程
1. 引用本文档时使用精确的功能描述 (如 修改流体粘性)
2. 本文档提供的代码位置可直接用于定位修改点
3. 结合测试案例理解完整工作流
4. 使用 Google Test 验证修改正确性

---

**文档版本**: 1.0
**生成日期**: 2025-10-17
**基于代码版本**: SPHinXsys master branch (commit 8c31d5ea2)
**维护建议**: 随 SPHinXsys 版本更新定期刷新此文档
