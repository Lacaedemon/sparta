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

What the sources say, and what they leave open.
Aelian is quoted from John Bingham's translation, *The Tactiks of Aelian* (1616), by his chapter and section numbers,
together with Bingham's own notes on the chapter, which are his rather than Aelian's
(Text Creation Partnership, [EEBO-TCP A05855](https://github.com/textcreationpartnership/A05855)).

- **Doubling the length "in number".**
  Asclepiodotus defines doubling of men "by length" (Tactics 10.17): "we interject or insert between the original files other files of equal strength,
  maintaining all the while the length of the phalanx, so that a compact order arises".
  It keeps the length: the inserted files fill the spaces between the files that were there.
  Aelian says the same (29.3): "of a front of 124 files we make a front (keeping the same ground) of 248 files,
  by inserting in the spaces betwixt file and file, some of the followers, that stood in the depth."
  Bingham's note on 29.3 says it "must be done in open order",
  and gives the drill: "These middle men with the hinder halfe file march vp to the front, & so doubling the front in number leaue yet the same measure of length."
  To undo it, "we shall command the men who have changed their position to counter-march to their original stations" (Asclepiodotus 10.20);
  Aelian has "command those, that were inserted, to countermarch to the place, they had before" (29.3).
  (Asclepiodotus in the Loeb Classical Library text, as reproduced on [LacusCurtius](https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Asclepiodotus/10*.html).)

- **Doubling "of place".**
  Asclepiodotus's doubling of place "by length" (10.18) keeps the men and opens the spacing instead:
  "when we change the above mentioned compact formation by length into a loose formation",
  to outflank the enemy or to avoid being outflanked.
  The interpolated passage Bingham prints in his note on 29.2 does it by "commanding some to turne to the Pike, some to the Target,
  till the Phalange be stretched out to a convenient length, as from 5 furlongs to 10".
  Bingham's note on 29.3 gives "two other waies, when the Phalange standeth in close order", "both which double the number, and place",
  in which the middlemen and their followers march out round one flank or both and come up level with the file leaders,
  but says "I finde them not expressed in Aelian".

- **Every second man.**
  Polyaenus (Stratagems 2.10.4) tells how Cleandridas, his phalanx drawn up deep,
  ordered the epistatai to pass over into the place of a parastates, a side-man
  (παρήγγειλε τοὺς ἐπιστάτας μεταβαίνειν εἰς παραστάτην,
  the English rendering being the sim's own),
  each rear-rank man stepping up beside the man ahead of him,
  and so made his line "much longer" (πολλῷ ... ὑπερμηκεστέραν) and outflanked the Lucanians
  (Greek text of Woelfflin and Melber, 1887, on [attalus.org](https://www.attalus.org/greek/polyaenus2.html);
  its [English translation](https://www.attalus.org/translate/polyaenus2.html) renders ἐπιστάτας as "his own officers", where Bingham's "followers" fits the drill).
  Bingham's note on Aelian 29.3 reads the same passage as "to insert the euen ranks man by man into the odde".

- **Which files stand.**
  Aelian's chapter 33 opens a phalanx it has closed.
  Closed on the right wing, "the rightwing-corner-file to stand (for it hath the right place already) and the rest proceeding on to the Target";
  "a contrarie course" for the left wing;
  and closed to the middle, "the right Diphalange turning to the Pike, and the left Diphalange to the Target",
  each wing moving out away from the middle.
  Bingham's note on chapter 33 has "The files next the middle section stand fast",
  but its word of command then turns "the right wing ... to the Target, the left to the Pike", each wing inward,
  against Aelian's text; the sim follows the text.

- **The names.**
  Asclepiodotus names the half of a file the half-file (*hemilochion*) and its leader the half-file leader (*hemilochites*),
  and calls the file leader a front-rank man (*protostates*) and the man behind him a rear-rank man (*epistates*),
  "so that in the whole file there comes first a front-rank-man, then a rear-rank-man, then successively a front-rank-man and a rear-rank-man, and so on":
  every second man of a file is an epistates
  (Tactics 2.2-2.3, [LacusCurtius](https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Asclepiodotus/2*.html)).

- **Xenophon**, Cyropaedia 2.3.21 (translated by Henry Graham Dakyns, [Project Gutenberg](https://www.gutenberg.org/ebooks/2085)),
  describes a brigadier "marching his regiment up from the river back to their quarters",
  its companies in single file, and unfolding them into line as they go.
  At the word "Companies in twos" "the captains-of-ten came into line",
  and at "Companies in fours" the captains of five.
  It is a drill done on the march (#1967).
  Xenophon does not say on which side the rear parts come up, or that the front halts:
  that each captain leads his part up beside the part ahead of it is an inference from "came into line".

The sim models two drills, chosen on the frontage-doubling order (`UnitFormation.ExplicatioDrill`).
The B key gives the half-file drill.
No key or order gives the alternate-rank drill yet ([#1969](https://github.com/Lacaedemon/sparta/issues/1969)).

- **Half-file** (the default, Bingham's note on Aelian 29.3).
  Each file's rear half marches up the interval beside its own file, led by its hemilochites, the man who headed the rear half.
  The front half keeps its ranks and stays on the line it stood on, opening out sideways.

- **Alternate rank** (every second man, Polyaenus 2.10.4).
  Every epistates, every second man of the file counting the file leader as the first, steps into the interval beside the man who stood ahead of him,
  led by the first of them, the man behind the file leader.
  Polyaenus does not say on which side.
  The sim uses the same side as the half-file drill.

In both, the sim keeps the file pitch, so the front's length doubles with the number of its files.
Aelian's doubling in number keeps the length, and fills the spaces of an open order.
The sim's widen is that insertion with the opening out of 10.18 done at once,
so it rests on 10.18 rather than 10.17,
on Polyaenus, whose line grew "much longer",
and on Xenophon's company, whose line grows as each part comes up beside the part ahead of it.

Which files stand follows Aelian 33.
Widened about the middle (B), the files next to the middle stand and each wing opens outward.
Of an even number of files the two middle files stand, and of an odd number the middle file and the file on its left.
Every interval of the left wing opens on the left of its file, and every interval of the right wing on the right.
With an even number of files the two flanks step out alike.
With an odd number the middle file belongs to the right wing, which gains one file more, so its flank steps out one file pitch farther:
9 files doubled to 18 move the left flank out 4 file pitches and the right 5.
Held on the right flank (Shift+B), the right corner file stands and every interval opens on the left;
held on the left (Ctrl+B), the mirror.
The leader of the file that stands is the guide the front rank dresses on.
Chapter 33 is about opening a closed phalanx, not about doubling it, so applying it to the explicatio is the sim's inference.

Nobody walks to a slot laid out from the unit's centre: each man follows a man he can see (`SoldierFollow`).

- Every man behind the head of his file keeps a rank's distance behind the man ahead of him, so nobody passes him.

- The leader of each file that stays dresses on the next file leader toward the file that stands,
  and takes his depth from the guide, who holds the ground he stood on.
  If the guide falls and nobody closes up into his place,
  the leader of the nearest file that stays becomes the guide where he stands.
  So the front rank stays on the line it stood on while it opens out sideways.

- The man whose role it is to lead a new file up an interval (the hemilochites, or the first epistates, behind the file leader) comes up beside the leader of the file he opened from.
  He steps out of his file before he comes up,
  and comes up only while nobody of another file stands in his lane,
  from level with him to a rank ahead,
  within a body's width of his place's line (or within a file pitch, where the files stand closer than a body's width).
  The men of his column behind him do the same.
  Only a man with the role leads: the head of an interval without it stays where he is.

- If a leader falls, the man behind him takes his place and his role.
  The roles belong to the files the explicatio dealt, and a later re-deal of the files, such as a duplicatio, takes them away.

- Each man stops following once he has taken his place and the man he follows has taken his:
  when he stands within the reform settle distance of his place,
  or when a man of another regiment presses on him so he can come no nearer
  (a man in an interval, only once his lane is empty),
  or, for a man in an interval, when every man standing in his lane has stopped following, so it will open no further.
  From then on he keeps to his place as he would to his slot.

The block's position is read off its men while the drill runs.
When no man is still following, the drill ends, and the slot grid is laid on the men where they stand.

The drill is for a block standing still, from wherever its men stand, settled on their slots or not.
A block on the march widens with the lateral deal ([#1967](https://github.com/Lacaedemon/sparta/issues/1967)),
and so does any other change of width that happens to double the files (a drag or [ ] resize, a form-up),
and so does a block whose grid stands turned from its men's facing, as an about-face leaves it,
since its file leaders stand behind its men and its files would cross
([#1968](https://github.com/Lacaedemon/sparta/issues/1968)).
The turn-and-unfold combo's widen doubles the turned block's files against the width it had before the turn,
so it is the drill only for a block as deep as it was wide (#1967).
A man held off his place by terrain, rather than by another regiment, keeps the drill running (#1967).

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
