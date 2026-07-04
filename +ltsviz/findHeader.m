function idx = findHeader(info, aliases)
%FINDHEADER Locate the first header matching one of the aliases.

normalized = cellfun(@ltsviz.normalizeName, cellstr(aliases), ...
    'UniformOutput', false);
idx = [];
for aliasIdx = 1:numel(normalized)
    alias = normalized{aliasIdx};
    for i = 1:numel(info)
        if strcmp(info(i).normalizedBase, alias) || ...
                strcmp(info(i).normalizedFull, alias)
            idx = i;
            return;
        end
    end
end
end
