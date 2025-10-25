%% 基于源码逐行推导Dt和dt的真实公式
% 参考: fluid_time_step.cpp (已完整抄录)

fprintf('===== 参数定义 =====\n');
% 物理参数
mu_f = 0.02;      % Line 22: mu_f = rho0_f * U_f * DH / Re
rho0_f = 1.0;     % Line 18
U_f = 1.0;        % Line 19
DH = 2.0;         % Line 14
c_f = 10.0;       % Line 20
h_min = 0.05;     % resolution_ref

% CFL参数
advectionCFL = 0.25;  % 默认值 (fluid_time_step.h Line 88)
acousticCFL = 0.6;    % 默认值 (fluid_time_step.h Line 48)

% U_ref传入值
U_ref = 1.5 * U_f;   % Line 200: get_fluid_advection_time_step_size(water_block, 1.5 * U_f)

fprintf('h_min = %.3f m\n', h_min);
fprintf('μ_f = %.3f Pa·s\n', mu_f);
fprintf('ρ₀ = %.1f kg/m³\n', rho0_f);
fprintf('c_f = %.1f m/s\n', c_f);
fprintf('U_ref = %.3f m/s\n', U_ref);
fprintf('advectionCFL = %.2f\n', advectionCFL);
fprintf('acousticCFL = %.2f\n', acousticCFL);

fprintf('\n===== 步骤1: 计算speed_ref_ (Line 71-78) =====\n');
% AdvectionViscousTimeStep构造函数
viscous_speed = mu_f / (rho0_f * h_min);
fprintf('viscous_speed = μ/(ρ₀h) = %.3f / (%.1f × %.3f) = %.3f m/s\n', ...
        mu_f, rho0_f, h_min, viscous_speed);

speed_ref_ = max(viscous_speed, U_ref);  % Line 77
fprintf('speed_ref_ = max(%.3f, %.3f) = %.3f m/s\n', ...
        viscous_speed, U_ref, speed_ref_);

fprintf('\n===== 步骤2: 计算Dt (Line 58-68) =====\n');
% AdvectionTimeStep::reduce (Line 58-62)
fprintf('reduce函数计算 max(|v|², 4h|a|/m)\n');
fprintf('假设: 加速度项可忽略,reduce ≈ |v|²\n');

% 模拟不同时刻的速度
velocities = [1.0, 1.15, 1.193, 1.5, 1.55];
fprintf('\n速度(m/s)\t|v|²\t\tsqrt(|v|²)\tspeed_max\tmax(speed_max, speed_ref_)\tDt(s)\n');
fprintf('--------\t----\t\t----------\t---------\t-----------------------\t------\n');

for v = velocities
    v_sqr = v^2;
    speed_max = sqrt(v_sqr);  % Line 67
    speed_final = max(speed_max, speed_ref_);  % Line 68分母
    Dt = advectionCFL * h_min / speed_final;  % Line 68
    fprintf('%.3f\t\t%.4f\t\t%.3f\t\t%.3f\t\t%.3f\t\t\t%.6f\n', ...
            v, v_sqr, speed_max, speed_max, speed_final, Dt);
end

fprintf('\n关键观察:\n');
if speed_ref_ > 1.55
    fprintf('→ 当|v| < %.3f时,Dt始终由speed_ref_锁定!\n', speed_ref_);
    Dt_locked = advectionCFL * h_min / speed_ref_;
    fprintf('→ Dt_locked = %.2f × %.3f / %.3f = %.6f s\n', ...
            advectionCFL, h_min, speed_ref_, Dt_locked);
end

fprintf('\n===== 步骤3: 计算dt (Line 22-33) =====\n');
% AcousticTimeStep::reduce (Line 22-26)
fprintf('reduce函数计算 max(c + |v|, 4h|a|/m)\n');
fprintf('假设: 加速度项可忽略,reduce ≈ c + |v|\n');

fprintf('\n速度(m/s)\tc + |v|\t\tdt(s)\n');
fprintf('--------\t-------\t\t------\n');

for v = velocities
    wave_speed = c_f + v;  % Line 26
    dt = acousticCFL * h_min / wave_speed;  % Line 33
    fprintf('%.3f\t\t%.3f\t\t%.6f\n', v, wave_speed, dt);
end

fprintf('\n===== 步骤4: 计算Dt/dt比值 =====\n');
fprintf('\n速度(m/s)\tDt(s)\t\tdt(s)\t\tDt/dt\n');
fprintf('--------\t------\t\t------\t\t-----\n');

for v = velocities
    % Dt计算
    speed_final = max(v, speed_ref_);
    Dt = advectionCFL * h_min / speed_final;

    % dt计算
    wave_speed = c_f + v;
    dt = acousticCFL * h_min / wave_speed;

    % 比值
    ratio = Dt / dt;
    fprintf('%.3f\t\t%.6f\t%.6f\t%.3f\n', v, Dt, dt, ratio);
end

fprintf('\n===== 步骤5: 与观测数据对比 =====\n');
fprintf('观测数据:\n');
fprintf('  t=12.5s: Dt=0.010833, Dt/dt=4 → dt=0.002708\n');
fprintf('  t=90s:   Dt=0.010489, Dt/dt=4 → dt=0.002622\n');

fprintf('\n理论预测(v=1.193, 收敛速度):\n');
v_conv = 1.193;
speed_final = max(v_conv, speed_ref_);
Dt_theory = advectionCFL * h_min / speed_final;
wave_speed = c_f + v_conv;
dt_theory = acousticCFL * h_min / wave_speed;
ratio_theory = Dt_theory / dt_theory;

fprintf('  Dt_theory = %.2f × %.3f / max(%.3f, %.3f) = %.6f s\n', ...
        advectionCFL, h_min, v_conv, speed_ref_, Dt_theory);
fprintf('  dt_theory = %.2f × %.3f / (%.1f + %.3f) = %.6f s\n', ...
        acousticCFL, h_min, c_f, v_conv, dt_theory);
fprintf('  (Dt/dt)_theory = %.6f / %.6f = %.3f\n', ...
        Dt_theory, dt_theory, ratio_theory);

fprintf('\n误差分析:\n');
Dt_obs_avg = (0.010833 + 0.010489) / 2;
dt_obs_avg = Dt_obs_avg / 4;
err_Dt = abs(Dt_theory - Dt_obs_avg) / Dt_obs_avg * 100;
err_dt = abs(dt_theory - dt_obs_avg) / dt_obs_avg * 100;
err_ratio = abs(ratio_theory - 4) / 4 * 100;

fprintf('  Dt误差: %.2f%%\n', err_Dt);
fprintf('  dt误差: %.2f%%\n', err_dt);
fprintf('  (Dt/dt)误差: %.2f%%\n', err_ratio);

if err_ratio < 1
    fprintf('\n✅ 结论: 理论模型与观测完全一致!\n');
else
    fprintf('\n❌ 结论: 仍存在误差,需进一步调查:\n');
    fprintf('   1. 加速度项是否可忽略?\n');
    fprintf('   2. 实际CFL参数是否为默认值?\n');
    fprintf('   3. 是否存在其他修正因子?\n');
end

fprintf('\n===== 最终公式 =====\n');
fprintf('Dt = advectionCFL × h / max(|v|, speed_ref_)\n');
fprintf('dt = acousticCFL × h / (c + |v|)\n');
fprintf('Dt/dt = [advectionCFL / acousticCFL] × [(c + |v|) / max(|v|, speed_ref_)]\n');

fprintf('\n当|v| < speed_ref_时:\n');
fprintf('Dt/dt = [%.2f / %.2f] × [(%.1f + v) / %.3f]\n', ...
        advectionCFL, acousticCFL, c_f, speed_ref_);
fprintf('      = %.4f × [(%.1f + v) / %.3f]\n', ...
        advectionCFL / acousticCFL, c_f, speed_ref_);

fprintf('\n若Dt/dt恒为4:\n');
fprintf('4 = %.4f × [(%.1f + v) / %.3f]\n', ...
        advectionCFL / acousticCFL, c_f, speed_ref_);
fprintf('→ (%.1f + v) / %.3f = %.3f\n', ...
        c_f, speed_ref_, 4 / (advectionCFL / acousticCFL));
fprintf('→ %.1f + v = %.3f\n', ...
        c_f, speed_ref_ * 4 / (advectionCFL / acousticCFL));
v_required = speed_ref_ * 4 / (advectionCFL / acousticCFL) - c_f;
fprintf('→ v = %.3f m/s\n', v_required);

if v_required >= 0 && v_required < 2
    fprintf('\n这意味着: 当速度恒定在v≈%.3f时,Dt/dt才会恒为4\n', v_required);
    fprintf('但你观测到的速度从1.15变化到1.55,Dt/dt仍恒为4,这是矛盾的!\n');
    fprintf('\n可能的解释:\n');
    fprintf('1. 加速度项实际上主导了reduce函数的返回值\n');
    fprintf('2. 存在其他隐藏的限制器(例如min/max操作)\n');
    fprintf('3. 实际参数与源码默认值不同\n');
end

fprintf('\n程序完成。\n');
