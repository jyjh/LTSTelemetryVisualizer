function summary = summarizeComparison(comparison, simRun, realRun, alignment, manifestFile)
%SUMMARIZECOMPARISON Create compact report metadata and metrics.

T = comparison.table;
summary = struct();
summary.created_at = datestr(now, 31);
summary.alignment_mode = comparison.mode;
summary.sim_file = simRun.path;
summary.sim_label = simRun.label;
summary.real_file = '';
summary.real_label = '';
if ~isempty(realRun)
    summary.real_file = realRun.path;
    summary.real_label = realRun.label;
end
summary.extract_manifest = manifestFile;
summary.alignment = alignment;
summary.samples = height(T);
summary.metrics = struct( ...
    'path_error_mean_m', meanFinite(T.path_error_m), ...
    'path_error_max_m', maxFinite(T.path_error_m), ...
    'speed_delta_mean_mps', meanFinite(T.speed_delta_mps), ...
    'speed_delta_max_abs_mps', maxFinite(abs(T.speed_delta_mps)), ...
    'yaw_rate_delta_max_abs_radps', maxFinite(abs(T.yaw_rate_delta_radps)), ...
    'lat_accel_delta_max_abs_g', maxFinite(abs(T.lat_accel_delta_g)), ...
    'brake_delta_max_abs_ratio', maxFinite(abs(T.brake_delta_ratio)), ...
    'throttle_delta_max_abs_ratio', maxFinite(abs(T.throttle_delta_ratio)));
summary.warnings = [simRun.warnings(:); collectWarnings(realRun)];
end

function warnings = collectWarnings(run)
if isempty(run)
    warnings = {'No real run supplied; report contains simulation only.'};
else
    warnings = run.warnings(:);
end
end

function value = meanFinite(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end

function value = maxFinite(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end
