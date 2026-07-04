# LTS Telemetry Visualizer

MATLAB-native correlation visualization for the FSAE lap-time simulator.

This package compares simulator MoTeC-style CSV exports with either a normalized
correlation replay CSV or a real MoTeC `.ld` log imported through the parent
project's existing `scripts/extract_motec_lap.py` pipeline. It creates a MATLAB
diagnostic figure and a Plotly-powered HTML report.

## Setup

From the parent `lts` repository:

```matlab
addpath('external/LTSTelemetryVisualizer')
addpath(genpath('external/LTSTelemetryVisualizer/external/plotly_matlab'))
```

The Plotly MATLAB dependency is included as a nested Git submodule so the
visualizer does not carry a custom 3D rendering stack. If Plotly's local
JavaScript bundle is unavailable, generated reports fall back to the public
Plotly CDN.

For fully offline HTML, add Plotly MATLAB to the path once and run:

```matlab
getplotlyoffline('https://cdn.plot.ly/plotly-2.35.2.min.js')
```

That creates the Plotly MATLAB offline bundle under `~/.plotly/plotlyjs/`, which
this package will embed in future reports.

## Usage

Real MoTeC log:

```matlab
ltsviz.visualizeCorrelation( ...
    'SimCsv', 'exports/correlation_run.csv', ...
    'RealMoTeCFile', 'data/lap5_raw.ld', ...
    'ChannelMap', 'config/motec/r25_real_channel_map.json', ...
    'TrackFile', 'tracks/endurance_track_grid_25ft_from_matlab_smoothed.mat', ...
    'OutputHtml', 'exports/visualization_lap5.html')
```

Existing normalized replay CSV:

```matlab
ltsviz.visualizeCorrelation( ...
    'SimCsv', 'exports/correlation_run.csv', ...
    'RealReplayCsv', 'exports/correlation_run_replay.csv', ...
    'OutputHtml', 'exports/visualization_lap5.html')
```

The result struct includes paths to the HTML report, aligned CSV, summary JSON,
and the MATLAB figure handle.

## Scope

V1 is offline diagnostic tooling. It does not change simulator physics, does not
depend on Vehicle Dynamics Blockset or RoadRunner, and does not force replay
trajectories onto the reference track. Free-space path divergence is treated as
an important correlation signal.
