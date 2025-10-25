% preprocess_data.m (Final Corrected Version)
%
% This script reads simulation data from the 'output' directory.
% It correctly extracts the physical time directly from the .vtp filenames.

clear; clc; close all;

% --- Configuration ---
output_dir = 'output';
output_mat_file = 'flow_data.mat';
time_scaling_factor = 1e-6; % As deduced from filenames
% --- End Configuration ---

fprintf('Starting data preprocessing (Filename Time Extraction)...\n');

% --- Step 1: Validate input directory ---
if ~isfolder(output_dir)
    error('Error: The directory "%s" was not found.', output_dir);
end

% --- Step 2: Get and sort file list ---
vtp_files = dir(fullfile(output_dir, '*.vtp'));
if isempty(vtp_files)
    error('Error: No .vtp files found in "%s".', output_dir);
end
[~, sort_idx] = sort_nat({vtp_files.name});
vtp_files = vtp_files(sort_idx);
num_files = length(vtp_files);
fprintf('Found %d .vtp files to process.\n', num_files);

% --- Step 3: Process each file ---
flow_data = struct('time', {}, 'particles', {});
error_files = {};
skipped_files = {};

fprintf('Processing files...\n');
for i = 1:num_files
    file_path = fullfile(output_dir, vtp_files(i).name);
    
    try
        % Extract time from filename
        time_str = regexp(vtp_files(i).name, '.*?_(\d+)\.vtp', 'tokens', 'once');
        if isempty(time_str)
            error('Could not parse time from filename: %s', vtp_files(i).name);
        end
        current_time = str2double(time_str{1}) * time_scaling_factor;
        
        file_content = fileread(file_path);
        points_str = regexp(file_content, '<Points>.*?<DataArray[^>]*>(.*?)</DataArray>.*?</Points>', 'tokens', 'once');
        velocity_str = regexp(file_content, '<PointData.*?<DataArray[^>]*Name="Velocity"[^>]*>(.*?)</DataArray>.*?</PointData>', 'tokens', 'once');
        pressure_str = regexp(file_content, '<PointData.*?<DataArray[^>]*Name="Pressure"[^>]*>(.*?)</DataArray>.*?</PointData>', 'tokens', 'once');
        
        if isempty(velocity_str) || isempty(pressure_str)
            skipped_files{end+1} = vtp_files(i).name;
            continue;
        end
        
        if isempty(points_str)
            error('Could not extract points data from "%s".', vtp_files(i).name);
        end
        
        points = sscanf(points_str{1}, '%f');
        points = reshape(points, 3, [])';
        velocity = sscanf(velocity_str{1}, '%f');
        velocity = reshape(velocity, 3, [])';
        pressure = sscanf(pressure_str{1}, '%f');
        
        if size(points,1) ~= size(velocity,1) || size(points,1) ~= size(pressure,1)
            error('Mismatch in points and data vectors in "%s".', vtp_files(i).name);
        end
        
        % Append data to the struct
        idx = length(flow_data) + 1;
        flow_data(idx).time = current_time;
        flow_data(idx).particles.position = points;
        flow_data(idx).particles.velocity = velocity;
        flow_data(idx).particles.pressure = pressure;
        
    catch ME
        error_files{end+1} = vtp_files(i).name;
        warning(ME.identifier, 'Failed to process file "%s". Error: %s', vtp_files(i).name, ME.message);
        continue;
    end
end

% --- Step 4: Save results and report ---
fprintf('\n--- Preprocessing Report ---\n');
fprintf('Successfully skipped %d files (static geometry).\n', length(skipped_files));
fprintf('Successfully processed %d particle data files.\n', length(flow_data));
if ~isempty(error_files)
    fprintf('Finished with errors. %d files failed:\n', length(error_files));
    cellfun(@(x) fprintf('  - %s\n', x), error_files);
end

fprintf('Saving processed data to "%s"...\n', output_mat_file);
save(output_mat_file, 'flow_data');

fprintf('Preprocessing complete!\n');

% --- Helper function for natural sorting ---
function [cs,index] = sort_nat(c,varargin)
    [~,index] = sort(regexprep(c,'(\d+)','${sprintf(''%020s'',$1)}'));
    cs = c(index);
end