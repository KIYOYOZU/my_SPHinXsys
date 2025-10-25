# 3D 槽道流动案例任务清单

> 依据《项目规划文档.md》《项目Case构建指南.md》，用于驱动 `test_3d_channel_flow` 案例的全流程迭代。

## 阶段 0：准备与资料确认
- [x] 通读《项目规划文档.md》并抽取关键接口。
- [x] 对照 2D/3D 参考案例，确认可复用模块与差异点。

## 阶段 1：物理需求与参数
- [x] 确认槽道长宽高、网格分辨率、入口/出口缓冲区长度。
- [x] 设定物性参数（`rho0_f`、`c_f`、`mu_f`），推导 `U_ref`、`dt_acoustic`、`dt_viscous`、驱动力。
- [x] 明确需要输出的观测量与采样频率。

## 阶段 2：代码骨架与几何建模
- [x] 在 `case_3d_channel_flow.cpp` 中实现 `ChannelGeometry` 与粒子生成。
- [x] 构建 `FluidBody` / `SolidBody` / `ObserverBody`，加入周期/壁面关系。
- [x] 实施入口注入或体力驱动的初始条件。

## 阶段 3：动力学与主循环
- [x] 配置时间步、密度求和、压力/粘性松弛、运输速度修正等模块。
- [x] 编写嵌套时间循环（Dt / dt_inner），接入周期边界更新。
- [x] 配置 `BodyStatesRecordingToVtp`、观测量、能量统计输出。

## 阶段 4：构建与测试支撑
- [x] 在 `CMakeLists.txt` 注册案例并更新 `tests/3d_examples/CMakeLists.txt`、`tests/CMakeLists.txt`。
- [x] 编写 `build.bat`/`run.bat` 或对应脚本以便一键构建运行。
- [x] 增补 `regression_test_tool/` 与 GTest 校验（若适用）。

## 阶段 5：计算、后处理与迭代
- [x] 编译并运行 3D 槽道算例，检查 VTP / 观测输出。
- [x] 按《SPHinXsys_Workflow_Cookbook.md》进行 MATLAB/Python 后处理，对比 3D 泊肃叶解析解。
- [x] 根据误差与粒子分布情况调整参数或算法（粒子增益、Transport Velocity、dt 设置等）。
- [x] 更新 `索引.md`、`CHANGELOG.md`、案例 README，整理复现说明。
- [x] 使用延长仿真时间（`end_time = 100.0`）重新运行并确认稳态达成（2025-10-21 最新运行通过 GTest，中心线误差 ≈1.9%，壁面法/展向残差 ≈ `7e-3`，`timing_summary.txt` 记录耗时 TickCount ≈ 1762 s / steady_clock ≈ 1876 s），必要时更新可视化与对比数据。
  - [x] 校核理论推导：针对平板泊肃叶流重新写出 `f_x = 12 μ U_bulk / (ρ H^2)` 的体力关系，确认当前实现与文档是否一致，并同步更新注释/规划文档。
  - [x] 移除或重构 `body_force_gain` 的经验系数，确保由物性参数唯一决定体力驱动；必要时引入守恒修正（如采用实际稳态平均速度回写）。
  - [x] 重新编译与运行 `test_3d_channel_flow.exe`，确保 GTest 通过；若仍失败，记录实际 `U_bulk`、`U_max`、`v_y/v_z` 残差并反馈到误差分析。
  - [x] 复跑 `preprocess_data.m`、`visualize_flow.m`，生成最新 `flow_data.mat` 与可视化摘要，更新误差、RMS 指标。
  - [x] 将结果与操作过程写入 `CHANGELOG.md` / `README.md` / `postprocess_summary.png` 注释区，并在 `项目规划文档.md` 中同步分析结论。

## 阶段 6：文档撰写与跨维度对比
- [x] 编写初版技术报告《technical_report.md》，基于源代码与核心库实现梳理几何建模、物性设定、动力学模块及时间积分的物理原理。
- [x] 新增 MATLAB 程序 `compare_umax_2d_vs_3d.m`，对比 2D 通道算例 (`umax.mat`) 与当前 3D 案例 (`flow_data.mat`) 的最大速度演化，并输出图像与数据。

## 阶段 7：文档修订与质量核查（2025-10-22）
- [x] 完成《technical_report_revised.md》，补充完整物理推导、源码行号对应关系、参数映射表与 ASCII 流程图。
- [x] 输出《ANALYSIS_REPORT.md》，逐条记录旧版技术报告的 13 处问题与修正依据。
- [x] 同步更新 `README.md`、`CHANGELOG.md`，在 0.5.0 版本中标记旧文档废弃并新增文档维护规范。
- [ ] 将分析报告中的待改进项（源码注释补充、额外断言、网格收敛性测试等）拆解为后续研发任务并纳入阶段规划。

- [x] 更新 README、CHANGELOG、技术报告及汇报版，写入新基准数据与结论；若数值行为出现异常，补充问题追踪与后续动作。

> 维护策略：完成项勾选 ✅ 并附运行日志，必要时新增子任务记录问题与解决方案。
