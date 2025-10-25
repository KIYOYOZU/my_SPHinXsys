# SPH 压力/密度松弛算法详解

**文档版本**: 2.0
**创建日期**: 2025-10-13
**更新日期**: 2025-10-14
**适用项目**: SPHinXsys - 2D Channel Flow (Weakly Compressible SPH)

**版本说明**: v2.0 重组了文档结构，按照实际执行流程（外层循环→内层循环）组织内容，而非按算法类型（压力松弛/密度松弛）组织，提高了逻辑连贯性。

---

## 目录

1. [物理基础：N-S方程与弱可压缩假设](#一物理基础ns方程与弱可压缩假设)
2. [算法策略：预测-校正分步积分](#二算法策略预测-校正分步积分)
3. [两级时间步结构详解](#三两级时间步结构详解)
4. [外层循环：预处理阶段（慢变量）](#四外层循环预处理阶段慢变量)
5. [内层循环：压力-密度耦合求解（快变量）](#五内层循环压力-密度耦合求解快变量)
6. [完整时间步的数据流](#六完整时间步的数据流)
7. [算法有效性分析](#七算法有效性分析)
8. [关键技术细节](#八关键技术细节)
9. [总结图表](#九总结图表)

---

## 一、物理基础：N-S方程与弱可压缩假设

### 1.1 控制方程

不可压缩流体的Navier-Stokes方程：

$$
\begin{cases}
\frac{D\mathbf{v}}{Dt} = -\frac{1}{\rho}\nabla p + \nu \nabla^2 \mathbf{v} + \mathbf{f} & \text{(动量方程)} \\
\nabla \cdot \mathbf{v} = 0 & \text{(连续性方程：不可压)}
\end{cases}
$$

**求解困难**：不可压约束 $\nabla \cdot \mathbf{v} = 0$ 需要通过求解压力泊松方程隐式满足，计算代价高。

### 1.2 弱可压缩近似（Weakly Compressible SPH, WCSPH）

**核心思想**：允许密度微小变化（约1%），通过**状态方程（EOS）**将压力与密度直接耦合，避免求解泊松方程。

#### 线性状态方程

**代码实现**:

```cpp
// 来源: src/shared/physical_closure/materials/weakly_compressible_fluid.cpp:15-18
Real WeaklyCompressibleFluid::getPressure(Real rho)
{
    return p0_ * (rho / rho0_ - 1.0);
}

// 构造函数: p0_ = rho0 * c0 * c0
// 来源: src/shared/physical_closure/materials/weakly_compressible_fluid.cpp:7
```

**数学形式**：

$$
p = p_0 \left( \frac{\rho}{\rho_0} - 1 \right) = \rho_0 c_0^2 \left( \frac{\rho}{\rho_0} - 1 \right) = c_0^2 (\rho - \rho_0)
$$

**参数说明**：
- $\rho_0$ = 参考密度（1.0 kg/m³）
- $c_0$ = 人工声速（10.0 m/s）
- $p_0 = \rho_0 c_0^2$ = 参考压力（100.0 Pa）

**对应参数定义**:

```cpp
// 来源: channel_flow_shell.cpp:18-20
const Real rho0_f = 1.0;        // 参考密度
const Real U_f = 1.0;           // 特征速度
const Real c_f = 10.0 * U_f;    // 人工声速 → c_f = 10.0
```

#### 数值例子

```
rho0 = 1.0, c0 = 10.0, p0 = 100.0

当 rho = 1.01 (密度增加1%)
  → p = 100.0 × (1.01/1.0 - 1) = 1.0 Pa

当 rho = 0.99 (密度减少1%)
  → p = 100.0 × (0.99/1.0 - 1) = -1.0 Pa
```

### 1.3 修改后的连续性方程

从不可压约束变为：

$$
\frac{D\rho}{Dt} = -\rho \nabla \cdot \mathbf{v}
$$

**物理意义**：密度随速度散度变化，形成 **压力-速度-密度耦合循环**：

```
ρ ─状态方程→ p ─压力梯度→ dv/dt ─速度散度→ dρ/dt ─积分→ ρ
```

---

## 二、算法策略：预测-校正分步积分

### 2.1 直接求解的困难

考虑完整的耦合系统：

```
动量方程: dv/dt = -∇p/ρ + ...  → 需要知道 p
状态方程: p = f(ρ)              → 需要知道 ρ
连续性:   dρ/dt = -ρ∇·v        → 需要知道 v
```

这是一个**隐式耦合系统**，需要迭代求解。

### 2.2 分步策略（Operator Splitting）

**核心思想**：将动量方程和时间积分分为多个步骤，交替更新不同变量。

#### 完整的Navier-Stokes动量方程分解

$$
\frac{D\mathbf{v}}{Dt} = \underbrace{-\frac{1}{\rho}\nabla p}_{\text{压力项}} + \underbrace{\nu \nabla^2 \mathbf{v}}_{\text{粘性项}} + \underbrace{\mathbf{f}}_{\text{体力项}}
$$

其中：
- $-\frac{1}{\rho}\nabla p$：压力梯度力（驱动速度场）
- $\nu \nabla^2 \mathbf{v}$：粘性耗散力（平滑速度场）
- $\mathbf{f}$：外部体力（如重力、驱动力）

#### 分步求解策略

WCSPH将动量方程分为**四个独立步骤**处理：

```
外层循环（对流时间步 Dt, 大步长）:
  ├─ 步骤1: 密度求和修正
  ├─ 步骤2: 粘性力计算 → force_prior
  ├─ 步骤3: 输运速度修正 → force_prior（累加）
  └─ 内层循环（声波时间步 dt, 小步长, 约10次）:
      ├─ 步骤4: 压力松弛（压力梯度力 + force_prior → 更新速度）
      ├─ 步骤5: 体力施加（体力 → 更新速度）
      └─ 步骤6: 密度松弛（速度散度 → 更新密度）
```

**为什么这样分步？**

```
时间尺度分析:
  粘性时间尺度:  τ_viscous = DH² / ν = 2² / 0.02 = 200 s
  对流时间尺度:  τ_convection = DH / U = 2 / 1 = 2 s
  声波时间尺度:  τ_acoustic = DH / c0 = 2 / 10 = 0.2 s

时间尺度关系:
  τ_acoustic << τ_convection << τ_viscous

结论:
  粘性力变化慢 → 在大时间步Dt上计算（外层循环）
  对流速度中等 → Dt由对流CFL条件决定
  压力波传播快 → 在小时间步dt上计算（内层循环）
```

### 2.3 预测-校正的物理意义

```
压力松弛 (Predictor - 预测器):
  "如果密度这样变化，压力会怎样？速度应该如何调整？"
  → ρⁿ → ρⁿ⁺¹/² → pⁿ⁺¹/² → ∇p → vⁿ⁺¹

密度松弛 (Corrector - 校正器):
  "速度调整后，速度散度是多少？密度实际如何变化？"
  → vⁿ⁺¹ → ∇·v → dρ/dt → ρⁿ⁺¹
```

两步形成**自洽循环**，保证压力-速度-密度的一致性。

---

## 三、两级时间步结构详解

### 3.1 时间步层次结构

WCSPH采用**两级时间步**策略，充分利用不同物理过程的时间尺度差异：

```
外层循环（对流时间步 Dt）:
  ├─ 计算一次粘性力（慢变量，τ_viscous = 200 s）
  ├─ 计算一次输运修正（慢变量）
  └─ 内层循环（声波时间步 dt, 约10次）:
      ├─ 压力松弛（快变量，τ_acoustic = 0.2 s）
      ├─ 体力施加（快变量）
      └─ 密度松弛（快变量）

时间步比:
  Dt / dt ≈ c0 / vmax = 10 / 1 = 10
```

### 3.2 时间步长的确定

#### 对流时间步（CFL条件）

$$
\Delta t_{\text{adv}} = C_{\text{CFL}} \frac{h}{v_{\max}} \approx 0.25 \frac{h}{v_{\max}}
$$

**物理意义**：流体粒子运动一个光滑长度 $h$ 所需的时间。

#### 声波时间步

$$
\Delta t_{\text{acoustic}} = C_{\text{CFL}} \frac{h}{c_0 + v_{\max}} \approx 0.25 \frac{h}{c_0}
$$

**物理意义**：压力波传播一个光滑长度所需的时间。

#### 时间步比

$$
\frac{\Delta t_{\text{adv}}}{\Delta t_{\text{acoustic}}} \approx \frac{c_0}{v_{\max}} = 10
$$

**含义**：
- 外层步长 $Dt$ 由流体运动决定（大）
- 内层步长 $dt$ 由声速决定（小，约为 $Dt/10$）
- 需要循环约10次内层步完成一次外层步

**必要性**：
- 声速 $c_0 = 10v_{\max}$ 远大于流速
- 压力波传播快，需要小时间步保证稳定性
- 两级时间步平衡了精度和效率

### 3.3 主循环中的完整流程

**代码对应**（主循环）:

```cpp
// 来源: channel_flow_shell.cpp:264-310
while (physical_time < end_time)
{
    while (integration_time < output_interval)
    {
        // ========== 外层循环：对流时间步 Dt ==========
        Real Dt = get_fluid_advection_time_step_size.exec();

        // ========== 预处理阶段（计算 force_prior） ==========
        update_density_by_summation.exec();       // 重新求和密度
        viscous_acceleration.exec();              // 计算粘性力 → force_prior
        transport_correction.exec();              // 计算输运修正 → force_prior（累加）

        // ========== 内层循环：声波时间步 dt ==========
        while (relaxation_time < Dt)
        {
            Real dt = SMIN(get_fluid_time_step_size.exec(), Dt);

            // 压力松弛（使用 force_prior）
            pressure_relaxation.exec(dt);
            //   → initialization: 预测 ρ^(n+1/2), p^(n+1/2)
            //   → interaction: 计算 force_pressure
            //   → update: v^(n+1) = v^n + (force_prior + force_pressure)/m * dt

            // 体力施加
            constant_gravity.exec(dt);
            //   → v^(n+1) += f_gravity/m * dt

            // 密度松弛
            density_relaxation.exec(dt);
            //   → initialization: x^(n+1)
            //   → interaction: 计算 drho_dt
            //   → update: ρ^(n+1)

            relaxation_time += dt;
        }

        // ========== 后处理：周期性边界 ==========
        periodic_condition.bounding_.exec();
        water_block.updateCellLinkedList();
        periodic_condition.update_cell_linked_list_.exec();
        water_block_complex.updateConfiguration();
    }
}
```

### 3.4 执行流程可视化

```
时间步 n → n+1 的完整求解流程
================================================

外层循环开始 (时间步长 Dt = 0.02 s)
  ↓
【预处理阶段 - 计算 force_prior】
  ├─ update_density_by_summation.exec()
  │  └─ 重新求和密度（消除累积误差）
  │
  ├─ viscous_acceleration.exec()
  │  └─ 计算粘性力: f_viscous = ρν∇²v
  │     → 存储到 force_prior_
  │
  └─ transport_correction.exec()
     └─ 计算输运修正: f_transport = m × v_transport / Dt
        → 累加到 force_prior_
  ↓
内层循环开始 (时间步长 dt = 0.002 s, 循环10次)
  ↓
【压力-密度耦合求解】
  ├─ pressure_relaxation.exec(dt)
  │  ├─ initialization:
  │  │  ├─ ρ^(n+1/2) = ρ^n + dρ/dt × dt/2
  │  │  ├─ p^(n+1/2) = f(ρ^(n+1/2))
  │  │  └─ x^(n+1/2) = x^n + v^n × dt/2
  │  │
  │  ├─ interaction:
  │  │  ├─ 计算压力梯度力: f_pressure = -∇p
  │  │  └─ 计算黎曼耗散: drho_dt (耗散项)
  │  │
  │  └─ update:
  │     └─ v^(n+1) = v^n + (force_prior + force_pressure) / m × dt
  │                          ↑                ↑
  │                   粘性+输运修正      压力梯度
  │
  ├─ constant_gravity.exec(dt)
  │  └─ v^(n+1) += f_gravity / m × dt
  │                    ↑
  │               体力驱动
  │
  └─ density_relaxation.exec(dt)
     ├─ initialization: x^(n+1) = x^(n+1/2) + v^(n+1) × dt/2
     ├─ interaction: 计算 drho_dt = ρ∇·v
     └─ update: ρ^(n+1) = ρ^(n+1/2) + drho_dt × dt/2
  ↓
内层循环结束
  ↓
【后处理阶段】
  ├─ periodic_condition.bounding_.exec()
  ├─ water_block.updateCellLinkedList()
  └─ water_block_complex.updateConfiguration()
  ↓
外层循环结束，进入下一个外层时间步
```

---

## 四、外层循环：预处理阶段（慢变量）

外层循环在对流时间步 $Dt$ 上执行，处理变化缓慢的物理量（粘性力、输运修正）。这些力在内层循环中保持不变，通过 `force_prior_` 传递给压力松弛步骤。

### 4.1 密度求和修正

#### 物理背景

SPH中密度有两种计算方式：
1. **求和密度**：$\rho_i = \sum_j m_j W_{ij}$（直接从核函数求和）
2. **积分密度**：$\frac{d\rho_i}{dt} = -\rho_i \nabla \cdot \mathbf{v}_i$（从连续性方程积分）

**问题**：积分密度会累积数值误差，导致密度漂移。

**解决方案**：每个外层时间步重新求和密度，消除累积误差。

```cpp
// 来源: channel_flow_shell.cpp:272
update_density_by_summation.exec();  // 重新计算求和密度
```

### 4.2 粘性力的计算

#### 物理背景

粘性力来源于流体内部的动量传递：

$$
\mathbf{f}^{\text{viscous}} = \rho \nu \nabla^2 \mathbf{v}
$$

其中 $\nu = \mu / \rho$ 是运动粘度。

#### SPH离散化

**对于内部粒子**：

$$
\mathbf{f}_i^{\text{viscous}} = \rho_i \nu \sum_j \frac{m_j}{\rho_j} \frac{2(\mathbf{v}_i - \mathbf{v}_j)}{\mathbf{r}_{ij}^2 + \epsilon^2} \mathbf{r}_{ij} \cdot \nabla W_{ij}
$$

其中：
- $\nu = \mu / \rho$：运动粘度
- $\mathbf{r}_{ij} = \mathbf{x}_i - \mathbf{x}_j$：粒子间相对位置
- $\epsilon$：避免分母为零的小量

**对于壁面粒子**：

考虑无滑移边界条件，壁面处速度 $\mathbf{v}_{\text{wall}} = 0$，粘性力增强。

#### 通道流的粘性力特性

```
粘性力的物理作用:
  1. 平滑速度场 → 抑制速度梯度过大
  2. 耗散动能 → 转化为热能
  3. 提供稳定性 → 避免数值振荡

对于 Re = 100:
  μ = ρ × U × DH / Re = 1.0 × 1.0 × 2.0 / 100 = 0.02
  粘性力相对较小，但对稳定性至关重要
```

#### 数值例子

假设粒子i有邻居j：

```
粒子i状态:
  vel_i = [1.2, 0.0] m/s
  rho_i = 1.0 kg/m³

邻居j状态:
  vel_j = [1.15, 0.0] m/s
  rho_j = 1.0 kg/m³
  r_ij = 0.05 m
  m_j = 0.001 kg

物理参数:
  ν = 0.02 m²/s
  ε = 0.01 * 0.05 = 0.0005 m

计算粘性力:
  vel_diff = [1.2, 0.0] - [1.15, 0.0] = [0.05, 0.0]

  r_ij² + ε² = 0.05² + 0.0005² = 0.0025 + 0.00000025 ≈ 0.0025

  dW_ijV_j = 0.8 × 0.001 = 0.0008

  force_viscous_j = 1.0 × 0.02 × (0.001/1.0) × 2 × [0.05, 0.0] / 0.0025
                     × 0.05 × 0.0008
                  = 0.02 × 0.001 × 2 × 0.05 / 0.0025 × 0.05 × 0.0008
                  = 0.02 × 0.001 × 40 × 0.05 × 0.0008
                  = 0.02 × 0.001 × 0.0016
                  = 3.2e-8 N

  force_viscous_i = Σ force_viscous_j (对所有邻居求和)
```

**物理意义**：
- 速度差越大 → 粘性力越大
- 粒子间距越小 → 粘性力越大（$\propto 1/r^2$）
- 粘性系数越大 → 粘性力越大

#### 代码执行

```cpp
// 来源: channel_flow_shell.cpp:273
viscous_acceleration.exec();  // 计算粘性力 → 存储到 force_prior_
```

### 4.3 输运速度修正

#### 物理背景

**问题**：标准SPH在以下情况会出现问题：

```
1. 粒子分布不均（Particle clustering）
2. 拉伸流动（Tensile flow）
3. 自由表面（Free surface）
```

**原因**：SPH的拉格朗日性质使得粒子随流体运动，可能导致粒子分布失真。

#### 解决方案：XSPH输运速度修正

**核心思想**：给粒子施加一个**虚拟漂移速度**，使其向高密度区域移动，保持粒子分布均匀。

**修正公式**：

$$
\mathbf{v}_i^{\text{transport}} = \epsilon \sum_j \frac{m_j}{\bar{\rho}_{ij}} (\mathbf{v}_j - \mathbf{v}_i) W_{ij}
$$

其中：
- $\epsilon$：修正系数（通常0.5-1.0）
- $\bar{\rho}_{ij} = (\rho_i + \rho_j)/2$：平均密度

**对应的力**：

$$
\mathbf{f}_i^{\text{transport}} = m_i \frac{\mathbf{v}_i^{\text{transport}}}{\Delta t}
$$

#### 物理意义

```
输运速度修正的作用:
  1. 防止粒子聚集 → 保持粒子均匀分布
  2. 提高数值稳定性 → 避免"粒子空洞"
  3. 改善插值精度 → 核函数在均匀分布时最准确
```

#### 为什么叫"输运"速度？

- 粒子有两种速度：
  1. **物理速度** $\mathbf{v}$：遵循N-S方程
  2. **输运速度** $\mathbf{v}^{\text{transport}}$：人工引入的漂移速度

- 粒子的实际运动：
  $$
  \frac{d\mathbf{x}_i}{dt} = \mathbf{v}_i + \mathbf{v}_i^{\text{transport}}
  $$

#### 通道流中的作用

```
通道流的特点:
  - 壁面附近速度梯度大
  - 中心区域速度均匀

输运修正的效果:
  - 壁面附近：防止粒子过度聚集
  - 中心区域：保持粒子均匀分布
  - 整体：提高速度场的光滑性
```

#### 代码执行

```cpp
// 来源: channel_flow_shell.cpp:274
transport_correction.exec();  // 计算输运修正 → 累加到 force_prior_
```

### 4.4 force_prior_ 的形成

#### 定义位置

**定义位置**（`channel_flow_shell.cpp: 204-205`）：

```cpp
// 来源: channel_flow_shell.cpp:204-207
InteractionWithUpdate<fluid_dynamics::TransportVelocityCorrectionComplex<AllParticles>>
    transport_correction(water_block_inner, water_block_contact);

InteractionWithUpdate<fluid_dynamics::ViscousForceWithWall>
    viscous_acceleration(water_block_inner, water_block_contact);
```

#### 执行顺序

**执行顺序**（`channel_flow_shell.cpp: 272-273`）：

```cpp
viscous_acceleration.exec();        // 先计算粘性力
transport_correction.exec();        // 再累加输运修正
```

#### force_prior_ 的内容

$$
\mathbf{f}_i^{\text{prior}} = \mathbf{f}_i^{\text{viscous}} + \mathbf{f}_i^{\text{transport}}
$$

**物理意义**：

`force_prior_` 包含了所有在外层循环计算的力（粘性力和输运修正力），这些力在整个内层循环中保持不变，与每个内层步计算的压力梯度力相结合，共同驱动速度更新。

#### 完整的速度更新公式

综合所有力的贡献，粒子i的速度更新为：

$$
\begin{aligned}
\mathbf{v}_i^{n+1} &= \mathbf{v}_i^n + \frac{\Delta t}{m_i} \left( \mathbf{f}_i^{\text{prior}} + \mathbf{f}_i^{\text{pressure}} + \mathbf{f}_i^{\text{gravity}} \right) \\
&= \mathbf{v}_i^n + \frac{\Delta t}{m_i} \left( \mathbf{f}_i^{\text{viscous}} + \mathbf{f}_i^{\text{transport}} + \mathbf{f}_i^{\text{pressure}} + \mathbf{f}_i^{\text{gravity}} \right)
\end{aligned}
$$

**对应代码位置**：

```cpp
// 1. 外层循环：计算 force_prior = force_viscous + force_transport
viscous_acceleration.exec();        // Line 272
transport_correction.exec();        // Line 273

// 2. 内层循环：压力松弛中更新速度（使用 force_prior）
pressure_relaxation.exec(dt);       // Line 281
//   → update: vel += (force_prior + force_pressure) / mass * dt

// 3. 内层循环：体力直接累加
constant_gravity.exec(dt);          // Line 282
//   → vel += force_gravity / mass * dt
```

---

## 五、内层循环：压力-密度耦合求解（快变量）

内层循环在声波时间步 $dt$ 上执行，处理变化快速的物理量（压力、密度、速度）。每个外层步需要执行约10次内层循环。

### 5.1 算法概览

内层循环包含三个连续步骤，形成**压力-速度-密度**的耦合求解：

```
内层循环的三个步骤:
  ┌─────────────────────────────────────────┐
  │ 1️⃣ 压力松弛 (Integration1stHalf)       │
  │    目标: 更新速度 v^(n+1)               │
  │    输入: ρⁿ, vⁿ, drho_dt^n, force_prior│
  │    过程:                                │
  │      → 预测 ρ^(n+1/2), p^(n+1/2)       │
  │      → 计算压力梯度力 f_pressure        │
  │      → v^(n+1) = v^n + (f_prior + f_pressure)/m * dt │
  │    输出: vⁿ⁺¹                           │
  └─────────────────────────────────────────┘
                    ↓
  ┌─────────────────────────────────────────┐
  │ 2️⃣ 体力施加 (constant_gravity)         │
  │    目标: 叠加体力效果                  │
  │    输入: vⁿ⁺¹ (来自压力松弛)            │
  │    过程:                                │
  │      → v^(n+1) += f_gravity/m * dt     │
  │    输出: vⁿ⁺¹ (含体力)                  │
  └─────────────────────────────────────────┘
                    ↓
  ┌─────────────────────────────────────────┐
  │ 3️⃣ 密度松弛 (Integration2ndHalf)       │
  │    目标: 更新密度 ρ^(n+1)               │
  │    输入: ρⁿ⁺¹/², vⁿ⁺¹                   │
  │    过程:                                │
  │      → 完成位置更新 x^(n+1)            │
  │      → 计算密度变化率 drho_dt          │
  │      → ρ^(n+1) = ρ^(n+1/2) + drho_dt * dt/2 │
  │    输出: ρⁿ⁺¹, drho_dt^(n+1)           │
  └─────────────────────────────────────────┘
```

**物理自洽性**：

```
ρ ─状态方程→ p ─压力梯度→ dv/dt ─积分→ v ─速度散度→ dρ/dt ─积分→ ρ
↑                                                              ↓
└──────────────────────── 闭环反馈 ────────────────────────────┘
```

三个步骤形成闭环，保证压力-速度-密度的一致性。

### 5.2 压力松弛（Integration1stHalf）详解

#### 5.2.1 初始化（Initialization）

**目标**：预测半步密度和压力，为后续计算压力梯度力做准备。

**代码实现**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:52-62
void Integration1stHalf::initialization(size_t index_i, Real dt)
{
    // 1️⃣ 半步密度预测
    rho_[index_i] += drho_dt_[index_i] * dt * 0.5;

    // 2️⃣ 根据密度计算压力（状态方程）
    p_[index_i] = fluid_.getPressure(rho_[index_i]);

    // 3️⃣ 半步位置预测
    pos_[index_i] += vel_[index_i] * dt * 0.5;
}
```

**物理推导**：

**1️⃣ 密度预测（Euler前向）**：

$$
\rho_i^{n+1/2} = \rho_i^n + \frac{d\rho_i}{dt}\bigg|^n \cdot \frac{\Delta t}{2}
$$

**2️⃣ 状态方程**：

$$
p_i^{n+1/2} = c_0^2 (\rho_i^{n+1/2} - \rho_0)
$$

**3️⃣ 位置预测**（用于后续邻居搜索）：

$$
\mathbf{x}_i^{n+1/2} = \mathbf{x}_i^n + \mathbf{v}_i^n \cdot \frac{\Delta t}{2}
$$

**数值例子**：

假设某个粒子在时间步 $n$：

```
输入状态:
  ρⁿ = 1.005
  drho_dt^n = -0.1
  velⁿ = [1.2, 0.0]
  posⁿ = [5.0, 1.0]
  dt = 0.001

执行 initialization:
  1️⃣ ρⁿ⁺¹/² = 1.005 + (-0.1) × 0.0005 = 1.00495

  2️⃣ pⁿ⁺¹/² = 100.0 × (1.00495 - 1.0) = 0.495 Pa

  3️⃣ posⁿ⁺¹/² = [5.0, 1.0] + [1.2, 0.0] × 0.0005
                = [5.0006, 1.0]

输出状态:
  ρⁿ⁺¹/² = 1.00495
  pⁿ⁺¹/² = 0.495
  posⁿ⁺¹/² = [5.0006, 1.0]
```

#### 5.2.2 相互作用（Interaction）- 压力梯度力

**物理推导：从连续形式到SPH离散**

**动量方程的压力项**：

$$
\frac{D\mathbf{v}}{Dt} = -\frac{1}{\rho}\nabla p
$$

**SPH离散化（对称形式，保证动量守恒）**：

$$
\frac{d\mathbf{v}_i}{dt}\bigg|_{\text{pressure}} = -\sum_j m_j \left( \frac{p_i}{\rho_i^2} + \frac{p_j}{\rho_j^2} \right) \nabla W_{ij}
$$

**转换为力的形式**（$m_i \cdot a = F$）：

$$
\mathbf{f}_i^{\text{pressure}} = -m_i \sum_j \left( \frac{p_i}{\rho_i^2} + \frac{p_j}{\rho_j^2} \right) m_j \nabla W_{ij}
$$

**利用体积关系** $V_i = m_i/\rho_i$：

$$
\mathbf{f}_i^{\text{pressure}} = -V_i \sum_j (p_i + p_j) \cdot \nabla W_{ij} \cdot V_j
$$

**代码实现**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:68-82
void Integration1stHalf::interaction(size_t index_i, Real dt)
{
    Vecd force = Vecd::Zero();
    Real rho_dissipation(0);

    // 遍历所有邻居粒子
    const Neighborhood &inner_neighborhood = inner_configuration_[index_i];
    for (size_t n = 0; n != inner_neighborhood.current_size_; ++n)
    {
        size_t index_j = inner_neighborhood.j_[n];

        // ∇W_ij 的模 × 邻居体积
        Real dW_ijV_j = inner_neighborhood.dW_ij_[n] * Vol_[index_j];

        // 单位方向向量 e_ij = (x_i - x_j) / |x_i - x_j|
        const Vecd &e_ij = inner_neighborhood.e_ij_[n];

        // 压力梯度力（SPH离散形式）
        // 注意：∇W_ij = dW_ij * e_ij
        force -= (p_[index_i] * correction_(index_j, index_i) +
                  p_[index_j] * correction_(index_i)) * dW_ijV_j * e_ij;

        // Riemann求解器的耗散项（数值稳定性）
        rho_dissipation += riemann_solver_.DissipativeUJump(p_[index_i] - p_[index_j])
                           * dW_ijV_j;
    }

    // 乘以粒子i的体积得到总力
    force_[index_i] += force * Vol_[index_i];

    // 更新密度变化率（耗散项）
    drho_dt_[index_i] = rho_dissipation * rho_[index_i];
}
```

**关键概念解释**：

**1. 核函数梯度** `∇W_ij`

SPH核函数 $W(\mathbf{r}, h)$ 的梯度分解为：

$$
\nabla W_{ij} = \frac{\partial W}{\partial r}\bigg|_{r_{ij}} \cdot \frac{\mathbf{x}_i - \mathbf{x}_j}{r_{ij}} = \text{dW}_{ij} \cdot \mathbf{e}_{ij}
$$

其中：
- $r_{ij} = |\mathbf{x}_i - \mathbf{x}_j|$ = 粒子间距
- $\text{dW}_{ij} = \frac{\partial W}{\partial r}\big|_{r_{ij}}$ = 核函数导数（标量）
- $\mathbf{e}_{ij} = \frac{\mathbf{x}_i - \mathbf{x}_j}{r_{ij}}$ = 单位方向向量

**代码存储**：
```cpp
dW_ij_[n]  // 标量：核函数导数
e_ij_[n]   // 向量：单位方向
```

**2. 核函数修正** `correction_`

边界附近的核函数被截断（缺少外侧邻居），需要修正以保证**一致性**：

$$
\nabla p_i \approx \sum_j (p_i \mathcal{C}_j^i + p_j \mathcal{C}_i) \cdot \nabla W_{ij} V_j
$$

其中 $\mathcal{C}$ 是修正矩阵（如线性梯度修正 `LinearGradientCorrection`）。

**作用**：
- 内部区域：$\mathcal{C} \approx 1$（无修正）
- 边界区域：通过修正矩阵补偿缺失邻居的影响

**数值例子**：

假设粒子 $i$ 有3个邻居：

```
粒子i状态:
  pos_i = [5.0, 1.0]
  p_i = 0.5 Pa
  Vol_i = 0.001 m³

邻居j1:
  pos_j1 = [4.95, 1.0]
  p_j1 = 0.52 Pa
  Vol_j1 = 0.001 m³
  r_ij1 = 0.05 m
  e_ij1 = [1, 0]
  dW_ij1 = 0.8 (核函数导数)

邻居j2:
  pos_j2 = [5.05, 1.0]
  p_j2 = 0.48 Pa
  Vol_j2 = 0.001 m³
  r_ij2 = 0.05 m
  e_ij2 = [-1, 0]
  dW_ij2 = 0.8

邻居j3:
  pos_j3 = [5.0, 0.95]
  p_j3 = 0.51 Pa
  Vol_j3 = 0.001 m³
  r_ij3 = 0.05 m
  e_ij3 = [0, 1]
  dW_ij3 = 0.8
```

**计算过程**（简化，不考虑 correction）：

```cpp
// 初始化
force = [0, 0]

// 邻居j1的贡献
dW_ijV_j1 = 0.8 × 0.001 = 0.0008
contribution_1 = -(0.5 + 0.52) × 0.0008 × [1, 0]
               = -1.02 × 0.0008 × [1, 0]
               = [-0.000816, 0] N

force = [0, 0] + [-0.000816, 0] = [-0.000816, 0]

// 邻居j2的贡献
dW_ijV_j2 = 0.0008
contribution_2 = -(0.5 + 0.48) × 0.0008 × [-1, 0]
               = -0.98 × 0.0008 × [-1, 0]
               = [0.000784, 0] N

force = [-0.000816, 0] + [0.000784, 0] = [-0.000032, 0]

// 邻居j3的贡献
dW_ijV_j3 = 0.0008
contribution_3 = -(0.5 + 0.51) × 0.0008 × [0, 1]
               = -1.01 × 0.0008 × [0, 1]
               = [0, -0.000808] N

force = [-0.000032, 0] + [0, -0.000808] = [-0.000032, -0.000808]

// 最终压力梯度力（乘以粒子i的体积）
force_i = [-0.000032, -0.000808] × 0.001
        = [-3.2e-8, -8.08e-7] N
```

**物理意义**：
- **x方向**：左邻居压力高（0.52），右邻居压力低（0.48），基本平衡，净力很小（-3.2e-8）
- **y方向**：下邻居压力高（0.51），向上推动粒子（-8.08e-7，负号表示向上）

**黎曼求解器的作用**：

前面计算的压力梯度力只是基础SPH离散，但在实际模拟中还需要**黎曼求解器**提供数值稳定性。

**为什么需要黎曼求解器？**

SPH使用核函数插值，本质上是一种**平滑**的数值方法。但在以下情况会出现问题：

```
1. 激波和不连续面：压力、密度突变
2. 粒子分布不均：核函数截断误差
3. 压力梯度剧烈：数值振荡（Gibbs现象）
```

**解决思路**：引入**人工耗散**（Artificial Viscosity），抑制非物理振荡。

**黎曼求解器类型**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/riemann_solver.h:55-80
// Line 55-80: 无黎曼求解器（纯中心差分）
class NoRiemannSolver
{
    Real DissipativeUJump(const Real &p_jump) { return 0.0; }  // 无耗散
    Real DissipativePJump(const Real &u_jump) { return 0.0; }
};

// 来源: src/shared/particle_dynamics/fluid_dynamics/riemann_solver.h:83-123
// Lines 83-123: 声学黎曼求解器（带耗散）
class AcousticRiemannSolver : public NoRiemannSolver
{
    Real DissipativeUJump(const Real &p_jump)
    {
        return p_jump * inv_rho0c0_ave_;
    }

    Real DissipativePJump(const Real &u_jump)
    {
        return rho0c0_geo_ave_ * u_jump * limiter_(SMAX(u_jump, Real(0)));
    }
};
```

**通道流使用**：

```cpp
// 来源: channel_flow_shell.cpp:195
Integration1stHalfWithWallRiemann    // 使用 AcousticRiemannSolver
```

**DissipativeUJump 的详细推导**：

**物理意义**：压力差 → 密度变化率的耗散修正

**代码实现**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/riemann_solver.h:96-99
Real DissipativeUJump(const Real &p_jump)
{
    return p_jump * inv_rho0c0_ave_;
}
```

其中：
```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/riemann_solver.h:90
inv_rho0c0_ave_ = 2.0 / (rho0_i * c0_i + rho0_j * c0_j)
```

**完整推导**：

从一维Riemann问题的特征分析：

$$
\frac{\partial \rho}{\partial t} + \mathbf{v} \cdot \nabla \rho = -\rho \nabla \cdot \mathbf{v}
$$

考虑压力波的传播，引入人工耗散项：

$$
\mathcal{D}_\rho = \frac{\Delta p}{\bar{\rho} \bar{c}}
$$

其中 $\bar{\rho}\bar{c}$ 是声阻抗的调和平均：

$$
\frac{1}{\bar{\rho}\bar{c}} = \frac{1}{2}\left( \frac{1}{\rho_i c_i} + \frac{1}{\rho_j c_j} \right)
$$

**代码中的应用**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:76-77
rho_dissipation += riemann_solver_.DissipativeUJump(p_[index_i] - p_[index_j])
                   * dW_ijV_j;
drho_dt_[index_i] = rho_dissipation * rho_[index_i];
```

**数值例子**：

```
粒子i和j的状态:
  p_i = 0.5 Pa
  p_j = 0.52 Pa
  rho0_i = rho0_j = 1.0 kg/m³
  c0_i = c0_j = 10.0 m/s

计算耗散项:
  p_jump = p_i - p_j = 0.5 - 0.52 = -0.02 Pa

  inv_rho0c0_ave = 2.0 / (1.0×10.0 + 1.0×10.0)
                 = 2.0 / 20.0
                 = 0.1

  DissipativeUJump = -0.02 × 0.1 = -0.002

  rho_dissipation_contribution = -0.002 × dW_ijV_j
                                = -0.002 × 0.0008
                                = -0.0000016
```

**物理意义**：
- 邻居压力高 → `p_jump < 0` → 耗散项为负 → 抑制密度增长
- 耗散强度正比于压力差和声阻抗倒数

**重要说明：代码中的实际实现**

上述物理推导显示黎曼求解器应该同时修正动量方程和连续性方程，但实际代码中采用了**分离策略**：

```cpp
// 1stHalf中的实际实现
force -= (p_[index_i] * correction_(index_j, index_i) +
          p_[index_j] * correction_(index_i)) * dW_ijV_j * e_ij;  // 纯SPH压力力

rho_dissipation += riemann_solver_.DissipativeUJump(p_[index_i] - p_[index_j])
                   * dW_ijV_j;  // 仅影响density变化率
```

**关键发现**：

```
压力梯度力 (force):
  → 使用标准SPH离散: f = -(pi + pj) * ∇Wij
  → 没有黎曼求解器修正
  → 直接驱动速度更新

密度耗散 (rho_dissipation):
  → 使用黎曼求解器修正: α(pi - pj)/c * ∇Wij
  → 仅影响drho_dt计算
  → 间接影响下一时间步的压力计算
```

**关键结论**：黎曼求解器在SPHinXsys中**仅用于密度耗散**，不直接修正压力梯度力！

#### 5.2.3 更新（Update）- 速度更新

**代码实现**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:64-67
void Integration1stHalf::update(size_t index_i, Real dt)
{
    vel_[index_i] += (force_prior_[index_i] + force_[index_i]) / mass_[index_i] * dt;
}
```

**物理推导**：

牛顿第二定律：

$$
\mathbf{v}_i^{n+1} = \mathbf{v}_i^n + \frac{\mathbf{f}_i^{\text{total}}}{m_i} \Delta t
$$

其中：
$$
\mathbf{f}_i^{\text{total}} = \mathbf{f}_i^{\text{prior}} + \mathbf{f}_i^{\text{pressure}}
$$

**力的分类**：
- `force_prior_`: 在外层循环计算的力（粘性力、输运速度修正）
- `force_`: 刚在 interaction 中计算的压力梯度力

**数值例子**：

```
输入状态:
  velⁿ = [1.2, 0.0] m/s
  mass_i = 0.001 kg
  dt = 0.001 s
  force_prior = [1.2e-5, 0] N      (来自外层循环)
  force_pressure = [-3.2e-8, -8.08e-7] N  (刚计算的)

计算加速度:
  a_total = (force_prior + force_pressure) / mass
          = ([1.2e-5, 0] + [-3.2e-8, -8.08e-7]) / 0.001
          = [1.1968e-5, -8.08e-7] / 0.001
          = [0.011968, -0.000808] m/s²

速度更新:
  velⁿ⁺¹ = [1.2, 0.0] + [0.011968, -0.000808] × 0.001
         = [1.2, 0.0] + [0.000011968, -0.000000808]
         = [1.200012, -0.000000808] m/s

输出状态:
  velⁿ⁺¹ = [1.200012, -0.000000808] m/s
```

#### 5.2.4 壁面边界的特殊处理

**物理背景**：

流体粒子与固体壁面相互作用时，需要考虑：
1. 壁面的无滑移边界条件
2. 体力（如重力）引起的静水压力修正

**代码实现**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:89-113
void Integration1stHalf<Contact<Wall>>::interaction(size_t index_i, Real dt)
{
    Vecd force = Vecd::Zero();

    for (size_t k = 0; k < contact_configuration_.size(); ++k)
    {
        Vecd *wall_acc_ave_k = wall_acc_ave_[k];
        Real *wall_Vol_k = wall_Vol_[k];
        Neighborhood &wall_neighborhood = (*contact_configuration_[k])[index_i];

        for (size_t n = 0; n != wall_neighborhood.current_size_; ++n)
        {
            size_t index_j = wall_neighborhood.j_[n];
            Vecd &e_ij = wall_neighborhood.e_ij_[n];
            Real dW_ijV_j = wall_neighborhood.dW_ij_[n] * wall_Vol_k[index_j];
            Real r_ij = wall_neighborhood.r_ij_[n];

            // 计算流体相对壁面的法向加速度
            Real face_wall_external_acceleration =
                (force_prior_[index_i] / mass_[index_i] - wall_acc_ave_k[index_j]).dot(-e_ij);

            // 壁面处的虚拟压力 = 流体压力 + 静水压力修正
            Real p_j_in_wall = p_[index_i] +
                rho_[index_i] * r_ij * SMAX(Real(0), face_wall_external_acceleration);

            // 计算流体-壁面压力作用力
            force -= (p_[index_i] + p_j_in_wall) * correction_(index_i)
                     * dW_ijV_j * e_ij;

            rho_dissipation += riemann_solver_.DissipativeUJump(p_[index_i] - p_j_in_wall)
                               * dW_ijV_j;
        }
    }
    force_[index_i] += force * Vol_[index_i];
    drho_dt_[index_i] += rho_dissipation * rho_[index_i];
}
```

**静水压力修正推导**：

考虑体力 $\mathbf{f}$ 作用下的流体静力学：

$$
\nabla p = \rho \mathbf{f}
$$

沿壁面法向积分：

$$
p_{\text{wall}} = p_{\text{fluid}} + \rho \mathbf{f} \cdot \Delta \mathbf{x}
$$

其中 $\Delta \mathbf{x} = \mathbf{x}_{\text{wall}} - \mathbf{x}_{\text{fluid}}$。

**代码实现**：

```cpp
p_j_in_wall = p_[index_i] + rho_[index_i] * r_ij * SMAX(0, f·(-e_ij))
```

- `r_ij`: 流体粒子到壁面的距离
- `SMAX(0, ...)`: 确保只在体力指向壁面时施加修正（避免非物理负压）
- `-e_ij`: 壁面的内法向（指向流体）

**物理意义**：
- 在通道流中，体力 $\mathbf{f} = [f_x, 0]$ 驱动流动
- 壁面处的压力需要考虑这个驱动力的贡献
- 保证了壁面边界条件的准确性

### 5.3 体力施加（constant_gravity）

体力是外部施加的驱动力，在通道流中通常是沿流动方向的恒定体力（模拟压力梯度驱动）。

**物理背景**：

通道流需要恒定的驱动力维持流动。理论上，泊肃叶流动由压力梯度驱动：

$$
\frac{\partial p}{\partial x} = -\frac{12\mu U}{DH^2}
$$

在SPH中，我们用等效体力 $\mathbf{f}$ 来代替压力梯度：

$$
\mathbf{f} = -\frac{1}{\rho}\frac{\partial p}{\partial x} = \frac{12\mu U}{\rho DH^2}
$$

**代码定义**：

```cpp
// 来源: channel_flow_shell.cpp:207
Gravity constant_gravity(Vec2d(fx, 0.0));
```

其中 `fx` 的计算（Line 26-27）：

$$
fx = \frac{12 \mu U}{\rho DH^2}
$$

**代码执行**：

```cpp
// 来源: channel_flow_shell.cpp:282 (内层循环中)
constant_gravity.exec(dt);
```

**物理实现**：

体力直接叠加到速度上：

$$
\mathbf{v}_i^{n+1} \mathrel{+}= \frac{\mathbf{f}_{\text{gravity}}}{m_i} \Delta t
$$

**数值例子**：

```
物理参数:
  μ = 0.02 Pa·s
  U = 1.0 m/s
  DH = 2.0 m
  ρ = 1.0 kg/m³

计算体力:
  fx = 12 × 0.02 × 1.0 / (1.0 × 2.0²)
     = 0.24 / 4.0
     = 0.06 m/s²

速度更新 (假设 dt = 0.001 s):
  vel^(n+1) = [1.200012, -0.000000808] (来自压力松弛)

  vel^(n+1) += [0.06, 0] × 0.001
             = [1.200012, -0.000000808] + [0.00006, 0]
             = [1.200072, -0.000000808] m/s
```

**物理意义**：

体力提供持续驱动，补偿粘性耗散，维持流动达到稳态。

### 5.4 密度松弛（Integration2ndHalf）详解

密度松弛是内层循环的最后一步，根据更新后的速度场计算密度变化，完成一个完整的压力-速度-密度耦合循环。

#### 5.4.1 初始化（Initialization）

**目标**：完成位置的另一半更新。

**代码实现**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:173-176
void Integration2ndHalf::initialization(size_t index_i, Real dt)
{
    // 完成位置的另一半更新
    pos_[index_i] += vel_[index_i] * dt * 0.5;
}
```

**物理推导**：

配合压力松弛的半步，完成完整时间步的位置更新：

$$
\mathbf{x}_i^{n+1} = \mathbf{x}_i^{n+1/2} + \mathbf{v}_i^{n+1} \cdot \frac{\Delta t}{2}
$$

**注意**：这里使用的是**更新后的速度** $\mathbf{v}_i^{n+1}$（来自压力松弛和体力施加）。

**数值例子**：

```
输入状态:
  posⁿ⁺¹/² = [5.0006, 1.0]  (来自压力松弛.initialization)
  velⁿ⁺¹ = [1.200072, -0.000000808]  (来自压力松弛.update + constant_gravity)
  dt = 0.001 s

执行 initialization:
  posⁿ⁺¹ = [5.0006, 1.0] + [1.200072, -0.000000808] × 0.0005
         = [5.0006, 1.0] + [0.000600036, -0.000000000404]
         = [5.001200036, 0.999999999596]

输出状态:
  posⁿ⁺¹ = [5.001200036, 0.999999999596]
```

**半步交错示意**：

```
位置更新:
  压力松弛.init: pos += vel^n × dt/2       → pos^(n+1/2)
  密度松弛.init: pos += vel^(n+1) × dt/2   → pos^(n+1)  ✓ 完成
```

#### 5.4.2 相互作用（Interaction）- 密度变化率

**物理推导：从连续形式到SPH离散**

**连续性方程（拉格朗日形式）**：

$$
\frac{D\rho_i}{Dt} = -\rho_i \nabla \cdot \mathbf{v}_i
$$

**SPH离散化**：

$$
\frac{d\rho_i}{dt} = \rho_i \sum_j \frac{m_j}{\rho_j}(\mathbf{v}_i - \mathbf{v}_j) \cdot \nabla W_{ij}
$$

**简化**（$m_j/\rho_j = V_j$）：

$$
\frac{d\rho_i}{dt} = \rho_i \sum_j (\mathbf{v}_i - \mathbf{v}_j) \cdot \nabla W_{ij} \cdot V_j
$$

**速度散度的物理意义**：

$$
\nabla \cdot \mathbf{v} = \frac{\partial v_x}{\partial x} + \frac{\partial v_y}{\partial y}
$$

**物理意义**：
- $\nabla \cdot \mathbf{v} > 0$：流体**膨胀** → 密度减小
- $\nabla \cdot \mathbf{v} < 0$：流体**压缩** → 密度增加
- $\nabla \cdot \mathbf{v} = 0$：**不可压**（密度不变）

**代码实现**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:178-196
void Integration2ndHalf::interaction(size_t index_i, Real dt)
{
    Real density_change_rate(0);
    Vecd p_dissipation = Vecd::Zero();

    const Neighborhood &inner_neighborhood = inner_configuration_[index_i];
    for (size_t n = 0; n != inner_neighborhood.current_size_; ++n)
    {
        size_t index_j = inner_neighborhood.j_[n];
        const Vecd &e_ij = inner_neighborhood.e_ij_[n];
        Real dW_ijV_j = inner_neighborhood.dW_ij_[n] * Vol_[index_j];

        // 速度差在方向 e_ij 上的投影
        Real u_jump = (vel_[index_i] - vel_[index_j]).dot(e_ij);

        // 累加密度变化率（连续性方程SPH形式）
        density_change_rate += u_jump * dW_ijV_j;

        // Riemann求解器的耗散项
        p_dissipation += riemann_solver_.DissipativePJump(u_jump)
                         * dW_ijV_j * e_ij;
    }

    // 乘以当前密度得到绝对变化率
    drho_dt_[index_i] += density_change_rate * rho_[index_i];

    // 更新耗散力（用于下一时间步）
    force_[index_i] = p_dissipation * Vol_[index_i];
}
```

**关键概念：`u_jump` 的物理意义**

```cpp
Real u_jump = (vel_[index_i] - vel_[index_j]).dot(e_ij);
```

这是速度差在粒子间连线方向上的投影，表示**相对靠近/远离速度**：
- `u_jump > 0`: 粒子 i 相对 j **远离** → 局部膨胀
- `u_jump < 0`: 粒子 i 相对 j **靠近** → 局部压缩

**数值例子**：

假设粒子 $i$ 有3个邻居（使用前面更新后的速度）：

```
粒子i状态:
  vel_i = [1.200072, -0.000000808] m/s
  rho_i = 1.00495 kg/m³

邻居j1:
  vel_j1 = [1.198, 0.0] m/s
  dW_ijV_j1 = 0.0008
  e_ij1 = [1, 0]

邻居j2:
  vel_j2 = [1.202, 0.0] m/s
  dW_ijV_j2 = 0.0008
  e_ij2 = [-1, 0]

邻居j3:
  vel_j3 = [1.200, 0.001] m/s
  dW_ijV_j3 = 0.0008
  e_ij3 = [0, 1]
```

**计算过程**：

```cpp
// 初始化
density_change_rate = 0

// 邻居j1的贡献
u_jump1 = (vel_i - vel_j1) · e_ij1
        = ([1.200072, -0.000000808] - [1.198, 0.0]) · [1, 0]
        = [0.002072, -0.000000808] · [1, 0]
        = 0.002072

density_change_rate += 0.002072 × 0.0008 = 0.0000016576

// 邻居j2的贡献
u_jump2 = (vel_i - vel_j2) · e_ij2
        = ([1.200072, -0.000000808] - [1.202, 0.0]) · [-1, 0]
        = [-0.001928, -0.000000808] · [-1, 0]
        = 0.001928

density_change_rate += 0.001928 × 0.0008
                    = 0.0000016576 + 0.0000015424
                    = 0.0000032

// 邻居j3的贡献
u_jump3 = (vel_i - vel_j3) · e_ij3
        = ([1.200072, -0.000000808] - [1.200, 0.001]) · [0, 1]
        = [0.000072, -0.001000808] · [0, 1]
        = -0.001000808

density_change_rate += (-0.001000808) × 0.0008
                    = 0.0000032 - 0.0000008006
                    = 0.0000023994

// 最终密度变化率（乘以当前密度）
drho_dt_i = density_change_rate × rho_i
          = 0.0000023994 × 1.00495
          = 0.0000024112 kg/(m³·s)
```

**物理解释**：
- **x方向**：速度几乎一致（1.198, 1.200072, 1.202），散度贡献小
- **y方向**：粒子 i 向下运动（vy = -0.000000808），邻居 j3 向上运动（vy = 0.001），局部**压缩** → 密度增加（drho_dt > 0）

**为什么密度松弛不用黎曼求解器？**

**代码对比**：

```cpp
// 来源: channel_flow_shell.cpp:195-196
Integration1stHalfWithWallRiemann     // 使用 AcousticRiemannSolver
Integration2ndHalfWithWallNoRiemann   // 使用 NoRiemannSolver
```

**原因**（Line 194注释）：

> "Here, we do not use Riemann solver for pressure as the flow is viscous."

**详细解释**：

| 项目 | 压力松弛（1stHalf） | 密度松弛（2ndHalf） |
|------|---------------------|---------------------|
| **主要计算** | 压力梯度力 → 速度更新 | 速度散度 → 密度更新 |
| **黎曼求解器类型** | `AcousticRiemannSolver` | `NoRiemannSolver` |
| **耗散作用对象** | 密度变化率 (`rho_dissipation`) | 力/加速度 (`p_dissipation`) |
| **实际耗散值** | **非零** (= p_jump/(ρ₀c₀)) | **零** (NoRiemannSolver返回0) |
| **耗散物理意义** | 抑制密度/压力耦合振荡 | 无（粘性流动已足够稳定） |

**关键结论**：
1. 压力松弛的黎曼求解器不修正压力梯度力，仅修正密度耗散项
2. 密度松弛实际上没有任何人工耗散
3. 粘性流动中速度场由粘性力平滑，不需要额外人工耗散

#### 5.4.3 更新（Update）- 密度更新

**代码实现**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:198-201
void Integration2ndHalf::update(size_t index_i, Real dt)
{
    // 完成密度的另一半更新
    rho_[index_i] += drho_dt_[index_i] * dt * 0.5;
}
```

**物理推导**：

配合压力松弛的半步，完成完整时间步的密度更新：

$$
\rho_i^{n+1} = \rho_i^{n+1/2} + \frac{d\rho_i}{dt}\bigg|^{n+1} \cdot \frac{\Delta t}{2}
$$

**数值例子**：

```
输入状态:
  ρⁿ⁺¹/² = 1.00495  (来自压力松弛.initialization)
  drho_dt^(n+1) = 0.0000024112  (刚在 interaction 中计算)
  dt = 0.001 s

执行 update:
  ρⁿ⁺¹ = 1.00495 + 0.0000024112 × 0.0005
       = 1.00495 + 0.0000000012056
       = 1.0049500012

输出状态:
  ρⁿ⁺¹ = 1.0049500012 kg/m³
```

**半步交错示意**：

```
密度更新:
  压力松弛.init: rho += drho_dt^n × dt/2       → rho^(n+1/2)
  密度松弛.update: rho += drho_dt^(n+1) × dt/2   → rho^(n+1)  ✓ 完成
```

---

## 六、完整时间步的数据流

本节展示一个完整的内层时间步（从 $n$ 到 $n+1$）中，所有物理量的演化过程。

### 6.1 初始状态（时间步 n）

```
粒子i的状态:
  pos^n = [5.0, 1.0] m
  vel^n = [1.2, 0.0] m/s
  rho^n = 1.005 kg/m³
  p^n = 0.5 Pa (由上一步计算)
  drho_dt^n = -0.1 kg/(m³·s) (由上一步计算)

外层循环已计算:
  force_prior = [1.2e-5, 0] N (粘性力 + 输运修正)

时间步长:
  dt = 0.001 s (内层声波时间步)
```

### 6.2 执行流程

#### 阶段1：压力松弛（Integration1stHalf）

```cpp
// ========== initialization ==========
rho^(n+1/2) = 1.005 + (-0.1) × 0.0005 = 1.00495
p^(n+1/2) = 100 × (1.00495 - 1.0) = 0.495
pos^(n+1/2) = [5.0, 1.0] + [1.2, 0.0] × 0.0005 = [5.0006, 1.0]

// ========== interaction ==========
// 计算压力梯度力（遍历邻居）
force_pressure = [-3.2e-8, -8.08e-7] N

// ========== update ==========
force_total = force_prior + force_pressure
            = [1.2e-5, 0] + [-3.2e-8, -8.08e-7]
            = [1.1968e-5, -8.08e-7] N

vel^(n+1) = [1.2, 0.0] + [1.1968e-5, -8.08e-7] / 0.001 × 0.001
          = [1.2, 0.0] + [0.011968, -0.000808] × 0.001
          = [1.200012, -0.000000808] m/s
```

#### 阶段2：体力施加（constant_gravity）

```cpp
// 体力加速度
fx = 12 × mu × U / (rho × DH²) = 0.06 m/s²

// 速度更新
vel^(n+1) += [fx, 0] × dt
           = [1.200012, -0.000000808] + [0.06, 0] × 0.001
           = [1.200072, -0.000000808] m/s
```

#### 阶段3：密度松弛（Integration2ndHalf）

```cpp
// ========== initialization ==========
pos^(n+1) = [5.0006, 1.0] + [1.200072, -0.000000808] × 0.0005
          = [5.001200036, 0.999999999596]

// ========== interaction ==========
// 计算密度变化率（遍历邻居）
density_change_rate = 0.0000023994
drho_dt^(n+1) = 0.0000023994 × 1.00495 = 0.0000024112 kg/(m³·s)

// ========== update ==========
rho^(n+1) = 1.00495 + 0.0000024112 × 0.0005
          = 1.0049500012 kg/m³
```

### 6.3 最终状态（时间步 n+1）

```
粒子i的状态:
  pos^(n+1) = [5.001200036, 0.999999999596] m  ✓ 完成
  vel^(n+1) = [1.200072, -0.000000808] m/s    ✓ 完成
  rho^(n+1) = 1.0049500012 kg/m³               ✓ 完成
  drho_dt^(n+1) = 0.0000024112 kg/(m³·s)       ✓ 完成
  p^(n+1) = ?  (将在下一时间步的压力松弛.initialization计算)
```

### 6.4 变量演化图

```
时间轴上的变量更新顺序:

       n                   n+1/2                 n+1
       |---------------------|---------------------|

密度:  ρⁿ ────────────────> ρⁿ⁺¹/² ────────────> ρⁿ⁺¹
       (旧)  压力松弛.init   (预测)  密度松弛.update (新)

压力:  pⁿ ────────────────> pⁿ⁺¹/²
       (旧)  压力松弛.init   (预测)

位置:  xⁿ ────────────────> xⁿ⁺¹/² ────────────> xⁿ⁺¹
       (旧)  压力松弛.init   (中间)  密度松弛.init  (新)

速度:  vⁿ ─────────────────────────────────────> vⁿ⁺¹
       (旧)      压力松弛.update + constant_gravity  (新)
```

### 6.5 完整时间步的物理量演化流程图

```
时刻 n:   [ρⁿ, vⁿ, xⁿ, pⁿ, drho_dt^n, force_prior] (完整状态)
           ↓
        压力松弛.init
           ↓ (半步预测)
时刻 n+1/2: [ρⁿ⁺¹/², pⁿ⁺¹/², xⁿ⁺¹/²]
           ↓
        压力松弛.interaction
           ↓ (计算压力梯度力 + 黎曼耗散)
        压力松弛.update
           ↓
           [vⁿ⁺¹] (速度初步更新)
           ↓
        constant_gravity
           ↓ (施加体力)
           [vⁿ⁺¹] (含体力) ✓
           ↓
        密度松弛.init
           ↓ (完成位置)
           [xⁿ⁺¹] (位置完成) ✓
           ↓
        密度松弛.interaction
           ↓ (计算密度变化率)
        密度松弛.update
           ↓
时刻 n+1:   [ρⁿ⁺¹, vⁿ⁺¹, xⁿ⁺¹, drho_dt^(n+1)] (完整状态) ✓
```

---

## 七、算法有效性分析

### 7.1 预测-校正的物理意义

```
压力松弛 (Predictor - 预测器):
  问题: "如果密度这样变化，压力会怎样？速度应该如何调整？"
  回答: ρⁿ → ρⁿ⁺¹/² → pⁿ⁺¹/² → ∇p → vⁿ⁺¹

密度松弛 (Corrector - 校正器):
  问题: "速度调整后，速度散度是多少？密度实际如何变化？"
  回答: vⁿ⁺¹ → ∇·v → dρ/dt → ρⁿ⁺¹
```

**自洽循环**：

```
ρ ─状态方程→ p ─压力梯度→ dv/dt ─积分→ v ─速度散度→ dρ/dt ─积分→ ρ
↑                                                              ↓
└──────────────────────── 闭环反馈 ────────────────────────────┘
```

两步形成闭环，保证压力-速度-密度的一致性。

### 7.2 数值稳定性保证

#### 半步交错（Staggered Grid in Time）

```
时间轴上的变量位置:

     ρⁿ      ρⁿ⁺¹/²    ρⁿ⁺¹        ← 密度在半步时刻求值
     |-------|-------|
          vⁿ      vⁿ⁺¹             ← 速度在整步时刻求值
          |-------|
```

**优势**：
1. **避免直接耦合**：密度和速度不在同一时刻求值，减少耦合不稳定性
2. **中心差分精度**：半步值提供了时间上的中心差分精度（二阶精度）
3. **能量守恒**：交错格式自然地保证了动量和能量守恒

#### 人工可压性的作用

状态方程 $p = c_0^2(\rho - \rho_0)$ 中的 $c_0$ 必须满足：

$$
c_0 \geq 10 \times v_{\max}
$$

**对应** `channel_flow_shell.cpp` Line 20：

```cpp
const Real c_f = 10.0 * U_f;  // c_f = 10.0, U_f = 1.0
```

**原因分析**：

**1. 密度变化控制**：

$$
\Delta \rho \approx \frac{\Delta p}{c_0^2} \sim \frac{\rho_0 v^2}{c_0^2}
$$

当 $c_0 = 10v$ 时：

$$
\frac{\Delta \rho}{\rho_0} \sim \frac{v^2}{100v^2} = 0.01 = 1\%
$$

**2. 时间步限制（CFL条件）**：

$$
\Delta t \leq \frac{h}{c_0 + v_{\max}}
$$

$c_0$ 太大 → $\Delta t$ 太小 → 计算效率低
$c_0$ 太小 → 密度变化大 → 数值不稳定

$c_0 = 10v_{\max}$ 是最佳平衡点！

### 7.3 与不可压流的关系

#### 极限分析

当 $c_0 \to \infty$（即 $p_0 \to \infty$），状态方程变为：

$$
p = c_0^2(\rho - \rho_0) \quad \Rightarrow \quad \rho - \rho_0 = \frac{p}{c_0^2} \to 0
$$

即恢复不可压约束 $\rho = \rho_0$！

#### 等价性证明

WCSPH 的连续性方程：

$$
\frac{D\rho}{Dt} = -\rho \nabla \cdot \mathbf{v}
$$

当 $\rho \approx \rho_0$ 时：

$$
\frac{D\rho}{Dt} = -\rho_0 \nabla \cdot \mathbf{v} \approx 0 \quad \Rightarrow \quad \nabla \cdot \mathbf{v} \approx 0
$$

即自动满足不可压约束！

**结论**：WCSPH 是不可压流的**弱可压近似**，在密度变化小（<1%）时与真实不可压流等价。

---

## 八、关键技术细节

### 8.1 Riemann求解器的耗散项

#### 物理背景

SPH在以下情况会出现非物理振荡：
- 激波、接触面等不连续处
- 压力梯度剧烈变化的区域
- 粒子分布不均匀的边界

**原因**：SPH的核函数插值是平滑的，无法准确捕捉不连续。

#### 解决方案：人工耗散

**压力松弛中的密度耗散**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:76-77
rho_dissipation += riemann_solver_.DissipativeUJump(p_[index_i] - p_[index_j]) * dW_ijV_j;
drho_dt_[index_i] = rho_dissipation * rho_[index_i];
```

**物理形式**：

$$
\mathcal{D}_\rho = -\alpha \frac{\rho c_0}{h} \Delta p
$$

**密度松弛中的动量耗散**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:192-193
p_dissipation += riemann_solver_.DissipativePJump(u_jump) * dW_ijV_j * e_ij;
force_[index_i] = p_dissipation * Vol_[index_i];
```

**物理形式**：

$$
\mathcal{D}_p = -\alpha \frac{\rho c_0}{h} \Delta u
$$

其中：
- $\alpha$：耗散系数（通常 0.1-0.3）
- $h$：光滑长度
- $\Delta p$：粒子间压力差
- $\Delta u$：粒子间速度差

#### 为什么只在压力松弛使用黎曼求解器？

**代码对应**：

```cpp
// 来源: channel_flow_shell.cpp:195-196
Integration1stHalfWithWallRiemann    // 使用 AcousticRiemannSolver
Integration2ndHalfWithWallNoRiemann  // 使用 NoRiemannSolver
```

**原因**（Line 194 注释）：

> "Here, we do not use Riemann solver for pressure as the flow is viscous."

**解释**：
- **压力松弛**：压力和密度通过状态方程强耦合，需要抑制密度振荡
- **密度松弛**：粘性流动中速度场由粘性力平滑，不需要额外人工耗散

### 8.2 限制器的作用

**问题**：过度耗散会使解变得过于平滑，丢失物理特征。

**解决方案**：使用**限制器**（Limiter）自适应调节耗散强度。

**代码实现**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/riemann_solver.h:94-98
Real DissipativePJump(const Real &u_jump)
{
    return rho0c0_geo_ave_ * u_jump * limiter_(SMAX(u_jump, Real(0)));
}
```

**限制器类型**：

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/riemann_solver.h:122
using AcousticRiemannSolver = BaseAcousticRiemannSolver<TruncatedLinear>;
```

`TruncatedLinear` 限制器：

$$
\phi(r) = \begin{cases}
0 & r \leq 0 \\
r & 0 < r < 1 \\
1 & r \geq 1
\end{cases}
$$

其中 $r$ 是局部Mach数：

$$
r = \frac{u_{\text{jump}}}{c_0} = \frac{|\mathbf{v}_i - \mathbf{v}_j| \cdot \mathbf{e}_{ij}}{c_0}
$$

**物理意义**：
- 低速区域（$r < 1$）：线性增强耗散
- 高速区域（$r \geq 1$）：耗散饱和，避免过度抑制

### 8.3 壁面边界的静水压力修正详解

#### 完整推导

考虑体力 $\mathbf{f}$ 作用下的流体静力学平衡：

$$
\nabla p = \rho \mathbf{f}
$$

沿壁面法向（设为 $\mathbf{n}$）积分，从流体粒子（$i$）到壁面（$j$）：

$$
\int_{\mathbf{x}_i}^{\mathbf{x}_j} dp = \int_{\mathbf{x}_i}^{\mathbf{x}_j} \rho \mathbf{f} \cdot d\mathbf{s}
$$

假设 $\rho$ 和 $\mathbf{f}$ 在小范围内恒定：

$$
p_j - p_i = \rho \mathbf{f} \cdot (\mathbf{x}_j - \mathbf{x}_i) = \rho \mathbf{f} \cdot \mathbf{r}_{ij}
$$

其中 $\mathbf{r}_{ij} = \mathbf{x}_j - \mathbf{x}_i$。

#### 代码实现

```cpp
// 来源: src/shared/particle_dynamics/fluid_dynamics/fluid_integration.hpp:105-106
// 计算流体相对壁面的法向加速度
Real face_wall_external_acceleration =
    (force_prior_[index_i] / mass_[index_i] - wall_acc_ave_k[index_j]).dot(-e_ij);

// 壁面处的虚拟压力 = 流体压力 + 静水压力修正
Real p_j_in_wall = p_[index_i] +
    rho_[index_i] * r_ij * SMAX(Real(0), face_wall_external_acceleration);
```

**参数说明**：
- `force_prior / mass`: 流体粒子的加速度（包含体力）
- `wall_acc_ave`: 壁面的平均加速度
- `-e_ij`: 壁面的内法向（指向流体）
- `SMAX(0, ...)`: 只在体力指向壁面时施加修正

#### 物理意义

**通道流示例**（体力 $\mathbf{f} = [f_x, 0]$）：

```
         壁面
    ──────────────
         ↓ -e_ij (内法向)

    粒子i (流体)
    f = [fx, 0] (体力向右)
```

计算：

```cpp
face_wall_external_acceleration = f · (-e_ij)
                                = [fx, 0] · [0, -1]
                                = 0  (体力与壁面法向垂直)

p_j_in_wall = p_i + 0 = p_i  (无修正)
```

**重力驱动流示例**（体力 $\mathbf{f} = [0, -g]$）：

```
    粒子i (流体)
    f = [0, -g] (重力向下)
         ↓

    ──────────────
         壁面 (下方)
```

计算：

```cpp
face_wall_external_acceleration = [0, -g] · [0, -1]
                                = g  (重力指向壁面)

p_j_in_wall = p_i + ρ × r_ij × g  (有修正！)
```

**结论**：修正项确保了壁面处的压力满足静力学平衡，提高了边界条件的准确性。

---

## 九、总结图表

### 9.1 算法流程对比

| 项目 | 压力松弛（1stHalf） | 密度松弛（2ndHalf） |
|------|------------------------------|-------------------------------|
| **主要目标** | 更新速度 $\mathbf{v}$ | 更新密度 $\rho$ |
| **求解方程** | 动量方程 | 连续性方程 |
| **输入** | $\rho^n, \mathbf{v}^n, \frac{d\rho}{dt}^n, \mathbf{f}^{\text{prior}}$ | $\rho^{n+1/2}, \mathbf{v}^{n+1}$ |
| **initialization** | $\rho^{n+1/2}, p^{n+1/2}, \mathbf{x}^{n+1/2}$ | $\mathbf{x}^{n+1}$ |
| **interaction核心** | $\mathbf{f}_i = -V_i\sum_j (p_i+p_j)\nabla W_{ij}V_j$ | $\frac{d\rho_i}{dt} = \rho_i\sum_j(\mathbf{v}_i-\mathbf{v}_j)\cdot\nabla W_{ij}V_j$ |
| **update** | $\mathbf{v}^{n+1} = \mathbf{v}^n + \frac{\mathbf{f}}{m}\Delta t$ | $\rho^{n+1} = \rho^{n+1/2} + \frac{d\rho}{dt}\frac{\Delta t}{2}$ |
| **输出** | $\mathbf{v}^{n+1}, \mathbf{x}^{n+1/2}$ | $\rho^{n+1}, \frac{d\rho}{dt}^{n+1}, \mathbf{x}^{n+1}$ |
| **代码位置** | `fluid_integration.hpp: 50-157` | `fluid_integration.hpp: 167-270` |
| **调用位置** | `channel_flow_shell.cpp: 281` | `channel_flow_shell.cpp: 284` |

### 9.2 两级时间步结构图

```
┌─────────────────────────────────────────────────────────────────┐
│ 外层循环 (对流时间步 Dt ≈ 0.02 s)                              │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 预处理阶段（慢变量，计算1次）                               │ │
│ │ • update_density_by_summation.exec()                       │ │
│ │ • viscous_acceleration.exec() → force_prior_               │ │
│ │ • transport_correction.exec() → force_prior_ (累加)        │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 内层循环 (声波时间步 dt ≈ 0.002 s, 循环10次)              │ │
│ │                                                             │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ 压力松弛 (Integration1stHalf)                          │ │ │
│ │ │ • initialization: ρ^(n+1/2), p^(n+1/2), x^(n+1/2)     │ │ │
│ │ │ • interaction: f_pressure = -∇p                        │ │ │
│ │ │ • update: v^(n+1) = v^n + (f_prior + f_pressure)/m*dt │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ │                            ↓                                │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ 体力施加 (constant_gravity)                             │ │ │
│ │ │ • v^(n+1) += f_gravity/m * dt                          │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ │                            ↓                                │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ 密度松弛 (Integration2ndHalf)                           │ │ │
│ │ │ • initialization: x^(n+1)                              │ │ │
│ │ │ • interaction: drho_dt = ρ∇·v                          │ │ │
│ │ │ • update: ρ^(n+1) = ρ^(n+1/2) + drho_dt*dt/2          │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 后处理阶段                                                  │ │
│ │ • periodic_condition.bounding_.exec()                      │ │
│ │ • water_block.updateCellLinkedList()                       │ │
│ │ • water_block_complex.updateConfiguration()                │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 9.3 物理量演化时间线

```
       外层循环开始                           外层循环结束
              ↓                                      ↓
    ┌─────────────────────────────────────────────────┐
    │  预处理: force_prior (计算1次)                  │
    ├─────────────────────────────────────────────────┤
    │  内层循环 #1 (dt)                               │
    │  ├─ 压力松弛 → v¹, ρ¹/²                        │
    │  ├─ 体力施加 → v¹                               │
    │  └─ 密度松弛 → ρ¹                               │
    ├─────────────────────────────────────────────────┤
    │  内层循环 #2 (dt)                               │
    │  ├─ 压力松弛 → v², ρ³/²                        │
    │  ├─ 体力施加 → v²                               │
    │  └─ 密度松弛 → ρ²                               │
    ├─────────────────────────────────────────────────┤
    │  ...                                            │
    ├─────────────────────────────────────────────────┤
    │  内层循环 #10 (dt)                              │
    │  ├─ 压力松弛 → v¹⁰, ρ¹⁹/²                     │
    │  ├─ 体力施加 → v¹⁰                              │
    │  └─ 密度松弛 → ρ¹⁰                              │
    └─────────────────────────────────────────────────┘
```

### 9.4 代码对应关系

| 功能 | 文件 | 行号 | 说明 |
|------|------|------|------|
| **状态方程** | `weakly_compressible_fluid.cpp` | 15-18 | `getPressure(rho)` |
| **粘性力定义** | `channel_flow_shell.cpp` | 204-207 | `ViscousForceWithWall` |
| **输运修正定义** | `channel_flow_shell.cpp` | 204-207 | `TransportVelocityCorrection` |
| **压力松弛定义** | `channel_flow_shell.cpp` | 195 | `Integration1stHalfWithWallRiemann` |
| **密度松弛定义** | `channel_flow_shell.cpp` | 196 | `Integration2ndHalfWithWallNoRiemann` |
| **外层时间步** | `channel_flow_shell.cpp` | 270 | `get_fluid_advection_time_step_size.exec()` |
| **内层时间步** | `channel_flow_shell.cpp` | 280 | `get_fluid_time_step_size.exec()` |
| **粘性力执行** | `channel_flow_shell.cpp` | 273 | `viscous_acceleration.exec()` |
| **输运修正执行** | `channel_flow_shell.cpp` | 274 | `transport_correction.exec()` |
| **压力松弛执行** | `channel_flow_shell.cpp` | 281 | `pressure_relaxation.exec(dt)` |
| **体力施加** | `channel_flow_shell.cpp` | 282 | `constant_gravity.exec(dt)` |
| **密度松弛执行** | `channel_flow_shell.cpp` | 284 | `density_relaxation.exec(dt)` |
| **1stHalf实现** | `fluid_integration.hpp` | 50-157 | 完整实现 |
| **2ndHalf实现** | `fluid_integration.hpp` | 167-270 | 完整实现 |

---

## 附录：关键公式汇总

### A.1 状态方程

$$
p = \rho_0 c_0^2 \left( \frac{\rho}{\rho_0} - 1 \right) = c_0^2 (\rho - \rho_0)
$$

### A.2 动量方程（压力项）

**连续形式**：
$$
\frac{D\mathbf{v}}{Dt} = -\frac{1}{\rho}\nabla p
$$

**SPH离散**：
$$
\frac{d\mathbf{v}_i}{dt}\bigg|_{\text{pressure}} = -\sum_j m_j \left( \frac{p_i}{\rho_i^2} + \frac{p_j}{\rho_j^2} \right) \nabla W_{ij}
$$

**简化（力的形式）**：
$$
\mathbf{f}_i^{\text{pressure}} = -V_i \sum_j (p_i + p_j) \cdot \nabla W_{ij} \cdot V_j
$$

### A.3 连续性方程

**连续形式**：
$$
\frac{D\rho}{Dt} = -\rho \nabla \cdot \mathbf{v}
$$

**SPH离散**：
$$
\frac{d\rho_i}{dt} = \rho_i \sum_j (\mathbf{v}_i - \mathbf{v}_j) \cdot \nabla W_{ij} \cdot V_j
$$

### A.4 时间积分

**密度（半步交错）**：
$$
\rho_i^{n+1/2} = \rho_i^n + \frac{d\rho_i}{dt}\bigg|^n \cdot \frac{\Delta t}{2}
$$

$$
\rho_i^{n+1} = \rho_i^{n+1/2} + \frac{d\rho_i}{dt}\bigg|^{n+1} \cdot \frac{\Delta t}{2}
$$

**速度（完整步）**：
$$
\mathbf{v}_i^{n+1} = \mathbf{v}_i^n + \frac{\mathbf{f}_i^{\text{total}}}{m_i} \Delta t
$$

**位置（半步交错）**：
$$
\mathbf{x}_i^{n+1/2} = \mathbf{x}_i^n + \mathbf{v}_i^n \cdot \frac{\Delta t}{2}
$$

$$
\mathbf{x}_i^{n+1} = \mathbf{x}_i^{n+1/2} + \mathbf{v}_i^{n+1} \cdot \frac{\Delta t}{2}
$$

### A.5 时间步限制（CFL条件）

**对流时间步**：
$$
\Delta t_{\text{adv}} = C_{\text{CFL}} \frac{h}{v_{\max}}
$$

**声波时间步**：
$$
\Delta t_{\text{acoustic}} = C_{\text{CFL}} \frac{h}{c_0 + v_{\max}}
$$

其中 $C_{\text{CFL}} \approx 0.25$。

---

**文档结束**

**版本历史**：
- v1.0 (2025-10-13): 初始版本，按算法类型组织（压力松弛/密度松弛）
- v2.0 (2025-10-14): 重大结构调整，按执行流程组织（外层循环→内层循环），提高逻辑连贯性

**参考文献**：
1. SPHinXsys 源码：`src/shared/particle_dynamics/fluid_dynamics/`
2. 通道流算例：`tests/2d_examples/test_2d_channel_flow_fluid_shell/`
3. 经典SPH文献：Monaghan, J.J. (1992). Smoothed Particle Hydrodynamics. Annual Review of Astronomy and Astrophysics.
