# Specification: Fix Formation Shape Softening in Curved March & Dense Battle (Issue #1422)

## Overview
PR #1415 introduced `MARCHING_CORRIDOR_PROXIMITY_MULT` (4.5x file pitch) to allow soldiers catching up after melee knockback to arrive directly into their formation slots without triggering a counterproductive flank-and-rear corridor detour. However, applying this wider direct-arrival threshold unconditionally during any march (`_approach_velocity != 0`) softened the formation shape during curved marching (`funnel_lanes`) and dense chaotic combat (`showcase`), where the corridor detour is necessary for smooth rank/file geometry during turns.

This track refines the `_corridor_to_slot` activation logic so that the wider direct-arrival behavior specifically targets lagging/knocked-back soldiers while preserving proper corridor smoothing during active curved marches and turns.

## Functional Requirements
1. **Targeted Corridor Bypass:** Refine `_corridor_to_slot` in `scripts/SoldierSteering.gd` (or relevant steering script) to gate the wider `MARCHING_CORRIDOR_PROXIMITY_MULT` threshold on displacement vector alignment and turning dynamics, ensuring soldiers in an actively turning formation maintain their corridor pathing.
2. **Preserve Post-Melee Catch-up:** Ensure knocked-back or displaced soldiers recovering from melee engagement continue to catch up cleanly without being flung by unneeded detours (retaining PR #1415's fix).
3. **Stationary & Linear March Stability:** Ensure stationary reform and straight-line marches retain identical high-fidelity formation cohesion.

## Non-Functional & Quality Requirements
- **Determinism:** All logic must maintain 100% deterministic simulation across seeds and replay runs.
- **Performance:** Zero measurable regression in computation cycles per tick; no per-soldier square-root operations in hot steering loops (`distance_squared_to`).
- **Code Standards:** Plain-ASCII comments and strings, caller-configurable thresholds, no bare magic literals.

## Acceptance Criteria
1. **Demo Verification (`funnel_lanes`):** `demos/inputs/funnel-hug-lanes.json` runs with `shape_residual` strictly within passing thresholds across declared check ticks (`8, 120, 540, 700, 860, 1000, 1080`).
2. **Demo Verification (`showcase`):** `demos/showcase.json` runs without generating new `overlap` defects on `uid8`.
3. **Unit Tests:** All existing unit tests pass via `./tools/check.sh test` without regression, including PR #1415 regression cases.
4. **CI & Lint:** `tools/check.sh validate test chars comments units patch_coverage` passes clean.

## Out of Scope
- Architectural restructuring of formation slot ownership (tracked under #547).
- Visual presentation or 3D renderer changes.
