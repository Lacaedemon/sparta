# Design note: fog of war

Status: **historical design note -- battle-side phases 1-2 shipped; phase 3
(AI consumption) has shipped its team-wide half (commander-scoped narrowing
and report propagation deferred); campaign/saga fog have not.**

Every date in this document is Pacific, including ones translated from a
GitHub timestamp, which the API reports in UTC.
This note was originally the design deliverable for
[#414](https://github.com/Lacaedemon/sparta/issues/414) (title: "add fog of
war"; body: "both in battles and in campaigns and sagas"; still open as of
2026-09-19, covering the remaining scope below), following the same
design-doc-first pattern as [`docs/battle-ai-design.md`](battle-ai-design.md)
(#498), [`docs/orders-queue-design.md`](orders-queue-design.md) (#516), and
[`docs/campaign-layer-design.md`](campaign-layer-design.md) (#582).
See
"Implementation status" immediately below for what has shipped since;
except where marked, the rest of this document is preserved as originally
written, describing the system before any of it existed.

It was also written as a **blocker for battle-AI phase 5**
([#588](https://github.com/Lacaedemon/sparta/issues/588)), whose entire scope
is "swap the omniscient placeholder implementation of the perception interface
for the fogged view, when fog of war (#414, battle side) lands."
That doc states the ownership split in its own non-goals: "#414 owns visibility
rules, rendering, and player UX; this design only consumes the resulting view
through the perception interface."
This note was the producer side of that contract; the battle-side visibility
and rendering it specifies (phases 1-2 below) have since shipped, and as of
2026-09-22 the phase-3 AI-consumption swap that closes the loop for #588 has
shipped its team-wide half -- see "Implementation status" below and
`docs/battle-ai-design.md`'s
own "Implementation status" section for why #588 spent over two weeks closed in
error.

## Implementation status (verified 2026-09-19)


| Phase | Scope | State |
| --- | --- | --- |
| 1 -- battle visibility core | per-team visible/remembered/unknown state, terrain `sight` axis | shipped |
| 2 -- fog rendering and player UX | ghost markers, `Settings` toggle, HUD indicator, targeting restricted to visible units | shipped |
| 3 -- the AI honors fog, the phase #588 tracks | `CommanderView`, AI reads the fogged view | shipped (team-wide view; commander-scoped narrowing deferred) |
| 4 -- campaign-map fog | province-level visibility on `CampaignState` | not shipped |
| 5 -- saga-scale knowledge | n/a -- saga layer does not exist | not shipped |

Phases 1 and 2 shipped, substantially as this document proposes, across
[#1560](https://github.com/Lacaedemon/sparta/pull/1560) (merged
2026-09-11) and [#1594](https://github.com/Lacaedemon/sparta/pull/1594)
(merged 2026-09-12), both dated Pacific: `scripts/Perception.gd` implements the
range-and-line-of-sight visibility test with screening-patch attenuation;
`Unit.sight_range`, `Unit.SIGHT_FOOT` / `SIGHT_MOUNTED` / `SIGHT_RANGED` /
`SIGHT_SCREEN_FACTOR` / `SIGHT_ROUTING_PENALTY`, and `Battle.sight_scale`
all exist as named; `BattleMap.parse` / `serialize` carry the proposed
`sight` key on terrain patches with the `kind`-derived default;
`scripts/FogGhostLayer.gd` draws the last-known ghost markers;
`Settings.fog_of_war` is the off-by-default toggle (`scripts/HUD.gd`, F7
hotkey and menu item); `scripts/SelectionManager.gd` restricts targeting to
visible units and falls a click on a ghost through to a ground-move order,
matching the open question below; the fog contact table is carried through
`Battle.capture_snapshot` / `restore_snapshot`; mid-battle fog transitions
are recorded as a replay track (`scripts/ReplayFogTrack.gd`, per
[#1579](https://github.com/Lacaedemon/sparta/issues/1579)); and the state
dump includes a ghost-records section (`tools/demo/DemoState.gd`, via
`FogGhostLayer.ghost_records()`).
One divergence from the proposal below, as originally written:
the shipped code had no persistent "explored terrain" grid and no
`FogOverlay` node -- there was no unexplored/explored *terrain* render
layer, `Battle.fog_cell` did not exist, and the "Fog rendering" section's
three-layer scheme below shipped only for units (visible /
hidden-with-ghost), not for terrain.

**Update, 2026-09-22: this divergence is closed by
[#1621](https://github.com/Lacaedemon/sparta/issues/1621) /
PR [#1623](https://github.com/Lacaedemon/sparta/pull/1623).**
A persistent per-cell explored grid (`Battle._fog_explored`, sized from
`Battle.fog_cell`, default 40 wu -- a tuned gameplay-legibility knob with no
physical derivation, authored as a bare wu literal per
`docs/units-convention.md`'s "Deliberately NOT metric" section, not dressed
in a metres expression) is now owned by `Battle`, survives
`capture_snapshot`/`restore_snapshot`, and only advances while fog is active
(paused, not cleared, while fog is off, mirroring `_fog_contacts`).
`scripts/FogOverlay.gd` renders it: an opaque unexplored fill,
a dimmed alpha over explored-but-not-currently-visible ground, and normal
rendering for ground inside the fog team's current sight coverage -- the
"Fog rendering" section's three-layer scheme below, now for terrain as well
as units.
The per-cell "currently visible"/"explored" test reuses `Perception.perceives`
directly (via the new `Perception.visible_cells`), so a cell is explored under
exactly the same range/screening/occlusion rules as an enemy unit.
The explored grid is scoped to the fog team only (matching `_fog_seen`/
`_fog_contacts`'s existing single-team shape), not generalized to a
per-team grid for every team in play -- that generalization is what phase 3
(`CommanderView`) would need, and stays open, tracked by that phase rather
than by this issue.
The state dump (`tools/demo/DemoState.gd`) exposes a `fog_terrain` summary
(grid shape, explored/total cell counts, currently-visible count) via
`FogOverlay.terrain_stats()`, the same way `ghosts` already exposes
`FogGhostLayer.ghost_records()`.

As of 2026-09-19, phase 3 had **not** shipped: no `CommanderView` class existed
in `scripts/`, and `scripts/UnitLeader.gd`, `scripts/Subcommander.gd`,
`scripts/General.gd`, and `scripts/PlayerDelegation.gd` each still documented
their perception source as omniscient -- `UnitLeader.gd` in exactly those
words, the other three as an "omniscient perception source" or an
"omniscient, already-serialized order".
GitHub nonetheless showed #588 as closed for over two weeks: it
closed at the same moment
[#1499](https://github.com/Lacaedemon/sparta/pull/1499) (the PR that
originally wrote this document) merged, because that PR's commit message
described a *future* phase 3's effect in a sentence that placed a closing
keyword next to the number.
GitHub's parser closes on any `<keyword> #N`
substring regardless of the sentence around it. #588 was reopened on
2026-09-19 once the cause was traced; the pattern is written up in
[#1614](https://github.com/Lacaedemon/sparta/issues/1614).
See
`docs/battle-ai-design.md`'s own "Implementation status" section for the
same note from the consumer side.

**Update, 2026-09-22: the team-wide half of phase 3 has shipped, still
without a formal `CommanderView` type.**
`Battle._ai_perceptible_units(team)` is the interposed perception source
this section's own "Build the interface" and "The invariant" subsections below describe:
a team's own units are always included,
and an enemy unit is included only when fog is off
(reproducing the prior omniscient set exactly)
or when `team` currently perceives it via `Perception.visible_enemy_uids`.
`Battle._run_enemy_ai`/`_run_player_delegated_ai` read from it instead of an unfiltered group query,
and `UnitLeader.decide`'s advance/attack fallback --
which used to bypass its own caller-supplied array entirely
and re-query the live groups directly through `UnitTargeting.nearest_enemy_to` --
now searches only that array (`UnitLeader._nearest_enemy_in`).
Four independent per-unit paths outside the command layer were found to have the same gap
during review, across two rounds,
and closed the same way:
`Unit._think()`'s auto-advance-on-detect fallback and its ranged-fire-at-standoff branch,
and `Unit._support_tick`'s own chase and ranged-fire branches,
each ran every physics tick,
picking a target from a bare `detection_range`/`SUPPORT_GUARD_RADIUS` scan
with no line-of-sight or fog test at all;
the ranged-fire branches were the sharper miss,
since `missile_range` can reach well past what fog lets a team see,
so a unit could loose a visible volley at a target the player's own screen still hides.
Every one of these branches now consults `Battle.ai_team_perceives`
(via `Unit._enemy_is_perceived`,
whose own doc comment names the currently-gated branches authoritatively,
kept there rather than duplicated in prose that can drift)
before chasing, or firing a standoff volley,
on an enemy not yet in MELEE contact --
leaving combat already in melee contact untouched.
Missile fire at standoff is itself one of the gated branches,
not exempt the way in-contact melee is:
a target already well within a unit's own `missile_range`
is still gated if it is not yet in melee contact and its side has not sighted it.
Only the auto-advance-on-detect fallback is actually AI-exclusive
(gated by `auto_advance_on_detect`);
the rest run identically for a player-commanded unit --
see "What the AI can see" above for why that is a deliberate symmetric choice,
not an omission.
The grep-based regression test this section's "The invariant" subsection calls for --
extended during review to also reject misuse of the `BattleRef` token,
not just a direct group lookup --
lives in `test/unit/test_battle_ai_fog.gd`,
alongside fog-on/fog-off coverage for each of the per-unit paths above.
It does not catch a live Battle instance reached through some other untyped variable,
a known gap the test's own header records
(reliably catching that needs real static type analysis, not a grep).
**Update, 2026-09-23: three more fresh-acquisition gaps found and closed during a later
review round -- the ORDER_SKIRMISH kite branch, the ORDER_SWEEP_ROUTERS and
ORDER_ROLL_THE_LINE target acquisitions, and the `chasing`-with-no-committed-`target_enemy`
half of the chase branch (its `target_enemy != null` half stays the disclosed exception) --
plus the same FRESH-reacquisition gap in far-tier attrition (`FarTierCombat.
engaged_target`). See `Unit._enemy_is_perceived`'s own doc comment for the complete,
current list.**
Team-wide, not commander-scoped:
every level of one team's chain reads the same set this AI tick,
matching this document's own "Phase 3 below implements the team-wide view first
and the commander-scoped narrowing second" sequencing
(see "Friendly visibility" above).
Commander-scoped narrowing and up-the-chain report propagation are tracked
as [#1625](https://github.com/Lacaedemon/sparta/issues/1625);
AI reasoning over a stale `last_known` contact
(this document's own "Last-known contact" section above)
rather than only current perception
is [#1626](https://github.com/Lacaedemon/sparta/issues/1626).

Phases 4 and 5 (campaign and saga fog) have not started: `scripts/campaign/`
has no visibility code, and the saga layer itself still does not exist.
[#414](https://github.com/Lacaedemon/sparta/issues/414) stays open to track
exactly that remaining scope.

## Motivation

### Both armies currently see everything, and nothing in the code pretends otherwise

*(As verified before phase 1 of this design shipped.
See "Implementation
status" above for what changed; the corrective paragraph after this
section's original text says what is still true today and what is not.)*

There is no visibility layer in the tree at all.
`git grep -in fog` finds no visibility *code*: the three hits under `scripts/`
are all comments saying the feature is absent.
`scripts/Battle.gd`'s `ROUT_MARGIN` comment calls `Unit.DETECTION_RANGE` "the
closest existing stand-in for a fog-of-war vision range, which this game
doesn't have yet", and `scripts/UnitLeader.gd` twice describes its own
perception as omniscient today and fogged only in battle-AI phase 5.
The remaining hits are prose: `docs/battle-ai-design.md`'s forward references
to this issue, two passing mentions of other games in `docs/related-games.md`
(lines 173 and 323), and `website/roadmap.qmd`'s roadmap line about
"fog-of-war-aware perception".
Every living unit is a `Node2D` that draws itself, so anything inside the
camera's view renders regardless of which team is looking, and every AI read
goes straight to `get_tree().get_nodes_in_group("units")`.

The result is a battle in which both commanders have a live satellite feed.
The player can watch an enemy reserve form up behind a hill and counter it
before it moves; the AI general can react to a flank march the instant it is
ordered.
Every decision in the game is therefore a decision made with perfect
information, which removes an entire dimension of generalship: reconnaissance,
screening, deception, and the reserve committed at a moment the enemy cannot
yet see are all unrepresentable.

**Since #1560/#1594, this is no longer true for the player.**
A
`Perception` module, ghost markers, terrain occlusion and screening, and an
off-by-default `Settings.fog_of_war` toggle now exist
(`scripts/Perception.gd`, `scripts/FogGhostLayer.gd`); with the toggle on,
the player sees only what their own units' sight radii and lines of sight
cover, per the mechanism proposed below.
**It was true for the AI until 2026-09-22.**
`Battle._run_enemy_ai()` and the whole chain-of-command AI used to read
`get_tree().get_nodes_in_group("units")` directly, with no fog applied,
regardless of the `Settings.fog_of_war` toggle.
As of that date, `Battle._ai_perceptible_units(team)` is what they read
instead -- fogged when `team`'s own side does not perceive an enemy, and
unconditionally omniscient (reproducing the old behaviour exactly) when fog
is off -- see "Implementation status" above and
`docs/battle-ai-design.md`'s own note on the same swap.

### The historical case

Ancient and early-modern battles were fought substantially blind.
Polybius records Hannibal at Lake Trasimene concealing his army on the wooded
heights above the lake and attacking a Roman column marching through morning
mist that hid the ambush until it closed
([Polybius, *Histories* III.83-84](https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.01.0234:book=3:chapter=83)).
The same author's account of Cannae records Hasdrubal's cavalry breaking the
Roman horse, riding round behind the line, and charging the Roman rear
([Polybius, *Histories* III.116](https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.01.0234:book=3:chapter=116)).
Polybius says nothing there about what the Roman command could or could not
see; the reading that an envelopment completed behind an already-engaged
infantry line is learned about late is this note's inference, not his claim.
Clausewitz generalized the condition a great deal later: war is "the realm of
uncertainty", in which "three quarters of the factors on which action in war is
based are wrapped in a fog of greater or lesser uncertainty"
(Clausewitz, *On War*, Book I, Chapter 3, Howard and Paret translation,
Princeton University Press, 1976).
A game whose stated pillar is bottom-up emergence (`PLAN.md`, pillar 2) has a
particular reason to want this: uncertainty is what makes a screening line of
skirmishers, a hidden reserve, and a deliberate feint into decisions rather
than decoration.

### #588 is blocked on the perception contract, not on the renderer

`docs/battle-ai-design.md` already fixed the AI-side requirement, as an owner
decision: "the AI honors fog of war ... same visibility rules, same
information, no omniscient fallback, no cheating."
It also fixed the interface shape, as a sketch: `visible_units(team)`,
`last_known(uid)`, `own_units()`, `reports()`.
What it explicitly deferred to this issue is everything that makes those
signatures answerable -- what "visible" means per unit, what `last_known`
persists, and whether distant friendlies outside a commander's own command are
fogged.
Those three questions are the core of this note.

## Current state

Verified against the tree at the time of writing.

### What the player can see

- Every `Unit` is a scene-tree `Node2D` that renders unconditionally.
  There is no per-team draw filter anywhere in `scripts/`.

- `scripts/SelectionManager.gd` is mouse control for team 0, or for every team under `Battle.all_teams_control` (the debug mode in `scripts/AllTeamsControl.gd`).
  Left click selects a friendly unit by its block or its raised flag, box-drag selects several, right click issues a move or an attack on the enemy unit clicked.
  Its `_unit_at` hit test resolves any unit's body or flag.
  Nothing consults visibility, so an enemy unit anywhere on the field is right-clickable as an attack target.
  **This changed in [#1560](https://github.com/Lacaedemon/sparta/pull/1560):** with `Settings.fog_of_war` on, `_unit_at` now honors `unit.visible`, so an unseen enemy cannot be clicked or targeted;
  a right click on empty fog or on a ghost marker falls through to a ground-move order instead.

- `scripts/CameraController.gd` is a free RTS camera: WASD and arrow-key pan, screen-edge pan, wheel zoom between `zoom_min` 0.45 and `zoom_max` 2.2, with `bounds` clamped to the battlefield rect Battle publishes.
  It is unconstrained within the field, which is the standard RTS arrangement and stays correct under fog.

- `scripts/HUD.gd` builds the on-screen UI in code: distance legend, menu button, selected-unit info panel, per-unit settings, and the unit card tray (`scripts/UnitCardTray.gd`).
  There is **no minimap** in the HUD today, so there is no second surface needing its own fog treatment in the first battle phase.

- `Battle.FIELD` is `Rect2(0, 0, 1600, 1200)`, which at `WorldScale.WU_PER_M` = 20.0 is an 80 m by 60 m field (`docs/world-scale-rebase-plan.md` states the same figure).
  The default spawn lines (`Battle.SPAWN_LINE_YS`) are y = 300 and y = 880, so the two armies start 580 wu = 29 m apart.
  This is the single most important constraint on the whole design.
  See "The scale problem" below.

- `Battle.ROUT_MARGIN` is `UnitRef.DETECTION_RANGE` = 190 wu (it was `maxf(UnitRef.RANGED_RANGE, UnitRef.DETECTION_RANGE)` until the missile reach became per unit), and `field_with_margin = field.grow(ROUT_MARGIN)` (`scripts/Battle.gd:41-42`, recomputed for the live map at `:531`) is what every spawned unit receives as `Unit.retreat_bounds` (`:1088`).
  A router that leaves it is removed from play by `Unit._escape()`.
  The comment above it states an invariant this design has to honour: the margin is sized to "the game's maximum visual range", with `DETECTION_RANGE` standing in for "a fog-of-war vision range, which this game doesn't have yet", "so a fleeing unit stays a plausible target for as long as it's still visible, rather than vanishing early".
  Phase 2 equips pilum units with 300-wu detection while intentionally keeping `Battle.ROUT_MARGIN` battle-wide and fixed at 190 wu to prevent per-unit boundary drift.
  `Battle.ROUT_MARGIN` remains fixed at 190 wu regardless of fog, not because fog is render-only overall (it is not: see "Implementation status" above), but because this specific value never reads fog state at all -- it is a compile-time `const`, and `Battle._sync_rout_margin` (its only recompute path, called once at battle setup from the live map's own geometry) has no fog-state input, nor is it ever called from `Battle._on_settings_changed`'s own fog-toggle handler.

### What the AI can see

*(Accurate as of 2026-09-19 --
describes the omniscient state this section's own bullets record,
which `Battle._ai_perceptible_units`
(the "Implementation status" section's 2026-09-22 update, above)
has since replaced with the fogged-or-omniscient view for every consumer named below.
`UnitTargeting.nearest_enemy`/`nearest_routing_enemy`'s own bare-radius detection_range scan
(last bullet) is unchanged in itself --
it still governs soldier-level auto-engagement,
which stays unfogged by design --
but four per-tick branches built on top of it now gate on perception
before treating a detected-but-not-yet-in-range enemy as a valid chase or fire target:
`Unit._think()`'s auto-advance-on-detect fallback and its own ranged-fire-at-standoff branch,
and `Unit._support_tick`'s chase and ranged-fire branches.
Only the first of those four is actually AI-only,
gated by `auto_advance_on_detect`
(true for the AI-driven army,
false for a player-commanded unit,
which always holds formation and waits for an order regardless of fog either way).
The other three run for BOTH teams:
a player's own idle ranged unit,
or a player unit placed on the Support order (selectable from the HUD),
is gated exactly the same way its AI-controlled counterpart is --
a deliberate, player-visible design choice
(not an oversight left over from the AI-only first pass),
settled during review:
fog is symmetric,
so a player unit that could snipe or chase past its own player's fogged screen
would itself be a fog-breaking exploit,
and one shared rule is simpler than carving the AI out as a special case.
See that "Implementation status" update for the detail.)*

- The chain-of-command AI is implemented through phase 4: `scripts/UnitLeader.gd`, `scripts/Subcommander.gd`, `scripts/General.gd`, `scripts/DoctrineRegistry.gd`, and `scripts/PlayerDelegation.gd`, dispatched from `Battle._run_enemy_ai()` and `Battle._run_player_delegated_ai()` on the `ai_period` cadence (default 60 ticks, once per second at `Replay.PHYSICS_TPS` 60).

- Every one of those files documents its perception source as the omniscient placeholder.
  `UnitLeader.gd`'s class doc says "perception is the omniscient placeholder the design doc describes -- every living unit is visible;
  phase 5 swaps this for a fogged view".
  `General.gd`'s class doc says it reads "the same omniscient perception every other command level reads".

- There is **no `CommanderView` class in the tree**.
  The interface `docs/battle-ai-design.md` sketches was never built as a type.
  The commanders take the units array their caller passes and read it directly.
  Introducing the type is therefore part of this work rather than a pre-existing seam to swap behind, and it is the largest single piece of unplanned work this design surfaces.

- `Unit.DETECTION_RANGE` is `9.5 * WorldScaleRef.WU_PER_M` (190 wu = 9.5 m), exposed per unit as the caller-configurable `Unit.detection_range`.
  It is a **target-acquisition** radius consumed by `UnitTargeting.nearest_enemy` and `UnitTargeting.nearest_routing_enemy`, not a sight radius.
  It governs which enemy a unit auto-engages.
  For unprofiled and default-bow units, at 9.5 m it is barely longer than `Unit.RANGED_RANGE` (`8.0 * WorldScaleRef.WU_PER_M` = 160 wu = 8 m).
  Units equipped with the pilum profile scale `detection_range` to match their 15.0 m (300 wu) missile reach.
  Sight is a separate quantity needing its own field.
  Conflating the two would silently change combat.

### The terrain model

- `Battle.TERRAIN` is the default patch table, holding two patches: a `forest` patch at `Rect2(200, 380, 250, 200)` with `kind` `"slow"` and `speed` 0.6, and a `hill` patch at `Rect2(1150, 380, 250, 200)` with `kind` `"block"`.

- `scripts/BattleMap.gd` is the per-battle map parser and is strict: `kind` must be `"block"` or `"slow"`, a `"slow"` patch requires a numeric `speed`, and `type` is a free string (defaulting to `"hill"`) that keys `Battle.TERRAIN_COLOR` for rendering.
  `BattleMap.serialize` is its inverse and is what the replay header records, so playback reconstructs the same battlefield.

- `Battle._ready` registers each patch on `PathField.active`: a `"slow"` patch becomes `set_speed_rect`, anything else becomes `block_rect`.

- `scripts/PathField.gd` already carries the occlusion primitive this design needs.
  Its own class doc describes two layers of obstacle geometry, of which the first is exact: "The EXACT terrain rects decide what is actually blocked: every sightline test (the straight-line fast path, string-pulling visibility, `is_blocked`) runs against the drawn rects themselves, grown by the caller's own `clearance`".
  The segment test itself is the private `PathField._segment_blocked(from, to, clearance)`, and it already has a public wrapper: `PathField.is_leg_blocked(from, to, clearance := 0.0)` (`scripts/PathField.gd:184-185`) forwards to it verbatim, so a visibility caller passing `clearance` 0.0 needs no new entry point and no rename.
  Its only caller today is `Unit.funnel_lane_offset`'s same-team congestion gate (`scripts/Unit.gd:3516`), and its doc comment frames it as a cheap "is this unit actually about to detour" test, which is the same question a sightline asks.

- Terrain is **flat**: a `"block"` patch is an impassable rect, not a height.
  There is no heightfield and no elevation anywhere in the sim, so elevation-driven vision (seeing over a wall, being seen from a ridge) has nothing to read and is out of scope until one exists.

### Replay and determinism

- `scripts/Replay.gd` is a deterministic-simulation-plus-input-log recorder.
  Its own class doc: "We do NOT record the state of every unit each frame.
  Instead we record just two things: the RNG seed, and the player's orders, each stamped with the physics tick it took effect."

- AI decisions are re-derived on playback rather than recorded, on the same tick cadence, which `docs/battle-ai-design.md` states as the design's replay rule ("re-derive, don't record").

- `Replay.rng` is the one seeded stream, seeded once per battle and never reseeded elsewhere.

- `scripts/ReplaySnapshotCache.gd` plus `Battle.capture_snapshot`, `restore_snapshot`, and `seek_to_tick` let a playback rewind resume from a cached mid-battle state instead of resimulating from tick 0.
  This matters here because explored-terrain state is **cumulative**, so unlike instantaneous visibility it cannot be recomputed from the state at one tick.
  See "Determinism and replay" below.

### Campaign and saga

- `scripts/campaign/CampaignState.gd` is the M2 campaign: provinces with an owner and an integer army strength, per-pair war and peace stances, one move per army per turn, auto-resolved or battle-resolved attacks.
  Every province's owner and army are readable by everyone.
  There is no visibility concept.

- `scripts/campaign/CampaignHUD.gd`'s `_overlay` is the victory and defeat overlay, not a fog layer.
  The only `visible` writes in the campaign scripts are that overlay's.

- The saga layer does not exist in code.
  `docs/campaign-layer-design.md` scopes it (#126, #428) as a layer above campaigns with interwar periods and city founding, and that design is itself unimplemented.

## The scale problem, stated first

An 80 m by 60 m field with armies deploying 29 m apart cannot support a
realistic sight model.
An unobstructed observer on flat ground can make out a body of troops at
kilometre range, so a physically honest sight radius would cover the entire
battlefield several times over and fog would be permanently empty.

Three positions are available, and this design takes the third.

1. **Fog scaled to the current field.**
   Pick a sight radius that is a fraction of the field (say 20 m on an 80 m map) and accept that it is not a physical claim about eyesight.
   Cheap, works today, and is the only option that produces visible fog before the world-scale rebase.

2. **Wait for the rebase.**
   `docs/world-scale-rebase-plan.md` (#891) rebases the sim to 1 wu = 1 m, which buys float precision but does not by itself enlarge the field.
   Waiting therefore does not actually solve this, and blocks #588 indefinitely.

3. **Make the sight radius a first-class map-scale parameter, defaulted to a fraction of the field.**
   Sight range is authored per unit type as a multiple of a per-battle `sight_scale` rather than as an absolute metre figure, with `sight_scale` defaulting to a fraction of the shorter field dimension.
   On today's 80 m by 60 m field that yields a short, visibly meaningful radius.
   On a future 800 m field the same data yields a proportionally longer one without re-authoring every unit.
   The doc is then honest about what the number is -- a **gameplay legibility parameter**, not a claim about eyesight -- which is exactly the distinction `docs/units-convention.md` draws for deliberately unit-tuned knobs.

This is worth stating before the mechanism because it decides the shape of the
parameter table: sight is authored as a ratio, and only the per-battle scale is
authored in metres.

## Proposed mechanism

*(As designed.
Phases 1-2 below shipped substantially as described, with
the exceptions called out per-phase in "Implementation status" above and
inline below.
Phases 3-5 remain as originally proposed -- not yet built.)*

### Three knowledge states, per observing team, per target unit

- **Visible** -- some living unit of the observing team perceives the target this tick.
  The target renders normally, is selectable as an order target, and appears in `visible_units()`.

- **Remembered** -- the target was visible at some earlier tick and is not visible now.
  The last observation is retained (position, facing, strength, state, tick) and rendered as a ghost marker.
  `last_known(uid)` answers from here.

- **Unknown** -- never seen.
  Nothing renders and nothing is returned.

Terrain gets its own two-state axis, independent of units, because a
battlefield you have walked is a battlefield you know the shape of:

- **Explored** -- some friendly unit's perception has covered this ground at some tick.
  Terrain and ground art render normally.

- **Unexplored** -- never covered.
  Rendered as an opaque unexplored layer.

**This terrain axis shipped in
[#1621](https://github.com/Lacaedemon/sparta/issues/1621)/#1623
(2026-09-22), as the fuller three-state scheme the "Fog rendering" section
below already describes** (explored ground that is not currently visible
renders dimmed, not fully normal as the simpler two-state description above
suggests) rather than this paragraph's original two-state simplification.
See "Implementation status" above.

### Observers are units, never the camera

Visibility is computed from the union of the observing team's living units'
perception, and from nothing else.
The camera is a viewing convenience with no perceptual standing: the player may
pan and zoom anywhere inside the field, and panning reveals nothing.
This keeps `CameraController` untouched, matches the standard RTS convention,
and -- more importantly -- keeps the player's information identical in kind to
the AI's, which is what makes "no omniscient fallback, no cheating" a checkable
claim rather than an aspiration.

### One unit's perception

For an observing unit `u` and a candidate target `t`, `t` is perceived when
both of these hold.

1. **Line of sight.**
   The segment from `u.position` to `t.position` is not blocked by an occluding terrain patch, evaluated against the exact drawn rects via the existing public `PathField.is_leg_blocked(from, to, 0.0)` (`scripts/PathField.gd:184-185`).

2. **Range, attenuated by screening.**
   `u.position.distance_squared_to(t.position) <= effective_sq`, where `effective_sq` is `pow(u.sight_range * pow(SIGHT_SCREEN_FACTOR, n_screens), 2.0)` and `n_screens` is the number of distinct screening patches that same segment crosses.

The two conditions compose rather than stacking independently: the range test
is against the *attenuated* range, never the full one.
Spelling that out matters because the two are easy to read as separate gates.
On the defaults below, a foot unit's 300 wu becomes 150 wu behind one screening
patch and 75 wu behind two, so a target at 290 wu across one forest patch is
**not** visible even though it is inside the unattenuated radius.
Squared distance is used for the same reason
`UnitTargeting.nearest_routing_enemy` already does, and `effective_sq` is
computed once per observer-target pair rather than per comparison.

Attenuation counts patches crossed and ignores where along the segment each one
sits, and how much of the segment lies inside it.
A unit standing at the far edge of a wood is therefore screened exactly as much
as one standing a hair inside it.
That is the cheap and predictable reading; a chord-length-weighted alternative
is a later tuning question, not a phase-1 one.

Both operands are `Node2D.position` and therefore parent-local, which is the
same convention the soldier body arrays and `UnitCombat.flank_multiplier`
already use.
`CLAUDE.md` records that a `global_position` mix-up here is a latent bug, so
the visibility code follows the existing convention rather than inventing a
second one.

### Terrain occlusion, on a third patch axis

Occlusion is a new, independent property of a terrain patch, not a re-reading
of `kind`.
Movement blocking and sight blocking are genuinely different questions -- a
wheatfield screens without blocking, a low wall blocks without screening -- so
the schema gets a third key rather than deriving one from the other.

Proposed `BattleMap.parse` addition: an optional `sight` key on each patch, one
of `"clear"`, `"screen"`, or `"block"`, with a default derived from `kind` so
every existing map and replay keeps working unchanged.

| `kind` | default `sight` | effect on a sightline crossing the patch |
| --- | --- | --- |
| `block` | `block` | the sightline is blocked outright |
| `slow` | `screen` | remaining sight range is multiplied by `SIGHT_SCREEN_FACTOR` per patch crossed |

A patch may override the default in either direction, which is what makes the
axis worth adding: an open rocky slope is `kind: "slow"` with `sight: "clear"`,
and a stone wall is `kind: "block"` with `sight: "block"` by default but could
be a palisade at `sight: "screen"`.

The default table under this rule reads as it should: the `hill` block patch
occludes (a hill you cannot walk through is a hill you cannot see through, on a
flat map), and the `forest` slow patch screens (troops in woods are seen late
and imperfectly).
Because `BattleMap.serialize` is the replay header's inverse of `parse`, the
new key must round-trip there too, and must be absent on a patch that took the
default so old replays stay byte-comparable.

### Detection ranges per unit type

Sight range is a caller-configurable per-unit field with a type-derived
default, following `CLAUDE.md`'s parameters convention exactly as
`Unit.detection_range` already does.

Proposed parameters:

| Parameter | Proposed default | Rationale |
| --- | --- | --- |
| `Battle.sight_scale` | `0.25 * min(field.size.x, field.size.y)` = 300 wu = 15 m on the default field | The per-battle scale everything else multiplies; a gameplay legibility parameter, not an eyesight claim |
| `Unit.SIGHT_FOOT` | 1.0 | Baseline: infantry and spearmen |
| `Unit.SIGHT_MOUNTED` | 1.4 | Higher eye level and the scouting role cavalry historically owned |
| `Unit.SIGHT_RANGED` | 1.2 | Skirmishers and archers screen and observe ahead of the line |
| `Unit.sight_range` | resolved from `is_cavalry` and `is_ranged` at spawn, overridable before `_ready` | The same set-before-tree contract `detection_range`, `drill_mode`, and `ai_doctrine` already follow |
| `Unit.SIGHT_SCREEN_FACTOR` | 0.5 | Remaining range through one screening patch |
| `Unit.SIGHT_ROUTING_PENALTY` | 0.6 | A routing unit is not observing; multiplies its own sight range while its state is ROUTING |
| `Battle.ROUT_MARGIN` | 190 wu | Unaffected by fog: a compile-time const, never recomputed from fog state (see "The rout margin is decoupled from fog of war" below) |

The multipliers are gameplay tuning and are labelled as such; only
`sight_scale`'s tie to field size is a structural claim.
The defaults key off two flags, `Unit.is_cavalry` and `Unit.is_ranged`, both of
which exist today (`scripts/Unit.gd:148,150`).
`Unit.anti_cavalry` exists too (`:149`) but drives no sight default: spearmen
sit at the `SIGHT_FOOT` 1.0 baseline.

Deliberately **not** modelled in the first battle phase, each because the sim
has nothing to read: facing-limited vision cones (a unit sees a full disc),
elevation, weather, dust, and night.
Each is a natural later phase and none of them changes the interface.

**A unit is a point, for both tests.**
Range and line of sight are both evaluated between `u.position` and
`t.position` -- the unit centers -- so a unit is either wholly visible or
wholly invisible, with no partial state.
That is a material approximation at this scale rather than a free
simplification: `Unit.FORMATION_SPACING` is `0.45 * WU_PER_M` = 9 wu
(`scripts/Unit.gd:7153`) and `NORMAL_SPACING_SCALE` is 2.0 (`:596`), so a
normally-spaced line's file pitch is 18 wu and a modest frontage is a large
fraction of the 300 wu foot sight radius proposed below.
Two consequences follow, and both are accepted here.
A unit half-emerged from behind the default `hill` block patch is entirely
invisible until its center clears the patch.
A wide line whose center sits just outside sight range is entirely invisible
even while part of it stands well inside.
The alternative -- testing the unit's extent, or sampling its soldier slots --
costs a per-soldier loop in a per-tick per-pair test and buys a partial
visibility state that nothing downstream (the ghost markers, the AI view, the
explored grid) currently has a representation for.
Extent-based or partial visibility is therefore a named later phase, listed
under the open questions below.

**The rout margin is decoupled from fog of war.**
`Battle.ROUT_MARGIN` remains fixed at `DETECTION_RANGE` = 190 wu.
This is not because fog is render-only overall (it is not: it also gates AI/order
targeting, see "Implementation status" above) -- it is because `rout_margin` and
`field_with_margin` are recomputed only from the live map's own geometry
(`Battle._sync_rout_margin`, called once at battle setup), with no fog-state input
anywhere in that computation, and `Battle._on_settings_changed`'s own fog-toggle handler
never calls it.
A routing enemy crosses `Unit.retreat_bounds` and escapes at the same tick whether fog of war is enabled or disabled.
A mid-battle fog toggle cannot desync `rout_margin` between recording and playback for this
reason alone; the fog state itself also replays deterministically now, via the
per-tick fog track (`sparta#1579`, `Replay.record_fog_change` / `Replay.fog_for_tick`).
`Battle.rout_margin` remains an instance property initialized to `ROUT_MARGIN` for compatibility, but its value is constant.

### Last-known contact

Per observing team, a dictionary keyed by target unit id.
Each entry is written on the last tick the target was visible, and is never
written otherwise:

```text
{
  "position": Vector2,   # where it was last seen
  "facing": float,       # its facing at that moment
  "strength": int,       # living soldiers when last seen
  "state": int,          # Unit.State when last seen
  "tick": int,           # the physics tick of the observation
}
```

This is exactly the payload `docs/battle-ai-design.md`'s `last_known(uid)`
sketch anticipates ("position/facing/strength as of the tick it was last seen,
plus that tick"), plus `state`, which the sketch omits and which the AI needs
in order to distinguish a unit last seen fighting from one last seen routing.

An entry is **never deleted while the unit lives**, so a commander's memory
does not silently improve.
It goes stale on its own instead: `tick` is in the record, so both the renderer
and the AI can compute staleness and act on it.
Proposed `Battle.contact_stale_ticks`, default 600 (10 s at 60 Hz), after which
the ghost marker fades and the AI treats the contact as unreliable rather than
absent.
A unit that dies while unobserved leaves its last-known entry in place -- the
enemy commander does not learn of a death it did not see, which is the whole
point.

### Friendly visibility

`docs/battle-ai-design.md` left this open, noting that fog "governs knowledge
of the *enemy* (and, once #414 defines it, possibly distant friendlies outside
the command)."

This design settles it: **friendly units of the same team are always visible to
that team.**
An army in the field has runners, standards, and a chain of command, and the
battle-AI design already requires that a commander always knows its own units'
positions and states.
Making distant friendlies fogged would additionally split the player's own HUD
into known and unknown friendly units, which is a large UX cost for a small
realism gain on an 80 m field.

The **commander-scoped** variant is a different question and a real one: a
subcommander's view is its own subtree's perception plus what has been reported
to it, which is narrower than the team view.
That is where the historical texture lives -- "a general reacts to a flanking
force *because a unit saw it*" -- and it is the interface's job to route it.
Phase 3 below implements the team-wide view first and the commander-scoped
narrowing second, because the first is what unblocks #588's acceptance test and
the second is a refinement of it.

### Fog rendering

*(As designed.
The shipped code implements layer 3 (visible, unchanged)
and layer 2 for units -- ghost markers at reduced alpha -- and, as of
[#1621](https://github.com/Lacaedemon/sparta/issues/1621), layers 1 and 2
for ground/terrain as well: `scripts/FogOverlay.gd` draws the opaque
unexplored fill and the dimmed explored-but-not-visible fill described
below, reading `Battle._fog_explored` (sized from `Battle.fog_cell`).
See "Implementation status" above.)*

Three layers, drawn above the battlefield and below the HUD.

1. **Unexplored.**
   Opaque fill in a darkened `Battle.FIELD_COLOR`, hiding ground art and terrain patches entirely.

2. **Explored but not currently visible.**
   The ground and terrain render normally, dimmed by a constant alpha.
   Remembered enemy units render as ghost markers -- the unit's block outline and standard at the last-known position and facing, at reduced alpha, fading further as the contact passes `contact_stale_ticks`.

3. **Visible.**
   Normal rendering, exactly as today.

Proposed implementation, as originally designed: a `FogOverlay` `Node2D`
(shipped at `scripts/FogOverlay.gd`, [#1621](https://github.com/Lacaedemon/sparta/issues/1621))
at a z-index above the battlefield, drawing a coarse visibility grid --
built substantially as proposed, with two divergences from this original
paragraph's own numbers.
First, `Battle.fog_cell` shipped with a default of 40 wu, giving a 40 by 30
cell grid on the default field, but not as this paragraph originally
proposed authoring it (`2.0 * WorldScaleRef.WU_PER_M`): `fog_cell` has no
physical derivation, so the shipped constant keeps a bare wu literal marked
`# tuned in wu` instead, per `docs/units-convention.md`'s "Deliberately NOT
metric" section (see the "Update, 2026-09-22" note above).
Second, this paragraph originally expected the coarse grid to need
smoothing, supplied by a bilinear-filtered `ImageTexture`; the shipped
`FogOverlay._draw()` instead draws hard-edged `draw_rect()` cells with no
texture and no smoothing, so the grid's cell boundaries are visible at
normal zoom rather than blended.
A smoothing pass remains a possible follow-up, not something #1621 built.
Enemy unit nodes are hidden by setting `CanvasItem.visible`, never by removing
them from the `units` group; see the determinism section for why that
distinction is load-bearing.

Player-facing numbers stay metric per `docs/units-convention.md`: if fog UI
ever displays a distance (a scout report, a contact age in seconds), it renders
through `DistanceLegend`'s helpers, never as a raw world-unit figure.

## How the AI consumes perception without cheating

*(As designed -- this whole section describes phase 3, which has not
shipped.
See "Implementation status" above.)*

### Build the interface `docs/battle-ai-design.md` sketched

The commanders currently read the units array their caller hands them.
The first structural step is to interpose the type that doc describes, so the
AI's only door onto the battle is a view object:

```text
# PROPOSED -- scripts/CommanderView.gd, following docs/battle-ai-design.md's sketch.
func visible_units(team: int) -> Array
func last_known(uid: int) -> Dictionary
func own_units() -> Array
func reports() -> Array
```

Interposing it while the implementation is still omniscient is a no-op change
that can be verified by a byte-identical replay, which is a much safer place to
prove the seam than inside the fog change itself.

### The invariant

**No AI code path reads `get_tree().get_nodes_in_group("units")`, or any other
unfiltered world state, directly.**
Every read goes through a `CommanderView`.
This is structurally enforceable and structurally checkable: a grep over
`scripts/UnitLeader.gd`, `scripts/Subcommander.gd`, `scripts/General.gd`, and
`scripts/PlayerDelegation.gd` for group lookups and for direct `Battle` field
access is a cheap regression test, and one belongs in the suite.

### What each level sees

- **Own command.**
  Always fully known, fog or no fog.
  This is `own_units()`, and it is exempt by the requirement above.

- **Enemy.**
  Only what the commander's scope perceives, plus remembered contacts through `last_known`.

- **Reports.**
  A subordinate's sighting reaches its superior through `reports()`, which is how a general learns of a flanking force it cannot itself see.
  Report latency is a natural knob and is deliberately left at zero in the first pass, matching `docs/battle-ai-design.md`'s own "chain latency" open question, which defaults to no extra latency beyond the existing per-unit `order_response_delay`.

### Difficulty never comes from perception

`docs/battle-ai-design.md` names this in its open questions and this design
adopts it unchanged: player-facing difficulty comes from doctrine quality and
doctrine parameters, never from letting the AI see more than the player.
A "poor commander" profile is a doctrine with worse plan weights, not a
commander with a longer sight radius.
Any future difficulty knob that widens AI sight is a design regression and
should be rejected on sight.

## Determinism and replay

### Visibility is derived, so it is recomputed rather than recorded

Instantaneous visibility is a pure function of serialized sim state: unit
positions, unit sight ranges, and the terrain table, all of which the replay
already reconstructs.
So playback recomputes it on the same cadence and **no visibility state is
recorded**: no per-tick visible set, no explored grid, and no contact table
ever reaches the file.
The replay *header* does change shape in one place, and this note should not
claim otherwise: `Replay.map` records "the battle's MAP block
(`BattleMap.serialize`'s shape)" (`scripts/Replay.gd:149`), so once phase 1
adds a `sight` axis to terrain patches, a map carrying a non-default `sight`
writes a key older builds never wrote.
The version policy for that key is the additive one the map block itself
already follows: `sight` is omitted whenever a patch takes the default, so
every default-sight replay stays byte-identical to today's.
`Replay.FORMAT_VERSION` deliberately does **not** bump, because
`Replay.start_playback` rejects on strict inequality
(`scripts/Replay.gd:222`), so a bump would invalidate every replay already
recorded rather than merely teaching old builds to refuse new ones.
The residual gap is one-directional and accepted: an old build reading a new
replay whose map carries a non-default `sight` ignores the key and replays the
battle at default sight.
Nothing in the sim reads `sight` before phase 3, and the cheaper fix when it
does start to matter is a per-key capability check in the header rather than a
global version bump.
This is the same rule `docs/battle-ai-design.md` applies to AI decisions
("re-derive, don't record"), and it holds for the same reason.

### The cumulative state is the exception

Explored terrain and the last-known contact table are **not** functions of the
current tick -- they are accumulations over every tick since the battle began.
Two consequences follow.

- **Recomputing from tick 0 is correct but not free.**
  A playback that starts at tick 0 and runs forward accumulates them correctly with no extra machinery.

- **A snapshot rewind is where this breaks.**
  `Battle.capture_snapshot` and `restore_snapshot` (`scripts/ReplaySnapshotCache.gd`) resume from a cached mid-battle moment, and a resumed state with an empty explored grid would show a player a fog that has forgotten ground the battle already covered.
  So the explored grid and the contact table must be captured in the snapshot alongside the rest of the derived state.
  The explored grid at the proposed 40 by 30 cells is one bit per cell, so the cost is negligible.
  The contact table is bounded by the unit count.

### Rendering must not feed back into the simulation

This is the sharpest trap in the design.
`UnitTargeting.nearest_enemy` and `UnitTargeting.nearest_routing_enemy` iterate
the `units` and `routers` groups, and `Battle` iterates `units` in several
places.
If fog were implemented by removing hidden units from those groups, **combat
would change** -- a unit would stop auto-acquiring an enemy the *player* cannot
see, which is both wrong and a silent desync between a recording and its
playback if the two ever differed in render state.

So the rule is explicit.
Fog affects `CanvasItem.visible` and ghost markers.
The retreat margin is unaffected either way.
The recorded replay map value drives playback.
A headless run with no rendering at all and a rendered run must produce byte-identical replays under the recorded fog state.
**Update, 2026-09-23: two claims in this paragraph no longer hold.**
`sparta#1579` shipped (`ReplayFogTrack.gd`, `Replay.record_fog_change` /
`Replay.fog_for_tick`), so a mid-battle toggle IS now reproduced on playback --
`Battle._on_settings_changed` records every RECORD-mode toggle at the tick it happened, and
`Battle._physics_process` re-applies it at the identical tick during playback, the same way
a queued order is replayed.
And "targeting... untouched" is no longer accurate at all: `Battle.ai_team_perceives` /
`Unit._enemy_is_perceived` (this PR, phase 5) gate AI/order targeting on the SAME perception
this section describes -- group membership, `_physics_process`, and collision remain
untouched, but targeting does not.

The corollary is that **soldier-level combat stays unfogged**: a soldier
strikes whoever is in reach whether or not the commander can see the unit.
Fog is a command-level information model, not a per-soldier sense model.

### Verification through the state dump

The per-tick state transcript that `verify-via-state-dump` reads is the natural
place to assert visibility, and it needs a per-team visibility section: which
enemy unit ids each team currently sees, and each team's last-known table.
That turns every acceptance test below into a transcript assertion rather than
a judgement call about a video, which is what `CLAUDE.md` asks for.

## Phase plan

Design only; no implementation is dispatched by this doc.
Each phase is a separate PR with its own demo.
Each holds the standing invariants.
Fog effects are bounded to visibility and ghost markers.
The retreat margin is unaffected.
A replay re-derives identically under its recorded map state.

### Phase 1 -- battle visibility core, headless

**Shipped** in [#1560](https://github.com/Lacaedemon/sparta/pull/1560) and
[#1594](https://github.com/Lacaedemon/sparta/pull/1594), substantially as
scoped below -- see "Implementation status" above for the one divergence
(no terrain explored/unexplored grid).

**Scope.**
A `Perception` module (proposed path `scripts/Perception.gd`) computing
per-team visible sets and maintaining the explored grid and the last-known
contact table on the AI cadence.
Per-unit `sight_range` with type-derived defaults.
The `sight` axis on terrain patches in `BattleMap.parse` and
`BattleMap.serialize`.
Sightline tests reuse the existing public `PathField.is_leg_blocked` with
`clearance` 0.0; no new `PathField` entry point is added.
`Battle.ROUT_MARGIN` remains fixed at `DETECTION_RANGE` (190 wu), unaffected by fog for the
reason given in "The rout margin is decoupled from fog of war" above (not because fog is
render-only overall, which by the time of implementation it no longer was).
This original scope proposed no AI consumption: the sim would run exactly as today and the
new state would be computed alongside it -- see "Implementation status" above for what
actually shipped.

**Parameters.**
`Battle.sight_scale` (default `0.25 * min(field.size.x, field.size.y)`),
`Unit.SIGHT_FOOT` 1.0, `Unit.SIGHT_MOUNTED` 1.4, `Unit.SIGHT_RANGED` 1.2,
`Unit.SIGHT_SCREEN_FACTOR` 0.5, `Unit.SIGHT_ROUTING_PENALTY` 0.6,
`Battle.contact_stale_ticks` 600, `Battle.fog_cell` 40 wu.

**Acceptance tests.**
A target inside range with a clear line is visible, and one behind the default
`hill` block patch is not.
A target across the `forest` screen patch is visible within the reduced range
and not beyond it.
A contact record is written on the tick of last sighting and not after.
A unit that dies while unobserved keeps its record.
A routing unit is removed by `Unit._escape()` at `Battle.ROUT_MARGIN` (190 wu)
beyond the field edge whether fog is enabled or disabled.
A fixed-seed battle produces a byte-identical replay with the module active,
proving no simulation feedback.
`BattleMap.parse(BattleMap.serialize(...))` round-trips the new key, and a map
with no `sight` key parses to the `kind`-derived defaults.

**Demo.**
Skip manifest -- there is nothing on screen to film.
The verification artifact is the state dump showing per-team visible sets
changing as units advance.

### Phase 2 -- fog rendering and player UX

**Shipped** in the same PRs, with the `FogOverlay` terrain render layer
following later in
[#1621](https://github.com/Lacaedemon/sparta/issues/1621)/#1623 (2026-09-22).
Ghost markers, the `Settings.fog_of_war`
toggle, targeting restricted to visible units, and the terrain
explored/unexplored overlay all match this phase's acceptance tests below --
see "Implementation status" above.

**Scope.**
The `FogOverlay` node, the three render layers, ghost markers for remembered
contacts with a staleness fade, and hiding non-visible enemy `Unit` nodes by
`CanvasItem.visible`.
Selection and order targeting restricted to what the player can see:
a right click on empty fog or on a ghost marker is a ground move order
(an attack order requires a live visible enemy target).
A `Settings` toggle to enable or disable fog,
defaulting to off so every existing demo, replay, and test renders exactly as before.

**Dependencies.**
Phase 1.

**Parameters.**
Unexplored fill alpha, explored dim alpha, ghost marker alpha, and the fade
curve over `contact_stale_ticks`, all caller-configurable with the values above
as defaults.

**Acceptance tests.**
A headless run and a rendered run of the same seed produce identical replays.
`SelectionManager` cannot right-click-target an unseen enemy.
The fog toggle restores today's rendering exactly.
`Battle.all_teams_control` disables fog, since a tester driving both armies
must see both.

**Demo.**
A real clip: the player's line advances across the field, an enemy unit
resolves out of the fog as it comes into sight, the player pulls back, and the
enemy leaves a fading ghost marker where it was last seen.

### Phase 3 -- the AI honors fog, the phase #588 tracks

**Shipped its team-wide half on 2026-09-22.** #588 was closed in error on
2026-09-02 and reopened on 2026-09-19 -- see "Implementation status" above for
the full history and what shipped.

**Scope.**
Build `CommanderView` as `docs/battle-ai-design.md` sketches it, route every
commander read through it, then swap the omniscient implementation for the
fogged one.
Team-wide fogged view first; commander-scoped narrowing plus report propagation
second.
**As shipped:** the team-wide view (`Battle._ai_perceptible_units`), with no
formal `CommanderView` type -- the caller's own array remains the interface,
same as the omniscient implementation it replaced.
Commander-scoped narrowing and report propagation are
[#1625](https://github.com/Lacaedemon/sparta/issues/1625).

**Dependencies.**
Phase 1; phase 2 only for the demo.

**Acceptance tests.**
This phase is the one #588 tracks,
so its acceptance criteria are that issue's:
an AI general cannot react to an unseen flanking force
until it enters some friendly unit's perception,
and reacts on the first decision tick after it does;
no AI code path reads unfogged state;
determinism on replay is preserved with fog active.
**Met, with one disclosed exception** --
`test/unit/test_battle_ai_fog.gd`,
including a fixed-seed replay-determinism check under fog
and fog-on/fog-off coverage for each independent per-unit path found during review
(across four rounds so far)
to bypass the command layer's own fog gate entirely --
`Unit._think()`'s and `Unit._support_tick`'s own not-yet-engaged targeting decisions, plus
far-tier attrition's own re-acquisition fallback, all closed the same way -- plus a gap in the
command layer's OWN candidate pool: `Battle._apply_order_cmd`'s DISTRIBUTED-attack branch
pre-sorted every live enemy by proximity to the clicked target with no perception filter at
all, so an ordered unit other than the one whose target was explicitly clicked could still be
handed a fresh, committed attack on an enemy its own side does not perceive; see
`Unit._enemy_is_perceived`'s own doc comment for the complete, current list rather than
re-enumerating it here.
**One known gap, outside this phase's own scope, not covered by "met" above:**
`OrderGuards.enemy_in_range` (backing `Order.Guard.ENEMY_IN_RANGE`)
calls `UnitTargeting.nearest_enemy_to` directly with no perception gate --
a queued order's wait condition can be satisfied by an enemy its own side has not perceived.
It decides an order-queue transition rather than a not-yet-engaged targeting commit,
tracked as [#1641](https://github.com/Lacaedemon/sparta/issues/1641).
Left deliberately ungated:
once a unit commits to an explicit attack order
(or `Unit._think()`'s own SWEEP_ROUTERS/ROLL_THE_LINE stances commit one through their own,
now-gated fresh-pick paths above),
`Unit._think()`'s own chase-an-explicit-target branch
keeps closing on that target's current live position
with no further perception re-check,
so a unit can keep chasing a target
that has since dropped out of its side's own current perception.
An `ORDER_CHASE` unit with no such prior commitment (target_enemy still null, a purely
auto-acquired quarry) does NOT share this exception -- that half of the same branch is
itself gated now.
This needs the same last-known-contact memory the perception layer does not yet have,
tracked as [#1626](https://github.com/Lacaedemon/sparta/issues/1626).
Add a grep-based regression test that the four AI scripts contain no direct group lookups,
and an interposition test that inserting the still-omniscient `CommanderView`
leaves a fixed-seed replay byte-identical.
**Met, adapted to the shipped shape**:
the regression test checks for no direct group lookup
AND no misuse of the `BattleRef` token
(there being no formal `CommanderView` type to interpose,
the "insert the still-omniscient implementation" half is instead the fog-off invariance test
in the same file,
proving `_ai_perceptible_units` reproduces the omniscient set exactly).
It does not catch a live Battle instance reached through some other untyped variable --
a known gap recorded in the test's own header,
since catching that reliably needs real static type analysis rather than a grep.

**Demo.**
A scripted flank march the AI does not react to until a screening unit sights
it, with the state dump showing the decision tick.

### Phase 4 -- campaign-map fog

**Not shipped.**
No province-level visibility exists in
`scripts/campaign/` as of 2026-09-19 (verified by grep).

**Scope.**
Province-level visibility on `CampaignState`: a province is visible when the
faction owns it or has an army adjacent to it, remembered once entered, and
unknown otherwise.
Remembered provinces show their last-known owner and army strength, not their
current ones.
`CampaignHUD` renders the three states.

**Dependencies.**
None on phases 1 to 3 -- the battle and campaign models share the vocabulary
and no code.
This phase is deliberately independent so it can be scheduled against
`docs/campaign-layer-design.md`'s own phases rather than behind the battle
work.

**Acceptance tests.**
A faction cannot read an unentered province's army strength.
A remembered province reports the strength it had when last observed.
A headless campaign turn sequence is deterministic with visibility active.

**Demo.**
Skip manifest if the campaign map has no clip harness at the time; otherwise a
short campaign-map clip showing a province resolving as an army moves adjacent.

### Phase 5 -- saga-scale knowledge

**Not shipped**; the saga layer itself still does not exist, as the scope
note below already says.

**Scope.**
Deferred by design.
The saga layer does not exist in code (`docs/campaign-layer-design.md` scopes
it as #126 and #428, and that design is itself unimplemented), so there is
nothing to fog.
When it lands, the question is what a dynasty remembers across interwar
periods -- a knowledge-decay model over a much longer clock than either of the
models above, and one that should be designed then rather than guessed now.

**Dependencies.**
A saga layer existing.

## Non-goals

- **Per-soldier sensing.**
  Fog is a command-level information model.
  Soldier melee resolution is unchanged and unfogged.
  That layer is `docs/individual-collision-design.md` and #547's territory.

- **Vision cones.**
  A unit sees a full disc in the first battle phase.
  Facing-limited vision is a natural later phase and changes no interface.

- **Elevation.**
  There is no heightfield in the sim, so there is nothing to read.

- **Weather, dust, and night.**
  Same reason.
  Each is a multiplier on `sight_scale` once the sim grows the state to drive it.

- **Stealth and ambush as unit abilities.**
  Hiding in woods as an active choice is a mechanic on top of this model, not part of it.

- **Multiplayer information security.**
  [#290](https://github.com/Lacaedemon/sparta/issues/290) is titled "add mutliplayer [sic] battles and campaigns" with the body "(multi-computer, not hotseat)".
  It names no network architecture and has no design yet.
  *If* it lands as lockstep -- every peer simulating the same battle from the same seed and the same inputs, which is the shape this game's replay recorder already implies -- then both players hold full state locally, fog is a rendering convention on each peer rather than a security boundary, and a modified client can see through it.
  A server-authoritative design would instead make fog a filter on what each peer is sent, which is a different and larger piece of work.
  Either way it is out of scope until #290 has a design.

## Open questions

- **Does the player see ghost markers for enemy contacts a subordinate saw?**
  Under team-wide visibility, yes automatically.
  Under commander-scoped narrowing (phase 3's second half) the player is the general and would see only reported contacts, which is more historical and considerably more confusing.
  Lean: team-wide for the player, commander-scoped for AI subordinates, and say so in the UI.

- **Should `sight_scale` really key off field size?**
  It couples two parameters a map author might want independent.
  The alternative is an absolute default in metres that every non-default map has to re-tune.
  Lean: keep the derivation and allow an absolute override.

- **What happens to an order issued against a ghost that turns out to be wrong?**
  A right click on a ghost marker falls through to a ground move to that location,
  because attack orders require a live visible target.
  An attack-at-last-known-position order may be considered in a future phase.

- **Does a routing unit still observe?**
  Modelled as a penalty (`SIGHT_ROUTING_PENALTY`) rather than blindness, on the reasoning that a fleeing man still has eyes.
  Untested; a phase-1 tuning question.

- **Is 0.25 of the field the right `sight_scale` fraction?**
  Purely empirical.
  It should be tuned against the phase-2 demo and settled before phase 3, since AI behaviour will be sensitive to it.

- **Should visibility model a unit's extent rather than its center?**
  Phase 1 treats a unit as a point for both the range and the line-of-sight test, so visibility is all-or-nothing.
  At a file pitch of 18 wu against a 300 wu sight radius that is visible in play: a line half out from behind the `hill` patch is entirely hidden, and one marginally outside range is entirely hidden while part of it stands inside.
  Lean: keep the point test through phase 2, and revisit extent or partial visibility only if the ghost-marker UI turns out to need a partial state anyway.

- **Does fog change combat balance?**
  It should not once a body is already in MELEE contact,
  since SOLDIER-level targeting there (who an already-fighting body engages)
  stays unfogged by design --
  see "Rendering must not feed back into the simulation" above.
  Missile fire at standoff is a different case, and NOT exempt:
  an idle ranged unit picking a new target that is not yet in melee contact --
  even one already well within its own missile_range --
  is gated on perception exactly like a chase decision is,
  for BOTH sides, not just the AI.
  So fog DOES change things below melee-contact range:
  a screening skirmisher line becomes far more valuable,
  cavalry's longer sight becomes a real advantage,
  and (since phase 3's team-wide swap)
  neither side's idle ranged units can loose a volley at,
  and neither side's AI-driven or Support-stance units can chase or fire on,
  a target their own side has not sighted --
  a player unit is held to the identical rule its AI-controlled counterpart is,
  a deliberate symmetric choice rather than a player-side exemption.
  That is intended, and worth measuring rather than assuming.

## Relationship to existing issues

- **#414** -- this doc is its design deliverable, and stays open tracking
  the remaining scope (phase 3's commander-scoped narrowing and report
  propagation, plus campaign and saga fog).
  The phases above were not filed as separate sub-issues; phases 1-2
  shipped directly under #414 via
  [#1560](https://github.com/Lacaedemon/sparta/pull/1560) and
  [#1594](https://github.com/Lacaedemon/sparta/pull/1594), and phase 3's
  team-wide half shipped 2026-09-22 (see "Implementation status" above).

- **[#588](https://github.com/Lacaedemon/sparta/issues/588)** -- battle-AI phase 5, blocked on this.
  Phase 3 above is the phase that finishes it; its team-wide half shipped
  2026-09-22, closing #588's own acceptance test (see "Implementation
  status" above), with commander-scoped narrowing tracked as
  [#1625](https://github.com/Lacaedemon/sparta/issues/1625).
  #588 was closed in error on 2026-09-02 and reopened on 2026-09-19, for the
  reason explained in "Implementation status" above.

- **#498 and `docs/battle-ai-design.md`** -- the consumer.
  Its perception interface sketch, its "AI honors fog of war" requirement, and its determinism rules are all inherited here unchanged.

- **#516 and `docs/orders-queue-design.md`** -- the actuation layer.
  Fog restricts which orders the player can express; it does not add order types.

- **#582 and `docs/campaign-layer-design.md`** -- phase 4 lands on top of whatever campaign substrate that design settles on.
  Province-level fog survives a hex substrate as cell-level fog.

- **#126 and #428** -- the saga layer, phase 5's prerequisite.

- **#891 and `docs/world-scale-rebase-plan.md`** -- the world-scale rebase.
  Authoring sight as a ratio of `sight_scale` rather than as an absolute world-unit figure means this design survives that rebase without re-tuning.

- **#290** -- lockstep multiplayer; see the non-goal above.
