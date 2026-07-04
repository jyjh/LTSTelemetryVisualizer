function [eastM, northM] = gpsToLocalMeters(latitudeDeg, longitudeDeg)
%GPSTOLOCALMETERS Convert WGS84 lat/lon to local ENU meters.
%
% Uses an equirectangular approximation around the first valid sample. That is
% accurate enough for FSAE track-scale visual diagnostics and avoids Mapping
% Toolbox or pyproj dependencies.

latitudeDeg = double(latitudeDeg(:));
longitudeDeg = double(longitudeDeg(:));
idx = find(isfinite(latitudeDeg) & isfinite(longitudeDeg), 1, 'first');
eastM = NaN(size(latitudeDeg));
northM = NaN(size(latitudeDeg));
if isempty(idx)
    return;
end

earthRadiusM = 6378137.0;
lat0 = latitudeDeg(idx) * pi / 180;
lon0 = longitudeDeg(idx) * pi / 180;
lat = latitudeDeg * pi / 180;
lon = longitudeDeg * pi / 180;

eastM = (lon - lon0) .* cos(lat0) * earthRadiusM;
northM = (lat - lat0) * earthRadiusM;
end
