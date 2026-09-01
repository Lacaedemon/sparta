# Order stances: Orthogonal flags table, held-position leash, and forced-order tag

Status: **design drafted** -- defines the orthogonal stance flags dictionary, held-position leash dynamics, and forced-order tagging system adapted from 0 A.D. simulation components.
Builds on [#956](https://github.com/Lacaedemon/sparta/issues/956) and connects to [#953](https://github.com/Lacaedemon/sparta/issues/953), [#822](https://github.com/Lacaedemon/sparta/issues/822), and [`docs/orders-queue-design.md`](orders-queue-design.md).

## Problem Statement

Order-mode stances (`Hold`, `All-out attack`, `Pin down`, `Chase`, `Sweep routers`, etc.) were originally implemented as disparate `match` branches scattered across `Unit._think`, `UnitCombat`, and targeting subroutines.

This architectural shape has three critical drawbacks:

- **Hot-path branching proliferation**:
  Adding or tweaking stances requires modifying deep conditional trees in core movement and combat functions.

- **Implicit contracts**:
  Behavioral boundaries (e.g. when an auto-acquired target overrides an order vs. when a unit holds) were maintained implicitly by statement order rather than explicit data contracts.

- **Explicit vs. reactive order confusion**:
  Without an explicit `is_forced` tag, the simulation struggled to cleanly distinguish a player's deliberate target assignment from an autonomous defensive retaliation.

## Design Architecture

### 1. Orthogonal Stance Flags Table

Stances are expressed as a data dictionary (`STANCE_PROFILES`) containing orthogonal boolean and numeric properties:

| Stance | `target_visible` | `target_attackers` | `respond_chase` | `hold_ground` | `leash_radius_m` | `chase_beyond_vision` |
|---|---|---|---|---|---|---|
| `HOLD` | `false` | `true` | `false` | `true` | `0.0` | `false` |
| `STAND_GROUND` | `true` | `true` | `false` | `true` | `15.0` | `false` |
| `AGGRESSIVE` | `true` | `true` | `true` | `false` | `INF` | `true` |
| `PIN_DOWN` | `true` | `true` | `true` | `false` | `30.0` | `false` |
| `SWEEP_ROUTERS` | `true` (routing only) | `false` | `true` | `false` | `100.0` | `true` |

### 2. Three Unified Choke Points

Instead of ad-hoc branching, the simulation evaluates stance behavior at three standardized choke points:

1. **Acquisition Choke Point (`UnitTargeting.gd`)**:
   Determines candidate target eligibility based on `target_visible` and `target_attackers` flags.

2. **Response Choke Point (`UnitCombat.gd`)**:
   Executes the priority response chain (`respond_chase` -> `stand_ground` -> `hold_ground` -> `flee`).

3. **Abandon / Leash Choke Point (`Unit.gd`)**:
   Monitors distance from `held_position` inside the movement/arrival logic that `Unit.gd` already owns;
   when distance exceeds `leash_radius_m`, the unit breaks engagement and returns to `held_position`.

### 3. Forced Order Tagging (`is_forced`)

Every order in the unit order stream carries an explicit `is_forced: bool` field:

- **Forced (`is_forced = true`)**:
  Direct player input or high-priority script command.
  Autonomous reactions and opportunistic target swaps cannot override or preempt this order.

- **Unforced (`is_forced = false`)**:
  Auto-generated behavioral response (e.g. auto-acquiring a nearby attacker, skirmisher evasion).
  Can be freely preempted when tactical conditions or player orders dictate.

## Migration and Verification Strategy

1. **Phase 1 (Data Table & Architecture Documentation)**:
   Publish `docs/order-stances-flags-table-design.md` (this document) defining schemas and flags.

2. **Phase 2 (Choke Point Refactoring)**:
   Extract stance evaluations in `scripts/Unit.gd` into the three choke points reading `STANCE_PROFILES`.

3. **Phase 3 (Leash Anchor & Order Tagging)**:
   Record `held_position` on player move arrival and tag player orders with `is_forced = true`.
