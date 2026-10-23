# Design note: individual-level collision

Status: **phases 1-4 landed; engaged melee is now soldier-authoritative** (behind
`Unit.INDIVIDUAL_COLLISION`, ON). Soldiers are seeded as world-space bodies from their
formation slots, separated across regiments on a soldier-sized `SoldierSpatialHash`, and
the flock render follows those positions. Phase 4 wired the per-soldier combat model
(`combat-model.md`) into live melee: `UnitCombat.strike` routes engaged, non-ranged
combat to `SoldierMelee.resolve`, which resolves the opposed land contest and wound
against per-soldier health, reaps the dead, and drives `unit.soldiers` -- so casualties,
morale, rout, and the HUD now read soldier deaths for the engaged-melee case. Knockback,
prone, depth bracing, and stamina are wired (#201 slices A-D); friendly soldier collision
is soldier-level (phase 5 slice 1).

**Still regiment-level (the remaining authority work):** ranged casualty *count*
(`UnitCombat.shoot` still derives one volley size from regiment scalars and one RNG
roll -- one roll for the whole volley, not one per shooter).
Delivery is no longer regiment-level: a live battle flies that count as a projectile
and lands it arrow by arrow, so `ProjectileField._land_on_soldiers` picks the nearest
living soldiers to the volley origin (`SoldierMelee.ranged_victims`) and gates each
arrow on the shield THAT man is holding -- its coverage arc and its block chance -- so
a kill is no longer guaranteed.
Only a fieldless unit test still resolves the whole volley at once through
`SoldierMelee.apply_ranged_casualties`, where each kill is guaranteed.
Per-soldier armour in the ranged contest, and full per-shooter/per-target resolution,
stay tracked in #1186 / #435.
Also still regiment-level: morale (a regiment scalar,
not derived from soldier state), and **enemy** soldier-vs-soldier collision + retiring the
regiment circle -- the last is deferred to **#201** (stopping a charge needs momentum/mass;
see the phase-5 note below and #296). #201's momentum physics landed (#749), but a live
empirical test (#296) found it does NOT yet arrest a charge on its own; #783 was the root
cause, and #784 fixed it. Retiring the regiment circle stays blocked, but on the residual
first-contact overshoot transient recorded in #296's own thread -- not on #783, which is
closed. Posture/graded bracing and the rearward domino cascade are also deferred. The
design decisions are settled (see
"Decisions" below).

Tracks [#164](https://github.com/Lacaedemon/sparta/issues/164) (collision at the
individual level, not the unit level) and
[#192](https://github.com/Lacaedemon/sparta/issues/192) (individuals occupy space
and don't overlap). It's the groundwork for the physics model in
[#201](https://github.com/Lacaedemon/sparta/issues/201), which layers metric
units, mass, and knock-back *on top of* individual bodies -- so individual
collision has to land first.

This is the project's **#1 design pillar** (see [`PLAN.md`](../PLAN.md)), and
changing it touches the determinism guarantees that make replays work. So it gets
a design pass before code.

## Where collision is today

The simulation collides **regiments, not soldiers**. Each `Unit` is one circular
body and `_separate()` (`scripts/Unit.gd`) resolves regiment-vs-regiment overlap:

- A unit is a circle of `RADIUS = 18`. The *separation floor* is per-type --
  `SEPARATION_RADIUS_INFANTRY = 18`, `SPEARMEN = 20`, `CAVALRY = 24`, capped at
  `SEPARATION_RADIUS_MAX = 28` -- kept below melee reach so lines press into
  contact instead of bouncing apart.
- Each frame a unit pushes out of any overlapping unit by a `_push_share` of the
  penetration: `0.5` for a normal pair (each corrects half), but `0`/`1` for a
  spear screen vs. cavalry so horses can't ride through (the existing hard-block).
- Neighbours come from `SpatialHash` (`CELL_SIZE = 128`), rebuilt once per tick,
  replacing the old O(n²) scan. A co-located pair fans apart along a **uid-keyed**
  angle so the push is deterministic across a run and its replay.

Individual soldiers already exist, but **only as decoration**. `_soldier_pos` /
`_soldier_vel` (the "flock marks", `MARK_RADIUS = 1.7`, `CAV_MARK_RADIUS = 2.6`,
`FORMATION_SPACING = 3.4`) are a cosmetic layer -- the file says plainly they are
"never read by the sim". PR #202 added per-mark separation *in the renderer*; it
has no gameplay effect. So "individuals don't overlap" is true on screen and false
in the model.

## What #164 changes

Promote soldiers from drawn marks to **simulated bodies**: the thing that occupies
space, blocks movement, and fights becomes the individual, and the regiment
becomes a controller that issues formation slots and orders to its soldiers rather
than a single colliding circle.

The hard constraints any design must keep:

1. **Determinism / replay.** [`Replay.gd`](../scripts/Replay.gd) re-runs the real
   simulation from a seed plus an order log; it records no per-frame state. Every
   new per-soldier interaction must be order-stable and seed-driven, exactly like
   the current uid-keyed push. That means each soldier needs a **stable id**
   (e.g. `unit.uid * MAX_SOLDIERS + index`) to key tie-breaks and iteration order,
   and any randomness must draw from `Replay.rng` in a fixed order.
2. **Scale.** `max_soldiers` defaults to **120**. A few dozen regiments is then
   **thousands** of bodies, not dozens -- the separation pass goes from ~10²
   to ~10⁴ entities. The `SpatialHash` is the right tool but needs a soldier-sized
   cell and a per-soldier rebuild, and the per-frame cost has to be budgeted
   against the fixed 60 Hz tick. The engaged/unengaged level-of-detail below is
   what keeps the expensive pass bounded (~1,500 bodies, not ~5,000).
3. **Soft vs. hard semantics carry down.** The `_push_share` screen logic and the
   melee-intermixing softening are regiment-level today; the individual model has
   to reproduce "a spear line stops a charge" and "melee lines interpenetrate a
   little" out of soldier-level rules, not lose them.

## A phased plan

Each phase is independently shippable and testable (the GUT suite exercises the
sim logic headless -- no rendering needed), so collision correctness can be
verified before the next phase builds on it.

1. **[DONE] Promote marks to bodies, behind a flag.** Each soldier has a stable id
   (`soldier_id` = `uid * SOLDIER_ID_STRIDE + index`) and a world-space simulated
   position (`_sim_soldier_pos`) seeded from its formation slot (`seed_sim_soldiers`).
   The regiment circle stays authoritative; the soldier layer runs in parallel and
   the containment invariant is pinned in `test_soldier_bodies.gd`.
2. **[DONE] Soldier-level separation, engaged tier, within AND across regiments.**
   `_separate()`'s penetration/`_push_share` math is carried down to soldiers via the
   shared `_soldier_pair_push` helper (so the spear-vs-cavalry hard block falls out
   for free) and run for *engaged* soldiers only (front `Unit.engaged_ranks()` -- a
   depth scaled to the unit's own weapon reach and rank spacing, not a flat constant --
   with linger hysteresis). One global, deterministic pass (`Unit.separate_engaged_global`,
   orchestrated by `Battle` on `physics_frame`) gathers engaged soldiers across all
   regiments in soldier-id order, buckets them in the soldier-sized
   `SoldierSpatialHash`, and applies a Jacobi accumulate-then-apply step -- so enemy
   front ranks press into each other. (A debug overlay made the layer visible at this
   stage; phase 3 replaced it with the real soldier render.)
   **Superseded (#270):** this position-correction separation pass has since been
   retired. Soldiers never teleport -- friendly crowding is handled by a velocity-based
   avoidance pass (`SoldierSteering`, written into each body's feed-forward) and enemy
   contact by combat **knockback**, so spacing emerges from steering + press-vs-recoil
   rather than a per-tick position snap.
3. **[DONE] Render-as-reality.** The flock render (`_update_flock`) now follows
   `_sim_soldier_pos`: each mark's target gains the simulated body's collision push
   (~0 for the unengaged bulk, the real per-soldier separation for engaged front
   ranks), so the on-screen soldiers reflect the collision while keeping all the
   flock polish (formation, combat lunge, rank-cycling, relief corridor, colour). The
   debug overlay is retired. The visual is subtle until the soldiers gain persistent
   body dynamics / per-soldier combat (the next phase) -- today the sim re-seeds from
   formation each tick, so the soldiers hold formation and deform at contact rather
   than wandering as free bodies.
4. **Persistent bodies + combat at the individual level.** Give soldiers persistent
   dynamics -- they arrive at their slots while separating (bounded "arrive" steering
   instead of the current per-tick re-seed), so cohesion is emergent and soldiers can
   be displaced and hold the displacement. Then melee and missiles resolve against
   soldiers, so flanking and screening fall out of geometry. This is the first
   gameplay change (it **unblocks #240**, the sustained spear-vs-sword standoff) and
   where the rock-paper-scissors design meets per-soldier collision. The per-soldier
   combat resolution for this phase -- the opposed attack/defence rolls, health and
   stamina, knockback, prone, and the bracing chain -- is specified in
   [`combat-model.md`](combat-model.md). This phase ships in slices. **Phase 4a
   [DONE]** lands two non-authoritative foundations: (i) the combat math (per-type
   profile, charge term, facing gate, opposed land contest, and wound) as pure,
   unit-tested functions on `Unit`, and (ii) **persistent soldier-body dynamics** --
   the engaged front-rank bodies arrive at their slots under bounded force and integrate
   their own velocity (`step_sim_soldiers`), so a body knocked back in melee holds the
   displacement and returns instead of re-seeding onto formation each tick (the
   unengaged bulk feeds the unit's march velocity forward, tracking its slots at
   velocity with no teleport -- #270). The regiment circle still resolves
   casualties, exactly as phase 1 added the soldier-body state before later phases
   read it. **Phase 4b** wires the contest and wound into the live melee against a
   per-soldier health pool that accumulates on these persistent bodies (the first
   gameplay change; unblocks #240). A later slice (#270) retired the separation pass
   and added **knockback** as the enemy collision response; remaining slices add
   stamina, posture, and the prone/domino chain.
5. **Retire the regiment circle (in progress, shipping in slices).** Make soldiers
   authoritative for occupying space, so `RADIUS`-based `_separate()` becomes
   derived/diagnostic, then `#201`'s physics (mass, momentum, knock-back) layers on the
   soldier bodies.
   - **Slice 1 [DONE] -- friendly collision.** A soldier->regiment **coupling** slides each
     regiment's center toward its soldiers' centroid at a bounded velocity, never a snap
     (`SoldierBodies.couple` / `Unit.couple_all_sim_soldiers`, run as the last soldier
     sub-step in `Battle._on_soldier_tick`).
     The drift is measured against the slots, not against the centre,
     so it is ~0 during a clean march even for a block whose short rear rank puts its slot
     centroid off the centre: the coupling is silent except when bodies are pushed off formation.
     While the slots move and the men deliberately do not follow (an in-place turn)
     or walk onto new ones (a hold-ground re-square's short files),
     `couple` measures against the turn's starting slots, or leaves the walkers out.
     `SoldierSteering` gained a **friendly-contact tier**
     (regiment-broadphase-gated) that steers overlapping friendlies apart even when neither
     is fighting, carrying the move-through-idle / relief exemptions and the engaged-anchor
     asymmetry down from `_separate`. `_separate()` now **skips friendly pairs** -- the
     regiment circle separates ENEMIES only. So friendly regiments separate from the soldier
     layer up; the enemy front-rank closeup and the spear-vs-cavalry hard block are
     unchanged. Soldiers separate substantially (not yet to a perfect zero-overlap; the last
     residual is a later tuning refinement).
   - **Enemy collision -- deferred to #201, still blocked (see #296; #783 is fixed).** The next slice
     (move the not-both-engaged enemy separation + the spear-vs-cavalry hard block to the
     soldier level) hit a wall: the regiment's `_move_to` advances the charge (~170 u/s)
     independently of the soldier layer, and a velocity-only soldier push + the bounded
     body->regiment coupling cannot counteract it -- a charging cavalry rides clean through
     a spear line even at extreme tuning. Stopping a charge on a braced line is a
     **momentum/mass** problem, which is exactly what **#201** layers onto the soldier
     bodies (landed as #749). **#749 alone is not sufficient, though: a live-battle test
     (#296) found the charge still rode through -- #783 was the root cause
     (`SoldierBodies.couple()` averages drift over every soldier, diluting the resisted
     front rank's signal against the unengaged bulk), and #784 fixed it.** So enemy
     collision (and then retiring the regiment circle entirely, plus the `_push_share` /
     intermixing helpers it still uses) stays blocked -- no longer on #783, but on the
     residual first-contact overshoot transient #296's own thread records. Until then the regiment circle
     keeps resolving enemy collision (the `_front_depth` closeup and the hard block),
     unchanged. Friendly collision stays soldier-level (slice 1).

## Decisions (resolved)

The four design/perf trade-offs are settled:

1. **Bodies: plain data, not Godot nodes.** Soldiers are position/velocity arrays
   on the `Unit` (today's mark approach, extended) -- not thousands of
   `CharacterBody2D` nodes. This keeps determinism fully in our hands and reuses
   the existing `SpatialHash`; `move_and_slide` stays out of the deterministic
   simulation path.
2. **All 120 soldiers exist; only the engaged ones run the expensive sim.** Every
   soldier in `max_soldiers` is a real body, but the simulation runs at two levels
   of detail (see below) -- engaged soldiers get full per-soldier collision and
   combat, while the unengaged bulk just follows its formation slot cheaply.
3. **Target scale: budget for ~5,000 soldiers on the field, ~1,500 engaged at
   once.** A default 5v5 battle is ~1,020 soldiers (one side = Spearmen 140 +
   Infantry 120 + Archers 90 + Cavalry 80 + Cavalry 80 = 510); a large campaign
   stack (~20v20, the composition cycling) reaches ~4,000+. So the grid and
   per-frame budget are sized for **~5,000 total** bodies doing the cheap
   formation update, of which a realistic peak of **~1,000-1,500** are engaged and
   run the full collision/combat pass. This is the number to keep the 60 Hz tick
   under, and it's the figure to validate against #131's Pixel-6 ≥30 fps goal.
   **Update:** measured scaling of the engaged/friendly-contact tier is super-linear
   with soldier count -- see
   [`crowding-pressure-evaluation.md`](crowding-pressure-evaluation.md) for the
   benchmark data and why this budget is optimistic at higher density than the
   current reference scenario.
4. **Cross-platform replay: accept the same-build/platform-only caveat.** Soldier-
   level float ordering amplifies it, but bit-exact cross-platform replay stays out
   of scope -- no fixed-point position path. Determinism within a build/platform
   (the property replays and tests rely on) is still required.
   Re-affirmed 2026-09-19 against a measurement rather than an estimate;
   see "How large the cross-platform divergence actually is" below.

### How large the cross-platform divergence actually is

The caveat above was accepted on the reasoning that soldier-level float ordering
amplifies a platform difference,
without a figure for how big that difference starts out.
It now has one.

Windows 11 win64 against an `ubuntu-latest` runner,
same engine build (`4.7.stable.official.5b4e0cb0f`),
the `sidestep` clip,
both dumps taken through `website/tools/dump-demo-states.sh` so the two sides run an identical path:

| tick | components differing, of 2060 float32 | worst gap |
| --- | --- | --- |
| 8, 19, 20 | 0 | -- |
| **21** | **1** | **1 ulp** |
| 22 | 2 | 1 ulp |

The per-tick counts come from decoding the two `bit_dump.jsonl` files directly
and comparing every field,
not from `analyze_transcript.gd --compare-bit-dumps`.
That tool deliberately reports the **first** divergent field and stops
(`DemoBitDump.compare_dumps` returns on the first differing tick,
and `_first_unit_diff` on the first differing field within it),
so it answers "where does this start" and cannot answer "how much of the state moved".
Its whole reading on this pair is one line,
`DIVERGENT tick=21 uid=9 field=soldier[26].x a=d28abd44 b=d18abd44 ulps=1 (5 common ticks compared)`,
which is the table's first divergent row and none of the rest.

Three things the numbers settle, each of which had been open.

**It is rounding, not a divergent branch.**
Every differing component is one representable step.
A comparison flipping on one platform and not the other -- the mechanism previously suspected -- would show as a large gap rather than a single ulp.

**It enters in a soldier, not a unit.**
No unit position component differs at any dumped tick.
The perturbation therefore starts in the per-soldier body update and is carried up from there,
which is why it compounds gradually rather than displacing a formation at once.

**It is not melee-specific, and this is confirmation rather than news.**
The melee-knife-edge reading was already falsified by the hash streams,
which put the first divergent tick at 21 in four of the six clips measured --
`sidestep`, `support`, `cycle_charge` and `showcase` --
and at 61 and 60 in `rout_rally` and `general_doctrine_reserves`.
What rules melee out is not the tick number but `sidestep` itself,
which is a lone regiment side-stepping with no enemy in reach and diverges as early as any of them.
One contact-free witness is enough, and it is the only one:
the other three clips that diverge at tick 21 all reach contact,
so none of them could separate a melee cause from a pre-melee one.
`demos/README.md` has said so since #1557 merged on 2026-09-09,
and #1566 records the per-clip measurement behind it.
What the raw bits add is an elimination rather than an inference:
`SoldierCombat`'s land-chance sigmoid is the only `exp` on the per-soldier path,
and it is unreachable on `sidestep`, which has no enemy in reach,
so it is ruled out by construction instead of by the timing of the first divergence.
The surviving transcendental candidate is the `rotated()` round trip in `SoldierBodies._corridor_to_slot`,
on the post-spawn slot chase every clip runs.

**Not established.**
Whether the ulp originates inside `Vector2.rotated()` itself,
or in a per-soldier branch downstream of it.
A uniform `sin`/`cos` difference would be expected to perturb many of a unit's soldiers,
and exactly one component moved.
Settling it needs intermediate values dumped inside `_corridor_to_slot`,
and is only worth doing if this decision is revisited.

**Why the decision stands.**
One ulp in one of 2060 components is the floating-point noise floor.
Removing it costs a deterministic implementation for every transcendental on the per-tick path,
plus a bit-exactness gate in CI -- a permanent tax on the hot loop.
The user-visible symptom was addressed separately:
the demo defect sweep publishes the runner's own transcripts,
so a verdict is reproduced by re-judging that dump rather than by re-running the sim on a machine whose sim will not match it.
What remains lost is local reproduction of the sim itself off Linux,
and that is the price this decision accepts.

**Reproducing it.**
Arm `SPARTA_DEMO_BITDUMP` with a tick list alongside a state dump to write `bit_dump.jsonl`,
then compare two runs:

```
godot --headless --path . -s tools/demo/analyze_transcript.gd -- <dump-a> --compare-bit-dumps <dump-b>
```

It exits 1 on a difference, 0 on agreement,
and 2 on a missing or empty dump rather than reporting agreement.
On a difference it names the unit, the field, the axis,
and how many representable steps apart the two values are.
The Linux side comes from the demo defect sweep's `bit_ticks` dispatch input,
which writes the same file into the run's transcript artifact.
Run the comparison against a dump and itself first:
an empty result and a clean result are otherwise indistinguishable.

## Simulation level-of-detail (engaged vs. unengaged)

The key consequence of decisions 2 and 3: the per-frame cost is dominated by how
many soldiers are *engaged*, not by the total on the field. So soldiers run at two
tiers, re-evaluated each tick:

- **Engaged** -- a soldier at a regiment's contact face: in or near melee, being
  shot at, or pressed against an enemy/obstacle. Runs the full pass --
  soldier-vs-soldier separation on the soldier-sized `SpatialHash`, plus
  individual combat resolution. This is where flanking, screening, and chokepoints
  emerge from geometry.
- **Unengaged** -- the bulk of a regiment not in contact. Follows its formation slot
  as a cheap rigid offset from the regiment center (essentially today's behaviour),
  with no per-soldier neighbour scan. Promoted to *engaged* the moment an enemy or
  obstacle comes within range.

The engaged/unengaged flag must itself be deterministic (derived from positions and
states already in the sim, not wall-clock or frame-rate), so replays stay exact.
The promotion/demotion boundary uses linger hysteresis (`ENGAGED_LINGER`) so soldiers
don't flap between tiers at the threshold -- shipped in phase 2.

Phases 1-4 are live: the soldiers are simulated, separated across regiments, rendered at
their simulated positions, and **engaged melee resolves per-soldier and drives regiment
strength/morale** (the first gameplay change). The per-soldier reach model gives a longer
weapon the opening-strike advantage on the approach (#233); the fully *sustained*
asymmetric standoff of **#240 has now landed too**, via `SoldierMeleeStandoff.gd`: a
soldier that already outreaches (or matches) its nearest enemy holds its ground and never
gets a synthetic bias -- the existing landed-strike knockback (`SoldierMelee`/
`SoldierCombat`) is already a real, physically-motivated push-back mechanism, so a longer
reach's opening-strike advantage carries straight through the sustained case on its own,
with no extra force layered on top (an earlier version of this pass DID add a
backing-away bias for the longer-reach side; it was removed as exactly the kind of
top-down gimmick this design's "no regiment-level kite" stance already argued against).
The pass instead supplies only the other half: a per-soldier velocity bias, composed
additively into `_sim_steer` alongside `SoldierSteering`'s friendly-avoidance bias,
presses a shorter-reach soldier forward until it closes inside ITS OWN reach, so the
outreached side doesn't just stand and trade free hits for nothing. `Unit._press_into` and
`Unit._separate()`'s reach-independent front-depth floor are untouched, and the pass
composes with the existing physics (formation arrival, friendly steering, enemy contact,
knockback) rather than replacing any of it. The engaged tier's own depth is now also
reach-scaled (`Unit.engaged_ranks()`, replacing a flat 3-rank constant) -- a 48wu-reach
spear regiment at the historical 9wu rank pitch now fields up to 6 ranks able to strike
within their own weapon's reach, instead of being capped at 3 regardless of how deep the
formation actually runs. Measured on a 24 v 24 Spearmen-vs-Infantry demo
(`demos/inputs/spear-standoff.json`): the spear regiment holds its ground through the
whole clash rather than retreating; both sides trade losses as the sword presses in to
close the reach gap, but the spear's reach and rank-depth advantage give it a real edge
over the course of the clash (by tick 740, the spear holds 12/24 soldiers against the
sword's 10/24, neither side yet routing). The "give ground to hold reach distance" order
that follow-up promised has now landed too (#983), as `Unit.ORDER_GIVE_GROUND` /
`SoldierMeleeStandoff.give_ground_bias`: an explicit player-facing withdrawal, not the
passive default -- an engaged unit under this order backs away from its nearest enemy at a
constant rate REGARDLESS of reach comparison (no ramp, no reach gate), and overrides the
passive outreached-press bias above for the same soldier when both would otherwise apply.
The next authority slices are ranged resolution (per-shooter launch and per-target
opposed impact, replacing the regiment volley count -- see #1186) and
morale-from-soldier-state; retiring the regiment circle's enemy-collision
branches is unblocked on the momentum/mass side (#783 closed via #784's engaged-weighted
body coupling -- see the phase-5 note above) but still needs its own residual-transient fix
before that retirement is safe (tracked on #296).

## Melee-intermixing depth is gated by the defender's formation_mode

Two enemy regiments in sustained melee previously had no formation-mode-aware limit on
how deep the fighting could intermix: the regiment circle's engaged-vs-engaged closeup
(`Unit._separate`) only bounds the two blocks' *centres*, and the soldier-level contact
pass (`SoldierEnemyContact.accumulate`/`SoldierCollision.enemy_contact_impulse`) only
resolves actual body-radius overlaps -- so an attacker able to find (or open) a seam
between neighbouring defenders could press arbitrarily deep into the defending formation
regardless of how tightly that formation was packed. `Unit.formation_containment_margin`
closes that gap for the shield-wall-class tier: each defending soldier's own formation
widens the enemy-contact test radius that `SoldierEnemyContact.accumulate` resolves
against.

- **Shield-wall-class** (TIGHT/SQUARE/SCHILTRON/SHIELD_WALL/TESTUDO): the full margin
  (`FORMATION_CONTAINMENT_SCALE_TIGHT = 1.0`), unconditionally, so the front ranks hold
  contact with effectively no depth-wise intermixing -- a fallen defender's live neighbours
  still cover the gap.
- **NORMAL**: a smaller, also-unconditional margin
  (`FORMATION_CONTAINMENT_SCALE_NORMAL = 0.4`) -- "a couple of ranks deep", not a full
  block (see below for why it's flat rather than knockback-reactive).
- **LOOSE**: stays at zero -- the design intent is explicitly that a loose formation "can
  become deeply enmeshed."

Cavalry never contribute a margin (mounted formations don't interlock shields, and
`CAV_MARK_RADIUS`'s wider body would eat most of `SoldierSpatialHash.CELL_SIZE`'s own
headroom over the raw separation floor it's pinned against). The margin is scaled off
`soldier_body_radius()` rather than a flat metre value, so it stays proportionate to the
body it protects.

**Why NORMAL's margin is flat rather than knockback-reactive.** An earlier version of this
fix gave NORMAL a smaller margin that zeroed out for a specific body while that soldier was
prone -- letting a felled defender's own slot briefly cede ground to the attacker who felled
him, matching "a couple of ranks deep, as a knockback consequence, not a standing
steady-state overlap" more literally. That made the enemy-contact contact-*pair set* vary
per soldier, per tick, depending on which individual bodies happened to be prone -- and
`SoldierEnemyContact`'s contact-pair geometry is already the documented dominant source
of the "melee-lock swirl" torque bias (`.claude/memories/sparta.md`; see also
`test_residual_melee_swirl_battle.gd`'s regression guard and the `ANCHOR_RANKS` doc
comment on `Unit.gd`). That per-soldier heterogeneity measurably reintroduced the swirl
on CI (Linux) even though the guard test stayed under its threshold locally on Windows --
this sim is only deterministic *within* a build/platform, not bit-exact across them (see
"Decisions" above), so a chaotic-sensitive regression like this one can clear a local run
and still fail CI. Reverted, then replaced with the flat value used here: every NORMAL
soldier gets the identical margin regardless of prone state or tick, so the contact-pair
set never varies over time -- the same structural shape as TIGHT's own always-on margin,
which is not itself a swirl source. A regiment-level, knockback-reactive refinement (e.g.
an aggregate of how many engaged soldiers are currently prone, applied uniformly rather
than body-by-body) is still a possible follow-up if the reactive nuance is worth
pursuing.

## Blocks front to front meet at their front ranks

The margin above limits how far bodies mix once the two front ranks touch.
It cannot stop the larger interpenetration the regiment layer itself orders.
The regiment-level melee contact ranges (`_in_enemy_contact` and the others built the same way)
are weapon reach plus `Unit.RADIUS` (0.9 m) a side, measured centre to centre,
and the engaged floor in `_separate` is the two `_front_depth()` values,
each capped at half the unit's reach.
A block's real centre-to-front-rank distance grows by half a rank pitch for every rank,
so for an 8-rank block both fall short of it by two to three ranks.
Two such blocks closing front to front therefore came into contact
only after their front ranks had walked into each other
(no body contact resists them before the flag),
and the press then closed the centres to the capped floor,
with each grid's slots ordered most of a block deep inside the other.
Over the catalog's melee clips on main a3714751,
`tools/demo/melee-penetration.sh` (its `PEN-ALL foot` line) measured the median frontal foot pair
standing 3.0 ranks inside the other block, with 77% of pairs more than a rank inside.
With `MeleeFrontLine` the same measure reads 0.0 ranks and 25%;
20 of the 28 frontal foot pairs still past a rank were spawned inside each other, 16 of them in `cannae_scale`.
(The tool reads each block's front from its slot grid, `motion_ref.slot_grid.front`;
main's dumps lack that field, so its figures sign the front by facing, as the tool always did.)

`MeleeFrontLine` adds the missing depth back for a frontal pair:
each block's front-rank depth beyond `Unit.RADIUS` to the close-tier melee contact ranges
(each contact test goes through `MeleeFrontLine.within_contact`;
a router's anchor test, which shrinks the range on re-entry, measures the same gap),
and beyond its capped `_front_depth()` to the engaged floor,
both weighted by how squarely the two blocks face each other
(a flank or rear attack has its own weight, in
[Flank and rear attacks stop at the defender's edge](#flank-and-rear-attacks-stop-at-the-defenders-edge)).
A flank-anchored frontage stands its men off the block's position,
so the ranges are measured between the men's centres;
the gap moves from the positions to the men's centres by the same weight,
so it does not jump as a pair starts to face.
The directions read from a melee pair in contact take the bearing of that same gap
(`MeleeFrontLine.toward`):
the steering yield, the router's front arc, the leader's flank-threat bearing,
the flank multiplier (`UnitCombat.flank_multiplier`, which `OrderGuards.flanked` reads),
the shield wall's frontal test (`Unit._is_frontal_attack`),
the cycle charge's pull-back (which also opens its standoff past the contact extension),
and the point a fighting unit faces and presses toward (`Unit.contact_point`).
Two reads keep the positions:
a missile unit's facing as it shoots, since a missile unit takes no extension,
and the subcommander's outflanking bearing, which reads only enemies not yet in contact.
The engaged floor pushes along that gap too.
The neighbourhood lookup that finds a pair adds each block's whole anchor shift to its reach past the radius,
since no contact range counts the shift.
Contact then starts as the front ranks come within reach,
and the press stops with them on one line.
Pairs with cavalry, missile troops or a far-tier block keep the centre-based ranges
(`MeleeFrontLine`'s doc comment says why).
A square fronts every way:
a line meeting it frontally reaches its slot rectangle's extent toward the line,
so the pair keeps its extended range when a block it was pressing forms square.

The weight reads where each block's men face, not its heading:
a heading turn the grid absorbs (a router's about-face),
or an engage or order turn still in progress (the men stand fast until it settles),
leaves the pair's ranges where its men still stand.
It multiplies how directly the two grid fronts oppose each other
by the share of the narrower front that overlaps the other's, across the pair's front axis.
A pair offset to one side keeps that share of the extension however far the press closes it,
so the floor cannot fall as the pair closes.
The depth is a file-major block's deepest surviving file,
which its grid centres on.
The engaged fraction's neighbourhood lookup widens the same way.
Auto-acquisition, the router sweep and the support stance's guard also count an enemy in frontal contact past their search radius
(the support stance measures that contact from its ward),
when nothing inside the radius qualifies.
The morale's 6 m local-force radius and the rally check's `RALLY_CONTACT_RADIUS` stay as they were,
and also count an enemy in melee contact at the pair's frontal range,
so a frontal enemy held at its front rank, past either radius, still counts as close.
`SoldierMelee`'s knockback "clear the line" distance keeps the capped `_front_depth()` sum:
it is how far a struck man travels, not a distance between centres.

The sprint window (`Unit.SPRINT_START_DISTANCE`) stays measured centre to centre,
so a charge into a deep block meets its front ranks with that much less of the sprint behind it,
and the charge bonus is lower for it.
Opening the window past the contact extension moved first contact up to 165 ticks earlier than main in `cycle_charge`
and added defect candidates in `charge` and `knockback_focus`,
so it is left for a follow-up.

Holding the blocks at their front ranks lowers frontal lethality,
since only the front ranks reach each other.
Measured with two 120-man Tight blocks (`last_unit_rally`'s staging on main) and neither allowed to break (morale 100),
casualties over the first 1150 ticks fell from a mean of 47 to 37 men over the clip's own seed and perturbed seeds 1 to 4.
The block standing its ground lost 11 instead of 23,
and the advancing block about the same (26 against 24).
Units take correspondingly longer to break in a straight frontal fight:
in the perturbed melee-outcome delta,
`general_doctrine_reserves`' low-morale foot and `march_to_contact`'s unit 1 mostly no longer break inside their clips,
and `file_major_reform_contrast` and `spear_standoff` break 100 to 145 ticks later.

### Flank and rear attacks stop at the defender's edge

A block whose front faces another block's flank or rear is met the way a square is:
the attacker reaches its own front rank,
and the defender reaches its slot rectangle's extent along the attacker's front
(`MeleeFrontGeometry.outline`): its front-rank depth for a rear attack,
its front half-width for a flank attack.
So the attacker's front rank stops on the defender's rear rank or end file.
This side part of the weight multiplies the same two terms as the frontal part,
with the attacker's front as the axis:
how far the defender lies ahead of that front (a ramp over one `Unit.RADIUS`)
and how much of that front overlaps the defender's outline across it.
When both blocks' fronts bear on each other (an L-shaped meeting),
the pair takes the larger of the two orientations' weights and their reaches averaged by weight.

The side part is gated on the angle between the two fronts (`MeleeFrontLine.side_gate`).
It is 0 down to a cosine of `melee_side_contact_max_cos` (0.75, about 41 degrees off square)
and reaches its whole weight at `melee_front_line_min_cos` (0.5),
where the frontal part has fallen to 0.
Two separate properties follow.
The weight is continuous in the angle:
both parts are continuous and they hand over at the ends of the gate,
the frontal part falling to 0 at the cosine where the gate reaches 1,
so the weight does not jump as a clash turns from oblique to flank
(a test sampling every degree finds no step above 0.05 at the default values).
And the frontal ramp plus the side gate never exceeds 1:
as the cosine rises between the two values the gate falls from 1 to 0 at least as fast as the ramp rises from 0,
and outside them one of the two is 0,
so the pair's weight, which multiplies each by terms of at most 1, is at most 1 too.
The bound holds at every angle for any values of the two parameters,
and continuity for any `melee_front_line_min_cos` from -1 to below 1.
At 1 or above, the frontal ramp is itself a step at square: 1 head on, 0 at any other angle.
Below -1 the ramp is still above 0 when both fronts point the same way,
where the pair's front axis (one front and the other reversed) vanishes and flips side,
so the frontal part steps at exactly 180 degrees
(a test turns the defender through 180 degrees 60 wu to either side of the attacker's centre line
and asserts a step of more than 0.05 at a min cosine of -1.5 and of at most 0.005 from -1 up).
Two details of `side_gate` keep them under other tunings: it caps both parameters at 1,
so with the min cosine above 1 the gate still reaches 0 head on, where the ramp is 1
(a test sweeps the gate plus the ramp over cosines from 1 to -1 for ten tunings,
among them a min cosine of 1.2 and of -1.5, and a head-on pair with the min cosine at 1.2 weighs exactly 1);
and when the max cosine is tuned at or below the min cosine
the gate rises from 0 at the min cosine to 1 at the max cosine,
or over at least `MeleeFrontLine.SIDE_GATE_MIN_SPAN` (0.25, the defaults' own span),
instead of stepping at the min cosine.
A clash within about 41 degrees of square is weighed by the frontal part alone,
exactly as before:
the frontal lethality probe (two 120-man blocks, Tight, Normal and Loose order,
the clip's seed and perturbed seeds 1 to 4) reads a bit-identical per-tick hash stream to main 2c2955cc's.
A line's extension bound (`MeleeFrontProfile.ext`, which the contact reject and the
neighbourhood lookup read) is its slot rectangle's half-diagonal,
the farthest its outline reaches along any axis.

Measured with two 120-man Infantry blocks in Tight order, neither allowed to break,
the defender spawned facing away (rear) or side-on (flank),
over the first 1150 ticks on the clip's seed and perturbed seeds 1 to 4.
On main 2c2955cc the attacker's front-rank slots settled 3.9 ranks inside the defender in a rear attack
and 8.1 file pitches inside it on a flank;
with the side contact their slots settle on average 0.8 and 0.9 ranks short of the defender's edge.
The attacker's front-rank men then stand 1.7 (rear) and 2.7 (flank) ranks from the defender's outermost men,
as a frontal pair's front ranks stand 2.4 ranks apart in the same probe.
The attacker's losses fall from 11.0 to 0 men in the rear and from 18.2 to 2.6 on a flank,
since the defender's men facing away cannot strike back,
and the defender's from 46.4 to 39.4 and from 20.0 to 17.6,
since only the attacker's front rank reaches it.

A routing defender is left out: `_side_part` weighs 0 any orientation whose defender is `ROUTING`,
so a pursuer behind or beside a fleeing block keeps the centre-based range and presses in among its ranks,
and the router's anchor contact and `_can_rally`'s contact read the ranges they read on main.
A router whose own front bears on an enemy's flank still meets it there.
Without this exception a pursuer stopped at the router's rear rank and struck only that rank.
Measured with a brittle 120-man Infantry block (morale 0.5) in Tight order
between two 120-man Infantry blocks at morale 100,
one 120 wu south of it facing it and one 190 wu north of it facing it,
over the clip's seed and perturbed seeds 1 to 4:
it turns north on breaking, flees past the north block and leaves the field by tick 1474 to 1634.
At tick 900 it fields on average 105.6 men on main 2c2955cc,
111.2 with the side contact applied to routers,
and 97.6 with routers left out.
By its first routing sample it has lost 0 to 2 men on main (tick 300) and none with the side contact (tick 270),
so the 8 men it loses beyond main's fall in the pursuit,
but what costs them comes before the rout, where the exception does not reach: it breaks sooner.
The north block comes on against the router's rear,
and with the side contact it is in contact at the tick-210 sample (30-tick samples), 80 to 83 wu from the router's centre,
at the router's rear rank, where on main its first contact sample is tick 240, 46 to 53 wu from the centre;
the router's morale falls faster (1.6 or 1.7 at tick 240 against 2.2 on main),
and it breaks at tick 270 instead of 300 on all five seeds, before losing a man.
With the side contact turned off for the north block's pairs until the router breaks
(and on for them after, a probe-only change), it breaks at tick 300 as on main and fields 104.8 men at tick 900;
turned off for them only after it breaks, it breaks at 270 and fields 98.8.
Turning it off for the south block's pairs changes no sample:
the south block stands in front of the router until the rout and behind it after,
where the exception already has it press in centre to centre.
With a single Infantry pursuer (the router an Infantry or a Spearmen block, otherwise the same staging)
the pursuer does not catch the router while it routs:
the rout and rally are identical to main's at every 30-tick sample on all five seeds,
with or without the exception, and the runs diverge only after the router rallies,
when the pursuer meets the rallied block's rear.

### An enemy inside a block is struck by the men around him

Only a block's near-front ranks strike (`Unit.engaged_soldier_indices`),
and the front follows the slot grid,
so an enemy that has got in behind those ranks would never be struck.
`SoldierInteriorStrike` finds such enemies, and `SoldierMelee`'s interior pass,
after the striking ranks have struck, has every other man of the block strike the nearest one within his reach.
It draws nothing when nobody is inside, so a fight without one is bit-identical to one without the pass.

A point is inside a block when it lies behind the rearmost man of the striking set along `Unit.near_front_forward`
and within the block's footprint:
the grid's own rectangle (`MeleeFrontGeometry.grid_front`, `MeleeFrontProfile`) about the live men's mean,
padded on the flanks and rear by `Unit.interior_strike_margin` (0 by default).
An enemy soldier counts when both he and his unit's position are inside.
The unit test is what keeps the pass to intruders.
Without it, any enemy man behind the rearmost striker counted,
and in ordinary clashes the enemy's front-rank men,
which jitter level with and a little past a block's striking ranks,
were struck by the ranks behind for the whole fight.
A Loose block's striking set is its front rank alone, so this was worst there:
on the merge of #1834 onto #1845 (5edea880),
two 120-man Loose blocks spawned 120 wu apart lost 14.0 and 9.0 men by tick 1150 (seed runs 0 to 4) against 8.4 and 7.8 on main 82991008,
and the pass fired in 23 of 117 catalog clips.
Requiring the man to stand a whole rank pitch or more behind the rearmost striker was tried first
and did not separate the cases:
at one and at one and a half pitches the pass still fired in 22 of the 117 clips,
since in a deep clash the enemy's leading men are pushed several ranks in.
Testing the unit's position against the footprint alone, without the striking set,
still took in a small unit fighting front to front whose centre had reached the block's front ranks:
in `general_doctrine_reserves` a 30-man block's few men pushed past the striking ranks were struck from behind,
and its three 30-man blocks broke in 12 or 13 of 16 perturbed runs where on main they broke in 2 (on 6ed15a50).

With both tests, on 5679cf3c against main 82991008, over seed runs 0 to 4:
two 120-man blocks closing front to front from 400 wu apart, in Tight, Normal and Loose order,
the same blocks spawned 120 wu apart in Tight and Normal order,
and the rear and flank probes of the previous section in Tight and Normal order (and the rear in Loose)
never fire the pass and end bit-identical to main.
Two Loose blocks spawned 120 wu apart start inside each other, and the pass fires once on each run, at tick 2;
a Loose block spawned on another's flank fires it once, at tick 80.
In the catalog it fires in 19 of the 117 clips (18 of which change),
each time on an enemy unit whose centre is behind the striking ranks:
an infantry block among a cavalry squadron, whose single striking rank stands well ahead of its roomy footprint's centre
(`schiltron`, `square`, `charge`, `cycle_charge`, and in `battle_ai_leaders`),
blocks spawned on top of each other (`cannae_scale`, `sweep_routers`),
blocks that have run more than half their depth into each other (`battle_ai_leaders`' infantry),
small parties and lone men among a block (`small_unit_melee`, `coast_to_stop`, `subcommander_mutual_support`),
and a block that routs and rallies with its pursuer pressed in among it.
In the router probe of the previous section without the north block,
the rout and the rally are unchanged on all five seeds,
and the rallied block, striking the pursuer inside it, costs it 29.4 men by tick 2400 against 24.8 on main.
The perturbed melee-outcome delta (K 16, Benjamini-Yekutieli) against main flags 5 rows, against 13 with the unit's position tested against the footprint alone (6ed15a50):
`subcommander_mutual_support`'s one-man unit inside the cavalry is cut down in 14 of 16 runs where it survived in 14,
`battle_ai_leaders` loses 7 and 8 more men a side, and `cycle_charge_flee` one more.
A square has no interior pass, since it already strikes with whoever is threatened;
nor has a routing block, and a routing enemy is never inside,
so a router overrun by its pursuer is cut down only by the pursuer's own striking ranks.

## Physical contact is proximity-based, not combat-state-based

Both the margin above and the underlying soldier-level pass it widens
(`SoldierEnemyContact.accumulate`) used to gather soldiers via
`Unit.engaged_soldier_indices()` -- gated entirely on `is_engaged()`, a COMBAT-state
decision (`state == FIGHTING`, with a short linger). That conflated two genuinely
different questions: "is this regiment fighting" (a gameplay/order choice) and "is this
regiment's body touching an enemy's" (a physical fact). A unit under a plain move order
with no attack target deliberately never fights an enemy it walks into -- `_think()`'s own
"disengage" comment: "Fight when in contact, UNLESS the player gave a plain move order
with no explicit attack target -- that's a disengage command." But that combat decision
was ALSO silently disabling every soldier-level collision check for that unit: with
`engaged_soldier_indices()` empty, none of its soldiers ever entered
`SoldierEnemyContact.accumulate`'s pooled array, so its bodies had zero physical
resistance against an enemy they were geometrically inside of -- the regiment marched
straight through, no different from an obstacle-free field. (The regiment-circle backstop
in `_separate()` had the same gap on its tighter, engaged-only `_front_depth()` floor.)

Fixed by decoupling the two: `Unit._in_enemy_contact` is a PURE PROXIMITY flag -- true
whenever any live enemy regiment is within melee contact range (`attack_range + both
RADII`), computed unconditionally every tick in `_think()` (mirroring the existing
`_under_fire` check, before any order-branch early return, so it's fresh regardless of
which branch a given tick takes). `Unit.contact_soldier_indices()` is a new selection,
sharing the exact same near-front geometry as `engaged_soldier_indices()`
(`_select_near_front_indices`) but gated on `is_engaged() OR _in_enemy_contact` rather
than `is_engaged()` alone. `SoldierEnemyContact.accumulate` and `_separate()`'s enemy
branch both switched to this proximity-inclusive gate; `engaged_soldier_indices()` itself
-- and everything downstream of it (melee striking, `SoldierSteering`) -- is untouched, so a
disengaging unit still deals and takes no melee damage and its morale is unaffected by the
brush; only its bodies now physically resist.

**The regiment's own position anchor had the same gap, and closing it took two attempts.**
#783 (SoldierBodies.couple() averaging position drift over every soldier body, diluting a
fighting regiment's resisted front rank against its unengaged bulk -- the "charge rides
through a braced line" bug) was already fixed by #784, which weighted `couple()`'s anchor
toward `Unit.position_anchor_indices()`'s narrower live-front selection instead of the
whole-block centroid. But `position_anchor_indices()` (and the `near_front_soldier_indices()`
it calls) gated on `is_engaged()` alone, same as everything else above did before this PR --
so a disengaging unit's `couple()` call still fell through to the whole-block-centroid
average, and its position (and therefore every soldier's formation-slot target) diluted
right through contact the same way #783 documented for a charging regiment, just never
fixed for a merely-marching one.

Extending both functions to `is_engaged() OR _in_enemy_contact` (mirroring the exact
decoupling this PR applies everywhere else) was tried and reverted first, tracked as
[#1136](https://github.com/Lacaedemon/sparta/issues/1136): it made
`test_collision_knockback_battle.gd`'s live 900-tick showcase-scenario regression guard
hang indefinitely (reproduced in isolation, not a flake -- a plain, no-coverage run of just
that one test never completed). Not root-caused at the time; the position anchor is a much
more sensitive piece of code than the contact-resolution/`_separate()` changes above -- its
own doc comments and this file's "Decisions" section already record a history of subtle
swirl/instability regressions from narrowing its selection, and widening WHICH units
qualify for it (not just how narrow the selection is once they do) was an untested new axis.

Landed on the second attempt, with the identical diff: reproducing on a from-scratch clone
(both the single hanging test and the FULL 2642-test suite, on both Windows and native
Linux, same Godot 4.7.0 build) found no hang at all -- every run completed cleanly, well
under any CI timeout. The original hang's cause was never identified; the working
hypothesis is a platform/build-specific floating-point divergence rather than a
deterministic property of this code, consistent with the chaos-sensitivity this file's own
"Decisions" section already documents for a sibling test. If a live-battle test in this
family hangs again, that history -- and this note -- are the first things to revisit before
assuming a fresh regression.

The position-anchor gap is closed; the kinematic drive now yields too.
Verified empirically against the site's showcase clip
(`demos/showcase.json`, seed 12345): a "disengaging" unit now visibly takes real contact
resistance (and casualties, since the enemy's own attack still lands) it took none of
before. `_move_to()` itself also yields on an orderly (player-move / disengage) march:
it strips the component of the commanded step that would walk the block into a
contacting enemy, and bleeds `_current_speed` when that leftover is zero, so the
rear ranks are not kept pressing into an arrested front. Combat approaches
(`formed_turn`, not orderly) still close -- they have to cover the gap between
either-side contact range and this unit's own `in_contact` gate, after which
`_press_into` takes over.

## Collision damage: hard contact converts dissipated kinetic energy into health loss

`SoldierCollision.enemy_contact_impulse` resolves closing velocity **fully inelastically**
(no bounce-back -- see its own doc comment) whenever two enemy soldier bodies are in
contact. That resolution genuinely dissipates kinetic energy every tick, but until this
section landed nothing attached a consequence to it beyond the existing skill-roll-driven
strike damage (`SoldierCombat.wound`) -- a fast, hard impact and a gentle graze arrested the
same way as far as health was concerned.

`SoldierCombat.collision_damage(delta_v)` converts a soldier's actual velocity change this
tick into health loss (`COLLISION_DAMAGE_SCALE * delta_v.length_squared()`) -- a deceleration-
based severity measure (the same shape real crash-injury metrics use), not a literal
kinetic-energy split. An earlier version derived damage independently from each pair's raw
closing speed and effective masses (a `0.5 * mu * closing_speed^2` reduced-mass split); review
on the introducing PR found three compounding bugs in that approach -- no cap across a
soldier's simultaneous contacts (mirroring the exact "multi-pair force accumulation" bug this
file's own "Decisions" section already documents for the velocity pipeline), full KE
recomputed from scratch every tick during a multi-tick arrest (overcounting total damage
1.4-2x for a realistic charge), and a mass-split formula that made a **braced/heavier**
defender take **more** absolute damage against a much heavier attacker, not less -- inverting
what bracing is supposed to do.

**Fixed by deriving damage from the velocity pipeline's own output instead of an independent
recompute.** `SoldierEnemyContact.accumulate` flags which soldiers had at least one pair clear
`SoldierCombat.is_hard_collision`'s real-closing-speed threshold (`COLLISION_DAMAGE_MIN_SPEED`
-- never the synthetic overlap-correction term, so ordinary sustained pushing between two
packed lines causes zero extra damage), then -- AFTER the existing multi-pair trim and
per-tick `KNOCKBACK_SPEED_MAX` cap have fully resolved each soldier's actual velocity change
for the tick -- computes damage from that real, already-bounded delta. This automatically
inherits both of the velocity pipeline's existing correctness properties (the multi-pair cap
and the per-tick bound) with no separate bookkeeping, and automatically gets the bracing
direction right: a heavier/braced body always receives a *smaller* velocity change from the
same contact (`enemy_contact_impulse`'s own effective-mass split), so it always takes less
damage too -- no separate asymmetry formula to get backwards.

`COLLISION_DAMAGE_MIN_SPEED` and `COLLISION_DAMAGE_SCALE` are tunable constants, threaded as
overridable parameters on `is_hard_collision`/`collision_damage` respectively (see
`SoldierCombat.gd`'s own comments for the calibration reasoning); both need playtesting, not
just derivation.
