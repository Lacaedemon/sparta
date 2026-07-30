# Design note: individual-level collision

Status: **phases 1-4 landed; engaged melee is now soldier-authoritative** (behind
`Unit.INDIVIDUAL_COLLISION`, ON). Soldiers are seeded as world-space bodies from their
formation slots, separated across regiments on a soldier-sized `SoldierSpatialHash`, and
the flock render follows those positions. Phase 4 wired the per-soldier combat model
(`combat-model.md`) into live melee: `UnitCombat.strike` routes engaged, non-ranged
combat to `SoldierMelee.resolve`, which resolves the opposed land contest and wound
against per-soldier health, reaps the dead, and drives `unit.soldiers` — so casualties,
morale, rout, and the HUD now read soldier deaths for the engaged-melee case. Knockback,
prone, depth bracing, and stamina are wired (#201 slices A-D); friendly soldier collision
is soldier-level (phase 5 slice 1).

**Still regiment-level (the remaining authority work):** ranged casualties (decrement
`soldiers` and trim arbitrary rear bodies, not arrow-targeted), morale (a regiment scalar,
not derived from soldier state), and **enemy** soldier-vs-soldier collision + retiring the
regiment circle — the last is deferred to **#201** (stopping a charge needs momentum/mass;
see the phase-5 note below and #296). #201's momentum physics landed (#749), but a live
empirical test (#296) found it does NOT yet arrest a charge on its own; #783 was the root
cause, and #784 fixed it. Retiring the regiment circle stays blocked, but on the residual
first-contact overshoot transient recorded in #296's own thread — not on #783, which is
closed (see the phase-5 note below). Posture/graded bracing and the rearward domino
cascade are also deferred. The design decisions are settled (see
"Decisions" below).

Tracks [#164](https://github.com/Lacaedemon/sparta/issues/164) (collision at the
individual level, not the unit level) and
[#192](https://github.com/Lacaedemon/sparta/issues/192) (individuals occupy space
and don't overlap). It's the groundwork for the physics model in
[#201](https://github.com/Lacaedemon/sparta/issues/201), which layers metric
units, mass, and knock-back *on top of* individual bodies — so individual
collision has to land first.

This is the project's **#1 design pillar** (see [`PLAN.md`](../PLAN.md)), and
changing it touches the determinism guarantees that make replays work. So it gets
a design pass before code.

## Where collision is today

The simulation collides **regiments, not soldiers**. Each `Unit` is one circular
body and `_separate()` (`scripts/Unit.gd`) resolves regiment-vs-regiment overlap:

- A unit is a circle of `RADIUS = 18`. The *separation floor* is per-type —
  `SEPARATION_RADIUS_INFANTRY = 18`, `SPEARMEN = 20`, `CAVALRY = 24`, capped at
  `SEPARATION_RADIUS_MAX = 28` — kept below melee reach so lines press into
  contact instead of bouncing apart.
- Each frame a unit pushes out of any overlapping unit by a `_push_share` of the
  penetration: `0.5` for a normal pair (each corrects half), but `0`/`1` for a
  spear screen vs. cavalry so horses can't ride through (the existing hard-block).
- Neighbours come from `SpatialHash` (`CELL_SIZE = 128`), rebuilt once per tick,
  replacing the old O(n²) scan. A co-located pair fans apart along a **uid-keyed**
  angle so the push is deterministic across a run and its replay.

Individual soldiers already exist, but **only as decoration**. `_soldier_pos` /
`_soldier_vel` (the "flock marks", `MARK_RADIUS = 1.7`, `CAV_MARK_RADIUS = 2.6`,
`FORMATION_SPACING = 3.4`) are a cosmetic layer — the file says plainly they are
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
   **thousands** of bodies, not dozens — the separation pass goes from ~10²
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
sim logic headless — no rendering needed), so collision correctness can be
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
   `SoldierSpatialHash`, and applies a Jacobi accumulate-then-apply step — so enemy
   front ranks press into each other. (A debug overlay made the layer visible at this
   stage; phase 3 replaced it with the real soldier render.)
   **Superseded (#270):** this position-correction separation pass has since been
   retired. Soldiers never teleport — friendly crowding is handled by a velocity-based
   avoidance pass (`SoldierSteering`, written into each body's feed-forward) and enemy
   contact by combat **knockback**, so spacing emerges from steering + press-vs-recoil
   rather than a per-tick position snap.
3. **[DONE] Render-as-reality.** The flock render (`_update_flock`) now follows
   `_sim_soldier_pos`: each mark's target gains the simulated body's collision push
   (~0 for the unengaged bulk, the real per-soldier separation for engaged front
   ranks), so the on-screen soldiers reflect the collision while keeping all the
   flock polish (formation, combat lunge, rank-cycling, relief corridor, colour). The
   debug overlay is retired. The visual is subtle until the soldiers gain persistent
   body dynamics / per-soldier combat (the next phase) — today the sim re-seeds from
   formation each tick, so the soldiers hold formation and deform at contact rather
   than wandering as free bodies.
4. **Persistent bodies + combat at the individual level.** Give soldiers persistent
   dynamics — they arrive at their slots while separating (bounded "arrive" steering
   instead of the current per-tick re-seed), so cohesion is emergent and soldiers can
   be displaced and hold the displacement. Then melee and missiles resolve against
   soldiers, so flanking and screening fall out of geometry. This is the first
   gameplay change (it **unblocks #240**, the sustained spear-vs-sword standoff) and
   where the rock-paper-scissors design meets per-soldier collision. The per-soldier
   combat resolution for this phase — the opposed attack/defence rolls, health and
   stamina, knockback, prone, and the bracing chain — is specified in
   [`combat-model.md`](combat-model.md). This phase ships in slices. **Phase 4a
   [DONE]** lands two non-authoritative foundations: (i) the combat math (per-type
   profile, charge term, facing gate, opposed land contest, and wound) as pure,
   unit-tested functions on `Unit`, and (ii) **persistent soldier-body dynamics** —
   the engaged front-rank bodies arrive at their slots under bounded force and integrate
   their own velocity (`step_sim_soldiers`), so a body knocked back in melee holds the
   displacement and returns instead of re-seeding onto formation each tick (the
   unengaged bulk feeds the unit's march velocity forward, tracking its slots at
   velocity with no teleport — #270). The regiment circle still resolves
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
   - **Slice 1 [DONE] — friendly collision.** A soldier->regiment **coupling** slides each
     regiment's center toward its soldiers' centroid at a bounded velocity, never a snap
     (`SoldierBodies.couple` / `Unit.couple_all_sim_soldiers`, run as the last soldier
     sub-step in `Battle._on_soldier_tick`). Because the formation slots are centred, the
     drift is ~0 during a clean march, so the coupling is silent except when bodies are
     pushed off formation. `SoldierSteering` gained a **friendly-contact tier**
     (regiment-broadphase-gated) that steers overlapping friendlies apart even when neither
     is fighting, carrying the move-through-idle / relief exemptions and the engaged-anchor
     asymmetry down from `_separate`. `_separate()` now **skips friendly pairs** — the
     regiment circle separates ENEMIES only. So friendly regiments separate from the soldier
     layer up; the enemy front-rank closeup and the spear-vs-cavalry hard block are
     unchanged. Soldiers separate substantially (not yet to a perfect zero-overlap; the last
     residual is a later tuning refinement).
   - **Enemy collision — deferred to #201, still blocked (see #296; #783 is fixed).** The next slice
     (move the not-both-engaged enemy separation + the spear-vs-cavalry hard block to the
     soldier level) hit a wall: the regiment's `_move_to` advances the charge (~170 u/s)
     independently of the soldier layer, and a velocity-only soldier push + the bounded
     body->regiment coupling cannot counteract it — a charging cavalry rides clean through
     a spear line even at extreme tuning. Stopping a charge on a braced line is a
     **momentum/mass** problem, which is exactly what **#201** layers onto the soldier
     bodies (landed as #749). **#749 alone is not sufficient, though: a live-battle test
     (#296) found the charge still rode through — #783 was the root cause
     (`SoldierBodies.couple()` averages drift over every soldier, diluting the resisted
     front rank's signal against the unengaged bulk), and #784 fixed it.** So enemy
     collision (and then retiring the regiment circle entirely, plus the `_push_share` /
     intermixing helpers it still uses) stays blocked — no longer on #783, but on the
     residual first-contact overshoot transient #296's own thread records. Until then the regiment circle
     keeps resolving enemy collision (the `_front_depth` closeup and the hard block),
     unchanged. Friendly collision stays soldier-level (slice 1).

## Decisions (resolved)

The four design/perf trade-offs are settled:

1. **Bodies: plain data, not Godot nodes.** Soldiers are position/velocity arrays
   on the `Unit` (today's mark approach, extended) — not thousands of
   `CharacterBody2D` nodes. This keeps determinism fully in our hands and reuses
   the existing `SpatialHash`; `move_and_slide` stays out of the deterministic
   simulation path.
2. **All 120 soldiers exist; only the engaged ones run the expensive sim.** Every
   soldier in `max_soldiers` is a real body, but the simulation runs at two levels
   of detail (see below) — engaged soldiers get full per-soldier collision and
   combat, while the unengaged bulk just follows its formation slot cheaply.
3. **Target scale: budget for ~5,000 soldiers on the field, ~1,500 engaged at
   once.** A default 5v5 battle is ~1,020 soldiers (one side = Spearmen 140 +
   Infantry 120 + Archers 90 + Cavalry 80 + Cavalry 80 = 510); a large campaign
   stack (~20v20, the composition cycling) reaches ~4,000+. So the grid and
   per-frame budget are sized for **~5,000 total** bodies doing the cheap
   formation update, of which a realistic peak of **~1,000–1,500** are engaged and
   run the full collision/combat pass. This is the number to keep the 60 Hz tick
   under, and it's the figure to validate against #131's Pixel-6 ≥30 fps goal.
   **Update:** measured scaling of the engaged/friendly-contact tier is super-linear
   with soldier count — see
   [`crowding-pressure-evaluation.md`](crowding-pressure-evaluation.md) for the
   benchmark data and why this budget is optimistic at higher density than the
   current reference scenario.
4. **Cross-platform replay: accept the same-build/platform-only caveat.** Soldier-
   level float ordering amplifies it, but bit-exact cross-platform replay stays out
   of scope — no fixed-point position path. Determinism within a build/platform
   (the property replays and tests rely on) is still required.

## Simulation level-of-detail (engaged vs. unengaged)

The key consequence of decisions 2 and 3: the per-frame cost is dominated by how
many soldiers are *engaged*, not by the total on the field. So soldiers run at two
tiers, re-evaluated each tick:

- **Engaged** — a soldier at a regiment's contact face: in or near melee, being
  shot at, or pressed against an enemy/obstacle. Runs the full pass —
  soldier-vs-soldier separation on the soldier-sized `SpatialHash`, plus
  individual combat resolution. This is where flanking, screening, and chokepoints
  emerge from geometry.
- **Unengaged** — the bulk of a regiment not in contact. Follows its formation slot
  as a cheap rigid offset from the regiment center (essentially today's behaviour),
  with no per-soldier neighbour scan. Promoted to *engaged* the moment an enemy or
  obstacle comes within range.

The engaged/unengaged flag must itself be deterministic (derived from positions and
states already in the sim, not wall-clock or frame-rate), so replays stay exact.
The promotion/demotion boundary uses linger hysteresis (`ENGAGED_LINGER`) so soldiers
don't flap between tiers at the threshold — shipped in phase 2.

Phases 1-4 are live: the soldiers are simulated, separated across regiments, rendered at
their simulated positions, and **engaged melee resolves per-soldier and drives regiment
strength/morale** (the first gameplay change). The per-soldier reach model gives a longer
weapon the opening-strike advantage on the approach (#233); the fully *sustained*
asymmetric standoff of **#240 has now landed too**, via `SoldierMeleeStandoff.gd`: a
soldier that already outreaches (or matches) its nearest enemy holds its ground and never
gets a synthetic bias — the existing landed-strike knockback (`SoldierMelee`/
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
reach-scaled (`Unit.engaged_ranks()`, replacing a flat 3-rank constant) — a 48wu-reach
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
passive default — an engaged unit under this order backs away from its nearest enemy at a
constant rate REGARDLESS of reach comparison (no ramp, no reach gate), and overrides the
passive outreached-press bias above for the same soldier when both would otherwise apply.
The next authority slices are ranged casualties (kill soldiers in the
health pool) and morale-from-soldier-state; retiring the regiment circle's enemy-collision
branches is unblocked on the momentum/mass side (#783 closed via #784's engaged-weighted
body coupling — see the phase-5 note above) but still needs its own residual-transient fix
before that retirement is safe (tracked on #296).

## Melee-intermixing depth is gated by the defender's formation_mode

Two enemy regiments in sustained melee previously had no formation-mode-aware limit on
how deep the fighting could intermix: the regiment circle's engaged-vs-engaged closeup
(`Unit._separate`) only bounds the two blocks' *centres*, and the soldier-level contact
pass (`SoldierEnemyContact.accumulate`/`SoldierCollision.enemy_contact_impulse`) only
resolves actual body-radius overlaps — so an attacker able to find (or open) a seam
between neighbouring defenders could press arbitrarily deep into the defending formation
regardless of how tightly that formation was packed. `Unit.formation_containment_margin`
closes that gap for the shield-wall-class tier: each defending soldier's own formation
widens the enemy-contact test radius that `SoldierEnemyContact.accumulate` resolves
against.

- **Shield-wall-class** (TIGHT/SQUARE/SCHILTRON/SHIELD_WALL/TESTUDO): the full margin
  (`FORMATION_CONTAINMENT_SCALE_TIGHT = 1.0`), unconditionally, so the front ranks hold
  contact with effectively no depth-wise intermixing — a fallen defender's live neighbours
  still cover the gap.
- **NORMAL**: a smaller, also-unconditional margin
  (`FORMATION_CONTAINMENT_SCALE_NORMAL = 0.4`) — "a couple of ranks deep", not a full
  block (see below for why it's flat rather than knockback-reactive).
- **LOOSE**: stays at zero — the design intent is explicitly that a loose formation "can
  become deeply enmeshed."

Cavalry never contribute a margin (mounted formations don't interlock shields, and
`CAV_MARK_RADIUS`'s wider body would eat most of `SoldierSpatialHash.CELL_SIZE`'s own
headroom over the raw separation floor it's pinned against). The margin is scaled off
`soldier_body_radius()` rather than a flat metre value, so it stays proportionate to the
body it protects.

**Why NORMAL's margin is flat rather than knockback-reactive.** An earlier version of this
fix gave NORMAL a smaller margin that zeroed out for a specific body while that soldier was
prone — letting a felled defender's own slot briefly cede ground to the attacker who felled
him, matching "a couple of ranks deep, as a knockback consequence, not a standing
steady-state overlap" more literally. That made the enemy-contact contact-*pair set* vary
per soldier, per tick, depending on which individual bodies happened to be prone — and
`SoldierEnemyContact`'s contact-pair geometry is already the documented dominant source
of the "melee-lock swirl" torque bias (`.claude/memories/sparta.md`; see also
`test_residual_melee_swirl_battle.gd`'s regression guard and the `ANCHOR_RANKS` doc
comment on `Unit.gd`). That per-soldier heterogeneity measurably reintroduced the swirl
on CI (Linux) even though the guard test stayed under its threshold locally on Windows —
this sim is only deterministic *within* a build/platform, not bit-exact across them (see
"Decisions" above), so a chaotic-sensitive regression like this one can clear a local run
and still fail CI. Reverted, then replaced with the flat value used here: every NORMAL
soldier gets the identical margin regardless of prone state or tick, so the contact-pair
set never varies over time — the same structural shape as TIGHT's own always-on margin,
which is not itself a swirl source. A regiment-level, knockback-reactive refinement (e.g.
an aggregate of how many engaged soldiers are currently prone, applied uniformly rather
than body-by-body) is still a possible follow-up if the reactive nuance is worth
pursuing.

## Physical contact is proximity-based, not combat-state-based

Both the margin above and the underlying soldier-level pass it widens
(`SoldierEnemyContact.accumulate`) used to gather soldiers via
`Unit.engaged_soldier_indices()` — gated entirely on `is_engaged()`, a COMBAT-state
decision (`state == FIGHTING`, with a short linger). That conflated two genuinely
different questions: "is this regiment fighting" (a gameplay/order choice) and "is this
regiment's body touching an enemy's" (a physical fact). A unit under a plain move order
with no attack target deliberately never fights an enemy it walks into — `_think()`'s own
"disengage" comment: "Fight when in contact, UNLESS the player gave a plain move order
with no explicit attack target — that's a disengage command." But that combat decision
was ALSO silently disabling every soldier-level collision check for that unit: with
`engaged_soldier_indices()` empty, none of its soldiers ever entered
`SoldierEnemyContact.accumulate`'s pooled array, so its bodies had zero physical
resistance against an enemy they were geometrically inside of — the regiment marched
straight through, no different from an obstacle-free field. (The regiment-circle backstop
in `_separate()` had the same gap on its tighter, engaged-only `_front_depth()` floor.)

Fixed by decoupling the two: `Unit._in_enemy_contact` is a PURE PROXIMITY flag — true
whenever any live enemy regiment is within melee contact range (`attack_range + both
RADII`), computed unconditionally every tick in `_think()` (mirroring the existing
`_under_fire` check, before any order-branch early return, so it's fresh regardless of
which branch a given tick takes). `Unit.contact_soldier_indices()` is a new selection,
sharing the exact same near-front geometry as `engaged_soldier_indices()`
(`_select_near_front_indices`) but gated on `is_engaged() OR _in_enemy_contact` rather
than `is_engaged()` alone. `SoldierEnemyContact.accumulate` and `_separate()`'s enemy
branch both switched to this proximity-inclusive gate; `engaged_soldier_indices()` itself
— and everything downstream of it (melee striking, `SoldierSteering`) — is untouched, so a
disengaging unit still deals and takes no melee damage and its morale is unaffected by the
brush; only its bodies now physically resist.

**The regiment's own position anchor has the same gap, tried here and reverted.** #783
(SoldierBodies.couple() averaging position drift over every soldier body, diluting a
fighting regiment's resisted front rank against its unengaged bulk — the "charge rides
through a braced line" bug) was already fixed by #784, which weighted `couple()`'s anchor
toward `Unit.position_anchor_indices()`'s narrower live-front selection instead of the
whole-block centroid. But `position_anchor_indices()` (and the `near_front_soldier_indices()`
it calls) gate on `is_engaged()` alone, same as everything else above did before this PR —
so a disengaging unit's `couple()` call still falls through to the whole-block-centroid
average, and its position (and therefore every soldier's formation-slot target) dilutes
right through contact the same way #783 documented for a charging regiment, just never
fixed for a merely-marching one.

Extending both functions to `is_engaged() OR _in_enemy_contact` (mirroring the exact
decoupling this PR applies everywhere else) was tried and reverted: it made
`test_collision_knockback_battle.gd`'s live 900-tick showcase-scenario regression guard
hang indefinitely (reproduced in isolation, not a flake — a plain, no-coverage run of just
that one test never completes). Not yet root-caused; the position anchor is a much more
sensitive piece of code than the contact-resolution/`_separate()` changes above — its own
doc comments and this file's "Decisions" section already record a history of subtle
swirl/instability regressions from narrowing its selection, and widening WHICH units
qualify for it (not just how narrow the selection is once they do) is an untested new axis.
Left as a known, real, but not-yet-safely-closed follow-up rather than risk landing a hang
in a live-battle-critical path -- tracked on
[#1136](https://github.com/Lacaedemon/sparta/issues/1136).

**This — and the position-anchor gap above — do not fully close the underlying issue
either way.** Verified empirically against the site's showcase clip
(`demos/showcase.json`, seed 12345): a "disengaging" unit now visibly takes real contact
resistance (and casualties, since the enemy's own attack still lands) it took none of
before, but `_move_to()` — the code driving that unit's own kinematic march toward its
destination — is still not itself gated by contact at all. It keeps commanding `position`
forward at full march speed every tick regardless; the soldier/regiment-level resistance
above only pushes back afterward, bounded, each tick — a tug-of-war between an unbounded
kinematic drive and a bounded physical response, not the drive itself yielding to contact.
Closing it fully needs `_move_to()` itself (or the regiment's overall kinematic advance) to
yield to contact, not just be resisted after the fact — a change to core movement code
shared by every unit in the game, deliberately out of scope here.

## Collision damage: hard contact converts dissipated kinetic energy into health loss

`SoldierCollision.enemy_contact_impulse` resolves closing velocity **fully inelastically**
(no bounce-back — see its own doc comment) whenever two enemy soldier bodies are in
contact. That resolution genuinely dissipates kinetic energy every tick, but until this
section landed nothing attached a consequence to it beyond the existing skill-roll-driven
strike damage (`SoldierCombat.wound`) — a fast, hard impact and a gentle graze arrested the
same way as far as health was concerned.

`SoldierCombat.collision_damage(delta_v)` converts a soldier's actual velocity change this
tick into health loss (`COLLISION_DAMAGE_SCALE * delta_v.length_squared()`) — a deceleration-
based severity measure (the same shape real crash-injury metrics use), not a literal
kinetic-energy split. An earlier version derived damage independently from each pair's raw
closing speed and effective masses (a `0.5 * mu * closing_speed^2` reduced-mass split); review
on the introducing PR found three compounding bugs in that approach — no cap across a
soldier's simultaneous contacts (mirroring the exact "multi-pair force accumulation" bug this
file's own "Decisions" section already documents for the velocity pipeline), full KE
recomputed from scratch every tick during a multi-tick arrest (overcounting total damage
1.4-2x for a realistic charge), and a mass-split formula that made a **braced/heavier**
defender take **more** absolute damage against a much heavier attacker, not less — inverting
what bracing is supposed to do.

**Fixed by deriving damage from the velocity pipeline's own output instead of an independent
recompute.** `SoldierEnemyContact.accumulate` flags which soldiers had at least one pair clear
`SoldierCombat.is_hard_collision`'s real-closing-speed threshold (`COLLISION_DAMAGE_MIN_SPEED`
— never the synthetic overlap-correction term, so ordinary sustained pushing between two
packed lines causes zero extra damage), then — AFTER the existing multi-pair trim and
per-tick `KNOCKBACK_SPEED_MAX` cap have fully resolved each soldier's actual velocity change
for the tick — computes damage from that real, already-bounded delta. This automatically
inherits both of the velocity pipeline's existing correctness properties (the multi-pair cap
and the per-tick bound) with no separate bookkeeping, and automatically gets the bracing
direction right: a heavier/braced body always receives a *smaller* velocity change from the
same contact (`enemy_contact_impulse`'s own effective-mass split), so it always takes less
damage too — no separate asymmetry formula to get backwards.

`COLLISION_DAMAGE_MIN_SPEED` and `COLLISION_DAMAGE_SCALE` are tunable constants, threaded as
overridable parameters on `is_hard_collision`/`collision_damage` respectively (see
`SoldierCombat.gd`'s own comments for the calibration reasoning); both need playtesting, not
just derivation.
