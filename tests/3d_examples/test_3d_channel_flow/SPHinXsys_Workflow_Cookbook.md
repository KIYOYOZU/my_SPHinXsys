# SPHinXsys 可复现工作流手册：从零到可视化

## 1. 目标与引言

本手册旨在提供一个**完全可复现的**、从零开始的工作流程，适用于任何 SPHinXsys 标准算例。其核心目标是让一位新用户，在仅拥有一个“干净”的 SPHinXsys 项目和一个算例文件夹（仅含 `.cpp` 和 `CMakeLists.txt`）的情况下，能够通过本手册的指导，独立完成从编译、运行到高级数据可视化的全过程。

## 2. 初始状态与核心原则

### 初始状态

您开始时应该拥有：
1.  一个完整的 SPHinXsys 项目源码。
2.  一个位于 `tests` 目录下的算例文件夹，其中**仅包含**：
    *   `your_project.cpp`
    *   `CMakeLists.txt`

### 核心原则

*   **编译位置**：**项目根目录**。
*   **时间来源**：**.vtp 文件名**。
*   **MATLAB 陷阱**：使用 `arrayfun` 处理结构体数组的点索引。
*   **物理参数来源**： **`.cpp` 源代码**。

---

## 3. 工作流分步详解

### 步骤一：首次环境配置（仅需一次）

**目标**：创建并配置 CMake 构建环境。

**操作**：
1.  打开命令行工具。
2.  导航到 SPHinXsys 项目的**根目录**。
3.  执行以下命令：
    ```shell
    mkdir build
    cd build
    cmake .. -G "Visual Studio 17 2022" -A x64
    ```
**验证**：项目根目录下成功创建了 `build` 文件夹，且其中包含了 Visual Studio 的解决方案文件 (`.sln`)。

---

### 步骤二：创建 `build.bat` 用于日常编译运行

**目标**：在算例文件夹中创建一个可反复使用的、一键式的编译运行脚本。

**操作**：在您的**算例子目录**下，创建以下 `build.bat` 文件。

#### `build.bat` 模板

```batch
@echo off
setlocal

REM --- 用户需配置 ---
set "TARGET_NAME=test_3d_poiseuille_flow_shell"
REM ---

REM --- 路径设置 ---
set "PROJECT_ROOT=..\..\.."
set "BUILD_DIR=%PROJECT_ROOT%\build"

REM --- 备份与创建 Output ---
if exist "output" (
    if exist "output_backup" (rmdir /s /q "output_backup")
    rename "output" "output_backup"
)
mkdir "output"

REM --- 编译与运行 ---
cmake --build "%BUILD_DIR%" --target %TARGET_NAME% --config Debug
"%BUILD_DIR%\tests\3d_examples\%TARGET_NAME%\bin\Debug\%TARGET_NAME%.exe"

endlocal
```

---

### 步骤三：编写 MATLAB 脚本用于数据处理与可视化

**目标**：创建两个 MATLAB 脚本，一个用于数据预处理，另一个用于高级可视化。

#### `preprocess_data.m` 设计大纲

此脚本的核心任务是将 `output` 文件夹中成百上千的 `.vtp` 文件，高效地转换为一个单一的、结构化的 `.mat` 文件。

**功能结构：**
1.  **初始化**：定义 `output` 目录和输出的 `.mat` 文件名。
2.  **文件扫描与排序**：
    *   使用 `dir` 函数获取所有 `.vtp` 文件。
    *   **注意点**：必须对文件名进行**自然排序**（`sort_nat`），以确保 `file10.vtp` 排在 `file2.vtp` 之后。
3.  **循环处理每个 `.vtp` 文件**：
    *   **提取时间（核心）**：
        *   **注意点**：**必须**使用正则表达式从文件名 `*_(\d+).vtp` 中提取数字部分，并乘以一个缩放因子（如 `1e-6`）来获得真实的物理时间。**绝对不要**依赖 `.dat` 文件。
    *   **数据解析**：
        *   使用 `fileread` 将 `.vtp` 文件读为字符串。
        *   使用正则表达式分别提取 `<Points>` 和 `<PointData...Name="Velocity">` 标签内的数据块。
    *   **边界情况处理**：
        *   **注意点**：如果一个 `.vtp` 文件（通常是描述初始几何的 `Shell_*.vtp`）中找不到速度数据，脚本应能**优雅地跳过**该文件，而不是报错。
    *   **数据存储**：将提取出的时间、粒子位置和速度，存入一个结构体数组 `flow_data` 中。
4.  **保存与报告**：
    *   使用 `save` 命令将 `flow_data` 保存到 `.mat` 文件。
    *   在命令行中打印报告，说明成功处理了多少文件，跳过了多少文件。

#### `visualize_flow.m` 设计大纲

此脚本的核心任务是加载 `.mat` 文件，并以“双视图同步动画”的形式，对仿真结果进行高级可视化和定量分析。

**功能结构：**
1.  **初始化与数据加载**：
    *   加载 `flow_data.mat` 文件。
    *   **注意点**：**必须**从对应的 `.cpp` 源代码中查找并定义关键的物理参数（如 `fluid_radius`, `U_max`），用于后续的理论对比和颜色范围优化。
2.  **创建图形界面**：
    *   使用 `figure` 和 `subplot(1, 2, ...)` 创建一个包含左右两个子图的窗口。
3.  **初始化左侧 3D 动画子图**：
    *   设置坐标轴、视角、颜色图 (`colormap`) 等。
    *   **注意点**：使用 `scatter3` 创建一个**空的**绘图句柄 `plot_3d_handle`，后续动画将通过 `set` 命令更新此句柄，而非重复绘图，以提高性能。
4.  **初始化右侧 2D 对比子图**：
    *   绘制代表理论解的**静态**曲线（如泊肃叶流的抛物线）。
    *   使用 `plot` 创建一个代表仿真数据的**空的**散点图句柄 `plot_2d_handle`。
    *   设置图例、标题和坐标轴范围。
5.  **同步动画循环**：遍历 `flow_data` 中的每一帧。
    *   **更新 3D 图**：
        *   使用 `set(plot_3d_handle, 'XData', ..., 'YData', ..., 'ZData', ..., 'CData', ...)` 更新粒子的位置和颜色。
        *   **注意点**：为了获得更好的视觉效果，颜色范围 `clim` 应在**当前帧**动态计算，并可以排除管壁附近的低速粒子，以增强核心流场的色彩对比度。
    *   **更新 2D 图**：
        *   提取当前帧中位于管道中间切片的粒子。
        *   计算这些粒子的径向距离和轴向速度。
        *   使用 `set(plot_2d_handle, 'XData', ..., 'YData', ...)` 更新仿真数据散点图。
    *   使用 `drawnow` 和 `pause` 控制动画的刷新和速度。
6.  **处理 MATLAB 索引陷阱**：
    *   **注意点**：在需要从 `flow_data` 结构体数组中一次性提取所有粒子的位置或速度时（例如，为了计算全局坐标范围），**必须**使用 `arrayfun` 来避免“逗号分隔列表”错误。例如：
        ```matlab
        positions_cell = arrayfun(@(s) s.particles.position, flow_data, 'UniformOutput', false);
        all_positions = vertcat(positions_cell{:});
        ```

---

## 4. 完整工作流程总结

1.  **首次**：按照【步骤一】的指示，在项目根目录手动配置好 CMake 环境。
2.  **日常**：
    a. 在算例子目录中，创建好【步骤二】所述的 `build.bat` 文件。
    b. 根据【步骤三】的大纲和注意点，编写您自己的 `preprocess_data.m` 和 `visualize_flow.m` 脚本。
    c. **运行仿真**：执行 `.\build.bat`。
    d. **数据处理**：在 MATLAB 中运行 `preprocess_data.m`。
    e. **数据可视化**：在 MATLAB 中运行 `visualize_flow.m`。