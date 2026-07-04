function repoRoot = detectRepoRoot()
%DETECTREPOROOT Locate the parent LTS repository when used as a submodule.

packageDir = fileparts(mfilename('fullpath'));
submoduleRoot = fileparts(packageDir);
candidates = { ...
    fullfile(submoduleRoot, '..', '..'), ...
    pwd};

repoRoot = pwd;
for i = 1:numel(candidates)
    candidate = char(java.io.File(candidates{i}).getCanonicalPath());
    if exist(fullfile(candidate, 'src', 'Simulator.m'), 'file') && ...
            exist(fullfile(candidate, 'scripts', 'extract_motec_lap.py'), 'file')
        repoRoot = candidate;
        return;
    end
end
end
