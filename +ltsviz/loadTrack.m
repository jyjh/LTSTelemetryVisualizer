function track = loadTrack(trackFile)
%LOADTRACK Read an optional reference track file.
%
% The returned struct carries the centerline (x, y), optional station s,
% per-point half widths (leftWidth/rightWidth in meters, falling back to
% width/2), and whether the circuit is closed. Widths feed the 3D track
% ribbon; the correlation report only uses the centerline.

track = struct('hasTrack', false, 'x', [], 'y', [], 's', [], ...
    'label', '', 'width', NaN, 'leftWidth', [], 'rightWidth', [], ...
    'closed', false);
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
                [track.width, track.leftWidth, track.rightWidth] = trackWidths(t);
                if isfield(t, 'closed')
                    track.closed = logical(double(t.closed));
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
            [track.width, track.leftWidth, track.rightWidth] = ...
                trackWidthsFromTable(T, names, info);
            track.closed = endpointsClose(track.x, track.y);
            track.hasTrack = true;
        end
    otherwise
        warning('ltsviz:UnsupportedTrack', ...
            'Track file must be .mat or .csv, got %s.', ext);
end
end

function [width, leftWidth, rightWidth] = trackWidths(t)
width = NaN;
leftWidth = [];
rightWidth = [];
if isfield(t, 'width_m')
    width = scalarOrPerPoint(double(t.width_m));
end
if isfield(t, 'left_width_m')
    leftWidth = double(t.left_width_m(:));
end
if isfield(t, 'right_width_m')
    rightWidth = double(t.right_width_m(:));
end
n = numel(t.points_m);
if isempty(leftWidth) && ~isempty(width) && isscalar(width)
    leftWidth = repmat(width / 2, n, 1);
end
if isempty(rightWidth) && ~isempty(width) && isscalar(width)
    rightWidth = repmat(width / 2, n, 1);
end
if isempty(width) && ~isempty(leftWidth) && ~isempty(rightWidth)
    width = mean([leftWidth(:), rightWidth(:)], 'all');
end
end

function [width, leftWidth, rightWidth] = trackWidthsFromTable(T, names, info)
width = NaN;
leftWidth = [];
rightWidth = [];
iw = ltsviz.findHeader(info, {'width_m', 'width'});
if ~isempty(iw)
    width = scalarOrPerPoint(double(T.(names{iw})(:)));
end
il = ltsviz.findHeader(info, {'left_width_m', 'left_width'});
ir = ltsviz.findHeader(info, {'right_width_m', 'right_width'});
if ~isempty(il)
    leftWidth = double(T.(names{il})(:));
end
if ~isempty(ir)
    rightWidth = double(T.(names{ir})(:));
end
n = height(T);
if isempty(leftWidth) && isscalar(width) && ~isnan(width)
    leftWidth = repmat(width / 2, n, 1);
end
if isempty(rightWidth) && isscalar(width) && ~isnan(width)
    rightWidth = repmat(width / 2, n, 1);
end
end

function value = scalarOrPerPoint(values)
values = values(:);
if numel(values) == 1
    value = values(1);
else
    value = values;
end
end

function tf = endpointsClose(x, y)
% A centerline whose ends meet within half a meter is treated as a closed
% circuit so the 3D ribbon and cone lines wrap seamlessly.
tf = hypot(x(1) - x(end), y(1) - y(end)) < 0.5;
end
