%% 验证 GTest 结果 - 检查最终速度是否满足容差
% 此脚本读取最后时刻的径向速度分布,与解析解比较
%
% 作者: Claude Code (AI Assistant)
% 日期: 2025-10-15
% 目的: 验证理论与实际偏差分析的结论

clc; clear; close all;

%% 参数定义 (与 channel_flow_shell.cpp 一致)
DH = 2.0;          % 通道高度 (m)
U_f = 1.0;         % 特征速度 (m/s)
tolerance = U_f * 5e-2;  % GTest 容差 (Line 345, 353)

fprintf('=== GTest 验证分析 ===\n');
fprintf('参数设置:\n');
fprintf('  通道高度 DH = %.2f m\n', DH);
fprintf('  特征速度 U_f = %.2f m/s\n', U_f);
fprintf('  GTest 容差 = %.4f m/s\n\n', tolerance);

%% 读取实际模拟数据
try
    % 使用 importdata 读取 SPHinXsys 输出格式
    % 格式通常为: x, y, vx, vy (或类似)
    data = importdata('output\FluidRadialObserver_Velocity.dat');

    if isstruct(data)
        data = data.data;  % 提取数值部分
    end

    % 假设列格式: [x, y, vx, vy]
    if size(data, 2) >= 3
        positions = data(:, 1:2);  % x, y 坐标
        velocities = data(:, 3:4); % vx, vy
    else
        error('数据格式不符合预期,列数 < 3');
    end

    fprintf('✓ 成功读取数据: %d 个观察点\n\n', size(data, 1));

catch ME
    fprintf('✗ 读取数据失败: %s\n', ME.message);
    fprintf('提示: 请确保模拟已运行完成,输出文件存在\n');
    return;
end

%% 定义解析解 (泊肃叶流, Line 333-336)
analytical_solution = @(y) 1.5 * U_f * (1 - (2*y/DH - 1).^2);

%% 逐点比较
fprintf('逐点验证 (径向观察点):\n');
fprintf('%-10s %-10s %-12s %-12s %-12s %-10s\n', ...
    'Index', 'y (m)', 'u_theory', 'u_actual', 'Error', 'Pass?');
fprintf('%s\n', repmat('-', 1, 78));

num_points = size(positions, 1);
errors = zeros(num_points, 1);
pass_flags = false(num_points, 1);

for i = 1:num_points
    y_pos = positions(i, 2);  % y 坐标
    u_theory = analytical_solution(y_pos);  % 理论速度 (x 方向)
    u_actual = velocities(i, 1);  % 实际速度 (vx)

    error_val = abs(u_theory - u_actual);
    pass = error_val <= tolerance;

    errors(i) = error_val;
    pass_flags(i) = pass;

    % 只显示前 5 个、最大误差和通道中心附近的点
    if i <= 5 || i == num_points || error_val > 0.1 || abs(y_pos - DH/2) < 0.1
        fprintf('%-10d %-10.4f %-12.4f %-12.4f %-12.4f %-10s\n', ...
            i, y_pos, u_theory, u_actual, error_val, ...
            char(pass*"✓ PASS" + ~pass*"✗ FAIL"));
    end
end

fprintf('%s\n', repmat('-', 1, 78));

%% 统计结果
max_error = max(errors);
mean_error = mean(errors);
num_passed = sum(pass_flags);
num_failed = num_points - num_passed;

fprintf('\n统计结果:\n');
fprintf('  最大误差: %.4f m/s (容差: %.4f m/s)\n', max_error, tolerance);
fprintf('  平均误差: %.4f m/s\n', mean_error);
fprintf('  通过点数: %d / %d (%.1f%%)\n', num_passed, num_points, ...
    100*num_passed/num_points);
fprintf('  失败点数: %d / %d (%.1f%%)\n', num_failed, num_points, ...
    100*num_failed/num_points);

%% GTest 最终判定
fprintf('\n=== GTest 最终结果 ===\n');
if num_failed == 0
    fprintf('✓ 所有测试通过! (EXPECT_NEAR 满足)\n');
else
    fprintf('✗ 测试失败! %d 个点超出容差\n', num_failed);
    fprintf('  (对应 channel_flow_shell.cpp Line 352-353)\n');
end

%% 可视化对比
figure('Name', 'GTest Verification', 'Position', [100, 100, 1200, 500]);

% 子图1: 速度剖面对比
subplot(1, 2, 1);
y_range = linspace(0, DH, 100);
plot(y_range, analytical_solution(y_range), 'b-', 'LineWidth', 2, ...
    'DisplayName', '理论解 (泊肃叶流)');
hold on;
scatter(positions(:, 2), velocities(:, 1), 50, 'r', 'filled', ...
    'DisplayName', '实际数据');
grid on;
xlabel('通道高度 y (m)', 'FontSize', 12);
ylabel('x 方向速度 u (m/s)', 'FontSize', 12);
title('速度剖面对比', 'FontSize', 14, 'FontWeight', 'bold');
legend('Location', 'south');
ylim([0, 1.6]);

% 标注最大速度
[u_max_theory, ~] = max(analytical_solution(y_range));
[u_max_actual, idx_max] = max(velocities(:, 1));
y_max_actual = positions(idx_max, 2);
plot(DH/2, u_max_theory, 'bo', 'MarkerSize', 12, 'LineWidth', 2);
plot(y_max_actual, u_max_actual, 'ro', 'MarkerSize', 12, 'LineWidth', 2);
text(DH/2, u_max_theory + 0.1, sprintf('理论: %.3f m/s', u_max_theory), ...
    'HorizontalAlignment', 'center', 'FontSize', 10);
text(y_max_actual, u_max_actual - 0.1, sprintf('实际: %.3f m/s', u_max_actual), ...
    'HorizontalAlignment', 'center', 'FontSize', 10);

% 子图2: 误差分布
subplot(1, 2, 2);
bar(1:num_points, errors, 'FaceColor', [0.3, 0.6, 0.9]);
hold on;
plot([0, num_points+1], [tolerance, tolerance], 'r--', 'LineWidth', 2, ...
    'DisplayName', 'GTest 容差');
grid on;
xlabel('观察点编号', 'FontSize', 12);
ylabel('绝对误差 (m/s)', 'FontSize', 12);
title('误差分布', 'FontSize', 14, 'FontWeight', 'bold');
legend('Location', 'best');

% 标注最大误差点
[~, idx_max_error] = max(errors);
plot(idx_max_error, errors(idx_max_error), 'ro', 'MarkerSize', 10, ...
    'MarkerFaceColor', 'r');
text(idx_max_error, errors(idx_max_error) + 0.02, ...
    sprintf('最大: %.4f', errors(idx_max_error)), ...
    'HorizontalAlignment', 'center', 'FontSize', 9);

saveas(gcf, 'GTest_Verification_Results.png');
fprintf('\n✓ 图片已保存: GTest_Verification_Results.png\n');

%% 生成总结报告
fprintf('\n=== 关键发现 ===\n');
fprintf('1. 理论最大速度: %.3f m/s (泊肃叶流解析解)\n', u_max_theory);
fprintf('2. 实际最大速度: %.3f m/s (数值模拟结果)\n', u_max_actual);
fprintf('3. 偏差百分比: %.1f%% (低于理论值)\n', ...
    100*(u_max_actual - u_max_theory)/u_max_theory);
fprintf('4. 偏差是否符合预期: ');
expected_deviation = -20;  % 理论与实际偏差分析.md 中的预测
actual_deviation = 100*(u_max_actual - u_max_theory)/u_max_theory;
if abs(actual_deviation - expected_deviation) < 5
    fprintf('✓ 是 (与分析报告一致)\n');
else
    fprintf('✗ 否 (实际 %.1f%%, 预期 %.1f%%)\n', ...
        actual_deviation, expected_deviation);
end

fprintf('\n结论: ');
if max_error > tolerance
    fprintf('数值结果与理论值偏差过大,验证了 "传输速度修正" 假设!\n');
else
    fprintf('数值结果与理论值吻合良好,需重新评估偏差原因。\n');
end
