# Design: far-tier winner pursuit and rout contagion across many formations

Status: **design drafted** -- nothing here is implemented;
this document is the scoping deliverable [#621](https://github.com/Lacaedemon/sparta/issues/621) itself asks for ("scope this properly ... before implementing, rather than bolting it onto the pair model"), phased so each slice ships as its own reviewable PR.
Builds on [`docs/large-scale-simulation-design.md`](large-scale-simulation-design.md) (the two-tier model), [#557](https://github.com/Lacaedemon/sparta/issues/557) (phase 2, `FarTierRules`), and [#580](https://github.com/Lacaedemon/sparta/issues/580)/[#617](https://github.com/Lacaedemon/sparta/pull/617) (the pair-scoped rout/rally arc `tick_pair` implements).
Connects to [#550](https://github.com/Lacaedemon/sparta/issues/550) (the parent LOD epic) and [`docs/battle-ai-design.md`](battle-ai-design.md) (`pursue_routers`, phase 3).

File, function, and field names in this document were read from `main` at commit `08b87e18` (2026-09-01);
re-check them against the tree before wiring.

## The gap #621 names, restated precisely

`FarTierRules.tick_pair` is a pure, two-body driver: given exactly formation A and formation B, it resolves one tick of their mutual attrition, movement, and rout/rally/shatter.
#621 asks for the multi-formation analogs of two close-tier behaviours it cannot express:

- **Winner pursuit** -- a formation whose opponent just broke should press toward a *new* target (a neighbouring enemy formation) instead of idling once the old opponent starts fleeing.
- **Rout contagion** -- a formation that breaks should shake morale in *sibling* formations nearby, not just its one opponent.

Both need "a formation plus its neighbours," not a pair, which is the bigger architectural step the issue defers to a design doc.

## What is actually live today (the discovery this doc is built on)

Reading `Battle.gd`'s tick and the two systems this issue touches turns up a fact neither #621 nor `docs/large-scale-simulation-design.md` states plainly: **`FarTierRules.tick_pair` is never called from live gameplay.**
`FarTierFormation`'s own class doc says as much -- "no live battle constructs or ticks one yet" -- but that line is easy to read as "not yet wired for far-vs-far *specifically*" rather than "not wired at all."
It is the latter.
Grep confirms `tick_pair` has exactly one caller in the whole tree: `test/unit/test_far_tier_rules.gd`.

What *is* live, wired through `Battle._tick_tier_transitions` (`scripts/Battle.gd:2823`) and `TierTransition` (`scripts/TierTransition.gd`):

- **Promotion and demotion** run every tick, per formation, off the distance-hysteresis predicates in `FormationTier` (`PROMOTE_RANGE = 400`, `DEMOTE_RANGE = 600`).
- **Demotion only drops the per-soldier arrays.**
  `TierTransition.demote` empties `_sim_soldier_*` and sets `u.tier = FormationTier.FAR`;
  every other `Unit` field (`position`, `facing`, `morale`, `soldiers`, `formation_mode`, orders) is untouched and keeps being written by the ordinary, tier-agnostic `Unit._physics_process` path: `_think`/`_move_to` still march the formation on its orders, `UnitMorale.tick_morale`/`tick_fatigue`/`tick_cohesion` still run, and a routing far-tier unit still flees via the ordinary `_process_rout` (state == `ROUTING` is checked before anything tier-specific in `_physics_process`).
  Only the per-soldier body step and coupling are skipped (`Unit.step_all_sim_soldiers`/`couple_all_sim_soldiers`, both gated on `tier != FormationTier.FAR`).

- **Nothing resolves combat for a far-tier formation.**
  `TierTransition.can_demote` refuses to demote an engaged unit, so a formation only ever *enters* the far tier already out of contact -- and once there, `FarTierRules.tick_pair`/`tick_attrition` are never called live at all.
  A far-tier formation cannot take a casualty, cannot lose morale from combat, and therefore cannot rout, until `FormationTier.should_promote` fires and hands it back to the close tier's real combat.

  > **Correction, measured while implementing phase 0 (2026-09-02).**
  > This bullet originally gave the reason as "no code path ever calls `UnitCombat.strike`/`shoot` (they run off the per-soldier arrays this tier has none of)".
  > That mechanism is wrong on both halves.
  > `Unit._think`'s fighting branches call `UnitCombat.strike`/`shoot` with **no tier gate**, and `strike` falls through to the regiment-damage formula whenever either side has no soldier layer (its own doc comment names that fallback) -- so a far-tier formation reaching contact *would* have struck through the formula path.
  >
  > The real reason the case never arises is **distance**: `PROMOTE_RANGE` (400 wu) is far larger than any combat reach -- melee contact is `attack_range + RADIUS * 2` = 62 wu at the default gladius, and `RANGED_RANGE` is 160 wu -- and `Battle._tick_tier_transitions` runs *before* the units act each tick, so a far-tier formation is always promoted back to the close tier before anything can strike it or be struck.
  >
  > The one exception, which the original bullet also missed: `_tick_tier_transitions` scans only the `units` group, so a **routing** enemy is invisible to the promote trigger. A far-tier formation running down a broken enemy therefore stays far-tier while in contact with it, and was already dealing formula-path casualties to it before phase 0.
  >
  > This matters for the conclusion, not against it: the case is empty at the shipped tier band either way, so the gap phase 0 closes is real. It changes what phase 0 has to *do* -- see "Phase 0 as built" below.

So the honest current behaviour of "far tier" is: a performance optimization for formations that are marching, idle, or holding reserve, not a second combat model.
It moves, follows orders, recovers morale at the ordinary rate, and reconstitutes into full soldier fidelity the moment an enemy closes inside `PROMOTE_RANGE` -- at which point *close-tier* combat takes over.
`FarTierRules`'s statistical strike/attrition math (`strike_expectation`, `casualty_rate`, `tick_attrition`) and its parallel rout/rally/shatter state machine (`FarTierFormation.routing`/`rout_timer`, `enter_rout`/`tick_rout`/`rally`/`shatter`) exist, are unit-tested in isolation, and drive nothing in a live battle.

This matters for scoping #621: **building a many-formation orchestration layer on top of `tick_pair` would be building on a foundation the live game never runs.**
The winner-pursuit and rout-contagion behaviours the issue wants only mean anything once far-tier formations can fight at all.
Wiring that live-combat gap is the actual prerequisite, and it turns out to be more consequential than #621's own ask -- so it is Phase 0, tracked as [#1485](https://github.com/Lacaedemon/sparta/issues/1485) rather than folded into this one silently (per this repo's issue-first convention).

## What already generalizes to "many formations" for free

The close tier's own analogous behaviours are not pair-scoped, and neither system is gated on `tier` -- so once far-tier formations can take casualties at all, both halves of #621 are largely *already* multi-formation, for free, through machinery this design doc does not need to invent:

- **Rout contagion already shakes every nearby friendly, tier-agnostic, today.**
  `Unit._rout()` (`scripts/Unit.gd:6883`) iterates `get_tree().get_nodes_in_group("units")` -- every live formation on the field, not just the one it was fighting -- and drops morale by 12 on every teammate within `ROUT_SHOCK_RADIUS` (7 m).
  Nothing there reads `tier`.
  A far-tier formation that breaks already rings this shockwave against its far-tier and close-tier neighbours alike, the day it can break at all.

- **Winner pursuit already exists as an AI decision, tier-agnostic, today.**
  `UnitLeader.decide` (`scripts/UnitLeader.gd`), driven by the general's `pursue_routers` doctrine flag (`docs/battle-ai-design.md` phase 3), already retargets *any* unit -- via `UnitTargeting.nearest_enemy_to(..., pursue_routers)`, which has no tier check either -- onto a fresh enemy the instant its current target is gone or breaks.
  `UnitLeader.decide` runs over every AI-controlled unit regardless of tier (`Battle._run_enemy_ai` iterates `_team_units(1)`, not filtered by tier), so a far-tier formation already receives a fresh attack order onto a neighbour the moment its old target routs -- it just currently has nothing to *execute* that order's combat with once it arrives, per the gap above.

So the two behaviours #621 names are not, in the main, missing orchestration logic to invent from scratch.
They are downstream consequences of the one real gap: far-tier formations cannot exchange casualties.
Once that is fixed by routing far-tier attrition through the *same* systems (`Unit.morale`, `Unit._rout()`, `UnitLeader`'s targeting) close-tier combat already uses -- rather than through a second, parallel `FarTierFormation`/`tick_pair` state machine -- pursuit and contagion inherit the close tier's existing multi-formation behaviour automatically, with no separate "orchestrate across neighbours" layer to design.

## The design: drive far-tier attrition through `Unit`'s own fields, not a shadow record

Reject the reading of `docs/large-scale-simulation-design.md`'s phase 2 that a live far-tier fight constructs `FarTierFormation` records and calls `tick_pair` on them.
That would stand up a second morale/rout/targeting state machine next to the one `Unit` already has, and the two would need to be kept in sync by hand (exactly the trap `FarTierFormation`'s own class doc gestures at when it says `TierTransition` "keeps the unit's own scalar fields as the aggregate source of truth").
Instead:

1. **A far-tier formation still has a `target_enemy`, set by the existing AI/order path.**
   Reuse it unchanged;
   no new targeting concept.

2. **A new per-tick step, `FarTierCombat.tick(u: Unit, delta: float)`, called from `Battle.gd` for every live `tier == FormationTier.FAR` unit with a fightable `target_enemy` in range**, computes the expected casualties for this tick using `FarTierRules`'s existing formulas (`strike_expectation`, `casualty_rate`, `in_striking_range`, `flank_multiplier`, the stance factors) evaluated directly against the two `Unit`s' own fields (`attack`, `defense`, `attack_range`, `formation_mode`, `is_ranged`, `position`, `facing`) -- no `FarTierFormation` object constructed.
3. **Casualties apply through `UnitCombat.register_casualties`**, the same entry point close-tier combat already uses -- so morale erosion, the crumble boost, `_die()`, and `_rout()` (with its existing contagion shockwave) are the *one* implementation, exercised by both tiers, rather than two formulas that can drift.
   `register_casualties`'s own doc comment already anticipates a "formula-path hit on a unit with no soldier layer" for its cosmetic-marker fallback, which reads as this exact caller having been anticipated, never finished.

4. **The fractional-casualty carry** (`tick_attrition`'s `casualty_carry` accumulator) becomes a small `Unit` field, e.g. `_far_tier_casualty_carry: float`, mirrored the way `_rout_timer` already is -- not a second record.
5. **Movement while fighting** (`face_toward` when in range, `advance` otherwise) is redundant with what `_think`/`_move_to` already does once a formation has a live `target_enemy`;
   confirm rather than reimplement, and only add a far-tier-specific branch where a real gap turns up (e.g. a far-tier attack order today may resolve as "walk into contact and stop," which is correct -- promotion then takes over -- so `FarTierCombat.tick` should apply attrition to formations that *never* promote, i.e. that stay far-tier because they're outside `PROMOTE_RANGE` of every enemy despite being in `attack_range`/`RANGED_RANGE` of one specific target, which can happen for a long-reach ranged formation given `PROMOTE_RANGE` (400) versus `RANGED_RANGE`;
   check the actual constant relationship before assuming this case is empty).

6. **`FarTierRules`'s pair-scoped API (`tick_pair`, `tick_rout`, `enter_rout`, `rally`, `shatter`, and `FarTierFormation.routing`/`rout_timer`) becomes dead weight once step 3 lands**, since `Unit._rout()`/`_process_rout()` already do that job, generically, for every tier.
   Phase 4 of the plan decides its fate explicitly rather than leaving an unused parallel model in the tree.

This design keeps the tier boundary exactly where `docs/large-scale-simulation-design.md` already draws it (aggregate fields are a *view* of the same `Unit`, not a separate object) and turns "orchestrate pursuit and contagion across many far-tier formations" into "let far-tier formations use the multi-formation systems the close tier already has" -- which is a much smaller, much safer change than a new orchestration layer would have been.

## Phase 0 as built

Shipped for #1485. Deviations from the sketch above, and the open questions it settled:

- **`FarTierCombat.tick_all(units, delta)`, not `tick(u, delta)`.**
  The pass plans every formation's rate against the pre-tick state before booking any casualty, so an exchange stays simultaneous -- the guarantee `FarTierRules.tick_pair` gives a *pair*, generalized to the whole field. A per-unit entry point would have given whichever formation the tree visited first a thinning-term advantage.
- **The expectation math lives in `scripts/FarTierRates.gd`**, a Unit-shaped twin of `FarTierRules`'s record-shaped formulas, split out because `tools/check.sh file_length` caps a new `scripts/*.gd` file at 100 lines.
  This answers the third open question below: `FarTierRules` keeps its `FarTierFormation` parameter shape and stays the isolated reference model; `FarTierRates` is the live twin, and `test_far_tier_combat.gd` pins the two against each other across stances, angles, thinning, and the ranged/melee split so they cannot drift apart silently.
  Two deliberate divergences. The **cadence**: `FarTierRates` reads the attacker's own `Unit.melee_attack_interval()`, where the record carries no weapon and `FarTierRules` must use `Unit.ATTACK_INTERVAL`; the parity test compares per-strike expectation, which is interval-independent. And the **ranged fall-through**: `Unit._think` gates its ranged branch on `not in_contact`, so an archer regiment whose enemy has closed to melee contact falls through to `UnitCombat.strike`. `FarTierRates.resolves_as_ranged` mirrors that, which `FarTierRules` cannot -- so parity for a ranged attacker holds outside melee contact, and the melee branch takes over inside it.

  **A known balance divergence, distinct from those two.** Holding parity with `FarTierRules` means `FarTierRates` drops fatigue, cohesion, and the order-mode modifiers -- and unlike the record, which has no such fields, the live `Unit` genuinely carries all three. `UnitMorale.tick_fatigue` accrues fatigue for exactly as long as a unit is `FIGHTING` (which is now the far tier's own gate), `cohesion` sits below 1.0 after a merge and ramps back, and `UnitCombat.order_mode_modifiers` is non-identity under `ALL_OUT_ATTACK`, `KNOCKBACK_FOCUS`, and `WEDGE_CHARGE`. Fatigue and cohesion only ever scale output *down*, so a fatigued or freshly-merged far-tier attacker hits **harder** than the close-tier equivalent would; the order-mode modifiers cut both ways. Phase 2's balance measurement is where this gets priced, since carrying the three across is a small change to `strike_expectation` and a real change to the parity test's premise.
- **`UnitCombat.strike`/`shoot` return early for a far-tier attacker**, before the RNG draw.
  Required by the correction above: those paths were reachable for a far-tier formation, so without the guard a fight would be billed twice (once as a rolled strike, once as continuous attrition). Returning before the draw also keeps the far tier RNG-free, as `FarTierRules` documents it.
  Everything else in `Unit._think` still runs for a far-tier formation -- targeting, facing, the `FIGHTING` state, the press into contact -- so only casualty resolution moved. The early return still spends `_approach_velocity`, as both paths below it do, so a far-tier formation cannot bank an unspent charge and cash it on its first close-tier strike after promotion.
  `FarTierCombat.engaged_target` then *reads* that state rather than reimplementing its gates: it books nothing unless the unit is already `FIGHTING` and not `is_maneuver_turning()`, which inherits `_think`'s disengage rule (a plain move order past a broken enemy marches by instead of grinding it down) and its `_face_for_action` hold (no attrition while the men are mid-arc).
- **`Battle.promote_range` / `demote_range` are now instance fields** (defaulting to `FormationTier.PROMOTE_RANGE`/`DEMOTE_RANGE`), with the trigger distance a parameter on `FormationTier.should_promote`/`should_demote`.
  Without this the feature is untestable and undemonstrable: at the shipped band no formation can be both far-tier and in reach. `demos/inputs/far-tier-contact-1485.json` sets `"tier_ranges": {"promote": 6.0, "demote": 95.0}` through the recorder's new field of the same name. Promote had to go that low because two pressing regiments close well inside the 36 wu separation floor: measured at 17.8 wu, which promoted them mid-fight at a 20 wu trigger.
- **The second open question below is answered, and the answer is "empty at the default band".**
  Two far-tier formations in mutual reach cannot occur with `PROMOTE_RANGE` at 400 wu, since every reach is well inside it. So live far-tier combat at the shipped band is confined to running down a **routing** enemy (invisible to the promote trigger), and shipped play changes only in that this now resolves as a continuous expectation rather than as rolled per-cooldown strikes. Making the general case reachable is a **tuning** decision about the tier band, not more code; phase 2's measurement is the natural place to take it.

## Open questions this doc does not resolve

- **`ROUT_SHOCK_RADIUS` (7 m) was tuned for close-order soldier spacing, not for the distance between far-tier formation centroids.**
  A far-tier formation's `position` is a whole regiment's centroid;
  two far-tier formations that are tactically adjacent (e.g. a battle line's neighbouring regiments) may sit well outside 7 m of each other even though a close-tier observer would call them "next to each other."
  Whether contagion at far-tier scale needs its own, larger radius constant (and what governs it -- formation frontage?
  `DEMOTE_RANGE`-scaled?) is a balance question Phase 2 should measure against a real multi-formation scenario before picking a number, not guess up front.

- **Whether a far-tier formation should ever fight *another* far-tier formation, or only ever fight while promotion is imminent.**
  `PROMOTE_RANGE` (400) already sits close to combat range by design (the design doc's own "correctness floor" argument), so two far-tier formations may rarely stay far-tier while in mutual `attack_range`/`RANGED_RANGE`.
  If that case turns out to be empty in practice (worth checking against the benchmark scenarios before building for it), `FarTierCombat.tick` degenerates to "a far-tier formation vs. its one close-tier target," which is materially simpler than the general case and worth confirming before Phase 0 is scoped in detail.

- **Whether `FarTierRules`'s formulas should be read directly by `FarTierCombat.tick`, or whether `FarTierRules` itself should be refactored to take `Unit` parameters instead of `FarTierFormation` ones**, eliminating the now-parallel record type rather than leaving it as an alternate call surface.
  Leaning toward the latter (one set of formulas, one caller shape), but that is a Phase 0 implementation decision, not a design-doc one.

## Phased plan

1. **This document** -- a docs-only PR with a skip-form manifest (the mechanic under discussion is not implemented, so no recorded battle can show it).
2. **Phase 0 -- live far-tier combat resolution** (tracked as #1485, a prerequisite to #621's own two behaviours): `FarTierCombat.tick`, the `_far_tier_casualty_carry` field, wiring into `Battle.gd`'s tick, and a decision on `FarTierRules`'s parameter shape (see the third open question above).
   Verify in isolation first, the way phase 2 of the LOD design did: a far-tier formation fighting a close-tier one produces attrition and, eventually, a rout, with the existing contagion shockwave observably reaching a third nearby formation -- all through the transcript, no new tier-specific fields needed there since `morale`/`soldiers`/`state` already serialize per unit regardless of tier.
   **Done-check:** a scripted scenario with three formations (two far-tier siblings behind one close-tier front) shows the front's break dropping morale on both far-tier siblings, and shows a far-tier-vs-close-tier fight producing casualties, purely by exercising `Unit`'s existing systems.

3. **Phase 1 -- winner pursuit verification.**
   With Phase 0 live, confirm `UnitLeader`'s existing `pursue_routers` retargeting reaches a far-tier formation correctly once its target breaks or dies: does the new attack order actually resolve combat against the new target (Phase 0's job), and does a formation that presses forward past `DEMOTE_RANGE`'s inverse (i.e. toward `PROMOTE_RANGE` of yet another enemy) promote cleanly per the existing `_tick_tier_transitions` trigger?
   This phase is mostly verification and, if a gap turns up, a small targeted fix -- not new pursuit logic, per the "already generalizes" section above.
   **Done-check:** a scripted scenario where a far-tier formation's target routs shows the formation's order retargeting onto a neighbouring enemy within the same or next tick, and either fighting it (Phase 0) or promoting to close tier on approach, matching what a close-tier formation would do in the equivalent situation.

4. **Phase 2 -- rout-contagion radius at far-tier scale.**
   Measure whether `ROUT_SHOCK_RADIUS` needs a far-tier-appropriate variant (first open question above) against a real multi-formation scenario, and implement whatever the measurement supports.
   **Done-check:** the design doc (this file, amended) records the measurement and the resulting constant (or the decision that 7 m already suffices, with the scenario that showed it).

5. **Phase 3 -- determinism, tests, demo, website.**
   `test/unit/test_far_tier_combat.gd` (the new resolution step, deterministic given fixed inputs);
   an A/B lockstep-hash case exercising a far-tier fight;
   a scripted-input demo showing a far-tier reserve pursuing into a neighbour after its first opponent breaks, with the contagion shockwave visible;
   `website/tactics.qmd` updated if this is player-visible (a far-tier formation visibly fighting, rather than freezing, is).

6. **Phase 4 -- `FarTierRules` cleanup.**
   Once Phase 0 routes attrition and rout through `Unit`'s own systems, decide explicitly whether `FarTierFormation.routing`/`rout_timer` and `FarTierRules.tick_pair`/`tick_rout`/`enter_rout`/`rally`/`shatter` are dead code to remove (their job now done by `Unit._rout()`/`_process_rout()`), or whether they remain as a deliberately-isolated unit-testable reference model worth keeping for its own sake (e.g. as a fast analytical approximation for AI planning, distinct from the live per-tick resolution).
   Either answer should be recorded here, not left implicit.

## Code touch-points (Phase 0, for scoping the follow-up issue's size)

| File | Change |
| --- | --- |
| `scripts/FarTierCombat.gd` (new, static) | `tick(u, delta)`, reading `u.target_enemy`, applying `FarTierRules`'s strike/rate math against `Unit` fields, calling `UnitCombat.register_casualties` |
| `scripts/Unit.gd` | `_far_tier_casualty_carry: float` field |
| `scripts/Battle.gd` | a call to `FarTierCombat.tick` per live far-tier unit, placed in `_physics_process` alongside the existing tier-transition and combat steps |
| `scripts/FarTierRules.gd` | parameter-shape decision (third open question); existing `strike_expectation`/`casualty_rate`/`in_striking_range`/stance-factor functions are the reused math either way |
| `test/unit/test_far_tier_combat.gd` (new) | isolated coverage of the new resolution step |
| `test/unit/test_lockstep_ab_sim_hash.gd` | one A/B case exercising a far-tier fight, proving determinism |

## Sources

- [`docs/large-scale-simulation-design.md`](large-scale-simulation-design.md) -- the two-tier model, promotion/demotion, and the determinism invariants this design stays inside.
- [`docs/battle-ai-design.md`](battle-ai-design.md) -- `pursue_routers` and the chain-of-command targeting this design reuses rather than reimplements.
- `scripts/FarTierRules.gd`, `scripts/FarTierFormation.gd`, `scripts/TierTransition.gd`, `scripts/FormationTier.gd`, `scripts/UnitCombat.gd`, `scripts/UnitLeader.gd`, `scripts/Unit.gd` -- read in full while drafting this document, at commit `08b87e18`.
