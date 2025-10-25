%% visualize_flow.m
% 功能：加载 flow_data.mat，创建双视图同步动画
% - 左图：3D 粒子散点图（速度场可视化）
% - 右图：2D 速度剖面图（与理论解对比）

clc; clear; close all;

%% 加载数据
data_file = 'flow_data.mat';
if ~exist(data_file, 'file')
    error('数据文件 %s 不存在，请先运行 preprocess_data.m', data_file);
end

load(data_file, 'flow_data');
fprintf('成功加载 %d 帧数据\n', length(flow_data));

%% 从 .cpp 中提取的物理参数
% 参考：test_3d_FVM_incompressible_channel_flow.h
DL = 1.0;               % 计算域长度
DH = 0.6494805454;      % 计算域高度
DW = 0.038968832;       % 计算域宽度
rho0_f = 1.0;           % 密度
U_f = 1.0;              % 自由流速度
U_inlet = 1.0;          % 入口速度（从 InvCFInitialCondition 和边界条件）

% 对于通道流，理论最大速度（中心线）取决于压力梯度
% 这里假设均匀流，理论速度为 U_inlet
U_theoretical = U_inlet;

%% 计算全局坐标范围（用于设置固定坐标轴）
positions_cell = arrayfun(@(s) s.particles.position, flow_data, 'UniformOutput', false);
all_positions = vertcat(positions_cell{:});

x_range = [min(all_positions(:,1)), max(all_positions(:,1))];
y_range = [min(all_positions(:,2)), max(all_positions(:,2))];
z_range = [min(all_positions(:,3)), max(all_positions(:,3))];

fprintf('坐标范围：X [%.3f, %.3f], Y [%.3f, %.3f], Z [%.3f, %.3f]\n', ...
        x_range, y_range, z_range);

%% 创建图形窗口
fig = figure('Position', [100, 100, 1600, 600]);
set(fig, 'Color', 'w');

%% 左侧子图：3D 速度场可视化
subplot(1, 2, 1);
ax_3d = gca;
hold(ax_3d, 'on');
grid(ax_3d, 'on');
box(ax_3d, 'on');
view(ax_3d, 45, 30);  % 更好的观察角度：方位角45°，仰角30°
xlabel(ax_3d, 'X (m) - 流动方向');
ylabel(ax_3d, 'Y (m) - 通道高度');
zlabel(ax_3d, 'Z (m) - 通道宽度');
title(ax_3d, '3D 速度场（颜色表示 X 方向速度）');
colormap(ax_3d, 'jet');
cb = colorbar(ax_3d);
ylabel(cb, '速度 U_x (m/s)', 'FontSize', 10);

% 设置固定坐标轴范围
xlim(ax_3d, x_range);
ylim(ax_3d, y_range);
zlim(ax_3d, z_range);

% 绘制通道边界框（wireframe box）
% 定义通道的8个顶点
x_min = x_range(1); x_max = x_range(2);
y_min = y_range(1); y_max = y_range(2);
z_min = z_range(1); z_max = z_range(2);

% 底面4条边
plot3(ax_3d, [x_min x_max], [y_min y_min], [z_min z_min], 'k-', 'LineWidth', 2);
plot3(ax_3d, [x_max x_max], [y_min y_max], [z_min z_min], 'k-', 'LineWidth', 2);
plot3(ax_3d, [x_max x_min], [y_max y_max], [z_min z_min], 'k-', 'LineWidth', 2);
plot3(ax_3d, [x_min x_min], [y_max y_min], [z_min z_min], 'k-', 'LineWidth', 2);

% 顶面4条边
plot3(ax_3d, [x_min x_max], [y_min y_min], [z_max z_max], 'k-', 'LineWidth', 2);
plot3(ax_3d, [x_max x_max], [y_min y_max], [z_max z_max], 'k-', 'LineWidth', 2);
plot3(ax_3d, [x_max x_min], [y_max y_max], [z_max z_max], 'k-', 'LineWidth', 2);
plot3(ax_3d, [x_min x_min], [y_max y_min], [z_max z_max], 'k-', 'LineWidth', 2);

% 4条垂直边
plot3(ax_3d, [x_min x_min], [y_min y_min], [z_min z_max], 'k-', 'LineWidth', 2);
plot3(ax_3d, [x_max x_max], [y_min y_min], [z_min z_max], 'k-', 'LineWidth', 2);
plot3(ax_3d, [x_max x_max], [y_max y_max], [z_min z_max], 'k-', 'LineWidth', 2);
plot3(ax_3d, [x_min x_min], [y_max y_max], [z_min z_max], 'k-', 'LineWidth', 2);

% 添加尺寸标注
text(ax_3d, x_max, y_min, z_min - 0.05*DW, sprintf('L=%.2f', DL), 'FontSize', 10, 'Color', 'k', 'FontWeight', 'bold');
text(ax_3d, x_max + 0.05*DL, (y_min+y_max)/2, z_min, sprintf('H=%.3f', DH), 'FontSize', 10, 'Color', 'k', 'FontWeight', 'bold');
text(ax_3d, x_max, y_min, (z_min+z_max)/2, sprintf('W=%.3f', DW), 'FontSize', 10, 'Color', 'k', 'FontWeight', 'bold');

% 创建空的 scatter3 句柄（后续通过 set 更新）
plot_3d_handle = scatter3(ax_3d, [], [], [], 10, [], 'filled');

%% 右侧子图：2D 速度剖面（Y方向切片）
subplot(1, 2, 2);
ax_2d = gca;
hold(ax_2d, 'on');
grid(ax_2d, 'on');
box(ax_2d, 'on');
xlabel(ax_2d, 'Y Position (m)');
ylabel(ax_2d, 'Velocity U_x (m/s)');
title(ax_2d, '通道中心线速度剖面（X方向速度 vs Y位置）');

% 绘制理论解（均匀流）
y_theory = linspace(y_range(1), y_range(2), 100);
u_theory = U_theoretical * ones(size(y_theory));
plot(ax_2d, y_theory, u_theory, 'r--', 'LineWidth', 2, 'DisplayName', '理论解（均匀流）');

% 创建空的散点图句柄（仿真数据）- 使用 scatter 而不是 plot
plot_2d_handle = scatter(ax_2d, [], [], 36, 'b', 'filled', 'DisplayName', '仿真数据', ...
                         'MarkerFaceAlpha', 0.6, 'MarkerEdgeColor', 'none');
legend(ax_2d, 'Location', 'best');

% 设置固定坐标轴范围
ylim(ax_2d, [0, 1.6]);  % 与3D图的colormap上限保持一致
xlim(ax_2d, y_range);

%% 创建截图保存文件夹
frames_dir = 'animation_frames';
if ~exist(frames_dir, 'dir')
    mkdir(frames_dir);
    fprintf('已创建文件夹: %s\n', frames_dir);
else
    fprintf('使用现有文件夹: %s\n', frames_dir);
end

% 获取文件夹完整路径
frames_full_path = fullfile(pwd, frames_dir);

% 初始化 GIF 帧数组
gif_frames = cell(1, length(flow_data));

%% 动画循环
fprintf('\n开始动画播放并保存截图...\n');
for frame_idx = 1:length(flow_data)
    current_data = flow_data(frame_idx);
    current_time = current_data.time;
    positions = current_data.particles.position;
    velocities = current_data.particles.velocity;

    % 更新左侧 3D 图
    velocity_magnitude = velocities(:, 1);  % X 方向速度

    % 使用固定速度范围以便对比不同时刻
    % 根据通道流的理论，最大速度约为入口速度的1.5倍
    clim_min = 0;
    clim_max = 1.6;  % 固定上限 1.6 m/s

    set(plot_3d_handle, ...
        'XData', positions(:,1), ...
        'YData', positions(:,2), ...
        'ZData', positions(:,3), ...
        'CData', velocity_magnitude, ...
        'SizeData', 10);
    caxis(ax_3d, [clim_min, clim_max]);

    % 更新右侧 2D 图（提取中心切片）
    % 选取靠近通道中心的粒子（Z 和 X 方向的中间位置）
    z_center = mean(z_range);
    x_center = mean(x_range);
    tolerance_z = 0.3 * DW;  % 放宽容差从 0.05 到 0.3
    tolerance_x = 0.3 * DL;  % 放宽容差从 0.05 到 0.3

    center_mask = abs(positions(:,3) - z_center) < tolerance_z & ...
                  abs(positions(:,1) - x_center) < tolerance_x;

    % 诊断输出：显示选中的粒子数量
    num_selected = sum(center_mask);

    if any(center_mask)
        y_slice = positions(center_mask, 2);
        u_slice = velocities(center_mask, 1);
        set(plot_2d_handle, 'XData', y_slice, 'YData', u_slice);

        % 每10帧输出一次诊断信息
        if mod(frame_idx, 10) == 1
            fprintf('  Frame %d: 选中 %d 个粒子用于2D剖面图\n', frame_idx, num_selected);
        end
    else
        % 如果没有选中粒子，输出警告
        if frame_idx == 1 || mod(frame_idx, 10) == 1
            fprintf('  ⚠️ 警告：Frame %d 未选中任何粒子！\n', frame_idx);
            fprintf('     Z范围: [%.4f, %.4f], 中心=%.4f, 容差=%.4f\n', ...
                    min(positions(:,3)), max(positions(:,3)), z_center, tolerance_z);
            fprintf('     X范围: [%.4f, %.4f], 中心=%.4f, 容差=%.4f\n', ...
                    min(positions(:,1)), max(positions(:,1)), x_center, tolerance_x);
        end
    end

    % 更新标题显示时间
    title(ax_3d, sprintf('3D 速度场 (t = %.3f s)', current_time));
    title(ax_2d, sprintf('速度剖面 (t = %.3f s)', current_time));

    % 刷新绘图
    drawnow;

    % 保存当前帧为高质量 PNG
    frame_filename = sprintf('frame_%04d.png', frame_idx);
    frame_filepath = fullfile(frames_dir, frame_filename);

    % 使用 print 命令保存高分辨率图像
    print(fig, frame_filepath, '-dpng', '-r300');

    % 捕获帧用于 GIF 动画
    frame = getframe(fig);
    gif_frames{frame_idx} = frame2im(frame);

    pause(0.05);  % 控制动画速度

    if mod(frame_idx, 10) == 0
        fprintf('已处理 %d/%d 帧 (已保存: %s)\n', frame_idx, length(flow_data), frame_filename);
    end
end

%% 生成 GIF 动画
fprintf('\n正在生成 GIF 动画...\n');
gif_filename = 'flow_animation.gif';
gif_filepath = fullfile(frames_dir, gif_filename);

for frame_idx = 1:length(gif_frames)
    [A, map] = rgb2ind(gif_frames{frame_idx}, 256);
    if frame_idx == 1
        imwrite(A, map, gif_filepath, 'gif', 'LoopCount', Inf, 'DelayTime', 0.1);
    else
        imwrite(A, map, gif_filepath, 'gif', 'WriteMode', 'append', 'DelayTime', 0.1);
    end
end

fprintf('GIF 动画已保存: %s\n', gif_filepath);

%% 输出汇总信息
fprintf('\n========== 动画生成完成 ==========\n');
fprintf('截图保存位置: %s\n', frames_full_path);
fprintf('生成截图数量: %d 张\n', length(flow_data));
fprintf('PNG 文件: frame_0001.png ~ frame_%04d.png\n', length(flow_data));
fprintf('GIF 动画: %s\n', gif_filepath);
fprintf('图像分辨率: 300 DPI\n');
fprintf('===================================\n');

%% 关键帧分析
fprintf('\n========== 关键帧分析 ==========\n');

% 初始帧
fprintf('\n1. 初始状态 (Frame 1, t = %.3f s):\n', flow_data(1).time);
initial_velocities = flow_data(1).particles.velocity(:, 1);
fprintf('   - X方向平均速度: %.4f m/s\n', mean(initial_velocities));
fprintf('   - X方向最大速度: %.4f m/s\n', max(initial_velocities));
fprintf('   - X方向最小速度: %.4f m/s\n', min(initial_velocities));
fprintf('   - 速度标准差: %.4f m/s\n', std(initial_velocities));

% 中间帧
mid_idx = round(length(flow_data) / 2);
fprintf('\n2. 中间状态 (Frame %d, t = %.3f s):\n', mid_idx, flow_data(mid_idx).time);
mid_velocities = flow_data(mid_idx).particles.velocity(:, 1);
fprintf('   - X方向平均速度: %.4f m/s\n', mean(mid_velocities));
fprintf('   - X方向最大速度: %.4f m/s\n', max(mid_velocities));
fprintf('   - X方向最小速度: %.4f m/s\n', min(mid_velocities));
fprintf('   - 速度标准差: %.4f m/s\n', std(mid_velocities));

% 最终帧
fprintf('\n3. 最终状态 (Frame %d, t = %.3f s):\n', length(flow_data), flow_data(end).time);
final_velocities = flow_data(end).particles.velocity(:, 1);
fprintf('   - X方向平均速度: %.4f m/s\n', mean(final_velocities));
fprintf('   - X方向最大速度: %.4f m/s\n', max(final_velocities));
fprintf('   - X方向最小速度: %.4f m/s\n', min(final_velocities));
fprintf('   - 速度标准差: %.4f m/s\n', std(final_velocities));

fprintf('\n4. 速度场演化分析:\n');
fprintf('   - 平均速度变化: %.4f m/s (初始) -> %.4f m/s (最终)\n', ...
        mean(initial_velocities), mean(final_velocities));
fprintf('   - 速度场均匀性变化 (标准差): %.4f -> %.4f\n', ...
        std(initial_velocities), std(final_velocities));

if std(final_velocities) < std(initial_velocities)
    fprintf('   - 结论: 速度场逐渐趋于均匀分布\n');
else
    fprintf('   - 结论: 速度场出现更大的空间变化\n');
end

fprintf('===================================\n');
