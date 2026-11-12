# Historical analysis and design: Unit reshaping vs. formal maneuvers

Status: **design drafted** -- establishes historical grounding, tactical manual precedents, and simulation mechanics for unit reshaping vs. formal drill maneuvers.
Builds on [#1327](https://github.com/Lacaedemon/sparta/issues/1327) and relates to [#453](https://github.com/Lacaedemon/sparta/issues/453), [#819](https://github.com/Lacaedemon/sparta/issues/819), and [`docs/orders-queue-design.md`](orders-queue-design.md).

## Historical record and tactical manuals

Ancient military manuals (Asclepiodotus, *Tactica* X-XII;
Aelian, *Tactica* XXVII-XXIX;
Arrian, *Ars Tactica* 20-24;
Vegetius, *De Re Militari* III.14-16) and narrative historians (Xenophon, *Cyropaedia* and *Anabasis*;
Polybius XVIII) make clear that ancient armies did not reshape formations by arbitrary single-file increments:

- **Mathematical Ratios and Subunit Integrity**:
  Formations were organized into discrete files (*lochoi* of 8, 12, or 16 men in the phalanx;
  *contubernia* / *decuriae* of 8-10 men in the legion).
  Reshaping was executed at the file level: an entire file moved as a cohesive subunit behind or beside its neighbor.

- **Formal Maneuvers (*Explicatio* & *Duplicatio*)**:
  - *Duplicatio* (*epidiplasiasmos*): Doubling formation depth by placing odd files behind even files, reducing frontage by exactly half while doubling ranks (e.g. 16 files of 8 deep becoming 8 files of 16 deep for shock column penetration).

  - *Explicatio* (*diplasiasmos tou mēkous*, doubling of the length): Unfolding depth into frontage by bringing part of each file up into the interval beside it, halving depth and doubling width to match or overlap opposing battle lines.
    See [The explicatio drills](#the-explicatio-drills) for the sources and for the two drills the sim models.

  - *Countermarch* (*chorios*, *lakonikos*, *makedonikos*): Inverting front and rear ranks while maintaining positional frontage.

- **Chaos of Ad-Hoc Reshaping**:
  Attempting arbitrary file adjustments in the field without drill cadences broke dressing, destroyed shoulder-to-shoulder cohesion (*synaspismos*), and opened fatal seams in the line that cavalry or peltasts could exploit.

## The explicatio drills

What the manuals say, and what they leave open:

- Asclepiodotus defines doubling "by length" (Tactics 10.17): "we interject or insert between the original files other files" of equal strength.
  He does not say where the inserted files come from, and his doubling "of men" may add men rather than redeal them.
  Doubling "of place" (10.18) keeps the men and opens the spacing instead.
  To undo a doubling, "we shall command the men who have changed their position to counter-march to their original stations" (10.20).
  (Loeb Classical Library text, as reproduced on [LacusCurtius](https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Asclepiodotus/10*.html).)
- Asclepiodotus also names the half of a file the half-file (*hemilochion*) and its leader the half-file leader (*hemilochites*), and the man behind each file leader the rear-rank man (*epistates*) (Tactics 2.2-2.3, [LacusCurtius](https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Asclepiodotus/2*.html)).
- Xenophon describes the drill itself (Cyropaedia 2.3.21, trans. H. G. Dakyns, [Project Gutenberg](https://www.gutenberg.org/ebooks/2085)).
  A company marching in single file unfolds into line: at the word "Companies in twos" "the captains-of-ten came into line", each leading his part of the file up beside the part ahead of it, and at "Companies in fours" the captains of five do the same.
  The leader of each rear part brings it up, and the front stays where it is.

The sim models two drills, chosen on the frontage-doubling order (`UnitFormation.ExplicatioDrill`; the B key gives the half-file drill):

- **Half-file** (the default, after Xenophon's drill and Asclepiodotus's half-file).
  Each file's rear half marches up the interval beside its own file, led by its hemilochites, the man who headed the rear half.
  The front half keeps its ground and its ranks.
- **Alternate rank** (every second man).
  Each epistates, and every second man after him, steps into the interval beside the man who stood ahead of him.
  Bingham's notes on Aelian, chapter 29 (1616), list this way of doubling the front.
  Its ancient source is not verified: Aelian 29 and Arrian's Tactica have not been checked.

In both drills the front rank holds its ground, and the men who change file step sideways into the interval on the spear side (the right; the side away from a held flank when the widen is anchored) before they march up it.
Each column follows its leader in: no man steps into the interval before the man ahead of him, and no man overtakes him.
If the leader falls, the man behind him takes his place and his role.
Any other change of width that happens to double the files (a drag or [ ] resize, a form-up) is not a drill, and keeps the lateral deal.

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
