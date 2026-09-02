# Design note: A longer-range missile model

Status: **design drafted** -- nothing here is implemented.
This document is the scoping deliverable [#1470](https://github.com/Lacaedemon/sparta/issues/1470) asks for: the deployment-distance design ([`docs/deployment-distance-design.md`](deployment-distance-design.md), [#957](https://github.com/Lacaedemon/sparta/issues/957)) states plainly that "a longer-range missile model is outside this design" and defers it here.
Builds on [`docs/far-tier-pursuit-contagion-design.md`](far-tier-pursuit-contagion-design.md) ([#621](https://github.com/Lacaedemon/sparta/issues/621)), [`docs/large-scale-simulation-design.md`](large-scale-simulation-design.md) (the two-tier model), [`docs/combat-model.md`](combat-model.md), and [`docs/units-convention.md`](units-convention.md).

File, function, and constant names below were read from this branch's tree and re-verified with `git grep`;
anything not yet in the tree is marked **proposed**.
Re-check every name against the tree before wiring.

## Historical background

### Ranges

The longer-ranged ancient missile weapons -- the sling, both bows, and torsion artillery -- reached far enough that a battlefield 80 m across, which is what the game gives them today, is a rounding error against them.
The hand-thrown shafts are the exception and the reason the field size has never bitten: a javelin at 20-30 m and a pilum at 15-20 m both fit comfortably inside it.

- **Sling**:
  Xenophon has Rhodian slingers using lead shot outrange both the Persian slingers, who threw large stones, and the Persian archers, so that the Greeks could keep the Persian light troops off the column (*Anabasis* 3.3.16-18).
  Vegetius has recruits practise at a mark set 600 Roman feet away, about 178 m at 0.296 m to the foot (*Epitoma rei militaris* 2.23).
  Korfmann's experimental work puts effective sling ranges for lead shot in the same band, around 180-200 m (Korfmann 1973).

- **Self bow**:
  A plain wooden bow of the kind Cretan archers carried is the shortest-ranged of the archery types, effective at perhaps 100-150 m against a formed target rather than an individual.
  Vegetius's 600-foot practice mark is set for archers and slingers together (*Epitoma rei militaris* 2.23), which puts the training standard at roughly the top of that band.

- **Composite bow**:
  The Persian, Scythian, and later Roman *sagittarii* composite bow reached further than the self bow for the same draw length, on the order of 150-200 m effective and further still for harassing fire at extreme elevation.
  Xenophon's account of the retreat turns on exactly this range advantage: the Persian bows and slings outreached the Greek hoplites entirely until Xenophon raised his own Rhodian slingers and a small body of horse (*Anabasis* 3.3.16-20).

- **Javelin and pilum**:
  A hand-thrown shaft is an order of magnitude shorter-ranged than a bow or sling.
  A Roman line closed behind a pilum volley thrown from within some twenty metres (Goldsworthy 1996), the figure the sibling deployment design already cites;
  a skirmisher's lighter javelin thrown on the run reaches perhaps 20-30 m.

- **Artillery**:
  Torsion engines are the only class that outranges the whole of even a deep historical deployment.
  Marsden's reconstruction work puts bolt-shooters in the 300-400 m band and stone-throwers comparable (Marsden 1969).
  Josephus describes the Roman stone-throwers at Iotapata carrying their shot two stades, about 370 m (*Bellum Judaicum* 3.7).

### Rates

Rate of shooting is the weaker half of the evidence and is treated as such throughout this design;
the ancient sources describe volleys and their effect, not shots per minute, so the figures below are modern reconstructions and are carried as tunables with wide bounds rather than as pinned historical constants.

An archer shooting deliberately at a formed target is usually reconstructed at roughly 6-12 shots per minute sustained, a slinger somewhat slower because the sling must be loaded and wound, a javelineer limited by how many shafts he carries rather than by cadence (two pila per legionary), and a torsion engine at a few shots per minute for a bolt-shooter and under one for a stone-thrower.
See the open questions: these are the numbers most in need of a specialist source before they are tuned.

Sources: Xenophon, *Anabasis* 3.3.7-18;
Vegetius, *Epitoma rei militaris* 2.23;
Josephus, *Bellum Judaicum* 3.7;
Manfred Korfmann, "The Sling as a Weapon", *Scientific American* 229 (1973);
E. W. Marsden, *Greek and Roman Artillery: Historical Development* (Oxford, 1969);
Adrian Goldsworthy, *The Roman Army at War 100 BC - AD 200* (Oxford, 1996).

### The figures in world units

World scale is 20 world units per metre (`WorldScale.WU_PER_M`, verified in `scripts/WorldScale.gd`), so a metric figure converts by multiplying by 20.
Per [`docs/units-convention.md`](units-convention.md) any constant derived from these would be authored as `<metres> * WorldScaleRef.WU_PER_M` rather than as a bare world-unit literal.

| Weapon | Effective range (m) | Range (wu) | Reconstructed rate |
| --- | --- | --- | --- |
| Javelin, thrown on the run | 20-30 | 400-600 | 1-2 shafts carried |
| Pilum | 15-20 | 300-400 | 2 shafts carried |
| Self bow | 100-150 | 2000-3000 | 6-12 per minute |
| Sling | 180-200 | 3600-4000 | 4-8 per minute |
| Composite bow | 150-200 | 3000-4000 | 6-12 per minute |
| Bolt-shooter | 300-400 | 6000-8000 | 2-4 per minute |
| Stone-thrower | around 370 | around 7400 | under 1 per minute |

The scale problem is visible directly in that column.
`Battle.FIELD` is 1600 x 1200 wu, 80 x 60 m (`scripts/Battle.gd`), so a sling at 3600 wu outranges the default battlefield along its long axis twice over, and a bolt-shooter outranges it between three and five times over.
Even the deployment design's *Historical* preset, a 4000-wu (200 m) line gap in a 4620-wu (231 m) field, is a battlefield on which artillery reaches the enemy line from the moment of deployment and shoots well past it, while a sling or composite bow reaches that line only at the very top of its band.
A longer-range missile model is therefore not a retune of one constant;
it changes what the opening of a battle is.

## Where the game stands today

### The one range constant, and what is welded to it

`Unit.RANGED_RANGE` is `8.0 * WorldScaleRef.WU_PER_M`, 160 wu or 8 m (`scripts/Unit.gd`).
It is a single global `const`, not a per-type or per-unit value:
nothing in `scripts/LoadoutRegistry.gd` carries a missile range, the registry's `reach_m` is explicitly a melee reach ("the archers' melee sidearm is short -- their bow is ranged fire, not a melee reach"), and the archer roster entry in `Battle._default_loadout` carries `LoadoutRegistry.WEAPON_SIDEARM` with `"ranged": true` beside it.
So the bow is not a weapon type in the loadout registry at all;
it is a boolean on the unit (`Unit.is_ranged`) plus one shared range constant.

Four other values are defined in terms of that constant or pinned against it, and each one moves if it moves.

- **`Unit.RALLY_CONTACT_RADIUS`** is declared as `RANGED_RANGE` outright (`scripts/Unit.gd`), with a comment saying the identity is deliberate: "a router in archer reach has not broken contact".
  At a 3600-wu missile range that identity would say a routing unit has not broken contact anywhere on the field.

- **`Battle.ROUT_MARGIN`** is `maxf(UnitRef.RANGED_RANGE, UnitRef.DETECTION_RANGE)` (`scripts/Battle.gd`), the margin outside the field a router runs to.

- **`Unit.DETECTION_RANGE`** is `9.5 * WorldScaleRef.WU_PER_M`, 190 wu, and `RANGED_RANGE`'s own comment records the invariant that it "stays below DETECTION_RANGE so an auto-acquired target is always in detection too".
  A missile range past 190 wu breaks that invariant by construction.

- **`Unit.SKIRMISH_KITE_DISTANCE`** is 100.0 wu, documented as "tuned in wu, between melee contact and RANGED_RANGE" (`scripts/Unit.gd`).
  It is a fixed distance, not a fraction of the shooter's reach, so it does not follow a longer range.

### The firing path

`Unit._think` sets `_under_fire` by scanning every node in the `units` group for an alive, non-routing enemy unit with `is_ranged` inside `RANGED_RANGE`, once per unit per tick (`scripts/Unit.gd`);
the flag drives the AUTO pace ladder's jog escalation, a morale erosion term, and the gate that blocks resting recovery while it is set (`scripts/UnitMorale.gd`).

The fire branch itself requires `is_ranged`, no melee contact, and `dist_sq <= RANGED_RANGE * RANGED_RANGE`, plus a target-or-not-disengaging disjunction.
It sets `State.FIGHTING`, turns the unit to face with `_face_for_action` before loosing, then starts a `RANGED_INTERVAL` cooldown and calls `UnitCombat.shoot`.
`Unit.RANGED_INTERVAL` is 1.0 s and `Unit.RANGED_DAMAGE_FACTOR` is 0.7;
both are global constants with no per-type variation.

`UnitCombat.shoot` (`scripts/UnitCombat.gd`) draws one seeded roll from `Replay.rng.randf_range(0.6, 1.4)` first so the stream stays deterministic, then picks up a `friendly_interceptor` if one blocks the line, computes `eff_attack` from the attack stat times fatigue, cohesion, formation factor, and order-mode modifier, subtracts the target's stance-scaled defense, floors the result at 1, and multiplies by `RANGED_DAMAGE_FACTOR`, the roll, and `target.missile_defense_factor(u)`.
There is no range term anywhere in that formula:
a volley at 1 wu and a volley at 159 wu are identically lethal.
There is no ammunition either;
`git grep` for `ammo`, `ammunition`, `quiver`, and `arrows_left` across `scripts/` returns nothing.

`friendly_interceptor` walks the whole `units` group and blocks the shot on the nearest friendly whose centre is within its own `separation_radius` of the straight flight line, with the projection constrained to (0.05, 0.95).
It is a purely two-dimensional segment test:
nothing consults the projectile's height, so a lobbed volley is blocked by a friendly it would physically pass over.

### The projectile layer

`ProjectilePhysics` (`scripts/ProjectilePhysics.gd`) is pure ballistics: `solve_launch` inverts the level-ground range equation `R = v^2 sin(2*theta)/g`, `height_at` is the gravity parabola, `peak_height` its maximum, and `ground_at` interpolates the horizontal position linearly from launch to aim point.
Two launch angles exist as constants, `ANGLE_FLAT` at 20 degrees and `ANGLE_ARCED` at 55 degrees, and the script's own comment says the engine will choose between them per shot once line-of-sight and cover gating land.
Today it does not choose: `UnitCombat._volley_is_arced` returns `true` unconditionally and exists as a seam rather than an inline literal.

`ProjectileField` (`scripts/ProjectileField.gd`) holds in-flight volleys as plain-data parallel arrays with no nodes, ticked once per physics frame by `Battle`.
Its gravity is `GRAVITY = 90.0` wu/s^2, deliberately below real gravity's 196 wu/s^2 so that "volleys arc slowly and high enough to read at battlefield ranges";
the class doc calls it a balance knob.
A volley's casualty count is rolled once at launch and carried by the projectile, so the field draws no RNG at all and resolves landed projectiles in launch order, which is what keeps replays deterministic.
The class doc lists what is not built: "Per-arrow landing hit-detection, shield-arc blocking, cover/LOS, and non-soldier targets are later slices".

That geometry does not extrapolate to long range, and the arithmetic says so before any code is written.
For the arced angle, peak height is `R * tan(theta) / 4`, which is independent of gravity, so at 55 degrees a shot peaks at 0.357 of its range.
Evaluating `solve_launch` at `GRAVITY = 90` gives the following.

| Range | Launch speed | Flight time | Peak height |
| --- | --- | --- | --- |
| 160 wu (8 m), today | 124 wu/s (6.2 m/s) | 2.25 s | 57 wu (3 m) |
| 3600 wu (180 m), a sling | 587 wu/s (29 m/s) | 10.7 s | 1285 wu (64 m) |
| 7000 wu (350 m), a bolt-shooter | 819 wu/s (41 m/s) | 14.9 s | 2499 wu (125 m) |

A sling shot that peaks 64 m up and hangs for eleven seconds is not a sling shot, and it peaks higher than the default field is deep.
Two causes compound.
`ANGLE_ARCED` at 55 degrees is above the 45-degree maximum-range angle, so at long range it spends energy on height that a real shooter spends on distance.
And `GRAVITY = 90` was chosen to make an 8 m arc readable;
the same choice leaves a 180 m shot needing roughly two-thirds the launch speed a real projectile does and hanging about half again as long.
Both factors are the same square root read in opposite directions: at a fixed range launch speed scales as the square root of gravity, so `sqrt(90 / 196.2)` is 0.68, and flight time as its reciprocal, so `sqrt(196.2 / 90)` is 1.48.

### The far tier

`FarTierRules` (`scripts/FarTierRules.gd`) already carries a ranged branch, and it is a faithful mirror of the close tier's numbers rather than an independent model.
`strike_expectation` branches on `attacker.is_ranged` to skip the melee-stance offence penalty, apply `Unit.RANGED_DAMAGE_FACTOR`, and blunt through `missile_defense_factor`;
`casualty_rate` uses `Unit.RANGED_INTERVAL` for the cadence and deliberately does not apply the Lanchester thinning term to a ranged attacker, because `UnitCombat.shoot` draws from the flat attack stat with no soldier-count scaling;
`in_striking_range` uses `Unit.RANGED_RANGE` for a ranged attacker instead of the melee reach.
`FarTierFormation.is_ranged` mirrors `Unit.is_ranged` and is copied across on demotion.

Two facts about that tier bound everything below.
There is no `FarTierRates` script in the tree (`scripts/` holds only `FarTierFormation.gd` and `FarTierRules.gd` under that prefix), so the rate constants a far-tier missile model would need do not exist yet under that or any other name.
And, as [`docs/far-tier-pursuit-contagion-design.md`](far-tier-pursuit-contagion-design.md) establishes and this branch re-confirms, `FarTierRules.tick_pair` has exactly one caller in the whole tree and it is a unit test:
no live battle resolves far-tier combat at all, which that document tracks as its Phase 0 ([#1485](https://github.com/Lacaedemon/sparta/issues/1485)).

`FormationTier.PROMOTE_RANGE` is 400.0 wu and `DEMOTE_RANGE` is 600.0 wu (`scripts/FormationTier.gd`), both benchmark-tuned rather than authored.

## What changes when missiles reach 100-200 m

### The far tier stops being an out-of-contact optimisation

Today a formation only ever enters the far tier already out of contact, and once there it cannot take a casualty until it promotes.
That holds because the longest reach in the game, 160 wu, is well inside `PROMOTE_RANGE` at 400 wu:
anything close enough to shoot at you is close enough to have promoted you first.

A 3600-wu sling range inverts that by a factor of nine.
A formation would be shot at from far outside `DEMOTE_RANGE`, which means one of exactly three things, and the choice is the central architectural decision of this design.

1. **Resolve long-range fire at the far tier.**
   `FarTierRules` already has the ranged branch, so this is the option the existing code points at.
   It is gated on the far-tier combat wiring being live at all, which is [#1485](https://github.com/Lacaedemon/sparta/issues/1485), not this design.

2. **Drive promotion from missile range instead of a fixed radius.**
   Rejected.
   The deployment-distance design records that `PROMOTE_RANGE` is pinned from below by `Unit.DETECTION_RANGE + Unit.SPRINT_START_DISTANCE` and from above by the measured close-tier budget, and that moving it means re-running the benchmark sweep.
   Promoting every formation inside 3600 wu would promote most of a historical-preset battlefield at once, which is precisely the cost the two-tier model exists to avoid.

3. **Let long-range fire be a far-tier-only effect that stops mattering once a formation promotes.**
   Rejected as a model, kept as a fallback presentation: it makes the same weapon behave differently on either side of an invisible radius.

This design adopts option 1 and states the dependency plainly:
**a longer-range missile model past `PROMOTE_RANGE` cannot be implemented before far-tier combat is live.**
Phase 2 below is therefore bounded to ranges that stay inside the close tier.

### Deployment distances become the thing the ranges are measured against

The deployment design's three presets are a 580-wu (29 m) *Close* gap, a 1200-wu (60 m) *Far-tier opening*, and a 4000-wu (200 m) *Historical* gap.
Read against the range table above, those presets acquire a meaning they do not have today.

One convention has to be fixed first, because the two families of figure are not measured the same way.
The game gates firing on the distance between unit *centres*: `scripts/Unit.gd` compares `position.distance_squared_to(enemy.position)` against `RANGED_RANGE * RANGED_RANGE`.
The deployment design's gaps are between line anchors, and it records that its 580-wu *Close* gap is "about 20 m front to front at today's block depths" ([`docs/deployment-distance-design.md`](deployment-distance-design.md)), roughly 400 wu.
Every preset reading below is centre to centre, matching the code, so the gaps are read at their full 580, 1200, and 4000 wu.
The historical range figures, by contrast, are front-to-front throwing and shooting distances, so an authored `range_m` consumed as a centre-to-centre bound has to be *lengthened* by half of each block's depth -- on the order of 180 wu at today's depths -- rather than taken from the table unchanged.
That correction is left to Phase 2, which is where a profile first gets authored;
it moves the effective reach in the direction of the longer numbers, so it does not disturb the comparisons in this section.

At the *Close* preset the bows, the sling, and both artillery pieces reach the enemy line outright at deployment, the javelin reaches only at the top of its band, and the pilum does not reach at all, so for most of the table the missile phase is instantaneous and there is nothing to manoeuvre for.
At the *Far-tier opening* preset a bow or sling reaches across the gap and a javelin does not, so the light troops must be pushed forward to be used at all.
At the *Historical* preset only artillery reaches outright, a sling or composite bow reaches only at the very top of its band, and nothing else reaches at all, so the approach march opens under artillery fire and comes under everything else only partway across it, which is what the skirmisher-screening passage in the sibling design is describing.

That is the argument for building the missile model after the presets rather than before:
without them there is no battlefield on which a 180 m weapon differs from a 20 m one.

### Morale under fire without reply

A suppression term already exists.
`UnitMorale` subtracts `UNDER_FIRE_MORALE_EROSION_PER_SEC * delta`, 1.5 morale per second, for as long as `u._under_fire` is set, and the same flag gates the resting-recovery branch immediately below it (`scripts/UnitMorale.gd`).
So the game does charge something for being shot at, over and above the casualties.

What it does not do is distinguish a unit that can shoot back from one that cannot, and the term has no floor.
Rout fires at `morale <= 0.0` (`scripts/UnitMorale.gd`), so roughly 67 s of continuous fire routs a full-morale unit that has taken no casualties at all.
At the 8 m range the game has today that is close to unreachable, because a unit inside 8 m is in contact within a second or two.
At 180 m it is the ordinary outcome of standing still, which is the hazard this design has to close before the ranges grow.

The historical picture is of a cost that shapes a formation rather than destroys it:
Xenophon's whole account of the retreat is of a heavy column that could not close with light troops and had to acquire missile arms of its own to make the harassment stop (*Anabasis* 3.3.7-18).
The column was harried and slowed across the whole retreat, not broken by the harassment.

The proposal is therefore two edits to the existing term rather than a new mechanism.
Gate it on an inability to reply, so a unit that is `is_ranged` and whose own missile range reaches the shooter stops paying it.
And give it a floor, a morale value below which incoming fire alone stops eroding, so suppression can shake a formation without breaking it unaided.
Suppression that can rout a unit unaided would let a single archer regiment beat a phalanx by standing still, which no source supports and which the existing rout-contagion machinery would then amplify across the line.

The floor is a fix to present-day behaviour, not only a guard on behaviour this design would add:
Phase 3's floor test fails against `main` today rather than describing something new.

### Ammunition

Nothing in the tree tracks ammunition, and at an 8 m range with a 1 s cadence that is a defensible omission:
a fight at that distance is decided long before a quiver empties.
At 180 m with a suppression term it is not, because "stand off and shoot until they break" becomes a dominant strategy with no cost attached.

Ammunition is what prices it, and it is also what makes the historical light-troop pattern legible:
skirmishers shot their bundle off, withdrew through the intervals, and were done for the phase.
A thrown-shaft limit is already historical rather than invented, since a legionary carried two pila (Goldsworthy 1996).

## Proposed mechanism

Everything below is **proposed** and none of it exists in the tree.
Per this repo's caller-configurable convention, every value named here enters through a data table or an instance field with today's behaviour as the default, and every metric length is authored as `<metres> * WorldScaleRef.WU_PER_M`.

### A missile profile in the loadout registry

`scripts/LoadoutRegistry.gd` already interns weapon, shield, armor, and mount records on disjoint id ranges, and the record types it constructs convert authored metric lengths once at construction time:
`Weapon.make` sets `reach_wu` from `reach_m` through `WorldScaleRef.m_to_wu` (`scripts/Weapon.gd`), which is the only call site of that helper anywhere in `scripts/`.
The registry file itself holds no `WorldScale` reference, so the proposed profile's conversion belongs in its record type's `make` rather than in the registry.
A missile profile is the same shape, on its own id range.

Proposed fields, with defaults chosen so that an unset profile reproduces today's numbers exactly:

- `range_m`, defaulting to 8.0 so `Unit.RANGED_RANGE` stays the fallback.

- `interval_s`, defaulting to `Unit.RANGED_INTERVAL` (1.0).

- `damage_factor`, defaulting to `Unit.RANGED_DAMAGE_FACTOR` (0.7).

- `min_range_m`, defaulting to 0.0;
  non-zero only for artillery, which cannot depress onto a nearby target.

- `ammo`, defaulting to a sentinel meaning unlimited so Phase 2 changes no existing behaviour.

- `accuracy_at_max`, defaulting to 1.0, the fraction of nominal damage a shot delivers at the profile's maximum range.

Proposed ids, one per row of the historical table: sling, self bow, composite bow, javelin, pilum, bolt-shooter, stone-thrower.

### Per-unit range, and the constants welded to it

`Unit` gains a `missile_range` instance field defaulting to `RANGED_RANGE`, exactly the pattern `Battle.field` and `Battle.spawn_line_ys` use against `Battle.FIELD` and `Battle.SPAWN_LINE_YS`.
Every read site listed in the current-state section above is then rewritten against the instance field rather than the constant, and the three that are *pinned* against it need separate decisions rather than a mechanical substitution.

- `RALLY_CONTACT_RADIUS` stops being an alias of the missile range and becomes its own constant at today's value of 160 wu, since what it is really measuring is melee contact, not archery.

- `Battle.ROUT_MARGIN` stops following the missile range and follows `DETECTION_RANGE` alone;
  a router does not need to run past artillery range to be gone.

- `SKIRMISH_KITE_DISTANCE` becomes a fraction of the kiting unit's own `missile_range`, proposed default 0.6, so a longer-ranged skirmisher kites proportionally further out.

Target acquisition needs a fourth decision.
`DETECTION_RANGE` at 190 wu can no longer bound the missile range, so a ranged unit needs either its own larger detection radius or an acquisition path that consults the missile range directly.
This design proposes the former, since a per-unit `detection_range` already exists as a settable instance field.

### Range in the damage formula

`UnitCombat.shoot` gains one term and keeps its RNG ordering unchanged, which matters because the seeded roll is drawn first specifically to keep the stream deterministic.
The proposed term is a linear accuracy falloff from 1.0 at point blank to `accuracy_at_max` at the profile's range, applied alongside `missile_defense_factor`, with a default of 1.0 that leaves every existing replay bit-identical.

### Trajectory selection

`_volley_is_arced` becomes a real choice rather than a constant `true`, and `ANGLE_ARCED` at 55 degrees stops being the only arced option.
The proposed rule is to pick the launch angle from the range: a flat shot inside a threshold fraction of the profile's maximum, and above that the *lower* of the two angles that solve the range equation, which is at or below 45 degrees and is what a real shooter uses.
The arithmetic in the current-state section is the acceptance criterion:
peak height must stay a readable fraction of the field depth, and flight time must stay short enough that a volley aimed at a formation's current position still lands among it.

`GRAVITY` at 90 wu/s^2 is a balance knob chosen for an 8 m arc.
Phase 4 measures whether one value reads at both 8 m and 180 m, and if it does not, gravity moves onto the missile profile rather than being retuned globally.

### Long-range interception

`friendly_interceptor`'s segment test is sound at 8 m and wrong at 180 m, where a lobbed volley passes hundreds of world units above the friendly line it is fired over.
The proposed fix is to evaluate `ProjectilePhysics.height_at` at the interceptor's projection along the line and let the shot through when it clears a shoulder-height threshold, which turns the existing seam into the cover and line-of-sight gating `ProjectileField`'s class doc already anticipates.

## Phased plan

Each phase is one reviewable PR with its own acceptance tests and its own demo, per this repo's demo contract.

### Phase 1 (design)

This document.
Demo: a skip manifest, since a design note films nothing.

### Phase 2 (per-type missile profiles, close-tier ranges only)

Add the missile profile to `scripts/LoadoutRegistry.gd`, the `Unit.missile_range` instance field, and the read-site rewrites, including the three de-weldings above *and* the fourth decision on target acquisition.
Ranges stay strictly inside `FormationTier.PROMOTE_RANGE` (400 wu, 20 m) in this phase, so nothing depends on far-tier combat;
promotion tests `< PROMOTE_RANGE` (`scripts/FormationTier.gd`), so 400 wu itself is already outside the bound.
Only the pilum row fits, authored at the bottom of its band (15 m, 300 wu).
That range is past the 190-wu `DETECTION_RANGE` default, and `scripts/Unit.gd`'s own comment records the invariant that the missile range stays below detection so an auto-acquired target is always in detection too.
So the acquisition decision is in scope for this phase and not deferrable: the profile must also raise the unit's `detection_range` to at least its missile range.
The per-unit `detection_range` field already exists and is settable before the node enters the tree (`scripts/Unit.gd`), so this is an assignment rather than new machinery.
The javelin's 400-600 wu band starts at that bound and so waits for the far-tier work, and the bow and sling rows are authored but not yet assigned to a roster unit.

Acceptance tests: a unit with no profile reproduces today's `RANGED_RANGE`, `RANGED_INTERVAL`, and `RANGED_DAMAGE_FACTOR` exactly;
an existing replay plays back bit-identically;
a pilum unit fires at its own range and not at the global one;
a pilum unit auto-acquires a target at that 300-wu range, past the 190-wu detection default, and a unit with no profile keeps the 190-wu default;
`RALLY_CONTACT_RADIUS` and `Battle.ROUT_MARGIN` no longer move when a unit's missile range changes.

Demo: a pilum-armed unit loosing at its own 300-wu range while an unprofiled unit beside it holds for the global 160-wu one, verified against the standard demo defect checklist.

### Phase 3 (suppression morale and ammunition)

Gate the existing `_under_fire` morale erosion on an inability to reply, add the floor it currently lacks, and add the ammunition counter with the profile's `ammo` field.

Proposed parameters and defaults: the suppression rate in morale per second, with today's `UNDER_FIRE_MORALE_EROSION_PER_SEC` (1.5) becoming the configurable default;
a suppression floor as a morale value below which incoming fire alone stops eroding, which the term has no equivalent of today;
`ammo` unlimited by default so unprofiled units are unchanged.

Acceptance tests: a unit under fire with no reply erodes morale and halts at the default floor instead of routing, which is a regression test against present-day `main` rather than a new capability;
a unit that can reply is not suppressed;
a unit with finite ammunition stops firing when empty and stops suppressing the enemy at the same moment.

Demo: a skirmisher shooting a heavy unit to the suppression floor and no further, with the state dump showing the morale curve flattening at the floor rather than crossing it.

### Phase 4 (trajectory selection and long-range ballistics)

Implement the angle choice, the accuracy falloff, and the height-aware interception, and measure gravity at both ends of the range band.

Acceptance tests: `solve_launch` at each profile's maximum range produces a peak height under a stated fraction of field depth and a flight time under a stated bound;
a volley fired over a friendly line at a lobbing angle is not intercepted, while the same shot fired flat is;
the accuracy falloff at its 1.0 default leaves the damage formula bit-identical.

Demo: a lobbed volley passing over a friendly line to land on the enemy behind it, with the state dump confirming the interception did not fire.

### Phase 5 (long ranges at the far tier, gated)

Blocked on live far-tier combat ([#1485](https://github.com/Lacaedemon/sparta/issues/1485)).
Once that is wired, assign the sling, bow, composite-bow, and artillery profiles their historical ranges and let `FarTierRules.in_striking_range` read the per-formation missile range instead of `Unit.RANGED_RANGE`.

Acceptance tests: a far-tier formation takes casualties from a shooter outside `DEMOTE_RANGE`;
the far-tier and close-tier casualty rates agree for the same profile at the same range, which is the mirror property `FarTierRules` already documents for the existing ranged branch;
a battle at the *Historical* deployment preset opens with artillery fire and nothing else.

Demo: a *Historical*-preset opening in which the approach march is conducted under fire, at the deployment design's own far-deployment scenario.

## Open questions

- **Rates of shooting are the weakest evidence here.**
  The range figures rest on ancient testimony and on Marsden's and Korfmann's reconstruction work;
  the shots-per-minute figures rest on modern reconstruction alone and are given as bands.
  A specialist source should be found before Phase 2 pins any `interval_s` default, and until one is, the profile intervals should be treated as balance knobs rather than as historical constants.

- **Does one gravity value read at both 8 m and 180 m?**
  Phase 4 measures it.
  If it does not, gravity moves onto the missile profile, which costs `ProjectileField` a per-projectile gravity array;
  its determinism argument is unaffected, since the value is fixed at launch and the field still draws no RNG.

- **What does a volley aim at over a ten-second flight?**
  `ProjectileField` aims at the target's position at launch and lands there regardless of where the target went, which is correct for an 8 m shot and a deliberate choice at 180 m.
  Leading the target adds a prediction the player cannot see;
  not leading it makes long-range fire against a moving formation nearly useless, which may be historically right.
  Phase 4 should state which it picks and why rather than inheriting the current behaviour silently.

- **Should artillery be a unit at all?**
  The table's bottom two rows are engines, not men, and every mechanism in this design is a property of a `Unit` with soldiers.
  A stone-thrower as a one-soldier unit with a 7400-wu range and a sub-one-per-minute cadence would work mechanically and would misreport its own strength everywhere the HUD shows a soldier count.
  This is a separate design if artillery is ever wanted.

- **Does the suppression term interact badly with rout contagion?**
  `Unit._rout` drops morale on every teammate within `ROUT_SHOCK_RADIUS`, tier-agnostically, per the far-tier design's reading of it.
  A suppressed line is already near its floor, so one break could cascade further than it does today.
  Phase 3's acceptance test covers the single-unit case;
  the multi-unit case needs its own scenario before the suppression rate is raised from its default.

- **Which deployment preset is the missile model balanced against?**
  The three presets give three different answers to "how long is the missile phase", and balancing for one leaves the others wrong.
  This design assumes the *Far-tier opening* preset as the balance target, because it is the one where a bow reaches and a javelin does not, and that assumption should be stated in the tuning PR rather than discovered from it.
