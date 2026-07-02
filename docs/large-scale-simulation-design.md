# Design note: multi-resolution (LOD) simulation for large-scale battles

Status: **phases 1–4 implemented** (PRs #568, #577, #589, and the phase-4 PR;
phase 5 remains). This note consolidates #550 (and its benchmark evidence from
#551) into one spec, following the same design-doc-first pattern as #516
(`docs/orders-queue-design.md`) and #547. It lays out the model and the phased
plan tracked by the phase issues linked below.

## Motivation

### The scale gap

The owner's long-horizon goal ([#550](https://github.com/Lacaedemon/sparta/issues/550))
is to simulate battles up to the scale of Cannae — commonly cited around
80,000+ Roman and 50,000+ Carthaginian troops, well over 100,000 combatants
total (ancient-source estimates vary; treat this as an order-of-magnitude
target, not a precise headcount). Battles today run low-hundreds to
low-thousands of soldiers across a handful of units — roughly two orders of
magnitude below that target.

### Why full individual-soldier simulation likely can't close it

The bottom-up-emergence design pillar (`PLAN.md`, pillar 2; #548) commits to
realistic per-soldier state and behavior — position, facing, speed,
weapon/shield, slot ownership, individual orders (#497 / #535 / #547) — kept
array-based/SoA for performance. That architecture is efficient, but it is
still fundamentally **O(soldiers) state and, per the evidence below,
worse-than-linear per-tick cost**. Simulating 100,000+ soldiers, each with
real physics, combat, and orders, is very unlikely to fit the 60fps budget on
the reference hardware (`PLAN.md`'s target: a 2022 MacBook Air M2 24GB and the
developer's usual PC).

### The evidence (from #551's benchmark, merged)

This was previously an expectation; it is now measured. `tools/benchmark/`
([#551](https://github.com/Lacaedemon/sparta/issues/551), merged) reports,
on the dev PC, physics-step cost **alone** — before any render cost — already
at the 60fps budget at ~1,720 soldiers (two 8-unit armies, the current
`benchmarks/scenarios/large-battle.json` reference scenario): mean 16.97ms
against a 16.67ms/tick target, p95 well over.

Worse, scaling is **super-linear** with soldier count:

| Soldiers (relative) | Tick cost (relative) |
|---|---|
| 1x | 1x (already at budget) |
| 2x | ~3.1x |
| 4x | ~12x |

Not proportional — this looks like an O(n^1.5)-ish or worse interaction cost,
plausibly from per-soldier neighbor/collision or combat-target search
(worth profiling as a follow-up, out of scope here). This is why #550 was
bumped from P3 to P2: given super-linear scaling, even *moderate* growth
beyond today's typical battle size blows the 60fps budget well before
triple-digit-thousand soldier counts. The close-tier/far-tier split this
issue proposes is relevant much sooner than the original "eventually,
Cannae-scale" framing implied — it is the mechanism that keeps growing the
game's realistic per-entity fidelity (#497/#535/#547, all correctly array-based
already) from also growing the sim's simulated footprint 1:1 with battle size.

## The model: two simulation tiers

Rather than choosing one simulation fidelity for the whole battle, different
**formations** within a battle are simulated at different resolutions
simultaneously. Fidelity is a per-formation property, not a per-battle one.

### Close tier — full individual-soldier fidelity

This is the #497/#535/#547 bottom-up model exactly as it exists and is being
built today: real per-soldier physics, per-soldier weapon/shield objects,
individual slot ownership and orders, `_sim_soldier_*` SoA arrays. A
close-tier formation is a formation currently in or near active combat — the
part of the battle that is tactically relevant *right now*.

Nothing about #497/#535/#547 changes to support this tier; they already build
it. What changes is that it becomes optional per-formation rather than
universal.

### Far tier — aggregate/statistical simulation

A far-tier formation carries no per-soldier state at all. It is a small,
fixed-size record per formation, evolved by statistical rules instead of
per-soldier physics:

- **count** — living soldiers (replaces the array length).
- **morale** — the existing unit-level morale scalar (`PLAN.md` pillar 2
  already keeps morale/rout at unit-level for now, per #529 — the far tier is
  a natural extension of that existing abstraction, not a new one).
- **position** and **facing** — the formation's centroid and orientation, the
  aggregate analog of the individual-soldier centroid/bbox already exposed as
  `soldier_summary` in the state transcript (see below).
- **casualties-so-far** — running total, derived from `count` decreasing over
  time, needed to reconstruct plausible losses/HP distribution on promotion.
- **formation_mode / spacing / stance** — the existing durable "mode" fields
  from the orders-queue design (`docs/orders-queue-design.md`) carry over
  unchanged; they describe the formation, not its soldiers.

A far-tier formation's morale/casualties/position evolve tick-to-tick via
coarse statistical rules (e.g. expected casualty rate as a function of
opposing far-tier formations' aggregate strength and morale, in the spirit of
a Lanchester-style attrition model) rather than per-soldier combat resolution.
The exact attrition rule is implementation detail for phase 2 (below); the
important design constraint is that it consumes and produces only the
aggregate fields above — no per-soldier read or write, ever.

### Promotion / demotion

A formation transitions between tiers as it enters or leaves the
tactically-relevant zone. Proposed trigger, to be tuned empirically (see
"Validating tier thresholds" below):

> **Promote** a far-tier formation to close tier when its distance to the
> nearest enemy contact point (or, before any contact exists, the nearest
> enemy formation) drops below a threshold distance `PROMOTE_RANGE`.
> **Demote** a close-tier formation to far tier when that same distance rises
> above a threshold `DEMOTE_RANGE > PROMOTE_RANGE` (a hysteresis gap, so a
> formation sitting exactly at the boundary doesn't thrash tiers every tick).

This is deliberately the simplest trigger that could work — a single scalar
distance check, no camera-frustum or player-attention signal, so it stays a
pure function of already-serialized sim state (positions), which the
determinism section below requires. It is also a small, composable piece in
its own right (`PLAN.md` pillar 3): a standalone predicate over two
positions, not a new subsystem entangled with rendering, orders, or combat —
it can be tuned or swapped without touching either tier's internals. Camera/attention-based triggers (only
promote what the player can currently see) are a plausible refinement but are
explicitly **not** the phase-1 mechanism: they would make simulation fidelity
depend on rendering/UI state, which cuts against having a single deterministic
sim step independent of what's on screen. If the distance-only trigger proves
tactically wrong in practice (e.g. a flank the player is about to redirect
toward should promote before contact), revisit then — don't build the more
complex trigger speculatively.

`PROMOTE_RANGE` / `DEMOTE_RANGE` are not guessed; they're tuned against the
benchmark (phase 4, below) once the close-tier soldier-count ceiling is
measured, so the values reflect an actual "how big a close-tier bubble can the
hardware afford," not an arbitrary distance.

## Determinism across the tier boundary

Per the two invariants that already govern the orders-queue design
(`docs/orders-queue-design.md`, "Two invariants") and the state-transcript
verification method (#500/#501/#507), everything in the sim step must be a
pure function of serialized state, evaluated deterministically, reproducible
on replay. The tier boundary must hold to the same bar:

- **Demotion (close → far) is lossy but deterministic.** Collapsing
  individual soldiers to an aggregate record is a pure reduction over the
  soldier arrays (count them, average position, roll up morale/casualties) —
  no randomness, so it's trivially deterministic.
- **Promotion (far → close) must reconstruct plausible per-soldier state
  without live RNG.** Spreading an aggregate `count` back into individual
  soldier positions/facings/HP needs *some* variation (soldiers shouldn't
  reappear stacked on one exact point) but must not call an unseeded or
  wall-clock RNG at the moment of promotion, or the same replay could promote
  a formation into a different soldier layout on two runs.

  The resolution: promotion is a **pure function of the aggregate state plus
  a deterministic seed** derived from already-serialized data — e.g. a hash
  of `(formation uid, promotion tick, battle seed)`, matching the pattern the
  project already uses for reproducible per-soldier layout (the battle-level
  seed that scenario files like `benchmarks/scenarios/large-battle.json`
  already carry as `"seed"`). Given the same aggregate state and the same
  seed, promotion always produces the same reconstructed soldier layout — a
  formation-slot placement (see #547's slot model) seeded off that hash,
  filled front-to-back up to `count`, with casualties consumed from the rear
  ranks first (matching how #547 slot ownership already models a soldier
  falling out of the front line). No live randomness; replay-safe.

- **A round trip is not required to be lossless**, only deterministic. A
  formation that promotes then immediately demotes need not reconstruct its
  *exact* pre-demotion soldier layout — only *a* plausible layout consistent
  with the aggregate numbers, reproducibly. This is analogous to how the
  close tier itself already accepts some reconstruction: formation-slot
  layout is already recomputed from `unit.position + facing + formation_mode`
  today (the very re-derivation #547 is designed to make explicit and
  persistent, rather than implicit) — a far-tier round trip is the same kind
  of "recompute a plausible state from durable inputs," just crossing the
  tier boundary instead of a facing change.

## How the state transcript represents a far-tier formation

The transcript (#500/#501/#507, and the field reference in
`.claude/skills/verify-via-state-dump/SKILL.md`) already records, per unit:
`uid`, `name`, `team`, `position`, `facing`, `morale`, `state`, `formation`,
`soldiers` (living count), `current_speed`, `order_mode`, `target_enemy_uid`,
`engaged` — plus, optionally, `soldier_summary` (`count`, `centroid`, `bbox`,
`prone_count`) or the full per-soldier `soldiers_full` arrays.

A far-tier formation has no per-soldier data to summarize — no
`soldier_summary`, no `soldiers_full`, because there are no individual bodies
to derive them from. The transcript needs an explicit **`tier` field**
(`"close"` / `"far"`) per unit record, so a reader (human or the
verify-via-state-dump tooling) can tell *why* `soldier_summary` is absent —
"not requested this dump" (today's `SPARTA_DEMO_STATE_FULL` opt-in) vs. "this
formation has no individual soldiers to summarize" (a far-tier formation) are
different facts and must not look the same in the dump. (As implemented, the
field serializes the names uppercase — `"CLOSE"` / `"FAR"`, via
`FormationTier.TIER_NAMES` — matching the transcript's other enum-name fields
like `state` and `formation`.)

For a `tier: "far"` unit, the existing scalar fields (`position`, `facing`,
`morale`, `soldiers`) already carry the aggregate state as-is — no new fields
needed for those. What's new is purely the `tier` marker and the absence of
any per-soldier payload. This keeps the transcript change minimal: it is an
additive field plus a conditional omission, not a parallel record shape.

## Interaction with the orders model (#516)

A far-tier formation still receives and queues orders — a reserve formation
sitting in the rear is exactly the kind of thing a player gives a standing
march order to ("advance to the line when engaged") — but at the formation's
own coarse granularity. The `Order` / orders-queue model from
`docs/orders-queue-design.md` already operates at the `Unit` level (move,
wheel, form testudo, attack), not the individual-soldier level, so it applies
to a far-tier formation **unchanged**: a `MoveOrder` moves the aggregate
`position`; a `FormationOrder` still writes `formation_mode` (relevant again
immediately on promotion, since the reconstructed close-tier layout reads
it). No new order types are needed for the far tier.

#547's per-soldier orders (an individual soldier's standing "advance if your
file-mate dies," slot reshaping) are, by construction, not applicable to a
far-tier formation — there are no individual soldiers to hold slots or
receive those orders. This is not a gap to fill; it's the expected
consequence of the far tier having no soldier-level state at all. #547's
model needs no change to accommodate the far tier — it simply doesn't run
for far-tier formations, and starts applying again once the reconstructed
soldier layout exists post-promotion.

## Validating tier thresholds: the benchmark as the tuning tool

`tools/benchmark/` (#551, merged) is the empirical instrument this design
depends on, not just background evidence for the motivation section:

- **Finding the close-tier soldier-count ceiling.** `run-benchmark.sh`'s
  scale-sweep mode (`for s in 1 2 4; do tools/benchmark/run-benchmark.sh
  benchmarks/scenarios/large-battle.json "$s"; done`, per
  `tools/benchmark/README.md`) gives the soldier count at which physics-step
  cost alone crosses the 16.67ms/tick budget on the reference hardware. That
  number *is* the practical ceiling for total close-tier soldiers across all
  currently-promoted formations — not a guess, a measured value, re-run
  whenever per-soldier realism grows (more per-soldier state, per #535/#547).
- **Sizing the far-tier's job.** Given a Cannae-scale target (~100k+
  combatants) and a measured close-tier ceiling (order-of-magnitude
  thousands, per the current data), the far tier needs to carry the
  difference — i.e. the overwhelming majority of combatants in a
  Cannae-scale battle, with only the actively-engaged fraction promoted to
  close tier at any moment. This ratio is the concrete number that tells
  phase 5 (below) how ambitious the reference large-scale scenario needs to
  be to count as a real acceptance test.
- **Tuning `PROMOTE_RANGE` / `DEMOTE_RANGE`.** Once phase 3 lands the
  promotion/demotion mechanism, sweep the thresholds against the benchmark:
  too tight and every formation promotes almost immediately (no fidelity
  savings); too loose and formations that are visibly fighting stay
  aggregate (a correctness/plausibility failure, not just a performance one).
  The right threshold is the largest one that keeps the *promoted* soldier
  count under the measured ceiling for the target scenario size — again, a
  benchmark-driven number, not an authored constant.

### Measured record (phase 4, 2026-07-02, dev PC)

The phase-4 tuning runs, all on the developer's usual PC (one of the two
reference machines; Godot 4.7 headless, default 120-tick warmup + 600-tick
measure window). The benchmark now also reports `close_tier_soldiers` — the
per-tick promoted-bubble size — next to the timings.

| Run | Spawned | Close-tier (mean / peak) | Mean tick | p95 tick |
|---|---|---|---|---|
| `large-battle` 1x | 1,720 | 1,189 / 1,546 | 16.65 ms | 21.13 ms |
| `large-battle` 2x | 3,440 | 2,841 / 3,236 | 37.14 ms | 44.13 ms |
| `large-battle` 4x | 6,880 | 6,508 / 6,701 | 135.83 ms | 146.95 ms |
| `echelon-battle` (reserves beyond `DEMOTE_RANGE`) | 1,990 | 1,029 / 1,270 | 16.67 ms | 21.39 ms |
| `echelon-battle-shallow` (reserves inside the band) | 1,990 | 1,639 / 1,880 | 16.77 ms | 20.91 ms |

(One caveat baked into the numbers: physics can't run *faster* than 60 ticks/s
without `--fixed-fps`, so an under-budget run's mean pins at the ~16.67 ms
pacing floor — the mean shows *whether* the budget holds, and only an
over-budget run shows by how much it fails. The p95 above the floor is the
share of ticks that individually exceeded it.)

**The measured ceiling.** The reference engaged battle (1x, every soldier
close-tier and fighting) sits exactly at the 60fps budget, and doubling it is
2.2x over — so the close-tier ceiling on this hardware is, in practice, *the
reference front itself*: ~1,700 spawned / ~1,200–1,550 alive through a
sustained melee window. There is no headroom to promote a second echelon that
then joins the fight.

**The tuned thresholds.** `PROMOTE_RANGE = 400` / `DEMOTE_RANGE = 600`
(unchanged from the provisional values, now evidence-backed):

- The correctness floor pins the promote threshold from below:
  `PROMOTE_RANGE` must exceed `DETECTION_RANGE + SPRINT_START_DISTANCE`
  (190 + 200 = 390), so a formation regains individual fidelity before it can
  detect, shoot at, or charge anything.
- The measured ceiling pins it from above: the promoted bubble already spends
  the whole budget on the engaged fronts, so the largest threshold that keeps
  the promoted count under the ceiling is the smallest one the combat floor
  allows — promote only what is about to fight. 400 is that value with a
  small margin.
- The `echelon-battle` pair validates `DEMOTE_RANGE` as the deployment-depth
  discriminator: reserves deployed beyond it (850 behind the front) demote on
  spawn and the promoted bubble stays at the two fronts (peak 1,270 of 1,990;
  60fps holds), while the same reserves parked inside the hysteresis band
  (500 behind) keep their close spawn tier for good (peak 1,880 of 1,990).
  The shallow run's *tick cost* barely moves at this army size — idle
  close-tier soldiers are far cheaper than engaged ones — but its bubble now
  exceeds the ceiling, and the scale sweep shows what that costs the moment
  those extra soldiers fight (2x: 2.2x over budget). At Cannae-scale reserve
  counts the far tier is carrying the difference either way.

Re-run the sweep and the echelon pair (and update this table) whenever
per-soldier realism grows or the reference hardware changes; the thresholds
are only as current as these numbers.

## Phase plan

Design only, right now — no implementation dispatched by this doc. Each phase
below is filed as its own tracking issue, linked from #550 and from here.

### Phase 1 — aggregate far-tier data model (representational only) — [#556](https://github.com/Lacaedemon/sparta/issues/556)

Define the far-tier formation record (`count`, `morale`, `position`,
`facing`, `casualties`, the durable mode fields) and a placeholder
promotion/demotion trigger (the simple distance threshold above, with
provisional constant values — not yet tuned). No visual or gameplay change:
this phase is purely representational — the data model exists and is
unit-tested, but nothing in `Battle.gd` acts on it yet.

**Done-check:** the far-tier record type exists, is unit-tested in isolation,
and a formation can be constructed in either tier with no behavior wired to
the distinction yet.

### Phase 2 — far-tier simulation rules — [#557](https://github.com/Lacaedemon/sparta/issues/557)

Wire the statistical rules that evolve a far-tier formation's morale,
casualties, and position over time, with no per-soldier state involved. Verify
in isolation: a far-tier formation fighting another far-tier formation
produces plausible attrition (casualties accumulate at a rate broadly
consistent with the close-tier combat model it approximates) without ever
touching `_sim_soldier_*` arrays.

**Done-check:** two far-tier formations, simulated against each other for N
ticks with no close-tier formations present, produce morale/casualty curves
that a reviewer judges plausible against the close-tier model's own behavior
in an equivalent small-scale scenario.

### Phase 3 — promotion / demotion transition + determinism verification — [#558](https://github.com/Lacaedemon/sparta/issues/558)

Implement the tier transition itself: demotion (the lossy-but-deterministic
reduction) and promotion (the seeded, deterministic reconstruction described
above). Verify determinism explicitly — replay a scenario that promotes and
demotes a formation twice and confirm bit-identical (or field-identical, via
the state transcript) soldier reconstruction both times.

**Done-check:** a scripted-input replay that crosses the promotion boundary
produces identical reconstructed soldier layouts (position, facing, HP) on
two separate runs from the same seed; a demote-then-promote round trip
produces a plausible (not necessarily identical) layout consistent with the
aggregate numbers carried across the demotion.

### Phase 4 — transcript + benchmark integration — [#559](https://github.com/Lacaedemon/sparta/issues/559)

Add the `tier` field to the state transcript (per the section above). Run the
benchmark sweep to measure the actual close-tier soldier-count ceiling on
the reference hardware, and tune `PROMOTE_RANGE` / `DEMOTE_RANGE` against that
measured ceiling for a representative multi-formation scenario.

**Done-check:** the transcript distinguishes a far-tier unit's absent
`soldier_summary` (`tier: "far"`) from a close-tier unit's not-requested one;
the tuned thresholds are recorded in this doc (or a follow-up comment) with
the benchmark numbers that produced them.

### Phase 5 — large reference scenario (acceptance test) — [#560](https://github.com/Lacaedemon/sparta/issues/560)

Author a new `benchmarks/scenarios/` (or `demos/inputs/`) scenario
approaching Cannae-scale using mostly far-tier formations, with a handful of
close-tier formations actively engaged, sized so the total promoted soldier
count stays under the phase-4 ceiling. This is the acceptance test for the
whole design: it exercises promotion/demotion under realistic load, confirms
the far tier's rules stay plausible at scale, and gives a concrete "how close
to Cannae are we now" number to report back on #550.

**Done-check:** the scenario runs at the reference hardware's 60fps budget
(measured via `tools/benchmark/`), the promoted/close-tier soldier count is
within the phase-4-tuned threshold, and the far-tier formations' aggregate
behavior over the run looks plausible when spot-checked against the
transcript.

## Relationship to existing issues

- **#550** — this doc is the design-doc deliverable #550 asks for; phases
  [#556](https://github.com/Lacaedemon/sparta/issues/556),
  [#557](https://github.com/Lacaedemon/sparta/issues/557),
  [#558](https://github.com/Lacaedemon/sparta/issues/558),
  [#559](https://github.com/Lacaedemon/sparta/issues/559), and
  [#560](https://github.com/Lacaedemon/sparta/issues/560) are its tracked
  sub-issues.
- **#551** (benchmark tooling, merged) — the validation instrument phases 1–5
  lean on throughout, especially phase 4.
- **#497 / #535 / #547** (bottom-up individual-soldier model) — unchanged;
  this design makes their existing per-soldier fidelity the close tier,
  applied selectively rather than universally.
- **#516** (unified orders queue) — unchanged at the order-type level; a
  far-tier formation uses the same `Order` model at its own granularity.
- **#529** (unit-level morale/rout) — the far tier's morale handling is a
  direct extension of the existing unit-level-morale architecture already in
  place for that reason.
