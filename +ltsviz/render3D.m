function result = render3D(varargin)
%RENDER3D Build a standalone 3D replay of what the car is doing.
%
%   result = ltsviz.render3D('SimCsv', 'exports/correlation_run.csv', ...)
%
% Renders the simulation run (optionally against an aligned reality run)
% as animated 3D cars on the reference track in a single self-contained
% HTML file: play/pause/scrub playback, chase/cockpit/orbit/top cameras,
% live pedal-steer telemetry, and speed/input strip charts. The file works
% offline in any WebGL-capable browser.
%
% Simplest use — just the simulation:
%   ltsviz.render3D('SimCsv', 'exports/correlation_run.csv')
%
% Simulation vs a real MoTeC lap on the endurance track:
%   ltsviz.render3D( ...
%       'SimCsv', 'exports/correlation_run.csv', ...
%       'RealMoTeCFile', 'data/lap5_raw.ld', ...
%       'ChannelMap', 'config/motec/r25_real_channel_map.json', ...
%       'TrackFile', 'tracks/endurance_track_grid_25ft_from_matlab_smoothed.mat')
%
% Name-value options:
%   SimCsv           (required) MoTeC-style sim CSV export.
%   RealReplayCsv    Normalized replay CSV from extract_motec_lap.py.
%   RealMoTeCFile    Raw MoTeC .ld log; extracted via the Python pipeline.
%   ChannelMap       Channel map JSON for .ld extraction (auto by default).
%   Lap              Lap number/range passed to the extractor.
%   LdxFile          Optional .ldx sidecar for lap markers.
%   TrackFile        Reference track .mat/.csv (drives the 3D ribbon).
%   AlignmentMode    'time' (default) or 'distance'.
%   OutputHtml       Output path (default exports/scene3d_<timestamp>.html).
%   MaxScenePoints   Replay samples kept in the payload (default 4000).
%   RepoRoot         Parent lts repository root.
%   PythonCommand    Python launcher used for .ld extraction.
%   SampleFrequencyHz Resampling rate for .ld extraction (default 100).
%
% The result struct carries htmlFile, the scene payload, the comparison
% summary, and any extraction intermediates.

repoRootDefault = ltsviz.detectRepoRoot();
parser = inputParser;
parser.FunctionName = 'ltsviz.render3D';
parser.addParameter('SimCsv', '', @(x) ischar(x) || isstring(x));
parser.addParameter('RealMoTeCFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('RealReplayCsv', '', @(x) ischar(x) || isstring(x));
parser.addParameter('ChannelMap', '', @(x) ischar(x) || isstring(x));
parser.addParameter('Lap', [], @(x) isempty(x) || isnumeric(x) || ischar(x) || isstring(x));
parser.addParameter('LdxFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('TrackFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('AlignmentMode', 'time', @(x) ischar(x) || isstring(x));
parser.addParameter('OutputHtml', '', @(x) ischar(x) || isstring(x));
parser.addParameter('MaxScenePoints', 4000, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 2));
parser.addParameter('RepoRoot', repoRootDefault, @(x) ischar(x) || isstring(x));
parser.addParameter('PythonCommand', 'python', @(x) ischar(x) || isstring(x));
parser.addParameter('SampleFrequencyHz', 100, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
parser.parse(varargin{:});
opts = parser.Results;

repoRoot = char(opts.RepoRoot);
outputHtml = char(opts.OutputHtml);
if isempty(outputHtml)
    outputHtml = fullfile(repoRoot, 'exports', ...
        sprintf('scene3d_%s.html', datestr(now, 'yyyymmdd_HHMMSS')));
else
    outputHtml = ltsviz.resolvePath(outputHtml, repoRoot);
end
outputDir = fileparts(outputHtml);
if ~isempty(outputDir) && ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

[simRun, realRun, track, extract] = ltsviz.prepareRuns( ...
    'SimCsv', opts.SimCsv, ...
    'RealReplayCsv', opts.RealReplayCsv, ...
    'RealMoTeCFile', opts.RealMoTeCFile, ...
    'ChannelMap', opts.ChannelMap, ...
    'Lap', opts.Lap, ...
    'LdxFile', opts.LdxFile, ...
    'TrackFile', opts.TrackFile, ...
    'RepoRoot', repoRoot, ...
    'PythonCommand', opts.PythonCommand, ...
    'SampleFrequencyHz', opts.SampleFrequencyHz, ...
    'OutputDir', outputDir);

[simRun, realRun, alignment] = ltsviz.alignRuns(simRun, realRun);
comparison = ltsviz.buildComparison(simRun, realRun, ...
    'AlignmentMode', opts.AlignmentMode);
summary = ltsviz.summarizeComparison(comparison, simRun, realRun, ...
    alignment, extract.manifest);
scene = ltsviz.buildScene3D(simRun, realRun, track, comparison, summary, ...
    'MaxPoints', opts.MaxScenePoints);
ltsviz.write3DHtml(outputHtml, scene);

result = struct( ...
    'htmlFile', outputHtml, ...
    'scene', scene, ...
    'summary', summary, ...
    'replayCsv', extract.replayCsv, ...
    'extractManifest', extract.manifest);
fprintf('LTS 3D replay HTML: %s\n', outputHtml);
end
