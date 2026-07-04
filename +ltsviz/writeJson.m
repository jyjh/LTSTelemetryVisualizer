function writeJson(filepath, data)
%WRITEJSON Write a struct as JSON with best-effort pretty formatting.

try
    text = jsonencode(data, 'PrettyPrint', true);
catch
    text = jsonencode(data);
end
fid = fopen(filepath, 'w');
if fid < 0
    error('ltsviz:JsonOpenFailed', 'Could not write %s.', filepath);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', text);
end
