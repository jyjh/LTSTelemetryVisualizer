function comparison = buildComparison(simRun, realRun, varargin)
%BUILDCOMPARISON Interpolate sim and real telemetry onto a common axis.

parser = inputParser;
parser.addParameter('AlignmentMode', 'time', @(x) ischar(x) || isstring(x));
parser.parse(varargin{:});
mode = lower(string(parser.Results.AlignmentMode));
if mode ~= "time" && mode ~= "distance"
    error('ltsviz:InvalidAlignmentMode', 'AlignmentMode must be "time" or "distance".');
end

axisName = 'time_s';
simAxis = simRun.time(:);
realAxis = [];
if mode == "distance"
    axisName = 'distance_m';
    simAxis = simRun.distance(:);
end
if ~isempty(realRun)
    realAxis = realRun.time(:);
    if mode == "distance"
        realAxis = realRun.distance(:);
    end
end

axis = finiteUnique(simAxis);
if ~isempty(realAxis)
    realFinite = finiteUnique(realAxis);
    if ~isempty(realFinite)
        lo = max(min(axis), min(realFinite));
        hi = min(max(axis), max(realFinite));
        axis = axis(axis >= lo & axis <= hi);
    end
end
if isempty(axis)
    error('ltsviz:NoOverlap', 'No overlapping samples are available for comparison.');
end

T = table(axis, 'VariableNames', {axisName});
T.sim_x_m = interpFinite(simAxis, simRun.xAligned, axis);
T.sim_y_m = interpFinite(simAxis, simRun.yAligned, axis);
T.sim_speed_mps = interpFinite(simAxis, simRun.speed, axis);
T.sim_steer_rad = interpFinite(simAxis, simRun.steer, axis);
T.sim_throttle_ratio = interpFinite(simAxis, simRun.throttle, axis);
T.sim_brake_ratio = interpFinite(simAxis, simRun.brake, axis);
T.sim_yaw_rate_radps = interpFinite(simAxis, simRun.yawRate, axis);
T.sim_lat_accel_g = interpFinite(simAxis, simRun.latAccelG, axis);
T.sim_long_accel_g = interpFinite(simAxis, simRun.longAccelG, axis);

if ~isempty(realRun)
    T.real_x_m = interpFinite(realAxis, realRun.xAligned, axis);
    T.real_y_m = interpFinite(realAxis, realRun.yAligned, axis);
    T.real_speed_mps = interpFinite(realAxis, realRun.speed, axis);
    T.real_steer_rad = interpFinite(realAxis, realRun.steer, axis);
    T.real_throttle_ratio = interpFinite(realAxis, realRun.throttle, axis);
    T.real_brake_ratio = interpFinite(realAxis, realRun.brake, axis);
    T.real_yaw_rate_radps = interpFinite(realAxis, realRun.yawRate, axis);
    T.real_lat_accel_g = interpFinite(realAxis, realRun.latAccelG, axis);
    T.real_long_accel_g = interpFinite(realAxis, realRun.longAccelG, axis);
else
    T.real_x_m = NaN(size(axis));
    T.real_y_m = NaN(size(axis));
    T.real_speed_mps = NaN(size(axis));
    T.real_steer_rad = NaN(size(axis));
    T.real_throttle_ratio = NaN(size(axis));
    T.real_brake_ratio = NaN(size(axis));
    T.real_yaw_rate_radps = NaN(size(axis));
    T.real_lat_accel_g = NaN(size(axis));
    T.real_long_accel_g = NaN(size(axis));
end

T.path_error_m = hypot(T.sim_x_m - T.real_x_m, T.sim_y_m - T.real_y_m);
T.speed_delta_mps = T.sim_speed_mps - T.real_speed_mps;
T.steer_delta_rad = T.sim_steer_rad - T.real_steer_rad;
T.throttle_delta_ratio = T.sim_throttle_ratio - T.real_throttle_ratio;
T.brake_delta_ratio = T.sim_brake_ratio - T.real_brake_ratio;
T.yaw_rate_delta_radps = T.sim_yaw_rate_radps - T.real_yaw_rate_radps;
T.lat_accel_delta_g = T.sim_lat_accel_g - T.real_lat_accel_g;
T.long_accel_delta_g = T.sim_long_accel_g - T.real_long_accel_g;

comparison = struct('mode', char(mode), 'axisName', axisName, 'axis', axis, 'table', T);
end

function values = finiteUnique(values)
values = double(values(:));
values = values(isfinite(values));
values = unique(values, 'stable');
values = sort(values);
end

function out = interpFinite(axis, values, query)
axis = double(axis(:));
values = double(values(:));
query = double(query(:));
keep = isfinite(axis) & isfinite(values);
axis = axis(keep);
values = values(keep);
if isempty(axis)
    out = NaN(size(query));
elseif numel(axis) == 1
    out = repmat(values(1), size(query));
else
    [axis, idx] = unique(axis, 'stable');
    values = values(idx);
    [axis, order] = sort(axis);
    values = values(order);
    q = max(axis(1), min(axis(end), query));
    out = interp1(axis, values, q, 'linear');
end
end
