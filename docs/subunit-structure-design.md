# Design note: subdividing units into subunits

Status: **design only** --- no code lands with this note. It answers
[#1218](https://github.com/Lacaedemon/sparta/issues/1218) so an implementation
can follow, and lays out a phased plan whose first slice is small enough to ship
on its own. Nothing here changes the running simulation yet.

## The question

[#1218](https://github.com/Lacaedemon/sparta/issues/1218) asks for two things:

1. Different unit types get **different subunit structures** --- files, ranks, or
   quadrants --- as specified by historical records, with recorded reasoning
   where the record is silent.
2. Unit-level behaviours such as reforming, after casualties or on a
   commander's order, get implemented **through subunit-level behaviours**. The
   issue's own worked example: a reform into a longer, narrower formation could
   convert one or more flank files into a back rank and march that file around
   the edge of the rest of the unit into its rear.

The second half is the load-bearing one. The first is a data question with a
bounded answer; the second is a claim about where maneuver logic lives, and it
is the same "bottom-up physics, no top-down gimmicks" principle `PLAN.md`
already applies to combat and movement, applied to organisation.

## What we do today (verified against the code)

- **One grouping exists, and it is the file.** `_sim_soldier_file` and
  `_sim_soldier_rank` (`scripts/Unit.gd`) are persistent per-soldier ids ---
  which column a man belongs to, and how deep he stands in it. They are dealt by
  `_ensure_file_assignment`, maintained through a death by `SoldierMelee.reap`,
  and serialized into the state dump, so they already survive casualties and
  replay.
- **No unit type declares a structure.** A type is a dictionary literal in
  `Battle._default_loadout()`. It already carries structural *geometry* ---
  `file_pitch_m`, `rank_pitch_m`, `formation`, `file_major_reform_default` ---
  but nothing about organisation. Every type gets the same implicit answer.
- **The file count is derived from the roster size, and file depth is a
  remainder.** `UnitFormation.frontage(u)` reads `_files(u.max_soldiers)`, which
  is `ceil(sqrt(max_soldiers * 1.7))` (`FORMATION_ASPECT`) --- the type's
  *full-strength* size, not its live count, so the width holds steady as men
  fall and steps down a single notch only once `_ranks_closed` crosses the
  close-the-ranks threshold. `file_capacities(count, files)` then divides the
  live count across that width and spreads the remainder over a centred span. So
  the width is chosen first, from a number fixed at spawn, and the depth is
  whatever is left over.
- **Only one of three layout branches preserves identity.**
  `Unit.formation_slots()` dispatches three ways: the square branch pairs men
  onto a `ceil(sqrt(n))` grid by proximity and bypasses file identity entirely;
  the file-major branch is the one that keeps it; the row-major fallback
  recomputes from the live count every tick and reassigns by raw array index.
  Every loadout type defaults to FILE_MAJOR and `disciplined` defaults to true,
  so the fallback is reached only by an explicit scenario override.

## The inversion this note is about

Armies derived the footprint from the subunit. We derive the subunit from the
footprint.

A Hellenistic file had a **declared depth** --- the manuals define the file as
the primitive and build every larger body by multiplying it --- and a phalanx's
frontage was the consequence of how many files it fielded. We do the reverse:
`_files()` picks a file *count* from the roster size and an aspect constant, and
a man's file depth is a division remainder. Nothing in the game has a doctrinal
depth to hold.

The consequence is visible in how casualties are absorbed. Because the width is
pinned to `max_soldiers`, losses come out of *depth*: files shorten, and the
frontage holds until the close-ranks notch fires. A doctrinal-depth army does
the opposite by default --- a file that cannot be kept at depth is collapsed
into its neighbours and the unit fields *fewer files*, which is what the
file-closer existed to enforce. We have the notch, so we can reach that state;
we get there by a global threshold rather than by any file running short.

This is the same shape of shortcut `docs/square-formation-design.md` names as
its gap 3, one level up. There the criticism is that `ceil(sqrt(n))` picks the
square's footprint first and fits men to it; here the footprint of the *line* is
picked first and the file falls out of it. Both make shape an input where it
should be an output.

The current numbers, at full strength, computed from `_files()` and
`file_capacities()` against the roster in `Battle._default_loadout()`:

| type | soldiers | files | file depth | historical file depth |
| --- | ---: | ---: | ---: | --- |
| Spearmen | 140 | 16 | 8--9 | see below |
| Infantry | 120 | 15 | 8 | see below |
| Archers | 90 | 13 | 6--7 | see below |
| Cavalry | 80 | 12 | 6--7 | see below |

Note the depths are not absurd --- 8 is a thoroughly plausible number for close-
order foot. The objection is not that the output is wrong, it is that the output
is unowned: no type asked for 8, and no type can ask for anything else.

## What armies actually did

*(historical section --- pending)*

## The design calls

The issue deliberately leaves these open. This note makes the calls so that
implementation is unblocked; each is revisable if a phase disproves it.

### Does a structure attach to the loadout type, or to the roster name?

**To the loadout type, with a per-roster override.**

The game has four spawnable loadout types and seventeen roster names.
`Faction.ROSTER_UNIT_TYPES` maps every name onto one of the four, and the
mapping is many-to-one in exactly the place that matters: Spartan Hoplites,
Triarii, the Sacred Band, Libyan Spearmen and the Pezhetairoi Phalanx are all
`Spearmen`. Attaching structure to the loadout type alone would give a Spartan
file and a Macedonian file the same declared depth, which is precisely the
distinction #1218 exists to capture.

Attaching it to the roster name instead would mean seventeen answers, most of
them guesses, and would strand any scenario that spawns a bare `Infantry` with
no faction flavour.

So: the loadout type carries the default, and a roster name may override it.
This is the layering `Battle` already uses --- `_default_loadout()` supplies the
type default and `_spawn_scenario` applies per-unit overrides on top --- so it
needs no new mechanism, only a new key threaded the way `file_major_reform_default`
already is.

**Implementation trap for whoever takes this.** `_default_loadout()` is an army
roster iterated with `loadout[i % loadout.size()]`, not a type registry: it holds
five entries, of which **two are byte-identical `Cavalry` entries**, so the
default battle fields five units a side with two cavalry regiments. A structural
key added to only the first `Cavalry` entry will apply to only one of the two
spawned regiments, and `_loadout_for_type()`'s first-match lookup will hide the
omission from every test that goes through it. Set the key on both, or dedupe
the entries first as separate work.

### What is the structural primitive?

**A subunit is a contiguous group of men with a stable id, an internal order,
and a declared target size.** That is exactly what `_sim_soldier_file` plus
`_sim_soldier_rank` already are, minus the declared size.

So the primitive is not new. The generalisation is:

- `_sim_soldier_file` becomes *which subunit a man belongs to*.
- `_sim_soldier_rank` becomes *his index within it*.
- A new per-type declaration supplies the **target size** and the **shape** the
  subunit takes when laid out (a column, a row, a block).

Keeping the existing arrays and widening their meaning matters more than the
naming. They are already dealt deterministically, trimmed index-aligned on a
death by `SoldierMelee.reap`, serialized into the state dump, and read by the
one layout path that preserves identity. A parallel `_sim_soldier_subunit`
array alongside a surviving `_sim_soldier_file` would double the state that has
to stay consistent through a casualty, for no gain. Rename in place, in one
mechanical commit, or leave the names alone and widen the docstrings --- but do
not carry two.

This also keeps the standing performance rule in `PLAN.md`: per-soldier state
stays in `Packed*Array` slots, and no per-soldier heap object is introduced.

### Does the declared size become an input, or stay an output?

**An input, with the derived value kept as the fallback.**

This is the inversion above, stated as a change: a type declares its subunit
size, the unit fields `ceil(live / size)` subunits, and the frontage follows
from that count. `_files()` stays as the answer for any unit whose type declares
nothing, and as the degenerate case when the live count is smaller than a single
subunit.

Two consequences worth stating plainly, because they are behaviour changes
rather than refactors:

- **Frontage stops being constant as casualties mount.** Today the width is
  pinned to `max_soldiers` and depth absorbs the losses. Under a declared depth,
  a unit that loses a subunit's worth of men fields one fewer subunit, so the
  width steps down --- continuously, in subunit-sized notches, rather than once
  at the close-ranks threshold. The existing `_ranks_closed` notch and this
  behaviour overlap and one of them should go; deciding which belongs to the
  phase that implements it, not to this note.
- **The player-facing frontage control needs a meaning.** `frontage_override`
  currently sets a file count directly, and the drag-resize handle
  (`files_for_halfwidth`) maps a dragged width onto one. Under declared subunits
  the honest reading is that the player sets a *subunit count*, and the width
  follows. That is a HUD and input change, not just a layout one.

### What does "implemented through subunit-level behaviours" buy?

**A measured reduction in how far men walk to reform, and the removal of a
recurring bug family.** This is not speculative --- the codebase already contains
one worked example of the transformation, and it is worth quoting because it
sets the standard the rest should be judged against.

`Unit.reform_ranks(hold_ground)` re-squares the block by reflecting it in depth.
Done as a whole-block relabel, every man walks the block's full depth to reach a
slot another man is vacating on the same tick. Done as a per-subunit operation
--- `UnitFormation.reversed_ranks_within_files` reverses each file's *internal*
order, which exactly cancels the reflection for every full-depth file --- only
the men in short files move at all. That function's own docstring records the
measurement: **for 80 men on 12 files, 24 men step one rank pitch, against all
80 crossing the block** under the index-order relabel.

That is the shape #1218 is asking to generalise, and it gives the phases below a
falsifiable acceptance test: for each maneuver converted, count the men who move
and the distance they cover, before and against after.

The second payoff is structural. `docs/square-formation-design.md` already
argues that subunit-based reform **subsumes** the array-index identity-swap bug
family rather than fixing it one maneuver at a time --- a family that has
recurred at least four times ([#541](https://github.com/Lacaedemon/sparta/issues/541),
[#668](https://github.com/Lacaedemon/sparta/issues/668),
[#802](https://github.com/Lacaedemon/sparta/issues/802),
[#1146](https://github.com/Lacaedemon/sparta/issues/1146)), each caught by a
human noticing something wrong in a clip. If subunits move as bodies, "a man
crossed his own formation" stops being a thing that has to be detected.

The issue's own example --- converting a flank file into a back rank by marching
it around the edge of the unit --- is a third case, and it is the one that most
clearly cannot be expressed today: there is no way to say "this file, as a
body, takes that route". It needs a subunit to be addressable as a thing that
receives an order, which is where this note meets
[#547](https://github.com/Lacaedemon/sparta/issues/547).

## Phased plan

*(pending)*

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
