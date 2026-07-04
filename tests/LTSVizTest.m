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
            cleanup = onCleanup(@() cleanupFiles(csvFile, htmlFile, ...
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
        end
    end
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
