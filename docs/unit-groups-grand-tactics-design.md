# Grand tactical architecture: Unit-group line management and line relief

Status: **design drafted** -- establishes grand tactical battle line definitions, automated reserve gap plugging, and multi-unit line relief mechanics.
Builds on [#1033](https://github.com/Lacaedemon/sparta/issues/1033) and connects to [#819](https://github.com/Lacaedemon/sparta/issues/819), [#1327](https://github.com/Lacaedemon/sparta/issues/1327), and [`docs/acies-triplex-design.md`](acies-triplex-design.md).

## Concept and Historical Motivation

In ancient battles (Cannae, Zama, Cynoscephalae, Pharsalus), tactical cohesion existed at two fractal levels:

- **Micro-tactical (Unit level)**:
  Individual soldiers fill front-rank casualties from rear ranks and maintain file dressing.

- **Grand tactical (Unit-group / Wing level)**:
  Subcommanders (*legati*, *tribuni*, *hipparchs*) manage an entire battle line (*acies*).
  When a front-line century or syntagma breaks or is exhausted, fresh reserve units (*principes*, *triarii*, or tactical reserve cohorts) plug the breach or execute a coordinated passage of lines (*line relief*).

## Unit-Group Battle Line Model

### 1. Conceptual Battle Line Representation

A `UnitGroup` defines a structured multi-unit frontage:

- **Primary Line (`LineTier.FRONT`)**: Units actively holding frontage and absorbing shock.

- **Secondary / Support Line (`LineTier.SUPPORT`)**: Units staggered 30m-60m behind primary intervals, ready to advance through intervals.

- **Tactical Reserve (`LineTier.RESERVE`)**: Units held behind the center or flanks under commander hold orders.

### 2. Gap-Plugging Behavior (Emergent Line Preservation)

- **Gap Detection**:
  When a front-line unit routs, shatters, or is knocked out of cohesion, the unit group evaluates the resulting gap width in the battle line.

- **Reserve Dispatch**:
  The nearest unengaged reserve unit in `LineTier.SUPPORT` or `LineTier.RESERVE` is assigned a fast advance order to the anchor coordinates of the lost unit, restoring line continuity before enemy penetration occurs.

### 3. Grand-Tactical Line Relief (Pre-Rout Unit Rotation)

- **Threshold Monitoring**:
  When a front unit drops below critical stamina/morale thresholds (e.g. fatigue > 75% or strength < 50%) while holding ground, the group commander initiates unit rotation.

- **Corridor Passage**:
  The support unit executes a synchronized `RELIEF` order, opening file corridors and exchanging places with the exhausted unit, which withdraws safely to the rear reserve tier to rest and recover morale.

## Implementation Roadmap

1. **Phase 1 (Design & Architecture Doc)**:
   Document the unit-group battle line hierarchy and reserve rotation dynamics in `docs/unit-groups-grand-tactics-design.md` (this document).

2. **Phase 2 (Unit Group Gap Detection System)**:
   Implement line boundary query algorithms in `scripts/UnitGroup.gd` tracking slot vacancies and neighboring flank integrity.

3. **Phase 3 (Subcommander Reserve Dispatch & Automated Relief)**:
   Connect AI subcommander doctrine triggers to issue automated gap-filling and line relief orders.
