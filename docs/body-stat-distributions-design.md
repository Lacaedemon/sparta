# Design note: per-soldier body stat distributions

Status: **design only -- nothing implemented.**
No per-soldier height, body mass, strength, or speed exists in the tree today;
every soldier in a regiment is mechanically identical.
This note pins down what would have to change, where the numbers would come from, and
how a per-soldier draw stays replay-deterministic, so a later slice can be scoped
against something concrete instead of re-deriving all of it.

It answers the scoping comment on the tracking issue, which asked for a design pass
before code and named four open questions: cosmetic versus mechanical, the data source
for the distributions, the RNG and replay-determinism plumbing, and the per-soldier
array shape.

## Motivation

Every soldier in a regiment currently shares one stat block.
`SoldierCombat.profile_for` returns a single dictionary per unit -- one `skill`, one
`armour`, one `max_health`, one `max_stamina`, one `body_mass_kg` -- and
`SoldierBodies.seed` `fill()`s the per-soldier arrays with those same values, so two
hundred men in a phalanx are two hundred copies of one man.

That is wrong on the history and wrong on the feel.
A line of hoplites was not two hundred identical bodies;
it was a distribution,
and the tails of that distribution are where the interesting behaviour lives -- the big
man who does not go down when he is shoved, the small man who does, the fast man who
arrives at the enemy line first and dies alone.
The project already models mass in real kilograms end to end (see
`docs/soldier-loadout-design.md`), which means the machinery to make a heavier man
genuinely harder to knock over is already in place and simply has nothing varying to
feed it.

The request is also explicitly for **creatures**, not only men: horses and elephants
differ by breed and species far more than men differ from each other, and the
`Mount` type already carries a real `mass_kg` that a per-animal draw could vary.

## Where the per-soldier state is today

Verified against `scripts/Unit.gd`, `scripts/UnitCombat.gd`, `scripts/SoldierCombat.gd`,
`scripts/SoldierBodies.gd`, and `scripts/GaitLimits.gd` at this branch's merge base.

### Per-soldier arrays that exist

`Unit` keeps per-soldier state as parallel `Packed*Array`s, index-aligned with
`_sim_soldier_pos` and, with one exception noted below, compacted together when men die:

- `_sim_soldier_pos`, `_sim_body_vel`, `_sim_steer`, `_sim_soldier_facing` --
  `PackedVector2Array`, parent-local (not world-space; see the array's own doc comment
  in `Unit.gd`).

- `_sim_soldier_hp`, `_sim_prone`, `_sim_soldier_stamina`,
  `_sim_soldier_shield_hold_angle` -- `PackedFloat32Array`.

- `_sim_soldier_weapon_id`, `_sim_soldier_shield_id`, `_sim_soldier_file`,
  `_sim_soldier_rank`, `_sim_soldier_square_slot`, `_sim_soldier_row_slot` --
  `PackedInt32Array`.

- `_sim_soldier_broken` -- `PackedByteArray`.

One exception matters for the contract a new array has to join.
`_sim_soldier_facing` is index-aligned like the rest but is *not* compacted in
`SoldierMelee.reap()`, which never touches it;
it is instead re-derived on the next tick by the size-mismatch resize in
`SoldierBodies.step` (`scripts/SoldierBodies.gd`), which either reseeds the tail at the
unit heading during an owned maneuver or refills the whole array from
`Unit.soldier_world_facings`.
That works because facing is recomputable from formation state.
A drawn body stat is not recomputable, so it cannot take the facing route and must join
the reap walk explicitly.

None of these is a *body* stat.
Health and stamina are pools, not physique;
the loadout ids are equipment;
the rest is geometry and formation bookkeeping.

### Per-unit stats a body stat would have to displace

`Unit` carries the movement envelope as four exported scalars: `move_speed = 90.0`
(sprint), `jog_speed = 67.5`, `walk_speed = 45.0`, and `accel = 30.0` / `decel = 60.0`.
At `WorldScale.WU_PER_M = 20.0` those are 4.5, 3.375, and 2.25 m/s.
`Unit._current_speed` moves toward a `pace_speed` chosen per tick from those three, and
every soldier body in the unit is fed from the same number.

`SoldierCombat.profile_for(is_cavalry, anti_cavalry, is_ranged, training, armor_id,
mount_id)` returns the combat block.
Its four branches set `body_mass_kg` to 75 (cavalry), 80 (anti-cavalry), 70 (ranged),
and 80 (other foot), and derive the relative contact scalar as
`relative_mass_from_kg(body_mass_kg)` against `CONTACT_MASS_BASELINE_KG = 80.0`.
`skill` is just the unit's clamped `training`.
There is no strength term anywhere: melee wounding runs off the weapon's `lethality`
(`Unit.soldier_lethality`, resolved through the per-soldier weapon id) and the charge
factor, never off the man swinging it.

### The gait cap, which a speed draw immediately collides with

`GaitLimits.SUPERPHYSICAL_SPEED_FRAC = 1.15` caps a body's integrated velocity at that
multiple of its unit's sprint pace.
`Unit.superphysical_speed_frac` is an exported per-unit override defaulting to it, and
`tools/demo/DemoDefects.gd` re-exports the same constant as
`DemoDefects.SUPERPHYSICAL_SPEED_FRAC`, computing
`cap = sprint * SUPERPHYSICAL_SPEED_FRAC` for the `superphysical_speed` demo-defect
check, so the engine and the audit metric agree by construction.

This is the sharpest concrete integration hazard in the whole feature.
A per-soldier speed multiplier above 1.0 pushes a fast man's body toward that cap from
below, and a draw wide enough to be interesting will cross it -- at which point either
the engine silently clamps away the variation the draw exists to create, or the demo
metric starts flagging legitimate fast men as a physics defect.
Any speed phase has to move the cap onto the per-soldier factor on both sides at once.

### The player-visible-number rule

`docs/units-convention.md` requires that a physically-derived length or speed constant
be authored in metres and folded at parse time as `<metres> * WorldScaleRef.WU_PER_M`,
that runtime state stay in world units with no conversion in hot loops, and that no raw
world-unit number reach the player.
`scripts/DistanceLegend.gd` is the display boundary: `metres_for_world(world_units,
world_units_per_metre)` and `mps_for_world_speed(...)` plus the `label_text` helpers.
Mass is already exempt from that conversion because it is stored in absolute kilograms
(`body_mass_kg`), which `docs/soldier-loadout-design.md` states is deliberate -- the HUD
reports kilograms, never the relative contact scalar.

So: a per-soldier **height** would be drawn in metres, converted once at spawn (a
boundary conversion, not a hot-loop one), stored in world units, and displayed through
`DistanceLegend.metres_for_world`.
A per-soldier **mass** stays in kilograms throughout and is displayed directly.
A per-soldier **speed** follows height's rule.

## Where the numbers come from

Three tiers, and they are not equally solid.
Saying so plainly matters more than picking tidy figures, because the tiers fail
differently and a later implementer needs to know which numbers to re-derive.

**Every figure below must be re-verified against the cited source
before it is written into code.**
They are recorded here as the shape of the answer and the place to look, not as
already-checked constants.

### Tier 1: stature, from skeletons, directly evidenced

Stature is the one body stat ancient skeletal remains speak to well.
Long-bone length regresses onto living stature by the standard method of Trotter and
Gleser (Trotter, M. and Gleser, G. C., "Estimation of stature from long bones of
American Whites and Negroes", *American Journal of Physical Anthropology* 10 (1952),
463-514), and the European Holocene series compiled by Ruff and colleagues gives
period-by-period means for exactly the populations of interest (Ruff, C. B., Holt,
B. M., Niskanen, M., et al., "Stature and body mass estimation from skeletal remains in
the European Holocene", *American Journal of Physical Anthropology* 148 (2012),
601-617).

For Roman Italy specifically, Kron argues a mean adult male stature of roughly 168 cm
from published skeletal samples (Kron, G., "Anthropometry, physical anthropology, and
the reconstruction of ancient health, nutrition, and living standards", *Historia* 54
(2005), 68-83).
Koepke and Baten's long European series puts first-millennium European male stature in
roughly the same range (Koepke, N. and Baten, J., "The biological standard of living in
Europe during the last two millennia", *European Review of Economic History* 9 (2005),
61-95).

Two cautions the design has to carry, not bury:

- **The observed spread of *estimates* is not the population spread.**
  A Trotter-Gleser individual estimate carries a standard error of several centimetres
  on top of whatever the population actually varied by, so the standard deviation of a
  published estimate series is inflated.
  Male stature standard deviation in living reference populations sits near 6 to 7 cm,
  and that is the better prior for a draw.

- **Sample selection is not neutral.**
  Cemetery populations are not army populations, and armies selected for size in some
  periods and did not in others.
  Treating a civilian skeletal mean as a soldier mean is an assumption, and it should be
  a named, tunable offset rather than an invisible one.

### Tier 2: body mass, from skeletons, weakly evidenced

Body mass can be estimated from skeletal frame size (bi-iliac breadth plus stature) or
from femoral head diameter, and the Ruff et al. series above reports it alongside
stature.
The error is materially larger than for stature, and the two estimates are correlated
with each other rather than independent, which matters for the draw: height and weight
must be drawn **jointly**, not as two independent normals, or the roster fills with
physically impossible men.

The practical form is to draw stature, then draw a body-mass index conditional on it, so
mass follows from height times a build factor.
That keeps the joint distribution sane without needing a defensible covariance matrix
from the archaeology, which does not exist at the precision the sim would imply.

### Tier 3: strength and speed, not evidenced at all

There is no ancient evidence for either.
Skeletons carry activity markers, not newtons, and no ancient source records a
distribution of running speeds.
Both therefore come from **modern reference distributions rescaled by body size**, and
the document should say so where a player might otherwise read a false precision.

- **Strength.**
  Grip strength is the best-normed proxy with published means and standard deviations by
  age and sex (Dodds, R. M., Syddall, H. E., Cooper, R., et al., "Grip strength across
  the life course: normative data from twelve British studies", *PLoS ONE* 9 (2014),
  e113637; and Massy-Westropp, N. M., Gill, T. K., Taylor, A. W., et al., "Hand grip
  strength: age and gender stratified normative data in a healthy population", *BMC
  Research Notes* 4 (2011), 127).
  Peak young-adult male values in those series sit in the high 40s of kilograms-force
  with a coefficient of variation around 0.15 to 0.20.
  Muscle force scales with physiological cross-sectional area, so strength scales
  roughly as mass to the two-thirds power rather than linearly (Jaric, S., "Muscle
  strength testing: use of normalisation for body size", *Sports Medicine* 32 (2002),
  615-631) -- which is the allometric exponent the draw should use to derive a
  strength factor from a drawn mass, so a heavier man is stronger but not
  proportionally so.

- **Speed.**
  The ancient sources give **march rates**, not sprint speeds.
  Vegetius records the Roman military step as twenty Roman miles in five summer hours,
  and the full step as twenty-four (Vegetius, *Epitoma rei militaris* 1.9); at the
  conventional 1478 m Roman mile that is about 1.6 m/s and about 2.0 m/s respectively.
  Modern load-carriage physiology gives sustained loaded marching speeds in the same
  neighbourhood, around 1.2 to 1.4 m/s, and quantifies how load slows a man (Knapik,
  J. J., Reynolds, K. L., and Harman, E., "Soldier load carriage: historical,
  physiological, biomechanical, and medical aspects", *Military Medicine* 169 (2004),
  45-56).
  Note that the sim's current `walk_speed` of 2.25 m/s already sits above the Vegetian
  full step, so the existing gait ladder is faster than the historical one;
  a speed phase should decide whether to keep that or rescale it,
  and that decision belongs to a separate issue rather than riding along inside a
  variation slice.

### Creatures

Deferred to a later phase, but the sources are the same shape.

Horse withers height is estimated from metapodial length by published multiplication
factors (von den Driesch, A. and Boessneck, J., "Kritische Anmerkungen zur
Widerristhoehenberechnung aus Laengenmassen vor- und fruehgeschichtlicher
Tierknochen", *Saeugetierkundliche Mitteilungen* 22 (1974), 325-348), and Roman cavalry
mounts are conventionally placed around 14 to 15 hands, well below a modern warmblood
(Hyland, A., *Equus: The Horse in the Roman World*, London, 1990).
Steppe ponies were smaller again.

War elephants split by species: the Asian elephant and the now-extinct North African
forest elephant, the latter markedly smaller, which is the whole point of Polybius'
account of Raphia, where Ptolemy's African elephants would not face Antiochus' Indian
ones (Polybius, *Histories* 5.84).
A per-species mass distribution on `Mount` is the natural home,
since `Mount.mass_kg` already flows into contact mass through
`SoldierCombat.relative_mass_from_kg(mount.mass_kg)`.

## Proposed mechanism

### Storage

Four new per-soldier arrays on `Unit`, index-aligned with `_sim_soldier_pos`, seeded in
`SoldierBodies.seed`, extended by the same tail-resize path the existing arrays use, and
compacted in `SoldierMelee.reap()` (`scripts/SoldierMelee.gd`), which hand-writes a
guarded `remove_at(i)` for every parallel per-soldier array as each casualty is spliced
out:

- `_sim_soldier_height` -- `PackedFloat32Array`, world units.

- `_sim_soldier_mass_kg` -- `PackedFloat32Array`, kilograms (matching `body_mass_kg`).

- `_sim_soldier_strength` -- `PackedFloat32Array`, dimensionless factor centred on 1.0.

- `_sim_soldier_speed` -- `PackedFloat32Array`, dimensionless factor centred on 1.0.

`SoldierMelee.reap()` is the single most bug-prone integration site in this feature.
It walks the dead high-to-low and hand-writes a `remove_at(i)` per array:
`_sim_soldier_pos`, `_sim_body_vel`, and `_sim_soldier_hp` unconditionally, then
`_sim_steer`, `_sim_prone`, `_sim_soldier_stamina`, `_sim_soldier_weapon_id`,
`_sim_soldier_shield_id`, `_sim_soldier_shield_hold_angle`, `_sim_soldier_file`, and
`_sim_soldier_broken`, each behind its own size guard.
The three arrays carrying permutation semantics (`_sim_soldier_rank`,
`_sim_soldier_square_slot`, `_sim_soldier_row_slot`) go through
`UnitFormation.drop_rank_assignment` and `UnitFormation.drop_slot_assignment` instead,
because dropping an index there also has to renumber the survivors' assignments.
A new array omitted from that walk de-aligns from `_sim_soldier_pos` on the first melee
death, with no error and no crash;
every surviving soldier's body stats shift by one index for the remainder of the battle.
The four new arrays are plain per-soldier values with no permutation to preserve, so
each takes the simple `remove_at(i)` form, added in the same change that introduces the
array.

`reap()` is the most bug-prone site but not the only one.
Three further places in the tree enumerate every parallel per-soldier array by hand, and
each silently de-aligns or drops a new one if it is not extended in the same change:

- **Far-tier demotion and promotion** (`scripts/TierTransition.gd`).
  `demote()` clears every per-soldier array outright, and `promote()` rebuilds them from
  the unit's aggregate state using an RNG seeded by
  `TierTransition.promotion_seed(uid, tick, battle_seed)`, whose own comment states it is
  never the shared `Replay.rng` stream.
  A drawn body stat therefore cannot simply persist across a far-tier round trip: it is
  discarded on demotion and has to be reconstructed on promotion from that local seed,
  not from the spawn-time stream.
  This is the site that forces the uid-hash question below.

- **Unit serialization** (`Unit.to_dict()` / `Unit.from_dict()` in `scripts/Unit.gd`).
  Each array is named explicitly in both directions, so a new one that is not added there
  is lost across any snapshot round trip.

- **`Battle.SIM_SOLDIER_ARRAY_KEYS`** (`scripts/Battle.gd`).
  This constant lists the snapshot keys the rearguard-detachment split truncates to the
  detachment's own headcount;
  an omitted array leaves the detachment holding the parent's full-length copy.

An acceptance test for phase 1 should exercise a demote-promote round trip and a
`to_dict()`/`from_dict()` round trip, not only a `reap()` compaction.

That is sixteen bytes per soldier on top of the existing per-soldier footprint.
If that proves too much at the target soldier counts, the fallback is to quantise each
factor into a `PackedByteArray` -- a value in [0, 255] mapped onto a fixed range -- for
four bytes total, at the cost of a dequantise in the read path.
Do not take the fallback pre-emptively;
measure first,
per the repo's habit of not optimising ahead of a number.

The two derived factors (`strength`, `speed`) are stored rather than recomputed because
the read sites are hot loops;
the two physical quantities (`height`, `mass_kg`) are stored because they are what the
HUD reports and what a save or replay would have to round-trip.

### The draw

A `BodyStats` helper (proposed path `scripts/BodyStats.gd`, does not exist today), a
leaf script in the style of `scripts/GaitLimits.gd` and `scripts/WorldScale.gd` with no
preloads of its own, holding:

- The distribution parameters as named constants with defaults, per the repo's
  caller-configurable-parameters convention: a mean stature, a stature standard
  deviation, a build-factor mean and standard deviation, the per-unit-type mass means
  (defaulting to today's `SoldierCombat.profile_for` figures), a strength coefficient of
  variation, a speed coefficient of variation, and a truncation width in standard
  deviations.

- A pure static `draw(rng, params) -> Dictionary` returning one soldier's stature, mass,
  strength factor, and speed factor, drawing stature first and conditioning mass on it
  so the pair stays jointly plausible.

- A per-culture parameter table, if and when a phase needs one;
  the first phase uses a single global distribution shape,
  per the scoping comment's suggested narrower slice.

Defaults, all overridable and all subject to the re-verification note above: stature
mean 1.68 m and standard deviation 0.065 m, truncated at plus or minus three standard
deviations so no soldier is impossible;
mass derived from stature and a build factor whose mean is keyed on the unit's own
existing body mass, so the existing balance point is preserved exactly;
strength and speed factors centred on 1.0 with coefficients of variation around 0.15 and
0.05 respectively.

That mass mean is per-unit-type from phase 1, not deferred to the per-culture phase.
`SoldierCombat.profile_for` already sets four distinct body masses -- 75 kg cavalry,
80 kg anti-cavalry, 70 kg ranged, and 80 kg for other foot -- so a single global 80 kg
mean would silently reweight two of the four classes even at zero variance, moving an
archer's relative contact mass from 0.875 to 1.0 and a rider's from 0.9375 to 1.0
against `SoldierCombat.CONTACT_MASS_BASELINE_KG`.
The global part of the phase 1 distribution is therefore its *shape* -- the stature
spread and the build-factor spread -- while its mass mean reads today's per-type figure.
Phase 6's per-culture and per-mount tables are a different axis and do not substitute for
this.

Speed gets the much tighter spread deliberately -- both because running speed varies
less across a population than strength does, and because of the
`SUPERPHYSICAL_SPEED_FRAC` collision above.
Ship the speed phase only once the cap has been moved onto the per-soldier factor.

### Determinism

This is the part with the least room for improvisation.

`scripts/Replay.gd` holds exactly one seeded stream, `Replay.rng`, whose seed is set
once per battle by `start_recording()` or `start_playback()`;
the file states plainly that nothing else may call `randomize()` or set `.seed` on that
stream, or replays silently desync.
`Replay.forced_seed` defaults to -1 and, when non-negative, is used verbatim as that
battle's seed and then consumed back to -1, which is how the scripted-input demo
recorder (`tools/demo/DemoInputRecorder.gd`) makes a live recording reproducible.

So the draw **must** come from `Replay.rng`, in a fixed order, at a fixed point:
inside `SoldierBodies.seed`, iterating soldiers by index, drawing each man's four values
before moving to the next.
Fixed order is not a nicety.
The stream is shared with combat, so any change to how many values the spawn path
consumes shifts every later draw in the battle, and a spawn-order change silently
invalidates every recorded replay and every demo scenario.

Two consequences follow, and both are acceptance criteria rather than notes:

- **The spawn fingerprint has to cover the draw.**
  `Replay.spawn_fingerprint` and `Replay.last_load_spawn_mismatch` already exist to
  catch a replay recorded against a layout this build no longer produces.
  Per-soldier stats are part of that layout now, so the fingerprint should include them
  and the mismatch warning should fire when a distribution parameter changes.

- **Tail resizes draw too, and in the same stream.**
  Reinforcement or any path that grows a unit's soldier arrays after the initial seed
  must draw from the same stream at that moment, not from a fresh generator.

- **The draw is unconditional, and `variation_enabled` does not gate it.**
  The flag controls only what is *stored*: with it false the drawn values are discarded
  and each array is filled with that soldier's unit-type baseline, so the stream advances
  by the same four values per soldier either way.
  A flag that skipped the draw would make the stream depend on a tuning parameter, which
  would move the desync from one known phase to whichever later phase flips the flag, and
  again on any future rebalance.
  The cost of drawing-and-discarding is four `randf` calls per soldier, once, at spawn.

- **Phase 1 is the single re-record point, and it is not optional.**
  Because the draw is unconditional, phase 1 advances `Replay.rng` by four values per
  soldier before any combat roll, so every recorded replay under `demos/` and every
  scripted-input demo diverges from its recording at that phase.
  The `Replay.spawn_fingerprint` mismatch is the intended loud signal.
  Phase 1 therefore ships a re-record sweep of every `demos/` replay and every
  `demos/inputs/` scenario in the same PR, and no later phase re-records again, because
  no later phase changes how many values the spawn path consumes.

An alternative worth considering and rejecting explicitly: deriving each soldier's stats
from a hash of `(unit uid, soldier index, battle seed)` rather than from the shared
stream.
That is attractive because it is order-independent and immune to the shifting-stream
problem above.
It would not violate the replay contract.
That contract forbids calling `randomize()` or setting `.seed` on `Replay.rng`
elsewhere, and a pure hash of three already-deterministic inputs does neither and
introduces no randomness at all.

It would also not be a new convention.
`TierTransition.promotion_seed(uid, tick, battle_seed)` is exactly this idiom already:
it returns `hash([uid, tick, battle_seed])` and seeds a local RNG that the code comment
describes as never the shared `Replay.rng` stream (`scripts/TierTransition.gd`).
Adopting a hash for body stats would follow that precedent rather than establish one.
(The stable left/right lane tie-break keyed on `uid` in `scripts/Unit.gd` is a different
thing and is not evidence either way: it derives a deterministic *choice* from a uid, not
a pseudo-random per-entity value.)

It is deferred rather than rejected, on two grounds.
One stream is one thing to reason about, one thing the spawn fingerprint has to cover,
and one place a later reader has to look to answer "where did this number come from".
And the shared-stream draw is what makes the phase 1 re-record below a single, bounded
event rather than a recurring one.

The promotion path is the thing most likely to force the hash.
Promotion has to reconstruct per-soldier stats without touching `Replay.rng`, and a hash
of `(uid, soldier index, battle seed)` reconstructs them exactly, where a local
Gaussian draw would not reproduce the men the unit had before it was demoted.
If phase 1's promotion reconstruction proves unsatisfying, adopt the hash deliberately
for body stats as a whole and record it in `Replay.gd` beside the existing contract, so
the derivation is documented rather than quietly introduced.

### What it changes

- **Contact and knockback.**
  `SoldierCombat.knockback_impulse`, `anchor_capacity`, `translational_impulse`,
  `partition_impulse`, and `prone_chance` all take a `defender_mass`, currently the
  unit-wide `combat_profile()["mass"]`.
  They would take the struck soldier's own derived relative mass.
  This is the change with the most gameplay value per unit of work, because the
  machinery is entirely in place and only the input is uniform.

- **Melee outcome.**
  `SoldierCombat.wound` takes a `lethality_a`;
  a strength factor multiplies it,
  so a stronger man wounds harder with the same weapon.
  Whether strength should also enter `land_chance` (which currently takes `skill` from
  `training`) is an open question below -- strength and skill are different things and
  conflating them would be a modelling error, not a shortcut.

- **Gait.**
  A per-soldier speed factor scales each body's target pace in `SoldierBodies.step`,
  subject to the cap discussion above.

- **Fatigue.**
  Stamina is currently filled from one `max_stamina`.
  A heavier or stronger man plausibly carries a different stamina pool, but the sign of
  the effect is genuinely unclear (more muscle costs more to move), so this stays out of
  the phased plan until someone decides what it should model.

- **Appearance.**
  The issue explicitly asks for varied appearance.
  Per-soldier height is already the natural driver for figure-mesh scale in the render
  path, and unlike everything above it is mechanically free.

### What it must not change

- **Replay determinism.**
  Every existing recorded replay and every scripted-input demo must still reproduce.
  The fingerprint mismatch path exists precisely so a genuine break is loud rather than
  silent;
  a phase that trips it has to re-record, not suppress it.

- **The existing balance point.**
  The mean of every distribution is chosen to reproduce today's uniform value *for that
  unit type*, which is why the mass mean is keyed on `SoldierCombat.profile_for` from
  phase 1 rather than on one global figure.
  With `variation_enabled = false` every soldier therefore holds exactly today's value
  for his own unit class, ranged and cavalry included, so no gameplay quantity changes.
  That is testable and should be a test.
  It is *not* bit-identical to a pre-phase-1 recording, because the unconditional draw
  advances the shared stream;
  see the re-record acceptance criterion above.
  Bit-identity is a claim about the values the arrays hold, not about the RNG stream.

- **The new-file line cap.**
  `tools/check.sh`'s `file_length` check caps files *added* under `scripts/` by a diff at
  `SPARTA_CHECK_MAX_NEW_FILE_LINES` lines, defaulting to 100.
  The proposed `scripts/BodyStats.gd` is a new file under `scripts/`, so it is subject to
  that cap from its first commit: the constants, `draw()`, and the doc comments have to
  fit inside it.
  A later per-culture parameter table is what most plausibly pushes past the cap, so plan
  for it to live in a data file or a sibling leaf script rather than growing `BodyStats.gd`
  past the budget.

- **Patch coverage.**
  Per the repo's pre-push rule, a diff touching `scripts/` runs `patch_coverage`
  alongside the other checks in one `tools/check.sh` invocation.
  A wide new data table with no exercised branches is the classic way to miss the
  `codecov/patch` gate, so each phase carries its own unit tests rather than deferring
  them.

- **Hot-loop cost.**
  No `WU_PER_M` multiplication and no distribution evaluation in a per-tick path;
  the draw happens once at spawn and at tail resize, and the stored factors are read
  directly.

## Phased plan

Each phase is independently shippable and independently revertible.
No phase depends on a later phase's data table.

### Phase 1 -- the arrays and the draw, mechanically inert

Add the four arrays, the `BodyStats` helper, the seed-time draw from `Replay.rng`, and
the fingerprint coverage.
Nothing reads the arrays yet.

- **Parameters:** stature mean and standard deviation, build-factor mean and standard
  deviation, the per-unit-type mass means (defaulting to today's
  `SoldierCombat.profile_for` figures), strength and speed coefficients of variation,
  truncation width, and a master `variation_enabled` flag defaulting to **false**.

- **Defaults:** as listed under "The draw" above, with `variation_enabled = false`, so
  every stored value equals today's unit-type value until a later phase turns the flag on.
  The phase is inert in *gameplay* terms and is deliberately not inert in *stream* terms:
  the draw happens regardless, which is why the re-record lands here.

- **Tests:** the same seed produces the same roster across two runs;
  a different seed produces a different one;
  every drawn value falls inside the truncation bounds;
  the arrays stay index-aligned with `_sim_soldier_pos` across a `SoldierMelee.reap()`
  casualty compaction, a tail resize, a `TierTransition` demote-promote round trip, and a
  `Unit.to_dict()`/`from_dict()` round trip;
  with `variation_enabled = false` every soldier gets exactly today's values for his own
  unit class, ranged and cavalry included;
  the number of values the spawn path draws per soldier does not depend on
  `variation_enabled`.

- **Re-record:** every replay under `demos/` and every scenario under `demos/inputs/` is
  re-recorded in this PR, and the resulting demo clips are re-verified against the
  standard defect checklist.

- **Demo:** skip, with an honest reason -- nothing is visible.

### Phase 2 -- appearance only

Drive figure-mesh scale from `_sim_soldier_height` in the render path.
Turn `variation_enabled` on.
Still nothing mechanical reads the arrays.

- **Parameters:** a render-only scale clamp, so an extreme draw cannot produce a
  visually absurd figure even though the underlying stat is legitimate.

- **Defaults:** clamp at plus or minus two standard deviations of drawn height.

- **Tests:** two soldiers with different heights get different mesh scales;
  the scale clamp binds at the tails;
  the sim state dump is unchanged from phase 1 for the same
  seed, which is what proves the phase is cosmetic.

- **Demo:** a real clip -- a formed line at rest, close enough that the varied figures
  read.
  Check it against the standard demo defect checklist as usual.

### Phase 3 -- mass into contact

Route the per-soldier mass into the knockback and prone chain.

- **Parameters:** a mass-variation scale factor, so the spread can be tuned or zeroed
  independently of the height spread that drives appearance.

- **Defaults:** scale 1.0, that is, the full drawn spread.

- **Tests:** a heavier soldier receives a smaller translational impulse from an
  identical blow, and a lighter one a larger;
  `prone_chance` moves monotonically with mass;
  the population mean impulse over a large roster matches today's uniform-mass result
  within tolerance, checked per unit class rather than pooled, which is the
  balance-preservation check.

- **Demo:** a cavalry charge into a formed foot line, where the varied knockback is the
  visible result.

### Phase 4 -- strength into melee

Multiply weapon lethality by the striker's strength factor in the wound path.

- **Parameters:** a strength-to-lethality exponent, so the coupling can be softened
  without changing the draw.

- **Defaults:** exponent 1.0, that is, linear in the strength factor.

- **Tests:** identical soldiers with different strength factors produce different
  expected wounds from the same weapon;
  the population mean over a large roster matches
  today's result;
  `land_chance` is unchanged, confirming strength did not leak into
  skill.

- **Demo:** a sustained infantry melee, with the state dump showing the casualty spread
  rather than the clip alone.

### Phase 5 -- speed, gated on the cap

Scale each body's pace by its speed factor, and move `SUPERPHYSICAL_SPEED_FRAC` onto the
per-soldier factor in both `SoldierBodies` and `tools/demo/DemoDefects.gd` in the same
change, so the engine and the audit metric stay in agreement.

- **Parameters:** the speed coefficient of variation, and whether the gait cap scales
  with the factor or stays absolute.

- **Defaults:** coefficient of variation 0.05, cap scaling with the factor.

- **Tests:** the `superphysical_speed` demo-defect check does not fire on a roster at
  the top of the speed distribution;
  a fast soldier arrives at a distant waypoint before
  a slow one;
  formation cohesion is not visibly degraded at the default spread.

- **Demo:** a long march across the field, where the line's dressing under varied
  individual speeds is the thing under review.

### Phase 6 -- per-culture tables, and creatures

Replace the single global distribution shape with a per-culture parameter table for men,
on top of the per-unit-type mass means already established in phase 1, and add
per-species and per-breed mass distributions for mounts.
This is where the historical research actually pays out, and it is deliberately last
because everything above works with one distribution.

- **Parameters:** the culture table itself, and a per-`Mount` distribution alongside the
  existing scalar `mass_kg`.

- **Defaults:** every culture initially set to the phase 1 global distribution, so the
  table lands inert and each culture is tuned in its own change with its own citation.

- **Tests:** a unit tagged with a culture draws from that culture's parameters;
  an untagged unit falls back to the global default;
  the mount distribution reproduces the existing scalar `mass_kg` at its mean.

- **Demo:** two visibly different cultures' units side by side.

## Open questions

1. **Does strength enter `land_chance`, or only `wound`?**
   Skill and strength are different attributes and the current model has only skill.
   Folding strength into the hit contest is defensible (a stronger man beats aside a
   weaker man's guard) but it is a modelling decision, not an implementation detail.

2. **Should the draw come from `Replay.rng` or from a uid-keyed hash?**
   The stream keeps determinism in one place;
   the hash is immune to stream-order shifts and, being a pure function of
   already-deterministic inputs, breaks nothing in the replay contract either.
   The plan takes the stream and names the alternative, but the fragility is real and a
   first implementer may find it decisive.

3. **What is the soldier-versus-civilian selection offset?**
   Skeletal means come from cemetery populations.
   Whether and by how much to shift them for an army is an assumption that should be a
   named parameter, and nobody has decided its default.

4. **Does the gait ladder get rescaled?**
   `walk_speed` at 2.25 m/s already exceeds the Vegetian full step.
   Reconciling the sim's gait ladder with the historical march rates is worth doing and
   is not this feature's job;
   it wants its own issue.

5. **Does stamina vary with physique, and in which direction?**
   Left out of the phased plan deliberately, because the sign is genuinely unclear.

6. **How much does per-soldier variation cost at the target soldier counts?**
   Sixteen bytes per soldier is the straightforward answer and the quantised fallback is
   four, but neither has been measured against the large-scale simulation targets in
   `docs/large-scale-simulation-design.md`.

7. **Do drawn stats survive a save, or are they redrawn from the seed?**
   Redrawing is smaller and matches how the rest of the spawn layout works, but it makes
   every drawn stat a function of the distribution parameters, so changing a parameter
   changes an old battle's men.
   The fingerprint mismatch would catch it;
   whether catching it is enough is a decision.
   The tree narrows this more than it first appears: `TierTransition.demote()` already
   discards every per-soldier array, so "survive" is not available across a far-tier round
   trip whatever the save path does, and `promote()` has to reconstruct the stats from its
   own local seed.
   So the live question is whether that reconstruction reproduces the same men, which is
   what the uid-hash alternative above would buy.
