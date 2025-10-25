%% preprocess_data_fvm.m
% 功能：从 FVM output/*.vtu 文件中提取时间、单元中心位置、速度数据
% 输出：flow_data.mat（包含结构体数组 flow_data）
%
% 说明：FVM UnstructuredGrid 文件结构：
%  - Points: 网格节点坐标
%  - Cells: 由节点组成的单元（四面体等）
%  - Velocity: 定义在单元中心（CellData），不是节点（PointData）

clc; clear; close all;

%% 配置参数
output_dir = 'output';
output_mat_file = 'flow_data.mat';
time_scale_factor = 1.0;  % 时间缩放因子（根据实际情况调整）

%% 扫描并排序 .vtu 文件
vtu_files = dir(fullfile(output_dir, '*.vtu'));

% 自然排序（确保 file10.vtu 在 file2.vtu 之后）
[~, sorted_idx] = sort_nat({vtu_files.name});
vtu_files = vtu_files(sorted_idx);

fprintf('找到 %d 个 .vtu 文件\n', length(vtu_files));

%% 初始化结构体数组
flow_data = struct('time', [], 'particles', struct('position', [], 'velocity', []));
valid_count = 0;
skipped_count = 0;

%% 循环处理每个 .vtu 文件
for i = 1:length(vtu_files)
    filename = vtu_files(i).name;
    filepath = fullfile(output_dir, filename);

    % 提取时间（从文件名中提取数字）
    tokens = regexp(filename, '_(\d+)\.vtu', 'tokens');
    if isempty(tokens)
        fprintf('警告：无法从文件名 %s 中提取时间，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end
    time_step = str2double(tokens{1}{1});
    current_time = time_step * time_scale_factor;

    % 读取文件内容
    try
        file_content = fileread(filepath);
    catch
        fprintf('警告：无法读取文件 %s，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end

    % 提取节点位置数据（<Points> 标签内的 DataArray）
    points_pattern = '<Points>(.*?)</Points>';
    points_block_match = regexp(file_content, points_pattern, 'tokens');

    if isempty(points_block_match)
        fprintf('警告：文件 %s 中未找到<Points>标签，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end

    points_block = points_block_match{1}{1};
    dataarray_pattern = '<DataArray[^>]*>(.*?)</DataArray>';
    dataarray_match = regexp(points_block, dataarray_pattern, 'tokens');

    if isempty(dataarray_match)
        fprintf('警告：文件 %s 的<Points>中未找到DataArray，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end

    points_str = strtrim(dataarray_match{1}{1});
    points_data = sscanf(points_str, '%f');
    node_positions = reshape(points_data, 3, [])';  % N_nodes × 3 矩阵

    % 提取单元连接关系（<Cells> 标签，用于计算单元中心）
    cells_pattern = '<Cells>(.*?)</Cells>';
    cells_block_match = regexp(file_content, cells_pattern, 'tokens');

    if isempty(cells_block_match)
        fprintf('警告：文件 %s 中未找到<Cells>标签，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end

    % 提取连接性数据（connectivity array）
    cells_block = cells_block_match{1}{1};
    connectivity_pattern = '<DataArray[^>]*Name="connectivity"[^>]*>(.*?)</DataArray>';
    connectivity_match = regexp(cells_block, connectivity_pattern, 'tokens');

    % 提取偏移量数据（offsets array）
    offsets_pattern = '<DataArray[^>]*Name="offsets"[^>]*>(.*?)</DataArray>';
    offsets_match = regexp(cells_block, offsets_pattern, 'tokens');

    if isempty(connectivity_match) || isempty(offsets_match)
        fprintf('警告：文件 %s 中未找到单元连接数据，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end

    connectivity_str = strtrim(connectivity_match{1}{1});
    connectivity = sscanf(connectivity_str, '%d') + 1;  % VTK索引从0开始，MATLAB从1开始

    offsets_str = strtrim(offsets_match{1}{1});
    offsets = sscanf(offsets_str, '%d');

    % 计算单元中心位置
    num_cells = length(offsets);
    cell_centers = zeros(num_cells, 3);

    start_idx = 1;
    for cell_idx = 1:num_cells
        end_idx = offsets(cell_idx);
        cell_node_indices = connectivity(start_idx:end_idx);
        cell_center = mean(node_positions(cell_node_indices, :), 1);
        cell_centers(cell_idx, :) = cell_center;
        start_idx = end_idx + 1;
    end

    % 提取速度数据（<CellData> 中的 Velocity，对应单元中心）
    velocity_pattern = '<DataArray[^>]*Name="Velocity"[^>]*>(.*?)</DataArray>';
    velocity_match = regexp(file_content, velocity_pattern, 'tokens');

    if isempty(velocity_match)
        fprintf('提示：文件 %s 中未找到速度数据，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end

    velocity_str = strtrim(velocity_match{1}{1});
    velocity_data = sscanf(velocity_str, '%f');
    velocities = reshape(velocity_data, 3, [])';  % N_cells × 3 矩阵

    % 验证数据一致性
    if size(cell_centers, 1) ~= size(velocities, 1)
        fprintf('警告：文件 %s 中单元数量和速度数据数量不匹配 (%d vs %d)，跳过\n', ...
                filename, size(cell_centers, 1), size(velocities, 1));
        skipped_count = skipped_count + 1;
        continue;
    end

    % 存储数据（将单元中心作为"粒子"位置）
    valid_count = valid_count + 1;
    flow_data(valid_count).time = current_time;
    flow_data(valid_count).particles.position = cell_centers;
    flow_data(valid_count).particles.velocity = velocities;

    fprintf('✓ 成功处理文件 %s: %d 单元, t = %.3f\n', filename, num_cells, current_time);

    if mod(valid_count, 10) == 0
        fprintf('已处理 %d/%d 个有效文件...\n', valid_count, length(vtu_files));
    end
end

%% 裁剪未使用的结构体
flow_data = flow_data(1:valid_count);

%% 保存结果
save(output_mat_file, 'flow_data', '-v7.3');

fprintf('\n=== 数据预处理完成 ===\n');
fprintf('总文件数：%d\n', length(vtu_files));
fprintf('成功处理：%d\n', valid_count);
fprintf('跳过文件：%d\n', skipped_count);
fprintf('数据已保存到：%s\n', output_mat_file);

if valid_count > 0
    fprintf('\n第一帧数据：\n');
    fprintf('  时间: %.3f s\n', flow_data(1).time);
    fprintf('  单元数: %d\n', size(flow_data(1).particles.position, 1));
    fprintf('  速度范围: [%.3f, %.3f] m/s\n', ...
            min(flow_data(1).particles.velocity(:,1)), ...
            max(flow_data(1).particles.velocity(:,1)));
end

%% 辅助函数：自然排序
function [sorted_list, sorted_index] = sort_nat(unsorted_list)
    % 自然排序函数（确保数字顺序正确）
    [~, sorted_index] = sort(cellfun(@(x) sscanf(x, '%*[^0-9]%d'), ...
                                     unsorted_list, 'UniformOutput', true));
    sorted_list = unsorted_list(sorted_index);
end
