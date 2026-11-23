# Graphics settings and benchmarks

The project targets Godot 4.7.2 Forward+ and Windows Desktop. Benchmark runs use a fresh in-memory game and do not load, back up, or write `save.json`.

## Run from Windows

Export the **Windows Desktop** preset to `build/windows/Frontier.exe`. From the repository root, run:

```bat
build\windows\Frontier.exe -- --benchmark=flythrough --preset=high --bench-seconds=60 --bench-warmup=5
```

Routes are `flythrough`, `walk`, and `factory`. Omit `--preset` to use the saved graphics preset. The preset override is in-memory only and is never written to `settings.cfg`. `--bench-seconds` defaults to 60; `--bench-warmup` defaults to 5.

`tools\benchmark\run_benchmarks.bat` runs all three routes at High. Pass `all` to run each route at Low, Medium, High, and Ultra:

```bat
tools\benchmark\run_benchmarks.bat all
```

Godot 4.7.2 forwards custom exported-game arguments after the `--` separator into `OS.get_cmdline_user_args()`. The parser also accepts raw `++benchmark=...`, `++preset=...`, `++bench-seconds=...`, and `++bench-warmup=...` arguments from `OS.get_cmdline_args()`.

Results are written as one JSON summary and one per-frame CSV under `user://benchmarks`. On Windows this project name resolves to:

```text
%APPDATA%\Godot\app_userdata\Factory\benchmarks
```

The batch runner opens that folder after completing its runs.

## Metrics

- **Average FPS** is sample count divided by total sampled frame time.
- **1% low FPS** is the inverse of the mean frame time among the slowest `ceil(1% of frames)`; **0.1% low** uses the slowest `ceil(0.1%)`.
- **p50/p95/p99** are nearest-rank frame-time percentiles. Hitch records are strictly greater than 33.3 ms or 50 ms and include sample timestamp and route progress.
- Warmup frame count and maximum are reported separately; warmup is intended to expose shader-compilation hitches without including them in steady-state statistics.
- CPU process and physics times come from Godot performance monitors. GPU and render CPU times use `RenderingServer` viewport render-time measurement.
- VRAM and static memory are Godot monitor values. Static memory is not total system RAM.
- Startup reports engine-start-to-main-ready, terrain build, and foliage build times. System metadata includes OS/version, processor/count, adapter/vendor/API, resolution, render scale, preset, and Godot version.
- Godot does not expose CPU or GPU utilization percentages. The JSON writes both values as `null` with an explanatory note. For Windows utilization data, run [PresentMon](https://github.com/GameTechDev/PresentMon) alongside the game and align its capture with the benchmark timestamps.

CPU-only software-renderer results (for example, lavapipe/llvmpipe) are useful for correctness and CPU-side comparisons but are **not representative of an RTX or other hardware GPU**. Do not infer GPU performance from them.

## Graphics options

F10 opens the settings panel; Apply stores settings in `user://settings.cfg`, except when a command-line preset override is active. F3 toggles the performance overlay.

The presets set the shadow atlas/distance, soft-shadow filter, AO/fog toggles, foliage density, grass radius, tree view distance, and antialiasing. Low uses 2048/180 m, 0.5 foliage, 35 m grass and FXAA; Medium uses 4096/300 m, SSAO, 0.75 foliage, 48 m grass and TAA; High uses 4096/450 m, SSAO+SSIL, volumetric fog, 1.0 foliage, 60 m grass and TAA; Ultra uses 8192/700 m, the High effects, 1.25 foliage, 75 m grass and TAA at 1.0 render scale. The remaining fields are editable under Custom.

Window mode, VSync, FPS cap, render scale/scaling mode, antialiasing, shadow filtering/distance/splits, post-processing toggles, grass radius/density, and tree view distance apply immediately. Tree/scatter density is rebuilt at startup; changing it requires restarting the game to rebuild tree and scatter instances.
