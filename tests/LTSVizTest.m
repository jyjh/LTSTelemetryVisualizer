classdef LTSVizTest < matlab.unittest.TestCase
    methods (Test)
        function parsesMotecHeadersAndUnits(testCase)
            file = tempname + ".csv";
            cleanup = onCleanup(@() deleteIfExists(file));
            fid = fopen(file, 'w');
            fprintf(fid, 'Time (s),Vehicle Speed Value (km/h),Steer (deg),Throttle Pedal (%%),X,Y\n');
            fprintf(fid, '0,36,10,50,1,2\n1,72,20,75,3,4\n');
            fclose(fid);

            run = ltsviz.readTelemetryCsv(file);

            testCase.verifyEqual(run.time, [0; 1], 'AbsTol', 1e-12);
            testCase.verifyEqual(run.speed, [10; 20], 'AbsTol', 1e-12);
            testCase.verifyEqual(run.steer, deg2rad([10; 20]), 'AbsTol', 1e-12);
            testCase.verifyEqual(run.throttle, [0.5; 0.75], 'AbsTol', 1e-12);
            testCase.verifyEqual(run.x, [1; 3], 'AbsTol', 1e-12);
        end

        function convertsGpsToLocalMeters(testCase)
            [east, north] = ltsviz.gpsToLocalMeters([42; 42], [-84; -83.999]);

            testCase.verifyEqual(east(1), 0, 'AbsTol', 1e-9);
            testCase.verifyEqual(north(1), 0, 'AbsTol', 1e-9);
            testCase.verifyGreaterThan(east(2), 70);
            testCase.verifyLessThan(abs(north(2)), 1e-6);
        end

        function alignsAndBuildsComparison(testCase)
            sim = minimalRun('sim', [0; 1; 2], [0; 1; 2], [0; 0; 0]);
            real = minimalRun('real', [0; 1; 2], [0; 0; 0], [0; 1; 2]);

            [sim, real] = ltsviz.alignRuns(sim, real);
            comparison = ltsviz.buildComparison(sim, real);

            testCase.verifyEqual(height(comparison.table), 3);
            testCase.verifyLessThan(max(comparison.table.path_error_m), 1e-9);
        end

        function simOnlyCreatesHtml(testCase)
            csvFile = tempname + ".csv";
            htmlFile = tempname + ".html";
            sceneFile = replace(htmlFile, ".html", "_3d.html");
            cleanup = onCleanup(@() cleanupFiles(csvFile, htmlFile, sceneFile, ...
                replace(htmlFile, ".html", "_aligned.csv"), ...
                replace(htmlFile, ".html", "_summary.json")));

            fid = fopen(csvFile, 'w');
            fprintf(fid, 'Time (s),Distance (m),Speed mps (m/s),X,Y,Yaw\n');
            for i = 0:4
                fprintf(fid, '%d,%d,5,%d,0,0\n', i, i * 5, i);
            end
            fclose(fid);

            result = ltsviz.visualizeCorrelation('SimCsv', csvFile, ...
                'OutputHtml', htmlFile, 'Visible', false);

            testCase.verifyTrue(isfile(result.htmlFile));
            testCase.verifyTrue(isfile(result.alignedCsv));
            testCase.verifyTrue(isfile(result.summaryJson));
            testCase.verifyTrue(isfile(result.sceneHtml));
            testCase.verifyEqual(result.sceneHtml, sceneFile);
            testCase.verifyTrue(contains(fileread(result.sceneHtml), 'LTS_SCENE'));
        end

        function buildScene3DCreatesConsistentPayload(testCase)
            sim = curvedRun('sim', 1.0);
            real = curvedRun('real', 1.04);

            trackCsv = tempname + ".csv";
            cleanup = onCleanup(@() deleteIfExists(trackCsv));
            writeCircleTrack(trackCsv, 20, 30);

            [sim, real] = ltsviz.alignRuns(sim, real);
            comparison = ltsviz.buildComparison(sim, real);
            summary = ltsviz.summarizeComparison(comparison, sim, real, ...
                struct('mode', 'initial_pose'), '');
            track = ltsviz.loadTrack(trackCsv);
            scene = ltsviz.buildScene3D(sim, real, track, comparison, summary);

            n = numel(scene.sim.t);
            testCase.verifyEqual(numel(scene.sim.x), n);
            testCase.verifyEqual(numel(scene.sim.h), n);
            testCase.verifyEqual(numel(scene.sim.roll), n);
            testCase.verifyEqual(numel(scene.sim.pitch), n);
            testCase.verifyEqual(numel(scene.real.t), n);
            testCase.verifyTrue(all(isfinite(scene.sim.x)));
            testCase.verifyTrue(all(isfinite(scene.sim.h)));
            testCase.verifyTrue(all(abs(scene.sim.roll) <= deg2rad(8)));
            testCase.verifyTrue(scene.meta.hasReal);
            testCase.verifyTrue(scene.track.hasTrack);
            testCase.verifyTrue(scene.track.closed);
            testCase.verifyEqual(numel(scene.track.left), numel(scene.track.x));
            testCase.verifyGreaterThan(scene.samples, 1);
            testCase.verifyEqual(scene.meta.axisUnit, 's');
            testCase.verifyTrue(scene.meta.attitudeEstimated);
        end

        function render3DWritesStandaloneHtml(testCase)
            simCsv = tempname + ".csv";
            replayCsv = tempname + ".csv";
            trackCsv = tempname + ".csv";
            htmlFile = tempname + ".html";
            cleanup = onCleanup(@() cleanupFiles(simCsv, replayCsv, trackCsv, htmlFile));

            writeCurvedCsv(simCsv, 'sim');
            writeCurvedCsv(replayCsv, 'real');
            writeCircleTrack(trackCsv, 20, 30);

            result = ltsviz.render3D('SimCsv', simCsv, ...
                'RealReplayCsv', replayCsv, ...
                'TrackFile', trackCsv, ...
                'OutputHtml', htmlFile);

            testCase.verifyTrue(isfile(result.htmlFile));
            html = fileread(result.htmlFile);
            testCase.verifyTrue(contains(html, 'LTS_SCENE'), ...
                'Scene payload missing from report.');
            testCase.verifyTrue(contains(html, 'THREE'), ...
                'three.js bundle missing from report.');
            testCase.verifyFalse(contains(html, 'cdn.jsdelivr'), ...
                'Local three.js vendor copy was not embedded.');
            testCase.verifyTrue(result.scene.meta.hasReal);
            testCase.verifyTrue(result.scene.track.hasTrack);
        end

        function loadTrackReadsClosedMatTrack(testCase)
            matFile = tempname + ".mat";
            cleanup = onCleanup(@() deleteIfExists(matFile));
            th = linspace(0, 2 * pi, 41).';
            track = struct();
            track.points_m = [30 * cos(th), 30 * sin(th)];
            track.station_m = linspace(0, 2 * pi * 30 - 1, 41).';
            track.width_m = 5;
            track.left_width_m = 2.5 + 0.1 * sin(th);
            track.right_width_m = 2.5 - 0.1 * sin(th);
            track.closed = 1;
            save(matFile, 'track');

            t = ltsviz.loadTrack(matFile);

            testCase.verifyTrue(t.hasTrack);
            testCase.verifyTrue(t.closed);
            testCase.verifyEqual(t.width, 5);
            testCase.verifyEqual(numel(t.leftWidth), 41);
            testCase.verifyEqual(numel(t.rightWidth), 41);
            testCase.verifyEqual(numel(t.x), 41);
        end
    end
end

function writeCurvedCsv(filepath, kind)
% A right-hand circle lap starting at the origin heading +x, with varying
% speed and pedal input so the 3D replay has something to animate.
dt = 0.1;
t = (0:dt:40).';
n = numel(t);
R = 30;
theta = 2 * pi * t / 40;
x = R * sin(theta);
y = R * (1 - cos(theta));
speed = 8 + 2.5 * sin(2 * theta);
steerRad = repmat(atan(3.0 / R), n, 1);
throttle = 0.5 + 0.4 * cos(theta);
brake = 0.3 + 0.3 * sin(3 * theta);
latG = speed.^2 / R / 9.80665;
longG = 0.15 * cos(2 * theta);
distance = [0; cumtrapz(t, speed)];
if strcmp(kind, 'real')
    % A slightly different line: small growing offset and speed bias.
    x = x + 0.4 * t / 40;
    y = y + 0.2 * t / 40;
    speed = speed * 1.03;
end
fid = fopen(filepath, 'w');
fprintf(fid, ['time_s,distance_m,speed_mps,steer_rad,throttle_ratio,' ...
    'brake_ratio,lat_accel_g,long_accel_g,x_m,y_m,yaw_rad\n']);
for i = 1:n
    fprintf(fid, '%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g\n', ...
        t(i), distance(i), speed(i), steerRad(i), throttle(i), brake(i), ...
        latG(i), longG(i), x(i), y(i), theta(i));
end
fclose(fid);
end

function writeCircleTrack(filepath, n, R)
th = linspace(0, 2 * pi, n + 1).';
x = R * sin(th);
y = R * (1 - cos(th));
s = linspace(0, 2 * pi * R, n + 1).';
fid = fopen(filepath, 'w');
fprintf(fid, 'x_m,y_m,s_m,width_m\n');
for i = 1:n + 1
    fprintf(fid, '%.6g,%.6g,%.6g,4\n', x(i), y(i), s(i));
end
fclose(fid);
end

function run = curvedRun(label, speedScale)
run = minimalRun(label, [], [], []);
n = 401;
t = (0:n-1).' * 0.1;
theta = 2 * pi * t / 40;
speed = (8 + 2.5 * sin(2 * theta)) * speedScale;
run.time = t;
run.x = 30 * sin(theta);
run.y = 30 * (1 - cos(theta));
run.speed = speed;
run.distance = [0; cumtrapz(t, speed)];
run.steer = repmat(atan(3.0 / 30), n, 1);
run.throttle = 0.5 + 0.4 * cos(theta);
run.brake = 0.3 + 0.3 * sin(3 * theta);
run.latAccelG = speed.^2 / 30 / 9.80665;
run.longAccelG = 0.15 * cos(2 * theta);
end

function run = minimalRun(label, time, x, y)
run = struct();
run.path = "";
run.kind = label;
run.label = label;
run.time = time(:);
run.distance = time(:);
run.x = x(:);
run.y = y(:);
run.xAligned = x(:);
run.yAligned = y(:);
run.yaw = zeros(size(time(:)));
run.gpsCourse = NaN(size(time(:)));
run.speed = ones(size(time(:)));
run.steer = zeros(size(time(:)));
run.throttle = zeros(size(time(:)));
run.brake = zeros(size(time(:)));
run.yawRate = zeros(size(time(:)));
run.latAccelG = zeros(size(time(:)));
run.warnings = {};
end

function cleanupFiles(varargin)
for i = 1:nargin
    deleteIfExists(varargin{i});
end
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end
