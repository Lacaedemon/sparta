# Design note: acies triplex (checkerboard spacing + persistent lines)

Status: **phase 1 landed** — checkerboard (quincunx) spacing as a new multi-unit
form-up distribution mode (`SelectionManager.FormUpDist.CHECKERBOARD`). Persistent
line-membership state, cavalry-flank-vulnerability tradeoffs, and century-level
partial withdrawal are **not yet built** — tracked in
[#819](https://github.com/Lacaedemon/sparta/issues/819), see "Deferred" below.

Tracks [#805](https://github.com/Lacaedemon/sparta/issues/805) (phase 1, closed) and
[#819](https://github.com/Lacaedemon/sparta/issues/819) (the remaining phases). Builds on
[#377](https://github.com/Lacaedemon/sparta/issues/377) (passage of lines,
merged), which built the *tactical* relief-swap (pairing N fresh units to N
tired ones in one gesture) but not the *spatial* checkerboard arrangement those
swaps would happen within.

## Historical background

The Roman **acies triplex** (Camillian reforms, 4th century BCE) deployed
infantry in three lines — hastati, principes, triarii — each made of maniples
(120-150 soldiers, six ranks) with **gaps between maniples roughly matching
their own frontage width**. The line behind was offset so its maniples covered
those gaps: a checkerboard (quincunx) pattern. Sources:

- Polybius VI — the primary ancient source for the manipular system (already
  cited by #377/#378).
- Vegetius, *De Re Militari* — cited in `REFORM_RESEARCH.md` for rank-closing
  procedures; also documents the acies triplex's discipline advantage (troops
  held formation rather than pursuing recklessly).
- [imperiumromanum.pl, "Acies Triplex: Roman Triple Formation"](https://imperiumromanum.pl/en/roman-army/military-formations-of-ancient-romans/acies-triplex/amp/) —
  secondary source: maniple size, cavalry deployed on the flanks in ten
  divisions, and a named weakness — **insufficient cavalry was the system's
  greatest vulnerability for protecting the flanks and rear**, since a gapped,
  multi-line infantry formation trades frontage flexibility for flank exposure.
  Also: the rear CENTURY of a maniple (not the whole maniple) withdrew into a
  gap first, letting the front century keep fighting — a more granular
  withdrawal than #377's whole-unit swap.

## What phase 1 builds

A new `FormUpDist` mode, `CHECKERBOARD`, selectable the same way as the
existing four modes (Y to cycle, ☰ Menu → Form-up distribution to enable/
disable it in the cycle). When active, a multi-unit drag-to-form-up (`Battle.
enqueue_form_up`) alternates the ordered selection into two rows instead of one
line:

- **Front row** (units at even ordinal position: 1st, 3rd, 5th, ...) forms up
  along the dragged `a`->`b` line exactly like the other four modes, except the
  gap between adjacent front-row units is widened to roughly **that unit's own
  frontage width** (`CHECKERBOARD_GAP_SCALE * files * FORMATION_SPACING`)
  instead of the flat `MULTI_FORM_UP_GAP` — the quincunx "gap ≈ own frontage"
  rule.
- **Rear row** (units at odd ordinal position: 2nd, 4th, ...) is placed at the
  lateral midpoint of each front-row gap, offset backward (away from the
  facing direction) by `CHECKERBOARD_LINE_GAP` world units — enough depth that
  the two rows read as visually and physically distinct lines rather than one
  crowded block.
- If the rear row has one more unit than the front row has internal gaps (an
  even total selection splits evenly, so there's no back-row-fits-a-gap
  parity — see `_checkerboard_slices`'s own doc comment), the trailing rear
  unit is placed past the front row's own flank at the same lateral pitch,
  rather than left with no slot.

This is a **read-only layout change**: it reuses `Battle.enqueue_form_up` per
unit exactly like the other four modes (each unit is still routed as its own
recorded form-up order), so replays, the orders queue, and every other
consumer of a form-up command are untouched. No new sim/combat mechanics.

## Deferred (tracked in [#819](https://github.com/Lacaedemon/sparta/issues/819))

- **Persistent line-membership state.** `General.gd`'s reserve-commit logic
  (#586/PR #794) is an army-composition decision — which units join the fight
  at all — not a spatial "this unit belongs to line 2, standing in reserve
  behind a gap" concept. Nothing currently models line membership as
  persistent formation state; a checkerboard form-up today is a one-shot
  layout, not a standing arrangement a unit remembers.
- **Cavalry-flank-vulnerability tradeoff.** The historical system's chief
  weakness (thin cavalry can't cover the flanks of a gapped multi-line
  formation) isn't modeled — a checkerboard-formed army isn't currently more
  vulnerable to flanking than a solid line.
- **Century-level partial withdrawal.** The historical rear-century-first
  withdrawal needs per-sub-unit granularity that doesn't exist yet — gated
  behind [#547](https://github.com/Lacaedemon/sparta/issues/547) ("Rethink
  slot: explicit per-soldier slot ownership"). #377's passage-of-lines and
  #802's target-slot work both operate at the whole-`Unit` level.
- **Command-structure spatial analog.** `General.gd` (#586) already splits an
  army into multiple `groups` by doctrine, and `Subcommander.gd` (#585)
  independently manages each group's line integrity — a genuine
  decentralized-command analog — but those groups aren't tied to the
  checkerboard's spatial arrangement.

## Relationship to other design docs

- [`REFORM_RESEARCH.md`](REFORM_RESEARCH.md) — the single-unit reformation
  research (File-Closure Principle, Hysteresis in Reformation Decisions) this
  issue's multi-unit, whole-battle-line-composition counterpart builds on.
- Parent: [#362](https://github.com/Lacaedemon/sparta/issues/362) (implement a
  variety of unit maneuvers).
