## SPHinXsys 3D 泊肃叶流与柔性壳体耦合 (FSI) 技术分析报告

### 摘要

本报告详细分析了 SPHinXsys 库中用于流固耦合（FSI）验证的 `test_3d_poiseuille_flow_shell` 案例。该案例模拟了粘性流体在柔性圆管内以 $Re=100$ 的雷诺数流动的过程，旨在验证弱可压 SPH (WCSPH) 方法与薄壳结构动力学耦合算法的准确性。报告深入探讨了 WCSPH 的三大核心方程在 SPHinXsys 源代码中的具体实现和对应的数学公式。

---

### 第一部分：关键参数与工况设计

#### 1.1 关键参数定义与意义

| 参数名称 | 含义 | 作用 | 文件地址 |
| :--- | :--- | :--- | :--- |
| `number_of_particles` | 径向观测点数量 / 模拟分辨率基准 | 用于定义径向观测点的数量，同时在测试宏中用于计算初始粒子间距（分辨率）。 | [`poiseuille_flow_shell.cpp:135`](poiseuille_flow_shell.cpp:135), [`poiseuille_flow_shell.cpp:402`](poiseuille_flow_shell.cpp:402) |
| `SimTK_resolution` | 几何模型（圆柱体）周向离散精度 | 用于构建圆柱体几何形状时，确定圆周方向的网格数量，数值越高，几何形状越光滑。 | [`poiseuille_flow_shell.cpp:138`](poiseuille_flow_shell.cpp:138), [`poiseuille_flow_shell.cpp:165`](poiseuille_flow_shell.cpp:165) |
| $c_f$ (数值声速) | 弱可压流体的数值硬度 | 确保流体密度波动小于 1%，以模拟不可压缩性。该值被设定为最大流速 $U_{max}$ 的 10 倍。 | [`poiseuille_flow_shell.cpp:26`](poiseuille_flow_shell.cpp:26) |
| $diameter$ | 管道特征长度（内径） | 是计算雷诺数 $Re$ 的特征长度，用于反向推导出所需的平均流速 $U_f$。 | [`poiseuille_flow_shell.cpp:14`](poiseuille_flow_shell.cpp:14) |

#### 1.2 数值声速 $c_f$ 的计算流程

$c_f$ 的计算是一个反向设计过程，旨在精确复现 $Re=100$ 的工况：

1.  **反求平均流速 $U_f$**: 根据目标雷诺数 $Re=100$ 和已知物理参数（$\rho_{0,f}, \mu_f, diameter$），反向计算出所需的平均流速 $U_f$。
    $$
    U_f = \frac{Re \cdot \mu_f}{\rho_{0,f} \cdot diameter}
    $$
2.  **确定最大流速 $U_{max}$**: 对于泊肃叶流，最大流速是平均流速的 2 倍 ($U_{max} = 2 U_f$)。
3.  **设定数值声速 $c_f$**: 遵循 WCSPH 经验法则 $c_f \ge 10 U_{max}$。
    $$
    c_f = 10.0 \cdot U_{max}
    $$

---

### 第二部分：WCSPH 核心方程与实现

WCSPH 方法通过三个核心方程来推进流体模拟。

#### 2.1 状态方程 (Equation of State, EOS)

*   **目的**: 将密度 $\rho$ 变化转化为压力 $P$。
*   **公式 (线性简化形式)**: SPHinXsys 采用泰特方程的一阶泰勒近似（线性化形式），在弱可压假设下简化了计算。
    $$
    P = p_0 \left( \frac{\rho}{\rho_0} - 1 \right)
    $$
    其中 $p_0 = \rho_0 c_0^2$。

| 模块 | 文件地址 | 核心代码 | 对应功能 |
| :--- | :--- | :--- | :--- |
| **应用层调用** | [`poiseuille_flow_shell.cpp:176`](poiseuille_flow_shell.cpp:176) | `water_block.defineClosure<WeaklyCompressibleFluid, Viscosity>(ConstructArgs(rho0_f, c_f), mu_f);` | 指定流体类型并传入 $\rho_0$ 和 $c_0$。 |
| **底层实现 (计算 $P$)** | [`SPHinXsys/src/shared/physical_closure/materials/weakly_compressible_fluid.cpp:17`](../../../../SPHinXsys/src/shared/physical_closure/materials/weakly_compressible_fluid.cpp:17) | `return p0_ * (rho / rho0_ - 1.0);` | 直接实现线性状态方程。 |

#### 2.2 连续性方程 (Density Summation)

*   **目的**: 计算粒子 $i$ 的当前密度 $\rho_i$。
*   **公式 (SPH离散形式)**:
    $$
    \rho_i = \sum_j m_j W(\mathbf{r}_{ij}, h) = \underbrace{m_i W(\mathbf{r}_{ii}, h)}_{\text{自身贡献}} + \underbrace{\sum_{j \neq i} m_j W(\mathbf{r}_{ij}, h)}_{\text{邻居贡献}}
    $$

| 模块 | 文件地址 | 核心代码 | 对应功能 |
| :--- | :--- | :--- | :--- |
| **应用层调用** | [`poiseuille_flow_shell.cpp:302`](poiseuille_flow_shell.cpp:302) | `update_density_by_summation.exec();` | 执行密度求和计算。 |
| **底层实现 (自身贡献)** | [`SPHinXsys/src/shared/particle_dynamics/fluid_dynamics/density_summation.cpp:38`](../../../../SPHinXsys/src/shared/particle_dynamics/fluid_dynamics/density_summation.cpp:38) | `Real sigma_i = mass_[index_i] * kernel_.W0(h_ratio_[index_i], ZeroVecd);` | 初始化求和 $\sigma_i$ 并计算粒子 $i$ 对自身的贡献 ($m_i W(0, h)$)。 |
| **底层实现 (邻居贡献)** | [`SPHinXsys/src/shared/particle_dynamics/fluid_dynamics/density_summation.cpp:41`](../../../../SPHinXsys/src/shared/particle_dynamics/fluid_dynamics/density_summation.cpp:41) | `sigma_i += inner_neighborhood.W_ij_[n] * mass_[inner_neighborhood.j_[n]];` | 遍历所有邻居 $j$，累加 $m_j W(\mathbf{r}_{ij}, h)$。 |
| **默认核函数** | [`SPHinXsys/src/shared/kernels/kernel_wendland_c2.cpp:19`](../../../../SPHinXsys/src/shared/kernels/kernel_wendland_c2.cpp:19) | `return pow(1.0 - 0.5 * q, 4) * (1.0 + 2.0 * q);` | 默认使用的 **Wendland C2 核函数** 的核心计算部分。 |

#### 2.3 动量方程 - 压力梯度项

*   **目的**: 计算由压力 $P$ 驱动的加速度。
*   **公式 (黎曼求解器格式)**: 采用声学黎曼求解器计算界面压力 $p^*$，以提高数值稳定性。
    $$
    \mathbf{F}_{\text{pressure}, i} = - \sum_j 2 p^* V_j \nabla_i W(\mathbf{r}_{ij}, h)
    $$

| 模块 | 文件地址 | 核心代码 | 对应功能 |
| :--- | :--- | :--- | :--- |
| **应用层调用** | [`poiseuille_flow_shell.cpp:313`](poiseuille_flow_shell.cpp:313) | `pressure_relaxation.exec(dt);` | 执行压力松弛（包括压力梯度力计算）。 |
| **底层实现 (求解 $p^*$)** | [`SPHinXsys/src/shared/physical_closure/materials/riemann_solver.h:110`](../../../../SPHinXsys/src/shared/physical_closure/materials/riemann_solver.h:110) | `Real p_star = average_state.p_ + 0.5 * rho0c0_geo_ave_ * u_jump * limited_mach_number;` | 声学黎曼求解器计算界面压力 $p^*$。 |
| **底层实现 (计算总力)** | `fluid_integration.hpp` (内部) | `Vecd force = -2.0 * interface_state.p_ * gradW_ij;` <br> `force_i += force * Vol_[index_j];` | 计算 $-2 p^* \nabla W$ 并乘以邻居体积 $V_j$，累加到总力 $\mathbf{F}_i$。 |

#### 2.4 动量方程 - 粘性项

*   **目的**: 计算流体内部摩擦力导致的加速度。
*   **公式 (Morris et al. 格式)**: 基于牛顿内摩擦定律 $\boldsymbol{\tau} \propto \mu \cdot (\text{应变率})$。
    $$
    \left( \frac{d\mathbf{v}}{dt} \right)_{\text{viscosity}, i} = \sum_j m_j \frac{2\mu}{\rho_i \rho_j} \frac{\mathbf{v}_{ij} \cdot \mathbf{r}_{ij}}{|\mathbf{r}_{ij}|^2 + \epsilon} \nabla_i W(\mathbf{r}_{ij}, h)
    $$

| 模块 | 文件地址 | 核心代码 | 对应功能 |
| :--- | :--- | :--- | :--- |
| **应用层调用** | [`poiseuille_flow_shell.cpp:303`](poiseuille_flow_shell.cpp:303) | `viscous_acceleration.exec();` | 执行粘性加速度计算。 |
| **底层实现 (计算应力)** | `viscous_dynamics.hpp` (内部) | `Real v_r_ij = vel_derivative.dot(e_ij);` <br> `Real fi_j = 2.0 * mu_(...) * v_r_ij / (r_ij + 0.01 * smoothing_length_);` | 计算应变率 $\frac{\mathbf{v}_{ij} \cdot \mathbf{r}_{ij}}{|\mathbf{r}_{ij}|^2}$，并乘以 $2\mu$ 得到粘性应力项 $f_{ij}$。 |
| **底层实现 (累加总力)** | `viscous_dynamics.hpp` (内部) | `viscous_force_i += fi_j * Vol_[index_j] * gradW_ij;` | 将粘性应力项代入SPH梯度算子，乘以邻居体积 $V_j$，累加到总粘性力 $\mathbf{F}_{\text{viscosity}, i}$。 |