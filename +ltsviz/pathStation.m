function station = pathStation(x, y, closed)
%PATHSTATION Cumulative path length for x/y samples.

if nargin < 3
    closed = false;
end
x = double(x(:));
y = double(y(:));
keep = isfinite(x) & isfinite(y);
x = x(keep);
y = y(keep);
if numel(x) < 2
    station = zeros(size(x));
    return;
end
if closed
    x = [x; x(1)];
    y = [y; y(1)];
end
station = [0; cumsum(hypot(diff(x), diff(y)))];
end
