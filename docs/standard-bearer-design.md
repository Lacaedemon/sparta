# Design note: Standard-bearer (formation anchor, visual hierarchy, and casualty succession)

Status: **design drafted** -- establishes architectural and historical grounding for the regimental standard-bearer mechanic.
Builds on [#820](https://github.com/Lacaedemon/sparta/issues/820) and ties into [#818](https://github.com/Lacaedemon/sparta/issues/818) position-anchoring.

## Historical background

In Mediterranean ancient warfare, unit standards served as the primary physical anchor for formation alignment and tactical command:

- **Roman Legionary Standards**:
  Each century or maniple had a *signifer* carrying the century's *signum* (spear topped with a bronze hand, wreaths, and phalerae discs).
  The legion had an *aquilifer* carrying the sacred *aquila* (eagle), and cavalry units had an *imaginifer* or *vexillarius* carrying the *vexillum*.

- **Tactical and Spatial Dressing**:
  Soldiers in rank-and-file did not align by abstract global coordinates;
  they aligned ("dressed") their files and ranks by referencing the standard-bearer positioned in the front rank center or flank.
  The standard was tall enough to remain visible above helmets and shield walls.

- **Succession and Morale**:
  Losing a standard was a catastrophic disgrace and tactical failure, often precipitating routs.
  If a standard-bearer fell in combat, the nearest surviving soldier (often a junior officer such as an *optio* or veteran front-ranker) immediately picked it up to maintain the line and prevent collapse.

- **Greek and Hellenistic Standards**:
  Phalanxes used distinct pennants (*semeia*) and horn/trumpet signalers (*salpingktes*) stationed near the file leaders (*lochagoi*) to dictate advance pace and formation density.

## Architecture and Core Mechanics

### 1. Designated Soldier Index and Positioning

- Each regiment (`Unit.gd`) designates one soldier slot as the active standard-bearer (`standard_bearer_idx: int = 0`).

- By default, the bearer is placed in the center file of the front rank (`rank = 0, file = floor(frontage / 2)`).

- The soldier's local position serves as the physical reference anchor for rank-and-file dressing updates.

### 2. Casualty and Succession Protocol

- When the soldier designated as the standard-bearer receives fatal damage:
  1. The standard enters a transitional "fallen" state.
  2. The simulation selects the nearest surviving front-rank soldier as the successor.
  3. The successor takes over standard-bearer status.
  4. A brief recovery delay (e.g. 1.0s) models the physical act of securing the standard, during which formation cohesion receives a minor temporary dampening.

### 3. Morale and Cohesion Coupling

- While the standard is in a dropped/unrecovered state, the unit experiences a temporary morale and cohesion penalty.

- Prompt succession restores baseline morale recovery rates.

- If a unit routs, the standard is abandoned or dropped, triggering rout-contagion checks in adjacent friendly formations.

### 4. Visual Rendering Hierarchy

- Standard-bearer soldiers render a distinct standard icon/mesh above their figure.

- The standard marker is visually decoupled from UI selection banners/flags (which indicate player selection state, order mode, or target reticles), preventing visual clutter.

## Implementation Roadmap

1. **Phase 1 (Design & Architecture)**:
   Finalize specifications in `docs/standard-bearer-design.md` (this document) and validate integration points.

2. **Phase 2 (Simulation Model)**:
   Implement `standard_bearer_idx`, succession logic, and soldier dressing offsets in `scripts/Unit.gd`.

3. **Phase 3 (Visual Presentation)**:
   Add standard-bearer rendering pass and distinct visual standard assets.

4. **Phase 4 (Morale & Combat Balance)**:
   Integrate casualty-succession morale modifiers into `scripts/UnitCombat.gd` and `scripts/UnitMorale.gd`.
