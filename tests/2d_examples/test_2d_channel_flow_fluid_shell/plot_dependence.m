% --- 步骤1：设定计算参数与变量 ---

% 清理工作区和命令窗口
clear;
clc;

% 已知参数
p_inf = 1197;       % 来流静压 (Pa)
gamma = 1.4;        % 空气的比热比

% 创建马赫数向量 (从0开始以观察低速极限)
M = 0:0.01:5;       % 马赫数范围从 0 到 5，步长 0.01

% --- 步骤2：实现总压及总压比的计算 ---

% 不可压缩模型总压计算
% 公式来源: 气体动力学课件-02－基本概念.pdf, 第8页
p0_inc = p_inf * (1 + (gamma/2) * M.^2);

% 可压缩模型总压计算 (等熵)
% 公式来源: 气体动力学课件-02－基本概念.pdf, 第8页
exponent = gamma / (gamma - 1);
base = 1 + ((gamma - 1)/2) * M.^2;
p0_comp = p_inf * (base.^exponent);

% 计算两种模型总压的比值
% 当 M=0 时，p0_comp 可能为0，导致除零错误，需处理
% 在此代码中，M=0时，p0_comp = p_inf > 0，所以不会出错
ratio_inc_comp = p0_inc ./ p0_comp;


% --- 步骤3：绘图与注释 (双图)---

% 创建新图形窗口，并设置为较舒适的尺寸


% --- 子图1：总压绝对值对比 ---
subplot(2, 1, 1); % 创建一个2行1列的子图布局，并激活第1个

% 使用对数Y轴(semilogy)以更好地显示数量级差异
plot(M, p0_inc, 'b-', 'LineWidth', 2);
hold on;
plot(M, p0_comp, 'r-', 'LineWidth', 2);

% 添加图表元素
title('总压对比', 'FontSize', 14);
xlabel('Ma', 'FontSize', 12);
ylabel('总压 (p_0) [Pa]', 'FontSize', 12);
legend('不可压', '可压', 'Location', 'northwest');
grid on;
set(gca, 'FontSize', 12);
hold off;

% --- 子图2：总压比值分析 ---
subplot(2, 1, 2); % 激活第2个子图

plot(M, ratio_inc_comp, 'k-', 'LineWidth', 2);

% 添加 M=0.3 的临界线
hold on;
xline(0.3, 'r:', 'LineWidth', 1.5, 'Label', 'M = 0.3');
% 添加比值为1的参考线
yline(1.0, 'g:', 'LineWidth', 1.0);
hold off;

% 添加图表元素
title('不可压/可压缩总压之比', 'FontSize', 14);
xlabel('Ma', 'FontSize', 12);
ylabel('总压比 (p_{0,不可压} / p_{0,可压})', 'FontSize', 12);
legend('比值', 'Location', 'northeast');
grid on;
axis([0 5 0 1.1]); % 设定合适的坐标轴范围
set(gca, 'FontSize', 12);
