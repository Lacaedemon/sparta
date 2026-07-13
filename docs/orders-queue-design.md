# Design note: unified orders queue

Status: **in implementation — phases 1–3 landed** (the `Order` type + queue +
apply-once, the movement-maneuver migration, and the transition/relief/waypoint
absorption); phases 4–5 (the guard vocabulary and the transcript's remaining
gaps) are implemented and in review (#525, #526). This
note consolidates the design from #516 (and its refinement comments) into one
spec, and lays out the phased implementation plan tracked by the phase issues
linked below.

The goal: model **every player-issued command as one polymorphic `Order`**, held
in a single **orders queue** on `Unit`. `current_order` (the head of the queue)
is what the unit is doing now; it drives execution and subsumes the scattered
maneuver flags that hold that state today.

## Motivation

A unit's "what is it doing / what will it do next" is currently smeared across
many ad-hoc fields:

- move target plus a separate waypoint/append list,
- `_pending_march_target`,
- the maneuver in-progress flags (`_wheel_target`, `_engage_turn_target`, the
  conversio / quarter-turn in-progress state),
- `order_mode`, `formation_mode` transitions, and more.

Three problems follow from that spread.

**No single source of truth.** Inference logic drifts from what the code
actually does. The conversio-vs-centre-pivot ambiguity that made #465 hard to
verify is a direct symptom: an about-face and a 180° centre-pivot both read as
`state: MOVING`.

**The transcript can't see the maneuver.** The machine-readable state transcript
(#500 / #501 / #507) records `state`, `formation`, `order_mode`, position,
facing, morale, and the per-soldier summary — but *not* which maneuver a unit is
executing (#515), because no field authoritatively holds it. So a correct
conversio and the exact bug it was meant to replace look identical in the dump.

**A whole class of double-apply bugs.** `Battle.gd` applies every order twice —
once immediately for zero-latency feedback, and again when the next physics tick
drains `_pending_orders` (#518). Any non-idempotent order path is corrupted by
the second apply reading state the first apply just armed. This has already
produced the move-to-rear about-face aborting mid-turn and centre-pivoting
(#517), and the arrow-nudge travelling a few pixels instead of the full
`NUDGE_DISTANCE` (#521). Wheel, file-double, and formation/spacing transitions
are all exposed to the same hazard.

Adding a new command today means threading new flags through several code paths.

## The model

### Order + orders queue + current_order

`Unit` holds an `orders` queue of `Order` values. `current_order` is the head:
the order the unit executes this tick. Completed orders leave the queue; the
next order becomes current. This replaces the move-only waypoint list and every
in-progress maneuver flag with one structure.

Queue operations preserve the gestures that exist today:

- **append** (shift-click waypoint) — add to the tail,
- **replace-current** (plain order) — clear and set head,
- **insert-next** — splice ahead of the tail,
- **clear**.

Some orders are instantaneous; some occupy the unit for N ticks. Some are
interruptible, some not. Each subtype encodes its own duration and
interruptibility.

### Verbs vs modes

The design splits cleanly into two layers.

**Orders are verbs.** They are queue entries that execute and complete: move,
wheel, attack, "form testudo".

**Modes are durable nouns.** They are persistent `Unit` state that a completed
order writes: `formation_mode`, `spacing`, `active_weapon`, `stance`. A
transition order (form testudo / change spacing / switch weapon) executes like
any other order — possibly over a transition time — and on completion writes its
mode. The mode then stays as queryable `Unit` state until a later order changes
it.

This split is what keeps the transcript honest for free: it already serializes
`state` / `formation` / `order_mode`, so it records **both** the live
order/queue **and** the resulting modes with no special-case dump code.

### Taxonomy

One queue, many subtypes. GDScript is single-inheritance `class_name`, so the
hierarchy stays shallow — a tagged-record / enum-plus-data approach may beat a
deep class tree in places (evaluate during phase 1, per the avoid-nesting
default).

| Order (verb) | Kind | Writes mode | Notes |
|---|---|---|---|
| `MoveOrder` | movement | — | carries an **execution style** (direct march / about-face-conversio / sidestep) chosen by geometry — an about-face is the execution style of a rear move, not a separate order |
| `WheelOrder` | movement | — | pivot the line about an end |
| `QuarterTurnOrder` | movement | — | 90° facing change in place |
| `FileDoubleOrder` | movement | — | deepen / widen the formation (duplicatio / explicatio) |
| `NudgeOrder` | movement | — | short sidestep / backstep, holds facing |
| `AttackOrder` | targeting | — | terminates when the target dies |
| `FormationOrder` | transition | `formation_mode` | tight / loose / square / shield-wall / testudo |
| `SpacingOrder` | transition | `spacing` | open / close order |
| `StanceOrder` | transition | `stance` | hold / cycle-charge (and the intra-unit rank-relief mode toggle — see below) |
| `SwitchWeaponOrder` | transition | `active_weapon` | future: pike↔sword, javelin↔sword |
| `RelieveUnitOrder` | targeted action | — | **inter-unit** relief: a fresh unit passes through / replaces a tired front-line ally; the order names the ally to relieve, and the response-delay + ward become the order's own execution state |

**Waypoints are absorbed, not preserved alongside.** The current waypoint/append
list *is* a proto-orders-queue for moves — a waypoint already is a queued move.
Unifying just replaces the bespoke move-only list with the general queue; the
append gesture is identical to the player. The codebase already half-built this
pattern (a move waypoint queue, then maneuvers and relief bolted on separately
as flags); the unified queue finishes it. Net: fewer moving parts after the
refactor, not more.

**Relief is two distinct behaviors — keep them separate.** Today relief runs
through `_relief_partner` links on `Unit`, managed by `UnitRelief.gd` — a single
mechanism that conflates two things we want to model differently. The order/mode
split cleaves them cleanly:

- **Inter-unit relief is an order.** One unit relieving another — a fresh unit
  passes through or replaces a tired front-line ally — is a targeted queue action
  (`RelieveUnitOrder`) that names the ally to relieve. Its response-delay and ward
  become the order's own execution state. This is definitely an order, not a mode.
- **Intra-unit rank-relief is a mode.** Individuals within a unit relieving their
  *own* unit's front line — rear ranks rotating forward to the fighting line — is
  a durable intra-unit behavior, so it belongs in the mode layer (a reactive /
  ROE-style mode toggled by a `StanceOrder`), not a queue entry. It is the same
  rank-cycle recovery that makes routs nearly unreachable in #529 — so whether
  the mode is on, and how strong its recovery is, is the knob that issue turns.

Modeling these two separately (an order for one, a mode for the other) is the
right resolution of the current single-mechanism `_relief_partner` / `UnitRelief`
relief.

**Support-ward is the one real judgement call.** "Guard unit Y until told
otherwise" may fit better as a durable *assignment mode* (like formation/stance)
than as a queue entry, or as a standing `SupportOrder`. Decide case-by-case
during phase 3.

## Composability

Orders compose at three carefully-separated levels. The first two are in; the
third is out by default.

### 1. Intra-order phasing (the core)

An `Order` carries its own choreography as internal phases — a small
deterministic state machine — not as separate queue entries. The canonical case
is the move-to-rear: **phase 1 conversio (turn in place) → phase 2 reform (the
ranks re-square to the new heading so a full rank fronts it; deferred to
arrival — or skipped when there is nothing to bring forward — for an order
issued without the reform-before-move drill) → phase 3 march**.

This is both the clean model and the fix for the #517 / #518 bug class. Today the
about-face and the march are dispatched as separate state mutations that race
through the immediate-plus-drain double-apply, and the second apply cancels the
conversio mid-turn. Modeled as one phased order, the phases advance once per tick
deterministically; there is no second dispatch to lose. **Composition inside a
single queue entry is both the model and the bug fix.**

### 2. Macro expansion (a thin layer)

A higher-level command expands into a *sequence of primitive orders appended to
the flat queue* — e.g. a flank maneuver → wheel, advance, attack — tagged with a
group id so cancelling the macro clears its not-yet-executed children. This gives
reuse and compound player commands **without** a persistent tree: the executed
structure stays flat, so `current_order` is always a single legible primitive in
the transcript.

The grouping itself is `Unit.enqueue_macro(steps: Array[Order]) -> int`: it stamps
every step with a fresh `Order.macro_id` and appends each in turn, so the existing
queue/promotion machinery runs them exactly like any other queued sequence.
`Unit.cancel_macro(macro_id)` drops the macro's not-yet-executed remainder from
the queue, leaving a step already in flight (the currently-executing order)
untouched -- interrupt that with `set_current_order()`/`clear_orders()` instead.
No maneuver expands itself into a macro yet; that is left to whatever combo a
future command builds on top of `enqueue_macro`.

### 3. No deep order-tree / behavior-tree

Avoid by default. It is more machinery than the domain needs, harder to serialize
deterministically (it undercuts the "what is it doing now" legibility that
motivates the whole design), and it cuts against the avoid-nesting default. Adopt
it only if genuinely hierarchical reactive behavior becomes a real need.

### Parallel composition is the order/mode split, not nesting

"March while in testudo" = a `MoveOrder` executing while `formation_mode =
TESTUDO`, a durable mode set by an earlier order. Concurrency lives in the mode
layer. That is precisely what keeps a nested tree from being needed.

## Conditional logic

Orders support conditional logic in three tiers, deliberately constrained so the
queue stays deterministic and transcript-legible. Arbitrary if/else is the
"deep tree" trap in another costume, and is out of the core.

### 1. Terminal conditions (explicit)

Every order already ends on a condition: move → reached target; attack → target
dead; hold → timer. Make the terminal condition a **first-class field** of the
order, not special-cased logic. This enables "advance UNTIL contact, then
attack" as `MoveOrder{terminal: contact}` → `AttackOrder`. Condition-driven queue
advancement is just the self-terminating form of the phased / macro composition
above.

### 2. Guards from a bounded, enumerated vocabulary

An order or queue slot may carry a guard — "advance to the next order WHEN
\<condition\>" — drawn from a small closed deterministic set:

`enemy-in-range`, `contact-made`, `morale-below-X`, `ally-exhausted`,
`ticks-elapsed`, `flanked`, …

This covers "hold UNTIL in range THEN fire" without free-form code. The closed
vocabulary is the guardrail: composable, not Turing-complete.

### 3. Standing conditional behavior = the mode layer

Most "conditional orders" are really rules-of-engagement / stance: HOLD ("don't
chase unless attacked"), cycle-charge / caracole (#472), "fire at will in range".
These are durable **reactive modes** that modify how orders execute — the same
layer as `formation_mode`, per the order/mode split. The existing `order_mode`
enum (`HOLD` / `CYCLE_CHARGE` / `SUPPORT` / …) is already a crude version. Do NOT
encode these as if/else inside every order.

### Out of the core: arbitrary reactive branching

"If flanked form square else advance" is a reactive AI layer *above* the queue
that reissues and reorders commands — it edits the plan; it is not an `if`
embedded in each order. Reactivity mutates a still-flat, still-deterministic
queue.

## Two invariants

Conditionals — indeed the whole design — rest on two hard constraints. Break
either and the rest falls apart.

**Determinism.** Every condition and every order is a pure function of
*serialized* sim state, evaluated in the sim step. No wall-clock, no unseeded RNG
(cf. the #497 flake). Same inputs → same branch on replay. Orders are set and
advanced deterministically in the sim step, identical on replay.

**Transcript legibility.** The dump records the active order AND its active phase
AND its pending / unmet condition — e.g. `MoveToRear: conversio` vs `MoveToRear:
march`, or `Hold: until enemy_in_range`. A phased or conditional order is
verifiable by a direct read, not by inferring intent from motion. This is
strictly better than the flat maneuver label #515 asked for, because the phase
boundary itself is visible — conversio-vs-pivot verification becomes a one-field
read.

## How the transcript records it

Because `current_order` is a real field and modes are real `Unit` state, the
transcript records the unit's plan with no special-case dump code:

- `current_order` — the head primitive (e.g. `MoveOrder`, `WheelOrder`),
- its **active phase** when phased (e.g. `MoveToRear: march`),
- its **pending terminal condition / guard** when conditional (e.g. `Hold:
  until enemy_in_range`),
- the durable **modes** (`formation_mode`, `spacing`, `active_weapon`, `stance`),
  set by completed orders and already serialized today,
- optionally the queue tail (the pending orders) for full plan legibility.

This resolves #515 as a side effect: the explicit-maneuver field it asks for is
just `current_order` plus its phase, so #515 becomes phase 1 of this work rather
than a separate bolt-on.

## Phased implementation plan

Do this phased, not big-bang. Each phase drops the flags it subsumes as it
migrates them, so the flag spread shrinks monotonically. Land after #497 (the
spring purge) so the refactor is not fighting in-flight `Unit.gd` changes.

Every phase must hold both invariants (determinism on replay; the transcript
stays legible) and must preserve every existing behavior it touches
(append/waypoint, relief, HOLD, formation transitions).

### Phase 1 — `Order` + orders queue + `current_order` (apply-once)

**Scope.** Introduce the `Order` value type, the `orders` queue on `Unit`, and
`current_order` with phase support. Make each order **apply exactly once** in the
sim step — the queue advances deterministically per tick, retiring the immediate
+ tick-drain double-apply. Wire `current_order` (+ its phase) into the
transcript.

**Subsumes.** The move-only waypoint/append list becomes the queue; #515's
explicit-maneuver field becomes `current_order` + phase.

**Resolves.** The #518 double-apply class at its root — apply-once is the whole
point. Phase 1 **coordinates with the in-flight #518 fix**: that short-term fix
is effectively this phase's apply-once slice landing first, and the queue then
formalizes it (single source of truth, one apply site). Do not duplicate the fix;
build the queue on top of it.

**Determinism / replay risks.** The apply-once cutover changes *when* an order's
effect first lands (tick boundary instead of immediately-plus-next-tick), so
existing replays and demo transcripts must be re-verified tick-by-tick, not just
by final position.

**Done-check.** Orders route through one apply site; `current_order` + phase
appear in the transcript; a scripted-input replay of an existing maneuver
produces the same body positions tick-by-tick as before (minus the spurious
second apply); the double-apply reproduction from #518 no longer fires.

### Phase 2 — migrate movement maneuvers onto the queue

**Scope.** Move `MoveOrder` (with geometry-chosen execution style),
`WheelOrder`, `QuarterTurnOrder`, `FileDoubleOrder`, and `NudgeOrder` onto the
queue. Model the move-to-rear as a phased order (conversio → march).

**Subsumes.** `_wheel_target`, `_engage_turn_target`, the conversio /
quarter-turn in-progress state, `_pending_march_target`, and the nudge state —
all dropped as each migrates.

**Resolves / verifies.** The phased move-to-rear fixes the #517 centre-pivot; the
apply-once queue plus phasing fixes the #521 nudge under-travel. Both become
tick-by-tick transcript checks.

**Determinism / replay risks.** Execution-style selection must be a pure function
of geometry and serialized state (no frame-timing dependence). Re-verify every
migrated maneuver against its recorded transcript.

**Done-check.** Each movement maneuver runs off `current_order`; the subsumed
flags are deleted; the #517 conversio holds bodies frozen through the full turn
and the #521 nudge translates the centroid by the full `NUDGE_DISTANCE`, both
confirmed in the transcript.

**As implemented (#523).** The in-place turns and the wheel keep their execution
state on the Order itself (`turn_target` / `turn_start_facing` / `pivot`), and a
phased rear move carries its recorded reform choice and parks its march in
`target_pos`; `_wheel_target`, the conversio / quarter-turn in-progress state,
and `_pending_march_*` are deleted. Replacing or clearing the queue interrupts
the maneuver in flight (a partial turn folds and settles; a wheel stops where it
stands), so a parked rear march dies with its order — which also fixes a latent
stale-march bug the parallel flags had. Two scoping notes:

- The **standalone V/Q/E drills** became `ABOUT_FACE` / `QUARTER_TURN` queue
  entries created by `Unit` itself, still deliberately unrecorded (the queue is
  not serialized, so replays are untouched). They now fire only from a
  standstill, so an unrecorded gesture can never clobber the order a live
  behaviour runs off.
- **`_engage_turn_target` stays a Unit field**, not a queue entry. The combat
  re-face is reactive execution state the sim arms *while fighting* — an idle
  auto-engaged unit has no order at all — so per this doc's own verbs-vs-modes
  split it belongs to the reactive layer, not the queue. It shares the in-place
  turn mechanics (`is_maneuver_turning` covers it for the body-arrival freeze).

### Phase 3 — migrate transition orders + split relief + absorb waypoints

**Scope.** Move `FormationOrder`, `SpacingOrder`, `StanceOrder`, and
`SwitchWeaponOrder` onto the queue, each writing its durable mode on completion.
Split the current `_relief_partner` / `UnitRelief` mechanism into its two real
behaviors: **inter-unit relief** becomes a `RelieveUnitOrder` queue entry (names the ally;
response-delay + ward become the order's execution state), and **intra-unit
rank-relief** becomes a durable mode toggled by a `StanceOrder` (cross-links
#529, whose rank-cycle recovery is exactly this mode). Finish absorbing the
waypoint list. Decide support-ward: durable assignment mode vs standing
`SupportOrder`.

**Subsumes.** The `_relief_partner` / `UnitRelief` relief mechanism (split into
the order + the mode) and the ad-hoc formation/spacing/stance transition flags.

**Determinism / replay risks.** Transition timing (a formation change over N
ticks) must advance deterministically; a mode must be written exactly on
completion, not mid-transition, or replays diverge.

**Done-check.** Every transition order writes its mode on completion and appears
in the transcript as an in-flight order until then; inter-unit relief runs as a
`RelieveUnitOrder` queue entry while intra-unit rank-relief is a queryable mode;
the support-ward decision is recorded here.

**As implemented (#524).** Five scoping decisions, mirroring phase 2's notes:

- **The route is the queue.** A queued waypoint leg IS a queued `MOVE` order; the
  parallel `Unit.waypoints` list is deleted. Finishing a leg retires its order,
  and promoting a not-yet-started `MOVE` commits its march
  (`retire_current_order` → `_start_promoted_move`), so a route continues behind
  a finished attack or relief. One behavior fix falls out: an append now queues
  *behind* an in-flight rear-move about-face instead of pre-empting the turn.
  `move_target` / `has_move_target` stay as the in-flight leg's execution state.
- **Relief split, as specced.** The inter-unit swap's execution state lives on
  the reliever's `RELIEF` order (`Order.friendly_target`, later generalized into a
  pass-through link any order type can arm): the pass-through
  separation exemption is checked from either side off that one link, the tired
  unit's retreat is a queue-visible `MOVE` order of its own, and the link — so
  the exemption — dies with the order on an interrupt. The order retires only
  once the swap has resolved (no foe, no advance in flight, link cleared), so
  retiring can't shove a still-overlapping pair apart. Intra-unit rank-relief is
  the durable `Unit.rank_relief` mode (default on, so replays and balance are
  unchanged): it gates the training-driven rank-cycle fatigue reduction and
  in-fight morale recovery, and a `STANCE` order writes it. `target_enemy` and
  `support_target` stay unit fields — the reactive layer (enemy AI, auto-engage)
  writes `target_enemy` with no order behind it, so per the verbs-vs-modes split
  they are execution state the queue reads.
- **Transitions complete instantaneously today.** `FORMATION` / `FRONTAGE` / the
  new `STANCE` order write their mode at the apply tick — the write IS the
  completion — because the sim has no transition choreography for them yet: the
  body re-packing that follows is the presentation layer's arrival dynamics.
  The completion-write contract is therefore held trivially (a deterministic
  write at the apply tick), and a future PR that gives a formation change a real
  N-tick duration inherits the queue machinery ready-made. The idle-only queue
  entry (occupy the queue only when no live order runs) carries the transcript
  visibility; a busy unit's concurrent mode write is the mode layer's parallel
  composition. `SpacingOrder` maps onto what the codebase already models —
  open/close order is `FORMATION` density, line width is `FRONTAGE` — and
  `SwitchWeaponOrder` stays future work: no weapon-switch mechanic exists yet.
- **`StanceOrder` has no player gesture yet.** The stance hotkeys still arm a
  mode for the *next* move/attack order; `Battle.enqueue_stance` exists (and is
  recorded) so the mode layer is reachable from the same exactly-once dispatch
  as every other command, with the standalone-gesture UX tracked as follow-up
  work (#593).
- **Support-ward decision: a standing `SupportOrder` (queue entry), not a
  durable assignment mode.** Support already behaves like an order, not a mode:
  it has a terminal condition (the ward dies or routs → the duty is spent), any
  fresh order replaces it (assignment modes like `formation_mode` survive
  re-orders; support does not), and the transcript reports it as
  `current_order = SUPPORT` with the ward in `target_uid`. The resolved ward
  reference (`Unit.support_target`) stays on the unit as execution state, since
  uid→node resolution lives in Battle.

### Phase 4 — terminal conditions + trigger vocabulary + ROE modes

**Scope.** Add the first-class terminal-condition field, the bounded enumerated
guard vocabulary, and the reactive ROE modes (HOLD / fire-at-will / cycle-charge)
in the mode layer. Enable "advance UNTIL contact THEN attack" and "hold UNTIL in
range THEN fire".

**Subsumes.** The crude `order_mode` HOLD behavior, promoted into a real ROE
mode.

**Determinism / replay risks.** This is the highest-risk phase for determinism:
every condition must read only serialized sim state and evaluate in the sim step.
No wall-clock, no unseeded RNG. Guard evaluation order must be fixed.

**Done-check.** Each guard in the closed vocabulary is a pure function of
serialized state; a conditional order's pending condition shows in the transcript;
a replay with conditions produces identical branch choices on re-run.

**As implemented (#525).** Three scoping decisions:

- **The guard lives on the `Order` itself, evaluated by a new pure module,
  `OrderGuards.gd`.** `Order.guard` (a `Guard` enum: `ENEMY_IN_RANGE`,
  `CONTACT_MADE`, `MORALE_BELOW`, `ALLY_EXHAUSTED`, `TICKS_ELAPSED`, `FLANKED`)
  plus `guard_param` / `guard_uid` cover the closed vocabulary; `_guard_ticks`
  is the one piece of live execution state a guard needs (advanced once per
  tick, reset for free because each `Order` is a fresh instance). Attached at
  construction via a fluent `Order.new_move(dest).with_guard(...)`, mirroring
  the constructor-helper pattern the taxonomy table already uses. A satisfied
  guard retires the order early from `Unit._update_current_order`, checked
  before the per-type match so it pre-empts ANY order kind's own completion
  condition — the general form of "terminal condition," not a MOVE-specific
  carve-out.
- **"Advance UNTIL contact THEN attack" is the guard-plus-append composition
  the design doc names, not a new order type.** A `MoveOrder` guarded by
  `CONTACT_MADE` with an appended, unresolved `AttackOrder` (`target_uid < 0`)
  behind it: the guard firing retires the move and promotes the attack on the
  same tick, and a new promotion hook (`Unit._start_promoted_attack`) resolves
  the unresolved attack's target to whatever enemy is actually in contact —
  the counterpart to the existing `_start_promoted_move` hook that commits a
  promoted route leg's march. A player-issued attack (a resolved `target_uid`)
  is untouched; `Battle._apply_order_cmd` already sets `target_enemy` at issue
  time.
- **"Hold UNTIL in range THEN fire" needed no new mechanism.** A ranged unit
  already fires at any live enemy inside `RANGED_RANGE` unconditionally (the
  `is_ranged` branch in `Unit._think` is not gated on `order_mode`), so
  fire-at-will is the existing default rather than a mode of its own. The ROE
  modes the design doc asks to promote (`HOLD` / `SKIRMISH` / `CYCLE_CHARGE` /
  `SUPPORT` / the flank/rear attack bias) already exist as `Unit.OrderMode` —
  phase 4 documents them as the mode-layer promotion in place (see the
  comment block above `Unit.ORDER_HOLD`) rather than renaming or duplicating
  them; the guard vocabulary is what was actually missing, and gives the
  queue a first-class way to gate an order's own early completion on one of
  them instead of the ad-hoc `if order_mode == ORDER_HOLD` checks scattered
  through `_think`.
- **No new player gesture yet**, matching phase 3's `StanceOrder` precedent:
  guarded orders are reachable via the `Order` API (for demos, tests, and a
  future reactive-AI layer per the design doc's "out of the core" boundary),
  with the hotkey/UI surface left as follow-up work.

### Phase 5 — transcript records order + phase + condition (verification payoff)

**Scope.** Finish the transcript surface: `current_order`, active phase, pending
terminal condition / guard, the durable modes, and optionally the queue tail.
This is largely delivered incrementally by phases 1–4; phase 5 closes any gaps
and locks the format.

**Determinism / replay risks.** Low — read-only serialization. Guard against
non-deterministic ordering when dumping the queue.

**Done-check.** A single transcript read distinguishes conversio from centre-pivot
(the #517 verification), shows a held-until condition, and shows every durable
mode — no motion-inference needed.

**As implemented (#526).** Phases 1–4 already delivered `current_order`,
`order_phase`, and `order_guard` on the state-dump snapshot
(`DemoInputRecorder._unit_record`); phase 5's own gaps were two fields plus
the verification itself:

- **`frontage`** — the file count a `FRONTAGE` order last wrote (or the
  type-derived default when none has), read via the same
  `UnitFormation.frontage` lookup the sim itself uses. The taxonomy table's
  other durable modes were already covered: `formation` (`formation_mode`),
  `order_mode` + `rank_relief` (stance). `active_weapon` has no field to dump
  — `SwitchWeaponOrder` is still future work (phase 3's own scoping note: no
  weapon-switch mechanic exists yet), so there is nothing there to surface
  until that mechanic lands.
- **`queue_tail`** — the not-yet-current queued orders' type names, in queue
  order. Optional per the design doc, and cheap once `current_order` /
  `order_phase` / `order_guard` already existed: a plain slice of `Unit.orders`
  past the head. Empty (`[]`), not `null`, when nothing is queued, so a reader
  distinguishes "no current order" (`current_order: null`) from "current
  order, nothing behind it."
- **The #517 verification itself, now a permanent regression test**
  (`test_orders_transcript.gd`): stages a plain forward march and a rear-move
  about-face on the same unit through the SAME snapshot code CI's demo
  state-dump path runs (not a hand-rolled read of `Unit` fields), and asserts
  `order_phase` alone reads `NONE` vs `TURN` — the one-field read the whole
  design exists to make possible.

## Relationship to existing issues

- **#515** (explicit current-maneuver state) — absorbed as phase 1; it becomes
  `current_order` + phase. Close it into this once phase 1 lands, or keep it as
  the phase-1 tracking issue.
- **#518** (orders applied twice) — the bug class phase 1 kills at the root. The
  in-flight #518 fix is phase 1's apply-once slice landing first.
- **#517** (move-to-rear centre-pivot) — fixed by the phased move-to-rear in
  phase 2 and verified in phase 5.
- **#521** (nudge under-travel) — fixed by apply-once + the queue in phases 1–2.
- **#529** (routs nearly unreachable — in-fight morale recovery) — the intra-unit
  rank-relief *mode* introduced in phase 3 is the same rank-cycle recovery that
  issue tracks; whether that mode is on, and how strong its recovery is, is the
  knob #529 tunes.
