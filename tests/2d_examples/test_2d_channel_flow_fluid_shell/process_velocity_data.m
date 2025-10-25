%% SPHinXsys Batch Velocity Data Processing
%
% 脚本功能:
% 1. 清理工作环境。
% 2. 指定包含 VTP 文件的目录。
% 3. 查找所有 "WaterBody_*.vtp" 文件。
% 4. 遍历每个 VTP 文件:
%    a. 从文件名中提取时间 ID。
%    b. 解析 VTP 文件，提取粒子位置和速度数据。
%    c. 将提取的数据存储到结构体数组中。
% 5. 按时间 ID 对数据进行排序。
% 6. 将处理后的数据保存到 'velocity_data.mat' 文件中。
%

% --- 1. 初始化 ---
clear;
close all;
clc;

fprintf('开始批量处理 VTP 文件以提取速度数据...\n');

% --- 2. 设置目录和文件模式 ---
output_dir = 'output'; % 包含 VTP 文件的目录
vtp_files = dir(fullfile(output_dir, 'WaterBody_*.vtp'));

if isempty(vtp_files)
    error('在目录 ''%s'' 中未找到 "WaterBody_*.vtp" 文件。', output_dir);
end

fprintf('找到 %d 个 VTP 文件待处理。\n', length(vtp_files));

% --- 3. 准备数据结构 ---
velocity_data = struct('time_id', {}, 'positions', {}, 'velocities', {}, 'max_velocity', {});

% --- 4. 循环处理每个文件 ---
for i = 1:length(vtp_files)
    file_info = vtp_files(i);
    vtp_file_path = fullfile(output_dir, file_info.name);
    
    fprintf('正在处理文件 (%d/%d): %s\n', i, length(vtp_files), file_info.name);

    % 从文件名中提取 time_id
    [~, name, ~] = fileparts(file_info.name);
    time_id_str_cell = regexp(name, 'WaterBody_(\d+)', 'tokens');
    if isempty(time_id_str_cell)
        warning('无法从文件名中提取 time_id: %s。已跳过此文件。', file_info.name);
        continue;
    end
    time_id = str2double(time_id_str_cell{1}{1});

    % --- 4a. 解析 VTP 文件 (逻辑借鉴自 plot_velocity_field.m) ---
    try
        % 直接把 XML 读成文本，再用正则抓取 DataArray 的内容
        fileText = fileread(vtp_file_path);

        % 小工具函数：按 Name 抓取对应 <DataArray ...>...</DataArray> 的内部文本
        extractData = @(nm) regexp(fileText, ...
            ['<DataArray[^>]*Name="' nm '"[^>]*>([\s\S]*?)</DataArray>'], ...
            'tokens','once');

        posTok = extractData('Position');
        velTok = extractData('Velocity');

        % 与原逻辑对齐：准备同名字符串变量供后续 isempty 检查与 sscanf 使用
        position_data_str = '';
        velocity_data_str = '';

        if ~isempty(posTok)
            position_data_str = strtrim(posTok{1});
        end
        if ~isempty(velTok)
            velocity_data_str = strtrim(velTok{1});
        end
        
        if isempty(position_data_str) || isempty(velocity_data_str)
            warning('在文件 %s 中未找到 Position 或 Velocity 数据。已跳过。', file_info.name);
            continue;
        end
        
        % 将字符串转换为数值矩阵
        positions = reshape(sscanf(position_data_str, '%f'), 3, [])';
        velocities = reshape(sscanf(velocity_data_str, '%f'), 3, [])';

        % --- 4b. 存储数据 ---
        velocity_data(end+1).time_id = time_id;
        velocity_data(end).positions = positions;
        velocity_data(end).velocities = velocities;
        
        % 记录最大速度
        velocity_magnitude = sqrt(velocities(:,1).^2 + velocities(:,2).^2);
        velocity_data(end).max_velocity = max(velocity_magnitude);

    catch ME
        warning('解析 VTP 文件 %s 时出错: %s。已跳过。', file_info.name, ME.message);
    end
end

% --- 5. 按 time_id 对数据排序 ---
if ~isempty(velocity_data)
    [~, sort_idx] = sort([velocity_data.time_id]);
    velocity_data = velocity_data(sort_idx);
    fprintf('数据已按 time_id 排序。\n');
end

% --- 6. 将数据保存到 .mat 文件 ---
if ~isempty(velocity_data)
    output_mat_file = 'velocity_data.mat';
    save(output_mat_file, 'velocity_data');
    fprintf('成功处理 %d 个文件，数据已保存至 ''%s''。\n', length(velocity_data), output_mat_file);
else
    warning('没有成功处理任何文件，未生成 .mat 文件。');
end

% --- 7. 保存Umax收敛数据到统一文件 ---
if ~isempty(velocity_data)
    physical_time = [velocity_data.time_id] * 1e-6; % 实际物理时间
    max_velocities = [velocity_data.max_velocity];
    
    % 创建一个包含时间和速度的结构体
    convergence_data.time = physical_time;
    convergence_data.umax = max_velocities;

    % 根据初始速度生成动态变量名 (将'.'替换为'_')
    initial_velocity_approx = max_velocities(1);
    variable_name = sprintf('u0_%.1f', initial_velocity_approx);
    variable_name = strrep(variable_name, '.', '_');

    % 将结构体赋值给动态变量
    eval([variable_name, ' = convergence_data;']);

    % 将该变量追加保存到 umax.mat 文件
    output_umax_file = 'umax.mat';
    if exist(output_umax_file, 'file')
        save(output_umax_file, variable_name, '-append');
        fprintf('成功将变量 ''%s'' 追加到 ''%s''。\n', variable_name, output_umax_file);
    else
        save(output_umax_file, variable_name);
        fprintf('成功创建 ''%s'' 并保存变量 ''%s''。\n', output_umax_file, variable_name);
    end
end

% --- 8. 从C++源文件中提取物理参数并保存 ---
fprintf('正在从C++源文件提取物理参数...\n');

% 尝试多个可能的路径(确保脚本在不同工作目录下都能运行)
cpp_file_candidates = {
    'channel_flow_shell.cpp',           % 当前目录(脚本运行在项目根目录)
    '../channel_flow_shell.cpp',        % 从output目录回到父目录
    fullfile('..', 'channel_flow_shell.cpp')  % 显式相对路径
};

cpp_file = '';
for k = 1:length(cpp_file_candidates)
    if exist(cpp_file_candidates{k}, 'file')
        cpp_file = cpp_file_candidates{k};
        break;
    end
end

if ~isempty(cpp_file)
    cpp_content = fileread(cpp_file);

    % 使用正则表达式提取参数 (匹配 const Real PARAM = VALUE 格式)
    DL_match = regexp(cpp_content, 'const\s+Real\s+DL\s*=\s*([\d.]+)', 'tokens');
    DH_match = regexp(cpp_content, 'const\s+Real\s+DH\s*=\s*([\d.]+)', 'tokens');
    U_f_match = regexp(cpp_content, 'const\s+Real\s+U_f\s*=\s*([\d.]+)', 'tokens');
    Re_match = regexp(cpp_content, 'const\s+Real\s+Re\s*=\s*([\d.]+)', 'tokens');

    % 创建配置结构体
    sim_config = struct();
    if ~isempty(DL_match), sim_config.DL = str2double(DL_match{1}{1}); end
    if ~isempty(DH_match), sim_config.DH = str2double(DH_match{1}{1}); end
    if ~isempty(U_f_match), sim_config.U_f = str2double(U_f_match{1}{1}); end
    if ~isempty(Re_match), sim_config.Re = str2double(Re_match{1}{1}); end

    % 计算衍生参数
    sim_config.U_max_theory = 1.5 * sim_config.U_f;  % 泊肃叶流理论最大速度
    sim_config.time_scale = 1e-6;  % time_id到物理时间的转换系数(秒)

    % 保存到velocity_data.mat (追加模式)
    if exist(output_mat_file, 'file')
        save(output_mat_file, 'sim_config', '-append');
        fprintf('成功提取并保存物理参数: DL=%.1f, DH=%.1f, U_f=%.1f, Re=%.1f\n', ...
                sim_config.DL, sim_config.DH, sim_config.U_f, sim_config.Re);
        fprintf('衍生参数: U_max_theory=%.2f, time_scale=%.1e\n', ...
                sim_config.U_max_theory, sim_config.time_scale);
    else
        warning('velocity_data.mat文件不存在,无法追加sim_config。');
    end
else
    warning('未找到C++源文件(已尝试以下路径: %s),无法自动提取物理参数。', ...
            strjoin(cpp_file_candidates, ', '));
    fprintf('请确保C++源文件 ''channel_flow_shell.cpp'' 位于脚本目录或output父目录。\n');
end

