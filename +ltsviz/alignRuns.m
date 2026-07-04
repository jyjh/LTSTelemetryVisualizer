function [simRun, realRun, alignment] = alignRuns(simRun, realRun)
%ALIGNRUNS Translate and rotate the real trajectory into the sim frame.

alignment = struct('mode', 'none', 'rotationRad', 0, ...
    'translation', [0 0], 'realHeadingRad', NaN, 'simHeadingRad', NaN);
simRun.xAligned = simRun.x(:);
simRun.yAligned = simRun.y(:);

if isempty(realRun)
    return;
end

simOrigin = firstPoint(simRun.x, simRun.y);
realOrigin = firstPoint(realRun.x, realRun.y);
if any(~isfinite(simOrigin)) || any(~isfinite(realOrigin))
    realRun.xAligned = realRun.x(:);
    realRun.yAligned = realRun.y(:);
    alignment.mode = 'unavailable';
    return;
end

simHeading = firstPathHeading(simRun);
realHeading = firstPathHeading(realRun);
if ~isfinite(simHeading)
    simHeading = 0;
end
if ~isfinite(realHeading)
    realHeading = 0;
end
theta = atan2(sin(simHeading - realHeading), cos(simHeading - realHeading));
R = [cos(theta), -sin(theta); sin(theta), cos(theta)];
xy = [realRun.x(:) - realOrigin(1), realRun.y(:) - realOrigin(2)] * R.';
realRun.xAligned = xy(:,1) + simOrigin(1);
realRun.yAligned = xy(:,2) + simOrigin(2);

alignment.mode = 'initial_pose';
alignment.rotationRad = theta;
alignment.translation = simOrigin;
alignment.realHeadingRad = realHeading;
alignment.simHeadingRad = simHeading;
end

function point = firstPoint(x, y)
idx = find(isfinite(x(:)) & isfinite(y(:)), 1, 'first');
if isempty(idx)
    point = [NaN NaN];
else
    point = [x(idx), y(idx)];
end
end

function heading = firstPathHeading(run)
heading = NaN;
x = run.x(:);
y = run.y(:);
idx = find(isfinite(x) & isfinite(y));
if numel(idx) >= 2
    first = idx(1);
    for k = 2:numel(idx)
        j = idx(k);
        if hypot(x(j) - x(first), y(j) - y(first)) > 0.5
            heading = atan2(y(j) - y(first), x(j) - x(first));
            return;
        end
    end
end
if isfield(run, 'yaw') && any(isfinite(run.yaw))
    heading = run.yaw(find(isfinite(run.yaw), 1, 'first'));
elseif isfield(run, 'gpsCourse') && any(isfinite(run.gpsCourse))
    course = run.gpsCourse(find(isfinite(run.gpsCourse), 1, 'first'));
    heading = pi / 2 - course; % GPS true course: 0 north, positive clockwise.
end
end
