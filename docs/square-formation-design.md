# Design note: square formation as sub-unit folding

Status: **design only** --- no code lands with this note. It answers the open
questions raised in
[#1161](https://github.com/Lacaedemon/sparta/issues/1161) so an implementation
can follow, and lays out a phased plan whose first slice is small enough to ship
on its own. Nothing here changes the running simulation yet.

Filed at the owner's request after the question surfaced reviewing
[#1146](https://github.com/Lacaedemon/sparta/issues/1146) (proximity-paired
square slot assignment, merged). That fix is worth having on its own terms ---
it removed the absurd cross-block routes --- but it improved *which cell each man
walks to* without touching the fact that we assign cells to men at all. This
note is about that deeper modelling question.

## The question

Do we model how an army historically reformed from a line into a square? We
model the **outcome** well. We do not model the **mechanism**, and the
difference is not cosmetic: it is the same "bottom-up physics, no top-down
gimmicks" distinction the project already applies to combat and movement (see
`PLAN.md` and `docs/individual-collision-design.md`), applied to drill.

## What we do today (verified against the code)

- `UnitFormation.square_files(n)` is `maxi(1, ceil(sqrt(n)))`
  (`scripts/UnitFormation.gd`). A 120-man regiment goes from ~15 files to 11.
- `UnitFormation.square_slots(n, spacing)` delegates to `block_slots(n, files,
  spacing)`, which fills **every** cell (`for i in range(n)`). So a square is a
  **solid** block, not a shell.
- `Unit.formation_slots()`'s square branch (`scripts/Unit.gd`) returns before
  the file-major branch, so `_sim_soldier_file` --- the real, persistent
  per-soldier file identity we already keep and use for ordinary casualty
  reflow --- is deliberately switched **off** for squares. What the square keeps
  instead is `_sim_soldier_square_slot`, a per-soldier pairing onto the square
  grid decided by proximity (the #1146 fix), not a persistent file.
- "Hollow" appears in the prose (`in_square()`'s neighbours, `UnitFormation`'s
  section header, several comments) but never in the geometry. The
  perimeter/interior split exists only in `soldier_world_facings` (ring points
  outward via `square_is_perimeter`, interior keeps the unit heading) and in
  engaged-soldier selection (`live_perimeter_indices` /
  `most_exposed_among`) --- both read the solid grid and *select* a ring from it;
  neither makes the grid itself a shell.

Post-#1146, cells are paired to men by proximity instead of by array index.
That removed the absurd routes. It did not change any of the four points above.

## What armies actually did

In every case substantiated in `docs/REFORM_RESEARCH.md` and the sources it
cites, **the sub-unit is the atom of maneuver, not the soldier.**

- **Hellenistic phalanx.** The surviving tactical manuals (Asclepiodotus,
  Aelian, Arrian) describe the phalanx entirely in terms of the *file*: a
  file-leader at the front, a file-closer at the rear, and maneuvers defined as
  operations **on files** (doubling depth, doubling front, the countermarches,
  wheeling). We already model this faithfully elsewhere --- `Battle.gd` implements
  *exelismos* with its three named variants (Macedonian, Laconian, Choral).
- **Napoleonic square.** A battalion in line forms square by its
  companies/divisions wheeling back onto assigned faces, each keeping its
  internal file order intact. Hollow, with officers, colours and wounded
  inside, front rank kneeling with bayonets out.
- **Roman *orbis* and the Scottish schiltron** are the other standard referents:
  dense defensive formations presenting spears outward on all sides, the orbis
  formed by surrounded troops closing up. The schiltron's exact geometry
  (circular vs. rectangular) is genuinely disputed in the modern literature and
  the term covers several things across the Wallace/Bruce period --- a specialist
  check is warranted before designing to it precisely; this note treats the
  schiltron as the rectangular-shell case, same as the orbis, for now.

The reason the sub-unit is the atom is practical, not aesthetic. You cannot
issue 120 individual destinations to men with cavalry bearing down. You issue
**one** order; a handful of sub-unit leaders each know their pre-memorised place
in the square; every man keeps his neighbours. Forming square *was* the
benchmark of drill quality precisely because it is a coordination problem, and
the coordination is solved by rehearsal, not by pathfinding.

## Three concrete gaps

1. **File identity is destroyed by the reshape.** The square re-files onto
   `ceil(sqrt(n))` columns, so every man is reassigned. Historically a unit
   forming square does not re-file --- it folds its *existing* files onto four
   faces. #1146's pairing makes men keep their side and depth order, which
   *looks* like folding, but it is an emergent property of a global sort, not
   files moving as bodies.

2. **The square is solid, not hollow.** Real squares were a shell several ranks
   thick around an empty or command-occupied core. We fill the middle and then
   paper over it by pointing only the outer ring outward. Interior men are,
   physically, doing nothing --- which means we get the formation's density,
   frontage and casualty behaviour wrong, not just its look.

3. **`ceil(sqrt(n))` is a top-down geometric shortcut.** We pick the footprint
   first and fit men to it. A bottom-up model would derive the footprint from
   *how many files fold which way* --- shape as a consequence of the drill, not
   an input to it. This is the same shape of shortcut as a flat combat
   multiplier, which the project's stated philosophy already rejects for
   mechanics; drill should be held to the same bar.

## The design calls (answering #1161's open questions)

The issue deliberately left these open. This note makes the calls so that
implementation is unblocked; each is revisable if a phase disproves it.

### Is the file the right sub-unit?

**Yes --- the file (column) is the sub-unit of maneuver for our scale.** It is
what the Greek manuals use, what `docs/REFORM_RESEARCH.md` documents as the
primary unit of cohesion, and what we already model as a first-class per-soldier
identity (`_sim_soldier_file`) for casualty reflow. Larger groupings (a Roman
century, a Napoleonic company) are the right atom at a *larger* organizational
scale and belong with the acies-triplex / group-formation work
([#819](https://github.com/Lacaedemon/sparta/issues/819),
[#1033](https://github.com/Lacaedemon/sparta/issues/1033)); at the single
regiment's scale the file is both historically correct and already-built. Reuse
it rather than inventing a parallel sub-unit structure for squares.

### Should a square be genuinely hollow, and what sets shell thickness?

**Yes --- model the square as a genuine shell, and derive shell thickness from
weapon reach, not a fixed rank count or a raw headcount ratio.** Reach is the
physical quantity that actually determines how many ranks can present a weapon
outward on a face, and the project already carries per-unit reach
(`attack_range`, `soldier_reach()`), so the thickness falls out of data we have
rather than a new tuned literal. A schiltron/orbis of long spears presents more
ranks than a short-sword orbis; that difference should emerge, not be a magic
number. The core is empty (or, later, command/standard-occupied --- see
[#820](https://github.com/Lacaedemon/sparta/issues/820)).

Concretely: shell thickness `t` = the number of ranks whose weapons reach the
face, `clamp(round(reach / rank_pitch), 1, max_by_headcount)`, where
`max_by_headcount` is whatever the live count can actually fill around the
perimeter without leaving the shell ragged. When headcount is too low to man a
shell of thickness `t` around the derived perimeter, the square degrades
gracefully toward solid (a tiny remnant *is* effectively solid), which is also
historically right --- a shrunken square collapses inward.

### Should the footprint stay `ceil(sqrt(n))` or fall out of the fold?

**Derive it from the fold.** With the file as the atom and a hollow shell, the
footprint is a consequence: given `f` live files of depth `d` folding onto four
faces at shell thickness `t`, the side length is set by how many file-segments
each face carries. `ceil(sqrt(n))` stays as a *degenerate fallback* for the
solid-remnant case above and as the initial-perimeter estimate the fold refines,
not as the primary definition. This is the concrete way gap 3 is closed:
footprint becomes an output, not an input.

### Standalone, or ride on #547?

**Sequence it after #547's primitive, but scope the first slice to stand
alone.** [#547](https://github.com/Lacaedemon/sparta/issues/547) (explicit
per-soldier slot ownership) is the enabling primitive that makes identity
first-class and makes "a man crossed his own formation" *unrepresentable* rather
than merely *detectable*. The full hollow-file-folding model wants that
primitive underneath it. But phase 1 below (preserve file identity through the
reshape) reuses the `_sim_soldier_file` machinery that already exists and does
not need #547 --- it is a small, self-contained step that de-risks the rest and is
worth shipping first.

### Cost

Squares currently get cheap index-based layout; a persistent sub-unit structure
is more state to carry through casualties. But the state is *already paid for* on
the line side: `_sim_soldier_file` / `_sim_soldier_rank` are maintained every
tick for file-major reflow, trimmed index-aligned by `SoldierMelee.reap()`.
Extending that to squares reuses the same arrays and the same trim path; it does
**not** add per-soldier heap objects (the standing performance rule in `PLAN.md`
 --- shared `Type` objects plus per-soldier SoA arrays). The hollow shell lays out
the *same* `n` bodies as the solid block: hollowing changes which cells are
occupied, not how many men are placed, and `block_slots` / `square_slots` already
enumerate `for i in range(n)` rather than walking empty cells. So per-tick layout
cost is unchanged in order. The real cost is
the fold geometry itself (mapping `f` files onto four faces), which is an O(n)
pass like the layouts we already run. The genuine saving is elsewhere: a real
shell simplifies engaged-soldier selection, noted under Phase 2 below. Re-run `tools/benchmark` on the reference
scenario at each phase, per `PLAN.md`'s performance constraint, before trusting
any of this.

## Why one design, not three fixes

Sub-unit-based reform **subsumes the whole array-index bug family** rather than
fixing it one maneuver at a time. That family has recurred at least four times ---
[#541](https://github.com/Lacaedemon/sparta/issues/541) (about-face),
[#668](https://github.com/Lacaedemon/sparta/issues/668) (countermarch),
[#802](https://github.com/Lacaedemon/sparta/issues/802) (target-slot cadence),
[#1146](https://github.com/Lacaedemon/sparta/issues/1146) (square) --- each caught
only by a human noticing something wrong in a clip. If files moved as bodies, "a
man crossed his own formation" would be structurally impossible, not merely
detectable after the fact by
[#1149](https://github.com/Lacaedemon/sparta/issues/1149)'s route-aware metric
(which stays useful as a guard).

## Phased plan

Each phase is independently shippable and independently verifiable (state-dump
per-index identity checks per `.claude/skills/verify-via-state-dump`, plus a demo
against `demos/inputs/anti-cav-square.json` and the `square` catalog clip).

- **Phase 1 --- preserve file identity through the square reform.** Stop switching
  `_sim_soldier_file` off for squares. Fold the *existing* files onto the square
  grid, instead of re-pairing men by a global proximity sort. Reuses existing
  `_sim_soldier_file` machinery; no new primitive needed. Smallest, lowest-risk
  slice --- the recommended first PR.

  **Scope honestly: this does not close gap 1 on its own.** `_ensure_file_assignment`
  is the same sort-then-deal shape as the `#1146` mechanism this note criticises
  (`lateral_order` -> deal -> sort by depth), and `square_files(n)` =
  `ceil(sqrt(live))` is essentially never equal to the line's `frontage()`, so a
  man's file is necessarily redealt on entering and leaving square. Simulating the
  120-man / 15-to-11-file example above, only about 74% of line file-mate pairs
  survive the deal. It also *costs* an identity guarantee that holds today: because
  `set_formation` never resets `_sim_soldier_file` for squares, a
  line -> square -> line round trip currently preserves every survivor's original
  file id exactly, and a Phase 1 re-deal would overwrite that. And the instability
  `formation_slots()`' own docstring cites is still live here, since `square_files`
  steps at every perfect square (100, 81, 64, ...), forcing a fresh global re-deal
  mid-fight.

  What Phase 1 *does* buy, and the claim it should be judged on, is file-major
  casualty reflow **inside** the square, replacing today's row-major close-up that
  can jump a man clear across the block on a single death. Closing gap 1 properly
  needs a stable footprint (Phases 2-3) or `#547`.

  Guard with a per-index, local-frame before/after identity test
  (dump `soldiers_full.pos` de-rotated by `facing.angle() + PI/2 +
  _formation_angle`, compare by array index across the line->square transition),
  because the settled-state defect metrics are blind *during* a reshape.
- **Phase 2 --- make the shell genuinely hollow.** Replace `square_slots`' solid
  `block_slots` with a shell layout of derived thickness `t` (reach-based),
  leaving the core empty. Fix density/frontage/casualty behaviour to match the
  shell, not the solid block. Closes gap 2. Larger --- touches combat's
  engaged-soldier selection, which currently *selects* a ring from a solid grid;
  with a real shell that selection simplifies. Re-verify combat balance
  (`test/unit/test_unit.gd` engaged-set tests, the anti-cav demo) carefully.

  **This phase needs an interim footprint of its own.** A shell of thickness `t`
  on an `s x s` grid holds `4t(s - t)` cells. With `s` pinned at
  `square_files(n) = ceil(sqrt(n))`, the spare capacity is only `s^2 - n`, which
  is tiny by construction, so the shell cannot hold all `n` men for most of the
  roster:

  | unit | n | reach | t | s | shell capacity | result |
  | --- | ---: | ---: | ---: | ---: | ---: | --- |
  | Spearmen | 140 | 2.4 m | 5 | 12 | 140 | fits exactly, 2x2 core |
  | Infantry | 120 | 1.3 m | 3 | 11 | 96 | 24 men unplaced |
  | Cavalry | 80 | 1.5 m | 3 | 9 | 72 | 8 men unplaced |
  | Archers | 90 | 0.6 m | 1 | 10 | 36 | 54 men unplaced |

  The `max_by_headcount` valve only covers the opposite case (too few men to fill
  the shell). So Phase 2 needs at least a headcount-derived side length before
  Phase 3 replaces it with the fold-derived one; otherwise an implementer hits
  unplaced men on the first non-Spearmen unit tested.
- **Phase 3 --- derive the footprint from the fold.** Replace `ceil(sqrt(n))` as
  the primary footprint definition with the fold-derived side length; keep it as
  the degenerate-remnant fallback. Closes gap 3. Depends on phases 1-2.
- **Phase 4 (optional, later) --- ride #547.** Once explicit per-soldier slot
  ownership lands, re-express the fold as sub-unit orders ("your file wheels onto
  the east face") rather than a centralized layout recompute, making the identity
  guarantees first-class. Converges with #819 / #1033 at the larger scale.

## Cross-references

- [#1161](https://github.com/Lacaedemon/sparta/issues/1161) --- this design note's
  originating RFC.
- [#1146](https://github.com/Lacaedemon/sparta/issues/1146) --- proximity-paired
  square slots (merged); made this question visible.
- [#547](https://github.com/Lacaedemon/sparta/issues/547) --- explicit per-soldier
  slot ownership; the enabling primitive for phase 4.
- [#819](https://github.com/Lacaedemon/sparta/issues/819) /
  [#1033](https://github.com/Lacaedemon/sparta/issues/1033) --- persistent
  sub-units at century/company and group scale.
- [#1149](https://github.com/Lacaedemon/sparta/issues/1149) --- route-aware defect
  metric; the instrument, less necessary once the bug is structurally
  impossible, still useful as a guard.
- [#820](https://github.com/Lacaedemon/sparta/issues/820) --- standard-bearer; the
  thing a sub-unit historically forms *relative to*, and a natural occupant of a
  genuinely hollow core.
- `docs/REFORM_RESEARCH.md` --- the historical grounding for file-based cohesion.
- `docs/individual-collision-design.md`, `PLAN.md` --- the bottom-up-physics
  philosophy this note applies to drill.
