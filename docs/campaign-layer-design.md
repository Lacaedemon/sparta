# Design note: unified campaign layer

Status: **design — not yet implemented.** This note unifies the
campaign-cluster epics —
[#146](https://github.com/Lacaedemon/sparta/issues/146) (pausable real-time),
[#147](https://github.com/Lacaedemon/sparta/issues/147) (hex-grid map),
[#165](https://github.com/Lacaedemon/sparta/issues/165) (real geography),
[#482](https://github.com/Lacaedemon/sparta/issues/482) (supply lines),
[#483](https://github.com/Lacaedemon/sparta/issues/483) (foraging),
[#126](https://github.com/Lacaedemon/sparta/issues/126) (saga layer),
[#428](https://github.com/Lacaedemon/sparta/issues/428) (founding cities),
and the campaign-relevant parts of
[#427](https://github.com/Lacaedemon/sparta/issues/427) (period factions) —
into one coherent design, following the same design-doc-first pattern as
`docs/orders-queue-design.md` (#516) and
`docs/large-scale-simulation-design.md` (#550). Tracked by umbrella issue
[#582](https://github.com/Lacaedemon/sparta/issues/582), which links the
cluster issues as sub-issues.

Unlike those two docs, **no phase issues are filed yet**: each phase below
says "issue to be filed on acceptance," so the owner reviews the design
before the tracker grows a phase tree around it.

## Motivation

The project's stated vision (`PLAN.md`, `website/index.qmd`) is a game fusing
**dynastic grand strategy** with **real-time tactical battles**. The battle
half has had sustained design attention — collision, per-soldier
simulation, orders, loadouts, LOD. The campaign half is still the thin
M2/M3 vertical slice: a turn-based, polygon-province map with integer
armies, built to prove the campaign→battle→campaign round trip and then left
alone.

The open campaign issues each pull on a different part of that slice:

- #146 replaces the turn structure (turn-based → pausable real-time).
- #147 replaces the map substrate (provinces → hexes under provinces).
- #165 replaces the map *content* (invented polygons → real geography).
- #482/#483 add logistics (supply lines, foraging) that need both a finer
  map substrate and a continuous clock to mean anything.
- #126/#428 add a saga layer above campaigns, with interwar periods and
  city founding.
- #427 adds per-period faction data (rosters, structures, buildings) that
  campaigns and sagas both consume.
- #504 shows the campaign↔battle interface is underspecified even for the
  data it already passes.

Implemented independently, these would collide — a hex map built before the
time model is chosen bakes in per-turn movement costs; supply lines built on
the current province graph would have to be rebuilt on hexes; a saga layer
above an integer-army campaign carries nothing worth carrying. This doc
fixes the positions once so the phases build toward the same game.

## Current state

What exists today, exactly. Every symbol below is in the code on `main`.

### Scenes and scripts

- `scenes/MainMenu.tscn` (main scene) → `scenes/Campaign.tscn` (campaign) or
  `scenes/Battle.tscn` (standalone tactical battle).
- `scripts/campaign/CampaignState.gd` — the campaign rules, a pure
  `RefCounted` with no scene dependencies, unit-tested headlessly in
  `test/unit/test_campaign_state.gd`. Holds provinces (owner + integer
  `army` strength), a directed adjacency graph, per-pair war/peace stances
  with truces (`DEFAULT_TRUCE_TURNS := 3`), per-faction rulers
  (`{name, trait}`, traits `aggressive`/`defensive`/`normal`), deterministic
  AI diplomacy (`run_ai_diplomacy`), and dice auto-resolve for contested
  attacks (`DEFENDER_BONUS := 1.2`, rolls in `ROLL_MIN 0.75`–`ROLL_MAX 1.25`,
  `CASUALTY_SEVERITY := 0.6`).
- `scripts/campaign/CampaignMap.gd` — `Node2D` view/controller: renders the
  province polygons, turns clicks into `move_or_attack` calls, runs the
  greedy enemy AI (`_run_enemy_ai`), owns the tactical-battle hand-off.
- `scripts/campaign/CampaignLoader.gd` — validates and loads campaign maps
  from JSON (`load_map`/`parse_map`).
- `scripts/campaign/Campaigns.gd` — the campaign registry (`LIST`:
  Gallic War, The Four Kingdoms; `selected_path` set by the menu).
- `scripts/campaign/CampaignBattle.gd` — a static holder that ferries data
  across the one-way `change_scene_to_file` swap in both directions.
- `scripts/campaign/CampaignHUD.gd` — turn banner, standings, diplomacy
  panel, victory overlay.
- `data/campaigns/*.json` — data-driven maps: factions (name, color),
  rulers, provinces (id, name, owner, army, adjacency, polygon, label),
  optional starting `peace` pairs with truce lengths.

### The time model today

Strictly turn-based. `CampaignState.end_turn()` rotates `current_faction`,
`turn` increments when play wraps to faction 0, and a per-turn `_acted` set
limits each province's army to one move per turn. The human is always
faction 0 (`CampaignMap.PLAYER_FACTION := 0`); ending the turn runs every AI
faction to completion synchronously, then hands play back.

### The campaign→battle→campaign loop today

**Campaign → battle** (`CampaignMap._capture_clash`): when the player attacks
a defended enemy province (and "quick resolve" is off), the campaign stores
into `CampaignBattle`:

- `pending` — `{from, to, attacker_strength, defender_strength,
  attacker_name, defender_name, attacker_color, defender_color, to_name}`,
- `snapshot` — `CampaignState.snapshot()` (owners, armies, acted flags,
  diplomacy, turn), because the scene swap destroys the state object,
- `active = true`,

then swaps to `scenes/Battle.tscn`. `Battle._ready()` reads `pending` and
deploys `CampaignBattle.units_for(strength)` units per side —
`clampi(strength, 1, MAX_UNITS)` with `MAX_UNITS := 12` — cycling the
default five-type composition (spearmen / infantry / archers / cavalry /
cavalry) in `_spawn_line`.

**Battle → campaign** (`Battle._report_campaign_result`): on battle end the
winner's surviving unit count is scaled back to campaign strength
(`CampaignBattle.survivors_strength`, proportional to what was spawned) and
stored as `result = {attacker_won, survivors}`. Back in the campaign,
`CampaignMap._resume_from_battle` restores the snapshot and
`CampaignState.resolve_attack` applies the outcome through the same
`_settle` transition the dice path uses, so a fought battle and an
auto-resolve converge on the same state shape.

**What the loop does *not* pass.** Nothing else. Going in: no unit
composition (strength is one integer; the battle invents the army from the
default loadout), no terrain (the battlefield is `Battle.FIELD` with the
hardcoded `Battle.TERRAIN` patches regardless of where on the map the fight
happens), no weather or season, no commander. Coming out: no per-unit
casualties, no morale or experience carryover (`Unit.morale` and
`Unit.training` die with the scene), no distinction between troops killed,
routed, or captured — one integer, `survivors`.

**The #504 gap.** `_report_campaign_result` counts survivors with
`_team_units(...)`, which reads only the `"units"` group — a unit still
**routing** at battle end (moved to the `"routers"` group) is not counted,
even though `_check_victory` deliberately keeps that team *in play* via
`_team_in_play` (which unions `"units"` and `"routers"`). The two ends of
the same battle disagree about whether a fugitive exists. This is the
concrete example of why the interface needs a spec, not just plumbing.

### Determinism today

Battles are deterministic and replayable: a seeded RNG (`Replay.rng`,
`Replay.forced_seed`), orders applied on the fixed physics tick
(`Replay.PHYSICS_TPS := 60`), a seed-plus-orders log (`REPLAY.md`), and a
machine-readable state transcript for verification. The campaign has none
of this: `CampaignMap._build_state` constructs `CampaignState.new(_map)`
without a seed, so the auto-resolve dice call `_rng.randomize()` — two runs
of the same campaign session cannot be reproduced. (The seeded path exists —
`CampaignState._init(map, rng_seed)` — but only tests use it.)

### The dynastic germ

#124 (characters & dynasties) closed with the thin slice that exists today:
one ruler per faction, a `{name, trait}` pair surfaced in the turn banner
and steering AI diplomacy thresholds. There is no lifecycle — rulers don't
age, die, or have heirs. The saga layer (#126) is where that grows; see
"Saga structure" below.

## Design

Positions follow. Each one names its alternatives and why they lose.

### Map representation: a hex substrate under a province overlay

**Position: two layers.** A **hex grid** is the movement, occupancy, and
logistics substrate; **provinces** persist as the political overlay — a
province is a named, contiguous *set of hexes* with an owner, and everything
political (ownership, victory, diplomacy, recruitment sources) stays
province-level. This is #147's own framing — "provinces are made up of
hexes (invisibly)" — adopted as the load-bearing structure, not just a
rendering trick.

Per hex:

- **terrain type** (plains, forest, hills, mountains, marsh, river edge,
  coast) — drives movement cost, forage yield, and the battle hand-off
  (below);
- **forage stock** (see logistics) and any built structure (depot, fort —
  #427/#428);
- **province id** — membership in the political overlay.

Armies live *on* hexes, not *in* provinces: an army occupies a cluster of
hexes sized by its strength (#147: "armies occupy multiple hexes depending
on size") and moves hex-to-hex at the pace of its slowest contingent (#147's
speed ladder — cavalry > camels > elephants > foot > artillery — becomes a
per-unit-type campaign speed the army mins over). Two armies meet on the
map, not in a province-attack abstraction — which is what makes
interception, blocking a pass, and cutting a supply line *positional* facts
the player can see, instead of graph edges.

**How real geography (#165) feeds it.** A campaign map is authored by
rasterizing a real geographic source (coastlines, rivers, relief, forest
cover) onto the hex grid at map-authoring time — an offline data pipeline,
not a runtime dependency. Province boundaries trace hex sets (historical
regions: Narbonensis, Belgica, ...). The output stays a validated JSON file
under `data/campaigns/` in the existing `CampaignLoader` pattern (schema
versioned; the loader's lint-and-reject validation approach carries over).
Hand-authored maps remain possible — the four-kingdoms fantasy map just
rasterizes an invented geography.

**Against the alternatives.**

- *Keep the pure region graph* (today's model): too coarse for everything
  downstream. Supply lines, forage radii, army frontage, interception, and
  "the army is two days from the city" all need positions finer than
  "in province 3." The region graph also can't express #147 at all.
- *Continuous 2D positions* (the battle's model): matches the battle layer
  aesthetically, but gives up the discrete bookkeeping that logistics wants
  (per-hex forage stocks, supply paths as hex chains), makes deterministic
  campaign movement harder (float accumulation vs. integer hex steps), and
  buys nothing the game needs at campaign zoom — armies are day-scale
  objects, not colliding bodies. It also contradicts the owner's stated
  direction in #147.
- *Hexes only, no provinces*: loses the political layer cheaply kept —
  diplomacy, victory conditions, recruitment, and the existing campaign
  rules all speak province. The overlay preserves them while the substrate
  changes underneath.

**Migration note.** `CampaignState`'s political rules (diplomacy, truces,
rulers, victory) survive; its *movement* rules (`can_move`, `_acted`,
adjacency) are replaced by hex movement under the new time model. The
polygon renderer in `CampaignMap._draw` becomes a hex-cluster renderer with
province borders drawn along hex-set boundaries.

### Time model: pausable real-time on a fixed campaign tick

**Position: a fixed-tick, pausable, speed-scalable campaign clock** (#146),
replacing turns entirely. Concretely:

- Campaign time advances in **fixed discrete ticks** (a tick = a fixed slice
  of world time, e.g. one hour; exact ratio tuned in phase 1). Fixed ticks,
  not frame-delta time, for the same reason battles run on
  `Replay.PHYSICS_TPS`: determinism and replays (see below). Rendering
  interpolates between ticks; the sim never reads the wall clock.
- **Pause** gates the tick counter, nothing else. While paused the player
  can inspect anything and **issue orders**, which queue and execute when
  time resumes — the pause-to-plan loop of the genre. Speed controls
  (pause / 1x / 4x / ...) just scale ticks per real second.
- Orders go through a **campaign command queue** applied on tick boundaries
  — the same apply-once discipline the battle layer adopted
  (`docs/orders-queue-design.md`), which both kills the double-apply bug
  class before it exists here and gives the replay log its entries for
  free. Armies carry small order queues (move along path, then fortify) —
  the orders-queue model at campaign granularity, matching how
  `docs/large-scale-simulation-design.md` already applies it to far-tier
  formations unchanged.
- AI factions decide on a **periodic cadence** (every N ticks, staggered),
  replacing the synchronous whole-faction turn — the campaign analog of the
  battle's existing enemy-AI period. `end_turn()`, `_acted`, and the `turn`
  counter retire. Turn-flavored rules re-express in time units: a truce of
  "3 turns" becomes a truce of N days.

**What happens to campaign time during a battle: it freezes.** When a
tactical battle launches, the campaign clock stops for the whole world and
resumes when the battle resolves; the battle then charges a **fixed lump of
campaign time** (e.g. the remainder of the day) to both participating
armies on return. Rationale:

- A tactical battle compresses hours of world time into minutes of play.
  Letting the campaign clock run during it means the rest of the world
  moves at a wildly different exchange rate than the battlefield — and in
  single-player there is no one else to serve by keeping the world hot.
- Freezing keeps the battle a **single atomic event** on the campaign
  timeline, which the determinism section needs: the campaign log records
  "battle at tick T, seed S, result R" with nothing interleaved.
- The alternative — world keeps running, battle outcome applied
  retroactively — creates simultaneity paradoxes (a relief army arrives at
  a battle that is still being fought in another scene) for no single-player
  benefit. Revisit only if multiplayer ever becomes a goal (it is a
  non-goal, below).

AI-vs-AI clashes never open the battle scene (unchanged from today — PLAN.md
notes AI battles always auto-resolve); under real-time they resolve at the
tick the armies meet, through the auto-resolve path. Player battles keep the
"quick resolve" opt-out.

### Armies become composed objects

Everything below — logistics, the battle interface, hex occupancy — needs
armies to be more than an integer. **Position:** an army is a first-class
record: an ordered list of **regiments** (each with a unit type from the
faction roster, a soldier count, `morale`, and `training` — the same fields
`Unit` already carries in battle), a commander slot (a ruler or a general;
thin until the dynasty phase), and a supply state (carried rations, see
logistics). Small composable parts over a monolith, per PLAN.md pillar 3.

This replaces the per-province `army: int` and is the single biggest
migration cost in the design — `CampaignState`, the loader schema, the HUD,
and the auto-resolve all touch it. It is sequenced early (phase 2) because
the battle interface is the first consumer: the hand-off stops inventing
armies from the default loadout and starts deploying the real one.

Auto-resolve re-expresses over composition: instead of one dice roll over
two integers, a short deterministic aggregate fight over regiment lists (in
the spirit of the far-tier statistical rules in
`docs/large-scale-simulation-design.md` — coarse attrition over aggregate
records, no per-soldier state). Exact rule is phase-2 implementation detail;
the design constraint is it consumes and produces the same regiment records
the tactical battle does, so the two resolution paths stay interchangeable.

### Logistics: supply lines (#482) and foraging (#483)

Historical armies were fed or they dissolved; ancient-world provisioning is
the best-documented constraint on where armies could go and when. The
design grounds both mechanics in that practice, and — per PLAN.md pillar 2
(bottom-up emergence) — builds them from **local rules per army and per
hex**, not a global supply formula.

**The local rules:**

- **Consumption.** Each army consumes rations per soldier per day (pack
  animals count). This is one number per army per tick — cheap.
- **Carriage.** An army carries a bounded number of days of supply (its
  baggage train; historically single-digit days to a few weeks depending on
  train size — the exact cap is a per-army stat, extended by wagons at the
  cost of the artillery-tier speed penalty from #147's ladder).
- **Foraging** (#483). Each hex holds a **forage stock** that armies draw
  down, scaled by terrain type and **season** (rich in farmland at harvest,
  poor in mountains and winter). Foraging is per-hex and depleting:
  a large army strips its surroundings in days and must move or starve —
  which is why big historical armies kept moving, and why sitting a siege
  needed a supply line. Stocks regenerate seasonally. Dispersing to forage
  (a wider forage radius = more hexes drawn) is an army stance with a
  military cost: a foraging army moves slower and fights the first ticks of
  an interception at a readiness penalty.
- **Supply lines** (#482). A supply line is a **traced hex path** from an
  army to a friendly source (a supplied city, a depot, a coastal or river
  hex — waterways carry far more, matching the ancient cost advantage of
  water transport). The line delivers a flow of rations (and, per #482,
  **reinforcements** — replacement soldiers walk the same roads food does).
  A line is *cut* when an enemy army occupies (or a hostile zone of control
  covers) a hex on the path — no separate "raiding" mechanic needed at
  first: raiding **emerges** from parking a cavalry army on the enemy's
  road, exactly the bottom-up outcome the pillar asks for.
- **Depots** (#427's encampment/siegeworks structures). A built structure on
  a hex that stores supply and acts as a line source, extending reach in
  poor country — the magazine system. Forts (#428's long-term maintained
  forts) share the structure mechanism.
- **Attrition.** When consumption exceeds carried + foraged + delivered,
  the army starves: soldiers desert or die at a rate that ramps with the
  shortfall, morale drops (feeding the same `morale` the battle reads —
  a starved army arrives at battle brittle). No hit points, no abstract
  "supply %": just the ledger of the three sources against consumption.

**What this buys strategically:** seasons shape campaigning (winter
quarters emerge from forage math, not a "winter" rule); mass matters
(a bigger army is stronger in battle and weaker on the march); geography
matters (river valleys are highways, mountains are walls); and cutting the
enemy's line is a real alternative to fighting him — the classic
maneuver-warfare loop, produced by four local rules and a path trace.

**Scope discipline.** Phase 3 ships **food only**. #482 says "a variety of
resources"; the design keeps the ledger generic (a resource id on the flow)
so pay, fodder, and materiel can slot in later, but only food is designed
now — it was the binding constraint historically and one resource exercises
every mechanism.

### The campaign→battle interface, specified

The contract, per direction. The ferry mechanism (`CampaignBattle`'s static
holder across the scene swap) works and stays; the payload grows and gets
versioned.

**Campaign → battle:**

- **Army composition, both sides** — the regiment lists (type, count,
  morale, training), replacing `units_for`'s integer-to-default-loadout
  invention. The battle spawns what the campaign actually has, including
  understrength and shaken regiments.
- **Terrain** — generated from the battlefield hex and its neighbors: the
  hex's terrain type seeds the battle's terrain patches (today's hardcoded
  `Battle.TERRAIN` array becomes an input), so a fight in a forest hex is a
  forest fight. Deterministic generation from the campaign seed + hex id.
- **Context** — attacker/defender roles, faction names/colors (already
  passed today), season/weather (phase 3+, once seasons exist), and the
  supply-state morale modifiers already applied on the campaign side.

**Battle → campaign:**

- **Per-regiment outcomes**, not one integer: for each regiment that
  entered, its surviving soldier count, end-of-battle `morale`, and
  `training` gain (veterancy accrues from surviving real fights — the
  carryover that makes a saga's veteran colonies (#428) mean something).
- **Survivors include still-routing units** — the #504 position: a unit in
  the `"routers"` group at battle end **counts as surviving** for the losing
  side's escape accounting (fugitives regroup after the battle; historically
  most of a broken army survived the field unless pursued). Concretely:
  survivor counting unions `"units"` + `"routers"` exactly like
  `_team_in_play` already does — the victory check and the result report
  stop disagreeing. A routed-out regiment returns at reduced strength and
  rock-bottom morale rather than vanishing.
- **Casualty split** — dead vs. scattered-but-recovering, so the campaign
  can return part of the scattered fraction over the following days
  (stragglers rejoining), which is also where a future pursuit mechanic
  would bite.

The loop keeps its current shape otherwise: snapshot out, resolve on
return, one battle at a time, campaign clock frozen throughout (time model
above).

### Saga structure (#126): campaigns, interwar periods, and the dynasty

A **saga** is a sequence of campaigns (each campaign = one war) separated by
**interwar periods**, carrying persistent state forward so the wars form an
arc. Position on the split:

- **A campaign** owns: the war's map situation (hex/army state), diplomacy
  of the belligerents, and its own victory condition (which becomes the
  saga's transition trigger).
- **The saga** owns everything that outlives a war: the dynasty (below),
  the roster of veteran regiments (with their accrued `training`), founded
  cities and maintained forts, faction relationships that seed the next
  war's starting stances, and the period/faction data pack in play (#427).
- **An interwar period** is not a full simulation layer — it is a
  **decision screen sequence over saga state**: muster out veterans (→ found
  a colony, #428), maintain or abandon forts, invest in cities, succession
  events, and the inciting setup of the next campaign. Deliberately shallow
  in this design: the interwar is a menu over durable state, not a second
  map. If it earns depth later, it can grow into one without breaking the
  layering (battle → campaign → saga was the intended stack from the start —
  #126's own framing).

**Founding cities (#428).** Two mechanisms, both from the historical
playbook: **veteran colonies** (an interwar action spending mustered-out
veteran regiments to found a town on a chosen hex — the Roman colonia;
incentivized migration is a growth modifier on the new town, fed by
investment) and **forts that take root** (a fort maintained across N
campaigns upgrades to a town — the *canabae* path). Founded settlements
join the map's economic layer: forage-rich surroundings develop, and a town
is a supply-line source — tying #428 directly into the logistics loop
rather than being cosmetic.

**The dynasty — named honestly, sketched, scheduled last.** The vision says
*dynastic* grand strategy; today's implementation is one immortal
`{name, trait}` ruler per faction. The sketch: rulers become **characters**
with age, a small trait set (extending the existing
aggressive/defensive/normal AI hooks), an heir list, and mortality that
ticks on saga time; succession happens in interwar periods (or
mid-campaign, as a crisis event); player dynastic continuity is the saga's
thread — you play the house, not the man. Marriages, factions-within-
factions, and character-driven diplomacy are explicitly **out** of this
design's scope. Dynasty is phase 5, after sagas exist to give characters a
timeline to live on. Scoping it last is deliberate: it is the
highest-variance system in the genre, and everything before it (map, time,
logistics, sagas) is useful without it, while a dynasty layer without a
saga timeline is flavor text.

### Faction and period data (#427)

Campaign content becomes **data packs**, extending the existing
`data/campaigns/` + `CampaignLoader` pattern rather than inventing a new
one: a **period** (e.g. late Republic) defines its factions; each faction
carries its **unit roster** (the types its armies and cities can raise —
feeding army composition and the battle's spawn tables), its **campaign
structures** (encampments, siegeworks, depots, forts), and its **saga
buildings** (town/city structures, for #428's settlements). A campaign JSON
references a period pack; a saga fixes one for its whole arc. Validation
stays in the loader (lint-and-reject, like `parse_map` today). Rosters
reference the battle layer's `LoadoutRegistry` types so a faction's spear
line is the same object in both layers.

### Determinism: the campaign gets the battle's replay discipline

The same two invariants that govern the orders-queue and LOD designs apply
unchanged: every campaign-tick evolution is a **pure function of serialized
state**, and the state is **transcript-legible**. Concretely:

- **A campaign seed.** The campaign RNG is seeded at campaign start (the
  seeded path `CampaignState._init(map, rng_seed)` already exists for tests;
  it becomes the only path) and every stochastic draw — auto-resolve,
  forage variance if any, event rolls — pulls from it in tick order. The
  unseeded `_rng.randomize()` normal-play path retires.
- **A campaign log** — seed + the tick-stamped command stream (the campaign
  command queue above), mirroring `REPLAY.md`'s seed-plus-orders format.
- **Battles nest as recorded results.** The campaign log records, per
  battle: launch tick, the battle's own seed, and the returned result
  payload. Campaign replay **applies the recorded result** rather than
  re-fighting; the battle seed is retained so any battle can be replayed
  *independently* with the existing battle replay system. (Re-simulating
  battles inside a campaign replay would make campaign replays hostage to
  every battle-sim change; recorded-result nesting keeps the two replay
  systems decoupled. The battle's own replay file remains the
  tick-for-tick record of the fight.)
- **A campaign state transcript.** The verify-via-state-dump discipline
  (the machine-readable transcript used to verify battle behavior) extends
  to the campaign: dump armies (position, composition, supply, orders),
  hexes (stock, structures), diplomacy, and clock at requested ticks, so
  campaign mechanics are verified by exact values, not by reading a
  rendered map.

## Non-goals

- **Campaign AI.** Not designed here. The chain-of-command architecture in
  `docs/battle-ai-design.md` (in flight on
  [PR #581](https://github.com/Lacaedemon/sparta/pull/581), for #498) is
  expected to extend upward to campaign commanders — the campaign half of
  [#387](https://github.com/Lacaedemon/sparta/issues/387) — precisely
  because a hierarchy whose actuators are *orders* doesn't care whether the
  order is "wheel left" or "march on Belgica." The existing greedy
  province AI (`_run_enemy_ai`) and deterministic diplomacy heuristics stay
  as placeholders until that work reaches this layer. This doc only
  commits to keeping every AI touchpoint order-shaped so the extension has
  a clean seam.
- **Multiplayer.** Single-player assumptions are load-bearing (the
  time-freeze during battles, one battle at a time). Not designed for.
- **3D.** The campaign map is 2D top-down, like the battles (locked
  decision in `PLAN.md`).
- **Naval movement and transport.** Water matters to this design only as
  supply capacity (river/coast hexes as line sources). Fleets, sea battles,
  and amphibious operations are a separate future design.
- **Economy beyond logistics.** No taxation, trade, or construction economy
  is designed here beyond what supply lines, depots, and city founding
  strictly need. #427's building rosters define *what exists to build*;
  the economic loop that paces building is future work.

## Phased plan

Each phase is independently shippable, keeps the game playable throughout,
and carries acceptance criteria. **No phase issues are filed yet — each
will be filed when the owner accepts this design** (deliberately unlike the
LOD and orders-queue docs, whose phase issues were pre-filed).

### Phase 1 — map and time foundation

**Scope.** The hex substrate with the province overlay; hex-terrain data
model; the fixed-tick pausable clock with speed controls; the campaign
command queue (apply-once); hex-path army movement at slowest-contingent
speed; port the two shipped campaigns (Gallic War, Four Kingdoms) onto
hand-rasterized hex maps; retire `end_turn`/`_acted`/turn counting;
campaign seed + command log (replay foundation). Armies stay
integer-strength in this phase — composition is phase 2 — so the existing
auto-resolve and battle hand-off keep working unmodified.

**Dependencies.** None (this is the foundation).

**Acceptance criteria.** Both shipped campaigns are playable end-to-end on
the new substrate (move, fight via the existing hand-off, win); pause/speed
controls work and orders queue while paused; a recorded campaign session
replays to an identical final state (verified via a campaign state dump,
not eyeballing); the diplomacy/truce rules behave as today with truces
re-expressed in days; `tools/check.sh` fully green.

*Tracking issue: to be filed on acceptance.*

### Phase 2 — armies as composition + battle interface hardening

**Scope.** The army record (regiment lists with type/count/morale/training,
commander slot stub, supply-state stub); loader schema v2; auto-resolve
over composition; the widened battle contract both ways — real composition
in, per-regiment outcomes out; survivors counted as `"units"` + `"routers"`
(closes [#504](https://github.com/Lacaedemon/sparta/issues/504));
morale/training carryover; terrain hand-off (battle `TERRAIN` generated
from the battlefield hex). Minimal faction rosters (#427's campaign-relevant
slice) to give composition a vocabulary.

**Dependencies.** Phase 1 (hexes provide the battlefield-terrain source and
the tick timeline the results land on).

**Acceptance criteria.** A campaign battle deploys exactly the attacking
and defending armies' regiments (verified by state dump against the
campaign army record); a battle ending mid-rout reports the router as a
survivor and the campaign army reflects it; a regiment that survives a
fought battle carries increased `training` into the next battle; a forest-
hex battle spawns forest terrain; auto-resolve and fought-battle outcomes
have the same payload shape.

*Tracking issue: to be filed on acceptance.*

### Phase 3 — logistics: supply lines, foraging, attrition, seasons

**Scope.** Per-hex forage stocks with terrain/season yields; army
consumption/carriage ledger; supply-line path tracing with cut detection;
depots as buildable line sources; starvation attrition into desertion +
morale; the foraging stance; season clock; supply state visualized on the
map and passed into battle morale.

**Dependencies.** Phases 1 (hexes, clock) and 2 (armies that can carry
state; reinforcement flows need composition).

**Acceptance criteria.** An army camped in one place strips its forage
radius and begins attriting within the historically-plausible window for
its size (assert on the ledger via state dump); occupying a hex on an
enemy supply path stops the flow that tick; a winter campaign in poor
terrain is measurably costlier than a harvest-season one in farmland; a
starving army enters battle with reduced morale; all supply evolution
replays deterministically.

*Tracking issue: to be filed on acceptance.*

### Phase 4 — sagas and interwar periods

**Scope.** The saga container (campaign sequencing, transition triggers on
campaign victory); persistent saga state (veteran regiments, settlements,
forts, faction relations); the interwar decision screens; veteran-colony
and fort-to-town founding (#428) with migration incentives as growth
modifiers; period/faction data packs (#427) referenced by saga and
campaign.

**Dependencies.** Phase 2 (veterancy worth carrying); phase 3 (settlements
as supply sources — founding is a logistics act as much as a political
one).

**Acceptance criteria.** A two-campaign saga runs end-to-end with an
interwar between; a veteran regiment mustered out into a colony appears as
a town that acts as a supply source in the next campaign; a maintained fort
upgrades across the interwar; saga state survives the full
save/load/replay cycle deterministically.

*Tracking issue: to be filed on acceptance.*

### Phase 5 — dynasty

**Scope.** Rulers become characters: age, mortality on saga time, a small
trait set extending today's `ruler_trait` hooks, heirs and succession at
interwar (plus a mid-campaign succession crisis event); the player's
dynasty as the saga's continuity thread; commander slots on armies filled
by characters, their traits feeding the same deterministic AI-threshold
hooks rulers use today.

**Dependencies.** Phase 4 (characters need the saga timeline to live and
die on).

**Acceptance criteria.** A saga long enough for a succession sees the
player's heir take over with visible consequences (trait changes ripple
into AI diplomacy thresholds and army command); character lifecycle events
appear in the campaign log and replay deterministically; the game remains
fully playable if the player ignores every dynastic decision (defaults
resolve).

*Tracking issue: to be filed on acceptance.*

## Open questions for the owner

1. **Hex scale.** Roughly how much ground should one hex represent (which
   fixes army footprints, forage radii, and days-per-hex movement)? The
   design assumes "an army crosses several hexes per day" granularity.
2. **Battle time cost.** Is the freeze-plus-lump-cost model right, and how
   big should the lump be (rest of day? a fixed hour count by battle
   length)?
3. **Fugitive return rate.** For #504's fix: what fraction of
   routed-but-surviving troops should return, and over how many days?
   The design says "part of the scattered fraction over following days" —
   the constant is a gameplay call.
4. **Interwar depth.** Is the shallow decision-screen interwar acceptable
   for phase 4, or should interwar periods run on the campaign map (a
   peacetime clock with movement/building) from the start?
5. **Real-geography pipeline.** Hand-rasterized hex maps are assumed for
   phase 1 (Gaul redrawn by hand on hexes). Should the offline
   geography-to-hex pipeline (#165's full ambition) be its own phase, or
   stay an authoring technique outside the game code?
6. **Auto-resolve fidelity.** Should composition auto-resolve (phase 2)
   reuse the far-tier statistical combat rules from
   `docs/large-scale-simulation-design.md` directly (one attrition model
   for both layers), or stay a simpler independent formula?

## Relationship to existing issues

- [#582](https://github.com/Lacaedemon/sparta/issues/582) — the umbrella
  this doc is the deliverable for; the issues below are its sub-issues.
- [#146](https://github.com/Lacaedemon/sparta/issues/146) (pausable
  real-time) — the time-model section; retired-turn mechanics land in
  phase 1.
- [#147](https://github.com/Lacaedemon/sparta/issues/147) (hex grid) — the
  map section adopts its hexes-under-provinces framing, army hex
  footprints, and slowest-unit speed ladder; phase 1.
- [#165](https://github.com/Lacaedemon/sparta/issues/165) (real geography)
  — the rasterize-at-authoring-time pipeline; phase 1 technique, full
  pipeline per open question 5.
- [#482](https://github.com/Lacaedemon/sparta/issues/482) (supply lines) —
  logistics section; phase 3 (food + reinforcements; other resources keep a
  generic ledger slot).
- [#483](https://github.com/Lacaedemon/sparta/issues/483) (foraging) —
  logistics section; phase 3.
- [#126](https://github.com/Lacaedemon/sparta/issues/126) (saga layer) —
  saga section; phase 4.
- [#428](https://github.com/Lacaedemon/sparta/issues/428) (founding
  cities) — veteran colonies + fort-to-town in phase 4, wired into
  logistics as supply sources.
- [#427](https://github.com/Lacaedemon/sparta/issues/427) (period
  factions) — data packs; campaign-relevant slice in phase 2, full packs in
  phase 4.
- [#504](https://github.com/Lacaedemon/sparta/issues/504) (survivor count
  excludes routers) — specified in the battle-interface section; closed by
  phase 2.
- [#387](https://github.com/Lacaedemon/sparta/issues/387) (battle and
  campaign AI) — campaign half is a non-goal here; see
  `docs/battle-ai-design.md` (PR #581, in flight) whose chain-of-command
  architecture is expected to extend to campaign commanders.
- [#516](https://github.com/Lacaedemon/sparta/issues/516) /
  `docs/orders-queue-design.md` — the campaign command queue reuses its
  apply-once, order-shaped-verbs discipline at campaign granularity.
- [#550](https://github.com/Lacaedemon/sparta/issues/550) /
  `docs/large-scale-simulation-design.md` — the aggregate-record precedent
  the composition auto-resolve leans on (open question 6), and the
  determinism invariants both docs share.
