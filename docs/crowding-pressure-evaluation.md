# Design spike: a damped crowding-pressure term for soldier-body collision

Status: **evaluation only** (per [#750](https://github.com/Lacaedemon/sparta/issues/750)) —
no implementation in this doc or its PR. This answers the issue's three suggested-scope
questions and recommends follow-up issues rather than shipping code now.

## 1. Is our soldier-body separation likely to become a bottleneck?

**Yes, and sooner than [`individual-collision-design.md`](individual-collision-design.md)'s
Decision 3 assumes** — measured, not assumed, by re-running
[#549](https://github.com/Lacaedemon/sparta/issues/549)'s benchmark at increasing scale:

| scale | soldiers | close-tier (engaged) | mean tick | implied fps |
| --- | --- | --- | --- | --- |
| 1x | 1,720 | 1,458 (84.8%) | 27.1 ms | 36.9 |
| 2x | 3,440 | 3,230 (93.9%) | 95.6 ms | 10.5 |

(`tools/benchmark/run-benchmark.sh benchmarks/scenarios/large-battle.json <scale>`, 300
measured ticks after a 60-tick warmup, this session's CI-class container — absolute numbers
aren't the reference-PC target per `tools/benchmark/README.md`, but the *scaling shape* is what
matters here.)

Doubling soldier count **more than tripled (3.5x)** mean tick time. That's clearly
super-linear, and it isn't just "more soldiers, more pairs" — the fraction of soldiers
promoted into the expensive **engaged/close tier** also grew, from 84.8% to 93.9%. Both the
population *and* the fraction paying the expensive per-pair cost grew, compounding.

**Root cause: the tier-promotion gate is regiment-block-coarse, not soldier-coarse.**
`SoldierSteering._overlaps_friendly()` promotes a regiment's **entire** body set to the
expensive tier the moment its `soldier_block_extent()` (the whole formation's half-size)
overlaps a friendly regiment's extent — not when individual soldiers actually crowd each
other. The benchmark's `scale` multiplier grows each unit's soldier count at the same spawn
layout, which widens every formation block (more files to fit the extra soldiers) without
widening the battlefield to match. Wider blocks at fixed spacing overlap more readily, so a
much larger share of the population gets pulled into the O(neighbors) pairwise pass even
though soldier-level crowding may still be moderate. This is consistent with the project's
target scale (Decision 3: ~5,000 total, ~1,000-1,500 engaged) being **optimistic at battle
densities above the current reference scenario** — the two-tier LOD's whole point is to
bound the expensive pass to the contact faces, and a coarse promotion gate defeats that as
density rises.

**Conclusion: yes, this is worth addressing before Cannae scale (#550), and the actual lever
is the tier-promotion gate, not the per-pair force math** — see §3.

## 2. Would a damped, 0 A.D.-style crowding-pressure term help?

**Not for the performance problem, but partially for a distinct stability question.**
These are two different concerns and #750 conflates them somewhat by importing a single
mechanism (0 A.D.'s scalar pressure field) that in their engine addresses both at once. Ours
doesn't need to, because our physics model already differs from theirs in an important way.

### It would not fix the measured bottleneck

A damped pressure term changes how much **force** a crowded pair applies to each other; it
does not change **how many pairs get evaluated**. The blowup measured in §1 comes from too
many soldiers entering the expensive per-pair pass, not from the per-pair math being too
expensive per call. Damping the force per pair leaves the same O(engaged-count × neighbors)
work on the table — it would not have prevented the 2x→3.5x cost jump. Any fix here has to
shrink the *promoted population*, not the *cost per promoted soldier*.

### The stability half: already substantially covered by our existing architecture

0 A.D.'s crowding-pressure damping exists because *their* engine can apply force to a unit's
velocity/position more directly per tick. Ours does not: every soldier-body velocity target
— including `_sim_steer`'s accumulated friendly-avoidance push — is fed through
`SoldierBodies.step`'s `move_toward(desired_vel, body_accel * delta)` (see
`scripts/SoldierBodies.gd:239`). That means **no matter how large a single tick's summed
push vector gets, the body's actual velocity can only change by `body_accel * delta` that
tick** — there is no snap, no instant force application, and no teleport. This is exactly
the failure mode 0 A.D.'s pressure damping exists to prevent, and our "no top-down gimmicks,
no snaps" architecture (`sparta.md`) already prevents it structurally, for free, without a
separate pressure abstraction.

**The residual gap:** `SoldierSteering.accumulate()` sums each contributing pair's push
(`STEER_STRENGTH = 60.0` wu/s, split by share) into `steer[a]` with **no cap on the total**.
Bounded acceleration stops any single tick from spiking, but under *sustained* extreme
crowding (many ticks in a row with a large summed push — e.g. many soldiers converging into
one pinch point) the target velocity itself has no ceiling, so the body's actual speed could
ramp up over several ticks toward an unrealistically high asymptote. This is a real,
if secondary, finding — but it's a **magnitude cap**, not 0 A.D.'s pressure-accumulates-and-
damps-over-time model.

## 3. Recommendation

Don't adopt 0 A.D.'s scalar-pressure-field abstraction. It's built for a different physics
foundation (direct force/position application) than ours (bounded-acceleration integration,
already snap-free), so importing it would add a second, redundant damping mechanism layered
on top of one we already have — the kind of complexity `challenge-unnecessary-complexity`
review guidance flags. What's actually worth doing, as two independent, minimally-scoped
follow-ups:

1. **Tighten the engaged/friendly-contact tier-promotion gate** (the real performance
   lever, per §1) — likely by promoting based on actual soldier-to-soldier proximity (or a
   tighter per-side sub-region of the block extent) rather than whole-block-extent overlap,
   so a wide but sparsely-crowded formation doesn't pull its entire body count into the
   expensive pass. Tracked in [#769](https://github.com/Lacaedemon/sparta/issues/769), with
   a before/after benchmark at the same scale sweep used here.
2. **Cap the accumulated `_sim_steer` magnitude** as a physically-motivated saturation limit
   (a real body's displacement rate under crowd pressure is bounded by friction and
   structural rigidity regardless of how many neighbors are pressing on it) — a small,
   local change to `SoldierSteering.accumulate()`, independent of (1). Tracked in
   [#770](https://github.com/Lacaedemon/sparta/issues/770).

Neither of these is "implement a crowding-pressure term" as #750 originally framed it; both
are narrower, and each is independently a better fit for the "no top-down gimmicks, physics
already gets us there" design philosophy than importing 0 A.D.'s model wholesale.

## Non-goals (unchanged from #750)

Not implementing (1) or (2) in this doc/PR — filing them as follow-up issues instead. Not
adopting 0 A.D.'s stat-based combat model (damage types/armor/bonuses) — out of scope, noted
in #750 only as contrast.
