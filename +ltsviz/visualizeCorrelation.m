function result = visualizeCorrelation(varargin)
%VISUALIZECORRELATION Build a 3D correlation report from sim and real telemetry.
%
% result = ltsviz.visualizeCorrelation('SimCsv', simCsv, ...)

repoRootDefault = ltsviz.detectRepoRoot();
defaultChannelMap = fullfile(repoRootDefault, 'config', 'motec', ...
    'r25_real_channel_map.json');
if ~exist(defaultChannelMap, 'file')
    defaultChannelMap = fullfile(repoRootDefault, 'config', 'motec', ...
        'default_channel_map.json');
end

parser = inputParser;
parser.FunctionName = 'ltsviz.visualizeCorrelation';
parser.addParameter('SimCsv', '', @(x) ischar(x) || isstring(x));
parser.addParameter('RealMoTeCFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('RealReplayCsv', '', @(x) ischar(x) || isstring(x));
parser.addParameter('ChannelMap', defaultChannelMap, @(x) ischar(x) || isstring(x));
parser.addParameter('Lap', [], @(x) isempty(x) || isnumeric(x) || ischar(x) || isstring(x));
parser.addParameter('LdxFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('TrackFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('AlignmentMode', 'time', @(x) ischar(x) || isstring(x));
parser.addParameter('OutputHtml', '', @(x) ischar(x) || isstring(x));
parser.addParameter('RepoRoot', repoRootDefault, @(x) ischar(x) || isstring(x));
parser.addParameter('PythonCommand', 'python', @(x) ischar(x) || isstring(x));
parser.addParameter('SampleFrequencyHz', 100, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
parser.addParameter('Visible', false, @(x) islogical(x) || isnumeric(x));
parser.addParameter('KeepIntermediate', false, @(x) islogical(x) || isnumeric(x));
parser.parse(varargin{:});
opts = parser.Results;

repoRoot = char(opts.RepoRoot);
simCsv = ltsviz.resolvePath(opts.SimCsv, repoRoot);
if isempty(simCsv) || ~exist(simCsv, 'file')
    error('ltsviz:MissingSimCsv', 'SimCsv is required and must exist.');
end

outputHtml = char(opts.OutputHtml);
if isempty(outputHtml)
    outputHtml = fullfile(repoRoot, 'exports', ...
        sprintf('visualization_%s.html', datestr(now, 'yyyymmdd_HHMMSS')));
else
    outputHtml = ltsviz.resolvePath(outputHtml, repoRoot);
end
outputDir = fileparts(outputHtml);
if ~isempty(outputDir) && ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

simRun = ltsviz.readTelemetryCsv(simCsv, 'Label', 'Simulation', 'Kind', 'sim');
realRun = struct([]);
intermediateReplayCsv = '';
extractManifest = '';

realReplayCsv = ltsviz.resolvePath(opts.RealReplayCsv, repoRoot);
realMotecFile = ltsviz.resolvePath(opts.RealMoTeCFile, repoRoot);
if ~isempty(realReplayCsv)
    realRun = ltsviz.readTelemetryCsv(realReplayCsv, ...
        'Label', 'Reality', 'Kind', 'replay');
elseif ~isempty(realMotecFile)
    [intermediateReplayCsv, extractManifest] = ltsviz.extractReplayFromMotec( ...
        realMotecFile, ...
        'RepoRoot', repoRoot, ...
        'ChannelMap', ltsviz.resolvePath(opts.ChannelMap, repoRoot), ...
        'Lap', opts.Lap, ...
        'LdxFile', ltsviz.resolvePath(opts.LdxFile, repoRoot), ...
        'PythonCommand', opts.PythonCommand, ...
        'SampleFrequencyHz', opts.SampleFrequencyHz, ...
        'OutputDir', outputDir);
    realRun = ltsviz.readTelemetryCsv(intermediateReplayCsv, ...
        'Label', 'Reality', 'Kind', 'replay');
end

track = ltsviz.loadTrack(ltsviz.resolvePath(opts.TrackFile, repoRoot));
[simRun, realRun, alignment] = ltsviz.alignRuns(simRun, realRun);
comparison = ltsviz.buildComparison(simRun, realRun, ...
    'AlignmentMode', opts.AlignmentMode);

fig = ltsviz.makeFigure(simRun, realRun, track, comparison, ...
    'Visible', logical(opts.Visible));

summary = ltsviz.summarizeComparison(comparison, simRun, realRun, alignment, ...
    extractManifest);
baseOutput = erase(outputHtml, '.html');
alignedCsv = [baseOutput '_aligned.csv'];
summaryJson = [baseOutput '_summary.json'];

writetable(comparison.table, alignedCsv);
ltsviz.writeJson(summaryJson, summary);
ltsviz.writePlotlyHtml(outputHtml, simRun, realRun, track, comparison, summary);

if ~logical(opts.KeepIntermediate) && ~isempty(intermediateReplayCsv) && ...
        startsWith(intermediateReplayCsv, outputDir) %#ok<STRSCALR>
    % Keep the manifest and replay by default when the caller opted in only.
    % In normal use these intermediates are useful breadcrumbs, so this block
    % intentionally leaves files in place when the output directory differs.
end

result = struct( ...
    'htmlFile', outputHtml, ...
    'alignedCsv', alignedCsv, ...
    'summaryJson', summaryJson, ...
    'replayCsv', intermediateReplayCsv, ...
    'extractManifest', extractManifest, ...
    'figure', fig, ...
    'summary', summary);
fprintf('LTS visualization HTML: %s\n', outputHtml);
fprintf('Aligned comparison CSV: %s\n', alignedCsv);
fprintf('Summary JSON: %s\n', summaryJson);
end
