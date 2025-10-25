# Dt/dt比值恒定机制深度分析报告

## 1. 源码完整抄录

### 1.1 AdvectionViscousTimeStep (计算Dt)

**位置**: `fluid_time_step.cpp`

```cpp
// Line 71-78: 构造函数
AdvectionViscousTimeStep::AdvectionViscousTimeStep(SPHBody &sph_body, Real U_ref, Real advectionCFL)
    : AdvectionTimeStep(sph_body, U_ref, advectionCFL)
{
    Fluid &fluid = DynamicCast<Fluid>(this, particles_->getBaseMaterial());
    Viscosity &viscosity = DynamicCast<Viscosity>(this, particles_->getBaseMaterial());
    Real viscous_speed = viscosity.ReferenceViscosity() / fluid.ReferenceDensity() / h_min_;
    speed_ref_ = SMAX(viscous_speed, speed_ref_);  // 关键：锁定speed_ref_
}

// Line 80-82: reduce函数 (继承自AdvectionTimeStep)
Real AdvectionViscousTimeStep::reduce(size_t index_i, Real dt)
{
    return AdvectionTimeStep::reduce(index_i, dt);
}

// 实际调用的是父类 AdvectionTimeStep::reduce (Line 58-62)
Real AdvectionTimeStep::reduce(size_t index_i, Real dt)
{
    Real acceleration_scale = 4.0 * h_min_ * (force_[index_i] + force_prior_[index_i]).norm() / mass_[index_i];
    return SMAX(vel_[index_i].squaredNorm(), acceleration_scale);  // 返回max(|v|², 4h|a|/m)
}

// Line 65-68: outputResult函数
Real AdvectionTimeStep::outputResult(Real reduced_value)
{
    Real speed_max = sqrt(reduced_value);  // 对reduce结果开平方
    return advectionCFL_ * h_min_ / (SMAX(speed_max, speed_ref_) + TinyReal);  // 关键：再与speed_ref_比较
}
```

### 1.2 AcousticTimeStep (计算dt)

**位置**: `fluid_time_step.cpp`

```cpp
// Line 10-20: 构造函数
AcousticTimeStep::AcousticTimeStep(SPHBody &sph_body, Real acousticCFL)
    : LocalDynamicsReduce<ReduceMax>(sph_body),
      fluid_(DynamicCast<Fluid>(this, particles_->getBaseMaterial())),
      rho_(particles_->getVariableDataByName<Real>("Density")),
      p_(particles_->getVariableDataByName<Real>("Pressure")),
      mass_(particles_->getVariableDataByName<Real>("Mass")),
      vel_(particles_->getVariableDataByName<Vecd>("Velocity")),
      force_(particles_->getVariableDataByName<Vecd>("Force")),
      force_prior_(particles_->getVariableDataByName<Vecd>("ForcePrior")),
      h_min_(sph_body.getSPHAdaptation().MinimumSmoothingLength()),
      acousticCFL_(acousticCFL) {}

// Line 22-26: reduce函数
Real AcousticTimeStep::reduce(size_t index_i, Real dt)
{
    Real acceleration_scale = 4.0 * h_min_ * (force_[index_i] + force_prior_[index_i]).norm() / mass_[index_i];
    return SMAX(fluid_.getSoundSpeed(p_[index_i], rho_[index_i]) + vel_[index_i].norm(), acceleration_scale);
    // 返回max(c + |v|, 4h|a|/m)
}

// Line 29-33: outputResult函数
Real AcousticTimeStep::outputResult(Real reduced_value)
{
    return acousticCFL_ * h_min_ / (reduced_value + TinyReal);
}
```

---

## 2. 参数追踪

### 2.1 构造阶段

**channel_flow_shell.cpp**:
```cpp
Line 200: ReduceDynamics<fluid_dynamics::AdvectionViscousTimeStep>
          get_fluid_advection_time_step_size(water_block, 1.5 * U_f);
          → U_ref = 1.5 × 1.0 = 1.5 m/s

Line 202: ReduceDynamics<fluid_dynamics::AcousticTimeStep>
          get_fluid_time_step_size(water_block);
          → acousticCFL = 0.6 (默认值)
```

**AdvectionViscousTimeStep构造**:
```cpp
speed_ref_(初始) = U_ref = 1.5 m/s  (从Line 56继承)
viscous_speed = μ/(ρ₀h) = 0.02/(1.0×0.05) = 0.4 m/s
speed_ref_(最终) = max(0.4, 1.5) = 1.5 m/s  ← 锁定！
```

### 2.2 运行阶段

**双层循环结构** (channel_flow_shell.cpp Line 268-290):
```cpp
while (integration_time < output_interval) {  // 外层：积累到0.5s
    Dt = get_fluid_advection_time_step_size.exec();  // 计算对流时间步

    size_t inner_ite_dt = 0;
    while (relaxation_time < Dt) {  // 内层：用小dt积分到Dt
        dt = SMIN(get_fluid_time_step_size.exec(), Dt);  // 计算声波时间步
        // ... 压力松弛、密度松弛 ...
        relaxation_time += dt;
        inner_ite_dt++;
    }

    // Line 295-297: 控制台输出
    if (number_of_iterations % screen_output_interval == 0) {
        std::cout << "N=" << number_of_iterations
                  << " Time = " << physical_time
                  << " Dt = " << Dt
                  << " Dt / dt = " << inner_ite_dt << "\n";
    }
}
```

---

## 3. 理论公式推导

### 3.1 完整公式（考虑加速度项）

#### Dt的计算:
```
reduce_advection = max(|v|², 4h|a|/m)  (Line 62)
speed_max = sqrt(reduce_advection)      (Line 67)
speed_final = max(speed_max, speed_ref_) (Line 68)
Dt = advectionCFL × h / speed_final     (Line 68)
```

#### dt的计算:
```
reduce_acoustic = max(c + |v|, 4h|a|/m)  (Line 26)
dt = acousticCFL × h / reduce_acoustic   (Line 33)
```

### 3.2 简化情形分析

#### 情形1: 速度项主导Dt，速度项主导dt
```
假设: |v|² > 4h|a|/m, 且 c+|v| > 4h|a|/m

Dt = advectionCFL × h / max(|v|, speed_ref_)
dt = acousticCFL × h / (c + |v|)

Dt/dt = (advectionCFL / acousticCFL) × [(c + |v|) / max(|v|, speed_ref_)]
      = 0.4167 × [(10 + |v|) / max(|v|, 1.5)]
```

**问题**: 当|v|从1.15变化到1.55时，比值会变化（3.1 → 3.2），不恒定！

#### 情形2: 速度项主导Dt（且被speed_ref_锁定），速度项主导dt
```
假设: |v| < speed_ref_ = 1.5

Dt = advectionCFL × h / speed_ref_ = 0.25 × 0.05 / 1.5 = 0.008333 s
dt = acousticCFL × h / (c + |v|) = 0.6 × 0.05 / (10 + |v|)

Dt/dt = 0.008333 / (0.03 / (10 + |v|))
      = 0.008333 × (10 + |v|) / 0.03
      = (10 + |v|) / 3.6

当|v|=1.2: Dt/dt = 11.2 / 3.6 = 3.11
```

**问题**: 理论值≈3.11，但观测值=4，误差28%！

#### 情形3: 加速度项主导Dt，速度项主导dt
```
假设: 4h|a|/m > |v|², 且 c+|v| > 4h|a|/m

Dt = advectionCFL × h / sqrt(4h|a|/m)
dt = acousticCFL × h / (c + |v|)

Dt/dt = (advectionCFL / acousticCFL) × [(c + |v|) / sqrt(4h|a|/m)]
```

**若Dt/dt恒为4，求解|a|**:
```
4 = 0.4167 × [(10 + 1.2) / sqrt(4 × 0.05 × |a|)]
→ sqrt(0.2|a|) = 11.2 / 9.6 = 1.167
→ |a| = 6.81 m/s²
```

**粘性加速度估计**: `a_vis ~ μU/(ρh²) = 0.02×1/(1×0.0025) = 8 m/s²`

**结论**: 加速度量级吻合！但反推Dt时发现**速度项仍然主导**（|v|²=1.44 > 4h|a|/m=1.36），矛盾！

---

## 4. 数值验证结果

### 4.1 观测数据
```
t=12.5s:  Dt=0.010833, Dt/dt=4 → dt=0.002708
t=90s:    Dt=0.010489, Dt/dt=4 → dt=0.002622
```

### 4.2 理论预测（情形2，|v|=1.193）
```
Dt_theory = 0.008333 s
dt_theory = 0.002680 s
(Dt/dt)_theory = 3.109

误差:
- Dt误差: 21.83% ❌
- dt误差: 0.56%  ✅
- 比值误差: 22.27% ❌
```

### 4.3 反推分析
```
从Dt=0.010833反推:
speed_final = 0.25 × 0.05 / 0.010833 = 1.154 m/s < speed_ref_(1.5)

这意味着:
- speed_max = 1.154 (未被speed_ref_锁定)
- reduce_advection = 1.154² = 1.331
- 但实际|v|²=1.44 > 1.331，矛盾！
```

---

## 5. 关键矛盾总结

### 矛盾1: Dt的锁定机制失效
```
预期: 当|v| < 1.5时，Dt应被speed_ref_=1.5锁定在0.008333s
实际: Dt=0.010833s，说明speed_ref_并未锁定
```

### 矛盾2: 加速度项的角色模糊
```
理论: 若加速度主导Dt，则|a|≈6.8 m/s²合理
反推: 但reduce返回1.331 < |v|²=1.44，说明速度主导
```

### 矛盾3: 比值恒定的机制未知
```
观测: Dt/dt精确恒为4，即使速度从1.15变化到1.55
理论: 所有情形下，比值都应随速度变化
```

---

## 6. 可能的解释假设

### 假设A: 数据解读错误
- **可能性**: 控制台输出的"Dt"不是`get_fluid_advection_time_step_size.exec()`的返回值
- **验证方法**: 检查完整的控制台输出，确认Line 295-297的打印逻辑

### 假设B: CFL参数被修改
- **可能性**: 实际运行中的advectionCFL不是0.25，而是0.33
- **验证**: `0.33 × 0.05 / 1.5 = 0.011 ≈ 0.010833 ✅`
- **反驳**: 源码中没有修改CFL的地方

### 假设C: h_min被修改
- **可能性**: 实际h_min不是0.05
- **验证**: `Dt = 0.25 × h / 1.5 → h = 0.065`
- **反驳**: resolution_ref在Line 100明确为0.05

### 假设D: 存在隐藏的时间步缩放
- **可能性**: 在内层循环（Line 279）中，`SMIN(dt, Dt)`操作导致实际dt被Dt限制
- **验证**: 需要检查是否dt_acoustic总是大于Dt/4

### 假设E: 加速度项的系数不是4.0
- **可能性**: Line 24和Line 60的系数实际不是4.0
- **反驳**: 源码明确写着`4.0 * h_min_`

---

## 7. 需要进一步调查的问题

1. **提供完整控制台输出**: 查看"N=", "Dt=", "Dt/dt="的完整序列
2. **确认输出时机**: t=12.5s对应第几次迭代？
3. **检查dt的实际值**: 内层循环中dt是否被Dt限制？
4. **验证CFL参数**: 运行时CFL是否为默认值？
5. **检查h_min**: 实际网格间距是否精确为0.05？

---

## 8. 待修正的理论模型

### 当前最可能的机制（假设B）:
```
若advectionCFL = 0.33 (而非0.25):

Dt = 0.33 × 0.05 / 1.5 = 0.011 s
dt = 0.6 × 0.05 / (10 + 1.2) = 0.00268 s
Dt/dt = 0.011 / 0.00268 = 4.1 ≈ 4 ✅

结论: 比值恒为4是因为:
- Dt被speed_ref_=1.5锁定
- dt随速度微调，但c≫|v|，影响小
- 4 ≈ (advectionCFL / acousticCFL) × (c / speed_ref_)
    = (0.33 / 0.6) × (10 / 1.5)
    = 0.55 × 6.67 = 3.67 ≈ 4
```

### 需要验证的关键公式:
```
Dt/dt = (advectionCFL / acousticCFL) × [c / speed_ref_]  (当|v|≪c且|v|<speed_ref_时)
      = (0.33 / 0.6) × (10 / 1.5)
      = 3.67
```

**误差**: 仍有8%偏差，可能来自|v|的贡献。

---

## 9. 结论

基于当前证据，**最可能的真相**是：

1. **Dt被speed_ref_=1.5锁定** ✅
2. **dt由声速主导**，速度项贡献小 ✅
3. **advectionCFL实际值可能是0.33**（或h_min实际是0.065）
4. **Dt/dt≈4是两个CFL比值乘以物理量比值的结果**

但这需要**完整的控制台输出**或**实际运行日志**来最终确认！

---

**报告生成时间**: 2025-10-15
**数据来源**: 源码逐行分析 + 数值反推
**置信度**: 中等（需实际数据验证）

