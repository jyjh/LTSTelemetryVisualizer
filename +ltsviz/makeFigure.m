function fig = makeFigure(simRun, realRun, track, comparison, varargin)
%MAKEFIGURE Create a MATLAB diagnostic figure mirroring the HTML report.

parser = inputParser;
parser.addParameter('Visible', false, @(x) islogical(x) || isnumeric(x));
parser.parse(varargin{:});

visible = 'off';
if logical(parser.Results.Visible)
    visible = 'on';
end
fig = figure('Name', 'LTS Correlation Visualization', ...
    'Color', 'w', 'Visible', visible, 'Position', [50 50 1500 950]);
layout = tiledlayout(fig, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile(layout, [2 1]);
legendHandles = gobjects(0);
legendLabels = {};
if track.hasTrack
    h = plot3(track.x, track.y, zeros(size(track.x)), '-', 'Color', [0.65 0.65 0.65], ...
        'LineWidth', 1.0); hold on;
    legendHandles(end+1) = h; %#ok<AGROW>
    legendLabels{end+1} = 'Track'; %#ok<AGROW>
end
h = plot3(simRun.xAligned, simRun.yAligned, zeros(size(simRun.xAligned)), ...
    'b-', 'LineWidth', 1.2); hold on;
legendHandles(end+1) = h; %#ok<AGROW>
legendLabels{end+1} = 'Simulation'; %#ok<AGROW>
if ~isempty(realRun)
    h = plot3(realRun.xAligned, realRun.yAligned, zeros(size(realRun.xAligned)), ...
        'r-', 'LineWidth', 1.2);
    legendHandles(end+1) = h; %#ok<AGROW>
    legendLabels{end+1} = 'Reality'; %#ok<AGROW>
    h = scatter3(comparison.table.sim_x_m, comparison.table.sim_y_m, ...
        comparison.table.path_error_m, 8, comparison.table.path_error_m, 'filled');
    legendHandles(end+1) = h; %#ok<AGROW>
    legendLabels{end+1} = 'Path error'; %#ok<AGROW>
end
axis equal;
grid on;
xlabel('x [m]');
ylabel('y [m]');
zlabel('error [m]');
title('Trajectory Overlay');
legend(legendHandles, legendLabels, 'Location', 'best');
view(35, 35);

axisValues = comparison.axis;
axisLabel = comparison.axisName;
T = comparison.table;

nexttile(layout);
plot(axisValues, T.sim_speed_mps * 3.6, 'b-', 'LineWidth', 1); hold on;
plot(axisValues, T.real_speed_mps * 3.6, 'r-', 'LineWidth', 1);
ylabel('speed [km/h]');
title('Speed');
grid on;

nexttile(layout);
plot(axisValues, T.path_error_m, 'k-', 'LineWidth', 1);
ylabel('path error [m]');
title('Path Separation');
grid on;

nexttile(layout);
plot(axisValues, T.sim_throttle_ratio * 100, 'Color', [0.1 0.55 0.1], 'LineWidth', 1); hold on;
plot(axisValues, T.real_throttle_ratio * 100, '--', 'Color', [0.1 0.55 0.1], 'LineWidth', 1);
plot(axisValues, T.sim_brake_ratio * 100, 'Color', [0.75 0.1 0.1], 'LineWidth', 1);
plot(axisValues, T.real_brake_ratio * 100, '--', 'Color', [0.75 0.1 0.1], 'LineWidth', 1);
ylabel('input [%]');
xlabel(axisLabel, 'Interpreter', 'none');
title('Driver Inputs');
grid on;

nexttile(layout);
plot(axisValues, T.yaw_rate_delta_radps, 'm-', 'LineWidth', 1); hold on;
plot(axisValues, T.lat_accel_delta_g, 'Color', [0.1 0.45 0.8], 'LineWidth', 1);
ylabel('delta');
xlabel(axisLabel, 'Interpreter', 'none');
title('Yaw Rate / Lateral Accel Error');
legend({'yaw rate [rad/s]', 'lat accel [g]'}, 'Location', 'best');
grid on;
end
