# Implementation Plan: Fix Formation Shape Softening in Curved March & Dense Battle (Issue #1422)

Refine `_corridor_to_slot` steering behavior to preserve corridor detours during curved marching while retaining direct-arrival for post-melee displaced soldiers.

## User Review Required
> [!NOTE]
> This fix adjusts steering thresholds during marching state to eliminate shape residual spikes without compromising post-melee soldier recovery.

## Proposed Changes

### Phase 1: Investigation & Reproducing Tests
- [ ] Task: Trace corridor routing and capture baseline defect metrics
  - [ ] Run state dump on `demos/inputs/funnel-hug-lanes.json` at declared ticks and record `shape_residual` values
  - [ ] Run state dump on `demos/showcase.json` and record `uid8` overlap values
- [ ] Task: Author failing / boundary unit tests for curved march vs catch-up corridor gating
  - [ ] Add unit tests in `test/unit/test_soldier_steering.gd` verifying corridor entry behavior under active formation angular turn vs straight-line lagging displacement
  - [ ] Confirm tests exercise the boundary condition
- [ ] Task: Phase 1 Verification & Checkpoint (Refer to workflow.md)

### Phase 2: Implementation & Steering Refinement
- [ ] Task: Refine `_corridor_to_slot` in steering logic
  - [ ] Implement turning rate / displacement vector alignment check for `MARCHING_CORRIDOR_PROXIMITY_MULT` gating
  - [ ] Ensure all distance comparisons use `distance_squared_to`
  - [ ] Keep constants caller-configurable in `SoldierSteering.gd`
- [ ] Task: Verify unit tests pass (Green phase)
  - [ ] Run `./tools/check.sh test` and confirm all steering and unit tests pass
- [ ] Task: Phase 2 Verification & Checkpoint (Refer to workflow.md)

### Phase 3: Demo Defect Verification & Quality Assurance
- [ ] Task: Verify demo state dumps
  - [ ] Re-run `funnel_lanes` state dump and confirm `shape_residual` is back within passing bounds (< 18.0)
  - [ ] Re-run `showcase` state dump and confirm `uid8` has no new overlap defects
  - [ ] Verify post-melee catch-up test from #1415 still passes
- [ ] Task: Run full validation suite
  - [ ] Run `./tools/check.sh validate test chars comments units patch_coverage`
- [ ] Task: Phase 3 Verification & Checkpoint (Refer to workflow.md)
