# Design note: Standard-bearer (formation anchor, visual hierarchy, and casualty succession)

Status: **design drafted** -- establishes architectural and historical grounding for the regimental standard-bearer mechanic.
Builds on [#820](https://github.com/Lacaedemon/sparta/issues/820) and ties into [#821](https://github.com/Lacaedemon/sparta/issues/821) (the position-anchor question, closed 2026-07-15 and implemented in [#861](https://github.com/Lacaedemon/sparta/pull/861) as a two-rank near-front anchor) and [#818](https://github.com/Lacaedemon/sparta/pull/818) (where a front-rank-midpoint anchor was tried and reverted).

## Historical background

In Mediterranean ancient warfare, unit standards served as the primary physical anchor for formation alignment and tactical command:

- **Roman Legionary Standards**:
  Each century or maniple had a *signifer* carrying the century's *signum* (spear topped with a bronze hand, wreaths, and phalerae discs).
  The legion had an *aquilifer* carrying the sacred *aquila* (eagle), an *imaginifer* carrying the *imago* (the emperor's image), and cavalry units and detachments had a *vexillarius* carrying the *vexillum*.

- **Tactical and Spatial Dressing**:
  Soldiers in rank-and-file did not align by abstract global coordinates;
  they aligned ("dressed") their files and ranks by referencing the standard-bearer positioned in the front rank center or flank.
  The standard was tall enough to remain visible above helmets and shield walls.

- **Succession and Morale**:
  Losing a standard was a catastrophic disgrace and tactical failure, often precipitating routs.
  If a standard-bearer fell in combat, the nearest surviving soldier (often a junior officer such as an *optio* or veteran front-ranker) immediately picked the standard up to maintain the line and prevent collapse.

- **Greek and Hellenistic Standards**:
  Classical hoplite phalanxes coordinated by sound rather than by unit standards -- trumpeters (*salpingktes*) and voice, with Sparta famously pacing its advance by aulos players (Thucydides V.70).
  Distinct pennants (*semeia*) serving as unit standards are attested mainly in Hellenistic and Macedonian practice, stationed near the file leaders (*lochagoi*).

Sources: Polybius, *Histories* VI (maniple organization and standard-bearers);
Vegetius, *Epitoma Rei Militaris* II (the legion's *signiferi*);
Pliny, *Natural History* X (Marius and the *aquila*);
Thucydides, *History of the Peloponnesian War* V.70.

## Architecture and Core Mechanics

### 1. Designated Bearer Slot and Positioning

- Each regiment (`Unit.gd`) designates the soldier occupying one formation slot as the active standard-bearer.
  Because `SoldierMelee.reap()` compacts the soldiers array on casualties -- shifting every later soldier's file and rank -- the bearer is tracked as the occupant of a designated slot, re-resolved after every compaction, rather than as a raw array index that would silently re-point to a different soldier when any lower-indexed soldier dies.

- The designated slot defaults to the center file of the front rank, identified by its (rank, file) cell rather than by a raw slot index,
  because the index-to-cell mapping differs per layout:
  the default row-major block layout (`UnitFormation.block_slots`: `file = i % files`, `rank = i / files`) puts that cell at index `floor(files / 2)`,
  a hold-ground reform permutes that same grid through `_sim_soldier_row_slot` (which `SoldierMelee.reap()` trims on casualties exactly as it trims the square slots),
  the square/schiltron layout permutes the grid through `_sim_soldier_square_slot`,
  and file-major reform reads `_sim_soldier_file` / `_sim_soldier_rank` directly --
  so the bearer resolves through whichever layout `Unit.formation_slots` is currently producing.

- Formation anchoring is unchanged by this design, which settles #820's first open question: the standard-bearer complements, and does not replace, the position anchor that #821 settled and #861 shipped (`Unit.ANCHOR_RANKS = 2`, the near-front anchor computed by `Unit.near_front_soldier_indices()`);
  the front-rank-midpoint anchor tried in #818 was reverted there and redirected to #821.
  Formation slots remain a pure function of `Unit.position`, facing, and soldier count (`Unit.formation_slots` -> `soldier_world_slots`), and soldier bodies are steered onto those slots -- so the bearer's own body position is an output of dressing, and using it as the dressing input would be circular.
  The carried standard is the visual embodiment of the unit's anchor, not its source of truth.

### 2. Casualty and Succession Protocol

- When the soldier designated as the standard-bearer receives fatal damage:
  1. The standard enters a transitional "fallen" state.
  2. The simulation selects the surviving front-rank soldier nearest to the fallen bearer's slot as the successor, ties broken by lowest soldier index so replays stay deterministic.
  3. The successor takes over standard-bearer status.
  4. A brief recovery delay (e.g. 1.0s) models the physical act of securing the standard, during which formation cohesion receives a minor temporary dampening.

### 3. Morale and Cohesion Coupling

- While the standard is in a dropped/unrecovered state, the unit experiences a temporary morale and cohesion penalty.

- Prompt succession restores baseline morale recovery rates.

- If a unit routs, the standard is abandoned or dropped as part of the rout's presentation.
  Contagion needs no new mechanism: `Unit._rout()` already applies a flat morale penalty to every same-team unit within `ROUT_SHOCK_RADIUS`, unconditionally and with no role for the standard, so this design adds no second shock.
  Any standard-specific morale stakes beyond the dropped-standard penalty above are Phase 4 balancing questions.

### 4. Visual Rendering Hierarchy

- The game already renders a per-unit raised standard: `UnitSprites.flag()` draws a pole, swallowtail pennant, and unit-type emblem above every live unit, serves as the click target for selection, and fades on rout (its alpha eases from full to `ROUTING_ALPHA` once the unit enters `State.ROUTING`, which the morale threshold triggers).
  A second free-floating standard per unit would create exactly the clutter and confusion #820's open question warns about.

- This design therefore relocates the existing flag rather than adding a rival: the unit standard renders at the standard-bearer's body, so the one standard is carried by a soldier instead of hovering over the formation.
  Selection click-targeting and the morale fade carry over unchanged, with the selection hitbox following the bearer.

- During the fallen/recovery window the standard renders lowered at the fallen bearer's position, giving the succession mechanic a readable visual beat.

## Implementation Roadmap

1. **Phase 1 (Design & Architecture)**:
   Finalize specifications in `docs/standard-bearer-design.md` (this document) and validate integration points.

2. **Phase 2 (Simulation Model)**:
   Implement the designated bearer slot, its re-resolution after casualty compaction, and the succession protocol in `scripts/Unit.gd`.

3. **Phase 3 (Visual Presentation)**:
   Relocate the unit standard rendering (`UnitSprites.flag()`) to the bearer's body, move the selection hitbox with it, and add the lowered fallen-standard visual.

4. **Phase 4 (Morale & Combat Balance)**:
   Integrate casualty-succession morale modifiers into `scripts/UnitCombat.gd` and `scripts/UnitMorale.gd`.
