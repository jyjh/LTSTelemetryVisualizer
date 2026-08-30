function result = visualizeCorrelation(varargin)
%VISUALIZECORRELATION Build the correlation report plus 3D replay.
%
%   result = ltsviz.visualizeCorrelation('SimCsv', simCsv, ...)
%
% Produces the classic diagnostic set — Plotly HTML report, aligned
% comparison CSV, summary JSON, and an optional MATLAB figure — plus the
% standalone 3D replay scene (<output>_3d.html). Name-value options:
%
%   SimCsv, RealMoTeCFile, RealReplayCsv, ChannelMap, Lap, LdxFile,
%   TrackFile, AlignmentMode, OutputHtml, RepoRoot, PythonCommand,
%   SampleFrequencyHz, Visible, KeepIntermediate (as before), plus
%   SceneHtml ('' derives <OutputHtml base>_3d.html; 'none' disables) and
%   MaxScenePoints (default 4000).

repoRootDefault = ltsviz.detectRepoRoot();

parser = inputParser;
parser.FunctionName = 'ltsviz.visualizeCorrelation';
parser.addParameter('SimCsv', '', @(x) ischar(x) || isstring(x));
parser.addParameter('RealMoTeCFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('RealReplayCsv', '', @(x) ischar(x) || isstring(x));
parser.addParameter('ChannelMap', '', @(x) ischar(x) || isstring(x));
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
parser.addParameter('SceneHtml', '', @(x) ischar(x) || isstring(x));
parser.addParameter('MaxScenePoints', 4000, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 2));
parser.parse(varargin{:});
opts = parser.Results;

repoRoot = char(opts.RepoRoot);
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

fig = ltsviz.makeFigure(simRun, realRun, track, comparison, ...
    'Visible', logical(opts.Visible));

summary = ltsviz.summarizeComparison(comparison, simRun, realRun, alignment, ...
    extract.manifest);
baseOutput = erase(outputHtml, '.html');
alignedCsv = [baseOutput '_aligned.csv'];
summaryJson = [baseOutput '_summary.json'];

sceneHtml = resolveSceneHtml(opts.SceneHtml, baseOutput, repoRoot);
if ~isempty(sceneHtml)
    scene = ltsviz.buildScene3D(simRun, realRun, track, comparison, summary, ...
        'MaxPoints', opts.MaxScenePoints);
    ltsviz.write3DHtml(sceneHtml, scene);
else
    scene = [];
end

writetable(comparison.table, alignedCsv);
ltsviz.writeJson(summaryJson, summary);
ltsviz.writePlotlyHtml(outputHtml, simRun, realRun, track, comparison, ...
    summary, sceneHtml);

if ~logical(opts.KeepIntermediate) && ~isempty(extract.replayCsv) && ...
        startsWith(extract.replayCsv, outputDir) %#ok<STRSCALR>
    % Keep the manifest and replay by default when the caller opted in only.
    % In normal use these intermediates are useful breadcrumbs, so this block
    % intentionally leaves files in place when the output directory differs.
end

result = struct( ...
    'htmlFile', outputHtml, ...
    'alignedCsv', alignedCsv, ...
    'summaryJson', summaryJson, ...
    'replayCsv', extract.replayCsv, ...
    'extractManifest', extract.manifest, ...
    'figure', fig, ...
    'sceneHtml', sceneHtml, ...
    'scene', scene, ...
    'summary', summary);
fprintf('LTS visualization HTML: %s\n', outputHtml);
if ~isempty(sceneHtml)
    fprintf('LTS 3D replay HTML: %s\n', sceneHtml);
end
fprintf('Aligned comparison CSV: %s\n', alignedCsv);
fprintf('Summary JSON: %s\n', summaryJson);
end

function sceneHtml = resolveSceneHtml(sceneHtml, baseOutput, repoRoot)
sceneHtml = char(sceneHtml);
if strcmpi(sceneHtml, 'none')
    sceneHtml = '';
elseif isempty(sceneHtml)
    sceneHtml = [baseOutput '_3d.html'];
else
    sceneHtml = ltsviz.resolvePath(sceneHtml, repoRoot);
end
end
