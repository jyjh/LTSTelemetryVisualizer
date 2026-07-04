function run = localizeTrajectory(run)
%LOCALIZETRAJECTORY Ensure a run has local x/y coordinates when possible.

if any(isfinite(run.x)) && any(isfinite(run.y))
    return;
end

if any(isfinite(run.gpsLat)) && any(isfinite(run.gpsLon))
    [run.x, run.y] = ltsviz.gpsToLocalMeters(run.gpsLat, run.gpsLon);
    run.warnings{end+1} = 'Using GPS latitude/longitude as local x/y.';
    return;
end

if any(isfinite(run.distance)) && any(isfinite(run.yaw))
    run.x = reconstructPosition(run.distance, run.yaw, true);
    run.y = reconstructPosition(run.distance, run.yaw, false);
    run.warnings{end+1} = 'Reconstructed x/y from distance and yaw.';
else
    run.x = NaN(size(run.time));
    run.y = NaN(size(run.time));
    run.warnings{end+1} = 'No x/y or GPS position channels available.';
end
end

function values = reconstructPosition(distance, yaw, useX)
distance = double(distance(:));
yaw = double(yaw(:));
deltaS = [0; max(0, diff(distance))];
if useX
    values = cumsum(deltaS .* cos(yaw));
else
    values = cumsum(deltaS .* sin(yaw));
end
end
