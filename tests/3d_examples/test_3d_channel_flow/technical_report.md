# 三维泊肃叶槽道流算例技术报告

## 1. 几何建模与粒子生成
算例采用长方体通道几何，通道长度 `DL = 10.0`、高度 `DH = 2.0`、宽度 `DW = 1.0`（`test_3d_channel_flow.cpp:25-27`）。`ChannelGeometry` 继承自 `ComplexShape`，将带平移的长方体添加到组合几何中，实现计算域的空间定义（`test_3d_channel_flow.cpp:43-52`）。

壁面由 `ParticleGenerator<SurfaceParticles, WallBoundary>` 特化实现，沿流向与展向附加海绵层以支撑周期边界粒子扩展，顶/底壁粒子通过 `addSurfaceProperties` 指定法向与厚度用于壁面力学（`test_3d_channel_flow.cpp:54-92`）。中心线、壁法向、展向观察点通过辅助函数在通道中布设，以便提取一维剖面和传感器信号（`test_3d_channel_flow.cpp:96-142`）。

## 2. 物性设置与初始条件
流体采用弱可压模型，基准密度 `rho0_f = 1.0`，平均流速 `U_bulk = 1.0`，人工声速 `c_f = 10 U_bulk`，粘度由雷诺数 `Re = 100` 推导而得（`test_3d_channel_flow.cpp:32-36`）。初始速度条件 `InitialVelocity` 继承自 `fluid_dynamics::FluidInitialCondition`，在 `update()` 中为所有粒子赋予均匀流向速度 `(U_bulk, 0, 0)`，避免开局阶段的非物理调整（`test_3d_channel_flow.cpp:148-157`）。

## 3. SPH 体系构建
`channel_flow_3d()` 中首先实例化 `SPHSystem` 并关闭粒子松弛 / 重新加载流程（`test_3d_channel_flow.cpp:170-182`）。随后：

- `FluidBody` 结合 `ChannelGeometry` 生成晶格粒子，并通过 `defineClosure<WeaklyCompressibleFluid, Viscosity>` 绑定状态方程与粘性模型（`test_3d_channel_flow.cpp:183-185`）。
- `SolidBody` 壁面利用上文特化的生成器离散（`test_3d_channel_flow.cpp:187-189`）。
- 三组 `ObserverBody` 对应中心线、壁法向和展向速度监测（`test_3d_channel_flow.cpp:191-198`）。

内、接触、复合关系通过 `InnerRelation`、`ContactRelation`、`ComplexRelation` 建立，使后续动力学模块在流体内部以及与壁面耦合场景间共享邻域信息（`test_3d_channel_flow.cpp:200-209`）。

## 4. 动力学模块与物理原理
### 4.1 压力松弛与密度更新
`Dynamics1Level<fluid_dynamics::Integration1stHalfWithWallRiemann>` 与 `Integration2ndHalfWithWallNoRiemann` 实例化自 `fluid_integration.h` 的模板定义（`test_3d_channel_flow.cpp:210-211`；`fluid_integration.h:83-146`）。
- 第一阶段在 `interaction()` 中利用声学黎曼解计算界面压力/速度梯度，使动量方程半步积分并兼顾壁面接触作用。
- 第二阶段负责位置、密度的时间推进，采用无黎曼接触以降低数值耗散。

### 4.2 密度求和
`InteractionWithUpdate<fluid_dynamics::DensitySummationComplex>` 结合内外接触关系，在每个外层对流步之前执行核函数加权求和，保持弱可压体的状态方程闭合（`test_3d_channel_flow.cpp:212`；`density_summation.h:25-115`）。

### 4.3 时间步判据
- 对流时间步使用 `AdvectionViscousTimeStep`，基于参考速度与粘性限制确定外层 `Dt`（`test_3d_channel_flow.cpp:213`；`fluid_time_step.h:75-104`）。
- 声学时间步 `AcousticTimeStep` 采样粒子局部马赫数与传播速度，用于内层松弛循环中的自适应子步长（`test_3d_channel_flow.cpp:214`；`fluid_time_step.h:41-59`）。

### 4.4 粘性力与粒子再分布
- `InteractionWithUpdate<fluid_dynamics::ViscousForceWithWall>` 计算对称梯度的粘性项，包含壁面贡献，缓解高 Reynolds 数下的数值噪声（`test_3d_channel_flow.cpp:216`；`viscous_dynamics.h`）。
- `TransportVelocityCorrectionComplex` 在负压或粒子分布不均时调整输运速度，改善粒子体积守恒（`test_3d_channel_flow.cpp:215`；`transport_velocity_correction.h:24-120`）。

### 4.5 体力驱动
泊肃叶解析推导 `f_x = 12 μ U_bulk / (ρ H^2)` 转化为恒定体力，并通过 `GravityForce<Gravity>` 注入动量方程（`test_3d_channel_flow.cpp:219-223`）。该关系保证稳态平均速度满足解析值，无需经验增益。

### 4.6 周期与壁面处理
**PeriodicAlongAxis / PeriodicConditionUsingCellLinkedList.**  
`test_3d_channel_flow.cpp:225-233` 为 x、z 两个方向构造 `PeriodicAlongAxis periodic_along_*` 与 `PeriodicConditionUsingCellLinkedList periodic_condition_*`。`PeriodicAlongAxis` 在 `domain_bounding.h:33-63` 读取包围盒并计算平移向量
```
Δx = x_max - x_min,   Δz = z_max - z_min,
```
对应通道长度、宽度的数值范围。外层时间循环中这两套条件会依次执行：
1. `bounding_.exec()`（`test_3d_channel_flow.cpp:294-296`）按照 `domain_bounding.h:94-132` 的判据对边界粒子应用
   ```
   x_i ← x_i + Δx  (x_i < x_min),    x_i ← x_i - Δx  (x_i > x_max),
   z_i ← z_i + Δz  (z_i < z_min),    z_i ← z_i - Δz  (z_i > z_max),
   ```
   将粒子位置折回主域，保持质量守恒与周期连续性。  
2. `update_cell_linked_list_.exec()`（`test_3d_channel_flow.cpp:300-302`）在 `channel_fluid.updateCellLinkedList()` 之后运行，根据 `domain_bounding.h:141-189` 将跨越周期面的粒子 `ListData` 复制到对侧网格，形成成对的“ghost ↔ real” 邻域。这一步是粘性、压力计算能在周期面上闭合的关键。
执行顺序用 ASCII 示意如下：
```
 Step A: bounding_.exec()        Step B: update_cell_linked_list_.exec()
  ┌───────── Periodic box ─────────┐   ┌───────── Periodic box ─────────┐
  |   [ghost ← fluid] →            |   |   | mirrored particles |        |
  | x < x_min → wrap to x_max      |   | copy to neighbor cell lists     |
  | x > x_max → wrap to x_min      |   | update neighbor search buffers  |
  └────────────────────────────────┘   └────────────────────────────────┘
```
3D 案例在 x、z 两个方向各配置一套周期条件（`test_3d_channel_flow.cpp:225-233`），形成带 `20 h` 流向缓冲和 `4 h` 展向外延的“覆盖域”。相比 2D 案例只在 x 方向周期（`2d_example/channel_flow_shell.cpp:219-244`），这里额外的展向复制直接增加了粒子邻域数量。

**WallBoundary 粒子与法向控制.**  
`ParticleGenerator<SurfaceParticles, WallBoundary>::prepareGeometricData()` 在 `test_3d_channel_flow.cpp:74-92` 中对每一组 `(x_i, z_k)` 生成两层粒子：
```
top:    y = DH + 0.5·h,   n̂ = (0, 1, 0);
bottom: y = -0.5·h,       n̂ = (0,-1, 0);
```
其中 `h = resolution_ref`，厚度 `t = wall_thickness_` 通过 `addSurfaceProperties` 写入。该几何在粘性公式中体现为“墙粒子速度插值 ū_j = 0”的边界条件。

**壳-流耦合流水线.**  
1. `ContactRelationFromShellToFluid` 构造时为每个壁面粒子缓存邻域搜索器，并在 `updateConfiguration()` 中按“壳到流”方向收集邻域（`contact_body_relation.h:158-206`）。  
2. `ShellInnerRelationWithContactKernel` 与 `AverageShellCurvature` 在初始化阶段执行一次（`test_3d_channel_flow.cpp:200-205, 234-235`），将壳体法向统一到指向流体侧。  
3. `Integration1stHalfWithWallRiemann` / `Integration2ndHalfWithWallNoRiemann` 在压力与密度更新时耦合壁面贡献（`test_3d_channel_flow.cpp:210-216`），`ViscousForceWithWall` 则在 `viscous_dynamics.hpp:60-108` 计算粘性牵引  
   ```
   F_i^visc = 2 ∑_j μ (u_i - ū_j) · e_ij /(r_ij + 0.01h)
              · (e_ijᵀ K_i e_ij) · ∇W_ij · V_j · V_i,
   ```
   其中 `μ = mu_f`，`ū_j` 为壳体平均速度。该形式对应连续介质中的 τ = μ ∂u/∂n，从而抑制壁面渗流。
综合来看，周期复制和壁面接触以“位置折叠 → cell list 镜像 → 接触邻域 → 壁面力学”顺序滚动执行，确保通道顶/底是无滑移的同时，流向与展向具备环面拓扑。

## 5. 与二维通道 shell 案例的主要差异
- **壁面粒子布置**：3D 生成器额外迭代展向索引 `k`，在 `DW + 2×span_extension_` 范围内填充波浪状墙面（`test_3d_channel_flow.cpp:77-90`）。二维生成器只在 x 方向生成墙面线条，`prepareGeometricData()` 中无展向循环（`2d_example/channel_flow_shell.cpp:41-107`）。  
- **周期拓扑与邻域规模**：`BoundingBox(-20h, DL+20h)` 与 `DW` 扩展确保两个周期方向都具备缓冲（`test_3d_channel_flow.cpp:173-184`）。二维案例仅调用一次 `PeriodicConditionUsingCellLinkedList`，而 3D 版本在每个外层时间步中依次执行 `periodic_condition_x` 与 `periodic_condition_z`，导致邻域粒子数约翻倍，也让粘性项的耗散更显著。  
- **观测/后处理链路**：3D 增设 `SpanwiseObserver` 并且在 `preprocess_data.m:86-150` 中构建 `analysis.centerline_history`、`analysis.wall_normal_profile`；二维的 `process_velocity_data.m:1-120` 则遍历所有 VTP 网格，直接求取最大全局速度生成 `umax.mat`。  
- **驱动与初始状态**：两者相同地通过 `GravityForce<Gravity>` 应用体力 `f_x = 12 μ U_bulk / (ρ DH^2)` 和 `InitialVelocity` 均匀入口速度，但二维使用变量名 `U_f`、`fx`（`2d_example/channel_flow_shell.cpp:115-220`），三维使用 `U_bulk`、`body_force`（`test_3d_channel_flow.cpp:148-223`），方便在后处理时对照。

## 6. 时间积分与输出流程
初始化后执行：
1. 外层循环：在 `physical_time < end_time` 条件下推进 100 s 仿真（`test_3d_channel_flow.cpp:259-316`）。
2. 对流步 `Dt` 内部先调用密度、粘性、输运修正，再通过内层声学子步迭代压力松弛与体力，累计 `physical_time`。
3. 每 200 次迭代执行粒子排序，提高邻域访问局部性（`test_3d_channel_flow.cpp:294-299`）。
4. 输出阶段写入 VTP 状态、观察者数据、动能统计，并记录 GTest 所需的序列（`test_3d_channel_flow.cpp:306-313`）。

GTest 断言包括：中心线流速与解析值差异 < `5% U_bulk`；壁法/展向速度残差 < `2e-2`。这些判据在 100 s 长程结果下仍成立（`test_3d_channel_flow.cpp:350-376`）。

## 7. 运行计时与日志
新增的计时功能在仿真开始/结束处采集 `TickCount` 与 `steady_clock` 时间，输出到标准流并追加到 `output/timing_summary.txt`，同时记录 wall-clock 启停的时间戳（`test_3d_channel_flow.cpp:246-347`）。最新 100 s 运行得到 TickCount ≈ 1762 s、steady_clock ≈ 1876 s 的耗时记录，可用于性能追踪。

## 8. 物理结果与二维对比
**解析参照与三维表现.**  
泊肃叶解析解：`u(y) = (3/2) U_bulk (1 - (2y/DH - 1)^2)`（`analytical_velocity_profile()`，`test_3d_channel_flow.cpp:163-167`）。在 100 s 运行数据中：  
- `CenterlineObserver_Velocity.dat` 的中点 `u_mid` 峰值 `1.5284`，稳态尾段平均 `1.5264`，相对解析峰值 `1.5 U_bulk` 偏差 `1.9%`。  
- `SpanwiseObserver_Velocity.dat` 的 21 个采样点所有时间都相同，说明周期复制保持展向均匀流。  
`preprocess_data.m` 中 `analysis.wall_normal_profile` 将最后一帧壁法向速度与解析曲线对齐，并按  
```
RMS = √( mean( (u_sim - u_theory)² ) )
```
计算 `RMS = 1.85 × 10^{-2}`（`preprocess_data.m:118-150`），直接复用了 MATLAB 里的 `sqrt(mean(...))` 语句。

**二维 shell 案例的对照数据.**  
`process_velocity_data.m` 在解析 VTP 时使用 `max_velocity = max‖u‖` 填表，最终保存至 `umax.mat`（`process_velocity_data.m:47-120`）。`u0_1_0` 序列（读取于 `tests/2d_examples/.../umax.mat`）给出：峰值 `1.5554`，稳态均值 `1.5489`，相较解析高 `3.7%`。该误差源于 2D 壁面只有单行粒子且没有展向耗散，因此峰值偏高。

**二维/三维差异的时间演化.**  
`compare_umax_2d_vs_3d.m` 将两组数据插值到统一时间轴 `t_common`（`compare_umax_2d_vs_3d.m:52-71`），并计算
```
Δu(t) = u_3D(t) - u_2D(t),    ε_rel(t) = Δu(t) / u_2D(t),
```
同时在 `metrics.delta_mean/min/max` 中存储时间平均值。分析得到：  
- 初期 `t ∈ [0, 10]`：`⟨Δu⟩ ≈ -1.18×10^{-3}`，两者几乎重合。  
- 稳态 `t ∈ [80, 100]`：`⟨Δu⟩ ≈ -2.41×10^{-2}`，三维曲线明显低于二维。  
- 最小差值出现在 `t = 99.51 s`：`Δu_min = -2.95×10^{-2}`。  
图 1（文本示意）总结对比：
```
     速度
     1.56 ──┐   2D umax(t)
           │  ┌──────────────┐
     1.53 ─┤  │    3D u_mid(t)╱╲__ 稳态段
           │  │   (低1.9%) ╱      \
     1.50 ─┴──┴───────────┴──────────── 时间
          0          50            100 s
```
三维更低的峰值与 `ViscousForceWithWall` 中额外的展向邻域（`viscous_dynamics.hpp:60-108`）直接相关：更多墙面邻居提供更强粘性耗散，从而降低中心线速度幅值。

**壁面残差.**  
`WallNormalObserver_Velocity.dat` 显示 `v_y`, `v_z` 的最大偏差约 `7.3×10^{-3}`、`6.8×10^{-3}`，与 GTest 阈值 `2×10^{-2}` 有足够裕度（`test_3d_channel_flow.cpp:364-367`），间接验证了粘性边界条件 τ = μ (∂u/∂n) 的离散实现。

## 9. GTest 精度校验机制
主测试 `TEST(test_3d_channel_flow, laminar_profile)` 在调用 `channel_flow_3d()` 后自动执行断言（`test_3d_channel_flow.cpp:371-376`）。核心步骤如下：
1. **解析基线**：`analytical_velocity_profile` 返回泊肃叶理论速度。  
2. **中心线验证**：遍历 41 个中心线观察点并检查 `|u_sim(x_i) - u_ref(y_i)| < 0.05 · U_bulk`（`test_3d_channel_flow.cpp:350-357`）。该阈值来源于泊肃叶理论 `u_max = 1.5 U_bulk`，约等于其 3.3%，能覆盖粒子噪声与弱可压波动。  
3. **壁面验证**：针对 51 个壁法向观察点执行三条断言 —— `|u_tan(y_j) - u_ref(y_j)| < 0.05 · U_bulk`、`|v_y(y_j)| < 2×10^{-2}`、`|v_z(y_j)| < 2×10^{-2}`（`test_3d_channel_flow.cpp:359-367`）。第二、三条阈值取自最新稳态残差（`≈7×10^{-3}`），即一旦周期映射或粘性边界失效便会触发失败。  
4. **运行入口**：`main()` 调用 `RUN_ALL_TESTS()` 并返回 GoogleTest 状态码；`EXPECT_NEAR` 宏由 `<gtest/gtest.h>` 在比较失败时抛出断言，从而使回归测试与 CI 联动。
因此，GTest 以“中心线解析误差 + 壁面零流量”两套指标衡量精度；相较二维算例，新增的法/展向检查专门针对三维周期复制的正确性。

## 10. 结论
基于源码与 SPHinXsys 公共库，本算例实现了三维泊肃叶通道的全流程仿真：几何/粒子构建、弱可压 SPH 动力学、时间步控制、周期/壁面耦合以及长程稳态校验。100 s 运行验证了与解析解相符的流速分布，并通过新增计时与 2D/3D 对比工具，使案例具备更完整的复现、性能与精度评估闭环。
