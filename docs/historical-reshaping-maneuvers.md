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
  Bingham's note on chapter 33, restoring a phalanx closed to the middle, reads
  "The files next the middle section stand fast, and the right wing turne faces to the Target, the left to the Pike, and moue on till the first distance recouered",
  each wing turning inward, against Aelian's text.
  For a phalanx closed to a wing the note agrees with the text:
  "The right-wing-corner-file stand firme;
  the rest turne faces to the Target, and proceede to your first distance."
  The sim builds both readings of the middle (see the inward reading below).

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
  It is a drill done on the march ([#1967](https://github.com/Lacaedemon/sparta/issues/1967)).
  Xenophon does not say on which side the rear parts come up, or that the front halts:
  that each captain leads his part up beside the part ahead of it is an inference from "came into line".

- **Spacing.**
  Asclepiodotus (4.1) gives three orders of spacing:
  the most open, "in which the men are spaced both in length and depth four cubits apart",
  the most compact, "with locked shields", a cubit apart "on all sides",
  and the intermediate, "also called a 'compact formation'", two cubits apart "on all sides"
  ([LacusCurtius](https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Asclepiodotus/4*.html)).
  The sim's loose, normal and tight orders stand at four, two and one times its authored pitch.

The sim models two drills, chosen on the frontage-doubling order (`UnitFormation.ExplicatioDrill`).
The B key gives the half-file drill until Alt+B steps to the alternate-rank drill.

- **Half-file** (the default, Bingham's note on Aelian 29.3).
  Each file's rear half marches up the interval beside its own file, led by its hemilochites, the man who headed the rear half.
  The front half keeps its ranks and stays on the line it stood on, opening out sideways.

- **Alternate rank** (every second man, Polyaenus 2.10.4).
  Every epistates, every second man of the file counting the file leader as the first, steps into the interval beside the man who stood ahead of him,
  led by the first of them, the man behind the file leader.
  Polyaenus does not say on which side.
  By default the sim uses the same side as the half-file drill.

Where the sources differ or are silent, each reading is its own variant, with a short name, chosen on the same order as the drill.
Every variant works with both drills.
The B key deals the chosen reading, the defaults until Alt+B (drill), Alt+Shift+B (side) or Alt+Ctrl+B (ground) steps one;
the order (`Battle.enqueue_file_double`, `Order.new_file_double`) and the replay entry (`"explicatio_side"`, `"explicatio_ground"`) carry each one.

Which side of each file its interval opens on (`UnitFormation.ExplicatioSide`):

- **`outward`** (the default, Aelian 33's text).
  Widened about the middle (B), the files next to the middle stand and each wing opens outward.
  Of an even number of files the two middle files stand, and of an odd number the middle file and the file on its left.
  Every interval of the left wing opens on the left of its file, and every interval of the right wing on the right.
  With an even number of files the two flanks step out alike.
  With an odd number the middle file belongs to the right wing, which gains one file more, so its flank steps out one file pitch farther:
  9 files doubled to 18 move the left flank out 4 file pitches and the right 5.
  Held on the right flank (Shift+B), the right corner file stands and every interval opens on the left;
  held on the left (Ctrl+B), the mirror.

- **`inward`** (Bingham's note on Aelian 33).
  Widened about the middle, every interval of the left wing opens on the right of its file, toward the middle, and every interval of the right wing on the left.
  The intervals of the two files next to the middle then both open between them,
  so only one of the two can stand fast:
  which one is the sim's choice, not the note's.
  The right-hand one stands, as the guide does in the outward reading, and the left-hand one steps out two file pitches to make room.
  9 files doubled to 18 move the left flank out 5 file pitches and the right 4.
  Held on a flank there is no inward reading, since the note's words of command for a wing move "the rest" to the Target as the text does,
  so an inward widen held on a flank is the outward one.

- **`spear_side`** and **`shield_side`** (where Polyaenus 2.10.4 and Xenophon are silent).
  Every interval opens on the right of its file (the spear, or Pike, side), or every one on the left (the shield, or Target, side), whichever wing it is in.
  The file that stands is the same as in the outward reading: the files next to the middle, or the corner file of a held flank.
  9 files doubled to 18 about the middle move the left flank out 4 file pitches and the right 5 on the spear side, and the left 5 and the right 4 on the shield side.
  Held on the right flank, the shield side is the outward reading,
  and the spear side opens the standing corner file's interval beyond it, so the held flank steps out one file pitch;
  held on the left, the mirror.

Whether the doubled line keeps its pitch or its ground (`UnitFormation.ExplicatioGround`):

- **`lengthen`** (the default).
  The sim keeps the file pitch, so the front's length doubles with the number of its files.
  Aelian's doubling in number keeps the length, and fills the spaces of an open order.
  This widen is that insertion with the opening out of 10.18 done at once,
  so it rests on 10.18 rather than 10.17,
  on Polyaenus, whose line grew "much longer",
  and on Xenophon's company, whose line grows as each part comes up beside the part ahead of it.

- **`same_ground`** (Asclepiodotus 10.17, Aelian 29.3).
  The line keeps its length.
  The block closes one order of spacing as its files double, open order into compact and compact into locked shields, on both axes (Asclepiodotus 4.1),
  so the file pitch halves.
  Asclepiodotus inserts the new files "between the original files":
  every original file keeps its place, file leader included,
  and each new file comes up in the gap beside the file it opened from.
  That needs every interval on the same side of its file, so the same ground takes the spear side or the shield side, the sources saying neither.
  The outward reading would leave the two middle original files with no gap between them, and the inward reading would leave two gaps there,
  so under either some original files could not keep their places.
  Asked for either in a widen about the middle (B), the sim takes the spear side instead.
  That default is the sim's choice.
  A widen held on a flank (Shift+B, Ctrl+B) already opens every interval away from the held flank, outward or inward,
  so it keeps that side and the held flank keeps its ground.
  The one new file beyond the last original file then lengthens the line by half the old pitch on the open flank,
  on the right on the spear side and on the left on the shield side, which is also the sim's inference.
  Bingham's note on 29.3 says it "must be done in open order".
  A block already at locked shields, or in a shield wall, testudo or square, has no closer order to take,
  so it cannot keep its ground: the order is not issued to it.

When the files open, against when the men step into the intervals (`ExplicatioOpening.Reading`):

- **`together`** (the default, the sim's own inference).
  The files open out sideways while the men who change file step out and come up the intervals.

- **`files_first`**.
  Each old file opens out to its distance as a whole, every man keeping his place in it behind the man who stood ahead of him,
  and only once its file leader has taken his place do its men step into the interval beside it and come up.
  Asclepiodotus 10.17 inserts the new files "between the original files", so the files already stand apart,
  and Bingham's note on Aelian 29.3 says the insertion "must be done in open order".
  In Aelian 33 the opening is the files moving out to their distance, "the rest proceeding on to the Target",
  and in Bingham's note on it they "moue on till the first distance recouered".
  The lengthening explicatio opens and inserts in one drill,
  so doing its opening first is the sim's inference from those passages.
  The files open one after another, the files next to the one that stands first and the flank files last, since each file leader dresses on the next one in toward it.
  In the alternate-rank drill this keeps every file leader on the line he stood on.
  Together, each epistates steps out from right behind his file leader while the leader is still opening out and presses him ahead:
  1.07 wu for 140 Spearmen 9 files by 16 widened about the middle, measured 2026-11-14.
  But files first does not keep the front as a whole on its line.
  The epistates coming up into line beside his file leader runs past it before he settles, 1.24 to 1.27 wu, measured the same day, which is further than the file leaders run ahead together
  ([#1989](https://github.com/Lacaedemon/sparta/issues/1989)).
  So the front's run ahead in the alternate-rank drill moves from the file leaders to the column leaders and is not removed.

Arrian's *Tactica* (25.3 to 25.5, Hercher's Greek text on [classics.andrewgadsden.com](https://classics.andrewgadsden.com/library/arrian/tactica/25)) runs the other way:
the men from the depth are first put into the spaces between the hoplites, and the front "is made dense" (πυκνοῦται),
and only to double the ground as well are they then ordered to wheel out (ἐξελίσσεσθαι), half to the right and half to the left.
Asclepiodotus 10.18 likewise doubles the ground of an inserted line "when the interjected men counter-march by rank".
That order is the same-ground reading followed by an opening of the order, both of which the sim already deals,
so it is not a third reading here.

The leader of the file that stands is the guide the front rank dresses on.
Chapter 33 is about opening a closed phalanx, not about doubling it, so applying it to the explicatio is the sim's inference, in every reading.
Xenophon's drill on the march (Cyropaedia 2.3.21) is not built as a variant yet:
the sim does not deal the drill to a block on the march at all, and a man following a man on the march is the work of [#1967](https://github.com/Lacaedemon/sparta/issues/1967).

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
  within the lesser of a body's width and the file pitch less the reform settle distance, measured from his place's line
  (8 wu at the 9 wu pitch of close order, a body's width in open order).
  The men of his column behind him do the same.
  Only a man with the role leads: the head of an interval without it stays where he is.

- If a leader falls, the man behind him takes his place and his role.
  The roles belong to the files the explicatio dealt, and a later re-deal of the files, such as a duplicatio, takes them away.

- Each man stops following for good once he has taken his place and the man he follows has stopped:
  when he stands within the reform settle distance of his place,
  or, for a man in an interval, when every man standing in his lane has stopped following, so it will open no further.
  From then on he keeps to his place as he would to his slot.

- Every other man is judged afresh on every tick, and keeps following.
  While the man he follows has stopped or stands, he stands too, for that tick,
  when he is on his place,
  when a man of another regiment presses on him (a man in an interval, only once his lane has room for him),
  when he is held: the step he took toward his place brought him no nearer it and he is going toward it no faster,
  so something he cannot pass, a face of rock or a friend's body, holds him off his place,
  or when every man of the lane he waits on has stopped or stands.
  In the files-first reading a man whose old file has not opened yet stands once the man ahead of him in it stands.
  A man still shedding a way he carried off his place gains pace toward it each step, so he is not held.
  A man who stands goes on pressing for his place, and on the tick nothing holds him he is going again, and so are the men behind him.
  A friendly block that presses men and then marches off leaves them to go on to their places.
  Only taking one's place is for good.
  When the drill ends the grid is laid on the men who reached their places,
  and a held man's slot is then the place he could not reach.
  The men whose slots lie on the rock press on for them, and the block walks back after them:
  that is a regression of the drill now ending, which waits on relational formation keeping
  ([#1954](https://github.com/Lacaedemon/sparta/issues/1954), [#1990](https://github.com/Lacaedemon/sparta/issues/1990)).
  So each file is dressed from the front back, each man once the man ahead of him is,
  by what each man sees of his own place and his own way to it.
  Nothing measures the block against its slots, and nothing times it.

The block's position is read off its men while the drill runs.
When every man is done, the drill ends, and the slot grid is laid on the men where they stand.

The drill is for a block standing still, from wherever its men stand, settled on their slots or not.
A block on the march widens with the lateral deal ([#1967](https://github.com/Lacaedemon/sparta/issues/1967)),
and so does any other change of width that happens to double the files (a drag or [ ] resize, a form-up),
and so does a block whose grid stands turned from its men's facing, as an about-face leaves it,
since its file leaders stand behind its men and its files would cross
([#1968](https://github.com/Lacaedemon/sparta/issues/1968)).
The turn-and-unfold combo's widen doubles the files the turned block stands on across its new facing,
its old ranks, dealt afresh from where its men stand, so it is the drill for a block of any depth.

## The duplicatio in reverse

A block whose files an explicatio dealt halves its front (N) by undoing that explicatio.
Asclepiodotus 10.20 and Aelian 29.3, quoted above under the doubling "in number", undo the doubling by sending the men who changed their position back to their original stations.
Both undo the insertion on the same ground (10.17) and the compact formation it made.
Undoing by the same drill a widen that also opened the files out, the sim's default, is the sim's inference.
Neither source says how the files that stayed close up, or how a man walks back.
In the same section Asclepiodotus notes that some condemn such doublings, "especially when the enemy is near".

What the sim builds (`DuplicatioDrill`, `Unit._begin_duplicatio`):

- **Who goes back where** is read off the men, not chosen.
  The explicatio left each man his file, rank and role, and the man with a role heads his interval.
  A man with the epistates role says every second man went up, so each file and its interval interleave again, the file's men at the even ranks and the interval's at the odd ones.
  Otherwise the half-file went up, and the interval falls in behind the men of its file.
  A file a casualty has shortened still closes into one unbroken file.

- **How they go back.**
  Each man follows the man who will stand ahead of him in his old file, a rank behind, and covers his file leader.
  He takes his line across his front from where his file leader stands, so a file closes only as its leader does and none of its men cuts ahead of him into the next file's way.
  He steps across to his file's line only while nobody of the other part of the block (the men who went up, or the men who stayed) stands level with him between him and that line.
  Until then he keeps his own line and drops back along it.
  So the men of each interval fall back down it in column and step in behind the man they follow once they are behind him.
  The files that stayed close up only once the intervals beside them are empty.
  That walk, facing front, is the sim's inference, and the default.
  The sources say "countermarch", and a countermarch turns the men about, so the sim also builds a reading with the men facing about, below.

- **The face-about reading** (`DuplicatioMarch.FACE_ABOUT`, chosen by Alt+N before N).
  Each man of an interval faces about where he stands, marches back down his interval with its rear man leading, and faces front again on his station.
  The men who stayed in the files do not turn: they did not change their position.
  He turns through his own facing at the drill's turn rate (`Unit.CONVERSIO_TURN_RATE`, half a second for a half turn), through his right when he faces straight away from where he turns to, never in a snap.
  He faces about until he has taken his station, then turns front again.
  The column's rear man leads it: each man with a man of his own column to stand right behind him follows that man, a rank ahead of him, and the others follow the nearest man of their file ahead of them who stayed (`DuplicatioMarch.march_plan`).
  So after the half-file drill the column's rear man marches back until he stands as many ranks behind his file's last man as his column has men, and the men before him follow him down.
  After the every-second-man drill each man follows the man he will stand behind, as in the walk.
  He covers the same file leader and waits on the same men as in the walk, and steers by his file's front, which he reads off his file leader, since his own facing is turned about.
  Facing the way he goes, he is not held to the slower pace of a man stepping backward (`back_speed_fraction`), so the men are back sooner than in the walk.
  If the drill is cut short, each man still turned turns on to the front at the same rate.

  Why this reading, and why only this one.
  Asclepiodotus describes three kinds of countermarch (10.13 to 10.15), each done by file or by rank.
  10.16 says when the countermarch by rank is used; it adds no fourth kind.
  In the Macedonian the file leaders hold their ground and the files end on the ground before them;
  in the Laconian the file closers hold theirs and the files end beyond them;
  in the Cretan, or Persian, the leader and the closer change places and the files keep their ground.
  Each turns a file to face the other way with its leader at its new head.
  Neither 10.20 nor Aelian 29.3 says which the men of an interval perform.
  An interval's men end on stations behind them, facing front, in the order they stood: any of the three, done once, would leave the column facing the rear with its head at the far end, so no man would stand on his own station.
  The face-about reading is none of the three.
  It keeps what every countermarch ends with, each man facing about, and keeps the order of the column, so its rear man leads it back: that is the sim's inference.
  A column could also come back in order by doing two countermarches, the Laconian onto the ground behind its rear and then the Cretan on its stations to face front, its men passing each other in the interval.
  That reading is not built ([#1987](https://github.com/Lacaedemon/sparta/issues/1987)).

- **The front rank holds its line.**
  The file that stands is the one the explicatio stood on, which the block records with the ground: the middle file after a widen about the middle, or the held flank's corner file after one held on a flank, so a held flank does not move on the way back either.
  Its leader is the guide, and every file leader dresses his depth on him.
  If that whole file falls, the leader of the nearest file left becomes the guide.
  He holds the ground he stands on when he takes over, as in the explicatio, and the other files close on him by their relations.

- **The ground the explicatio kept.**
  The men go back to their original stations (10.20), so the duplicatio undoes whichever ground the explicatio kept, and the order does not choose it.
  The block records that ground when the explicatio is dealt.
  An explicatio that lengthened the line is undone by closing the files on the file that stands, so the line halves its length again.
  No source describes that reverse, so it is the sim's inference.
  An explicatio on the same ground (Asclepiodotus 10.17, Aelian 29.3) is undone by sending the inserted men back out of the gaps.
  The files that stayed keep their places, and the block opens one order of spacing again, locked shields into compact and compact into open order (Asclepiodotus 4.1).
  A block that has since changed to an order with no opener line order to take keeps its pitch and closes its files instead: that is the sim's choice.
  Undoing an explicatio on the other ground than it kept would leave the line at another spacing and length than it had, so that is not offered.

The drill is for a block standing still, square to its facing, and not fighting, as the explicatio is.
A block no explicatio dealt, or one whose files a re-deal has taken since, narrows with the lateral deal, as before.
The sources describe no other drill for it.
An about-face or countermarch since the explicatio turns the block about, so the head of each interval stands at its rear.
While the block stands turned its grid faces away from its men, and it is not undone (`Unit.explicatio_undoable` reads the turned grid).
The reform that follows the turn takes the roles away, on a full grid as on one with a short rear rank, and the block then narrows with the lateral deal too.
If an explicatio or duplicatio is still under way at that reform, the roles are kept for it, but a block whose grid is still mirrored by the turn is not undone.

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
