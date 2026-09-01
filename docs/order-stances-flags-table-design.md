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

Stances are expressed as a data dictionary (`STANCE_PROFILES`) containing orthogonal boolean and numeric properties.
The rows below map the five existing `OrderMode` stances named in the Problem Statement
(`HOLD`, `ALL_OUT_ATTACK`, `PIN_DOWN`, `CHASE`, `SWEEP_ROUTERS` -- see `scripts/Battle.gd`'s `OrderMode` enum);
the concrete cell values are provisional, to be pinned down by the Phase 2 behavior-preservation check (see Migration and Verification Strategy):

| Stance | `target_visible` | `target_attackers` | `routing_only` | `respond_chase` | `hold_ground` | `leash_radius_m` | `chase_beyond_vision` |
|---|---|---|---|---|---|---|---|
| `HOLD` | `false` | `true` | `false` | `false` | `true` | `0.0` | `false` |
| `ALL_OUT_ATTACK` | `true` | `true` | `false` | `true` | `false` | `INF` | `false` |
| `PIN_DOWN` | `true` | `true` | `false` | `false` | `true` | `30.0` | `false` |
| `CHASE` | `true` | `true` | `false` | `true` | `false` | `INF` | `true` |
| `SWEEP_ROUTERS` | `true` | `false` | `true` | `true` | `false` | `100.0` | `true` |

One caveat on the `SWEEP_ROUTERS` row: the shipped acquisition path prioritizes routing targets but deliberately falls back to ordinary targeting when no router is available (preserving the relentless-pursuit persistence invariant in `scripts/UnitTargeting.gd`),
so a strict reading of `routing_only = true` under-describes it;
Phase 2 must either encode that fallback in how the acquisition choke point consumes `routing_only`, or split the fallback into its own flag.

Stance-specific combat modifiers (`PIN_DOWN`'s slower cadence and exposure window, `ALL_OUT_ATTACK`'s hit bonus and defense penalty) are cadence/damage tuning, not acquisition/response/leash behavior;
they stay as per-stance constants in `scripts/Unit.gd` / `scripts/UnitCombat.gd` rather than gaining columns here.

### 2. Three Unified Choke Points

Instead of ad-hoc branching, the simulation evaluates stance behavior at three standardized choke points:

1. **Acquisition Choke Point (`UnitTargeting.gd`)**:
   Determines candidate target eligibility based on the `target_visible`, `target_attackers`, and `routing_only` flags.

2. **Response Choke Point (`UnitCombat.gd`)**:
   Executes the priority response chain over the table's own flags (`respond_chase` -> `hold_ground`).
   0 A.D.'s fuller chain also carries stand-ground and flee responses;
   in Sparta, fleeing is not a stance behavior at all: the morale threshold in `UnitCombat.gd`'s casualty accounting triggers the rout, and `Unit.gd`'s rout path executes it,
   and stand-ground collapses into `hold_ground` with a `leash_radius_m` of `0.0`.

3. **Abandon / Leash Choke Point (`Unit.gd`)**:
   Monitors distance from `held_position` inside the movement/arrival logic that `Unit.gd` already owns;
   when distance exceeds `leash_radius_m`, the unit breaks engagement and returns to `held_position`.
   The same abandon decision reads `chase_beyond_vision`:
   a stance with it `false` abandons a chase once the quarry leaves vision range,
   while a `true` stance keeps riding the quarry down.

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
   Extract the stance evaluations scattered across `scripts/Unit.gd`, `scripts/UnitCombat.gd`, and `scripts/UnitTargeting.gd`
   into the three choke points reading `STANCE_PROFILES`.
   The mapping must be byte-for-byte behavior-preserving:
   the proof is a per-tick state-dump diff on the existing stance demos (the standard sim-equality technique),
   which is also what pins the provisional cell values in the table above to the current shipped behavior.

3. **Phase 3 (Leash Anchor & Order Tagging)**:
   Record `held_position` on player move arrival and tag player orders with `is_forced = true`.
