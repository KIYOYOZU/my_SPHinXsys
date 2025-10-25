%% preprocess_data.m - FVM 版本
% 功能：从 output/*.vtu 文件中提取时间、单元中心位置、速度数据
% 注意：FVM 数据存储在 CellData 中，需要计算单元中心

clc; clear; close all;

%% 配置参数
output_dir = 'output';
output_mat_file = 'flow_data.mat';
time_scale_factor = 1.0;  % 时间缩放因子

%% 扫描并排序 .vtu 文件
vtu_files = dir(fullfile(output_dir, '*.vtu'));

% 自然排序
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

    % 提取时间
    tokens = regexp(filename, '_(\d+)\.vtu', 'tokens');
    if isempty(tokens)
        fprintf('警告：无法从文件名 %s 中提取时间，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end
    time_step = str2double(tokens{1}{1});
    current_time = time_step * time_scale_factor;

    % 读取文件
    try
        file_content = fileread(filepath);
    catch
        fprintf('警告：无法读取文件 %s，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end

    % 提取 NumberOfPoints 和 NumberOfCells
    piece_pattern = '<Piece\s+NumberOfPoints="(\d+)"\s+NumberOfCells="(\d+)"';
    piece_match = regexp(file_content, piece_pattern, 'tokens');
    if isempty(piece_match)
        fprintf('警告：无法提取文件 %s 的网格信息，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end
    num_points = str2double(piece_match{1}{1});
    num_cells = str2double(piece_match{1}{2});

    % 提取顶点坐标
    points_pattern = '<Points>.*?<DataArray[^>]*>(.*?)</DataArray>.*?</Points>';
    points_match = regexp(file_content, points_pattern, 'tokens');
    if isempty(points_match)
        fprintf('警告：文件 %s 中未找到Points数据，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end
    points_str = strtrim(points_match{1}{1});
    points_data = sscanf(points_str, '%f');
    points = reshape(points_data, 3, [])';  % N×3

    % 提取 Cells 的连接性
    cells_pattern = '<Cells>.*?<DataArray[^>]*Name="connectivity"[^>]*>(.*?)</DataArray>';
    cells_match = regexp(file_content, cells_pattern, 'tokens');
    if isempty(cells_match)
        fprintf('警告：文件 %s 中未找到Cells连接性，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end
    connectivity_str = strtrim(cells_match{1}{1});
    connectivity = sscanf(connectivity_str, '%d') + 1;  % MATLAB索引从1开始

    % 提取 offsets（每个单元的顶点结束位置）
    offsets_pattern = '<DataArray[^>]*Name="offsets"[^>]*>(.*?)</DataArray>';
    offsets_match = regexp(file_content, offsets_pattern, 'tokens');
    if isempty(offsets_match)
        fprintf('警告：文件 %s 中未找到offsets，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end
    offsets_str = strtrim(offsets_match{1}{1});
    offsets = sscanf(offsets_str, '%d');

    % 计算每个单元的中心
    cell_centers = zeros(num_cells, 3);
    start_idx = 1;
    for c = 1:num_cells
        end_idx = offsets(c);
        cell_vertex_indices = connectivity(start_idx:end_idx);
        cell_vertices = points(cell_vertex_indices, :);
        cell_centers(c, :) = mean(cell_vertices, 1);
        start_idx = end_idx + 1;
    end

    % 提取速度数据（CellData）
    velocity_pattern = '<CellData>.*?<DataArray[^>]*Name="Velocity"[^>]*>(.*?)</DataArray>';
    velocity_match = regexp(file_content, velocity_pattern, 'tokens');
    if isempty(velocity_match)
        fprintf('提示：文件 %s 中未找到速度数据，跳过\n', filename);
        skipped_count = skipped_count + 1;
        continue;
    end
    velocity_str = strtrim(velocity_match{1}{1});
    velocity_data = sscanf(velocity_str, '%f');
    velocities = reshape(velocity_data, 3, [])';  % N×3

    % 验证数据一致性
    if size(cell_centers, 1) ~= size(velocities, 1)
        fprintf('警告：文件 %s 中单元数和速度数据数量不匹配（%d vs %d），跳过\n', ...
                filename, size(cell_centers, 1), size(velocities, 1));
        skipped_count = skipped_count + 1;
        continue;
    end

    % 存储数据
    valid_count = valid_count + 1;
    flow_data(valid_count).time = current_time;
    flow_data(valid_count).particles.position = cell_centers;  % 使用单元中心
    flow_data(valid_count).particles.velocity = velocities;

    if mod(valid_count, 2) == 0
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

%% 辅助函数：自然排序
function [sorted_list, sorted_index] = sort_nat(unsorted_list)
    [~, sorted_index] = sort(cellfun(@(x) sscanf(x, '%*[^0-9]%d'), ...
                                     unsorted_list, 'UniformOutput', true));
    sorted_list = unsorted_list(sorted_index);
end
