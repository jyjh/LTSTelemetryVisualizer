function info = parseHeaders(headers)
%PARSEHEADERS Split MoTeC-style Channel Name (unit) headers.

info = repmat(struct('name', '', 'base', '', 'unit', '', ...
    'normalizedBase', '', 'normalizedFull', ''), numel(headers), 1);
for i = 1:numel(headers)
    name = char(headers{i});
    [base, unit] = splitHeader(name);
    info(i).name = name;
    info(i).base = base;
    info(i).unit = unit;
    info(i).normalizedBase = ltsviz.normalizeName(base);
    info(i).normalizedFull = ltsviz.normalizeName(name);
end
end

function [base, unit] = splitHeader(name)
tokens = regexp(strtrim(name), '^(.*?)\s*\(([^()]*)\)\s*$', 'tokens', 'once');
if isempty(tokens)
    base = strtrim(name);
    unit = '';
else
    base = strtrim(tokens{1});
    unit = strtrim(tokens{2});
end
end
