function [simRun, realRun, track, extract] = prepareRuns(varargin)
%PREPARERUNS Load the sim/real runs and reference track for reports.
%
%   [simRun, realRun, track, extract] = ltsviz.prepareRuns(...)
%
% Shared by ltsviz.visualizeCorrelation and ltsviz.render3D. The real run
% is read either from a normalized replay CSV (RealReplayCsv) or extracted
% from a raw MoTeC .ld log (RealMoTeCFile via the parent project's Python
% pipeline). extract reports the intermediate replay CSV and manifest paths
% (empty strings when nothing was extracted).
%
% Name-value options: SimCsv, RealMoTeCFile, RealReplayCsv, ChannelMap,
% Lap, LdxFile, TrackFile, RepoRoot, PythonCommand, SampleFrequencyHz,
% OutputDir.

repoRootDefault = ltsviz.detectRepoRoot();
defaultChannelMap = fullfile(repoRootDefault, 'config', 'motec', ...
    'r25_real_channel_map.json');
if ~exist(defaultChannelMap, 'file')
    defaultChannelMap = fullfile(repoRootDefault, 'config', 'motec', ...
        'default_channel_map.json');
end

parser = inputParser;
parser.FunctionName = 'ltsviz.prepareRuns';
parser.addParameter('SimCsv', '', @(x) ischar(x) || isstring(x));
parser.addParameter('RealMoTeCFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('RealReplayCsv', '', @(x) ischar(x) || isstring(x));
parser.addParameter('ChannelMap', defaultChannelMap, @(x) ischar(x) || isstring(x));
parser.addParameter('Lap', [], @(x) isempty(x) || isnumeric(x) || ischar(x) || isstring(x));
parser.addParameter('LdxFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('TrackFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('RepoRoot', repoRootDefault, @(x) ischar(x) || isstring(x));
parser.addParameter('PythonCommand', 'python', @(x) ischar(x) || isstring(x));
parser.addParameter('SampleFrequencyHz', 100, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
parser.addParameter('OutputDir', '', @(x) ischar(x) || isstring(x));
parser.parse(varargin{:});
opts = parser.Results;

repoRoot = char(opts.RepoRoot);
extract = struct('replayCsv', '', 'manifest', '');

channelMap = char(opts.ChannelMap);
if isempty(channelMap)
    channelMap = defaultChannelMap;
end

simCsv = ltsviz.resolvePath(opts.SimCsv, repoRoot);
if isempty(simCsv) || ~exist(simCsv, 'file')
    error('ltsviz:MissingSimCsv', 'SimCsv is required and must exist.');
end

simRun = ltsviz.readTelemetryCsv(simCsv, 'Label', 'Simulation', 'Kind', 'sim');
realRun = struct([]);

realReplayCsv = ltsviz.resolvePath(opts.RealReplayCsv, repoRoot);
realMotecFile = ltsviz.resolvePath(opts.RealMoTeCFile, repoRoot);
if ~isempty(realReplayCsv) && exist(realReplayCsv, 'file')
    realRun = ltsviz.readTelemetryCsv(realReplayCsv, ...
        'Label', 'Reality', 'Kind', 'replay');
elseif ~isempty(realReplayCsv)
    warning('ltsviz:MissingReplayCsv', ...
        'RealReplayCsv not found: %s. Continuing simulation-only.', realReplayCsv);
end
if isempty(realRun) && ~isempty(realMotecFile)
    [extract.replayCsv, extract.manifest] = ltsviz.extractReplayFromMotec( ...
        realMotecFile, ...
        'RepoRoot', repoRoot, ...
        'ChannelMap', ltsviz.resolvePath(channelMap, repoRoot), ...
        'Lap', opts.Lap, ...
        'LdxFile', ltsviz.resolvePath(opts.LdxFile, repoRoot), ...
        'PythonCommand', opts.PythonCommand, ...
        'SampleFrequencyHz', opts.SampleFrequencyHz, ...
        'OutputDir', char(opts.OutputDir));
    realRun = ltsviz.readTelemetryCsv(extract.replayCsv, ...
        'Label', 'Reality', 'Kind', 'replay');
end

track = ltsviz.loadTrack(ltsviz.resolvePath(opts.TrackFile, repoRoot));
end
