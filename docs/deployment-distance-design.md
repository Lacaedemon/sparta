# Design note: Historical deployment distances, far-tier openings, and paced advances

Status: **design drafted** -- establishes the historical and architectural grounding for deep battlefield deployments, the far-tier opening they produce, a paced advance across them, and the pre-battle deployment presets that expose them.
Builds on [#957](https://github.com/Lacaedemon/sparta/issues/957) and extends [#945](https://github.com/Lacaedemon/sparta/issues/945) (the 580-wu default line gap), [#550](https://github.com/Lacaedemon/sparta/issues/550) (the multi-resolution simulation), and [#876](https://github.com/Lacaedemon/sparta/issues/876) (the pre-battle screen).

## Historical background

Ancient Mediterranean armies did not deploy within a stone's throw of one another:

- **Deployment separation**:
  Armies drew up their lines well beyond missile range, typically a few hundred metres apart.
  Xenophon has the Greek and Persian lines at Cunaxa three or four stades (some 550-750 m) apart when the Greeks began their advance (*Anabasis* 1.8.17).
  That separation gave commanders time to read the enemy's disposition, dress their lines, and address the troops.

- **Measured and phased advance**:
  Phalanxes and legions did not sprint across hundreds of metres.
  They advanced at a steady pace so that gaps did not tear open in the line;
  at Mantinea the Spartans stepped off slowly to the music of many flute players for exactly that reason (Thucydides 5.70).
  The run came only at the end.
  At Cunaxa the Greek line raised the war cry and broke into a run as it closed (*Anabasis* 1.8.18),
  and modern reconstructions put that final run at roughly the last hundred metres or less,
  with a Roman line closing behind a pilum volley thrown from within some twenty metres (Hanson 1989; Goldsworthy 1996).

- **Skirmisher screening**:
  The opening minutes belonged to the light troops (*velites*, *psiloi*, *peltasts*), who contested the ground between the lines and withdrew through the intervals as the heavy infantry closed.
  Polybius has both Cannae and Zama open this way (3.115; 15.9-12),
  and Livy's account of the manipular legion has the light troops open the fight in front of the line and the heavy ranks behind them retire through the intervals (8.8).

Sources: Xenophon, *Anabasis* 1.8.17-18;
Thucydides, *History of the Peloponnesian War* 5.70;
Polybius, *Histories* 3.115 and 15.9-12;
Livy, *Ab Urbe Condita* 8.8;
V. D. Hanson, *The Western Way of War* (1989);
A. Goldsworthy, *The Roman Army at War 100 BC-AD 200* (1996).

## Where the game stands today

The design below is a set of deltas against the current build, so the baseline comes first.
World scale is 20 wu per metre (`WorldScale.WU_PER_M`).

- **Field and deployment**:
  `Battle.FIELD` is 1600 x 1200 wu (80 x 60 m), with the two default spawn lines at y = 300 and y = 880 (`Battle.SPAWN_LINE_YS`):
  a 580-wu (29 m) gap between line anchors, about 20 m front to front at today's block depths.
  The gap is deliberately capped just inside `FormationTier.DEMOTE_RANGE` so the default battle opens at close-tier fidelity.
  Both values are already caller-configurable instance fields (`Battle.field`, `Battle.spawn_line_ys`):
  the demo recorder sets them from an input script's `map` block, and `BattleMap.serialize` records a non-default map into the replay header so playback rebuilds the same battlefield.

- **Simulation tiers**:
  `FormationTier.PROMOTE_RANGE` is 400 wu (20 m) and `FormationTier.DEMOTE_RANGE` is 600 wu (30 m), measured centroid to nearest enemy centroid and evaluated every tick by `Battle._tick_tier_transitions`.
  Both thresholds are benchmark-tuned, not authored (`docs/large-scale-simulation-design.md`, "Validating tier thresholds"):
  the promote range is pinned from below by `Unit.DETECTION_RANGE + Unit.SPRINT_START_DISTANCE` (190 + 200 = 390 wu), so a formation regains individual fidelity before it can detect, shoot at, or charge anything, and from above by the measured close-tier budget.
  Every unit spawns close-tier (`Unit.tier` defaults to `FormationTier.CLOSE`);
  a unit deployed beyond `DEMOTE_RANGE` demotes on the first tier tick, which that doc's `echelon-battle` run already measures.
  `TierTransition.demote` drops the per-soldier arrays and keeps the unit's own scalar fields (position, facing, soldier count, morale, and the durable formation and order modes) as the aggregate;
  `TierTransition.promote` rebuilds the bodies from those scalars under a seed hashed from the unit uid, the promotion tick, and the battle seed, placing each body within `TierTransition.SCATTER_FRACTION` (a quarter) of the slot pitch of its slot and letting the ordinary arrival dynamics ease it home.
  A far-tier unit is not invisible:
  `Unit._refresh_flock_render` draws one mark per living soldier on the formation grid itself, so the footprint and the head count are continuous across a promotion.

- **Pace**:
  Each unit type carries three gaits (`Unit.walk_speed`, `Unit.jog_speed`, and `Unit.move_speed` for the sprint), set per type from the loadout's `walk_mps` / `jog_mps` / `sprint_mps`:
  spearmen 1.1 / 1.8 / 2.8 m/s, infantry 1.3 / 2.5 / 4.0, archers 1.5 / 3.0 / 4.5, cavalry 1.7 / 3.5 / 8.5.
  `Unit._move_to`'s AUTO ladder walks by default, jogs under fire, and sprints inside `Unit.SPRINT_START_DISTANCE` (200 wu, 10 m);
  `Unit.walk_advance` (on by default for spearmen, since a formed stance breaks at a jog) pins the walk.
  A live far-tier unit keeps its regiment-level `_move_to` and the same ladder, only without soldier bodies;
  the isolated far-tier record (`FarTierFormation`, whose rules no live battle ticks yet) carries a single pace, `march_speed`, copied from `walk_speed`.
  The enemy AI (`Battle._run_enemy_ai`, once per `AI_PERIOD` of 60 ticks) runs the general's plan, `General.PLAN_ADVANCE_LINE` by default, down through `Subcommander.decide_group` to `UnitLeader.decide`, whose fallback issues an ATTACK on the nearest enemy.
  No AI directive or ATTACK carries a gait, so the AI approaches on the AUTO ladder:
  a walk until the last 10 m, then the sprint.

- **Fatigue**:
  Movement is free today.
  `Unit.fatigue` builds only while a unit is in `State.FIGHTING` (`UnitMorale.tick_fatigue`) and recovers otherwise;
  per-soldier stamina drains on strikes thrown, blows met, and rising from prone (`SoldierCombat.KAPPA_A` / `KAPPA_D` / `KAPPA_P`), never on distance covered.
  The combat model's posture table (`docs/combat-model.md`, "posture") specifies a slow drain for jogging and a fast drain for sprinting, and its own implementation note says that table is not implemented as a state machine.

- **Time**:
  `Engine.time_scale` is already the game's speed mechanism, cycled by F5 through `HUD.SLOWMO_PRESETS` (1.0, 0.5, 0.25, 0.1) and recorded into the replay's time-scale track so playback reproduces the same per-tick delta.
  Every preset is a slowdown;
  there is no fast-forward.

- **Battle setup**:
  `PrebattleScreen` offers faction and roster choice for a custom battle, ferried across the scene swap by `CustomMatchup`'s static `pending_team_0` / `pending_team_1`, and `Battle._custom_matchup_scenario` deploys those rosters on the default spawn lines.
  No deployment-distance choice exists anywhere in the UI.

### The arithmetic of a deep deployment

Infantry walks at 22-26 wu/s.
A 1000-wu (50 m) gap closes in roughly 20 s when both lines advance and roughly 40 s when the player holds;
a 200 m gap takes about a minute and a half with both armies advancing and nearly three minutes when one holds.
Promotion fires when the centroids come within 400 wu, so at a 200 m gap the first minute or more of every battle is a far-tier march, and the promotion lands mid-march, on screen, every time.
Those two facts are the two design problems the tracking issue names:
the promotion has to read as deliberate, and the march has to be worth watching or skippable.

## Core architecture and mechanics

### 1. Far-tier battle openings

- **No new trigger is needed.**
  A deployment beyond `DEMOTE_RANGE` already opens far-tier:
  every unit spawns close, and the first `_tick_tier_transitions` pass demotes it.
  The only opening-specific mechanical change worth making is an optimisation:
  spawn a unit that would demote on tick one directly at `FormationTier.FAR`, so its per-soldier arrays are never seeded only to be dropped.
  It is optional, and it must leave the spawn fingerprint (`SpawnFingerprint.of_tree`) and the transcript's far-tier representation unchanged.

- **What the promotion looks like, and how to check it.**
  Because the far-tier render already draws the block's marks on its grid, the promotion changes neither the footprint nor the head count.
  What changes is that each mark becomes a body scattered within a quarter of the slot pitch of its slot (about 2 wu, 11 cm, at infantry's 0.45 m pitch) and then eases back onto it.
  That is a small shiver, not a pop-in.
  Whether it reads cleanly at the default battle zoom and at the demo recorder's usual close and wide zooms is an empirical question, so Phase 2 answers it the way every demo is verified:
  record a far-deployment scenario through a demo input script's `map` block, dump per-tick state around the promotion tick, and run the standard demo defect checklist (pulsing, facing surge, rank swapping) across it.

- **Where to stage it if it does not read cleanly.**
  `PROMOTE_RANGE` is not the knob.
  It is pinned from below by the detection-plus-charge floor and from above by the measured close-tier budget, so moving it means re-running the benchmark sweep and echelon pair and updating that doc's recorded numbers.
  The presentation knobs are `TierTransition.SCATTER_FRACTION` (a smaller scatter makes the promotion invisible, at the cost of a parade-exact reappearance) and, if the shiver itself is the problem, carrying the same seeded scatter into the far-tier marks so the marks and the bodies they become sit in the same places.
  Either is render-side or a single constant, and neither touches the tier thresholds.

### 2. A paced advance

The tracking issue poses three ways to make the opening march bearable:
a faster AI approach pace with fatigue costs, a time-acceleration control, or a chosen engagement range at setup.
They are not alternatives.
A setup preset decides how far apart the armies start, fast-forward decides how long the player spends watching the walk, and the approach pace decides what the march looks like at 1x, so this design adopts all three and orders them by what each one is gated on.

- **The advance already has the right shape at the wrong scale.**
  The AUTO ladder is the historical profile:
  a walk for the whole approach and a run only at the end.
  Historically that run covered the last hundred metres or less;
  in the game it covers the last 10 m (`SPRINT_START_DISTANCE`), about three seconds at infantry's sprint.
  Stretching the charge toward the historical distance is a retune of one constant, but a 40 m sprint at 4 m/s is ten seconds of the fastest gait, and movement is free today, so that retune waits for per-gait stamina.

- **A jog approach is gated on two things this design does not build.**
  First, movement costs nothing, so an AI that jogged its approach would simply arrive sooner with no penalty;
  the issue's premise that the fatigue system already prices a run does not hold on the current build, and the gate is the combat model's deferred per-gait stamina flow.
  Second, the isolated far-tier rules carry only the walk, and the walk is the right resolution for them, so a jog approach has to reach `FarTierRules` before those rules take over live movement, or the two paths diverge.
  Both belong to the combat model and the far-tier rules, not here.
  Until they land, the AI keeps walking;
  spearmen would keep walking regardless, since `walk_advance` is the price of a formed stance.

- **Fast-forward is a small extension of an existing mechanism.**
  `Engine.time_scale` and its replay track already exist;
  the change is presets above 1.0 (2x and 4x) on the same F5 cycle, plus one rule:
  an automatic return to 1x on the first promotion, routed through the same `Replay.record_time_scale_change` call the manual cycle uses so the replay's track stays complete.
  The promotion tick is a pure function of serialized positions, so the automatic return is deterministic.
  Two properties need stating.
  A time-scale change alters how much simulated time each 60 Hz tick integrates (the HUD's own notes on slow motion), so a battle fast-forwarded through its opening is reproducible from its replay but not tick-identical to the same battle at 1x, and the soldier-body dynamics see coarser steps at 4x than at 1x.
  The far-tier opening is the one phase where a different route is affordable:
  Godot documents `Engine.time_scale` as scaling the delta handed to `_physics_process`, and the physics step is `1 / physics_ticks_per_second`, so raising `Engine.physics_ticks_per_second` by the same factor as `time_scale` should hold every tick at 1/60 s of simulated time and simply run more of them per real second, and a far-tier tick is cheap precisely because it carries no per-soldier state.
  Phase 3 verifies that relation on this build and measures both routes on the far-deployment scenario before choosing;
  the tick-count route is preferred if it holds 60 fps through the opening, because it keeps the 1x trajectory.

- **Skirmisher screening is a battle-AI directive, not a new mechanic.**
  The SKIRMISH stance, the loose formation ranged units start in, and the ranged reach already exist;
  what is missing is a subcommander directive (`docs/battle-ai-design.md`) that sends ranged units forward under SKIRMISH during the approach and recalls them through the line before contact.
  At a ranged reach of `Unit.RANGED_RANGE` (160 wu, 8 m) the screen is a band a few metres ahead of the line, not a hundred-metre missile duel;
  a longer-range missile model is outside this design.

### 3. Pre-battle deployment presets

- **The preset is a line gap in world units, flowing through fields that already exist.**
  `PrebattleScreen` gains an option button beside the faction pickers, ferried by a third `CustomMatchup` static alongside the two rosters, and `Battle._ready` applies it to `spawn_line_ys` and `field` before the map is published to the replay header and before anything spawns.
  Because a non-default map is already serialized into the replay header, a preset battle replays correctly with no format change.

- **Three presets**:
  1. *Close* (the default, unchanged): the 580-wu (29 m) gap, close-tier from the first tick.
  2. *Far-tier opening*: a 1200-wu (60 m) gap, so both armies open far-tier and promote after each has closed about 400 wu, roughly 15-20 s of far-tier march when both advance.
  3. *Historical*: a 4000-wu (200 m) gap, the full approach.

- **The field grows with the gap.**
  The mechanism is the one the current default already used:
  keep the origin, team 0's line, and the terrain band where they are, move team 1's line to `300 + gap`, and extend the field downward to `gap + 620` so team 1 keeps today's 320 wu of ground behind its line (4620 wu, 231 m, for the historical preset).
  Camera bounds, the routing grid, and the rout margin all follow `field` already.

- **The default does not move.**
  Keeping the default at today's gap means the website demo catalog's default-spawn scenarios are not retimed and every existing replay still plays;
  the presets are opt-in.
  Campaign clashes keep the default too;
  a per-clash deployment distance is a campaign-design question this design defers.

## Open questions from the tracking issue

- **Does the mid-march promotion read cleanly, or should the promote radius or hysteresis be staged?**
  Answered by construction and by measurement:
  the far-tier render keeps footprint and head count continuous, so the transition is a sub-pitch shiver, and Phase 2 verifies it by state dump and clip at the usual zooms.
  The thresholds stay where the benchmark put them;
  `SCATTER_FRACTION` and the far-tier marks are the staging knobs if the shiver reads.

- **Which of a paced AI advance, a time-acceleration control, or a setup-time engagement range comes first?**
  All three, in this order:
  the setup preset (Phase 4), fast-forward with an automatic return at first promotion (Phase 3), and the AI approach pace last (Phase 5), because a jog approach is gated on per-gait stamina and a far-tier gait that belong to other designs.

- **The player convenience.**
  The fast-forward key and the preset cover it;
  no per-unit pacing automation is added for the player.

- **The field-growth mechanics.**
  Owned by the preset:
  grow the field downward from the spawn anchor by the preset's gap, with the default untouched so the demo catalog needs no retiming.

Deferred, each to its own issue when its phase opens:
the per-gait stamina flow and the far-tier gait that a jog approach needs;
the skirmisher-screen subcommander directive;
a charge-distance retune once sprinting costs stamina;
per-clash deployment distances for campaign battles;
and any longer-range missile model.

## Implementation roadmap

1. **Phase 1 (design)**:
   This document.

2. **Phase 2 (far-tier opening verified as a presented feature)**:
   Author a far-deployment demo input script using the `map` block, dump state around the promotion tick, run the standard defect checklist, and record the verdict in this document;
   adjust `SCATTER_FRACTION` or the far-tier marks only if the shiver reads.
   Optionally spawn directly at `FormationTier.FAR` for units that would demote on tick one.

3. **Phase 3 (fast-forward)**:
   Add presets above 1.0 to the F5 cycle with an automatic return to 1x at the first promotion, recorded through the existing time-scale track;
   verify the physics-delta relation above on this build, measure the `time_scale` route against the matched-tick-rate route on the far-deployment scenario, and keep whichever holds 60 fps through the opening, preferring the one that keeps the 1x trajectory.

4. **Phase 4 (deployment presets)**:
   Add the preset option to `scripts/PrebattleScreen.gd`, ferry it through `scripts/CustomMatchup.gd`, and apply it to `Battle.spawn_line_ys` and `Battle.field` with the downward field growth above;
   cover the three presets with a spawn-layout test.

5. **Phase 5 (AI approach pacing, deferred)**:
   Once the combat model's per-gait stamina and a far-tier gait exist, revisit a jog approach and the charge distance, and add the skirmisher-screen directive to the battle AI (`scripts/Subcommander.gd`, `scripts/UnitLeader.gd`).
