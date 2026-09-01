# Architectural plan: World scale rebase to 1 wu = 1 m

Status: **design drafted** -- outlines the architectural roadmap, migration workstreams, and validation strategy for rebasing Sparta's simulation scale from 20 wu/m to 1 wu = 1 m.
Builds on [#891](https://github.com/Lacaedemon/sparta/issues/891), [#440](https://github.com/Lacaedemon/sparta/issues/440), and [`docs/units-convention.md`](units-convention.md).

## Executive summary

Currently, Sparta operates on a dual-scale convention: the simulation runs in world units (wu) where `WorldScale.WU_PER_M = 20.0` (an 80m x 60m field is 1600 x 1200 wu), while authored constants and user-facing chrome display in metric metres.

Rebasing the simulation to **1 wu = 1 m** eliminates this split entirely:

- Every stored float in memory, simulation calculations, and state transcript dumps will read directly in standard metric units.

- Float32 precision is maximized over battlefield extents (positions ranging from 0 to 80 leave significantly more mantissa precision per millimetre than 0 to 1600).

- Constant expressions no longer require parse-time multiplication by `WU_PER_M`.

## Migration Workstreams

The rebase comprises three distinct workstreams:

### 1. Simulation Core and Constant Rebase

- Update `scripts/WorldScale.gd` so `WU_PER_M = 1.0`.

- Update all physical constants across `scripts/` (e.g. `Unit.gd`, `Soldier.gd`, `Formation.gd`, `FormUp.gd`) so their world-unit values equal their metric values directly.

- Update all exact-value unit test pins in `test/unit/` to reflect the 1 wu = 1 m ground truth.

### 2. Rendering Chrome, Camera, and Screen-Space Separation

Quantities that are purely visual or screen-space must be decoupled from the 20x coordinate scaling:

- **Camera Zoom & Pan**:
  Multiply default camera zoom by 20.0 (and adjust zoom limits / pan speeds) so that the rendered battlefield view remains pixel-identical.

- **HUD & Selection Chrome**:
  Decouple `draw_string` font sizes, `draw_line` widths, formation box outlines, and selection grip radii into viewport/screen coordinates instead of world coordinates.

- **LOD Thresholds**:
  Scale zoom-dependent level-of-detail triggers (`LOD_ZOOM_OUT`) accordingly.

### 3. Content Flag Day and Replay Versioning

Because coordinate magnitudes will divide by 20.0:

- **Replay Format**:
  Increment `Replay.FORMAT_VERSION` to cleanly reject legacy recordings that were captured at 20 wu/m.

- **Input Demos & Scenarios**:
  Batch-migrate all click coordinates in `demos/inputs/*.json` and scenario spawn anchors by dividing positions by 20.0.

- **State Dumps & Baseline Checks**:
  Regenerate all reference demo state dumps using `tools/demo/dump-state.sh`.

## Verification and Safety Strategy

1. **Pixel-Identical Visual Regression**:
   Use `tools/demo/` frame-capture under `xvfb-run` to compare rendered frames before and after the rebase, ensuring zero visual drift in troop positions and formations.

2. **Full Unit Test Verification**:
   Execute `./tools/check.sh test` across the full GUT suite (2700+ tests) to confirm all formation mathematics, collision solvers, and movement dynamics remain invariant.

3. **Transcript State Equivalence**:
   Verify that position vectors in `dump-state.sh` outputs match exactly (scaled 1:20) with previous runs.
