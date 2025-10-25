% 分析时间步数据
% 从输出文件中提取时间和时间步信息

% 读取观测数据（第一列是时间）
data = readmatrix('output/FluidAxialObserver_Velocity.dat');
times = data(:, 1);

% 计算Dt（输出间隔）
Dt_values = diff(times);
mean_Dt = mean(Dt_values);
std_Dt = std(Dt_values);

fprintf('=== 时间步分析 ===\n');
fprintf('总时间: %.3f s (从 %.3f 到 %.3f)\n', times(end) - times(1), times(1), times(end));
fprintf('输出步数: %d\n', length(times));
fprintf('平均Dt: %.6f s (±%.6f)\n', mean_Dt, std_Dt);

% 根据源码公式反推speed_ref_
% Dt = advectionCFL * h_min / max(speed_max, speed_ref_)
% 如果Dt被speed_ref_锁定：
h_min = 0.05;
advectionCFL = 0.25;
speed_ref_from_Dt = advectionCFL * h_min / mean_Dt;

fprintf('\n=== 反推参数 ===\n');
fprintf('已知: advectionCFL=%.2f, h_min=%.3f\n', advectionCFL, h_min);
fprintf('从Dt反推: speed_ref_ = %.6f m/s\n', speed_ref_from_Dt);

% 理论预期
U_ref_input = 1.5;  % channel_flow_shell.cpp Line 88
mu_f = 0.02;
rho0 = 1.0;
viscous_speed = mu_f / (rho0 * h_min);

fprintf('\n=== 理论预期 ===\n');
fprintf('输入U_ref: %.3f m/s (Line 88)\n', U_ref_input);
fprintf('粘性速度: μ/(ρ₀h) = %.3f m/s\n', viscous_speed);
fprintf('speed_ref_锁定值 (Line 77): max(%.3f, %.3f) = %.3f m/s\n', ...
        viscous_speed, U_ref_input, max(viscous_speed, U_ref_input));

% 检查矛盾
fprintf('\n=== 矛盾检查 ===\n');
if abs(speed_ref_from_Dt - U_ref_input) > 0.01
    fprintf('❌ 矛盾: 反推值(%.3f) ≠ 理论值(%.3f)\n', speed_ref_from_Dt, U_ref_input);
    fprintf('   差异: %.3f%%\n', abs(speed_ref_from_Dt - U_ref_input) / U_ref_input * 100);

    % 可能的解释
    fprintf('\n可能原因:\n');
    fprintf('1. h_min实际值不是0.05?\n');
    fprintf('2. advectionCFL实际值不是0.25?\n');
    fprintf('3. 存在其他隐藏的缩放因子?\n');

    % 反推h_min
    h_min_inferred = mean_Dt * U_ref_input / advectionCFL;
    fprintf('\n如果speed_ref_=%.3f: 则h_min=%.6f\n', U_ref_input, h_min_inferred);

    % 反推advectionCFL
    advectionCFL_inferred = mean_Dt * U_ref_input / h_min;
    fprintf('如果h_min=%.3f: 则advectionCFL=%.6f\n', h_min, advectionCFL_inferred);
else
    fprintf('✅ 一致: Dt符合speed_ref_=%.3f的锁定机制\n', U_ref_input);
end

% 分析Dt/dt比值
fprintf('\n=== Dt/dt分析 ===\n');
fprintf('观测到的Dt/dt: 4 (恒定)\n');
fprintf('→ dt = Dt/4 = %.6f s\n', mean_Dt / 4);

% 从dt反推dt的计算
acousticCFL = 0.6;
c_f = 10;  % 声速
% dt = acousticCFL * h / (c + |v| + ...)

fprintf('\n如果dt由声速主导:\n');
dt_acoustic_only = acousticCFL * h_min / c_f;
fprintf('  dt_theory = %.2f × %.3f / %.1f = %.6f s\n', ...
        acousticCFL, h_min, c_f, dt_acoustic_only);
fprintf('  dt_actual = %.6f s\n', mean_Dt / 4);
fprintf('  比值: %.3f\n', (mean_Dt / 4) / dt_acoustic_only);

fprintf('\n如果考虑速度项:\n');
v_typical = 1.5;
dt_with_velocity = acousticCFL * h_min / (c_f + v_typical);
fprintf('  dt_theory = %.2f × %.3f / (%.1f + %.1f) = %.6f s\n', ...
        acousticCFL, h_min, c_f, v_typical, dt_with_velocity);
fprintf('  与实际比值: %.3f\n', (mean_Dt / 4) / dt_with_velocity);

fprintf('\n程序完成。\n');
