function [replayCsv, manifestFile] = extractReplayFromMotec(motecFile, varargin)
%EXTRACTREPLAYFROMMOTEC Invoke the parent repo's existing MoTeC extractor.

parser = inputParser;
parser.addParameter('RepoRoot', ltsviz.detectRepoRoot(), @(x) ischar(x) || isstring(x));
parser.addParameter('ChannelMap', '', @(x) ischar(x) || isstring(x));
parser.addParameter('Lap', [], @(x) isempty(x) || isnumeric(x) || ischar(x) || isstring(x));
parser.addParameter('LdxFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('PythonCommand', 'python', @(x) ischar(x) || isstring(x));
parser.addParameter('SampleFrequencyHz', 100, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
parser.addParameter('OutputDir', '', @(x) ischar(x) || isstring(x));
parser.parse(varargin{:});
opts = parser.Results;

repoRoot = char(opts.RepoRoot);
script = fullfile(repoRoot, 'scripts', 'extract_motec_lap.py');
if ~exist(script, 'file')
    error('ltsviz:MissingExtractor', 'Could not find %s.', script);
end

outputDir = char(opts.OutputDir);
if isempty(outputDir)
    outputDir = fullfile(repoRoot, 'exports');
end
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

[~, baseName] = fileparts(char(motecFile));
stamp = datestr(now, 'yyyymmdd_HHMMSS');
replayCsv = fullfile(outputDir, sprintf('visualization_%s_%s_replay.csv', baseName, stamp));
manifestFile = fullfile(outputDir, sprintf('visualization_%s_%s_manifest.json', baseName, stamp));

args = {char(opts.PythonCommand), script, ...
    '--input', char(motecFile), ...
    '--output', replayCsv, ...
    '--manifest', manifestFile};
if ~isempty(opts.ChannelMap)
    args(end+1:end+2) = {'--channel-map', char(opts.ChannelMap)}; %#ok<AGROW>
end
if ~isempty(opts.Lap)
    args(end+1:end+2) = {'--laps', lapValue(opts.Lap)}; %#ok<AGROW>
end
if ~isempty(opts.LdxFile)
    args(end+1:end+2) = {'--ldx', char(opts.LdxFile)}; %#ok<AGROW>
end
if ~isempty(opts.SampleFrequencyHz)
    args(end+1:end+2) = {'--frequency', sprintf('%.9g', opts.SampleFrequencyHz)}; %#ok<AGROW>
end

[status, output] = system(joinCommand(args));
if status ~= 0 && ~isempty(opts.Lap)
    warning('ltsviz:LapExtractionFailed', ...
        ['Lap-specific extraction failed, likely because the .ldx has no BCN ' ...
         'markers. Retrying whole-log import.\n%s'], strtrim(output));
    args = argsWithoutLapAndLdx(args);
    [status, output] = system(joinCommand(args));
end
if status ~= 0
    error('ltsviz:ExtractionFailed', 'MoTeC extraction failed:\n%s', output);
end
fprintf('%s\n', strtrim(output));
end

function value = lapValue(lap)
if isnumeric(lap)
    if isscalar(lap)
        value = sprintf('%d', lap);
    else
        value = sprintf('%d-%d', lap(1), lap(2));
    end
else
    value = char(lap);
end
end

function command = joinCommand(args)
quoted = cell(size(args));
for i = 1:numel(args)
    quoted{i} = quote(args{i});
end
command = strjoin(quoted, ' ');
end

function value = quote(value)
value = char(value);
value = strrep(value, '"', '\"');
value = ['"' value '"'];
end

function args = argsWithoutLapAndLdx(args)
dropNext = false;
keep = true(size(args));
for i = 1:numel(args)
    if dropNext
        keep(i) = false;
        dropNext = false;
        continue;
    end
    if strcmp(args{i}, '--laps') || strcmp(args{i}, '--ldx')
        keep(i) = false;
        dropNext = true;
    end
end
args = args(keep);
end
