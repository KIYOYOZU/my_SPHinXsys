%% 验证加速度项对Dt的影响
fprintf('===== 加速度项分析 =====\n');

% 参数
h_min = 0.05;
advectionCFL = 0.25;
speed_ref_ = 1.5;

% 估算加速度量级
mu_f = 0.02;
rho0 = 1.0;
U_f = 1.0;
DH = 2.0;

% 粘性加速度 (量级估计)
fprintf('\n粘性加速度估计:\n');
a_vis_estimate = mu_f * U_f / (rho0 * h_min^2);
fprintf('  a_vis ~ μU/(ρh²) = %.3f × %.1f / (%.1f × %.4f) = %.2f m/s²\n', ...
        mu_f, U_f, rho0, h_min^2, a_vis_estimate);

% 驱动力加速度
fx = 12.0 * mu_f * U_f / (rho0 * DH * DH);
fprintf('  fx = 12μU/(ρDH²) = %.3f m/s² (Line 207)\n', fx);

% 合成加速度 (粗略)
fprintf('\n典型合加速度:\n');
a_typical_values = [0.06, 1.0, 5.0, 10.0, 15.0, 20.0];

fprintf('\n|a| (m/s²)\t4h|a|/m\t\t|v|² (v=1.2)\tmax(...)\tsqrt(...)\tDt (s)\n');
fprintf('----------\t-------\t\t------------\t--------\t---------\t-------\n');

v = 1.2;  % 典型速度
v_sqr = v^2;

for a = a_typical_values
    acc_scale = 4 * h_min * a;  % 假设m=1
    max_val = max(v_sqr, acc_scale);
    speed_max = sqrt(max_val);
    speed_final = max(speed_max, speed_ref_);
    Dt = advectionCFL * h_min / speed_final;

    dominant = '';
    if acc_scale > v_sqr
        dominant = ' ← 加速度主导';
    else
        dominant = ' ← 速度主导';
    end

    fprintf('%.2f\t\t%.4f\t\t%.4f\t\t%.4f\t\t%.4f\t\t%.6f%s\n', ...
            a, acc_scale, v_sqr, max_val, speed_max, Dt, dominant);
end

fprintf('\n===== 反推观测数据所需的加速度 =====\n');
Dt_obs = 0.010833;  % 观测值
v_obs = 1.2;  % 假设速度

fprintf('观测: Dt = %.6f s\n', Dt_obs);
fprintf('假设: v = %.3f m/s\n', v_obs);

% 从Dt反推speed_final
speed_final_inferred = advectionCFL * h_min / Dt_obs;
fprintf('\nSpeed_final = %.2f × %.3f / %.6f = %.4f m/s\n', ...
        advectionCFL, h_min, Dt_obs, speed_final_inferred);

if speed_final_inferred > speed_ref_
    fprintf('→ speed_final > speed_ref_(%.3f), 不可能!\n', speed_ref_);
    fprintf('→ 因此必然是 speed_final = speed_ref_ = %.3f 被锁定\n', speed_ref_);
    fprintf('→ 这意味着: max(speed_max, speed_ref_) = speed_ref_\n');
    fprintf('→ 即: speed_max < speed_ref_\n');

    % 但这与观测矛盾,因为如果speed_max < 1.5
    % 则Dt = 0.25 × 0.05 / 1.5 = 0.008333 ≠ 0.010833
    fprintf('\n❌ 矛盾! 这说明我对公式的理解仍然有误!\n');
else
    fprintf('→ speed_final = %.4f < speed_ref_\n', speed_final_inferred);
    fprintf('→ 因此 speed_max = speed_final = %.4f\n', speed_final_inferred);

    % 反推reduce的返回值
    reduce_val = speed_final_inferred^2;
    fprintf('\nReduce返回值: max(|v|², 4h|a|/m) = %.4f\n', reduce_val);

    % 检查是速度还是加速度主导
    v_sqr_obs = v_obs^2;
    fprintf('|v|² = %.3f² = %.4f\n', v_obs, v_sqr_obs);

    if reduce_val > v_sqr_obs
        fprintf('→ 加速度项主导! 4h|a|/m = %.4f\n', reduce_val);
        a_inferred = reduce_val / (4 * h_min);
        fprintf('→ |a| = %.4f / (4 × %.3f) = %.2f m/s²\n', ...
                reduce_val, h_min, a_inferred);

        fprintf('\n这是否合理?\n');
        fprintf('  粘性加速度估计: ~%.2f m/s²\n', a_vis_estimate);
        fprintf('  驱动力加速度: %.3f m/s²\n', fx);
        fprintf('  推断的加速度: %.2f m/s²\n', a_inferred);

        if a_inferred > a_vis_estimate / 2 && a_inferred < a_vis_estimate * 2
            fprintf('  ✅ 在合理范围内!\n');
        else
            fprintf('  ❌ 超出预期范围\n');
        end
    else
        fprintf('→ 速度项主导 (与默认假设一致)\n');
    end
end

fprintf('\n===== 检查Dt/dt恒为4的机制 =====\n');
fprintf('\n假设: 加速度项主导Dt, 速度项主导dt\n');
fprintf('Dt = advectionCFL × h / sqrt(4h|a|/m)\n');
fprintf('dt = acousticCFL × h / (c + |v|)\n');
fprintf('Dt/dt = [advectionCFL / acousticCFL] × [(c + |v|) / sqrt(4h|a|/m)]\n');

fprintf('\n若Dt/dt = 4:\n');
acousticCFL = 0.6;
c_f = 10.0;
v = 1.2;
ratio_target = 4;

fprintf('4 = [%.2f / %.2f] × [(%.1f + %.1f) / sqrt(4 × %.3f × |a|)]\n', ...
        advectionCFL, acousticCFL, c_f, v, h_min);

% 求解|a|
% 4 = (0.25 / 0.6) × [(10 + 1.2) / sqrt(0.2 × |a|)]
% 4 / 0.4167 = 11.2 / sqrt(0.2 |a|)
% 9.6 = 11.2 / sqrt(0.2 |a|)
% sqrt(0.2 |a|) = 11.2 / 9.6 = 1.1667
% 0.2 |a| = 1.3611
% |a| = 6.806

lhs = ratio_target / (advectionCFL / acousticCFL);
fprintf('%.3f = (%.1f + %.1f) / sqrt(4 × %.3f × |a|)\n', lhs, c_f, v, h_min);

rhs_numerator = c_f + v;
denominator_target = rhs_numerator / lhs;
fprintf('sqrt(4 × %.3f × |a|) = %.3f\n', h_min, denominator_target);

acc_scale_target = denominator_target^2;
a_target = acc_scale_target / (4 * h_min);

fprintf('|a| = %.3f / (4 × %.3f) = %.2f m/s²\n', acc_scale_target, h_min, a_target);

fprintf('\n结论: 若Dt/dt恒为4, 则需要|a| ≈ %.2f m/s²\n', a_target);
fprintf('这与粘性加速度估计(%.2f m/s²)接近!\n', a_vis_estimate);

if abs(a_target - a_vis_estimate) / a_vis_estimate < 0.5
    fprintf('✅ 猜想验证: 加速度项主导Dt, 且加速度相对稳定, 导致Dt/dt恒为4!\n');
else
    fprintf('❌ 加速度值不符, 需进一步调查\n');
end

fprintf('\n程序完成。\n');
