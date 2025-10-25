% visualize_flow.m
% 该脚本用于SPH流体模拟数据的同步可视化。

clear; clc; close all;

% --- 配置 ---
mat_file = 'flow_data.mat';
animation_speed = 0.5;      % 播放速度因子
marker_size = 20;           % 粒子标记大小

% 加载和验证数据
if ~isfile(mat_file)
    error('错误: 未找到 "%s"。请先运行 preprocess_data.m。', mat_file);
end
load(mat_file, 'flow_data');
if ~exist('flow_data', 'var') || isempty(flow_data)
    error('错误: 在 "%s" 中 "flow_data" 不存在或为空。', mat_file);
end
num_frames = length(flow_data);
fprintf('数据加载完成，共 %d 帧。\n', num_frames);

% --- 计算并显示粒子数 ---
if num_frames > 0
    num_particles_first_frame = size(flow_data(1).particles.position, 1);
    fprintf('第一帧的粒子数为: %d\n', num_particles_first_frame);
end

% 理论解 
scale = 0.001;
diameter = 6.35 * scale;
fluid_radius = 0.5 * diameter;
Re = 100;
rho0_f = 1050.0;
mu_f = 3.6e-3;
U_f = Re * mu_f / rho0_f / diameter;
U_max = 2.0 * U_f; % 理论最大速度

% 设置图形窗口和子图
fig = figure('Name', 'SPHinXsys 3D流动与剖面对比', 'NumberTitle', 'off', 'Color', 'w', 'Position', [100, 100, 1600, 800]);

% 速度动画
ax_3d = subplot(1, 2, 1, 'Parent', fig);
hold(ax_3d, 'on'); grid(ax_3d, 'on'); axis(ax_3d, 'equal'); view(ax_3d, 3);
xlabel(ax_3d, 'X (m)'); ylabel(ax_3d, 'Y (m)'); zlabel(ax_3d, 'Z (m)');
title(ax_3d, '粒子速度云图');
colormap(ax_3d, "jet");

% 速度剖面
ax_2d = subplot(1, 2, 2, 'Parent', fig);
hold(ax_2d, 'on'); grid(ax_2d, 'on');
xlabel(ax_2d, '径向距离 (m)'); ylabel(ax_2d, '轴向速度 (m/s)');
title(ax_2d, '速度剖面对比');

% 计算全局坐标和颜色范围
positions_cell = arrayfun(@(s) s.particles.position, flow_data, 'UniformOutput', false);
all_positions = vertcat(positions_cell{:});
min_coords = min(all_positions);
max_coords = max(all_positions);
axis_range = max_coords - min_coords;
padding = 0.1 * axis_range;
xlim(ax_3d, [min_coords(1)-padding(1), max_coords(1)+padding(1)]);
ylim(ax_3d, [min_coords(2)-padding(2), max_coords(2)+padding(2)]);
zlim(ax_3d, [min_coords(3)-padding(3), max_coords(3)+padding(3)]);

cb = colorbar(ax_3d);
cb.Label.String = '速度大小 (m/s)';

% 初始化绘图句柄
% 三维图初始化
pos_init = flow_data(1).particles.position;
vel_mag_init = vecnorm(flow_data(1).particles.velocity, 2, 2);
plot_3d_handle = scatter3(ax_3d, pos_init(:,1), pos_init(:,2), pos_init(:,3), marker_size, vel_mag_init, 'filled');
title_3d_handle = title(ax_3d, '');

% 二维图初始化
plot(ax_2d, linspace(0, fluid_radius, 200), U_max * (1 - (linspace(0, fluid_radius, 200).^2 / fluid_radius^2)), 'r-', 'LineWidth', 2, 'DisplayName', '理论解');
radial_dist_init = vecnorm(pos_init(:,[1,3]), 2, 2);
axial_vel_init = pos_init(:,2);
plot_2d_handle = plot(ax_2d, radial_dist_init, axial_vel_init, 'b.', 'DisplayName', 'SPH模拟');
legend(ax_2d, 'show', 'Location', 'best');
xlim(ax_2d, [0, fluid_radius * 1.1]);
ylim(ax_2d, [0, U_max * 1.2]);

% 同步动画循环
fprintf('开始同步动画...\n');
for i = 1:num_frames
    if ~isvalid(fig), break; end
    
    % 获取当前帧数据
    positions = flow_data(i).particles.position;
    velocities = flow_data(i).particles.velocity;
    current_vel_mag = vecnorm(velocities, 2, 2);
    
    % 更新三维图
    set(plot_3d_handle, 'XData', positions(:,1), 'YData', positions(:,2), 'ZData', positions(:,3), 'CData', current_vel_mag);
    title_str = sprintf('帧: %d / %d | 时间: %.4f s', i, num_frames, flow_data(i).time);
    set(title_3d_handle, 'String', title_str);
    
    % 动态更新颜色条范围
    if ~isempty(current_vel_mag) && all(isfinite(current_vel_mag))
        min_v = min(current_vel_mag);
        max_v = max(current_vel_mag);
        if min_v < max_v
            caxis(ax_3d, [min_v, max_v]);
        end
    end
    
    % 更新二维图 (取管道中心)
    pipe_center_y = (max_coords(2) + min_coords(2)) / 2;
    slice_indices = abs(positions(:,2) - pipe_center_y) < (fluid_radius * 2);
    radial_dist_sim = vecnorm(positions(slice_indices, [1,3]), 2, 2);
    axial_vel_sim = velocities(slice_indices, 2);
    set(plot_2d_handle, 'XData', radial_dist_sim, 'YData', axial_vel_sim);
    
    drawnow;
    pause(0.01 / animation_speed);
end

fprintf('动画结束\n');
waitfor(fig);