# Design note: fog of war

Status: **design -- not yet implemented.**
This note is the design deliverable for
[#414](https://github.com/Lacaedemon/sparta/issues/414) (title: "add fog of
war"; body: "both in battles and in campaigns and sagas"), following the same
design-doc-first pattern as [`docs/battle-ai-design.md`](battle-ai-design.md)
(#498), [`docs/orders-queue-design.md`](orders-queue-design.md) (#516), and
[`docs/campaign-layer-design.md`](campaign-layer-design.md) (#582).

It is also a **blocker for battle-AI phase 5**
([#588](https://github.com/Lacaedemon/sparta/issues/588)), whose entire scope
is "swap the omniscient placeholder implementation of the perception interface
for the fogged view, when fog of war (#414, battle side) lands."
That doc states the ownership split in its own non-goals: "#414 owns visibility
rules, rendering, and player UX; this design only consumes the resulting view
through the perception interface."
This note is the producer side of that contract.

## Motivation

### Both armies currently see everything, and nothing in the code pretends otherwise

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

- Every `Unit` is a scene-tree `Node2D` that renders unconditionally; there is no per-team draw filter anywhere in `scripts/`.

- `scripts/SelectionManager.gd` is mouse control for team 0, or for every team under `Battle.all_teams_control` (the debug mode in `scripts/AllTeamsControl.gd`).
  Left click selects a friendly unit by its block or its raised flag, box-drag selects several, right click issues a move or an attack on the enemy unit clicked.
  Its `_unit_at` hit test resolves any unit's body or flag; nothing consults visibility, so an enemy unit anywhere on the field is right-clickable as an attack target.

- `scripts/CameraController.gd` is a free RTS camera: WASD and arrow-key pan, screen-edge pan, wheel zoom between `zoom_min` 0.45 and `zoom_max` 2.2, with `bounds` clamped to the battlefield rect Battle publishes.
  It is unconstrained within the field, which is the standard RTS arrangement and stays correct under fog.

- `scripts/HUD.gd` builds the on-screen UI in code: distance legend, menu button, selected-unit info panel, per-unit settings, and the unit card tray (`scripts/UnitCardTray.gd`).
  There is **no minimap** in the HUD today, so there is no second surface needing its own fog treatment in the first battle phase.

- `Battle.FIELD` is `Rect2(0, 0, 1600, 1200)`, which at `WorldScale.WU_PER_M` = 20.0 is an 80 m by 60 m field (`docs/world-scale-rebase-plan.md` states the same figure).
  The default spawn lines (`Battle.SPAWN_LINE_YS`) are y = 300 and y = 880, so the two armies start 580 wu = 29 m apart.
  This is the single most important constraint on the whole design; see "The scale problem" below.

- `Battle.ROUT_MARGIN` is `maxf(UnitRef.RANGED_RANGE, UnitRef.DETECTION_RANGE)` = 190 wu, and `field_with_margin = field.grow(ROUT_MARGIN)` (`scripts/Battle.gd:41-42`, recomputed for the live map at `:517`) is what every spawned unit receives as `Unit.retreat_bounds` (`:1074`); a router that leaves it is removed from play by `Unit._escape()`.
  The comment above it states an invariant this design has to honour: the margin is sized to "the game's maximum visual range", with `DETECTION_RANGE` standing in for "a fog-of-war vision range, which this game doesn't have yet", "so a fleeing unit stays a plausible target for as long as it's still visible, rather than vanishing early".
  A real sight range longer than 190 wu breaks that invariant, so the parameter section below has to say what happens to the margin.

### What the AI can see

- The chain-of-command AI is implemented through phase 4: `scripts/UnitLeader.gd`, `scripts/Subcommander.gd`, `scripts/General.gd`, `scripts/DoctrineRegistry.gd`, and `scripts/PlayerDelegation.gd`, dispatched from `Battle._run_enemy_ai()` and `Battle._run_player_delegated_ai()` on the `ai_period` cadence (default 60 ticks, once per second at `Replay.PHYSICS_TPS` 60).

- Every one of those files documents its perception source as the omniscient placeholder.
  `UnitLeader.gd`'s class doc says "perception is the omniscient placeholder the design doc describes -- every living unit is visible; phase 5 swaps this for a fogged view", and `General.gd`'s says it reads "the same omniscient perception every other command level reads".

- There is **no `CommanderView` class in the tree**.
  The interface `docs/battle-ai-design.md` sketches was never built as a type; the commanders take the units array their caller passes and read it directly.
  Introducing the type is therefore part of this work rather than a pre-existing seam to swap behind, and it is the largest single piece of unplanned work this design surfaces.

- `Unit.DETECTION_RANGE` is `9.5 * WorldScaleRef.WU_PER_M` (190 wu = 9.5 m), exposed per unit as the caller-configurable `Unit.detection_range`.
  It is a **target-acquisition** radius consumed by `UnitTargeting.nearest_enemy` and `UnitTargeting.nearest_routing_enemy`, not a sight radius: it governs which enemy a unit auto-engages, and at 9.5 m it is barely longer than `Unit.RANGED_RANGE` (`8.0 * WorldScaleRef.WU_PER_M` = 160 wu = 8 m).
  Sight is a separate quantity needing its own field; conflating the two would silently change combat.

### The terrain model

- `Battle.TERRAIN` is the default patch table, holding two patches: a `forest` patch at `Rect2(200, 380, 250, 200)` with `kind` `"slow"` and `speed` 0.6, and a `hill` patch at `Rect2(1150, 380, 250, 200)` with `kind` `"block"`.

- `scripts/BattleMap.gd` is the per-battle map parser and is strict: `kind` must be `"block"` or `"slow"`, a `"slow"` patch requires a numeric `speed`, and `type` is a free string (defaulting to `"hill"`) that keys `Battle.TERRAIN_COLOR` for rendering.
  `BattleMap.serialize` is its inverse and is what the replay header records, so playback reconstructs the same battlefield.

- `Battle._ready` registers each patch on `PathField.active`: a `"slow"` patch becomes `set_speed_rect`, anything else becomes `block_rect`.

- `scripts/PathField.gd` already carries the occlusion primitive this design needs.
  Its own class doc describes two layers of obstacle geometry, of which the first is exact: "The EXACT terrain rects decide what is actually blocked: every sightline test (the straight-line fast path, string-pulling visibility, `is_blocked`) runs against the drawn rects themselves, grown by the caller's own `clearance`".
  The segment test itself is the private `PathField._segment_blocked(from, to, clearance)`, and it already has a public wrapper: `PathField.is_leg_blocked(from, to, clearance := 0.0)` (`scripts/PathField.gd:184-185`) forwards to it verbatim, so a visibility caller passing `clearance` 0.0 needs no new entry point and no rename.
  Its only caller today is `Unit.funnel_lane_offset`'s same-team congestion gate (`scripts/Unit.gd:3508`), and its doc comment frames it as a cheap "is this unit actually about to detour" test, which is the same question a sightline asks.

- Terrain is **flat**: a `"block"` patch is an impassable rect, not a height.
  There is no heightfield and no elevation anywhere in the sim, so elevation-driven vision (seeing over a wall, being seen from a ridge) has nothing to read and is out of scope until one exists.

### Replay and determinism

- `scripts/Replay.gd` is a deterministic-simulation-plus-input-log recorder.
  Its own class doc: "We do NOT record the state of every unit each frame.
  Instead we record just two things: the RNG seed, and the player's orders, each stamped with the physics tick it took effect."

- AI decisions are re-derived on playback rather than recorded, on the same tick cadence, which `docs/battle-ai-design.md` states as the design's replay rule ("re-derive, don't record").

- `Replay.rng` is the one seeded stream, seeded once per battle and never reseeded elsewhere.

- `scripts/ReplaySnapshotCache.gd` plus `Battle.capture_snapshot`, `restore_snapshot`, and `seek_to_tick` let a playback rewind resume from a cached mid-battle state instead of resimulating from tick 0.
  This matters here because explored-terrain state is **cumulative**, so unlike instantaneous visibility it cannot be recomputed from the state at one tick; see "Determinism and replay" below.

### Campaign and saga

- `scripts/campaign/CampaignState.gd` is the M2 campaign: provinces with an owner and an integer army strength, per-pair war and peace stances, one move per army per turn, auto-resolved or battle-resolved attacks.
  Every province's owner and army are readable by everyone; there is no visibility concept.

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

1. **Fog scaled to the current field.** Pick a sight radius that is a fraction of the field (say 20 m on an 80 m map) and accept that it is not a physical claim about eyesight.
   Cheap, works today, and is the only option that produces visible fog before the world-scale rebase.

2. **Wait for the rebase.** `docs/world-scale-rebase-plan.md` (#891) rebases the sim to 1 wu = 1 m, which buys float precision but does not by itself enlarge the field.
   Waiting therefore does not actually solve this, and blocks #588 indefinitely.

3. **Make the sight radius a first-class map-scale parameter, defaulted to a fraction of the field.** Sight range is authored per unit type as a multiple of a per-battle `sight_scale` rather than as an absolute metre figure, with `sight_scale` defaulting to a fraction of the shorter field dimension.
   On today's 80 m by 60 m field that yields a short, visibly meaningful radius; on a future 800 m field the same data yields a proportionally longer one without re-authoring every unit.
   The doc is then honest about what the number is -- a **gameplay legibility parameter**, not a claim about eyesight -- which is exactly the distinction `docs/units-convention.md` draws for deliberately unit-tuned knobs.

This is worth stating before the mechanism because it decides the shape of the
parameter table: sight is authored as a ratio, and only the per-battle scale is
authored in metres.

## Proposed mechanism

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

1. **Range.** `u.position.distance_squared_to(t.position) <= u.sight_range * u.sight_range`, using squared distance for the same reason `UnitTargeting.nearest_routing_enemy` already does.

2. **Line of sight.** The segment from `u.position` to `t.position` is not blocked by an occluding terrain patch, evaluated against the exact drawn rects via the existing public `PathField.is_leg_blocked(from, to, 0.0)` (`scripts/PathField.gd:184-185`), and attenuated by any screening patches the segment crosses (below).

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
| `Battle.ROUT_MARGIN` | redefined to include the largest sight range: 420 wu on these defaults, up from 190 wu | Keeps the invariant its own comment states -- the margin a router must clear is never shorter than the longest sight range in play |

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

**The rout margin has to grow with sight range.**
`Battle.ROUT_MARGIN` is `maxf(RANGED_RANGE, DETECTION_RANGE)` = 190 wu, and its
comment (`scripts/Battle.gd:32-41`) sizes it to "the game's maximum visual
range" so that "a fleeing unit stays a plausible target for as long as it's
still visible".
The defaults above put foot sight at 300 wu and mounted sight at 420 wu, which
is 1.6x to 2.2x that margin, so leaving the margin alone would have a routing
enemy cross `Unit.retreat_bounds`, be removed by `Unit._escape()`, and visibly
pop out of existence while still well inside a friendly unit's sight radius.
The proposal is to redefine the margin as the maximum of every range that makes
a unit worth watching, sight included: `maxf(RANGED_RANGE, maxf(DETECTION_RANGE,
max_sight_range))`, where `max_sight_range` is `sight_scale` times the largest
sight multiplier (`SIGHT_MOUNTED` 1.4, so 420 wu on the default field).
That makes it a per-battle instance value rather than a `const`, since
`sight_scale` is itself per-battle; `field_with_margin` is then recomputed in
the one place it is already recomputed for a non-default map
(`scripts/Battle.gd:517`), so nothing else in the spawn path changes.
The visible costs are a wider margin strip drawn under the field
(`scripts/Battle.gd:674`) and a longer flight before escape, both of which are
the intended behaviour rather than a regression.
The alternative -- keep the margin at 190 wu and accept the pop-out -- is
rejected here rather than left unstated, because a unit vanishing inside your
own sight radius reads as a bug to the player and would undercut the
ghost-marker model in the same breath.
Phase 1 owns the change, since that is where sight ranges first exist.

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

Three layers, drawn above the battlefield and below the HUD.

1. **Unexplored.** Opaque fill in a darkened `Battle.FIELD_COLOR`, hiding ground art and terrain patches entirely.

2. **Explored but not currently visible.** The ground and terrain render normally, dimmed by a constant alpha; remembered enemy units render as ghost markers -- the unit's block outline and standard at the last-known position and facing, at reduced alpha, fading further as the contact passes `contact_stale_ticks`.

3. **Visible.** Normal rendering, exactly as today.

Proposed implementation: a `FogOverlay` `Node2D` (proposed path
`scripts/FogOverlay.gd`) at a z-index above the battlefield, drawing a coarse
visibility grid.
Proposed `Battle.fog_cell`, default `2.0 * WorldScaleRef.WU_PER_M` = 40 wu,
giving a 40 by 30 cell grid on the default field -- small enough to be cheap,
coarse enough that the overlay needs smoothing, which a bilinear-filtered
`ImageTexture` supplies for free.
Enemy unit nodes are hidden by setting `CanvasItem.visible`, never by removing
them from the `units` group; see the determinism section for why that
distinction is load-bearing.

Player-facing numbers stay metric per `docs/units-convention.md`: if fog UI
ever displays a distance (a scout report, a contact age in seconds), it renders
through `DistanceLegend`'s helpers, never as a raw world-unit figure.

## How the AI consumes perception without cheating

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

- **Own command.** Always fully known, fog or no fog.
  This is `own_units()`, and it is exempt by the requirement above.

- **Enemy.** Only what the commander's scope perceives, plus remembered contacts through `last_known`.

- **Reports.** A subordinate's sighting reaches its superior through `reports()`, which is how a general learns of a flanking force it cannot itself see.
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
(`BattleMap.serialize`'s shape)" (`scripts/Replay.gd:143`), so once phase 1
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

- **Recomputing from tick 0 is correct but not free.** A playback that starts at tick 0 and runs forward accumulates them correctly with no extra machinery.

- **A snapshot rewind is where this breaks.** `Battle.capture_snapshot` and `restore_snapshot` (`scripts/ReplaySnapshotCache.gd`) resume from a cached mid-battle moment, and a resumed state with an empty explored grid would show a player a fog that has forgotten ground the battle already covered.
  So the explored grid and the contact table must be captured in the snapshot alongside the rest of the derived state.
  The explored grid at the proposed 40 by 30 cells is one bit per cell, so the cost is negligible; the contact table is bounded by the unit count.

### Rendering must not feed back into the simulation

This is the sharpest trap in the design.
`UnitTargeting.nearest_enemy` and `UnitTargeting.nearest_routing_enemy` iterate
the `units` and `routers` groups, and `Battle` iterates `units` in several
places.
If fog were implemented by removing hidden units from those groups, **combat
would change** -- a unit would stop auto-acquiring an enemy the *player* cannot
see, which is both wrong and a silent desync between a recording and its
playback if the two ever differed in render state.

So the rule is explicit: fog sets `CanvasItem.visible` and nothing else.
Group membership, `_physics_process`, targeting, and collision are all
untouched.
A headless run with no rendering at all and a rendered run must produce
byte-identical replays, and a test asserting that is the cheapest guard
available.

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
Each phase is a separate PR with its own demo, and each holds the two standing
invariants: fog never touches simulation state, and a replay re-derives
identically.

### Phase 1 -- battle visibility core, headless

**Scope.**
A `Perception` module (proposed path `scripts/Perception.gd`) computing
per-team visible sets and maintaining the explored grid and the last-known
contact table on the AI cadence.
Per-unit `sight_range` with type-derived defaults.
The `sight` axis on terrain patches in `BattleMap.parse` and
`BattleMap.serialize`.
Sightline tests reuse the existing public `PathField.is_leg_blocked` with
`clearance` 0.0; no new `PathField` entry point is added.
`Battle.ROUT_MARGIN` widened to the largest sight range, per "The rout margin
has to grow with sight range" above.
No rendering and no AI consumption: the sim runs exactly as today and the new
state is computed alongside it.

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
A routing unit spawned on the default map is still in play at 300 wu beyond
the field edge and removed by `Unit._escape()` only past the widened margin, so
the distance it must clear is never shorter than the longest sight range in the
battle.
A fixed-seed battle produces a byte-identical replay with the module active,
proving no simulation feedback.
`BattleMap.parse(BattleMap.serialize(...))` round-trips the new key, and a map
with no `sight` key parses to the `kind`-derived defaults.

**Demo.**
Skip manifest -- there is nothing on screen to film.
The verification artifact is the state dump showing per-team visible sets
changing as units advance.

### Phase 2 -- fog rendering and player UX

**Scope.**
The `FogOverlay` node, the three render layers, ghost markers for remembered
contacts with a staleness fade, and hiding non-visible enemy `Unit` nodes by
`CanvasItem.visible`.
Selection and order targeting restricted to what the player can see or
remember: a right click on empty fog is a move order, and a right click on a
ghost marker is an attack on the last-known position, which may find nothing
there.
A `Settings` toggle to disable fog, for demos and debugging, defaulting to on.

**Dependencies.** Phase 1.

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

### Phase 3 -- the AI honors fog, closing #588

**Scope.**
Build `CommanderView` as `docs/battle-ai-design.md` sketches it, route every
commander read through it, then swap the omniscient implementation for the
fogged one.
Team-wide fogged view first; commander-scoped narrowing plus report propagation
second.

**Dependencies.** Phase 1; phase 2 only for the demo.

**Acceptance tests.**
This phase closes #588, so its acceptance criteria are that issue's: an AI
general cannot react to an unseen flanking force until it enters some friendly
unit's perception, and reacts on the first decision tick after it does; no AI
code path reads unfogged state; determinism on replay is preserved with fog
active.
Add a grep-based regression test that the four AI scripts contain no direct
group lookups, and an interposition test that inserting the still-omniscient
`CommanderView` leaves a fixed-seed replay byte-identical.

**Demo.**
A scripted flank march the AI does not react to until a screening unit sights
it, with the state dump showing the decision tick.

### Phase 4 -- campaign-map fog

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

**Scope.**
Deferred by design.
The saga layer does not exist in code (`docs/campaign-layer-design.md` scopes
it as #126 and #428, and that design is itself unimplemented), so there is
nothing to fog.
When it lands, the question is what a dynasty remembers across interwar
periods -- a knowledge-decay model over a much longer clock than either of the
models above, and one that should be designed then rather than guessed now.

**Dependencies.** A saga layer existing.

## Non-goals

- **Per-soldier sensing.** Fog is a command-level information model.
  Soldier melee resolution is unchanged and unfogged; that layer is `docs/individual-collision-design.md` and #547's territory.

- **Vision cones.** A unit sees a full disc in the first battle phase.
  Facing-limited vision is a natural later phase and changes no interface.

- **Elevation.** There is no heightfield in the sim, so there is nothing to read.

- **Weather, dust, and night.** Same reason; each is a multiplier on `sight_scale` once the sim grows the state to drive it.

- **Stealth and ambush as unit abilities.** Hiding in woods as an active choice is a mechanic on top of this model, not part of it.

- **Multiplayer information security.** [#290](https://github.com/Lacaedemon/sparta/issues/290) is titled "add mutliplayer battles and campaigns" with the body "(multi-computer, not hotseat)"; it names no network architecture and has no design yet.
  *If* it lands as lockstep -- every peer simulating the same battle from the same seed and the same inputs, which is the shape this game's replay recorder already implies -- then both players hold full state locally, fog is a rendering convention on each peer rather than a security boundary, and a modified client can see through it.
  A server-authoritative design would instead make fog a filter on what each peer is sent, which is a different and larger piece of work.
  Either way it is out of scope until #290 has a design.

## Open questions

- **Does the player see ghost markers for enemy contacts a subordinate saw?** Under team-wide visibility, yes automatically.
  Under commander-scoped narrowing (phase 3's second half) the player is the general and would see only reported contacts, which is more historical and considerably more confusing.
  Lean: team-wide for the player, commander-scoped for AI subordinates, and say so in the UI.

- **Should `sight_scale` really key off field size?** It couples two parameters a map author might want independent.
  The alternative is an absolute default in metres that every non-default map has to re-tune.
  Lean: keep the derivation and allow an absolute override.

- **What happens to an order issued against a ghost that turns out to be wrong?** An attack order on a last-known position the enemy has left becomes a move to that position.
  That is the historically right answer and may read as a bug to a player.
  Needs a UI affordance; deferred to phase 2.

- **Does a routing unit still observe?** Modelled as a penalty (`SIGHT_ROUTING_PENALTY`) rather than blindness, on the reasoning that a fleeing man still has eyes.
  Untested; a phase-1 tuning question.

- **Is 0.25 of the field the right `sight_scale` fraction?** Purely empirical.
  It should be tuned against the phase-2 demo and settled before phase 3, since AI behaviour will be sensitive to it.

- **Does fog change combat balance?** It should not, since targeting stays unfogged, but a screening skirmisher line becomes far more valuable and cavalry's longer sight becomes a real advantage.
  That is intended, and worth measuring rather than assuming.

## Relationship to existing issues

- **#414** -- this doc is its design deliverable; the phases above should be filed as sub-issues.

- **[#588](https://github.com/Lacaedemon/sparta/issues/588)** -- battle-AI phase 5, blocked on this.
  Phase 3 above closes it.

- **#498 and `docs/battle-ai-design.md`** -- the consumer.
  Its perception interface sketch, its "AI honors fog of war" requirement, and its determinism rules are all inherited here unchanged.

- **#516 and `docs/orders-queue-design.md`** -- the actuation layer.
  Fog restricts which orders the player can express; it does not add order types.

- **#582 and `docs/campaign-layer-design.md`** -- phase 4 lands on top of whatever campaign substrate that design settles on; province-level fog survives a hex substrate as cell-level fog.

- **#126 and #428** -- the saga layer, phase 5's prerequisite.

- **#891 and `docs/world-scale-rebase-plan.md`** -- the world-scale rebase.
  Authoring sight as a ratio of `sight_scale` rather than as an absolute world-unit figure means this design survives that rebase without re-tuning.

- **#290** -- lockstep multiplayer; see the non-goal above.
