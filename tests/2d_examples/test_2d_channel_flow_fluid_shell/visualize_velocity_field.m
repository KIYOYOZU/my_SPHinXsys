%% SPHinXsys Post-Processing Script
%
% This script performs two main visualization tasks:
% 1. (Immediate) Plots the convergence history of maximum velocity (Umax) 
%    by loading pre-processed data from 'umax.mat'. This provides a quick
%    quantitative overview of the simulation's steady-state behavior.
% 2. (Animation) Creates a detailed, animated visualization of the flow field
%    and compares the velocity profile to the theoretical solution at each 
%    time step. This provides a qualitative understanding of the flow dynamics.
%

clear;
close all;
clc;

%% --- 用户配置 ---
config = struct();
config.save_animation = false;          % 是否保存动画到文件
config.output_format = 'mp4';          % 输出格式: 'mp4' | 'gif' | 'none'
config.output_filename = 'channel_flow_animation'; % 输出文件名(不含扩展名)
config.frame_rate = 20;                % 视频帧率(仅MP4)
config.animation_speed = 1.0;          % 播放速度倍数 (>1加速, <1减速)
config.gif_delay = 0.05;               % GIF帧间延迟(秒)
config.show_progress = true;           % 是否显示进度条

%% --- Task 1: Plot Umax Convergence History ---

fprintf('开始绘制Umax收敛曲线对比图...\n');

% Create a new figure for convergence comparison
figure('Name', 'Maximum Velocity Convergence Comparison', 'Position', [200, 200, 1000, 600]);
hold on;
grid on;

% Load all variables from umax.mat
umax_file = 'umax.mat';
if exist(umax_file, 'file')
    data = load(umax_file);
    variable_names = fieldnames(data);
    
    if isempty(variable_names)
        warning('文件 ''%s'' 中未找到任何工况数据。', umax_file);
    else
        fprintf('从 ''%s'' 中加载了 %d 个工况进行绘制。\n', umax_file, numel(variable_names));
        
        % --- Extract initial velocities and sort the variable names ---
        u0_values = zeros(numel(variable_names), 1);
        for i = 1:numel(variable_names)
            num_str = regexp(variable_names{i}, 'u0_(\d+_\d+)', 'tokens');
            if isempty(num_str) % Handle cases like 'u0_1'
                 num_str = regexp(variable_names{i}, 'u0_(\d+)', 'tokens');
            end
            if ~isempty(num_str)
                u0_values(i) = str2double(strrep(num_str{1}{1}, '_', '.'));
            else
                u0_values(i) = NaN; % Assign NaN for names that don't match
            end
        end
        [~, sorted_indices] = sort(u0_values);
        sorted_variable_names = variable_names(sorted_indices);
        
        % --- Generate a colormap for plotting ---
        colors = jet(numel(sorted_variable_names));

        % --- Loop through and plot each case in sorted order ---
        for i = 1:numel(sorted_variable_names)
            case_name = sorted_variable_names{i};
            case_data = data.(case_name);
            
            % Create a user-friendly display name for the legend, e.g., "u0_1_4" -> "SPH (u0=1.4)"
            display_name = strrep(case_name, '_', '.');
            display_name = strrep(display_name, 'u0.', 'u0=');
            
            plot(case_data.time, case_data.umax, '-', 'LineWidth', 2, 'DisplayName', ['SPH (' display_name ')'], 'Color', colors(i, :));
        end
    end
else
    warning('未找到收敛数据文件: %s', umax_file);
end

% Plot the theoretical steady-state solution
U_max_theory = 1.5;
plot([0, 100], [U_max_theory, U_max_theory], 'k--', 'LineWidth', 1.5, 'DisplayName', '理论值');

% Set chart properties
xlabel('时间步 (s)');
ylabel('槽道中部U_{max}');
title('不同初始速度u_0下，U_{max}随时间演化');
legend('Location', 'best');
axis([0, 101, 1, 2]); % Adjust axis limits to focus on the convergence region

hold off;

fprintf('收敛图表生成完毕。\n\n');


%% --- Task 2: Animate Flow Field and Velocity Profile ---

fprintf('开始生成流场动画...\n');

mat_file = 'velocity_data.mat';
if ~exist(mat_file, 'file')
    error('数据文件 ''%s'' 不存在。请先运行 process_velocity_data.m。', mat_file);
end
loaded_data = load(mat_file, 'velocity_data', 'sim_config');
velocity_data = loaded_data.velocity_data;

if isempty(velocity_data)
    error('数据文件为空,无法进行可视化。');
end

% 自动加载物理参数(如果可用)
if isfield(loaded_data, 'sim_config')
    sim_config = loaded_data.sim_config;
    U_f = sim_config.U_f;
    DH = sim_config.DH;
    DL = sim_config.DL;
    U_max_theory = sim_config.U_max_theory;
    time_scale = sim_config.time_scale; % 时间转换系数: time_id * time_scale = 物理时间(秒)
    fprintf('已从配置中加载物理参数: DL=%.1f, DH=%.1f, U_f=%.1f\n', DL, DH, U_f);
else
    % 回退到硬编码值(保持向后兼容)
    warning('velocity_data.mat中未找到sim_config,使用默认参数。');
    U_f = 1.0;
    DH = 2.0;
    DL = 10.0;
    U_max_theory = 1.5 * U_f;
    time_scale = 1e-6;
end
h = DH / 2.0;

% --- 预计算全局范围和视频设置(避免循环内重复计算) ---
fprintf('正在预处理数据...\n');
all_positions_x = cell2mat(arrayfun(@(s) s.positions(:,1), velocity_data, 'UniformOutput', false)');
all_positions_y = cell2mat(arrayfun(@(s) s.positions(:,2), velocity_data, 'UniformOutput', false)');
x_min = min(all_positions_x);
x_max = max(all_positions_x);
y_min = min(all_positions_y);
y_max = max(all_positions_y);
x_range = x_max - x_min;
y_range = y_max - y_min;

% 计算实际帧数(考虑播放速度)
total_frames = length(velocity_data);
frame_indices = round(linspace(1, total_frames, round(total_frames / config.animation_speed)));

% 初始化视频写入器
if config.save_animation
    if strcmpi(config.output_format, 'mp4')
        v = VideoWriter(config.output_filename, 'MPEG-4');
        v.FrameRate = config.frame_rate;
        open(v);
        fprintf('视频将保存为: %s.mp4\n', config.output_filename);
    elseif strcmpi(config.output_format, 'gif')
        gif_filename = [config.output_filename, '.gif'];
        fprintf('GIF将保存为: %s\n', gif_filename);
    end
end

% 初始化进度条
if config.show_progress
    progress_bar = waitbar(0, '正在生成动画...', 'Name', 'Animation Progress');
end

fig_animation = figure('Position', [100, 100, 1800, 600]); % 创建一个宽屏图形窗口并获取其句柄
colormap('jet');

for idx = 1:length(frame_indices)
    figure(fig_animation); % **核心修复**: 在每次循环开始时，确保动画窗口是当前绘图目标
    clf;

    % 获取当前帧索引(支持变速播放)
    t = frame_indices(idx);

    current_data = velocity_data(t);
    positions = current_data.positions;
    velocities = current_data.velocities;
    physical_time = current_data.time_id * time_scale; % 使用自动加载的时间转换系数
    velocity_magnitude = sqrt(velocities(:,1).^2 + velocities(:,2).^2);


    sgtitle(sprintf('Simulation at Time: %.5f s', physical_time), 'FontSize', 16);


    subplot(1, 2, 1);
    scatter(positions(:,1), positions(:,2), 20, velocity_magnitude, 'filled');
    axis equal;
    colorbar_handle = colorbar;
    ylabel(colorbar_handle, 'Velocity Magnitude');
    caxis([0, 2]);
    title('Velocity Field');
    xlabel('X ');
    ylabel('Y ');
    xlim([x_min-0.5, x_max+0.5]);
    ylim([y_min - 0.5, y_max + 0.5]);


    subplot(1, 2, 2);
    % 中心线速度剖面
    x0 = 0.5 * (x_min + x_max);
    dx_tol = 0.02 * x_range;
    idx_center = abs(positions(:,1) - x0) <= dx_tol;
    if nnz(idx_center) < 50
        dx_tol = 0.05 * x_range;
        idx_center = abs(positions(:,1) - x0) <= dx_tol;
    end

    y_s = positions(idx_center, 2);
    u_s = velocities(idx_center, 1);

    % 诊断输出：在第一帧和最后一帧输出统计信息
    if idx == 1 || idx == length(frame_indices)
        fprintf('\n=== 诊断信息 (帧 %d, t=%.2f s) ===\n', t, physical_time);
        fprintf('全局最大速度（所有粒子）：max(|v|) = %.6f m/s\n', max(velocity_magnitude));
        fprintf('中心线最大速度（x方向）：max(u_x) = %.6f m/s\n', max(u_s));
        fprintf('理论最大速度：U_max_theory = %.6f m/s\n', U_max_theory);
        fprintf('误差：%.2f%%\n', (max(u_s) - U_max_theory) / U_max_theory * 100);
        fprintf('===================================\n\n');
    end


    nbins = 40;
    edges = linspace(y_min, y_max, nbins+1);
    bin = discretize(y_s, edges);
    valid = ~isnan(bin);
    u_meas = accumarray(bin(valid), u_s(valid), [nbins, 1], @mean, NaN);
    y_mid = 0.5 * (edges(1:end-1) + edges(2:end));

    plot(u_meas, y_mid, 'bo', 'MarkerSize', 12, 'LineWidth', 1.5, 'MarkerFaceColor', 'none', 'LineStyle', 'none', 'DisplayName', 'SPH');
    hold on;

    % 理论二维通道
    y_c   = 0.5 * (y_min + y_max);
    h_eff = 0.5 * (y_max - y_min);     
    y_th  = linspace(y_min, y_max, 200);
    eta   = (y_th - y_c) / h_eff;       % 归一化
    u_th  = U_max_theory * (1 - eta.^2);

    plot(u_th, y_th, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Theoretical U_{max} = 1.5');
    hold on;

    grid on;
    legend('Location', 'southwest');
    title('Velocity Profile');
    xlabel('u_x');
    ylabel('y');
    xlim([0, 2]);
    ylim([y_min - 0.5, y_max + 0.5]);
    hold off;

    % 保存当前帧
    if config.save_animation
        frame = getframe(fig_animation);
        if strcmpi(config.output_format, 'mp4')
            writeVideo(v, frame);
        elseif strcmpi(config.output_format, 'gif')
            im = frame2im(frame);
            [imind, cm] = rgb2ind(im, 256);
            if idx == 1
                imwrite(imind, cm, gif_filename, 'gif', 'Loopcount', inf, 'DelayTime', config.gif_delay);
            else
                imwrite(imind, cm, gif_filename, 'gif', 'WriteMode', 'append', 'DelayTime', config.gif_delay);
            end
        end
    end

    % 更新进度条
    if config.show_progress
        waitbar(idx / length(frame_indices), progress_bar, ...
                sprintf('处理进度: %d/%d 帧', idx, length(frame_indices)));
    end

    drawnow;
    pause(0.001);
end

% --- 清理资源 ---
if config.save_animation && strcmpi(config.output_format, 'mp4')
    close(v);
    fprintf('视频已成功保存!\n');
end
if config.show_progress
    close(progress_bar);
end

fprintf('流场动画生成完毕。\n');
