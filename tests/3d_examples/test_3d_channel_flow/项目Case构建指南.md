# SPHinXsys 项目 Case 构建指南

> **文档版本**: v1.1
> **更新日期**: 2025-10-20
> **适用版本**: SPHinXsys master 分支

---

## 目录

- [1. 文档定位](#1-文档定位)
- [2. 案例骨架](#2-案例骨架)
- [3. 计算流程骨架](#3-计算流程骨架)
- [4. 核心组件与函数调用](#4-核心组件与函数调用)
  - [4.1 系统与 Body](#41-系统与-body)
  - [4.2 材料与几何](#42-材料与几何)
  - [4.3 粒子生成策略](#43-粒子生成策略)
  - [4.4 Body 关系](#44-body-关系)
  - [4.5 动力学模块](#45-动力学模块)
  - [4.6 时间步长与稳定性](#46-时间步长与稳定性)
  - [4.7 边界与约束模块](#47-边界与约束模块)
- [5. 主循环策略](#5-主循环策略)
- [6. 输出与验证](#6-输出与验证)
- [7. 典型案例模板](#7-典型案例模板)
  - [7.1 2D 纯流体](#71-2d-纯流体)
  - [7.2 流体-壳层耦合](#72-流体-壳层耦合)
  - [7.3 流体-固体耦合](#73-流体-固体耦合)
  - [7.4 3D 扩展要点](#74-3d-扩展要点)
- [8. 参数计算速查](#8-参数计算速查)
- [9. 常见问题与排错](#9-常见问题与排错)
- [10. 快速参考清单](#10-快速参考清单)

---

## 1. 文档定位

该指南聚焦 SPHinXsys 案例的计算流程与关键函数调用，帮助开发者在最短时间内完成案例脚本的搭建、校验及迭代。

**快速上手清单**

- 明确案例物理类型：纯流体 / 流固耦合 / 壳层 / 3D。
- 准备几何与材料参数，确认分辨率 `resolution_ref` 与声速 `c_f`。
- 选定合适的粒子生成方式与动力学组合，预估输出需求。

## 2. 案例骨架

标准案例目录至少包含以下文件：

```text
test_case_name/
├─ case_name.cpp        # 主程序
├─ CMakeLists.txt       # 构建脚本
├─ input/               # 可选：网格、初值
└─ regression_test_tool/ # 可选：回归数据
```

**命名规范**

- 目录：`test_2d_description`、`test_3d_description`。
- 源文件：下划线分隔，例 `poiseuille_flow.cpp`。
- 类名遵循 PascalCase，变量使用 snake_case。

## 3. 计算流程骨架

1. 定义几何与材料参数。
2. 构建 `SPHSystem` 并设置运行模式（粒子松弛、重载）。
3. 创建各类 `Body`，绑定材料、粒子生成方式。
4. 声明 Body 关系（Inner/Contact/Complex）。
5. 配置动力学模块（Simple/InteractionWithUpdate/Reduce/Dynamics1Level）。
6. 初始化系统网格与拓扑。
7. 进入主时间循环，依次执行：
   - 预处理与时间步长计算
   - 动力学求解（压力/速度松弛等）
   - 状态更新与输出
8. 结束前执行必要的资源释放或统计输出。

**最小示例**

```cpp
int main(int ac, char* av[]) {
    SPHSystem sph_system(system_domain_bounds, resolution_ref);
    sph_system.setRunParticleRelaxation(true);

    FluidBody water_block(sph_system, makeShared<WaterBlock>("WaterBody"));
    water_block.defineClosure<WeaklyCompressibleFluid, Viscosity>(rho0_f, c_f, mu_f);
    water_block.generateParticles<BaseParticles, Lattice>();

    InnerRelation water_inner(water_block);
    SimpleDynamics<GravityForce<Gravity>> apply_gravity(water_block, gravity);
    ReduceDynamics<fluid_dynamics::AcousticTimeStep> get_time_step(water_block);
    Dynamics1Level<fluid_dynamics::Integration1stHalfRiemann> pressure_relaxation(water_inner);

    BodyStatesRecordingToVtp write_vtp(sph_system);

    sph_system.initializeSystemCellLinkedLists();
    sph_system.initializeSystemConfigurations();

    while (physical_time < end_time) {
        Real dt = get_time_step.exec();
        pressure_relaxation.exec(dt);
        apply_gravity.exec(dt);
        water_block.updateCellLinkedList();
        write_vtp.writeToFile(physical_time);
    }
    return 0;
}
```

## 4. 核心组件与函数调用

### 4.1 系统与 Body

| 步骤 | 函数 / 类 | 说明 | 关键注意事项 |
|------|------------|------|--------------|
| 创建系统 | `SPHSystem(bounds, resolution)` | 初始化背景网格与时间管理 | `bounds` 必须覆盖所有 Body；`resolution` 取决于最细结构 |
| 模式设置 | `setRunParticleRelaxation(bool)`<br>`setReloadParticles(bool)` | 控制粒子松弛 / 重载流程 | 首次运行通常 `true, false`；重载阶段切换 |
| 物理体定义 | `FluidBody` / `SolidBody` / `ObserverBody` | 继承 `RealBody` | Name 唯一；Observer 仅记录数据 |
| 自适应网格 | `ParticleAdaptation`, `AdaptiveInnerBody` | 控制支持区域和核函数 | 粗细比需与 `defineAdaptationRatios` 保持一致 |

### 4.2 材料与几何

| 目标 | 常用 API | 场景 | 备注 |
|------|----------|------|------|
| 流体材料 | `defineClosure<WeaklyCompressibleFluid, Viscosity>(rho0, c_f, mu_f)` | 绝大多数弱可压缩流 | 可附加 `DensitySummation`、`EquationOfState` 参数 |
| 弹性固体 | `defineMaterial<LinearElasticSolid>(rho0, E, nu)`<br>`defineMaterial<NeoHookeanSolid>(...)` | 壳层、固体案例 | 与 `SolidParticles` 配合 |
| 几何（多边形） | 继承 `MultiPolygonShape`，调用 `addAPolygon`/`addACircle` | 2D 几何 | 顶点顺序需闭合 |
| 几何（布尔） | 继承 `ComplexShape`，组合 `add<GeometricShapeBox>` 等 | 孔洞、组合体 | 使用 `Transform` 控制坐标 |
| Level Set | `defineBodyLevelSetShape()`<br>`defineAdaptationRatios(boundary, interior)` | 复杂边界、3D | 必须在 `generateParticles` 前调用 |

### 4.3 粒子生成策略

| 策略 | 调用 | 适用阶段 | 特点 |
|------|------|----------|------|
| 规则格点 | `generateParticles<BaseParticles, Lattice>()` | 初次模拟 | 稳定、适合弱可压缩流 |
| 随机扰动 | `SimpleDynamics<RandomizeParticlePosition>` | 松弛前 | 打破对称、提高稳定性 |
| 粒子松弛 | `sph_system.setRunParticleRelaxation(true)`<br>`BodyParticlesRelaxation` | 结构体、固体 | 输出 reload 文件 |
| 重载粒子 | `generateParticles<BaseParticles, Reload>(body_name)` | 松弛后正式运行 | 需 `setReloadParticles(true)` 并确保 reload 数据存在 |

### 4.4 Body 关系

| 类型 | 类 | 作用 | 典型用途 |
|------|----|------|----------|
| 内部关系 | `InnerRelation` | 同一 Body 内部邻接 | 密度、压力松弛 |
| 接触关系 | `ContactRelation` / `ContactRelationFromShellToFluid` | 不同 Body 接触交互 | 流固/流壳耦合 |
| 复杂关系 | `ComplexRelation(inner, contact)` | 同时处理内外相互作用 | 边界层、FSI |
| Observer 关系 | `ContactRelation(observer, {&body})` | 观测点与主体关联 | 输出速度、压力 |

### 4.5 动力学模块

| 分类 | 代表 API | 主要任务 | 常见组合 |
|------|----------|----------|----------|
| 简单动力学 | `SimpleDynamics<GravityForce<Gravity>>`<br>`SimpleDynamics<InitialCondition>` | 外力、初值、边界刷新 | 重力 + 初始速度 |
| 相互作用更新 | `InteractionWithUpdate<fluid_dynamics::DensitySummationComplex>`<br>`InteractionWithUpdate<fluid_dynamics::ViscousForceWithWall>` | 粒子交互并更新属性 | 密度求和 + 粘性 |
| 约简动力学 | `ReduceDynamics<fluid_dynamics::AcousticTimeStep>`<br>`ReduceDynamics<MaximumSpeed>` | 计算全局量（dt、极值） | 声学时间步 + 皮卡数监控 |
| 单层动力学 | `Dynamics1Level<fluid_dynamics::Integration1stHalfRiemann>`<br>`Dynamics1Level<fluid_dynamics::Integration2ndHalfRiemann>` | 时间积分主干 | 第一半步 + 第二半步 |
| 多级算法 | `DynamicsSum`, `CombinedDynamics` | 自定义组合 | 复杂耦合流程 |

### 4.6 时间步长与稳定性

- 声学时间步 (`AcousticTimeStep`): `dt = CFL * h / (c + 1.2 * max|u|)`，适用于弱可压缩流体。
- 对流/粘性时间步 (`AdvectionViscousTimeStep`): 根据 `dt = CFL * h^2 / (nu + eps)` 估算，常用于高粘度或固体松弛。
- 建议在主循环中取 `dt = min(dt_acoustic, dt_viscous)` 并限制 `physical_time += dt;
iteration++`。

### 4.7 边界与约束模块

| 功能 | API | 说明 |
|------|-----|------|
| 周期边界 | `PeriodicConditionInAxisDirection` | 创建、拓展并调用 `bounding_.update()` |
| 固壁边界 | `TriangleMeshShapeSTL` + `ComplexShape` | STL 导入或布尔运算形成壁体 |
| 入流/出流 | `EmitterInflowInjection`、`InflowVelocityCondition`、`DisposerOutflowDeletion` | 配合 buffer body 使用 |
| 结构约束 | `ConstraintDynamics<solid_dynamics::ShellNormalDirection>` 等 | 壳层、梁、固体固定或加载 |

## 5. 主循环策略

1. **时间步更新**：调用 `ReduceDynamics` 计算 dt。
2. **外力/边界刷新**：执行 `SimpleDynamics`（重力、入流）。
3. **压力/速度松弛**：先 `Integration1stHalf`，再 `DensitySummation`、`Integration2ndHalf`。
4. **接触修正**：必要时执行 `TransportVelocityCorrection`、`PressureForceFromFluid`。
5. **输出控制**：根据 `physical_time` 与 `output_interval` 判断写文件。
6. **回归/监控**：周期性调用观测记录与回归测试。

建议以 `while (physical_time < end_time)` 包裹上述步骤，并通过 `Real relaxation_time = 0.0;` 分离粒子松弛阶段。

## 6. 输出与验证

| 目标 | 函数 / 类 | 说明 |
|------|------------|------|
| VTK 输出 | `BodyStatesRecordingToVtp` | 输出所有体的粒子场，可用于 ParaView |
| 观测点 | `ObservedQuantityRecording<Real/Vecd>` | 记录特定量（压力、速度），支持 CSV |
| 全局量 | `ReducedQuantityRecording<TotalKineticEnergy>` | 用于能量监控与回归 |
| 回归测试 | `RegressionTestDynamicTimeWarping<...>` | 自动与历史数据对比 |
| 粒子重载 | `ReloadParticleIO` | 保存/加载松弛粒子分布 |

输出路径默认位于 `build/bin/{case_name}/`，可通过 `sph_system.io_->reload_folder_` 自定义。

## 7. 典型案例模板

### 7.1 2D 纯流体

- **核心算法链**：`GravityForce` → `AcousticTimeStep` → `Integration1stHalfRiemann` → `DensitySummationComplex` → `Integration2ndHalfRiemann`。
- **关键参数**：`resolution_ref = H / N`，`c_f = 10 * U_ref`，`viscosity = rho * U_ref * L / Re`。
- **输出**：`BodyStatesRecordingToVtp` + `ObservedQuantityRecording<Vecd>("Velocity")`。

### 7.2 流体-壳层耦合

- **Body 设置**：`FluidBody` + `ThinStructure`；壳层使用 `ShellParticles` 并定义厚度。
- **关系**：`InnerRelation`（流体），`ContactRelationFromShellToFluid`（耦合），必要时 `ComplexRelation`。
- **动力学**：
  - 流体：同 2D 纯流体。
  - 壳层：`solid_dynamics::ShellStressRelaxationFirstHalf/SecondHalf`。
  - 耦合：`solid_dynamics::PressureForceFromFluid`、`ViscousForceFromFluid`。

### 7.3 流体-固体耦合

- **材料**：固体常用 `NeoHookeanSolid`，生成 `SolidParticles`。
- **松弛与重载**：针对固体体执行 `ParticleRelaxationComplex`，再 `generateParticles<Reload>`。
- **耦合流程**：
  1. 计算流体 dt 与压力松弛。
  2. 调用 `solid_dynamics::StressRelaxationFirstHalf` / `SecondHalf`。
  3. 同步动量交换：`fluid_dynamics::FluidForceOnSolidUpdate`。

### 7.4 3D 扩展要点

- 更新构建脚本链接 `sphinxsys_3d`。
- 几何多采用 `TriangleMeshShape` 或 `Level Set`。
- 时间步限制更加严格，建议启用 `ParticleSpacingByBodyShape` 自适应解析度。
- 输出体积数据建议同时写入 `BodyReducedQuantityRecording<Real>("Mass")` 以核对守恒。

### 7.5 教程示例索引（tutorials/sphinx/examples）

下表汇总 `tutorials/sphinx/examples/` 中 16 个官方教程案例的物理场景与关键调用，便于在搭建新 Case 时快速对照已有实践。

| 示例 | 场景摘要 | 关键调用/特性 |
| --- | --- | --- |
| Example 1: 2D dam break | 弱可压缩自由液面冲击与壁面相互作用，展示双准则时间推进 | ComplexShape 边界; fluid_advection_time_step / fluid_acoustic_time_step; fluid_pressure_relaxation + fluid_density_relaxation; BodyStatesRecordingToVtp; ObservedQuantityRecording; RegressionTest |
| Example 2: Elastic water gate | 闸门流固耦合，刚性底座 + 弹性门片组合，演示接触与弹性松弛 | ElasticBody GateBase/Gate; add_fluid_gravity; fluid_pressure_force_on_gate; gate_stress_relaxation_first/second_half; gate_computing_time_step_size; gate_average_velocity |
| Example 3: 3D multi-resolution particle distribution | 复杂三维几何清理与多分辨率粒子生成流程 | ImportedModel 粒子框架; random_imported_model_particles; update_smoothing_length_ratio; relaxation_step_inner.surface_bounding |
| Example 4: 2D multi-resolution particle distribution | 二维机翼脏几何的体拟合粒子生成和多分辨率自适应 | Airfoil ComplexShape; random_airfoil_particles; update_smoothing_length_ratio; relaxation_step_inner |
| Example 5: 2D Taylor-Green vortex | 周期平面内的涡旋衰减验证，突出对流/声学双时间步 | SMIN(get_fluid_time_step_size, get_fluid_advection_time_step_size); initialize_a_fluid_step; density_relaxation; periodic_condition_x/y |
| Example 6: Heat transfer | 流体与固体耦合的对流-传导换热，含温度场耦合 | ThermofluidBody / ThermosolidBody 材料; ThermalRelaxationComplex; initialize_a_fluid_step; pressure_relaxation + density_relaxation; periodic_condition |
| Example 7: 2D diffusion | 标量扩散过程建模，介绍扩散体、扩散松弛 | DiffusionBody/DiffusionBodyMaterial; DiffusionBodyRelaxation; diffusion_relaxation; get_time_step_size; periodic_condition_y |
| Example 8: Hydrostatic water column on an elastic plate | 静水压力作用下的弹性板形变，采用动态松弛 | WaterBlock + Gate ElasticBody; fluid_pressure_force_on_inserted_body; fluid_damping; average_velocity_and_acceleration; SMIN(get_fluid_time_step_size, inserted_body_computing_time_step_size) |
| Example 9: 2D static confinement | 静态限域壁面模型与多分辨率边界处理 | Static confinement boundary; initialize_a_fluid_step; pressure_relaxation; density_relaxation; update_density_by_summation |
| Example 10: Shell cases: a 2D thin plate | Uflyand-Mindlin 壳公式下的薄板动力响应 | PlateParticleGenerator; apply_point_force; computing_time_step_size; stress_relaxation_first/second_half; plate_position_damping; plate_rotation_damping |
| Example 11: Shell cases: a 3D arch | 三维拱壳受载，展示伪法向不一致时的处理 | Cylinder shell geometry; initialize_external_force; computing_time_step_size; stress_relaxation_first/second_half; constrain_holder; cylinder_position_damping |
| Example 12: Flow around a cylinder | 粘性外流绕柱流动，含自由流入/输出与力计算 | FreeStreamBuffer/Condition; get_fluid_advection_time_step_size; fluid_pressure_force_on_inserted_body; fluid_viscous_force_on_inserted_body; compute_vorticity; ReloadParticleIO |
| Example 13: 2D oscillating beam | 内部约束梁振动，验证固体动力学时间积分 | BeamInitialCondition; clamp_constrain_beam_base; computing_time_step_size; stress_relaxation_first/second_half; beam_corrected_configuration; ObservedQuantityRecording |
| Example 14: 2D bifurcation flow | 分叉管内流动，包含抛物入口、周期边界与涡量监控 | ParabolicInflow; periodic_condition.bounding/update; initialize_a_fluid_step; SMIN(get_fluid_time_step_size, get_fluid_advection_time_step_size); compute_vorticity; ReloadParticleIO |
| Example 15: 2D aortic valve | 血管瓣膜 FSI，周期入流驱动与叶片观察点 | InsertedBody + FluidObserver; ParabolicInflow; fluid_pressure_force_on_inserted_body; compute_vorticity; average_velocity_and_acceleration; ReloadParticleIO |
| Example 16: 2D Channel flow | 微流控通道多物理（流动 + 热输运），周期边界与热松弛 | ThermofluidBodyInitialCondition; pressure_relaxation & density_relaxation; thermal_relaxation_complex; periodic_condition_x.update/bounding; compute_vorticity |

## 8. 参数计算速查

| 参数 | 推荐公式 | 说明 |
|------|----------|------|
| 粒子间距 `resolution_ref` | `L / N` 或 `H / N` | `N` 为单方向粒子数，取整后向下调整 |
| 声速 `c_f` | `alpha * U_ref` (`alpha` 通常 10~20) | 保证马赫数 < 0.1 |
| 动力粘度 `mu_f` | `rho * U_ref * L / Re` | 依据目标雷诺数 |
| 时间步 `dt` | `min(dt_acoustic, dt_viscous)` | `dt_acoustic = CFL * h / (c + 1.2|u|max)` |
| 松弛迭代次数 | `max(200, 5 * domain_length / resolution_ref)` | 经验值，视收敛情况调整 |

## 9. 常见问题与排错

- **松弛不收敛**：检查 `setRunParticleRelaxation(true)` 是否开启、`RandomizeParticlePosition` 是否执行、松弛步数是否足够。
- **dt 过小**：降低 `c_f` 或增大 `resolution_ref`；确认 `max|u|` 未被异常外力放大。
- **边界渗漏**：确保墙体 Body 使用 `ComplexShape` 减去内部流体区域，并启用 `GhostBoundary` 修正。
- **回归误差大**：更新参考数据前先在稳定状态下运行两倍物理时间，避免暖机偏差。
- **输出缺失**：检验 `BodyStatesRecordingToVtp` 是否位于主循环内部，并确认 `output_interval` 设置正确。

## 10. 快速参考清单

- 创建系统：`SPHSystem(bounds, resolution_ref);`
- 流体材料：`body.defineClosure<WeaklyCompressibleFluid, Viscosity>(rho0, c_f, mu);`
- 粒子生成：`generateParticles<BaseParticles, Lattice>();`
- 时间步：`ReduceDynamics<fluid_dynamics::AcousticTimeStep> get_time_step(body);`
- 压力松弛：`Dynamics1Level<fluid_dynamics::Integration1stHalfRiemann> pressure_relaxation(inner_relation);`
- 密度求和：`InteractionWithUpdate<fluid_dynamics::DensitySummationComplex> density_update(complex_relation);`
- 观察点：`ObservedQuantityRecording<Real> write_pressure("Pressure", observer_contact);`
- 输出：`BodyStatesRecordingToVtp body_states_recording(sph_system);`
- 回归：`RegressionTestDynamicTimeWarping<ReducedQuantityRecording<TotalKineticEnergy>> kinetic_energy_test(...);`

> 建议在每次新增功能后更新该清单中的调用路径，并同步维护回归基线。
