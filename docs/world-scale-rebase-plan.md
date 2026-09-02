# Architectural plan: World scale rebase to 1 wu = 1 m

Status: **design drafted** -- outlines the architectural roadmap, migration workstreams, and validation strategy for rebasing Sparta's simulation scale from 20 wu/m to 1 wu = 1 m.
Builds on [#891](https://github.com/Lacaedemon/sparta/issues/891), [#440](https://github.com/Lacaedemon/sparta/issues/440), and [`docs/units-convention.md`](units-convention.md).
Also supersedes the near-term motivation previously tracked in [#892](https://github.com/Lacaedemon/sparta/issues/892).

Both prerequisites named above have already landed, independently of this plan.
The metric-authoring migration shipped first, so `WorldScale.WU_PER_M`, the
exact-value pins, and the units lint already exist as the scaffolding this
rebase needs.
The metric-alongside-world-units dump change also shipped.
That change already delivers the near-term motivation this plan originally cited.
So the remaining case for the rebase is the structural one: dissolving the wu/metre split outright, and the float32-precision headroom that dissolution buys.

## Executive summary

Currently, Sparta operates on a dual-scale convention.
The simulation runs in world units (wu) where `WorldScale.WU_PER_M = 20.0` (an 80m x 60m field is 1600 x 1200 wu), while authored constants and user-facing chrome display in metric metres.

Rebasing the simulation to **1 wu = 1 m** eliminates this split entirely:

- Every stored float in memory, simulation calculations, and state transcript dumps will read directly in standard metric units.

- Float32 precision is maximized over battlefield extents (positions ranging from 0 to 80 leave significantly more mantissa precision per millimetre than 0 to 1600).

- Constant expressions no longer require parse-time multiplication by `WU_PER_M`.

## Migration Workstreams

The rebase comprises three distinct workstreams:

### 1. Simulation Core and Constant Rebase

- Update `scripts/WorldScale.gd` so `WU_PER_M = 1.0`.

- Update all physical constants across `scripts/` so their world-unit values equal their metric values directly.
  This covers every script whose constants multiply by `WorldScaleRef.WU_PER_M` per `docs/units-convention.md`'s rule 1 (e.g. `Unit.gd`, `SoldierCombat.gd`, `SoldierSpatialHash.gd`, `UnitMorale.gd`).

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
   Use `tools/demo/capture-frames.sh` to compare rendered frames before and after the rebase, ensuring zero visual drift in troop positions and formations.
   Capture must run WITHOUT `--headless` and WITH `--rendering-driver opengl3`, since Movie Maker's frame writer needs a real renderer and `--headless` selects the dummy renderer that produces null/blank textures.
   On Linux CI, wrap the capture in `xvfb-run` for a display.
   `tools/demo/capture-frames.sh` and this repo's `CLAUDE.md` GDScript-quirks section both document the crash this avoids.

2. **Full Unit Test Verification**:
   Execute `./tools/check.sh test` across the full GUT suite (2,900+ `test_` functions across `test/unit/` as of 2026-09-01) to confirm all formation mathematics, collision solvers, and movement dynamics remain invariant.

3. **Transcript State Equivalence**:
   Verify that position vectors in `dump-state.sh` outputs match exactly (scaled 1:20) with previous runs.

4. **The website demo-diff workflow as the sim-side gate**:
   `.github/workflows/website-demo-diff.yml` dumps a per-tick sim-state transcript for every catalogued clip on each PR and posts the comparison against the PR's merge-base with its base branch;
   it reads sim state, never a drawn frame, and its own header rules render-layer regressions (chrome, LOD, draw order) out of scope.
   For this migration it is the check the tracking issue asks for on the simulation side:
   a correct rebase changes every world-unit field by the same factor and leaves the metric fields untouched, and any transcript that diverges otherwise names the scenario that broke.
   Step 3 is that comparison run by hand for one scenario while iterating;
   the workflow's full-catalog run is the acceptance gate for the sim, and step 1's frame capture is what covers the chrome the workflow cannot see.
