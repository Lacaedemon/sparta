# Technology Stack: Sparta

## Core Engine & Language
- **Engine:** Godot Engine 4.7.x Standard (Standard binary, NOT C# / .NET)
- **Primary Language:** GDScript
- **Rendering Driver:** `gl_compatibility` (OpenGL 3.0 compatible renderer)
- **Viewport Resolution:** 1280x720 base resolution with canvas_items stretch mode

## Simulation & Architecture Patterns
- **Simulation Loop:** Fixed-tick deterministic battle simulation with seed-based pseudo-random number generation (`Replay.gd`).
- **Spatial Indexing:** Custom spatial hashing (`SpatialHash.gd`, `SoldierSpatialHash.gd`) for O(1) proximity lookups and collision queries.
- **Entity Organization:** Two-tier simulation model (regiment-level steering and formations with soldier-level kinematic bodies and physical collision).

## Testing, Verification & Quality Assurance
- **Unit Testing Framework:** GUT (Godot Unit Test 9.3.x) located in `test/unit/` with `pre_run_hook.gd` and `post_run_hook.gd`.
- **Linter & Formatter:** GDToolkit 4.5.0 (`gdlint`, `gdformat`).
- **Validation Pipeline:** `tools/check.sh` running Godot import checks, GUT tests, character typography verification, comment audits, and patch coverage analysis.
- **Recording & Visual Verification:** Headless state dumps (`tools/demo/dump-state.sh`), Movie Maker frame capture via Xvfb (`demos/`).

## Documentation & Publishing
- **Doc Generator:** Quarto (`website/`) rendered to GitHub Pages.
- **Licensing Compliance:** CC0 asset sourcing policy.
