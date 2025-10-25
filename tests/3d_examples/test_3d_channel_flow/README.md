# test_3d_channel_flow

> 2025-10-22 更新：体力驱动切换为沿 `-x` 的恒定体力（`flow_direction = -1.0`）。以下指标来自同日完成的 100 s 反向驱动仿真（GTest 通过），速度为负号，括号中给出绝对值便于对照正向基线。

## 案例简介
- 三维泊肃叶通道流 (Plane Poiseuille)；周期边界沿 x/z，y 向为无滑移固壁。
- 体力驱动：恒定加速度 `body_force = flow_direction · 12 μ U_bulk / (ρ H²)`（当前 `flow_direction = -1.0`），目标雷诺数 100，对比解析抛物线。
- 观测输出：轴向/法向/展向三组 `ObserverBody`，配合 GTest 校验与 MATLAB 可视化脚本。

## 快速复现流程

### 1. 配置与编译
```powershell
.\build.bat
```
- 产生构建目录 `..\..\..\build_codex`，默认生成 `Release` 版。
- 成功后可执行文件位于:
  ```
  build_codex\tests\3d_examples\test_3d_channel_flow\bin\Release\test_3d_channel_flow.exe
  ```

### 2. 运行算例
```powershell
& ..\..\..\build_codex\tests\3d_examples\test_3d_channel_flow\bin\Release\test_3d_channel_flow.exe
```
- 运行时将生成 `output/` 下的:
  - VTP快照: `ChannelFluid_*.vtp` (约200帧)
  - 观测数据: `*Observer_Velocity.dat` (中心线/壁法向/展向)
  - 动能统计: `ChannelFluid_TotalKineticEnergy.dat`
  - 计时日志: `timing_summary.txt`
- 建议保证 `output/` 目录写权限，清理旧数据以避免冲突。

### 3. MATLAB 后处理
```matlab
% 在 MATLAB 中依次执行
preprocess_data               % 生成 flow_data.mat
visualize_flow                % 输出动画和特征曲线
```
- **preprocess_data.m**:
  - 解析所有VTP快照和观察点数据
  - 提取壁法向速度剖面并计算RMS误差
  - 输出: `flow_data.mat` (包含 `observer`, `analysis`, `config`)

- **visualize_flow.m**:
  - 生成三维流场动画: `channel_flow_animation.mp4`
  - 绘制速度剖面对比: `postprocess_summary.png`
  - 显示中心线速度时间演化

## 关键文件

### 核心程序
- **test_3d_channel_flow.cpp**: 主程序
  - 几何与粒子生成 (ChannelGeometry, WallBoundary)
  - SPH体系构建 (FluidBody, SolidBody, ObserverBody)
  - 动力学模块 (压力松弛, 粘性力, 周期边界)
  - GTest校验 (中心线+壁法向,容差0.05/0.02)

### 后处理脚本
- **preprocess_data.m**: VTP解析与数据聚合
- **visualize_flow.m**: 动画与可视化
- **compare_umax_2d_vs_3d.m**: 二维/三维对比分析
  - 输出: `output/umax_comparison.mat`, `umax_comparison.png`

### 构建与测试
- **build.bat**: CMake配置 + Visual Studio编译
- **CMakeLists.txt**: 项目构建配置
- **regression_test_tool/**: 回归测试工具链 (DTW误差评估)

### 文档
- **technical_report.md**: 旧版技术报告 (已废弃)
- **technical_report_revised.md**: 完整修订版技术报告 (推荐阅读)
  - 包含完整物理推导、源码引用、参数映射
  - 所有公式精确到源码行号
  - ASCII流程图和拓扑示意
- **ANALYSIS_REPORT.md**: 深度源码分析报告
  - 列出原技术报告中的13处错误
  - 验证方法和修正说明
- **CHANGELOG.md**: 版本变更历史
- **TODO_3d_channel_flow.md**: 开发任务清单

## 常见问题

### 构建失败
- **症状**: CMake找不到Simbody/TBB/Boost
- **解决**:
  1. 确认 `VCPKG_ROOT` 环境变量正确指向vcpkg安装目录
  2. 检查 `vcpkg integrate install` 是否已执行
  3. 手动指定工具链文件: `-DCMAKE_TOOLCHAIN_FILE=...`

### 输出为空
- **症状**: `output/` 目录下无VTP文件
- **解决**:
  1. 检查目录权限(不应为只读)
  2. 清理旧的 `sphinxsys.log`
  3. 查看控制台是否有错误信息

### MATLAB脚本报错
- **症状**: `preprocess_data.m` 提示文件不存在
- **解决**:
  1. 确保先运行C++程序生成 `output/ChannelFluid_*.vtp`
  2. 检查MATLAB当前目录是否在项目根目录
  3. 验证VTP文件是否损坏(用文本编辑器打开检查XML格式)

### VTP解析失败
- **症状**: MATLAB显示 "Skipping XXX.vtp"
- **原因**: VTP文件写入中断或XML格式错误
- **解决**:
  1. 删除损坏的VTP文件
  2. 重新运行模拟
  3. 如持续出现,检查磁盘空间和写权限

## 基准结果（2025-10-21, 100 s 运行）

### 仿真参数
```cpp
resolution_ref = 0.05     // 粒子间距
DL = 10.0, DH = 2.0, DW = 1.0   // 通道几何
Re = 100.0                // 雷诺数
U_bulk = 1.0              // 目标平均速度
end_time = 100.0 s        // 仿真时间
output_interval = 0.5 s   // 输出间隔 (200帧)
```

### 精度指标

**中心线速度** (数据源: `analysis.centerline_history`, `centerline_metrics.txt`):
- 峰值: `u_peak ≈ -1.5305` (|u| ≈ 1.5305) @ `t ≈ 96.45 s`
- 稳态平均: `u_mid ≈ -1.5265` (取 `t ∈ [80,100]` 共 39 样本)，相对解析解 `+1.77%`
- 最大绝对误差（最终剖面）: `max|u_theory - u_sim| ≈ 3.0×10⁻²`
- 中心线 RMS 误差: `≈ 2.66×10⁻²`

**壁法向速度剖面** (数据源: `analysis.wall_normal_profile`, 100 s 反向运行):
- RMS误差: `0.0182`
- 流向分量误差（平均绝对值）: `≈ 1.7×10⁻²`，最大 `≈ 2.7×10⁻²`
- 壁法向残差: `max|v_y| ≈ 9.7×10⁻³` (阈值 `2×10⁻²`)
- 展向残差: `max|v_z| ≈ 1.1×10⁻²`

**GTest验证状态**: ✅ 所有断言通过
- 中心线容差: `0.05 U_bulk` (5% 相对误差)
- 壁面容差: `0.02` (法向/展向速度)
- 实际裕度: `max(|v_y|, |v_z|) = 1.15e-2 < 2e-2` (≈1.7倍安全系数)

### 性能指标

**计算耗时** (来源: `output/timing_summary.txt` 2025-10-22 run):
- TickCount计时: `≈ 1669 s`
- steady_clock计时: `≈ 1772 s`
- 平均每帧耗时: `≈ 9.0 s/frame`
- 加速比: `≈ 0.056` (100 s / 1772 s)

**粒子统计**:
- 流体粒子数: `≈ 160,000` (200×40×20层)
- 壁面粒子数: `≈ 8,000` (顶+底双层网格)
- 观察点总数: `113` (41+51+21)

**输出文件**:
- VTP快照: `200 × 约2MB ≈ 400MB`
- 观察点数据: `3 × 约1MB ≈ 3MB`
- MAT文件: `flow_data.mat ≈ 50MB`
- 动画: `channel_flow_animation.mp4 ≈ 10MB`

### 二维对比分析

**数据来源**: `compare_umax_2d_vs_3d.m` 生成的 `umax_comparison.mat`

**峰值速度对比**:
| 案例 | 峰值 u_max | 稳态平均 | 相对解析解 | 数据源 |
|------|------------|----------|------------|--------|
| 2D | 1.5554 | 1.5489 | +3.7% | `umax.mat` (2D案例) |
| 3D | `u_max ≈ -1.5305` (|u| ≈ 1.5305) | `u_steady ≈ -1.5265` (|u| ≈ 1.5265) | +1.8% | `flow_data.mat` (2025-10-22 反向驱动) |
| 解析解 | 1.5000 | 1.5000 | - | 理论公式 |

### 附加验证：初速 `(+1,0,0)` + 体力 `-x`

- 目的：检验周期边界是否能处理“初始流向正、体力驱动负”这种非对齐配置。  
- 结果（100 s 运行，保持体力 `flow_direction_body = -1.0`，初速 `flow_direction_initial = +1.0`）：  
  - `u_peak ≈ -1.5096` (|u| ≈ 1.5096) @ `t ≈ 99.71 s`  
  - 稳态平均 `u_mid ≈ -1.4928` (39 样本)  
  - 中心线最大绝对误差 `≈ 1.03×10⁻²`，RMS `≈ 7.2×10⁻³`  
  - 壁面 RMS `≈ 3.5×10⁻³`，`max|v_y| ≈ 1.15×10⁻²`，`max|v_z| ≈ 9.7×10⁻³`  
  - 计时：`TickCount ≈ 1567 s` / `steady_clock ≈ 1664 s`  
- 结论：周期边界在流向交替条件下依旧稳定，初始正向动量会在数十秒内被反向体力取代，未出现粒子堆积或镜像失配。

**时间演化差异**:
- 初期 (t∈[0,10]): `⟨Δu⟩ ≈ -1.18×10⁻³` (几乎重合)
- 稳态 (t∈[80,100]): `⟨Δu⟩ ≈ -2.41×10⁻²` (3D显著偏低)
- 最大偏差: `Δu_min = -2.95×10⁻² @ t=99.51s`

**物理解释**:
- 三维展向周期增加了邻域粒子数
- 更多壁面接触导致粘性耗散增强
- 因此3D峰值速度更低,更接近理论值

## 技术文档索引

### 新手入门路径
1. **README.md** (本文件): 快速复现和基准结果
2. **technical_report_revised.md**: 完整技术原理
   - 第1-3节: 几何、物性、体系构建
   - 第4节: 动力学模块详解 (配合源码阅读)
   - 第7节: 物理结果与验证

### 深度学习路径
1. **technical_report_revised.md**: 逐节阅读
   - 包含完整物理推导
   - 所有源码精确到行号
   - 参数映射表和ASCII流程图
2. **ANALYSIS_REPORT.md**: 理解文档修订过程
   - 列出原技术报告的13处错误
   - 验证方法和修正说明
3. **SPHinXsys库源码**:
   - `fluid_integration.h/.hpp`: 压力/密度松弛
   - `viscous_dynamics.h/.hpp`: 粘性力计算
   - `domain_bounding.h`: 周期边界条件

### 开发者路径
1. **TODO_3d_channel_flow.md**: 任务清单和进度
2. **CHANGELOG.md**: 版本变更历史
3. **CLAUDE.md**: AI辅助开发工作流
4. **CMakeLists.txt**: 构建配置

## 文档维护规范

**更新README时需要同步**:
- 基准结果章节: 与最新运行数据一致
- 性能指标: 更新计时和文件大小
- 常见问题: 新增遇到的问题和解决方案

**更新技术报告时需要**:
- 所有源码引用精确到行号
- 公式推导从基本方程出发
- 数值结果指明数据源脚本
- 增加ASCII图和参数映射表

**提交前检查**:
- [ ] GTest全部通过
- [ ] MATLAB脚本成功运行
- [ ] `flow_data.mat` 已生成
- [ ] 文档中的数值与实际一致
- [ ] CHANGELOG已更新

## 变更记录
详见同目录 `CHANGELOG.md`。重大变更:
- **v0.5.0 (2025-10-22)**: 完整修订技术报告,修正13处错误
- **v0.4.0 (2025-10-21)**: 100s稳态验证与2D/3D对比
- **v0.3.0 (2025-10-21)**: 60s运行与计时记录
- **v0.2.0 (2025-10-21)**: 体力驱动校准与稳态验证

## 相关资源

**SPHinXsys官方**:
- 主仓库: https://github.com/Xiangyu-Hu/SPHinXsys
- 文档: https://www.sphinxsys.org/
- API参考: https://xiangyu-hu.github.io/SPHinXsys/

**参考案例** (同框架):
- 2D槽道流: `tests/2d_examples/test_2d_channel_flow_fluid_shell/`
- 3D泊肃叶流(圆管): `tests/3d_examples/test_3d_poiseuille_flow_shell/`
- FVM通道流: `tests/3d_examples/test_3d_FVM_incompressible_channel_flow/`

**理论背景**:
- Poiseuille流解析解: Batchelor "An Introduction to Fluid Dynamics" §5.3
- SPH方法: Liu & Liu "Smoothed Particle Hydrodynamics" (2003)
- 周期边界: Monaghan "Smoothed Particle Hydrodynamics" (2005)

---

**文档版本**: 1.1 (2025-10-22)
**对应仿真**: `end_time=100s`, `h=0.05`, `Re=100`
**维护者**: [项目团队]
