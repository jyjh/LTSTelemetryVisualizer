function run = readTelemetryCsv(filepath, varargin)
%READTELEMETRYCSV Read simulator or normalized replay telemetry.

parser = inputParser;
parser.addParameter('Label', '', @(x) ischar(x) || isstring(x));
parser.addParameter('Kind', 'sim', @(x) ischar(x) || isstring(x));
parser.parse(varargin{:});

filepath = char(filepath);
opts = detectImportOptions(filepath, 'VariableNamingRule', 'preserve');
T = readtable(filepath, opts);
headers = T.Properties.VariableNames;
info = ltsviz.parseHeaders(headers);
n = height(T);

run = struct();
run.path = filepath;
run.kind = char(parser.Results.Kind);
run.label = char(parser.Results.Label);
if isempty(run.label)
    [~, run.label] = fileparts(filepath);
end
run.rawTable = T;
run.headers = headers;
run.headerInfo = info;
run.warnings = {};

run.time = readChannel(T, info, {'time_s', 'time', 'Time', 'Control Time'}, 's', n);
run.distance = readChannel(T, info, {'distance_m', 'distance', 's_m', 'Distance', ...
    'Lap Distance', 'Control Distance', 'Ref S'}, 'm', n);
run.x = readChannel(T, info, {'x_m', 'x', 'X', 'Local X', 'Position X'}, 'm', n);
run.y = readChannel(T, info, {'y_m', 'y', 'Y', 'Local Y', 'Position Y'}, 'm', n);
run.gpsLat = readChannel(T, info, {'gps_lat_deg', 'gps_lat', 'latitude', ...
    'GPS Latitude', 'GPS Sensor Latitude', 'GPS.Sensor.Latitude'}, 'deg', n);
run.gpsLon = readChannel(T, info, {'gps_lon_deg', 'gps_lon', 'longitude', ...
    'GPS Longitude', 'GPS Sensor Longitude', 'GPS.Sensor.Longitude'}, 'deg', n);
run.gpsCourse = readChannel(T, info, {'gps_course_rad', 'gps_course', ...
    'GPS True Course', 'GPS Sensor True Course', 'GPS.Sensor.True Course'}, 'rad', n);
run.yaw = readChannel(T, info, {'yaw_rad', 'yaw', 'Yaw', 'Heading', 'Heading Raw'}, 'rad', n);
run.yawRate = readChannel(T, info, {'yaw_rate_radps', 'yaw_rate', 'Yaw Rate', ...
    'YawRate', 'Gyro Z', 'G Sensor Front Yaw Rate', 'G Sensor.Front.Yaw Rate'}, 'rad/s', n);
run.speed = readChannel(T, info, {'speed_mps', 'speed', 'Speed mps', ...
    'Vehicle Speed Value', 'Vehicle Speed', 'GPS Speed', 'Replay Speed Input'}, 'm/s', n);
run.steer = readChannel(T, info, {'steer_rad', 'steer', 'Steer Raw', 'Steer', ...
    'Replay Steer Input', 'Steering Angle'}, 'rad', n);
run.throttle = readChannel(T, info, {'throttle_ratio', 'throttle', 'Throttle Pedal', ...
    'Throttle Raw', 'Replay Throttle Input'}, 'ratio', n);
run.brake = readChannel(T, info, {'brake_ratio', 'brake', 'Brake', ...
    'Brake Raw', 'Replay Brake Input', 'Brake Requested'}, 'ratio', n);
run.brakePressureFront = readChannel(T, info, {'brake_pressure_front_bar', ...
    'Brake Pressure Front', 'Replay Brake Pressure Front'}, 'bar', n);
run.brakePressureRear = readChannel(T, info, {'brake_pressure_rear_bar', ...
    'Brake Pressure Rear', 'Replay Brake Pressure Rear'}, 'bar', n);
run.latAccelG = readChannel(T, info, {'lat_accel_g', 'lateral_accel_g', ...
    'G Sensor Front Acceleration Lateral', 'G Sensor Front Acceleration Late', ...
    'Lat Accel Raw', 'Lateral Acceleration', 'Lateral G'}, 'g', n);
run.longAccelG = readChannel(T, info, {'long_accel_g', 'longitudinal_accel_g', ...
    'G Sensor Front Acceleration Longitudinal', 'G Sensor Front Acceleration Long', ...
    'Long Accel Raw', 'Longitudinal Acceleration', 'Longitudinal G'}, 'g', n);

if all(~isfinite(run.time))
    run.time = (0:n-1).';
    run.warnings{end+1} = 'Missing time channel; using sample index as seconds.';
end
if all(~isfinite(run.distance)) && any(isfinite(run.speed))
    run.distance = integrateDistance(run.time, run.speed);
end
run = ltsviz.localizeTrajectory(run);
end

function values = readChannel(T, info, aliases, targetUnit, n)
idx = ltsviz.findHeader(info, aliases);
if isempty(idx)
    values = NaN(n, 1);
    return;
end
name = T.Properties.VariableNames{idx};
values = double(T.(name)(:));
values = values * unitScale(info(idx).unit, targetUnit);
end

function distance = integrateDistance(time, speed)
time = double(time(:));
speed = double(speed(:));
distance = zeros(size(time));
valid = isfinite(time) & isfinite(speed);
if nnz(valid) < 2
    distance(:) = NaN;
    return;
end
for i = 2:numel(time)
    if isfinite(time(i)) && isfinite(time(i-1)) && ...
            isfinite(speed(i)) && isfinite(speed(i-1))
        dt = max(0, time(i) - time(i-1));
        distance(i) = distance(i-1) + 0.5 * (speed(i) + speed(i-1)) * dt;
    else
        distance(i) = distance(i-1);
    end
end
end

function scale = unitScale(sourceUnit, targetUnit)
source = ltsviz.normalizeName(sourceUnit);
target = char(targetUnit);
scale = 1;
switch target
    case 'm/s'
        if any(strcmp(source, {'kmh', 'kph'}))
            scale = 1 / 3.6;
        end
    case 'rad'
        if strcmp(source, 'deg')
            scale = pi / 180;
        end
    case 'rad/s'
        if any(strcmp(source, {'degs', 'degsec', 'degpersec'}))
            scale = pi / 180;
        end
    case 'ratio'
        if contains(source, 'percent') || any(strcmp(source, {'pct', 'perc'}))
            scale = 0.01;
        end
    case 'bar'
        if strcmp(source, 'kpa')
            scale = 0.01;
        elseif strcmp(source, 'pa')
            scale = 1e-5;
        elseif strcmp(source, 'mpa')
            scale = 10;
        elseif strcmp(source, 'psi')
            scale = 0.0689475729;
        end
    case 'g'
        if any(strcmp(source, {'mss', 'ms2', 'mspers', 'mspers2'})) || contains(source, 'mss')
            scale = 1 / 9.80665;
        end
end
end
