# Design note: atomic order decomposition

Status: **design draft, no code yet**. Tracks [#822](https://github.com/Lacaedemon/sparta/issues/822).
Builds directly on [`orders-queue-design.md`](orders-queue-design.md) (phases
1-4 landed) — this note doesn't replace that design, it proposes changing
which of its two composition mechanisms (intra-order phasing vs. macro
expansion) the movement composites use.

## The ask

From discussion following #818 (checkerboard form-up, whose reform-hold added
a *third* bare-field phased mechanism alongside the two `orders-queue-design.md`
already documents):

1. **Atomic orders.** An order should represent exactly one primitive action —
   march straight forward, step back, turn in place, halt, charge forward,
   etc. — not a composite that internally cycles through phases.
2. **Hierarchical decomposition.** A complex player command (a multi-unit
   drag-line form-up in particular) should be broken down automatically into a
   queue of atomic orders, by group- and/or unit-level AI:
   - **Group level:** a drag-line command covering N units decomposes into N
     per-unit destinations/facings/frontages. **Already built** —
     `SelectionManager._form_up_slices`/`_checkerboard_slices` compute exactly
     this split today.
   - **Unit level:** each unit's own resulting move should further decompose
     into whatever sequence of genuinely atomic orders gets it there in good
     order — turn-in-place, then march, then (if needed) a distinct reform —
     rather than one order type with reform-then-march baked in as internal
     phases.
3. **HUD visibility.** The unit stats panel should show the order queue (not
   just `current_order`), with expand/collapse for a macro-grouped composite
   so a player can unfold it into the underlying atomic steps.

## What already exists (read this before designing further)

`orders-queue-design.md`'s "Composability" section names **two** mechanisms
and picks one for the movement maneuvers, for a specific, documented reason:

- **Intra-order phasing** (`Order.Phase`: `TURN` → `REFORM` → `MARCH` →
  `RETURN_TURN`) — one `Order` object carries its own internal choreography.
  This is what the rear-move (about-face) and lateral-pivot composites use
  today, and #818's form-up reform-hold added a *third*, parallel,
  **non-integrated** copy of the same idea as bare `Unit` fields
  (`_reform_timer`/`_reform_target`/`_reform_until_settled`/
  `_reform_settle_eps`) instead of `Order.Phase` — tracked as its own gap in
  #822 before this expanded discussion.
- **Macro expansion** (`Unit.enqueue_macro(steps: Array[Order])`) — a
  sequence of separate, genuinely atomic orders appended to the flat queue
  under one shared `macro_id`, so `cancel_macro` can drop the
  not-yet-executed remainder as a unit. **This is exactly what point 2 above
  is asking for — and it already exists.** `Unit.gd`'s own comment on it:
  "No maneuver expands itself into a macro yet."

**Why phasing was chosen for the rear-move composite specifically, and why
that reason matters here:** the design doc's own rationale (`orders-queue-
design.md` §Composability, "Intra-order phasing (the core)") is that
dispatching the about-face and the march as **separate state mutations**
through the *old* immediate-plus-drain double-apply path raced and let the
second apply cancel the conversio mid-turn (issues #517/#518 — a real, already-
shipped bug this design fixed). That specific race lived in the *live-input
dispatch* path (`Battle._apply_order_live`/`_apply_order_cmd`'s exactly-once
tagging), not in the queue/promotion machinery itself. `enqueue_macro` appends
through `append_order`/`retire_current_order`, the same queue-promotion path a
queued waypoint leg already uses safely — so decomposing into a **macro**
(separate queue entries) is not the same shape as the original #517/#518 bug,
but this needs to be verified empirically before/while implementing, not just
assumed by analogy.

## Proposed direction

Replace intra-order phasing for the movement composites with macro expansion,
and put #818's form-up reform-hold on the same mechanism instead of a third
bare-field copy:

1. **New atomic order types** for the pieces phasing currently hides inside
   one `Order`:
   - An in-place turn (subsumes the rear-move's `TURN` phase and the lateral-
     pivot's own turn — these may already be expressible via the existing
     `ABOUT_FACE`/`QUARTER_TURN` standalone types rather than needing a new
     one; check before adding a type).
   - A **REFORM** order: settle-gated hold that reshapes the ranks square to
     the unit's current heading (the rear-move's `REFORM` phase) — or, more
     generally after generalizing #818's `_reform_bodies_settled`/
     `_reshape_timeout`, ANY reshape-and-wait, including a form-up's frontage
     change. This is the direct replacement for #818's bare `_reform_timer`/
     `_reform_until_settled`/`_reform_settle_eps` fields.
   - `MOVE` (already atomic — a plain march) as the final step.
2. **Rebuild the rear-move and lateral-pivot composites as `enqueue_macro`
   sequences** of the above, instead of one `Order` with an internal `Phase`.
   `Order.Phase` may become unnecessary once both composites move off it —
   confirm no other caller depends on it before removing.
3. **Rebuild #818's form-up reform-hold as a macro** (a REFORM order, then a
   MOVE order) instead of the bare-field mechanism, closing the gap the
   original (narrower) #822 was filed for.
4. **Extend queue promotion** (`Unit._start_promoted_move`) to handle
   promoting a REFORM (or in-place-turn) order correctly — today promotion
   only special-cases `MOVE`/`ATTACK` and explicitly assumes "the phased
   composite is only ever built on a fresh order at the apply site," i.e. a
   *promoted* queue entry currently never gets rear-move/lateral-pivot
   treatment. Moving to macros changes this: a promoted REFORM/turn order
   needs its own correct promotion behavior, not a special case to preserve.
5. **HUD: show the order queue.** Add a queue view to the unit stats panel —
   `current_order.describe()` plus the queued remainder, each queue entry
   showing its own one-line description (`Order.describe()` already exists
   for transcripts/logs — reuse it). Group entries sharing a `macro_id` under
   one collapsed row by default ("Form up" / "Rear move"), with an
   expand/collapse control to reveal the underlying atomic steps. This is
   pure UI, no sim changes, and can land independently of 1-4.

## Suggested phasing (this is a multi-PR effort, like acies-triplex)

Given the size (touches `Order.gd`, `Unit.gd`'s promotion logic, `Battle.gd`'s
dispatch, and `HUD.gd`), don't attempt this as one PR:

- **Slice A:** verify the #517/#518 non-regression claim above empirically
  (a live-battle GUT test exercising the OLD race conditions against a
  macro-based rear-move, confirming it doesn't reproduce), then rebuild the
  rear-move composite alone as a macro. Smallest, most isolated maneuver to
  convert first (already has extensive test coverage to catch a regression).
- **Slice B:** lateral-pivot composite, same treatment.
- **Slice C:** #818's form-up reform-hold onto the same REFORM-order
  mechanism, retiring the bare `_reform_timer`/`_reform_until_settled`/
  `_reform_settle_eps` fields.
- **Slice D:** HUD order-queue display (independent of A-C; could land first
  or in parallel, since it only reads `current_order`/`orders` and
  `Order.describe()`, all of which already exist today).

## Open questions

- Does an in-place turn need a genuinely NEW `Order.Type`, or do the existing
  `ABOUT_FACE`/`QUARTER_TURN` standalone types already cover it once queued
  via a macro instead of created ad hoc by `Unit.conversio()`/`quarter_turn()`?
- Once nothing builds a `Phase`-carrying `Order`, is `Order.Phase` and its
  four-way state machine safe to delete entirely, or does something else
  (the transcript format, a test) still depend on its existence?
- Slice A's regression test: what's the minimal reproduction of the original
  #517/#518 race, so "doesn't reproduce" is actually falsifiable rather than
  just "no test caught anything"?
