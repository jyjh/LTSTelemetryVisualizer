# LTS Telemetry Visualizer (LTSViz)

MATLAB-native correlation and 3D replay tooling for the FSAE lap-time
simulator. LTSViz compares simulator MoTeC-style CSV exports with a real
MoTeC `.ld` log (or a normalized replay CSV) and produces:

- **A standalone 3D replay** — animated cars on the reference track with
  play/pause/scrub playback, chase/cockpit/orbit/top cameras, live
  pedal-steer telemetry, and synced speed/input strip charts. The HTML is
  fully self-contained (three.js is vendored) and works offline in any
  WebGL-capable browser.
- A Plotly-powered correlation report (trajectory overlay, speed, inputs,
  dynamics deltas) with a link to the 3D replay.
- The aligned comparison CSV, a summary JSON, and an optional MATLAB
  diagnostic figure.

## Setup

From the parent `lts` repository:

```matlab
addpath('external/LTSTelemetryVisualizer')
addpath(genpath('external/LTSTelemetryVisualizer/external/plotly_matlab'))
```

The Plotly MATLAB dependency is a nested Git submodule used by the
correlation report. The 3D replay does not need it: `external/three/
three.min.js` is vendored directly (r128 UMD build) and inlined into every
report, with a public CDN fallback if the vendored copy is removed.

## Quick start: 3D replay

The fastest way to see what the car is doing:

```matlab
ltsviz.render3D('SimCsv', 'exports/correlation_run.csv')
```

That opens with nothing but a simulation export — no track, no real log —
and writes `exports/scene3d_<timestamp>.html`. The viewer derives a track
ribbon from the simulated path when no track file is given.

The full form aligns a real MoTeC lap against the simulation on the
endurance circuit:

```matlab
result = ltsviz.render3D( ...
    'SimCsv', 'exports/correlation_run.csv', ...
    'RealMoTeCFile', 'data/lap5_raw.ld', ...
    'ChannelMap', 'config/motec/r25_real_channel_map.json', ...
    'TrackFile', 'tracks/endurance_track_grid_25ft_from_matlab_smoothed.mat');
web(result.htmlFile)
```

`RealReplayCsv` accepts an already-normalized replay CSV (from
`scripts/extract_motec_lap.py`) instead of a raw `.ld`. The blue car is
the simulation; the red translucent ghost is the aligned real run.

### Using the viewer

- **Cameras** — Orbit (drag to rotate, wheel to zoom, right-drag to pan),
  Chase, Cockpit, and Top views; press `C` to cycle.
- **Playback** — play/pause (`Space`), step (`←`/`→`, `Shift` for 10 s),
  speed 0.25×–4× (`↑`/`↓`), loop (`L`), restart (`R`). The scrubber and
  both strip charts are click-to-seek.
- **Telemetry** — live speed, throttle/brake bars, steering, lateral g,
  and the sim-vs-real path separation as the cars run.
- **Deep links** — append `?t=42.5&cam=chase&rate=0.5&play=0` to the file
  URL (or a served copy) to open at an exact moment, camera, and speed.
- **Toggles** — hide/show either car, trails, cones, and floating labels.

Body roll and pitch are *visual estimates* from the accelerometer channels
(small capped gains), not measured suspension data; the viewer notes this
in the telemetry panel.

## Full correlation report

```matlab
result = ltsviz.visualizeCorrelation( ...
    'SimCsv', 'exports/correlation_run.csv', ...
    'RealMoTeCFile', 'data/lap5_raw.ld', ...
    'ChannelMap', 'config/motec/r25_real_channel_map.json', ...
    'TrackFile', 'tracks/endurance_track_grid_25ft_from_matlab_smoothed.mat', ...
    'OutputHtml', 'exports/visualization_lap5.html')
```

This writes the correlation HTML, `<output>_3d.html` (the 3D replay;
pass `'SceneHtml', 'none'` to skip, or a path to relocate),
`<output>_aligned.csv`, `<output>_summary.json`, and (optionally, via
`'Visible', true`) a MATLAB diagnostic figure. The result struct includes
paths to every artifact, the scene payload, and the summary.

## Inputs

- **SimCsv** — MoTeC-style simulator export (the MotecLogGenerator
  convention) or any CSV exposing `time`/`distance`/`speed`/`x`/`y` (or
  GPS) channels. Channel resolution and unit conversion live in
  `ltsviz.readTelemetryCsv`.
- **RealMoTeCFile** — raw `.ld`; extracted through the parent project's
  `scripts/extract_motec_lap.py` pipeline using `ChannelMap`
  (`config/motec/r25_real_channel_map.json` by default), `Lap`, `LdxFile`,
  `PythonCommand`, and `SampleFrequencyHz`.
- **RealReplayCsv** — normalized replay CSV, when extraction was already
  done.
- **TrackFile** — `.mat` or `.csv` reference track. `ltsviz.loadTrack`
  reads centerline, per-point left/right widths, and the closed flag when
  present (the endurance track `.mat` has all of these) and the viewer
  extrudes the asphalt ribbon, edge lines, start line, and corner cones
  from them.

## Package layout

| Path | Role |
| --- | --- |
| `+ltsviz/render3D.m` | 3D-replay entry point (lean, no MATLAB figure) |
| `+ltsviz/visualizeCorrelation.m` | full correlation + 3D report entry point |
| `+ltsviz/prepareRuns.m` | shared sim/real/track loading |
| `+ltsviz/alignRuns.m` | initial-pose alignment of the real run |
| `+ltsviz/buildComparison.m` | common-axis interpolation of both runs |
| `+ltsviz/buildScene3D.m` | JSON payload for the 3D viewer |
| `+ltsviz/write3DHtml.m` | standalone HTML assembly |
| `+ltsviz/+assets/app3d.js`, `report3d.css` | the viewer application |
| `+ltsviz/writePlotlyHtml.m` | correlation report HTML |
| `external/three/` | vendored three.js r128 (see its README) |
| `tests/LTSVizTest.m` | unit tests (`runtests('tests')` with the package on the path) |

## Scope

The 3D replay is offline diagnostic tooling. It does not change simulator
physics, does not depend on Vehicle Dynamics Blockset or RoadRunner, and
does not force replay trajectories onto the reference track. Free-space
path divergence is treated as an important correlation signal and is shown
live as the sim-to-real path separation.
