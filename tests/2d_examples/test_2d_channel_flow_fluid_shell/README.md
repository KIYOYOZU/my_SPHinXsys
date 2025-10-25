# 2D Channel Flow with Fluid-Shell Interaction
# 二维槽道流体-壳体耦合仿真

[![SPHinXsys](https://img.shields.io/badge/Framework-SPHinXsys-blue)](https://www.sphinxsys.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](https://opensource.org/licenses/Apache-2.0)
[![Language](https://img.shields.io/badge/Language-C++%20%7C%20MATLAB-orange)]()

> 使用光滑粒子流体动力学(SPH)方法模拟经典的二维泊肃叶流动，验证流体-壳体耦合算法的准确性。

---

## 📖 目录

- [项目概览](#项目概览)
- [物理模型](#物理模型)
- [快速开始](#快速开始)
- [项目结构](#项目结构)
- [数值方法](#数值方法)
- [数据处理与可视化](#数据处理与可视化)
- [验证与测试](#验证与测试)
- [配置参数](#配置参数)
- [进阶文档](#进阶文档)
- [项目历程](#项目历程)
- [常见问题](#常见问题)
- [参考文献](#参考文献)

---

## 项目概览

### 研究背景

二维泊肃叶流(Poiseuille Flow)是流体力学中的经典问题，具有解析解，是验证数值方法准确性的理想测试算例。本项目使用SPHinXsys框架，通过全局体力驱动实现周期性边界条件下的层流模拟。

### 关键特性

- ✅ **理论验证**: 与Navier-Stokes解析解对比，误差<5%
- ✅ **流固耦合**: 使用壳体(Shell)粒子处理壁面边界
- ✅ **周期性边界**: X方向完全周期，Y方向壁面约束
- ✅ **自动化测试**: 集成Google Test单元测试
- ✅ **完整工作流**: 从仿真、数据处理到可视化的全流程

### 技术栈

| 组件 | 技术 | 用途 |
|------|------|------|
| 主仿真 | C++17 + SPHinXsys | SPH数值求解 |
| 构建系统 | CMake 3.16+ | 跨平台编译 |
| 数据处理 | MATLAB R2019b+ | VTP解析、MAT存储 |
| 可视化 | MATLAB + ParaView | 动画生成、流场分析 |
| 测试框架 | Google Test | 自动化验证 |

---

## 物理模型

### 控制方程

二维不可压缩粘性流动Navier-Stokes方程:

```math
\frac{\partial \mathbf{u}}{\partial t} + (\mathbf{u} \cdot \nabla)\mathbf{u} = -\frac{1}{\rho}\nabla p + \nu \nabla^2 \mathbf{u} + \mathbf{f}
```

其中驱动体力 $\mathbf{f} = (f_x, 0)$ 模拟恒定压力梯度。

### 理论解

稳态速度分布(抛物线型):

```math
u(y) = U_{max}\left[1 - \left(\frac{2y}{DH} - 1\right)^2\right], \quad U_{max} = 1.5 U_f
```

最大速度出现在通道中心线 $y = DH/2$。

### 关键参数

| 参数 | 符号 | 数值 | 物理意义 | 代码位置 |
|------|------|------|----------|---------|
| 通道长度 | $DL$ | 10.0 | 周期长度 | `channel_flow_shell.cpp:13` |
| 通道高度 | $DH$ | 2.0 | 壁面间距 | `channel_flow_shell.cpp:14` |
| 流体密度 | $\rho_0$ | 1.0 | 参考密度 | `channel_flow_shell.cpp:18` |
| 雷诺数 | $Re$ | 100.0 | $\frac{\rho U_f DH}{\mu}$ | `channel_flow_shell.cpp:21` |
| 动力粘度 | $\mu_f$ | 0.02 | 自动计算 | `channel_flow_shell.cpp:22` |
| 驱动力 | $f_x$ | 0.36 | $\frac{12\mu U_f}{\rho DH^2}$ | `channel_flow_shell.cpp:207` |

### 边界条件

```
                Y
                ↑
    ════════════════════════  ← 壁面(Shell粒子, 无滑移)
    →→→→→→→→→→→→→→→→→→→→→→  ← 流体域(周期性流动)
    ════════════════════════  ← 壁面(Shell粒子, 无滑移)
    ↓─────────── X ─────────→
    |← DL = 10.0 →|
```

- **X方向**: 周期性边界(流体粒子从右边界离开后从左边界重新进入)
- **Y方向**: 壳体壁面(施加无滑移边界条件)

---

## 快速开始

### 前置条件

- **操作系统**: Windows 10/11 (Linux/macOS需调整`build.bat`)
- **编译器**: Visual Studio 2022 (MSVC 14.3+)
- **CMake**: 3.16 或更高版本
- **MATLAB**: R2019b 或更高版本(用于数据处理)
- **SPHinXsys**: 已编译的库(需先构建整个SPHinXsys项目)

### 三步运行

```bash
# Step 1: 首次配置 (仅需执行一次，在SPHinXsys根目录)
cd D:\path\to\SPHinXsys
mkdir build && cd build
cmake .. -G "Visual Studio 17 2022" -A x64
cmake --build . --config Debug

# Step 2: 编译并运行仿真 (在本算例目录)
cd tests\2d_examples\test_2d_channel_flow_fluid_shell
.\build.bat

# Step 3: 数据处理和可视化 (MATLAB)
matlab -r "process_velocity_data; visualize_velocity_field;"
```

### 预期输出

**仿真阶段** (`build.bat`):
- `output/` 目录: 包含200个VTP文件 (`WaterBody_*.vtp`, `Wall_*.vtp`)
- 屏幕输出: 每100步显示物理时间和时间步长

**数据处理** (`process_velocity_data.m`):
- `velocity_data.mat` (约30MB): 完整时空速度场
- `umax.mat` (约20KB): 最大速度时间序列

**可视化** (`visualize_velocity_field.m`):
- `UmaxFromU0.jpg`: 收敛曲线对比图
- MATLAB动画窗口: 左侧为速度云图，右侧为剖面对比

---

## 项目结构

```
test_2d_channel_flow_fluid_shell/
│
├── 📄 核心源代码
│   ├── channel_flow_shell.cpp          主仿真程序 (362行)
│   └── CMakeLists.txt                   CMake构建配置
│
├── 🔧 构建与运行
│   └── build.bat                        Windows一键编译运行脚本
│
├── 📊 数据处理
│   ├── process_velocity_data.m          VTP → MAT数据提取
│   └── visualize_velocity_field.m       流场动画 + 收敛曲线
│
├── 📚 文档系统
│   ├── README.md                        本文档(项目概览)
│   ├── CHANGELOG.md                     版本变更历史
│   ├── 索引.md                          功能-代码快速定位
│   └── SPHinXsys_Workflow_Cookbook.md   可复现工作流程手册
│
└── 📁 输出目录
    ├── output/                          最新仿真结果
    ├── output_backup/                   历史数据备份
    ├── velocity_data.mat                处理后的速度数据
    └── umax.mat                         收敛曲线数据
```

### 核心文件说明

#### `channel_flow_shell.cpp` (主仿真程序)

| 模块 | 行号 | 功能 |
|------|------|------|
| 几何定义 | 13-36 | 通道尺寸、流体域多边形 |
| 粒子生成器 | 41-72 | 自定义壁面壳体粒子生成 |
| 观察点布置 | 77-109 | 轴向51点 + 径向21点 |
| 初始条件 | 115-127 | 均匀初始速度场 |
| 主仿真函数 | 129-355 | 物理体、数值方法、时间循环 |
| Google Test | 357-362 | 自动化验证测试 |

#### MATLAB脚本特性对比

| 特性 | `process_velocity_data.m` | `visualize_velocity_field.m` |
|------|---------------------------|------------------------------|
| 输入 | VTP文件 | velocity_data.mat |
| 处理 | XML解析、数据提取 | 分箱平均、理论解对比 |
| 输出 | MAT文件 | 图片 + 动画 |
| 关键技术 | 正则表达式、动态变量命名 | accumarray、双子图同步 |
| 运行时间 | ~2分钟(200帧) | ~30秒(绘图) |

---

## 数值方法

### SPH离散化

**核心算法**: 弱可压缩光滑粒子流体动力学(WCSPH)

**时间积分**: Verlet分步格式
```
1️⃣ 半步预测:  密度、压力、加速度计算 (Riemann求解器)
2️⃣ 全步更新:  速度、位置更新
3️⃣ 半步校正:  密度二次松弛 (无Riemann)
4️⃣ 修正步:    传输速度修正、粒子位移约束
```

### 关键数值组件

| 组件 | SPHinXsys类名 | 物理作用 |
|------|--------------|---------|
| 压力松弛 | `Integration1stHalfWithWallRiemann` | 流体-壳体动量交换(考虑Riemann求解) |
| 密度松弛 | `Integration2ndHalfWithWallNoRiemann` | 密度场平滑(简化边界处理) |
| 粘性力 | `ViscousForceWithWall` | 壁面剪切力计算 |
| 传输速度修正 | `TransportVelocityCorrectionComplex` | 抑制零能模式、稳定密度场 |
| 周期性边界 | `PeriodicAlongAxis` | X方向粒子跨边界连接 |

### 时间步长控制

**声波时间步** (CFL条件):
```math
\Delta t_{acoustic} = 0.4 \frac{h}{c_f + U_{max}}
```

**对流时间步**:
```math
\Delta t_{advection} = 0.25 \frac{h}{U_{max}}
```

实际时间步长: $\Delta t = \min(\Delta t_{acoustic}, \Delta t_{advection})$

典型值: $\Delta t \approx 0.001$ 秒

---

## 数据处理与可视化

### 工作流程

```
VTP文件 → [process_velocity_data.m] → MAT文件 → [visualize_velocity_field.m] → 图表/动画
```

### 数据提取 (`process_velocity_data.m`)

**处理逻辑**:
1. 扫描 `output/WaterBody_*.vtp`
2. 正则表达式提取时间ID: `regexp(filename, 'WaterBody_(\d+)', 'tokens')`
3. XML解析获取:
   - 粒子位置: `<PointData> → <DataArray Name="Position">`
   - 速度分量: `<DataArray Name="Velocity">`
4. 计算衍生量: $U_{mag} = \sqrt{u^2 + v^2}$, $U_{max} = \max(U_{mag})$
5. **自动提取物理参数**: 从`channel_flow_shell.cpp`读取DL, DH, U_f, Re (v2.2.0新增)
6. 排序并保存到`velocity_data.mat`

**容错机制**:
- 跳过损坏的VTP文件
- 处理缺失速度场
- 多路径查找C++源文件

**多工况支持**:
- 根据初始速度自动生成变量名(如 `u0_1_0` 表示初速1.0)
- 追加模式: 多次运行可累积不同工况数据
- 统一时间基准: 物理时间 = `time_id × 1e-6`

**输出文件**:
- `velocity_data.mat`: 包含完整速度场数据和`sim_config`配置结构
- `umax.mat`: 各工况的Umax时间序列

### 可视化 (`visualize_velocity_field.m`)

**用户配置** (v2.2.0新增):
```matlab
% 在脚本顶部修改配置
config.save_animation = true;            % 是否保存动画
config.output_format = 'mp4';           % 'mp4' | 'gif' | 'none'
config.output_filename = 'my_animation'; % 输出文件名
config.frame_rate = 20;                 % 视频帧率
config.animation_speed = 2.0;           % 2倍速播放
config.show_progress = true;            % 显示进度条
```

**任务1: Umax收敛曲线**

```matlab
% 自动加载所有工况数据
load('umax.mat');

% 多工况对比绘图(自动排序和颜色映射)
for each case:
    plot(time, Umax, 'Color', colormap(case_id), 'LineWidth', 2);
end

% 叠加理论值
yline(1.5, '--r', 'LineWidth', 2, 'DisplayName', '理论稳态值');
```

**关键发现**:
- 收敛时间: 约 30-50 秒
- 稳态值: 1.55 (理论值1.5, 超调约3.3%)
- 初速越大，收敛越快

**任务2: 流场双视图动画**

| 子图 | 内容 | 技术要点 |
|------|------|---------|
| 左侧 | 速度场散点图 | `scatter(x, y, 10, Umag, 'filled')`, `caxis([0,2])` |
| 右侧 | 中心线剖面 | 分箱平均处理散乱数据, 红线为理论解 |

**性能优化** (v2.2.0):
- 全局范围预计算,避免循环内重复
- 变速播放支持(`animation_speed`参数)
- 进度条实时反馈

**自动参数加载** (v2.2.0):
- 从`velocity_data.mat`自动读取物理参数(DL, DH, U_f等)
- 向后兼容:若配置缺失,回退到默认值

**动画导出** (v2.2.0新增):
- MP4视频: MPEG-4编码,可自定义帧率
- GIF动图: 256色索引,无限循环
- 一键保存,适合论文插图

**分箱平均算法**:
```matlab
% 从散乱粒子提取中心线数据
centerline_particles = abs(x - DL/2) < tolerance;
y_center = y(centerline_particles);
u_center = u(centerline_particles);

% 分箱平均
[y_bins, ~, bin_idx] = unique(round(y_center / bin_size) * bin_size);
u_binned = accumarray(bin_idx, u_center, [], @mean);
```

---

## 验证与测试

### 自动化测试

**测试框架**: Google Test (`gtest`)

**测试用例**: `channel_flow_shell.thickness_10x`

**测试代码** (`channel_flow_shell.cpp:357-362`):
```cpp
TEST(channel_flow_shell, thickness_10x)
{
    channel_flow_shell(); // 运行完整仿真
    // 测试在仿真函数内部自动执行(Lines 332-355)
}
```

**验证逻辑** (Lines 332-355):
```cpp
// 1. 计算理论解
Real umax_theory = 1.5 * U_f;
for (size_t i = 0; i < observation_location.size(); ++i) {
    Real y = observation_location[i][1];
    Real u_theory = umax_theory * (1.0 - pow((2.0 * y / DH - 1.0), 2));

    // 2. 提取数值解
    Real u_numerical = velocity[i][0];

    // 3. 相对误差检验
    EXPECT_NEAR(u_numerical, u_theory, 0.05 * u_theory); // ±5%容差
}
```

**观察点布置**:
- **轴向**: 51个点均匀分布在 $x \in [0.5, 9.5]$, $y = DH/2$
- **径向**: 21个点均匀分布在 $x = DL/2$, $y \in [0.1, 1.9]$
- 总计: 72个观察点

### 验证结果

| 指标 | 理论值 | 数值值 | 相对误差 |
|------|--------|--------|---------|
| $U_{max}$ | 1.50 | 1.55 | +3.3% |
| 抛物线形状 | 解析解 | 拟合良好 | <5% |
| 收敛时间 | N/A | 30-50秒 | - |

**误差来源分析**:
1. **离散化误差**: 粒子分辨率 $h = 0.05$
2. **边界处理**: 壳体粒子近似
3. **弱可压缩性**: 声速有限 $c_f = 10 U_f$ (Mach数 $\approx 0.1$)
4. **传输速度修正**: 人为引入的正则化

---

## 配置参数

### 快速修改指南

#### 1️⃣ 修改雷诺数

**文件**: `channel_flow_shell.cpp`

```cpp
// Line 21: 修改这一行
Real Re = 200.0; // 原值100.0
```

**影响**:
- `mu_f` 自动重新计算 (`Line 22`)
- 驱动力 `fx` 自动调整 (`Line 207`)
- 理论 $U_{max}$ 不变

#### 2️⃣ 修改初始速度

**文件**: `channel_flow_shell.cpp`

```cpp
// Line 124: InitialVelocity类的apply函数
void apply(size_t index_i, Real dt)
{
    vel_[index_i] = Vec2d(2.0, 0.0); // 原值(1.0, 0.0)
}
```

**影响**:
- 改变收敛速度
- 数据处理脚本会自动生成新的工况标签(如 `u0_2_0`)

#### 3️⃣ 修改通道几何

**文件**: `channel_flow_shell.cpp`

```cpp
// Lines 13-14
Real DL = 20.0; // 原值10.0
Real DH = 4.0;  // 原值2.0
```

**注意事项**:
- 需同步修改 `WaterBlock` 形状定义 (`Lines 33-35`)
- 观察点位置可能需要调整 (`Lines 77-109`)

#### 4️⃣ 修改粒子分辨率

**文件**: `channel_flow_shell.cpp`

```cpp
// Line 359: 测试用例参数
resolution_ref = 0.025; // 原值0.05 (分辨率提高2倍)
```

**影响**:
- 粒子数量增加 $2^d$ 倍 (d=维度)
- 计算时间显著增加 (约8倍, 因$O(N \log N)$)
- 精度提升

#### 5️⃣ 修改模拟时长

**文件**: `channel_flow_shell.cpp`

```cpp
// Line 250
Real end_time = 200.0; // 原值100.0

// Line 251: 同步调整输出间隔
Real output_interval = 1.0; // 原值0.5 (避免输出文件过多)
```

### 参数对照表

| 参数类别 | 参数名 | 代码位置 | 默认值 | 典型范围 |
|---------|--------|---------|--------|---------|
| **几何** | DL, DH | Lines 13-14 | 10.0, 2.0 | [5, 50], [1, 10] |
| **流体** | rho0_f | Line 18 | 1.0 | [0.8, 1.2] |
| | U_f | Line 19 | 1.0 | [0.1, 10] |
| | c_f | Line 20 | 10.0 | [5, 20]×U_f |
| | Re | Line 21 | 100.0 | [10, 1000] |
| **数值** | resolution_ref | Line 359 | 0.05 | [0.01, 0.1] |
| | thickness_multiplier | Line 360 | 10.0 | [5, 20] |
| **时间** | end_time | Line 250 | 100.0 | [10, 500] |
| | output_interval | Line 251 | 0.5 | [0.1, 2.0] |

---

## 进阶文档

本项目提供**三层文档体系**,适合不同需求:

### 1️⃣ CHANGELOG.md - 版本历史

**适用对象**: 维护者、贡献者

**内容**:
- 符合 [Keep a Changelog](https://keepachangelog.com/) 规范
- 详细记录每次变更的动机和影响
- 包含重大重构说明(如v2.0.0的驱动方式变更)

**典型条目**:
```markdown
## [2.0.0] - 2025-09-29
### Changed
- **核心变更**: 从"入口速度缓冲带"改为"全局体力驱动"
  - 修复了驱动力系数错误(8.0 → 12.0)
  - 使模拟与经典流体力学模型完全对齐
```

### 2️⃣ 索引.md - 功能定位

**适用对象**: AI助手、代码修改者

**内容**:
- 功能到代码的精确映射(行号级别)
- 多种用户描述方式(别名支持)
- 修改指引和注意事项

**示例**:
```markdown
## 流体参数设置
**用户可能的描述方式**: 雷诺数/粘度/密度设置

**代码位置**: `channel_flow_shell.cpp:18-22`

**修改建议**: 只需修改Re, mu_f会自动计算
```

### 3️⃣ SPHinXsys_Workflow_Cookbook.md - 工作手册

**适用对象**: 新手、复现者

**内容**:
- 零假设的完整操作步骤
- 关键命令和屏幕输出示例
- 常见陷阱和解决方法

**特色**:
- ✅ 每步预期输出
- ⚠️ 易错点提示
- 💡 技术原理解释

---

## 项目历程

### 版本时间线

```
v1.0.0 (2024-09-28)
  └─ 初始实现: 入口速度缓冲带 + 抛物线强制
      ↓ 发现问题: 驱动方式不符合经典流体力学

v2.0.0 (2025-09-29) ⭐ 重大重构
  ├─ 改为全局体力驱动(模拟压力梯度)
  ├─ 修复驱动力系数错误
  ├─ 新增Umax收敛曲线分析
  └─ 延长模拟时间(10s → 100s)
      ↓ 功能扩展

v2.1.0 (2025-09-29)
  ├─ 增加可配置初始速度功能
  ├─ 增强可视化(标记数值稳态解)
  └─ 完善文档体系(三层文档)
```

### 关键设计决策

**Q1: 为何从"入口速度"改为"全局体力"?**

**A1**:
- **旧方法问题**: 在入口区域强制设置抛物线速度,物理上不自洽
- **新方法优势**:
  - 符合经典泊肃叶流的压力梯度驱动
  - 完全周期性边界(无需特殊入口处理)
  - 收敛到理论稳态解

**Q2: 为何壁厚设为10倍分辨率?**

**A2**:
- SPHinXsys壳体粒子法要求: 壁厚需足够容纳曲率计算
- 经验值: 5-20倍分辨率(10倍为最佳权衡)
- 太薄: 曲率计算不准确
- 太厚: 计算成本增加

**Q3: 为何存在3.3%的超调?**

**A3**:
- **根本原因**: 传输速度修正引入的人为正则化
- **物理意义**: 抑制零能模式(spurious pressure oscillations)
- **可接受性**: 工程精度范围内,远小于±5%测试容差

---

## 常见问题

### Q1: 编译失败 - 找不到sphinxsys_2d库

**原因**: 未先编译SPHinXsys主项目

**解决方法**:
```bash
cd D:\path\to\SPHinXsys\build
cmake --build . --config Debug --target sphinxsys_2d
```

### Q2: VTP文件损坏或无速度数据

**现象**: `process_velocity_data.m` 报错或跳过某些文件

**原因**:
1. 仿真中途异常终止
2. 输出时间点不含速度场

**解决方法**:
- 检查仿真日志
- 脚本已内置容错,会自动跳过

### Q3: 收敛曲线不光滑

**现象**: Umax随时间震荡

**可能原因**:
1. 初始速度场与稳态相差太大
2. 粒子分辨率过低
3. 时间步长过大

**解决方法**:
- 降低初始速度
- 提高分辨率(减小 `resolution_ref`)
- 检查CFL条件

### Q4: 如何加速仿真?

**方法1**: 降低分辨率
```cpp
resolution_ref = 0.1; // 原值0.05, 速度提升约4倍
```

**方法2**: 减少输出频率
```cpp
output_interval = 2.0; // 原值0.5, 输出文件减少75%
```

**方法3**: 使用Release模式编译
```bash
cmake --build . --config Release
```

### Q5: 如何扩展到三维?

**步骤**:
1. 将 `#include "2d_channel_flow_shell.h"` 改为3D头文件
2. 修改几何定义为 `Vec3d`
3. 增加Z方向周期性边界
4. 调整CMakeLists.txt链接 `sphinxsys_3d`

**参考**: `tests/3d_examples/test_3d_poiseuille_flow_shell/`

---

## 参考文献

### 理论基础

1. **泊肃叶流**:
   - Poiseuille, J. L. M. (1846). *Experimental research on the movement of liquids in tubes of very small diameters*. Comptes Rendus, 11, 961-967.

2. **SPH方法**:
   - Monaghan, J. J. (2005). *Smoothed particle hydrodynamics*. Reports on Progress in Physics, 68(8), 1703.

3. **弱可压缩SPH**:
   - Morris, J. P., Fox, P. J., & Zhu, Y. (1997). *Modeling low Reynolds number incompressible flows using SPH*. Journal of Computational Physics, 136(1), 214-226.

### SPHinXsys框架

- **官方文档**: [https://www.sphinxsys.org/](https://www.sphinxsys.org/)
- **GitHub仓库**: [https://github.com/Xiangyu-Hu/SPHinXsys](https://github.com/Xiangyu-Hu/SPHinXsys)
- **论文**:
  - Zhang, C., et al. (2020). *SPHinXsys: An open-source meshfree multi-physics and multi-resolution library*. Computer Physics Communications, 267, 108066.

### 相关算例

- **2D Taylor-Green涡**: [example5_2D_tayloygreen](https://www.sphinxsys.org/html/examples/example5_2D_tayloygreen.html)
- **3D泊肃叶流**: `tests/3d_examples/test_3d_poiseuille_flow_shell/`

---

## 许可证

本项目遵循 [Apache License 2.0](https://opensource.org/licenses/Apache-2.0)

---

## 联系方式

- **问题反馈**: 在项目目录创建 `issues.txt`
- **技术支持**: 参考 [SPHinXsys论坛](https://www.sphinxsys.org/forum/)

---

## 致谢

感谢SPHinXsys开发团队提供的优秀框架和详细文档。

---

**最后更新**: 2025-10-02
**文档版本**: v3.0
**适用代码版本**: v2.1.0
