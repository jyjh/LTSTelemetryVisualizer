function name = normalizeName(value)
%NORMALIZENAME Case-insensitive matching key for channel names and units.

name = lower(char(value));
name = strrep(name, '%', 'percent');
name = regexprep(name, '[^a-z0-9]+', '');
end
