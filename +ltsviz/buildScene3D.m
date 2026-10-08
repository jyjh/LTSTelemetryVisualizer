function scene = buildScene3D(simRun, realRun, track, comparison, summary, varargin)
%BUILDSCENE3D Build the JSON-ready payload for the standalone 3D replay.
%
%   scene = ltsviz.buildScene3D(simRun, realRun, track, comparison, summary)
%   scene = ltsviz.buildScene3D(..., 'MaxPoints', 4000)
%
% The payload is consumed by ltsviz.write3DHtml. Positions come from the
% aligned comparison table so the simulation and reality cars replay on a
% shared clock. Headings are derived from the path tangent (frame-safe even
% after alignRuns rotates the real trajectory), and body roll/pitch are
% estimated from the accelerometer channels with small, capped gains.
%
% Name-value options:
%   MaxPoints  Maximum replay samples kept in the payload (default 4000).

parser = inputParser;
parser.FunctionName = 'ltsviz.buildScene3D';
parser.addParameter('MaxPoints', 4000, ...
    @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 2));
parser.parse(varargin{:});
maxPoints = parser.Results.MaxPoints;
if isempty(maxPoints)
    maxPoints = 4000;
end

T = comparison.table;
T = downsampleTable(T, maxPoints);
axis = double(T.(comparison.axisName));

if ~any(isfinite(T.sim_x_m)) || ~any(isfinite(T.sim_y_m))
    error('ltsviz:NoPositionChannels', ...
        ['The simulation run has no x/y (or GPS) channels, so a 3D replay ' ...
         'cannot be rendered.']);
end

hasReal = ~isempty(realRun) && any(isfinite(T.real_x_m)) && ...
    any(isfinite(T.real_y_m));

scene = struct();
scene.meta = buildMeta(simRun, realRun, track, comparison, summary, ...
    height(T), hasReal);
scene.track = buildTrackPayload(track, T, maxPoints);
scene.sim = buildRunPayload(T, 'sim', axis, comparison.axisName);
if hasReal
    scene.real = buildRunPayload(T, 'real', axis, comparison.axisName);
else
    scene.real = [];
end
end

function meta = buildMeta(simRun, realRun, track, comparison, summary, samples, hasReal)
meta = struct();
if hasReal
    meta.title = 'Simulation vs Reality — 3D Replay';
else
    meta.title = 'Simulation 3D Replay';
end
meta.createdAt = datestr(now, 31);
meta.simFile = char(simRun.path);
meta.simLabel = char(simRun.label);
meta.realFile = '';
meta.realLabel = '';
if hasReal
    meta.realFile = char(realRun.path);
    meta.realLabel = char(realRun.label);
end
meta.hasReal = hasReal;
meta.axisName = char(comparison.axisName);
if strcmp(meta.axisName, 'distance_m')
    meta.axisUnit = 'm';
else
    meta.axisUnit = 's';
end
axis = comparison.axis;
meta.duration = round((axis(end) - axis(1)) * 1000) / 1000;
meta.samples = samples;
meta.attitudeEstimated = true;
if isfield(summary, 'warnings')
    meta.warnings = summary.warnings;
else
    meta.warnings = {};
end
if isfield(summary, 'metrics')
    meta.metrics = summary.metrics;
else
    meta.metrics = struct();
end
meta.trackLabel = char(track.label);
end

function trackPayload = buildTrackPayload(track, T, maxPoints)
trackPayload = struct('hasTrack', false, 'x', [], 'y', [], 's', [], ...
    'width', 3, 'left', [], 'right', [], 'closed', false);
if track.hasTrack && numel(track.x) > 1
    x = double(track.x(:));
    y = double(track.y(:));
    s = [];
    if ~isempty(track.s) && numel(track.s) == numel(x)
        s = double(track.s(:));
    end
    left = halfWidths(track.leftWidth, x, track.width);
    right = halfWidths(track.rightWidth, x, track.width);
    closed = track.closed;
    idx = downsampleIndex(numel(x), min(maxPoints, 2000));
    trackPayload.x = round3(x(idx));
    trackPayload.y = round3(y(idx));
    if ~isempty(s)
        trackPayload.s = round3(s(idx));
    end
    trackPayload.left = round3(left(idx));
    trackPayload.right = round3(right(idx));
    width = track.width;
    if ~isscalar(width) || ~isfinite(width)
        width = mean([left(idx), right(idx)], 'all');
    end
    trackPayload.width = round3(width);
    trackPayload.closed = closed;
    trackPayload.hasTrack = true;
    return;
end
% No reference track: the viewer derives a ribbon from the sim trajectory.
trackPayload.width = 3;
trackPayload.x = round3(double(T.sim_x_m(:)));
trackPayload.y = round3(double(T.sim_y_m(:)));
end

function runPayload = buildRunPayload(T, prefix, axis, axisName)
v = T.([prefix '_speed_mps']);
th = T.([prefix '_throttle_ratio']);
br = T.([prefix '_brake_ratio']);
st = T.([prefix '_steer_rad']);
la = T.([prefix '_lat_accel_g']);
lo = T.([prefix '_long_accel_g']);
x = fillFinite(double(T.([prefix '_x_m'])));
y = fillFinite(double(T.([prefix '_y_m'])));

% Render-only smoothing: real logs carry GPS and sensor noise that the
% per-sample derivative channels (yaw, body attitude, steering display)
% would otherwise amplify into visible jitter. Positions, trails, and the
% raw channels below stay untouched — only derived render quantities are
% smoothed, over a fixed ~0.15 s window.
w = renderWindow(axis);

runPayload = struct();
runPayload.t = round3(axis);
runPayload.x = round3(x);
runPayload.y = round3(y);
runPayload.h = round4(unwrap(renderHeading(x, y, w)));
runPayload.v = round2(fillFinite(double(v), 0) * 3.6);
runPayload.th = round3(clamp01(fillFinite(double(th), 0)));
runPayload.br = round3(clamp01(fillFinite(double(br), 0)));
runPayload.st = round4(smoothRender(fillFinite(double(st), 0), w));
runPayload.la = round3(smoothRender(fillFinite(double(la), 0), w));
runPayload.lo = round3(smoothRender(fillFinite(double(lo), 0), w));
runPayload.roll = rollFromLateral(runPayload.la);
runPayload.pitch = pitchFromLongitudinal(runPayload.lo);
end

function w = renderWindow(axis)
% Odd sample window closest to 0.15 s for the payload's sample rate.
dt = median(diff(double(axis)));
if ~isfinite(dt) || dt <= 0
    dt = 0.01;
end
w = min(numel(axis), max(3, 2 * round(0.15 / dt / 2) + 1));
if w < 3
    w = 0; % signal smoothing off for degenerately short runs
end
end

function out = smoothRender(values, w)
if w < 3 || numel(values) < w
    out = values;
else
    out = smoothdata(values, 'movmean', w);
end
end

function h = renderHeading(x, y, w)
% Yaw for the car mesh: the path tangent over a fixed ~0.5 m lever of
% arc length on the lightly smoothed path. A space lever keeps GPS noise
% equally suppressed at every speed, and the heading holds (instead of
% spinning) wherever that lever of travel does not exist yet — standstill
% and the very start/end of the log.
if w < 3 || numel(x) < w
    xs = x;
    ys = y;
else
    xs = smoothdata(x, 'movmean', w);
    ys = smoothdata(y, 'movmean', w);
end
n = numel(xs);
h = nan(n, 1);
if n < 2
    return;
end
s = [0; cumsum(hypot(diff(xs), diff(ys)))]; % arc length (monotone)
half = 0.25; % [m] half of the heading lever
j = 1;
k = 1;
for i = 1:n
    while s(i) - s(j) > half
        j = j + 1;
    end
    while k < n && s(k) - s(i) < half
        k = k + 1;
    end
    if s(i) >= half && (k < n || s(k) - s(j) >= 2 * half)
        h(i) = atan2(ys(k) - ys(j), xs(k) - xs(j));
    elseif i > 1
        h(i) = h(i - 1);
    end
end
if all(isnan(h))
    h(:) = atan2(ys(n) - ys(1), xs(n) - xs(1));
end
first = find(~isnan(h), 1, 'first');
if ~isempty(first) && first > 1
    h(1:first - 1) = h(first); % pre-launch samples face the launch direction
end
end

function roll = rollFromLateral(la)
% Lean out of the turn: positive lateral g (turn center to the car's left)
% rolls the body to its right, away from the turn center.
gain = deg2rad(3);
limit = deg2rad(8);
roll = clampFinite(la * gain, -limit, limit);
roll = round4(roll);
end

function pitch = pitchFromLongitudinal(lo)
% Positive longitudinal g (accelerating) lifts the nose slightly;
% braking dips it.
gain = deg2rad(1.5);
limit = deg2rad(4);
pitch = clampFinite(lo * gain, -limit, limit);
pitch = round4(pitch);
end

function out = clamp01(values)
out = min(max(values, 0), 1);
out(~isfinite(out)) = 0;
end

function out = clampFinite(values, lo, hi)
out = min(max(values, lo), hi);
out(~isfinite(values)) = 0;
end

function values = fillFinite(values, replacement)
% Replace non-finite samples: interior/trailing holes hold the last finite
% value, leading holes take the first finite one, and fully empty channels
% fall back to the replacement scalar.
if nargin < 2
    replacement = NaN;
end
values = double(values(:));
finite = isfinite(values);
if ~any(finite)
    if nargin >= 2
        values(:) = replacement;
    end
    return;
end
firstFinite = find(finite, 1, 'first');
lastFinite = find(finite, 1, 'last');
values(~finite & (1:numel(values)).' < firstFinite) = values(firstFinite);
for i = firstFinite+1:lastFinite
    if ~isfinite(values(i))
        values(i) = values(i-1);
    end
end
if lastFinite < numel(values)
    values(lastFinite+1:end) = values(lastFinite);
end
end

function half = halfWidths(stored, x, width)
n = numel(x);
if ~isempty(stored) && numel(stored) == n
    half = double(stored(:));
    return;
end
if isscalar(width) && isfinite(width)
    half = repmat(width / 2, n, 1);
else
    half = repmat(1.5, n, 1);
end
end

function T = downsampleTable(T, maxSamples)
if height(T) <= maxSamples
    return;
end
idx = unique(round(linspace(1, height(T), maxSamples)));
T = T(idx, :);
end

function idx = downsampleIndex(n, maxSamples)
if n <= maxSamples
    idx = (1:n).';
    return;
end
idx = unique(round(linspace(1, n, maxSamples)));
end

function out = round2(values)
out = round(double(values) * 100) / 100;
end

function out = round3(values)
out = round(double(values) * 1000) / 1000;
end

function out = round4(values)
out = round(double(values) * 10000) / 10000;
end
