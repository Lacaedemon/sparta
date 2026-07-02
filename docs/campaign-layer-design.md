# Design note: unified campaign layer

Status: **accepted design — not yet implemented.** The owner reviewed this
note and answered its six open questions in
[the PR #583 review](https://github.com/Lacaedemon/sparta/pull/583#pullrequestreview-4618476256);
this revision folds those answers in. This note unifies the
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

The design held its phase issues back until the owner had reviewed it.
That review has happened — acceptance with amendments — so the phase
issues are now filed and linked from each phase below, as sub-issues of
#582.

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

Implemented independently, these would collide — a map substrate built
before the time model is chosen bakes in per-turn movement costs; supply
lines built on the current province graph would have to be rebuilt on the
finer substrate; a saga layer above an integer-army campaign carries
nothing worth carrying. This doc fixes the positions once so the phases
build toward the same game.

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

### Map representation: continuous geographic positions under a province overlay

**Position: continuous coordinates, as granular as stays performant.**
Armies (and any other campaign entity with a place in the world) carry
**continuous geographic positions — latitude/longitude** — with granularity
bounded only by performance, per the owner's review direction. **Provinces**
persist as the political overlay: a province stays a named polygon with an
owner, and everything political (ownership, victory, diplomacy, recruitment
sources) stays province-level — an army's province is a point-in-polygon
fact derived from its position, not a stored slot. Terrain and logistics
data live in **geographic data layers**, not per-cell gameplay objects:

- **raster layers** (relief, land cover, forage stock — see logistics),
  sampled at a position; each layer's cell size is a data-fidelity knob
  tuned independently, invisible to the player and decoupled from any
  gameplay grid;
- **vector layers** (coastlines, rivers, roads), kept as geometry and
  sampled or traced directly — a river is a polyline to cross or follow,
  not a flag on a cell;
- **structures** (depot, fort — #427/#428) as point features at map
  positions.

Storing positions in lat-long serves two other decisions directly. Real
geography (#165) ships in geographic coordinates, so campaign positions
live in the source data's own coordinate system and the ingestion pipeline
(its own phase, below) has no substrate conversion to do. And the saga
layer's **fluid scale** requirement — theater-scale campaigns, interwar
periods sliding between continental and city scale (saga section) — makes
scale a camera and data-resolution choice rather than a substrate change; a
fixed cell size would need re-gridding at every scale shift. Distance and
area math run through a per-campaign **map projection** (theater-scale
extents keep a local equidistant projection accurate); storage stays
lat-long.

Armies move along continuous paths at the pace of their slowest contingent
(#147's speed ladder — cavalry > camels > elephants > foot > artillery —
becomes a per-unit-type campaign speed the army mins over, unchanged in
continuous form). An army's footprint is a strength-scaled area around its
position. Two armies meet on the map, not in a province-attack abstraction
— which is what makes interception, blocking a pass, and cutting a supply
line *positional* facts the player can see, instead of graph edges. All of
these are geometry queries against positions, which is where performance
gets decided:

**The performance gate, honestly.** Position queries — interception,
supply-line cut detection, forage-radius overlap, AI sensing — go through a
**spatial index**; the battle layer's `SoldierSpatialHash` (per-soldier
neighbor queries at 1,700+ bodies per physics tick) is the in-repo
precedent pattern. Campaign entity counts sit orders of magnitude below
that, and campaign ticks fire far less often than physics ticks, so the
prior is that continuous positions hold comfortably — but that is a prior,
not a measurement. Phase 1's acceptance therefore includes a measured
campaign-tick budget at target entity counts at maximum game speed (the
same benchmark discipline the battle layer already applies to soldier
counts). **The fallback trigger:** if continuous-position queries cannot
stay within the campaign tick budget at target army counts, positions
aggregate to a coarse grid — #147's hexes, demoted from substrate to
fallback aggregation strategy. The political overlay and the geographic
data layers are unchanged by that fallback, so it is a contained retreat,
not a redesign.

**Against the alternatives.**

- *Keep the pure region graph* (today's model): too coarse for everything
  downstream. Supply lines, forage radii, army frontage, interception, and
  "the army is two days from the city" all need positions finer than
  "in province 3."
- *A hex-grid substrate* (#147's framing, and this doc's own position
  before the owner's review): what hexes bought — discrete per-cell
  bookkeeping, integer-step movement determinism — is available without
  them. Per-cell bookkeeping lives in the raster data layers at whatever
  resolution each layer wants; determinism with float positions is a solved
  problem in this codebase (the battle layer replays thousands of float
  soldier positions tick-for-tick under the fixed-tick sim, and the
  campaign clock is fixed-tick for the same reason). What hexes cost: a
  fixed cell size that fights fluid scale, a second spatial vocabulary
  bolted between the geographic source data and the game, and a granularity
  ceiling the owner explicitly declined. Demoted to the fallback above.
- *Continuous positions without the province overlay*: loses the political
  layer cheaply kept — diplomacy, victory conditions, recruitment, and the
  existing campaign rules all speak province. The overlay preserves them
  while the substrate changes underneath.

**Migration note.** `CampaignState`'s political rules (diplomacy, truces,
rulers, victory) survive; its *movement* rules (`can_move`, `_acted`,
adjacency) are replaced by continuous-path movement under the new time
model. The polygon renderer in `CampaignMap._draw` keeps rendering province
polygons; armies stop being a per-province integer and start being objects
with map positions (composition section below).

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

**What happens to campaign time during a battle: it freezes, then pays the
battle's real duration, 1:1.** When a tactical battle launches, the
campaign clock stops for the whole world and resumes when the battle
resolves. On return, the campaign clock advances by the battle's **actual
elapsed in-battle time** — battle ticks over `Replay.PHYSICS_TPS`, charged
1:1 as campaign game time to the whole world. An average large battle runs
30–60 minutes, so it costs the campaign 30–60 minutes of game time; a
five-minute rout costs five. This is the owner's decision (review answer
2): playthrough time and game time stay honest with each other — no
arbitrary lump cost. Rationale for the freeze-then-charge shape:

- A tactical battle plays out in a different scene at its own pace.
  Letting the campaign clock run *during* it means the rest of the world
  moves at an uncontrolled exchange rate against the battlefield — and in
  single-player there is no one else to serve by keeping the world hot.
- Freezing keeps the battle a **single atomic event** on the campaign
  timeline, which the determinism section needs: the campaign log records
  "battle at tick T, seed S, duration D, result R" with nothing
  interleaved. The charged duration is derived from the recorded battle
  tick count, so replays charge identically.
- The alternative — world keeps running, battle outcome applied
  retroactively — creates simultaneity paradoxes (a relief army arrives at
  a battle that is still being fought in another scene) for no single-player
  benefit. Revisit only if multiplayer ever becomes a goal (it is a
  non-goal, below).

The other resolution modes (battle-resolution section below) charge the
same clock the same way: a birds-eye battle runs on sim ticks and charges
its simulated duration 1:1; an insta-resolve computes in seconds of
playthrough but charges a **modelled duration** produced by the same
formula that produces the outcome — the 1:1 rule binds playthrough time
only for battles actually played out.

AI-vs-AI clashes never open the battle scene (unchanged from today — PLAN.md
notes AI battles always auto-resolve); under real-time they resolve at the
tick the armies meet, through the insta-resolve path.

### Armies become composed objects

Everything below — logistics, the battle interface, the map footprint —
needs armies to be more than an integer. **Position:** an army is a first-class
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

Auto-resolve re-expresses over composition as **insta-resolve**: instead of
one dice roll over two integers, a fast deterministic formula over the two
regiment lists (computes in under five seconds). The exact rule is phase-2
implementation detail; the design constraint is it consumes and produces
the same regiment records the tactical battle does, so every resolution
path stays interchangeable — insta-resolve is one of the player-selectable
resolution modes specified in the battle-resolution section below.

### Logistics: supply lines (#482) and foraging (#483)

Historical armies were fed or they dissolved; ancient-world provisioning is
the best-documented constraint on where armies could go and when. The
design grounds both mechanics in that practice, and — per PLAN.md pillar 2
(bottom-up emergence) — builds them from **local rules per army and per
patch of ground**, not a global supply formula.

**The local rules:**

- **Consumption.** Each army consumes rations per soldier per day (pack
  animals count). This is one number per army per tick — cheap.
- **Carriage.** An army carries a bounded number of days of supply (its
  baggage train; historically single-digit days to a few weeks depending on
  train size — the exact cap is a per-army stat, extended by wagons at the
  cost of the artillery-tier speed penalty from #147's ladder).
- **Foraging** (#483). The land carries a **forage stock layer** — one of
  the raster data layers from the map section — that armies draw down
  within their forage radius, scaled by land cover and **season** (rich in
  farmland at harvest, poor in mountains and winter). Foraging is local and
  depleting: a large army strips its surroundings in days and must move or
  starve — which is why big historical armies kept moving, and why sitting
  a siege needed a supply line. Stocks regenerate seasonally. Dispersing to
  forage (a wider forage radius = more ground drawn) is an army stance with
  a military cost: a foraging army moves slower and fights the first ticks
  of an interception at a readiness penalty.
- **Supply lines** (#482). A supply line is a **traced route** — a polyline
  over the road, valley, and waterway geometry — from an army to a friendly
  source (a supplied city, a depot, a coastal or river landing — waterways
  carry far more, matching the ancient cost advantage of water transport).
  The line delivers a flow of rations (and, per #482, **reinforcements** —
  replacement soldiers walk the same roads food does). A line is *cut* when
  an enemy army's zone of control covers a point on the route (a spatial
  query against the index from the map section) — no separate "raiding"
  mechanic needed at first: raiding **emerges** from parking a cavalry army
  on the enemy's road, exactly the bottom-up outcome the pillar asks for.
- **Depots** (#427's encampment/siegeworks structures). A built structure
  at a map position that stores supply and acts as a line source, extending
  reach in poor country — the magazine system. Forts (#428's long-term
  maintained forts) share the structure mechanism.
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
- **Terrain** — sampled from the geographic layers around the clash
  position: the land cover and relief at the battle site seed the battle's
  terrain patches (today's hardcoded `Battle.TERRAIN` array becomes an
  input), so a fight in forest country is a forest fight. Deterministic
  generation from the campaign seed + the battle-site coordinates.
- **Context** — attacker/defender roles, faction names/colors (already
  passed today), season/weather (phase 3+, once seasons exist), and the
  supply-state morale modifiers already applied on the campaign side.

**Battle → campaign:**

- **Per-regiment outcomes**, not one integer: for each regiment that
  entered, its surviving soldier count, end-of-battle `morale`, and
  `training` gain (veterancy accrues from surviving real fights — the
  carryover that makes a saga's veteran colonies (#428) mean something).
- **All routers that leave the field return** — the owner's decision
  (review answer 3), and the #504 position completed: a unit in the
  `"routers"` group at battle end **counts as surviving**, and every routed
  soldier who escapes the field **rejoins his army after the battle** — no
  probabilistic return rate, no stragglers trickling back over days. The
  losing side's permanent loss is exactly what was **killed or captured on
  the field**. Concretely: survivor counting unions `"units"` + `"routers"`
  exactly like `_team_in_play` already does — the victory check and the
  result report stop disagreeing — and escaped routers come back at full
  count with rock-bottom morale. This rule turns the battle layer's
  existing rout/rally and pursuit mechanics into a real campaign decision:
  a victor who wants to *destroy* an army rather than merely defeat it must
  spend battle time hunting fugitives down before they escape the field, at
  the cost of formation order and fatigue; let them run and the enemy
  re-forms at strength. (Historically most of an ancient battle's
  casualties fell in the pursuit, so the incentive is period-accurate.)
- **Casualty split** — dead vs. captured vs. escaped, per regiment. Dead
  and captured are permanent; escaped returns in full on battle end (the
  rule above). What capture looks like in-battle, and what captives are
  worth afterward, is an open question below.

The loop keeps its current shape otherwise: snapshot out, resolve on
return, one battle at a time, campaign clock frozen throughout (time model
above).

### Battle resolution: player-selectable modes

When armies clash and the player commands one, the player picks how the
battle resolves — the owner's decision (review answer 6), replacing the
single "quick resolve" toggle. Three modes, all consuming and producing the
same regiment records, so the choice is about attention, not outcome shape:

1. **Insta-resolve.** The fast deterministic formula over the two regiment
   lists from the composition section — computes in under five seconds of
   playthrough time, charges a modelled duration of game time. The
   successor of today's dice auto-resolve, and the only mode AI-vs-AI
   clashes ever use.
2. **Birds-eye resolve.** The battle runs under the **far-tier statistical
   combat rules the battle layer already ships** — `FarTierRules` evolving
   `FarTierFormation` aggregate records per tick
   (`docs/large-scale-simulation-design.md`; its phases 1–3 — the data
   model, the far-tier rules, and the tier transitions — are merged) —
   with no per-soldier state, presented as a simply-animated aggregate view:
   blocks maneuvering, engaging, and breaking on the field. Cheap enough to
   watch at campaign speed, deterministic and tick-logged like any battle,
   and it produces the same per-regiment outcome payload manual battles do.
3. **Manual command.** The full tactical battle, as today.

**Mid-battle takeover (birds-eye → manual).** The player watching a
birds-eye battle can take command partway through. The seam already exists:
`TierTransition` — merged with the LOD work — promotes a far-tier aggregate
record to reconstructed per-soldier state as a **pure function of the
aggregates plus a deterministic seed**, exactly the promotion path
mixed-tier battles use internally. Taking command promotes every formation
at the takeover tick and hands the reconstructed state to the tactical
scene.

The honest boundary: promotion gives per-formation state reconstruction;
what takeover *additionally* needs — and what its phase must build — is a
tactical battle that can **start mid-fight**. `Battle` today only starts
from spawn lines; deployment from arbitrary positions and facings,
in-progress morale and casualties, already-engaged opposing formations, and
an already-elapsed battle clock all have to load from the birds-eye state.
Determinism carries through the seam: the birds-eye segment is tick-logged,
the takeover tick is recorded in the campaign log, and promotion is
seed-deterministic, so a replay reproduces both segments and their join.
The first cut is one-way — birds-eye to manual; handing a manual battle
back to birds-eye raises UX and pacing questions deferred to the open
questions below.

### Saga structure (#126): campaigns, interwar periods, and the dynasty

A **saga** is a sequence of campaigns (each campaign = one war) separated by
**interwar periods**, carrying persistent state forward so the wars form an
arc. Position on the split:

- **A campaign** owns: the war's map situation (army positions, terrain
  layers), diplomacy of the belligerents, and its own victory condition
  (which becomes the saga's transition trigger). Campaign maps are
  **theater-scale** — the war's theater (Gaul, not the Mediterranean) —
  per the owner's review answer 4.
- **The saga** owns everything that outlives a war: the dynasty (below),
  the roster of veteran regiments (with their accrued `training`), founded
  cities and maintained forts, faction relationships that seed the next
  war's starting stances, and the period/faction data pack in play (#427).
- **An interwar period** is not a second war simulation — it is a
  **decision sequence over saga state**: muster out veterans (→ found a
  colony, #428), maintain or abandon forts, invest in cities, succession
  events, and the inciting setup of the next campaign. Per the owner's
  review answer 4, the interwar is **scale-fluid**: it presents on maps at
  whatever scale the narrative requires — continental for empire-level
  strokes, local/city scale for founding a colony or a succession crisis in
  the capital — and moves fluidly between scales within one interwar. The
  decision verbs anchor to the map at the relevant scale rather than a
  detached menu sequence. This is a presentation range over the same
  continuous-coordinate substrate (the map section's lat-long positions and
  data layers make scale a camera and layer-resolution choice), not a new
  simulation layer — the layering stack (battle → campaign → saga, #126's
  own framing) is unchanged.

**Founding cities (#428).** Two mechanisms, both from the historical
playbook: **veteran colonies** (an interwar action spending mustered-out
veteran regiments to found a town on a chosen site — the Roman colonia;
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
  it becomes the only path) and every stochastic draw — insta-resolve,
  forage variance if any, event rolls — pulls from it in tick order. The
  unseeded `_rng.randomize()` normal-play path retires.
- **A campaign log** — seed + the tick-stamped command stream (the campaign
  command queue above), mirroring `REPLAY.md`'s seed-plus-orders format.
- **Battles nest as recorded results.** The campaign log records, per
  battle: launch tick, resolution mode, the battle's own seed, its elapsed
  duration (the time-model section's 1:1 charge), and the returned result
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
  the data layers (forage stocks, structures), diplomacy, and clock at
  requested ticks, so campaign mechanics are verified by exact values, not
  by reading a rendered map.

## Non-goals

- **Campaign AI.** Not designed here. The chain-of-command architecture in
  `docs/battle-ai-design.md` (merged via
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
  supply capacity (river and coastal landings as line sources). Fleets, sea
  battles, and amphibious operations are a separate future design.
- **Economy beyond logistics.** No taxation, trade, or construction economy
  is designed here beyond what supply lines, depots, and city founding
  strictly need. #427's building rosters define *what exists to build*;
  the economic loop that paces building is future work.

## Phased plan

Each phase is independently shippable, keeps the game playable throughout,
and carries acceptance criteria. The design is accepted, so each phase now
has a filed tracking issue, linked below as sub-issues of #582.

### Phase 1 — map and time foundation

**Scope.** The continuous-coordinate substrate: lat-long army positions
with a per-campaign projection, provinces as the political polygon overlay,
the spatial index for position queries (`SoldierSpatialHash` pattern), and
hand-authored geographic data layers (terrain rasters, river/coast vectors)
for the two shipped campaigns; the fixed-tick pausable clock with speed
controls; the campaign command queue (apply-once); continuous-path army
movement at slowest-contingent speed; retire `end_turn`/`_acted`/turn
counting; campaign seed + command log (replay foundation). Armies stay
integer-strength in this phase — composition is phase 2 — so the existing
auto-resolve and battle hand-off keep working unmodified.

**Dependencies.** None (this is the foundation).

**Acceptance criteria.** Both shipped campaigns are playable end-to-end on
the new substrate (move, fight via the existing hand-off, win); pause/speed
controls work and orders queue while paused; a recorded campaign session
replays to an identical final state (verified via a campaign state dump,
not eyeballing); the diplomacy/truce rules behave as today with truces
re-expressed in days; the campaign tick budget is **measured** at target
army counts at maximum game speed, arming the map section's hex-fallback
trigger with data; `tools/check.sh` fully green.

*Tracking issue: [#603](https://github.com/Lacaedemon/sparta/issues/603).*

### Phase 2 — armies as composition + battle interface hardening

**Scope.** The army record (regiment lists with type/count/morale/training,
commander slot stub, supply-state stub); loader schema v2; insta-resolve
over composition (the fast formula, with its modelled game-time duration);
the widened battle contract both ways — real composition in, per-regiment
outcomes out; survivors counted as `"units"` + `"routers"` and **all
escaped routers returning in full**, the only permanent losses being field
deaths and captures (closes
[#504](https://github.com/Lacaedemon/sparta/issues/504));
morale/training carryover; the 1:1 battle-time charge; terrain hand-off
(battle `TERRAIN` sampled from the geographic layers at the clash
position). Minimal faction rosters (#427's campaign-relevant slice) to give
composition a vocabulary.

**Dependencies.** Phase 1 (the terrain layers and the tick timeline the
results land on).

**Acceptance criteria.** A campaign battle deploys exactly the attacking
and defending armies' regiments (verified by state dump against the
campaign army record); a battle ending mid-rout reports the router as a
survivor and the campaign army reflects its full escaped count; a regiment
that survives a fought battle carries increased `training` into the next
battle; a battle in forest country spawns forest terrain; a fought battle
advances the campaign clock by its recorded duration; insta-resolve and
fought-battle outcomes have the same payload shape.

*Tracking issue: [#604](https://github.com/Lacaedemon/sparta/issues/604).*

### Phase 3 — battle resolution modes: birds-eye resolve and takeover

**Scope.** The resolution-mode choice (insta-resolve / birds-eye / manual)
on player battles; the birds-eye runner — `FarTierRules` over
`FarTierFormation` records driven by the campaign battle payload — with the
simply-animated aggregate presentation; mid-battle takeover: promote every
formation at the takeover tick via `TierTransition` and load the tactical
scene from mid-fight state (deployment from arbitrary positions and
facings, in-progress morale and casualties, engaged pairs, elapsed battle
clock); birds-eye duration charged 1:1; the takeover tick recorded in the
campaign log.

**Dependencies.** Phase 2 (composition is the payload all modes share); the
battle layer's merged LOD machinery (`docs/large-scale-simulation-design.md`
phases 1–3, including `TierTransition`).

**Acceptance criteria.** A birds-eye battle replays deterministically and
returns the same payload shape as a manual battle over the same armies; a
mid-battle takeover produces a playable tactical battle whose per-regiment
aggregate totals match the birds-eye state at the takeover tick (verified
by state dump, not eyeballing); a replay of a taken-over battle reproduces
both segments and their join; AI-vs-AI clashes still insta-resolve.

*Tracking issue: [#605](https://github.com/Lacaedemon/sparta/issues/605).*

### Phase 4 — real-geography ingestion pipeline

**Scope.** #165's full ambition as its own phase, per the owner's review
answer 5: an offline pipeline ingesting real geographic sources
(coastlines, rivers, relief, land cover) and rasterizing/vectorizing them
into the campaign data layers phase 1 defined; projection handling;
validation in the `CampaignLoader` lint-and-reject style; the Gallic War
theater regenerated from real geography as the proving case; the authoring
workflow documented. Hand-authored maps stay first-class — the
four-kingdoms fantasy map just ships invented layers in the same formats.

**Dependencies.** Phase 1 (the data-layer formats the pipeline targets).

**Acceptance criteria.** The Gallic War campaign map regenerates from
geographic source data by a single documented command; the output passes
loader validation and is playable end-to-end; a hand-authored map and a
pipeline-produced map are indistinguishable to the game code (same
formats, same loader path).

*Tracking issue: [#606](https://github.com/Lacaedemon/sparta/issues/606).*

### Phase 5 — logistics: supply lines, foraging, attrition, seasons

**Scope.** The forage-stock raster layer with land-cover/season yields;
army consumption/carriage ledger; supply-route tracing with
zone-of-control cut detection; depots as buildable line sources; starvation
attrition into desertion + morale; the foraging stance; season clock;
supply state visualized on the map and passed into battle morale.

**Dependencies.** Phases 1 (substrate, clock, spatial index) and 2 (armies
that can carry state; reinforcement flows need composition). Phase 4
enriches it — real land cover makes forage yields meaningful — but
hand-authored layers suffice to ship.

**Acceptance criteria.** An army camped in one place strips its forage
radius and begins attriting within the historically-plausible window for
its size (assert on the ledger via state dump); an enemy zone of control
covering a point on a supply route stops the flow that tick; a winter
campaign in poor terrain is measurably costlier than a harvest-season one
in farmland; a starving army enters battle with reduced morale; all supply
evolution replays deterministically.

*Tracking issue: [#607](https://github.com/Lacaedemon/sparta/issues/607).*

### Phase 6 — sagas and interwar periods

**Scope.** The saga container (campaign sequencing, transition triggers on
campaign victory); persistent saga state (veteran regiments, settlements,
forts, faction relations); the scale-fluid interwar — decision sequences
anchored on maps that move between continental and local/city scale per
narrative needs (review answer 4); veteran-colony and fort-to-town
founding (#428) with migration incentives as growth modifiers;
period/faction data packs (#427) referenced by saga and campaign.

**Dependencies.** Phase 2 (veterancy worth carrying); phase 5 (settlements
as supply sources — founding is a logistics act as much as a political
one).

**Acceptance criteria.** A two-campaign saga runs end-to-end with an
interwar between; the interwar presents at least two working scales
(continental and local) over the same saga state; a veteran regiment
mustered out into a colony appears as a town that acts as a supply source
in the next campaign; a maintained fort upgrades across the interwar; saga
state survives the full save/load/replay cycle deterministically.

*Tracking issue: [#608](https://github.com/Lacaedemon/sparta/issues/608).*

### Phase 7 — dynasty

**Scope.** Rulers become characters: age, mortality on saga time, a small
trait set extending today's `ruler_trait` hooks, heirs and succession at
interwar (plus a mid-campaign succession crisis event); the player's
dynasty as the saga's continuity thread; commander slots on armies filled
by characters, their traits feeding the same deterministic AI-threshold
hooks rulers use today.

**Dependencies.** Phase 6 (characters need the saga timeline to live and
die on).

**Acceptance criteria.** A saga long enough for a succession sees the
player's heir take over with visible consequences (trait changes ripple
into AI diplomacy thresholds and army command); character lifecycle events
appear in the campaign log and replay deterministically; the game remains
fully playable if the player ignores every dynastic decision (defaults
resolve).

*Tracking issue: [#609](https://github.com/Lacaedemon/sparta/issues/609).*

## Open questions for the owner

The design's original six questions were answered in
[the owner's PR #583 review](https://github.com/Lacaedemon/sparta/pull/583#pullrequestreview-4618476256)
and their answers are folded into the sections above. What follows are the
new questions those answers raise.

1. **Capture mechanics.** The fugitive rule makes "killed or captured on
   the field" the only permanent loss — what does capture look like in the
   battle layer (surrender of shattered or cornered units? a pursuit
   outcome distinct from cutting fugitives down?), and what are captives
   worth afterward (ransom, enslavement, forced recruitment — saga-economy
   flavor)?
2. **Takeover UX and reversibility.** For the birds-eye → manual takeover:
   what is the affordance (pause-and-confirm at the takeover tick, or an
   instant hot-switch?), and should the reverse — handing an in-progress
   manual battle back to birds-eye resolution — be allowed?
3. **Performance targets for "as granular as can stay performant."** What
   entity counts should the campaign tick budget be measured against —
   how many armies (and, later, sub-army detachments) should a
   theater-scale campaign support at maximum game speed before the hex
   fallback is on the table?
4. **Interwar scale authoring.** Scale shifts serve "narrative
   requirements" — are those scripted per saga (authored beats choosing the
   scale), systemic (the game picks the scale from the decision at hand),
   or player-driven (free zoom with scale-appropriate verbs)?

## Relationship to existing issues

- [#582](https://github.com/Lacaedemon/sparta/issues/582) — the umbrella
  this doc is the deliverable for; the issues below are its sub-issues.
- [#146](https://github.com/Lacaedemon/sparta/issues/146) (pausable
  real-time) — the time-model section; retired-turn mechanics land in
  phase 1.
- [#147](https://github.com/Lacaedemon/sparta/issues/147) (hex grid) — the
  owner's review demoted hexes from substrate to the map section's explicit
  performance fallback; the issue's army footprints and slowest-unit speed
  ladder survive in continuous form (phase 1).
- [#165](https://github.com/Lacaedemon/sparta/issues/165) (real geography)
  — its own phase per the owner's review: the ingestion pipeline is
  phase 4, and lat-long positions make its geographic sources the map's
  native coordinate system.
- [#482](https://github.com/Lacaedemon/sparta/issues/482) (supply lines) —
  logistics section; phase 5 (food + reinforcements; other resources keep a
  generic ledger slot).
- [#483](https://github.com/Lacaedemon/sparta/issues/483) (foraging) —
  logistics section; phase 5.
- [#126](https://github.com/Lacaedemon/sparta/issues/126) (saga layer) —
  saga section; phase 6.
- [#428](https://github.com/Lacaedemon/sparta/issues/428) (founding
  cities) — veteran colonies + fort-to-town in phase 6, wired into
  logistics as supply sources.
- [#427](https://github.com/Lacaedemon/sparta/issues/427) (period
  factions) — data packs; campaign-relevant slice in phase 2, full packs in
  phase 6.
- [#504](https://github.com/Lacaedemon/sparta/issues/504) (survivor count
  excludes routers) — specified in the battle-interface section; closed by
  phase 2.
- [#387](https://github.com/Lacaedemon/sparta/issues/387) (battle and
  campaign AI) — campaign half is a non-goal here; see
  `docs/battle-ai-design.md` (merged via PR #581) whose chain-of-command
  architecture is expected to extend to campaign commanders.
- [#516](https://github.com/Lacaedemon/sparta/issues/516) /
  `docs/orders-queue-design.md` — the campaign command queue reuses its
  apply-once, order-shaped-verbs discipline at campaign granularity.
- [#550](https://github.com/Lacaedemon/sparta/issues/550) /
  `docs/large-scale-simulation-design.md` — the birds-eye resolve mode runs
  its far-tier rules (`FarTierRules`/`FarTierFormation`), and the takeover
  seam is its promotion machinery (`TierTransition`, merged via
  [#558](https://github.com/Lacaedemon/sparta/issues/558)); the two docs
  also share their determinism invariants.
