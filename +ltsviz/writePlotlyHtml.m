function writePlotlyHtml(outputHtml, simRun, realRun, track, comparison, summary)
%WRITEPLOTLYHTML Write a Plotly-powered standalone diagnostic report.

outputHtml = char(outputHtml);
outputDir = fileparts(outputHtml);
if ~isempty(outputDir) && ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

T = downsampleTable(comparison.table, 5000);
axisValues = T.(comparison.axisName);

pathData = buildPathData(T, simRun, realRun, track);
speedData = buildSpeedData(T, axisValues);
inputData = buildInputData(T, axisValues);
dynamicsData = buildDynamicsData(T, axisValues);

pathLayout = struct('title', 'Trajectory Overlay', ...
    'scene', struct('xaxis', struct('title', 'x [m]'), ...
                    'yaxis', struct('title', 'y [m]'), ...
                    'zaxis', struct('title', 'error [m]'), ...
                    'aspectmode', 'data'), ...
    'legend', struct('orientation', 'h'));
speedLayout = xyLayout('Speed', comparison.axisName, 'speed [km/h]');
inputLayout = xyLayout('Driver Inputs', comparison.axisName, 'input [%]');
dynamicsLayout = xyLayout('Dynamics Error', comparison.axisName, 'delta');

plotlyScript = plotlyScriptTag();
metricsHtml = metricsTable(summary);
warningsHtml = warningsList(summary);

html = sprintf(['<!doctype html>\n<html>\n<head>\n<meta charset="utf-8">\n' ...
    '<meta name="viewport" content="width=device-width, initial-scale=1">\n' ...
    '<title>LTS Correlation Visualization</title>\n%s\n' ...
    '<style>body{font-family:Arial,sans-serif;margin:24px;background:#f8f9fb;color:#1f2933}' ...
    '.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}' ...
    '.plot{background:white;border:1px solid #d9dee7;border-radius:6px;padding:8px}' ...
    '#path{height:680px}.half{height:360px}table{border-collapse:collapse;background:white}' ...
    'td,th{border:1px solid #d9dee7;padding:6px 8px;text-align:right}' ...
    'th:first-child,td:first-child{text-align:left}code{background:#edf1f7;padding:2px 4px}</style>\n' ...
    '</head>\n<body>\n<h1>LTS Correlation Visualization</h1>\n' ...
    '<p><strong>Simulation:</strong> <code>%s</code><br><strong>Reality:</strong> <code>%s</code></p>\n' ...
    '%s%s<div id="path" class="plot"></div>\n<div class="grid">\n' ...
    '<div id="speed" class="plot half"></div><div id="inputs" class="plot half"></div>\n' ...
    '<div id="dynamics" class="plot half"></div></div>\n<script>\n' ...
    'Plotly.newPlot("path", %s, %s, {responsive:true});\n' ...
    'Plotly.newPlot("speed", %s, %s, {responsive:true});\n' ...
    'Plotly.newPlot("inputs", %s, %s, {responsive:true});\n' ...
    'Plotly.newPlot("dynamics", %s, %s, {responsive:true});\n' ...
    '</script>\n</body>\n</html>\n'], ...
    plotlyScript, escapeHtml(summary.sim_file), escapeHtml(summary.real_file), ...
    metricsHtml, warningsHtml, ...
    jsonencode(pathData), jsonencode(pathLayout), ...
    jsonencode(speedData), jsonencode(speedLayout), ...
    jsonencode(inputData), jsonencode(inputLayout), ...
    jsonencode(dynamicsData), jsonencode(dynamicsLayout));

fid = fopen(outputHtml, 'w');
if fid < 0
    error('ltsviz:HtmlOpenFailed', 'Could not write %s.', outputHtml);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', html);
end

function data = buildPathData(T, simRun, realRun, track)
data = {};
if track.hasTrack
    data{end+1} = line3('Track', track.x, track.y, zeros(size(track.x)), ...
        'rgb(150,150,150)', 2); %#ok<AGROW>
end
data{end+1} = line3(simRun.label, simRun.xAligned, simRun.yAligned, ...
    zeros(size(simRun.xAligned)), 'rgb(31,119,180)', 3); %#ok<AGROW>
if ~isempty(realRun)
    data{end+1} = line3(realRun.label, realRun.xAligned, realRun.yAligned, ...
        zeros(size(realRun.xAligned)), 'rgb(214,39,40)', 3); %#ok<AGROW>
    marker = struct('size', 3, 'color', T.path_error_m, 'colorscale', 'Viridis', ...
        'showscale', true, 'colorbar', struct('title', 'path error [m]'));
    data{end+1} = struct('type', 'scatter3d', 'mode', 'markers', ...
        'name', 'Path error', 'x', T.sim_x_m, 'y', T.sim_y_m, ...
        'z', T.path_error_m, 'marker', marker); %#ok<AGROW>
end
end

function trace = line3(name, x, y, z, color, width)
trace = struct('type', 'scatter3d', 'mode', 'lines', 'name', name, ...
    'x', x(:), 'y', y(:), 'z', z(:), ...
    'line', struct('color', color, 'width', width));
end

function data = buildSpeedData(T, axisValues)
data = [ ...
    line2('Sim speed', axisValues, T.sim_speed_mps * 3.6, 'rgb(31,119,180)'), ...
    line2('Real speed', axisValues, T.real_speed_mps * 3.6, 'rgb(214,39,40)'), ...
    line2('Delta', axisValues, T.speed_delta_mps * 3.6, 'rgb(80,80,80)')];
end

function data = buildInputData(T, axisValues)
data = [ ...
    line2('Sim throttle', axisValues, T.sim_throttle_ratio * 100, 'rgb(44,160,44)'), ...
    line2('Real throttle', axisValues, T.real_throttle_ratio * 100, 'rgb(120,200,120)'), ...
    line2('Sim brake', axisValues, T.sim_brake_ratio * 100, 'rgb(214,39,40)'), ...
    line2('Real brake', axisValues, T.real_brake_ratio * 100, 'rgb(255,140,140)')];
end

function data = buildDynamicsData(T, axisValues)
data = [ ...
    line2('Yaw rate delta [rad/s]', axisValues, T.yaw_rate_delta_radps, 'rgb(148,103,189)'), ...
    line2('Lat accel delta [g]', axisValues, T.lat_accel_delta_g, 'rgb(23,190,207)'), ...
    line2('Path error [m]', axisValues, T.path_error_m, 'rgb(80,80,80)')];
end

function trace = line2(name, x, y, color)
trace = struct('type', 'scatter', 'mode', 'lines', 'name', name, ...
    'x', x(:), 'y', y(:), 'line', struct('color', color, 'width', 2));
end

function layout = xyLayout(titleText, xTitle, yTitle)
layout = struct('title', titleText, ...
    'xaxis', struct('title', xTitle), ...
    'yaxis', struct('title', yTitle), ...
    'legend', struct('orientation', 'h'));
end

function tag = plotlyScriptTag()
root = fileparts(fileparts(mfilename('fullpath')));
matches = dir(fullfile(root, 'external', 'plotly_matlab', '**', 'plotly*.min.js'));
if ~isempty(matches)
    jsPath = fullfile(matches(1).folder, matches(1).name);
    js = fileread(jsPath);
    tag = sprintf('<script>%s</script>', js);
    return;
end

bundlePath = fullfile(userHome(), '.plotly', 'plotlyjs', ...
    'plotly-matlab-offline-bundle.js');
if exist(bundlePath, 'file')
    js = fileread(bundlePath);
    tag = sprintf('<script>%s</script>', js);
else
    tag = ['<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>' ...
        '<!-- Local Plotly bundle not found; using CDN fallback. -->'];
end
end

function path = userHome()
path = getenv('USERPROFILE');
if isempty(path)
    path = getenv('HOME');
end
end

function html = metricsTable(summary)
m = summary.metrics;
rows = { ...
    'Mean path error [m]', m.path_error_mean_m; ...
    'Max path error [m]', m.path_error_max_m; ...
    'Mean speed delta [m/s]', m.speed_delta_mean_mps; ...
    'Max abs speed delta [m/s]', m.speed_delta_max_abs_mps; ...
    'Max abs yaw-rate delta [rad/s]', m.yaw_rate_delta_max_abs_radps; ...
    'Max abs lateral-accel delta [g]', m.lat_accel_delta_max_abs_g};
parts = {'<h2>Summary Metrics</h2><table><tr><th>Metric</th><th>Value</th></tr>'};
for i = 1:size(rows, 1)
    parts{end+1} = sprintf('<tr><td>%s</td><td>%.4g</td></tr>', rows{i,1}, rows{i,2}); %#ok<AGROW>
end
parts{end+1} = '</table>';
html = strjoin(parts, newline);
end

function html = warningsList(summary)
if ~isfield(summary, 'warnings') || isempty(summary.warnings)
    html = '';
    return;
end
parts = {'<h2>Warnings</h2><ul>'};
for i = 1:numel(summary.warnings)
    parts{end+1} = sprintf('<li>%s</li>', escapeHtml(summary.warnings{i})); %#ok<AGROW>
end
parts{end+1} = '</ul>';
html = strjoin(parts, newline);
end

function value = escapeHtml(value)
value = char(value);
value = strrep(value, '&', '&amp;');
value = strrep(value, '<', '&lt;');
value = strrep(value, '>', '&gt;');
value = strrep(value, '"', '&quot;');
end

function T = downsampleTable(T, maxSamples)
if height(T) <= maxSamples
    return;
end
idx = unique(round(linspace(1, height(T), maxSamples)));
T = T(idx, :);
end
