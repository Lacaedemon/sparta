# Design note: subdividing units into subunits

Status: **design only** --- no code lands with this note.
It answers [#1218](https://github.com/Lacaedemon/sparta/issues/1218) so an
implementation can follow, and lays out a phased plan whose first slice is
small enough to ship on its own.
Nothing here changes the running simulation yet.

## The question

[#1218](https://github.com/Lacaedemon/sparta/issues/1218) asks for two things:

1. Different unit types get **different subunit structures** --- files, ranks, or
   quadrants --- as specified by historical records, with recorded reasoning
   where the record is silent.
2. Unit-level behaviours such as reforming, after casualties or on a commander's
   order, get implemented **through subunit-level behaviours**.
   The issue's own worked example: a reform into a longer, narrower formation
   could convert one or more flank files into a back rank and march that file
   around the edge of the rest of the unit into its rear.

The second half is the load-bearing one.
The first is a data question with a bounded answer; the second is a claim
about where maneuver logic lives, and it is the same "bottom-up physics, no
top-down gimmicks" principle `PLAN.md` already applies to combat and movement,
applied to organisation.

## What we do today (verified against the code)

- **One grouping exists, and it is the file.** `_sim_soldier_file` and
  `_sim_soldier_rank` (`scripts/Unit.gd`) are persistent per-soldier ids ---
  which column a man belongs to, and how deep he stands in it.
  They are dealt by `_ensure_file_assignment`, maintained through a death by
  `SoldierMelee.reap`, and serialized into the state dump, so they already
  survive casualties and replay.
- **No unit type declares a structure.** A type is a dictionary literal in
  `Battle._default_loadout()`.
  It already carries structural *geometry* --- `file_pitch_m`, `rank_pitch_m`,
  `formation`, `file_major_reform_default` --- but nothing about organisation.
  Every type gets the same implicit answer.
- **The file count is derived from the roster size, and file depth is a
  remainder.** `UnitFormation.frontage(u)` reads `_files(u.max_soldiers)`, which
  is `ceil(sqrt(max_soldiers * 1.7))` (`FORMATION_ASPECT`) --- the type's
  *full-strength* size, not its live count, so the width holds steady as men
  fall and steps down a single notch only once `_ranks_closed` crosses the
  close-the-ranks threshold.
  `file_capacities(count, files)` then divides the live count across that width
  and spreads the remainder over a centred span.
  So the width is chosen first, from a number fixed at spawn, and the depth is
  whatever is left over.
- **Only one of three layout branches preserves identity.**
  `Unit.formation_slots()` dispatches three ways: the square branch pairs men
  onto a `ceil(sqrt(n))` grid by proximity and bypasses file identity entirely;
  the file-major branch is the one that keeps it; the row-major fallback
  recomputes from the live count every tick and reassigns by raw array index.
  Every loadout type defaults to FILE_MAJOR and `disciplined` defaults to true,
  so the fallback is reached only by an explicit scenario override.

## The inversion this note is about

Armies derived the footprint from the subunit.
We derive the subunit from the footprint.

A Hellenistic subunit had a **declared size** --- the manuals define the file
as the primitive and build every larger body by doubling its frontage, at
constant depth --- so a phalanx's width was the consequence of how many files
it fielded.
We do the reverse: `_files()` picks a file *count* from the roster size and an
aspect constant, and a man's file depth is a division remainder.
Nothing in the game has a doctrinal size to hold.

The consequence is visible in how casualties are absorbed.
Because the width is pinned to `max_soldiers`, losses come out of *depth*:
files shorten, and the frontage holds until the close-ranks notch fires.
Under a declared size the natural behaviour is the opposite --- a unit that
has lost a subunit's worth of men fields one fewer subunit and narrows --- so
the two models disagree about what a mauled unit looks like, not merely about
how it is labelled.

Note what the sources do *not* say here, since it would be easy to overclaim.
Asclepiodotus 3 describes the file-closer keeping his file aligned and
compelling the men to close up, and the second-rank man stepping forward when
the file-leader falls.
That is closing **within** a file.
No source consulted for this note describes a depleted file being collapsed
into its neighbours, so the narrowing behaviour above is an inference from the
declared-size model, not an attested drill.

This is the same shape of shortcut `docs/square-formation-design.md` names as
its gap 3, one level up.
There the criticism is that `ceil(sqrt(n))` picks the square's footprint first
and fits men to it; here the footprint of the *line* is picked first and the
file falls out of it.
Both make shape an input where it should be an output.

The current numbers, at full strength, computed from `_files()` and
`file_capacities()` against the roster in `Battle._default_loadout()`:

| type | soldiers | files | file depth | historical file depth |
| --- | ---: | ---: | ---: | --- |
| Spearmen | 140 | 16 | 8--9 | see below |
| Infantry | 120 | 15 | 8 | see below |
| Archers | 90 | 13 | 6--7 | see below |
| Cavalry | 80 | 12 | 6--7 | see below |

Note the depths are not absurd --- 8 is a thoroughly plausible number for
close-order foot.
The objection is not that the output is wrong, it is that the output is
unowned: no type asked for 8, and no type can ask for anything else.

## What armies actually did

The Hellenistic tactical manuals are unusually good evidence for this specific
question, because subdivision *is* their subject: they define the file first
and build everything else by doubling it.
Asclepiodotus (*Tactics*, 1st century BC) is the most systematic of them and
is cited below by chapter and section from the Loeb text.
Where the record is thin, this section says so rather than filling the gap.

### Read this before using any number below

Three caveats bound everything here.

The **manuals are late, derivative and idealised**.
Asclepiodotus (1st century BC), Aelian (about AD 100) and Arrian (about AD 137)
are the only systematic sources for phalanx internals, and their ladders double
at every level up to a 16,384-man phalanx.
That is a drill-book scheme, not a muster roll.

**Practice and manual disagree**, and the Spartan evidence disagrees with
itself.
Where that happens this note reports both rather than picking the tidier one.

***Lochos* means opposite things in the two traditions** --- a 16-man file in
Asclepiodotus, a regiment of several hundred in Thucydides.
Do not carry one usage into the other.

### The file was a declared size, and the declared size varied

This is the finding that matters most, and it is stated outright.
Asclepiodotus 2.1 defines the file (*lochos*) as the body "dividing the
phalanx into symmetrical units", and then records that the depth was a matter
of practice rather than nature: "some have formed the file of eight men,
others of ten, others of twelve, and yet others of sixteen men."

So the ancient authority on the subject treats file depth as exactly what this
note proposes to make it --- **a declared parameter with a small set of
conventional values**, not a quantity derived from headcount.
The manual's own arithmetic then runs on sixteen: 2.8 builds the *dilochia* (2
files, 32 men), *tetrarchia* (64), *taxis* (128) and *syntagma* (256) by
successive doubling. 2.2 names the two men who make a file a command entity
rather than a column: the file-leader (*lochagos*) at the front and the
file-closer (*ouragos*) at the rear.

### But the subunit's *shape* was not fixed --- only its headcount

The manual's tidy 16-man column is not what the best-attested piece of Spartan
practice describes, and the difference changes what we should model.

Thucydides 5.68.3, on Mantinea, gives the order of battle: seven *lochoi*,
four *pentekostyes* each, four *enomotiai* each, and "of every enomotia there
stood in front four".
So the *enomotia* was **four men wide and about eight deep --- roughly 32 men,
a block of four files, not a file at all.** The arithmetic self-checks, which
is why it is worth trusting: 7 x 4 x 4 x 4 = 448, exactly the front-rank total
the same passage gives.

The same sentence then says the depth was **not uniform**: the men were "not
ranged all alike in file, but as the captains of bands thought it necessary",
with eight merely the general case.
Depth was set locally, by the subunit's own commander.

Xenophon's ladder in *Const.
Lac.* 11 does not reconcile with Thucydides' --- it implies two *enomotiai*
per *pentekostys* where Thucydides has four --- and the dispute is unresolved.
Thucydides also warns that Spartan numbers were obscured by "the secrecy of
that state".

The design-relevant conclusion survives the dispute intact, and this is worth
being deliberate about: **it rests on the agreed part, not the disputed
part.** What modern scholarship argues over is the *enomotia*'s establishment
strength --- 32, 36 or 40 --- and that argument is largely downstream of a
further one about how many *enomotiai* a *mora* held.
What is not in dispute is that the *enomotia* was a small block of several
files whose depth was variable by design, rather than a fixed file.

So a historical subunit was **a body of roughly fixed headcount whose
battlefield geometry was a choice** --- 4x8 at Mantinea, re-formed to other
frontages on command.
That argues for declaring a subunit's *size* and treating its frontage and
depth as formation-time outputs, which is a different call from declaring a
depth.
A design that keyed off the exact number would be building on the contested
half; one that keys off "fixed headcount, variable array" is building on the
settled half.

### Light troops appear to have files, and probably did not

The manual does give them one.
Asclepiodotus 6.2 puts the light infantry at **a depth of eight men** against
the hoplite sixteen, and 6.3 gives them a complete parallel ladder --- four
files to a *systasis*, then *pentekontarchia*, *hekatontarchia*, *psilagia*,
*xenagia*, *systremma*, *epixenagia*, *stiphos*.

Taken at face value that would settle the Archers row.
It should not be taken at face value, and the reason is a **pattern of
silences** rather than an argument from taste.
The one chapter that includes light troops in full is the one that is pure
arithmetic.
Every chapter that would require observed detail omits them:

- chapter 4, on intervals, gives three spacings for the phalanx --- 4 cubits
  open, 2 in *pyknosis*, 1 in *synaspismos* --- and **no interval at all** for
  light troops;
- chapter 3, on file anatomy and where the best men stand, is silent on them;
- chapter 11, on order of march, and chapter 12, on the words of command, omit
  them entirely.
  There is no attested command for skirmishers to retire.

The ladder also carries its own tell: the names do not match the counts, since
a *pentekontarchia* ("fifty-command") holds 64 and a *hekatontarchia*
("hundred-command") holds 128.
These are inherited titles fitted onto a power-of-two scheme.
The same schematism produces the army as a tidy 4:2:1 --- 16,384 hoplites,
8,192 light, 4,096 horse.

The Roman evidence points the other way outright.
Polybius 6.24 divides each class into ten companies "except the velites", and
states that "the velites are divided equally among all the companies".
Roman light troops therefore had **no organic subunit of their own at all**
--- no maniple, no standard, distributed among the heavy companies.

**Conclusion: treat the record as effectively silent on light-troop internal
formation.** That is not a failure to find sources; it is what the sources
look like when a schematic tradition pads a gap.
The Archers row is consequently the one where #1218's own instruction applies
--- make an informed guess and record the reasoning --- and the design call
below does exactly that.

### The file's anatomy is the historical warrant for what we already do

Worth recording because it validates existing behaviour rather than asking for
new behaviour.
Asclepiodotus 3 describes how a file is manned: the front-rank men
(*protostatai*) are chosen for "size, strength, and skill", and the second
rank is "not much inferior ... so that when a file-leader falls his comrade
behind may move forward".
The *ouragoi* at the rear "surpass the rest in presence of mind" and keep the
files straight.

That is precisely the file-major casualty reflow the game already implements
--- a death shortens its own file's rear and the men behind step up --- and it
is attested for **heavy infantry only**.
Chapter 3 says nothing about cavalry or light troops, which is the same
silence as above, and reinforces the same conclusion.

### Cavalry has a shape *and* a small subunit, and the two are separate

This is the row where the current model is structurally wrong rather than
merely unowned --- but not in the way a first pass suggests.
The manual tradition and the practitioner tradition give different answers,
and both are usable.

Asclepiodotus 7.2--7.5 draws squadrons up as a **square**, an **oblong**, a
**rhomboid**, or a **wedge**, and credits them to different peoples: the
Thessalians first used the rhomboid (7.2), the Scythians and Thracians
invented the wedge and the Macedonians adopted it later (7.3), while the
Persians, Sicilians and Greeks regularly used the square (7.4).

The internal ordering is explicitly optional. 7.6--7.9 set out the rhomboid
ordered "by both rank and file", "by rank and not by file", and "neither by
rank nor by file" --- three schemes the editor notes "differ only in the way
one looks at them".
A body whose own source says it may have neither ranks nor files is not a body
whose subunit is the file.

What organises it instead is a **leader**.
The wedge's advantage is stated as a narrow front that "made it easiest for
them to break through", with wheeling made easier because "all have their eyes
fixed on the single squadron-commander" (7.3); the rhomboid is "more necessary
for manoeuvring because it bears toward a leader" (7.5).
That is a different organising principle from the phalanx's, and it is the one
[#820](https://github.com/Lacaedemon/sparta/issues/820) (standard-bearer)
already reaches toward.

Three details sharpen it.
The named posts inside a rhomboid squadron are the four **angles** --- the
*ilarches* at the front, the *ouragos* at the rear, and two *plagiophylakes*
on the flanks --- so the internal roles are positional, not file-based.
The wedge is given no internal officers at all beyond the leader, and its
cohesion mechanism is explicitly visual: all "have their eyes fixed on the
single squadron-commander, as is the case also in the flight of cranes" (7.3).
And 7.10 calls the whole arm an *epitagma*, a supporting force, "because it is
attached to the phalanx according as need for it arises" --- cavalry is
structurally an attachment in this tradition, given no intervals, no file
anatomy, no marching position and no words of its own.

Roman cavalry is the exception that proves the rule about per-roster
variation.
Polybius 6.25 divides the cavalry into ten squadrons and selects "three
officers (decuriones)" from each, the first-chosen commanding the whole
squadron --- so a 30-man *turma* is three 10-man *decuriae*, a real subunit
where the Greek squadron has none.

One caveat against reading any of these numbers as an establishment strength:
Asclepiodotus' own arithmetic does not close.
His worked rhomboid comes to 61 men (7.6), his square squadron is 16 by 8
(7.4), and the ladder makes an *ile*
64. Three shapes, three incompatible strengths, one chapter.

**But the manuals are not the only witness, and the other one disagrees.**
Xenophon's *Hipparchicus* is a practical handbook by a man who commanded
cavalry, and at 4.9--10 he tells a commander to appoint *dekadarchoi* (leaders
of ten, i.e. of a file) and *pempadarchoi* (leaders of five, i.e. of a
half-file) behind them --- for an explicitly stated reason: "so that each may
pass the word to as few men as possible."
At 2.3--2.5 the front-rank men are chosen as the strong and ambitious, the
rear rank as "the oldest and most sensible", and each rank picks the one
behind it, so "every man will naturally have complete confidence in the man
behind him."
Xenophon gives **no** depth or frontage numbers anywhere.

Rome converges on the same magnitude independently: Polybius 6.25 divides the
cavalry into ten squadrons and selects "three officers (decuriones)" from
each, the first-chosen commanding the whole squadron --- so a 30-man *turma*
is three 10-man *decuriae*.

So two independent practitioner traditions give cavalry a **ten-man group**,
while the manual tradition gives it a **shape** with positional officers and
no file anatomy.
The reconciliation that fits both is that these describe different axes: a
small command group of about ten for passing orders and absorbing losses, and
a squadron shape --- wedge, rhomboid, square --- chosen for the tactical
situation.
That is exactly the type-structure / formation-structure split the design
calls below draw, and cavalry is the type that most clearly needs both.

### The Roman subunit is a lateral half, and it is well attested

An earlier draft of this note recorded the Roman case as unsourced.
That was wrong, and the correction matters, because the attested answer is a
*different shape* from the phalanx's.

Polybius 6.24 divides each class into ten companies and then splits the
company itself: "When both centurions are on the spot, the first elected
commands the right half of the maniple and the second the left."
So a maniple is natively a **two-block body divided laterally**, each half
under its own centurion.
Its strength is not stated outright: Polybius gives 1,200 hastati and 1,200
principes across ten companies (6.20), so the familiar 120 is division, not
testimony.
That still puts a maniple almost exactly at the size of our own `Infantry`
unit, which is what makes the century the subunit that matters for us --- a
left half and a right half, not a column.

**One consequence to state before anyone designs against it: a maniple cannot
relieve itself.** Its two centuries stand side by side, so the split offers no
front-and-rear rotation. Every clearly attested Roman line change works the
other way --- Scipio at Zama recalled the hastati *by trumpet* and moved the
principes and triarii onto the wings, extending the line sideways rather than
passing one line through another. Relief is a manoeuvre between *units*, which
is [#819](https://github.com/Lacaedemon/sparta/issues/819)'s territory, not
something a subunit structure delivers on its own.

The *contubernium* is the tempting answer and should be resisted.
Polybius' organisational excursus is detailed and gives it no tactical role at
all; Vegetius, four centuries later, describes a mess-group of **ten** rather
than eight and then conflates it with the maniple.
The familiar eight-man tactical squad is modern reconstruction resting on a
confused late passage.

### The sharpest finding: subunit independence is itself type-specific

This is the one that turns #1218 from a data question into a mechanics
question.

Polybius 18.32 contrasts the two systems directly.
The Roman soldier "is likewise equally prepared and equally in condition
whether he has to fight together with the whole army or with a part of it or
in maniples or singly" (18.32.11), whereas the phalanx soldier "can be of
service neither in detachments nor singly" (18.32.9).

So the historical difference between our `Spearmen` and our `Infantry` is not
merely that one is organised into files of sixteen and the other into lateral
halves.
It is that **the Roman subunit could act independently and the phalanx file
could not.** A per-type structure that only sets a number misses this
entirely; the structure has to carry a capability as well as a shape.

### Subunit orders were slow and could fail

Worth recording because it cuts against the obvious implementation, which is
to apply a subunit maneuver instantly.

Thucydides 5.66 describes Spartan orders propagating down the officer chain
--- king to polemarchs to *lochagoi* to *pentekostyes* to *enomotarchs* to the
men --- noting that the army "consists of officers under officers".
That is a latency, and the game already models its unit-level analogue as an
order-response delay.

Thucydides 5.71--72 then records what happened when Agis tried a lateral
subunit shift mid-approach at Mantinea.
He ordered the Sciritae and Brasideans out to extend the line and told the
polemarchs Hipponoidas and Aristocles to fill the resulting gap with two
companies from the right wing.
It failed twice over: they "would not move over, for which offence they were
afterwards banished from Sparta", *and* "the enemy meanwhile closed before the
Sciritae ... had time to fill up the breach."

Two independent failure modes --- refusal and insufficient time --- in the
single best-attested instance of exactly the maneuver #1218 proposes to
implement.
Any subunit-order model that resolves instantly and always succeeds is
modelling something the sources say did not happen.

### Summary, and what the game currently does against it

| type | attested subunit | shape | size | can it act alone? | confidence |
| --- | --- | --- | --- | --- | --- |
| Spearmen | file (*lochos*); Spartan *enomotia* | column, or a 4-wide block | 16 by the manual (8/10/12 also attested); ~32 at Mantinea | **no** --- Polyb. 18.32.9 | high, but the two traditions differ |
| Infantry | century (half-maniple) | **lateral half**, left and right | ~60, two per ~120-man maniple | **yes** --- Polyb. 18.32.11 | high --- Polyb. 6.24 |
| Cavalry | group of ten (*dekas* / *decuria*), inside a shaped squadron | shape is selectable: wedge / rhomboid / square | ~10 per group; squadron counts do not reconcile | n/a --- it *is* the detachment | high; two traditions, two axes |
| Archers | none, or a schematic one | --- | --- | --- | **low** --- see the silences above |

Set against the current geometry computed earlier: Spearmen sit at 8--9 deep
where the manual's standard is 16, though 8 is itself attested and the Spartan
block was about that; Infantry sit in 15 files where the attested division is
into two lateral halves, which is not a depth question at all; Archers sit at
6--7 deep against a number the record does not really support; and Cavalry sit
in 12 files, modelling a structure the sources say cavalry did not use.

The Infantry row is the one to look at hardest.
Its subunit is not a different *number* from the phalanx's --- it is a
different *axis*, a lateral halving rather than a column, and it carries a
capability the phalanx's does not.

## The design calls

The issue deliberately leaves these open.
This note makes the calls so that implementation is unblocked; each is
revisable if a phase disproves it.

### Does a structure attach to the loadout type, or to the roster name?

**To the loadout type, with a per-roster override.**

The game has four spawnable loadout types and seventeen roster names.
`Faction.ROSTER_UNIT_TYPES` maps every name onto one of the four, and the
mapping is many-to-one in exactly the place that matters: Spartan Hoplites,
Triarii, the Sacred Band, Libyan Spearmen and the Pezhetairoi Phalanx are all
`Spearmen`.
Attaching structure to the loadout type alone would give a Spartan file and a
Macedonian file the same declared depth, which is precisely the distinction
#1218 exists to capture.

Attaching it to the roster name instead would mean seventeen answers, most of
them guesses, and would strand any scenario that spawns a bare `Infantry` with
no faction flavour.

So: the loadout type carries the default, and a roster name may override it.
This is the layering `Battle` already uses --- `_default_loadout()` supplies
the type default and `_spawn_scenario` applies per-unit overrides on top ---
so it needs no new mechanism, only a new key threaded the way
`file_major_reform_default` already is.

**Implementation trap for whoever takes this.** `_default_loadout()` is an
army roster iterated with `loadout[i % loadout.size()]`, not a type registry:
it holds five entries, of which **two are byte-identical `Cavalry` entries**,
so the default battle fields five units a side with two cavalry regiments.
A structural key added to only the first `Cavalry` entry will apply to only
one of the two spawned regiments, and `_loadout_for_type()`'s first-match
lookup will hide the omission from every test that goes through it.
Set the key on both, or dedupe the entries first as separate work.

### Which structures do we actually need?

**Four, and only one of them is the file.** The issue offers files, ranks and
quadrants as candidates; the record above supports a different split.

1. **A file-based group of declared size** --- Spearmen.
   The manual's *lochos* is 16 men in a column; the Spartan *enomotia* is about
   32 in a four-wide block.
   Both are a declared headcount whose array is chosen when the unit forms, which
   is why the parameter is a size rather than a depth --- and why the same
   structure kind covers a per-roster split between a Macedonian Pezhetairoi file
   and a Spartan Hoplite block.
2. **Lateral halves** --- Infantry.
   The maniple divides into a right and a left century under two centurions
   (Polyb. 6.24), which is a division along a different *axis* from the file, not
   a different number.
   Our 120-man `Infantry` unit is almost exactly a maniple, so this is directly
   applicable.
3. **A small group of about ten, inside a selectable squadron shape** ---
   Cavalry.
   Two traditions, two axes: a ten-man command group from Xenophon and Polybius,
   and a wedge / rhomboid / square shape from the manuals.
   The error to remove is not that cavalry has files, it is that cavalry has
   *twelve* of them because a line-infantry aspect ratio said so.
4. **Undeclared, falling back to the derived width** --- Archers, and honestly
   so.
   The manual gives them a ladder its own pattern of silences undercuts, and the
   Roman answer is that they had no organic subunit at all.
   Leaving this row underived is the reasoning #1218 asks to be recorded, not a
   gap left by laziness.

**Ranks are not a type structure anywhere in the record.** This is worth
stating because #1218 offers them and the sources decline.
Asclepiodotus' whole ladder is a **frontage-doubling tree at constant depth**:
only the *lochos* is a file, and every level above it doubles the *width*
while the depth stays at sixteen.
Nothing in it is ever a rank.

That is a direct confirmation of the call above, arrived at from the other
direction: if depth is the constant and width is what multiplies, then depth
is the declared parameter and width is the derived one --- which is precisely
the inversion this note proposes and the opposite of what `_files()` does.

**Quadrants are a formation structure, not a type structure.** Where a
quadrant genuinely appears is in a formation: a square folds onto four faces,
which is a subdivision of the current shape rather than of the unit's
doctrine.
So structure has two independent axes, and conflating them is the trap this
call exists to avoid:

- **Type structure** --- what doctrine organises this unit into, always.
  A file of sixteen.
- **Formation structure** --- what the *current* formation subdivides into.
  The square's four faces.

They compose rather than compete: a phalanx forming square folds its existing
files onto four faces, which is exactly Phase 1 of
`docs/square-formation-design.md`.
Cavalry is the case that shows why the two axes must be separate --- it has a
small subunit *and* a shape that is itself a tactical choice, so a model with
only one axis cannot express it at all.

### Does this contradict the square-formation note?

**No, and the distinction is worth stating because it reads like a
contradiction.** `docs/square-formation-design.md` calls it: "the file
(column) is the sub-unit of maneuver for our scale", and says to reuse it
"rather than inventing a parallel sub-unit structure for squares".

That call was answering *which* subunit the square should fold, for a phalanx,
at regiment scale --- and this note leaves it standing.
What it did not ask, and this note does, is whether the answer is **uniform
across types**.
The evidence says it is not: the file is right for both foot types and wrong
for cavalry.

So the two notes agree on the mechanism and differ only in scope.
Nothing here asks for a parallel structure alongside the file; it asks for the
file's depth to be declared, and for a type to be able to declare that it has
no file structure at all.

### What is the structural primitive?

**A subunit is a contiguous group of men with a stable id, an internal order,
and a declared target size.** That is exactly what `_sim_soldier_file` plus
`_sim_soldier_rank` already are, minus the declared size.

So the primitive is not new.
The generalisation is:

- `_sim_soldier_file` becomes *which subunit a man belongs to*.
- `_sim_soldier_rank` becomes *his index within it*.
- A new per-type declaration supplies the **target size** and the **shape** the
  subunit takes when laid out (a column, a row, a block).

Keeping the existing arrays and widening their meaning matters more than the
naming.
They are already dealt deterministically, trimmed index-aligned on a death by
`SoldierMelee.reap`, serialized into the state dump, and read by the one
layout path that preserves identity.
A parallel `_sim_soldier_subunit` array alongside a surviving
`_sim_soldier_file` would double the state that has to stay consistent through
a casualty, for no gain.
Rename in place, in one mechanical commit, or leave the names alone and widen
the docstrings --- but do not carry two.

This also keeps the standing performance rule in `PLAN.md`: per-soldier state
stays in `Packed*Array` slots, and no per-soldier heap object is introduced.

### Does the declared size become an input, or stay an output?

**An input, with the derived value kept as the fallback.**

This is the inversion above, stated as a change: a type declares its subunit
size, the unit fields `ceil(live / size)` subunits, and the frontage follows
from that count.
`_files()` stays as the answer for any unit whose type declares nothing, and
as the degenerate case when the live count is smaller than a single subunit.

Two consequences worth stating plainly, because they are behaviour changes
rather than refactors:

- **Frontage stops being constant as casualties mount.** Today the width is
  pinned to `max_soldiers` and depth absorbs the losses.
  Under a declared depth, a unit that loses a subunit's worth of men fields one
  fewer subunit, so the width steps down --- continuously, in subunit-sized
  notches, rather than once at the close-ranks threshold.
  The existing `_ranks_closed` notch and this behaviour overlap and one of them
  should go; deciding which belongs to the phase that implements it, not to this
  note.
- **The player-facing frontage control needs a meaning.** `frontage_override`
  currently sets a file count directly, and the drag-resize handle
  (`files_for_halfwidth`) maps a dragged width onto one.
  Under declared subunits the honest reading is that the player sets a *subunit
  count*, and the width follows.
  That is a HUD and input change, not just a layout one.

### What does "implemented through subunit-level behaviours" buy?

**A measured reduction in how far men walk to reform, and the removal of a
recurring bug family.** This is not speculative --- the codebase already
contains one worked example of the transformation, and it is worth quoting
because it sets the standard the rest should be judged against.

`Unit.reform_ranks(hold_ground)` re-squares the block by reflecting it in
depth.
Done as a whole-block relabel, every man walks the block's full depth to reach
a slot another man is vacating on the same tick.
Done as a per-subunit operation ---
`UnitFormation.reversed_ranks_within_files` reverses each file's *internal*
order, which exactly cancels the reflection for every full-depth file --- only
the men in short files move at all.
That function's own docstring records the measurement: **for 80 men on 12
files, 24 men step one rank pitch, against all 80 crossing the block** under
the index-order relabel.

That is the shape #1218 is asking to generalise, and it gives the phases below
a falsifiable acceptance test: for each maneuver converted, count the men who
move and the distance they cover, before and against after.

The second payoff is structural.
`docs/square-formation-design.md` already argues that subunit-based reform
**subsumes** the array-index identity-swap bug family rather than fixing it
one maneuver at a time --- a family that has recurred at least four times
([#541](https://github.com/Lacaedemon/sparta/issues/541),
[#668](https://github.com/Lacaedemon/sparta/issues/668),
[#802](https://github.com/Lacaedemon/sparta/issues/802),
[#1146](https://github.com/Lacaedemon/sparta/issues/1146)), each caught by a
human noticing something wrong in a clip.
If subunits move as bodies, "a man crossed his own formation" stops being a
thing that has to be detected.

The issue's own example --- converting a flank file into a back rank by
marching it around the edge of the unit --- is a third case, and it is the one
that most clearly cannot be expressed today: there is no way to say "this
file, as a body, takes that route".
It needs a subunit to be addressable as a thing that receives an order, which
is where this note meets
[#547](https://github.com/Lacaedemon/sparta/issues/547).

There is even a doctrinal precedent for choosing the *granularity* of a
maneuver by the tactical situation.
Asclepiodotus 10.16, on counter-marching by rank, notes that "sometimes it is
not advisable to make the counter-marches by half-wings, when the enemy is
near by, but rather by battalions" --- a smaller subunit when the enemy is
close, because a smaller body completes the movement sooner.
That is the same trade the reform measurement above quantifies, and it
suggests the granularity should eventually be a parameter rather than a
constant.

## The hazard that shapes the plan

Making the subunit count follow the **live** count is the obvious reading of
"declared depth becomes the input", and it is the one thing the existing code
explicitly warns against.

`_ensure_file_assignment`'s own comment records why the current design keys
frontage off `max_soldiers` rather than the live count: re-dealing on a size
change would "re-read every man's file off positions that contact impulses are
shoving around, on the tick of every casualty, for the whole of a melee ---
the target-slot churn this sim has been bitten by before, and it measurably
worsens the residual melee-lock swirl."
That swirl is a live, tracked defect family, not a hypothetical.

So the constraint on every phase below is: **a declared depth may change the
subunit count, but not continuously.** The count may step at a reform, at a
discrete hysteresis-gapped threshold like the existing `_ranks_closed` notch,
or on an explicit order --- never as a per-tick function of the live
headcount.
Any phase that finds itself re-dealing assignments inside a melee has taken a
wrong turn, and the residual-swirl guard is the test that will say so.

## Phased plan

Each phase is independently shippable and independently verifiable.
Every phase that touches layout re-runs `tools/benchmark` on the reference
scenario, per `PLAN.md`'s standing performance constraint, and checks the demo
against the standard defect checklist in
`.claude/skills/verify-via-state-dump`.

- **Phase 1 --- declare the structure, change nothing.** Add the per-type
  structural key to `Battle._default_loadout()` (**both** `Cavalry` entries ---
  see the trap above), thread it onto `Unit` in `_spawn_unit` the way
  `file_major_reform_default` is threaded, allow a roster-name and scenario
  override, and serialize it into the state dump.
  Nothing reads it for layout yet.

  The point of shipping this alone is that it is provably inert: a state-dump
  diff across the reference demos should be **byte-identical** apart from the
  new field.
  That gives phases 2 onward a clean base and makes the data question reviewable
  separately from the behaviour question.
  Smallest, lowest-risk slice; the recommended first PR.

- **Phase 2 --- make the declared depth the input for the foot types.** Spearmen
  and Archers derive their subunit count from `ceil(live / depth)` instead of
  `_files(max_soldiers)`, subject to the no-continuous-re-deal constraint above.
  Infantry and Cavalry are untouched, so the blast radius is two types.

  This is the first real behaviour change, and it collides with two existing
  mechanisms that must be resolved rather than left to interact: the
  `_ranks_closed` notch (which now duplicates part of the job) and
  `frontage_override` plus the drag-resize handle (whose unit of measure becomes
  the subunit).
  Expect the demo to look different --- a Spearmen block at a declared 16 is
  markedly deeper and narrower than today's 8--9.

- **Phase 3 --- give cavalry no file structure.** Stop laying cavalry out as
  files.
  This is the phase that most needs a decision made before it starts, because
  "no subunit" still requires *some* layout, and the historically motivated
  answer (a body oriented on a leader) depends on
  [#820](https://github.com/Lacaedemon/sparta/issues/820).

  An interim that does not block on #820: keep the block layout, drop the
  persistent per-soldier file identity for the type, and let the type declare
  itself structureless so nothing downstream reasons about cavalry files.
  That is strictly less wrong than today and does not prejudge the leader model.

- **Phase 4 --- express one reform as a subunit operation.** The issue's own
  example: convert a flank file into a back rank by marching that file around
  the edge of the block into its rear, as a body, rather than relabelling every
  man.
  This is the payoff phase.

  Its acceptance test is already defined by precedent: count the men who move
  and the distance they cover, before against after, the way
  `reversed_ranks_within_files` records 24 of 80 men stepping one pitch against
  all 80 crossing the block.
  A conversion that does not improve that pair of numbers has not earned its
  complexity.

- **Phase 5 (optional, later) --- ride #547.** Once explicit per-soldier slot
  ownership lands, a subunit becomes an addressable recipient of an order ("your
  file wheels onto the east face") rather than an input to a centralized layout
  recompute.
  Converges with `docs/square-formation-design.md`'s own Phase 4 and with the
  group-scale work in [#819](https://github.com/Lacaedemon/sparta/issues/819) /
  [#1033](https://github.com/Lacaedemon/sparta/issues/1033).

Phases 1--2 are worth doing regardless.
Phase 3 should not start before its open question is answered.
Phase 4 is where the issue's actual request is delivered, and phases 1--3
exist mainly to make it expressible.

## Cross-references

- [#1218](https://github.com/Lacaedemon/sparta/issues/1218) --- this note's
  originating issue.
- [#547](https://github.com/Lacaedemon/sparta/issues/547) --- explicit
  per-soldier slot ownership; the neighbouring architectural issue, and the
  primitive that would make subunit orders first-class.
- [#819](https://github.com/Lacaedemon/sparta/issues/819) --- century-level
  partial withdrawal, explicitly blocked on per-subunit granularity.
- [#1033](https://github.com/Lacaedemon/sparta/issues/1033) --- the same
  abstraction pointing upward: reusing unit-level formation and relief mechanics
  at the unit-group level.
- `docs/square-formation-design.md` --- argues the file is the right subunit at
  regiment scale, and sketches the fold this note generalises.
- `docs/REFORM_RESEARCH.md` --- the existing historical grounding for file-based
  cohesion.
- `docs/acies-triplex-design.md` --- multi-line organisation; the scale above
  this one.
- `PLAN.md`, `docs/individual-collision-design.md` --- the bottom-up-physics
  philosophy this note applies to organisation.
