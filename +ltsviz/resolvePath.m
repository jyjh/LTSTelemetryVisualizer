function pathOut = resolvePath(pathIn, repoRoot)
%RESOLVEPATH Resolve a possibly relative path against the parent repo root.

if nargin < 2 || isempty(repoRoot)
    repoRoot = pwd;
end
if isempty(pathIn)
    pathOut = '';
    return;
end
pathOut = char(pathIn);
if isfolder(pathOut) || isfile(pathOut)
    return;
end
if isAbsolutePath(pathOut)
    return;
end
pathOut = fullfile(char(repoRoot), pathOut);
end

function yes = isAbsolutePath(value)
if ispc
    yes = ~isempty(regexp(value, '^[A-Za-z]:[\\/]', 'once')) || startsWith(value, '\\');
else
    yes = startsWith(value, '/');
end
end
