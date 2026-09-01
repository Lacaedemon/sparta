# Historical analysis and design: Unit reshaping vs. formal maneuvers

Status: **design drafted** -- establishes historical grounding, tactical manual precedents, and simulation mechanics for unit reshaping vs. formal drill maneuvers.
Builds on [#1327](https://github.com/Lacaedemon/sparta/issues/1327) and relates to [#453](https://github.com/Lacaedemon/sparta/issues/453), [#819](https://github.com/Lacaedemon/sparta/issues/819), and [`docs/orders-queue-design.md`](orders-queue-design.md).

## Historical record and tactical manuals

Ancient military manuals (Asclepiodotus, *Tactica* X-XII; Aelian, *Tactica* XXVII-XXIX; Arrian, *Ars Tactica* 20-24; Vegetius, *De Re Militari* III.14-16) and narrative historians (Xenophon, *Cyropaedia* and *Anabasis*; Polybius XVIII) make clear that ancient armies did not reshape formations by arbitrary single-file increments:

- **Mathematical Ratios and Subunit Integrity**:
  Formations were organized into discrete files (*lochoi* of 8, 12, or 16 men in the phalanx; *contubernia* / *decuriae* of 8-10 men in the legion).
  Reshaping was executed at the file level: an entire file moved as a cohesive subunit behind or beside its neighbor.
- **Formal Maneuvers (*Explicatio* & *Duplicatio*)**:
  - *Duplicatio* (*epidiplasiasmos*): Doubling formation depth by placing odd files behind even files, reducing frontage by exactly half while doubling ranks (e.g. 16 files of 8 deep becoming 8 files of 16 deep for shock column penetration).
  - *Explicatio* (*diplasiasmos tou mekos*): Unfolding depth into frontage by stepping the rear half of files into intervals, halving depth and doubling width to match or overlap opposing battle lines.
  - *Countermarch* (*chorios*, *lakonikos*, *makedonikos*): Inverting front and rear ranks while maintaining positional frontage.
- **Chaos of Ad-Hoc Reshaping**:
  Attempting arbitrary file adjustments in the field without drill cadences broke dressing, destroyed shoulder-to-shoulder cohesion (*synaspismos*), and opened fatal seams in the line that cavalry or peltasts could exploit.

## Game Design and Mechanics Framework

To balance historical realism with player UX affordance, Sparta adopts a **tiered maneuver framework**:

### 1. First-Class Formal Drill Maneuvers (Hotkeys / Orders)

- *Duplicatio* (Halve Frontage / Double Depth): Fast, zero disorder penalty, maintains lock-step pacing.
- *Explicatio* (Double Frontage / Halve Depth): Standard drill cadence, orderly rank expansion into pre-calculated intervals.
- *Countermarch* & *About Face*: Subunit-preserving file turns without spatial displacement.

### 2. Arbitrary UI Drag Reshaping (Affordance with Realistic Cost)

- Players are allowed to arbitrarily drag frontage handles (for accessibility, intuitive map positioning, and hugging natural defiles/gaps).
- However, arbitrary single-file adjustments carry a **Cohesion & Time Cost**:
  - *Standard multiples* (divisible by base file size) execute rapidly with negligible disorder.
  - *Irregular widths* incur a transient cohesion dip and reform delay while soldiers find and assign new slot coordinates.
  - *In-Melee Reshaping*: Strictly prohibited or heavily penalized with immediate rout/flank collapse checks.

## Implementation Roadmap

1. **Phase 1 (Design & Manual Documentation)**:
   Draft historical analysis in `docs/historical-reshaping-maneuvers.md` (this document).

2. **Phase 2 (Formal Maneuver Orders Polish)**:
   Ensure `FileDoubleOrder` and `ExplicatioOrder` have dedicated UI shortcuts and distinct audio/visual feedback.

3. **Phase 3 (Cohesion & Disorder Scaling on Arbitrary Resize)**:
   Scale reform duration and momentary cohesion disruption based on deviation from standard file multipliers in `scripts/Unit.gd`.
