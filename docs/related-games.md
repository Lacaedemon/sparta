# Dev notes: related open-source games

A **running review** of open-source (and a few proprietary) strategy games next
to Sparta, so we don't re-research the landscape every time we want to borrow an
idea, some code, or art. Append to it as new projects surface -- this is a living
document, the design-and-code sibling of the art catalogue in
[`docs/asset-sources.md`](asset-sources.md).

Two questions for each game:

1. **Can we learn anything from its design?**
2. **Does its licence let us borrow its code or art when that helps?**

## The one rule that decides everything: can we reuse it?

Sparta's **code is MIT-licensed** (see [`LICENSE`](../LICENSE)) -- permissive. That
cuts both ways:

- **Copyleft code (GPL / AGPL) is reference-only for us.** Copying GPL source into
  Sparta would force the *combined* work -- Sparta's code included -- to be
  relicensed GPL. We are not doing that for a prototype. So for any GPL project we
  can **read it, learn from it, and reimplement clean-room**, but we cannot lift
  its code. Most of the open-source strategy world is GPL, so this is the common
  case, not the exception.
- **Permissive / public-domain code (MIT, BSD, Apache, PD) we *can* vendor**, keeping
  the upstream notice. This is rare in this genre.
- **Proprietary projects and commercial-game mods give us design lessons only** -- no
  code, no art.

**Art is licensed separately from code**, and the rules for bundling an art file
are the ones already written down in [`docs/asset-sources.md`](asset-sources.md):
CC0 and CC-BY / CC-BY-SA are bundle-safe (CC-BY/SA need attribution; `-SA`
derivatives stay `-SA`); `NC`, `ND`, freeware-no-redistribution, and
commercial-game assets are reference-only. Note that
[`PLAN.md`](../PLAN.md)'s *Locked decisions* currently say **CC0-only** for shipped
art, which is stricter than the asset catalogue -- so adopting a CC-BY-SA art set
(e.g. 0 A.D.'s, below) would be a deliberate policy change to agree on first, not
an automatic yes.

**Legend (code reuse into Sparta's MIT codebase)**
- ✅ **vendorable** -- MIT / BSD / Apache / public domain; copy with the upstream notice.
- ⛔ **reference-only (copyleft)** -- GPL / AGPL; read and reimplement, never copy in.
- 🚫 **design-only** -- proprietary or a commercial-game mod; no code or art to take.

(For the **art** column, the ✅ / 🅰 / ⛔ tags mean the same as in
[`asset-sources.md`](asset-sources.md): ✅ CC0, 🅰 CC-BY/CC-BY-SA with attribution,
⛔ not redistributable.)

---

## The shortlist

| Game | Type | Code licence | Art / data licence | Code | Art | Relevance to Sparta |
| --- | --- | --- | --- | :---: | :---: | --- |
| [0 A.D.](https://play0ad.com/) | Real-time strategy, ancient warfare | GPL v2 (or later) | CC-BY-SA 3.0 | ⛔ | 🅰 | **Very high** -- real-time ancient battles, formations, unit movement, economy |
| [Freeciv](https://github.com/freeciv/freeciv) | Turn-based 4X | GPL v2 (or later) | mixed (GPL / CC-BY-SA per file) | ⛔ | 🅰 (verify each) | Medium-high -- campaign/saga 4X; data-driven *rulesets* architecture |
| [OpenCiv](https://github.com/RyanGrieb/OpenCiv) | Browser turn-based 4X | **MIT** | per-repo (verify) | ✅ | verify | Medium -- MIT so code is vendorable, but TypeScript/web, turn-based |
| [C-evo](https://en.wikipedia.org/wiki/C-evo) (original) | Turn-based 4X | source **public domain** | graphics freeware | ✅ | ⛔ | Medium -- pluggable-AI module API; PD source, but Pascal/Delphi |
| [C-evo: vn971 port](https://github.com/vn971/cevo) | Turn-based 4X | GPL-3.0 | -- | ⛔ | -- | Same design lessons; this port is GPL + archived (Nov 2024) |
| [TotalWarSimulator](https://github.com/MichelangeloConserva/TotalWarSimulator) | Formation-battle research sim (Python 2D → Unity 3D) | **MIT** (see caveats below) | bundled third-party packs (varied) | ✅ | ⛔ | **Very high** -- a worked 2D→3D conversion of exactly Sparta's battle layer; formation/assignment algorithms |
| [godot-open-rts](https://github.com/lampe-games/godot-open-rts) | 3D RTS demo in Godot 4 | **MIT** | verify per asset | ✅ | verify | High -- reference implementation of 3D selection, movement, and camera in Sparta's own engine |
| [Divide et Impera](https://divideetimperamod.com/) | Total-overhaul **mod** for Total War: Rome II | proprietary (built on CA/Sega's game) | proprietary | 🚫 | 🚫 | **High for design only** -- historical realism, supply/population/reform systems, 2000+ unit rosters |
| [M2TWEOP](https://github.com/EOP-Labs/M2TWEOP-library) | Engine-overhaul **mod framework** for Medieval II: Total War | GPL-3.0 | game data proprietary (CA/Sega) | ⛔ | 🚫 | **High for design only** -- a published schema of a shipped Total War title's runtime state: morale and combat-status ladders, a battle-event taxonomy, an army-plan vocabulary |
| [REX / M2EX](https://github.com/Pannoniae/rex) | Unofficial x64 / DX11 **replacement executable** for Rome: Total War and Medieval II: Total War | none published (patched CA/Sega binaries) | game data proprietary (CA/Sega) | 🚫 | 🚫 | **High for design only -- do not reconstruct.** Public GitHub is docs and changelogs, not engine source; rebuilding it is a multi-year commercial-engine problem that conflicts with Sparta's Godot / bottom-up pillars |
| [Renaissance Kingdom Wars](https://store.steampowered.com/app/2533020/Renaissance_Kingdom_Wars/) | Real-time strategy + grand-strategy hybrid | proprietary | proprietary | 🚫 | 🚫 | **High for design only** -- RTS tactical battles fused with a province-conquest grand-strategy layer; mercenary-to-empire progression |
| [awesome-paradox](https://github.com/js00070/awesome-paradox) | Curated list of Paradox-related projects | n/a (link list) | n/a | -- | -- | Pointers to grand-strategy / **dynasty** design and OSS reimplementations |

---

## Per-game notes

### 0 A.D. (Wildfire Games)

The closest open-source relative to Sparta's battle layer: a real-time strategy
game set in **ancient warfare** (the same 500 BC - 1 AD world Sparta draws on),
with land battles of hundreds of units, formations, ranged-vs-melee interplay,
territory, and an economy. Released July 2009; version 28 "Boiorix" (Feb 2026) is
the first non-alpha build.

- **Design to learn from:** formation handling and how a unit's slot in a
  formation interacts with steering; large-scale pathfinding and unit movement
  (directly relevant to our [collision design pillar](../PLAN.md) and issues
  [#164](https://github.com/Lacaedemon/sparta/issues/164) /
  [#192](https://github.com/Lacaedemon/sparta/issues/192)); how an economy and tech
  tree sit under a battle layer (relevant to the campaign/saga arc).
- **Licence:** code **GPL v2 or later** → ⛔ reference-only; we read the engine
  (Pyrogenesis) for ideas but cannot copy it into Sparta. **Art and data are
  CC-BY-SA 3.0** → 🅰 bundle-safe *with attribution and share-alike*, exactly like
  the LPC sets already noted in [`asset-sources.md`](asset-sources.md). This is the
  single biggest art opportunity in the list: a large, directly-relevant
  ancient-warfare library -- gated only by PLAN.md's current CC0-only stance.

### Freeciv

A mature turn-based 4X in the Civilization lineage. The standout lesson is
architectural: gameplay rules live in **data-driven *rulesets*** (units,
buildings, techs, governments as editable data files), so the same engine can run
"civ2civ3", a classic ruleset, or a custom one without code changes.

- **Design to learn from:** the ruleset pattern is a strong model for Sparta's own
  data-driven content -- we already load campaigns from JSON
  ([`data/campaigns/`](../data/campaigns)); the same idea generalises to unit and
  faction definitions for the campaign/saga layer
  ([#126](https://github.com/Lacaedemon/sparta/issues/126),
  [#147](https://github.com/Lacaedemon/sparta/issues/147)). Also a reference for
  long-running 4X turn structure and AI.
- **Licence:** code **GPL v2 or later** → ⛔ reference-only. Bundled art and data
  are a mix of GPL and CC-BY-SA per file → verify each before treating any single
  asset as 🅰.

### OpenCiv (RyanGrieb)

A modern, **MIT-licensed** browser 4X (TypeScript/Node) inspired by Civ V. The MIT
licence is what sets it apart here: its code is the one project on this list we
could legitimately **vendor** into Sparta.

- **Design to learn from:** clean modern take on tile interaction, camera/zoom
  controls, and turn progression.
- **Caveat:** it is TypeScript targeting the browser and is turn-based, while
  Sparta is GDScript/Godot and real-time tactical -- so the practical reuse is
  *patterns and structure*, not literal code transplants. Its design value
  outweighs its (technically permitted) code-reuse value.

### C-evo

A turn-based 4X notable for its **AI architecture**: AI players are separate,
swappable modules talking to the engine through a defined API. The original by
Steffen Gerlach puts its **source code in the public domain** (graphics are
freeware), so the original source is, uniquely, freely reusable.

- **Design to learn from:** the pluggable-AI-module boundary is a clean model for
  [#135](https://github.com/Lacaedemon/sparta/issues/135) (recruitable AI
  subcommanders given higher-level orders) -- define a narrow command API and let an
  AI "commander" drive units through it.
- **Licence nuance:** the **original** source is public domain → ✅ vendorable in
  principle, but it's Pascal/Delphi, so porting to GDScript is a rewrite, not a
  copy. The maintained [`vn971/cevo`](https://github.com/vn971/cevo) port is
  **GPL-3.0** (and archived since Nov 2024) → ⛔; if we ever wanted the code, go to
  the PD original, not the GPL fork. Graphics are freeware → ⛔, never bundle.

### TotalWarSimulator (Michelangelo Conserva)

A solo-authored research project (later "Total War: AI", a QMUL Game AI group
effort) that tried to reproduce Total War-style formation battles three times
over: a **Python/pymunk 2D prototype** (`master`), a **Unity 3D port**
(`unity`, the default branch), and an abandoned **Unity DOTS** spike (`dots`)
-- plus a `cpp` branch. Studied in depth for the 3D conversion; the full
findings and the ideas adopted are in
[`3d-conversion-design.md`](3d-conversion-design.md).

- **Design to learn from:** optimal soldier→slot assignment
  (Hungarian/Jonker-Volgenant) when a formation moves or reshapes, gated by
  path-turn angle so it doesn't run every frame; arrival-time-normalized
  wheeling (outside files speed up, inside files slow, everyone stays
  dressed); unit-carrier-on-a-spline movement with a lag throttle; the
  drag-out ghost-formation preview gesture; and the architectural proof that
  a "3D" formation battle keeps a planar sim (its Unity port strips Y from
  every gameplay computation). Equally instructive as a **cautionary tale**:
  its combat layer was never finished in Python, was framerate-coupled and
  hacky in Unity, and the project died of serial rewrites rather than any
  technical wall.
- **Licence:** **MIT** (LICENSE added on the `unity` default branch) → ✅
  vendorable in principle -- a rarity in this genre. Two caveats: the vendored
  LAP/Hungarian solvers carry no license headers and have unclear upstream
  origins (re-implement, don't copy), and the bundled `Alglib` plugin is
  GPL/commercial dual-licensed (never copy). Bundled art (medieval weapon and
  animation packs) is third-party with per-pack terms → ⛔ treat as
  non-redistributable.

### godot-open-rts (lampe-games)

A complete small 3D RTS built in Godot 4 (MIT, ~1.1k stars): selection,
movement, construction, fog of war. Not a formation battle game, but the most
useful **same-engine reference** for the 3D conversion's interaction shell --
RTS camera, unit picking, and drag-select done idiomatically in Godot 4.

- **Design to learn from:** working, readable implementations of the exact
  input problems the 3D conversion must solve (ray picking, selection boxes,
  camera control) in Sparta's own engine and language family.
- **Licence:** code **MIT** → ✅ vendorable with notice; assets are per-file →
  verify before reuse.

### Divide et Impera

Not a standalone game: a **total-overhaul mod for Total War: Rome II** (a
commercial Creative Assembly / Sega title). It rebuilds the ancient-warfare
experience around historical authenticity -- a custom population system, a supply
system, a reforms system, 2000+ hand-built unit rosters, and reworked battle AI
and unit behaviour.

- **Design to learn from:** a rich source of *what realistic ancient warfare feels
  like* -- supply lines, population, and believable unit behaviour. Directly informs
  [#201](https://github.com/Lacaedemon/sparta/issues/201) (physics-based battles)
  and the broader realism goals.
- **Licence:** it is built on a proprietary game and its assets → 🚫 **design
  inspiration only**. We take none of its code or art; this matches PLAN.md's
  explicit "**not** commercial-game mod assets" warning.

### M2TWEOP (M2TW Engine Overhaul Project)

Not a game, and not a library you build against: an **in-memory patcher** for the
retail *Medieval II: Total War* binary.
It attaches through a proxy `d3d9.dll`, reverse-engineers the engine's live
structures, and re-exposes them to mod authors as a Lua API.
Most of its stated feature set is limit-breaking and re-exposure rather than new
mechanics -- raising the unit-roster cap, unlocking console commands, fixing
engine bugs.

That makes it a different **kind** of entry from the standalone games above
(REX/M2EX, next, is the other engine-patch row, but it ships binaries rather
than a published schema).
We are not reading it for its own design.
Its generated Lua reference (`docs/_static/LuaLib/index.html`) is in effect a
**published schema of a shipped Total War title's runtime state**: an itemised
list of what a mature grand-strategy game decided was worth modelling.

**The finding that frames everything else:** the API exposes **no per-soldier
accessor of any kind**.
Searching the reference for `soldierPos`, `getSoldierAt`, or `soldierIndex`
returns nothing, and every soldier-related field is an aggregate count
(`soldierCount`, `soldiersLost`, `soldiersKilled`, `soldiersEnd`).
Medieval II's model bottoms out at the regiment, so **Sparta already simulates a
layer it does not have**.
Nothing here is a template for our core physics.
The value is entirely in the layers *above* it -- perception, morale
classification, command, and reporting -- which is where Sparta is thinnest.

- **Morale is a seven-rung ladder, not a scalar plus a rout flag.**
  `moraleStatus` is `berserk, impetuous, high, firm, shaken, wavering, routing`.
  Sparta's `morale` is a float and `Unit.State` (`scripts/Unit.gd:12`) is
  `IDLE, MOVING, FIGHTING, ROUTING, DEAD`, so our model is effectively
  fine-or-routing.
  The ladder is a *classification of a quantity we already have* rather than a
  modifier layered on top, so it costs the physics nothing and buys legibility:
  `shaken` and `wavering` are visible pre-rout states a player can react to.
  Note it is two-sided -- `berserk` and `impetuous` sit above `high`, so
  over-eagerness is modelled as a morale state, not as disobedience.
- **Each unit carries a perceived local combat outcome.**
  `combatStatus` is `notInCombat, victoryCertain, victoryAlmostCertain,
  victoryDistinct, balanced, defeatDistinct, defeatAlmostCertain, defeatCertain`.
  This is the highest-value item here, because it is the one place we can do
  better rather than merely catch up: Medieval II must *estimate* a local
  balance-of-fight from stats, whereas a soldier-physics sim can **derive** one
  honestly from casualty differential, contact frontage, and engaged counts it
  already computes every tick.
- **The morale inputs we lack are all local observations**, not modifiers:
  nearby friendly and enemy counts, engaged-unit counts, and who is currently
  shooting at you.
  Sparta has `fatigue` (`scripts/UnitMorale.gd:13`) and `_under_fire`
  (`scripts/Unit.gd:779`) but **no local force-ratio input at all** -- morale
  moves on casualties and a friendly-shock contagion (`scripts/Unit.gd:6042`).
  Being locally outnumbered is a classic reason real formations break, and we
  cannot currently express it.
- **A battle-event taxonomy**, including `onBattleTideofBattle` ("A different
  team is now the strongest"), `onBattleArmyTired`, `onBattleArmyHalfDestroyed`,
  `onBattleUnitGoesBerserk`, and `onBattleGeneralRouted`.
  Sparta declares four signals across `scripts/`, all UI plumbing.
  The value is the list itself: a shipped title's considered answer to what is
  worth telling the player about.
- **An army-plan vocabulary.**
  `battleAI.gtaPlan` enumerates `DO_NOTHING, ATTACK_ALL, DEFEND, DEFEND_FEATURE,
  HIDE, AMBUSH, SCOUT, WITHDRAW` plus three settlement plans, and a plan
  decomposes into prioritised objectives with units assigned to each.
  `scripts/General.gd:46` defines exactly two, `PLAN_ADVANCE_LINE` and
  `PLAN_ENVELOP`.
  Our General/Subcommander split beneath that is arguably the better structure;
  what is missing is variety at the top, and an army that can only advance or
  envelop cannot fight a defensive battle.
- **Smaller items worth a look:** formation spacing is four numbers per unit type
  (front-to-back and side-to-side, in both close and loose order) alongside
  `mass`, `width`, and `height`; the battle-to-campaign result record tracks
  prisoners taken and caught separately, friendly-fire casualties, withdrawal as
  distinct from defeat, and a qualitative margin (`close, average, clear,
  crushing`); and there is a 16-value ground taxonomy whose `mud`/`mudRoad` and
  `grassShort`/`grassLong` splits are the kind of distinction you only reach by
  shipping.

**What to take care NOT to take.**
The engine pairs that ground taxonomy with per-unit-type terrain modifiers
(`statHeat`, `statScrub`, `statSand`, `statForest`, `statSnow`) -- a lookup table
saying this unit is some percentage worse in scrub.
That is exactly the top-down shortcut our design philosophy rejects: mud should
slow a heavy man more than a light one because of mass and friction, not because
of a table entry.
The same caution applies to `onCalculateUnitValue`, one scalar per unit type
whose own documentation says it drives the combat readout, recruitment, army
strength evaluation, auto-resolve, and the campaign AI at once.
One number feeding five subsystems is the definitional top-down abstraction.
It is still the right shape for *AI and campaign code*, which legitimately needs
a cheap comparable number, so the rule worth adopting is that such a scalar may
be read by planners and never by combat resolution or by anything the player
reads as an outcome.

- **Licence:** the project's own code is **GPL-3.0** and Sparta is MIT, so its
  source is ⛔ reference-only; the game data model it documents belongs to
  Creative Assembly / Sega, so that half is 🚫 design-only.
  In practice neither gates much, because what transfers here is knowledge of
  *which quantities a shipped title tracks*, which is not code.
  Its vendored `M2TWEOP Code/3rd/` tree is mostly permissive (MIT, BSD, zlib) but
  also carries LGPL FFmpeg and BeaEngine and a proprietary Autodesk FBX SDK; none
  of it is usable from GDScript, so the question is moot.

### REX / M2EX (Pannoniae)

Not an open-source engine. [Pannoniae/rex](https://github.com/Pannoniae/rex) is
the public hub for **REX** (Rome: Total War) and **M2EX** (Medieval II: Total
War): unofficial patches that replace the Steam executables with a 64-bit,
Direct3D 11 overhaul of Creative Assembly's 2004/2006 games. The GitHub repo
itself is about 78 KB -- a README, three `modding/*.md` notes, and dumped
scripting/console tables under `scripting/{rtwdocs,m2docs}/`. Language stats are
empty; there is no published licence. Releases ship Windows binaries that patch
a retail copy. Reconstructing REX therefore means reconstructing those two
commercial engines, then re-doing the overhaul on top.

**The finding that frames everything else:** REX already *is* the reconstruction.
Its March-August 2026 changelogs name full subsystems, not tweaks -- x64 runtime
and hardcoded-cap removal (factions, regions, religions, cultures, pack size
above 4 GB); a DX9-to-DX11 renderer then HDR, cascaded shadows, PBR, dynamic
lights, LOD fading, and a campaign-map rewrite that cut VRAM from roughly 1-2 GB
to 15 MB; battle combat (including vanilla bugs they claim to have fixed: spear,
high-ground, pikes, muskets, two-handers) plus formations, sieges, and projectile
physics accurate enough to drive terrain-following range rings; campaign AI,
fog-of-war, and end-turns they report as 20-40x faster; a new pack format, packer,
and 7-zip plugin. Rome 2 was publicly described as about 3 million lines of code.
RTW/M2TW are older and smaller, but still a complete AAA strategy product of that
era. A clean rebuild is years of specialist work even with source. Without source
it is longer.

That is a different kind of entry from M2TWEOP above. M2TWEOP publishes a Lua
schema of live engine state we can read. REX publishes replacement executables
we cannot vendor, plus changelogs of *what* they added, not *how* the sim works.

**Difficulty by approach (so we do not re-open the question):**

- **Read what is already public -- hours to days.** Changelog, the three
  `modding/*.md` files, and the dumped script/console tables. This is the
  legitimate harvest.
- **Reimplement documented TW combat rules in Godot -- weeks.** The modding
  community already published EDU chance-to-kill formulas (the Complete EDU
  Guide on the TWC Wiki). That is gameplay design research, not binary
  reconstruction. It also conflicts with Sparta's locked pillar in
  [`PLAN.md`](../PLAN.md): bottom-up emergence from soldier physics, not a
  top-down `1.1^(ATK - DEF)` lookup. Do not import those formulas into combat
  resolution.
- **Clean-room reconstruction of the engine -- multi-year, specialist team.**
  Two related-but-not-identical games, tightly coupled renderer / sim / AI /
  data, no public symbols. REX's own pace (first public release around March
  2026, DX11/HDR/PBR by August) is only plausible with deep engine access;
  community threads argue about leaked CA source versus binary patching.
  Either path is a copyright problem, not a coding exercise. Out of bounds
  here: no disassembly, no leaked trees, no patched-exe archaeology.
- **Copy REX's binary into Sparta -- not a shortcut.** Sparta is Godot 4.7
  GDScript, 2D-sim-first, CC0 art only. Dropping in a Direct3D C++ Total War
  executable would throw away the existing battle, the 3D-presentation plan
  ([#69](https://github.com/Lacaedemon/sparta/issues/69)), and the licence
  stance.

**Is it worth it?** For playing RTW/M2TW on modern PCs, REX already exists;
reconstructing it duplicates that project. For Sparta, no. The valuable bits
are design observations (range rings that follow projectile physics,
formation-attack, pike/musket feel, silhouette readability), which come from
changelogs and play. The expensive bits (DX11 port, pack format, campaign AI,
hardcoded-limit surgery) are solving CA's 2004 engine, not Sparta's. Sparta
already has the hard differentiating piece in progress: collision-first
individual soldiers, formation cohesion, spear screens. Recreating REX would
replace that with a different -- and copyrighted -- architecture.

**What to take care NOT to take.** Same rule as M2TWEOP's terrain-modifier
tables: EDU lethality formulas, per-type combat multipliers, and any other
top-down lookup that CA used to approximate an outcome our physics should
produce. Also the engine, the pack format, the renderer, and the campaign
layer -- those are CA's product.

**If we later want TW-like *feel* in Sparta,** stay on the Godot sim and
harvest public design: play notes (pikes, charges, range, camera), treat TWC
EDU/morale docs as reference for *which quantities a player notices*, and
open roadmap issues for specific UX (range rings, unit silhouettes,
formation-attack) when they earn a place. That is weeks of design, not years
of engine archaeology.

- **Licence:** none published on the GitHub repo; the shipped artefacts are
  patched Creative Assembly / Sega executables plus the retail game's data.
  🚫 **design inspiration only** -- no code, no art, no reconstruction.
  Matches PLAN.md's "**not** commercial-game mod assets" warning and the
  locked decision not to reconstruct commercial Total War engines.

### Renaissance Kingdom Wars (Broken Rampart Interactive)

A commercial hybrid of grand strategy and real-time tactical battles, set in
1510 during the age of gunpowder and mercenaries: players rise from a
mercenary captain to an empire ruler across 500+ provinces, evolving their
armies from medieval weaponry to Renaissance-era arquebuses and cannons.
Developed by Broken Rampart Interactive, a small indie studio founded
October 2023; entered Early Access July 2024 and reached full release
November 2024.

- **Design to learn from:** the closest commercial analogue on this list to
  Sparta's own pitch -- a grand-strategy province-conquest layer sitting
  directly on top of real-time tactical battles, with an explicit
  progression from small-scale mercenary command to empire management.
  Worth studying for how it paces that campaign-to-battle handoff and how
  weapon-technology evolution (medieval to gunpowder) is exposed to the
  player -- relevant to Sparta's own campaign/saga arc
  ([#126](https://github.com/Lacaedemon/sparta/issues/126)) and any future
  weapon-tech progression.
- **Licence:** proprietary, commercial Steam release (c) 2023-2024 Reverie
  World Studios, Inc. → 🚫 **design inspiration only** -- same category as
  Divide et Impera above; no code or art to take.

### awesome-paradox

A curated list of open-source projects around **Paradox Interactive** grand-strategy
games (Crusader Kings, Europa Universalis, Victoria, Hearts of Iron) -- mods, save
converters, parsers, and reimplementations.

- **Design to learn from:** Paradox's **dynasty/character** systems (Crusader Kings)
  are the clearest commercial model for Sparta's "**dynastic** grand-strategy" pitch
  and the saga layer ([#126](https://github.com/Lacaedemon/sparta/issues/126)). Two
  list entries are open-source reimplementations of Victoria II -- **OpenVic** and
  **Project Alice** -- worth studying for how a deep grand-strategy simulation is
  structured in open code (check each project's own licence before reusing code).
- **Licence:** the list itself is just links; the games it orbits are proprietary,
  so most mods build on closed engines. Treat as a reading list, not a code source.

---

## Others worth a look

The same pattern repeats across the open-source strategy ecosystem -- **GPL code,
often CC-BY-SA art** -- so all of these are ⛔ for code reuse and 🅰 (verify) for
art:

- **The Battle for Wesnoth** (GPL v2; art CC-BY-SA) -- turn-based tactics with a
  strong data-driven scenario/campaign system (WML). Good reference for
  externalised content.
- **Warzone 2100** (GPL v2; assets CC0 / CC-BY-SA) -- real-time strategy; one of the
  more permissively-arted GPL projects.
- **OpenRA** (GPL v3) -- a modernised RTS engine with a well-regarded multiplayer and
  **replay** architecture, relevant to Sparta's deterministic replay system
  ([`scripts/Replay.gd`](../scripts/Replay.gd), [`REPLAY.md`](../REPLAY.md)).
- **Beyond All Reason / Recoil (Spring)** (GPL) -- very large-scale RTS; a reference
  for unit counts and movement/physics at scale
  ([#201](https://github.com/Lacaedemon/sparta/issues/201)).

---

## Bottom line

- **Code:** the genre is overwhelmingly GPL, and Sparta is MIT, so treat 0 A.D.,
  Freeciv, Wesnoth, OpenRA, Spring, and the `vn971/cevo` port as **design and
  architecture references -- read, learn, reimplement clean-room; never copy code
  in.** The legitimately vendorable exceptions: **TotalWarSimulator (MIT)** and
  **godot-open-rts (MIT)** -- both directly relevant to the 3D conversion, the
  latter even in our own engine -- plus **OpenCiv (MIT)** and the **original
  C-evo (public-domain source)**, which are different engines/languages and
  turn-based, so their design value beats their code value.
- **Art:** the best opportunity is **0 A.D.'s CC-BY-SA 3.0 ancient-warfare
  library** -- bundle-safe with attribution under the [`asset-sources.md`](asset-sources.md)
  rules, but blocked for now by PLAN.md's CC0-only locked decision. If we ever
  relax that to allow CC-BY-SA (as the LPC note already contemplates), 0 A.D. is
  the first place to look.
- **Highest design value for Sparta specifically:** **0 A.D.** (real-time ancient
  tactics, formations, collision/pathing -- our core pillar) and **Divide et Impera**
  (historical realism: supply, population, rosters, believable unit behaviour).
- **Best source for the layers *above* the physics:** **M2TWEOP**, which is less a
  design to copy than a published schema of what a shipped Total War title tracks.
  Its API bottoms out at the regiment and has no per-soldier accessor at all, so it
  offers nothing for our core sim and a great deal for morale classification,
  per-unit perception, army planning, and battle reporting -- the parts of Sparta
  that are thinnest precisely because the physics has had all the attention.
- **Do not reconstruct REX/M2EX (or the CA engines they patch).** The GitHub
  repo is docs, not source; rebuilding those games is a multi-year commercial-
  engine project that would throw away Sparta's Godot sim and bottom-up combat
  pillar. Harvest UX from public changelogs and play; never disassemble,
  vendor, or port the replacement executables.

## Adding a game to this list

1. Find the project's **code licence** and, separately, its **art/data licence**.
2. Tag code reuse ✅ / ⛔ / 🚫 and art reuse ✅ / 🅰 / ⛔ (same meanings as
   [`asset-sources.md`](asset-sources.md)), and add a row above with links.
3. Write a sentence or two on **what we can learn from its design** and, if its art
   is reusable, note it so [`asset-sources.md`](asset-sources.md) can pick it up.
4. When in doubt on a licence, treat code as ⛔ and art as ⛔ until verified.
