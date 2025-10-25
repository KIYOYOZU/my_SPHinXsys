function visualize_vtp_files()
    % Add the path to the vtk-matlab library
    addpath('path/to/vtk-matlab');

    % Get a list of all .vtp files in the output directory
    output_dir = '../../../output';
    vtp_files = dir(fullfile(output_dir, 'SPH_Body_*.vtp'));

    % Create a figure
    figure;

    % Loop through each .vtp file
    for i = 1:length(vtp_files)
        % Read the .vtp file
        vtp_file = fullfile(output_dir, vtp_files(i).name);
        [points, ~, ~] = vtk_polydata_read(vtp_file);

        % Clear the figure
        clf;

        % Plot the points
        scatter(points(:,1), points(:,2), 10, 'filled');

        % Set the axis limits
        axis equal;
        xlim([-0.5, 1.5]);
        ylim([-0.5, 0.5]);

        % Set the title
        title(strrep(vtp_files(i).name, '_', ' '));

        % Pause for a short time
        pause(0.1);
    end
end