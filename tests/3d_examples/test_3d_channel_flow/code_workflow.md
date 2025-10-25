# test_3d_channel_flow 开发工作流

本文档整理当前案例的通用开发流程，供后续迭代或新成员参考。每个阶段建议采用固定的文件与格式，以保证协作一致性。

---

## 1. 立项准备

- **文档阅读顺序**
  1. `项目规划文档.md`（掌握总体目标与交付阶段）。
  2. `项目Case构建指南.md`、`SPHinXsys_Workflow_Cookbook.md`（了解约定俗成的流程、脚本接口）。
  3. 相关基准案例（如 `tests/2d_examples/test_2d_channel_flow_fluid_shell`）。
- **记录方式**
  - 在 `TODO_3d_channel_flow.md` 的“阶段 0”中确认勾选。
  - 如需额外调研，可在文档末尾增加“补充资料”小节（使用 `- [ ]` 列表）。

---

## 2. TODO 清单维护

- **位置**：`TODO_3d_channel_flow.md`
- **结构建议**：按阶段（阶段 0~6）分组，每项用复选框 `- [ ]` 表示；完成后改为 `- [x]`，并可附结果摘要或日志路径。
- **新增任务**：出现新的需求时，直接在对应阶段追加条目，必要时列出子任务。
- **模板示例**：
  ```markdown
  ## 阶段 5：计算、后处理与迭代
  - [ ] 编译并运行最新配置
    - [ ] 记录 GTest 输出与 `timing_summary.txt`
  - [ ] 生成 MATLAB 后处理结果
  ```

---

## 3. 代码实现循环

1. **geometry / material 准备**（`test_3d_channel_flow.cpp`）  
   - 常量定义、几何类与粒子生成器。
   - 可在注释中注明量纲与参考信息。
2. **动力学配置**  
   - 先创建关联（`InnerRelation` / `ContactRelation` / `ComplexRelation`）。
   - 再实例化时间步、压力松弛、粘性、传输修正等模块；遇到不熟悉的类，使用 `rg` 在 `src/shared/particle_dynamics` 搜源码。
3. **主循环与输出**  
   - 结构：外层对流步 → 内层声学子步 → 输出 → 计时。必要时增加 `ParticleSorting`、日志。  
   - 所有新增常量或流程应在 `technical_report.md` 中有对应解释。
4. **CMake 维护**  
   - 新增 MATLAB / 脚本需在 `CMakeLists.txt` 中用 `set_source_files_properties(... HEADER_FILE_ONLY ON)` 排除编译。

---

## 4. 构建与运行

- **命令规范**
  ```powershell
  .\build.bat                      # 生成 build_codex/（建议重定向到 logs/build_*.log）
  cmake --build ..\..\..\build_codex --target test_3d_channel_flow --config Release --clean-first  # 必要时强制重编译
  & ..\..\..\build_codex\tests\3d_examples\test_3d_channel_flow\bin\Release\test_3d_channel_flow.exe
  ```
- **MATLAB 批处理**（顺序执行，下述命令可写入 README）
  ```powershell
  matlab -batch "preprocess_data; exit"
  matlab -batch "visualize_flow; exit"
  matlab -batch "compare_umax_2d_vs_3d; exit"
  ```
- **产物整理**
  - `output/`：保留 VTP、观察点 `.dat`、`channel_flow_animation.mp4`、`postprocess_summary.png`、`timing_summary.txt`、`umax_comparison.*`。
  - `logs/`：保存每次构建的日志文件。

---

## 5. 文档写法

- **`README.md`**  
  - `## 快速复现流程`：列出编译、运行、后处理命令。  
  - `## 基准结果（YYYY-MM-DD, NN s 运行）`：罗列误差、峰值、计时等指标。  
  - `## 关键文件` 与 `## 变更记录`（链接到 `CHANGELOG.md`）。
- **`technical_report.md`**  
  - 按章节描述：几何建模 → 物性 → 动力学模块 → 时间积分 → 结果对比。  
  - 引用源码时放置文件与行号（如 `test_3d_channel_flow.cpp:219-223`）。  
  - 更新最新运行参数（如 100 s 耗时、峰值、误差等）。
- **技术文档撰写准则（来自团队复盘要求）**  
  1. **源码定位必须精确**：每个步骤对应 `文件:行号`，涉及库函数需补充头文件位置（如 `domain_bounding.h:33-189`），便于读者快速跳转。  
  2. **物理推导要写全**：给出关键公式（例如泊肃叶解析解、体力推导）与变量含义，而不是只写结论；必要时列出假设条件。  
  3. **图示优先 ASCII**：在 Markdown 中用文本方框/箭头画出流程或拓扑，保证无图片也能理解。  
  4. **比较分析需配数据**：二维/三维或版本差异，必须说明数据来源（文件或脚本）、时间段以及统计方式；推荐列出均值/峰值/最小值。  
  5. **测试说明同步记录**：若引入/修改 GTest 或回归脚本，应写明断言含义、阈值选择依据、失败时的诊断方法。  
  6. **“物理公式 + 源码” 联动**：在强化段落时，先从代码提炼出物理关系（示例：`test_3d_channel_flow.cpp:219-223` → `f_x = 12 μ U_bulk /(ρ DH^2)`），再写出公式并标注代码路径，确保读者知道公式来源与常量定义位置。
  7. **数值结果要回链数据源**：引用误差、峰值、RMS、差值等指标时，说明数据采样脚本（如 `preprocess_data.m`、`compare_umax_2d_vs_3d.m`）与具体字段，必要时写出计算公式，避免文字与数据脱节。
  按上述五点撰写完技术段落后，再检查 README / TODO / CHANGELOG 是否需要同步更新，避免知识孤岛。
- **`项目规划文档.md`**  
  - 在对应阶段小节中写入最新结论（例如“2025-10-21 最新 100 s 运行…”）。
- **`TODO_3d_channel_flow.md`**  
  - 勾选完成项，并把关键指标写在括号里，方便回顾。
- **`CHANGELOG.md`**  
  - 采用规范格式：`## [版本号] - 日期 - 主题`，下设 `### Added/Changed/Fixed/…`。  
  - 每条包含“做了什么”“为什么”“代码片段/命令”。示例：  
    ```markdown
    ### Changed
    - **延长仿真时间到 100 s (`test_3d_channel_flow.cpp`)**
      - 做了什么：将 `end_time` 设为 100 s，并保持输出间隔 `end_time/200`。
      - 为什么：观察更长程的稳态收敛与速度峰值演化。
      ```cpp
      const Real end_time = 100.0;
      ```
    ```

---

## 6. 质量检查

- **命令**：`git status --short`（确认只修改相关文件）。  
- **验证项目**：
  - GTest 是否通过。  
  - `flow_data.mat` 中 `analysis.final_time`、采样数量、峰值是否符合预期。  
  - `output/umax_comparison.mat` 的差值指标。  
  - `output/timing_summary.txt` 中记录是否更新。
- **异常处理**：若发现大偏差（如中心线误差 >5%），回查 TODO/报告并记录在 `CHANGELOG.md` 的 Known Issues。

---

## 7. 提交/分享前回顾

- 确认 README、技术报告、规划文档、TODO、CHANGELOG 都已同步。  
- 保留构建与运行命令样例，以及关键指标（误差、耗时）。  
- 如需提交 PR，建议描述开头列“复现步骤 / 关键结果 / 已知问题”。

---

### 附录：建议的 Markdown 样式

- 一级标题：`# 标题`
- 二级标题：`## 标题`
- 代码块：使用 ```语言 标注，如 ```powershell、```cpp、```matlab。
- 列表：优先使用 `-`；嵌套用两个空格缩进。
- 表格／指标：可用 `|` 分隔，但保持简洁。

按照此工作流执行，可确保“计划 → 实现 → 构建 → 后处理 → 文档 → 汇报”全链条信息明确、可复现。*** End Patch
---

## 8. 常见弯路与经验教训

1. **VTP 解析失败（Simbody/TBB/Boost 配置干扰）**  
   - 症状：`readstruct` 因 `.vtp` 文件不合法退出，或 CMake 反复报找不到依赖。  
   - 根因：直接复用根目录 `build/` 配置，生成器与当前工具链不一致；部分 `.vtp` 快照写入中断。  
   - 解决：  
     - 为案例单独使用 `build_codex/`，固定生成器 `Visual Studio 16 2019`；  
     - 对 VTP 扫描时捕获异常并跳过损坏文件，仍保证后处理可继续。  

2. **时间序列错位导致动画只剩 10 帧**  
   - 症状：`flow_data` 数组仅 10 帧，`observer` 数据齐全但 `preprocess_data` 提前截断，RMS 取样失真。  
   - 根因：默认依赖动能日志 `ChannelFluid_TotalKineticEnergy.dat`，与实际 VTP 数量不一致。  
   - 解决：完全改为使用观测器时间作为唯一时间轴，裁剪三类数据至共同帧长。  

3. **视角与壁面方向混乱**  
   - 症状：槽道在动画中“向上”倾斜，固定壁面难以辨识。  
   - 根因：MATLAB 默认 `view` 设置、`CameraUpVector` 未对齐 Y 轴。  
   - 解决：显式设置 `CameraUpVector = [0 1 0]`，并按需求（右下方向）旋转视角角度。  

4. **CHANGELOG 写到根目录**  
   - 症状：全局 `CHANGELOG.md` 被覆盖，与案例需求不匹配。  
   - 根因：忘记在案例目录创建本地日志。  
   - 解决：在 `tests/3d_examples/test_3d_channel_flow/` 下新增专用 `CHANGELOG.md`，仅记录本案例增量。  

> **提醒**：遇到类似问题，先在此小节补充记录，再更新对应脚本或文档，确保后续人员能直接复用经验。
