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

*(pending)*

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
