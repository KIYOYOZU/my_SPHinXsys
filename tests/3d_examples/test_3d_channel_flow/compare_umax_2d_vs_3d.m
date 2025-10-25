% compare_umax_2d_vs_3d.m
% 加载 2D 与 3D 通道流算例的最大速度演化，并进行对比分析。
% 2D 数据来源：tests/2d_examples/test_2d_channel_flow_fluid_shell/umax.mat
% 3D 数据来源：当前目录生成的 flow_data.mat（analysis.centerline_history）

clear; clc;

%% 路径配置
base_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(base_dir, '..', '..', '..');
case_2d_dir = fullfile(proj_root, 'tests', '2d_examples', ...
    'test_2d_channel_flow_fluid_shell');
case_3d_dir = base_dir; % 当前目录
output_dir = fullfile(case_3d_dir, 'output');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

%% 载入 2D umax 数据
umax_data_path = fullfile(case_2d_dir, 'umax.mat');
if ~isfile(umax_data_path)
    error('无法找到 2D umax 数据文件：%s', umax_data_path);
end
data2d = load(umax_data_path);

% 选择初速度为 1.0 的数据集（默认读取 u0_1_0）
candidate_names = fieldnames(data2d);
target_name = 'u0_1_0';
if ~ismember(target_name, candidate_names)
    error('未在 umax.mat 中找到数据集 %s。', target_name);
end
series2d = data2d.(target_name);
t2d = series2d.time(:);
u2d = series2d.umax(:);
u2d_std = zeros(size(u2d));

%% 载入 3D flow_data 数据
flow_data_path = fullfile(case_3d_dir, 'flow_data.mat');
if ~isfile(flow_data_path)
    error('请先运行 3D 案例并生成 flow_data.mat：%s', flow_data_path);
end
data3d = load(flow_data_path);
if ~isfield(data3d, 'analysis') || ~isfield(data3d.analysis, 'centerline_history')
    error('flow_data.mat 中缺少 analysis.centerline_history。');
end
centerline_tbl = data3d.analysis.centerline_history;
t3d = centerline_tbl.time(:);
u3d_signed = centerline_tbl.u_mid(:);
if isfield(data3d, 'config') && isfield(data3d.config, 'flow_direction_body')
    flow_direction = data3d.config.flow_direction_body;
elseif isfield(data3d, 'config') && isfield(data3d.config, 'flow_direction')
    flow_direction = data3d.config.flow_direction;
else
    flow_direction = sign(u3d_signed(find(~isnan(u3d_signed), 1, 'last')));
    if flow_direction == 0
        flow_direction = 1.0;
    end
end
u3d = flow_direction * u3d_signed; % 对齐方向后用于与 2D 数据对比

%% 构建公共时间轴并计算差异
t_max_common = min(max(t2d), max(t3d));
t_common = linspace(0, t_max_common, 400).';
u2d_interp = interp1(t2d, u2d, t_common, 'pchip', 'extrap');
u3d_interp = interp1(t3d, u3d, t_common, 'pchip', 'extrap');
delta_u = u3d_interp - u2d_interp;

metrics = struct();
metrics.t_common = t_common;
metrics.u2d_interp = u2d_interp;
metrics.u3d_interp = u3d_interp;
metrics.flow_direction = flow_direction;
metrics.delta_mean = mean(delta_u);
metrics.delta_max = max(delta_u);
metrics.delta_min = min(delta_u);
metrics.u2d_peak = max(u2d);
metrics.u3d_peak_aligned = max(u3d);
metrics.u3d_peak_signed = max(u3d_signed);
metrics.u3d_trough_signed = min(u3d_signed);

%% 绘图
fig = figure('Name', 'U_{max} Comparison 2D vs 3D', 'Position', [100, 100, 900, 600]);
hold on; grid on; box on;
plot(t2d, u2d, 'Color', [0 0.45 0.74], 'LineWidth', 2, 'DisplayName', '2D umax (mean)');
plot(t3d, u3d, 'Color', [0.85 0.33 0.1], 'LineWidth', 2, 'DisplayName', '3D centerline u_{mid} (aligned)');
% plot(t_common, u3d_interp - u2d_interp + metrics.u2d_peak, '--', 'Color', [0.47 0.67 0.19], ...
%     'LineWidth', 1.5, 'DisplayName', 'Δu + u_{2D,peak}');
xlabel('time [s]');
ylabel('velocity (aligned, m/s)');
title('Plane Poiseuille Channel Flow: U_{max} comparison (aligned 2D vs 3D)');
legend('Location', 'best');

% annotation_text = sprintf(['Peak velocities:\n 2D: %.4f\n 3D: %.4f\n' ...
%     'Δu (mean/min/max): %.4e / %.4e / %.4e'], ...
%     metrics.u2d_peak, metrics.u3d_peak, metrics.delta_mean, ...
%     metrics.delta_min, metrics.delta_max);
% annotation('textbox', [0.62, 0.15, 0.3, 0.2], 'String', annotation_text, ...
%     'FitBoxToText', 'on', 'BackgroundColor', [1 1 1 0.8]);

figure_path = fullfile(output_dir, 'umax_comparison.png');
saveas(fig, figure_path);

%% 保存对比数据
comparison_path = fullfile(output_dir, 'umax_comparison.mat');
save(comparison_path, 't2d', 'u2d', 'u2d_std', 't3d', 'u3d', 'u3d_signed', 'metrics');

fprintf('2D/3D umax 对比完成。\n图像保存至: %s\n数据保存至: %s\n', figure_path, comparison_path);
