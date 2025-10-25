%% preprocess_data.m - 3D channel flow case
% -------------------------------------------------------------------------
% 1. Read particle VTP snapshots from output/ChannelFluid_*.vtp
% 2. Load observer records (centerline / wall-normal / spanwise)
% 3. Synchronise timelines, build reference profiles, export flow_data.mat
% -------------------------------------------------------------------------

clc; clear; close all;

%% Configuration (keep aligned with test_3d_channel_flow.cpp)
output_dir = 'output';
resolution_ref = 0.05;
DL = 10.0;
DH = 2.0;
DW = 1.0;
rho0_f = 1.0;
flow_direction_initial = 1.0;
flow_direction_body = -1.0;
U_bulk = 1.0; % magnitude
U_bulk_signed = flow_direction_body * U_bulk;
U_max = 1.5 * U_bulk_signed;

num_centerline_pts = 41;
num_wall_normal_pts = 51;
num_spanwise_pts = 21;

%% STEP 1 : Collect VTP files
vtp_files = dir(fullfile(output_dir, 'ChannelFluid_*.vtp'));
if isempty(vtp_files)
    error('No ChannelFluid_*.vtp files found under %s.', output_dir);
end

[~, order] = sort_nat({vtp_files.name});
vtp_files = vtp_files(order); %#ok<*NASGU>
num_vtp = numel(vtp_files);

flow_template = struct('time', NaN, 'position', [], 'velocity', []);
flow_data = repmat(flow_template, num_vtp, 1);

valid_frames = 0;
for i = 1:num_vtp
    filename = vtp_files(i).name;
    filepath = fullfile(output_dir, filename);
    try
        vtp_struct = readstruct(filepath, FileType="xml");
    catch ME
        warning('Skipping %s (%s)', filename, ME.message);
        continue;
    end
    piece = vtp_struct.PolyData.Piece;

    % Points
    points_array = piece.Points.DataArray;
    if iscell(points_array)
        points_array = [points_array{:}];
    end
    points_raw = sscanf(strtrim(points_array(1).Text), '%f');
    points = reshape(points_raw, 3, []).';

    % Velocity
    point_data = piece.PointData.DataArray;
    if iscell(point_data)
        point_data = [point_data{:}];
    end
    names = string({point_data.NameAttribute});
    idx = find(names == "Velocity", 1);
    if isempty(idx)
        warning('File %s has no "Velocity" DataArray, skipped.', filename);
        continue;
    end
    velocity_raw = sscanf(strtrim(point_data(idx).Text), '%f');
    velocities = reshape(velocity_raw, 3, []).';

    if size(points, 1) ~= size(velocities, 1)
        warning('Point/velocity size mismatch in %s, skipped.', filename);
        continue;
    end

    valid_frames = valid_frames + 1;
    flow_data(valid_frames).position = points;
    flow_data(valid_frames).velocity = velocities;
    % time filled after observer loading

    if mod(valid_frames, 20) == 0
        fprintf('  processed %d valid VTP files\n', valid_frames);
    end
end

if valid_frames == 0
    error('No valid VTP snapshots could be parsed.');
end

if valid_frames < num_vtp
    flow_data = flow_data(1:valid_frames);
    fprintf('Parsed %d/%d VTP snapshots successfully.\n', valid_frames, num_vtp);
else
    fprintf('Parsed all %d VTP snapshots successfully.\n', valid_frames);
end

%% STEP 2 : Load observer records
centerline_file = fullfile(output_dir, 'CenterlineObserver_Velocity.dat');
wall_file = fullfile(output_dir, 'WallNormalObserver_Velocity.dat');
span_file = fullfile(output_dir, 'SpanwiseObserver_Velocity.dat');

observer.centerline = load_observer(centerline_file, num_centerline_pts);
observer.wall_normal = load_observer(wall_file, num_wall_normal_pts);
observer.spanwise = load_observer(span_file, num_spanwise_pts);

% observation coordinates (matching C++)
margin = 4.0 * resolution_ref;

center_positions = zeros(num_centerline_pts, 3);
center_positions(:, 1) = linspace(margin, DL - margin, num_centerline_pts);
center_positions(:, 2) = 0.5 * DH;
observer.centerline.positions = center_positions;

wall_positions = zeros(num_wall_normal_pts, 3);
wall_positions(:, 1) = 0.5 * DL;
wall_positions(:, 2) = linspace(margin, DH - margin, num_wall_normal_pts);
observer.wall_normal.positions = wall_positions;

span_positions = zeros(num_spanwise_pts, 3);
span_positions(:, 1) = 0.5 * DL;
span_positions(:, 2) = 0.5 * DH;
span_positions(:, 3) = linspace(-0.5 * DW + margin, 0.5 * DW - margin, num_spanwise_pts);
observer.spanwise.positions = span_positions;

%% STEP 3 : Synchronise timelines
wall_times = observer.wall_normal.time;
center_times = observer.centerline.time;

frames = min([valid_frames, numel(wall_times), numel(center_times)]);
if frames == 0
    error('Observer time series empty.');
end
if frames < valid_frames
    warning('Truncating valid frames from %d to %d to match observer sampling.', ...
        valid_frames, frames);
    flow_data = flow_data(1:frames);
end

for i = 1:frames
    flow_data(i).time = wall_times(i);
end

observer.wall_normal.time = wall_times(1:frames);
observer.wall_normal.velocity = observer.wall_normal.velocity(1:frames, :, :);

observer.centerline.time = center_times(1:frames);
observer.centerline.velocity = observer.centerline.velocity(1:frames, :, :);

if size(observer.spanwise.velocity, 1) >= frames
    observer.spanwise.velocity = observer.spanwise.velocity(1:frames, :, :);
else
    warning('Spanwise observer has fewer frames (%d) than %d, keeping original.', ...
        size(observer.spanwise.velocity, 1), frames);
end

%% STEP 4 : Build theoretical reference & metrics
y_coords = observer.wall_normal.positions(:, 2);
y_hat = 2 * y_coords / DH - 1;
u_theory = U_max * (1 - y_hat .^ 2);

final_idx = size(observer.wall_normal.velocity, 1);
u_sim_final = squeeze(observer.wall_normal.velocity(final_idx, :, 1)).';
rms_error = sqrt(mean((u_sim_final - u_theory) .^ 2));

analysis = struct();
analysis.wall_normal_profile = table(y_coords, u_sim_final, u_theory, ...
    'VariableNames', {'y', 'u_sim', 'u_theory'});
analysis.final_time = observer.wall_normal.time(final_idx);
analysis.rms_error = rms_error;

center_mid_idx = ceil(num_centerline_pts / 2);
analysis.centerline_history = table(observer.centerline.time, ...
    squeeze(observer.centerline.velocity(:, center_mid_idx, 1)), ...
    'VariableNames', {'time', 'u_mid'});

fprintf('Final RMS error (wall-normal profile): %.4f\n', rms_error);

%% STEP 5 : Persist MAT file
config = struct('DL', DL, 'DH', DH, 'DW', DW, ...
                'rho0_f', rho0_f, ...
                'flow_direction_initial', flow_direction_initial, ...
                'flow_direction_body', flow_direction_body, ...
                'U_bulk', U_bulk, ...
                'U_bulk_signed', U_bulk_signed, ...
                'U_max', U_max, ...
                'resolution_ref', resolution_ref, 'margin', margin);

save('flow_data.mat', 'flow_data', 'observer', 'analysis', 'config', '-v7.3');
fprintf('Saved flow_data.mat (%s).\n', fullfile(pwd, 'flow_data.mat'));

%% ------------------------------------------------------------------------
function obs = load_observer(filepath, num_points)
    if ~isfile(filepath)
        error('Observer file not found: %s', filepath);
    end
    raw = readmatrix(filepath, 'FileType', 'text');
    if isempty(raw)
        error('Observer file %s is empty.', filepath);
    end
    time = raw(:, 1);
    data = raw(:, 2:end);
    expected_cols = num_points * 3;
    if size(data, 2) ~= expected_cols
        error('Observer file %s column count (%d) != expected (%d).', ...
            filepath, size(data, 2), expected_cols);
    end
    reshaped = permute(reshape(data.', 3, num_points, []), [3, 2, 1]);
    obs = struct();
    obs.time = time;
    obs.velocity = reshaped;
end

function [sorted_list, order] = sort_nat(list_in)
    numeric_tokens = zeros(size(list_in));
    for k = 1:numel(list_in)
        token = regexp(list_in{k}, '\d+', 'match', 'once');
        if isempty(token)
            numeric_tokens(k) = inf;
        else
            numeric_tokens(k) = str2double(token);
        end
    end
    [~, order] = sort(numeric_tokens);
    sorted_list = list_in(order);
end
