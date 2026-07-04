function track = loadTrack(trackFile)
%LOADTRACK Read an optional reference track file.

track = struct('hasTrack', false, 'x', [], 'y', [], 's', [], ...
    'label', '', 'width', NaN);
if isempty(trackFile)
    return;
end
trackFile = char(trackFile);
if ~exist(trackFile, 'file')
    warning('ltsviz:MissingTrack', 'Track file not found: %s', trackFile);
    return;
end
[~, name, ext] = fileparts(trackFile);
track.label = name;
switch lower(ext)
    case '.mat'
        S = load(trackFile);
        if isfield(S, 'track')
            t = S.track;
            if isfield(t, 'points_m')
                points = double(t.points_m);
                track.x = points(:,1);
                track.y = points(:,2);
                if isfield(t, 'station_m')
                    track.s = double(t.station_m(:));
                else
                    track.s = ltsviz.pathStation(track.x, track.y, false);
                end
                if isfield(t, 'width_m')
                    track.width = double(t.width_m);
                end
                track.hasTrack = true;
            end
        end
    case '.csv'
        T = readtable(trackFile, 'VariableNamingRule', 'preserve');
        names = T.Properties.VariableNames;
        info = ltsviz.parseHeaders(names);
        ix = ltsviz.findHeader(info, {'x_m', 'x'});
        iy = ltsviz.findHeader(info, {'y_m', 'y'});
        is = ltsviz.findHeader(info, {'s_m', 'station_m', 'Distance', 's'});
        if ~isempty(ix) && ~isempty(iy)
            track.x = double(T.(names{ix})(:));
            track.y = double(T.(names{iy})(:));
            if ~isempty(is)
                track.s = double(T.(names{is})(:));
            else
                track.s = ltsviz.pathStation(track.x, track.y, false);
            end
            track.hasTrack = true;
        end
    otherwise
        warning('ltsviz:UnsupportedTrack', ...
            'Track file must be .mat or .csv, got %s.', ext);
end
end
