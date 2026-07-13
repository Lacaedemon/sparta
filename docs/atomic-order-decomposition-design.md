# Design note: atomic order decomposition (nested order tree)

Status: **design draft, no code yet**. Tracks [#822](https://github.com/Lacaedemon/sparta/issues/822).
Builds on [`orders-queue-design.md`](orders-queue-design.md) (phases 1-4
landed) but **overrides one of its decisions** — see "Relationship to the
existing design" below.

## The ask

From discussion following #818 (checkerboard form-up, whose reform-hold added
a *third* bare-field phased mechanism alongside the two `orders-queue-design.md`
already documents):

1. **Atomic orders.** An order should represent exactly one primitive action —
   march straight forward, step back, turn in place, halt, charge forward,
   etc. — never a composite that internally cycles through phases.
2. **Hierarchical decomposition, genuinely nested.** A complex player command
   decomposes into a *tree* of orders, not a flat list tagged with a shared
   group id: a drag-line command contains per-unit commands, each of which
   contains the atomic steps that get that one unit there. Depth isn't capped
   at two levels (one macro of atomic steps) — a command can decompose into
   commands that themselves decompose further.
3. **HUD visibility.** The unit stats panel should show the order queue/tree,
   with expand/collapse so a player can unfold a composite command into its
   nested children.

**Why nesting specifically, not just "a way to group related orders":**
conceptual chunking, for both a human player and the battle AI. Examining a
unit's order queue should read as a clear conceptual structure ("rear move",
"form up") with detail available on demand, not a flat stream of atomic
orders with no visible grouping the reader has to reconstruct by hand. This
applies as much to `General.gd`/`Subcommander.gd` introspecting a unit's
current activity at a high level as it does to a player reading the HUD —
both want "what is this unit conceptually doing" as the default view, with
the atomic breakdown one expand away, not the only view available.

## Relationship to the existing design

`orders-queue-design.md`'s "Composability" section explicitly considered and
rejected a nested order-tree, citing three reasons: "more machinery than the
domain needs," "harder to serialize deterministically," and that "it cuts
against the avoid-nesting default."

**The third reason is a category error and this design doesn't carry it
forward.** `shared/coding/avoid-nesting.md` (the source of that "default") is
a code-style guideline about **function calls and function definitions** —
prefer named intermediates over `f(g(h(x)))`, prefer top-level functions over
functions defined inside other functions. It says nothing about whether a
*data structure* (an order queue) should be a tree or a flat list. Nesting
*data* to represent genuinely hierarchical *domain* structure (a command that
contains sub-commands) isn't the thing that guideline is about, and citing it
against a data model was a mismatch.

The other two reasons are real engineering tradeoffs, not category errors, and
this design has to actually address them rather than wave them away:

- **"More machinery than the domain needs"** — true in the sense that a tree
  needs traversal/promotion logic a flat list doesn't. Addressed below by
  keeping the tree shallow in practice (group → per-unit → atomic steps is
  the common case, maybe 2-3 levels) and reusing the flat queue's existing
  primitives (`append_order`/`retire_current_order`) at each level rather than
  inventing a fourth mechanism from scratch.
- **"Harder to serialize deterministically"** — real, and worth being precise
  about: the *tree structure itself* (which children under which parent, in
  what order) is static once built (constructed once at decomposition time,
  from the same deterministic inputs — unit positions, drag geometry — every
  other order-issuing path already uses), so it serializes exactly like any
  other order field. What's dynamic is the traversal CURSOR (which node is
  currently the active leaf) — that's a small, explicit piece of state (see
  "Advancement" below), not an open-ended amount of hidden machine state.

## Data model

```gdscript
# On Order (scripts/Order.gd):
var children: Array[Order] = []   # nested sub-orders; empty = a genuine leaf/atomic order
var _active_child: int = 0        # index into children of the currently-executing sub-order
```

A **leaf** order (`children.is_empty()`) is what "atomic" means concretely: it
has no further decomposition, and it's the thing that actually drives
`Unit._think()`'s movement/turn logic each tick (a plain `MOVE`, a `REFORM`,
an in-place turn, `WHEEL`, `NUDGE`, etc. — the same primitive verbs
`orders-queue-design.md` already taxonomizes, unchanged).

A **composite** order (non-empty `children`) is a container: a `MOVE`-flavored
order representing "get this unit to X, however many steps that takes" whose
children are e.g. `[in-place-turn, REFORM, MOVE]` (the rear-move composite,
rebuilt as real children instead of `Order.Phase`), or a `FORM_UP`-flavored
order at the very top of the tree whose children are one composite order PER
UNIT in the drag selection (the group-level decomposition
`SelectionManager._checkerboard_slices` already computes — this design just
gives its output a home in the tree instead of N independent flat Battle
commands).

## The active leaf and advancement

`Unit.current_order` still names the **top-level** order the unit is
executing (what a player issued) — nothing about the transcript's top-level
"what is this unit doing" legibility changes. A new accessor walks down to the
actually-executing node:

```gdscript
## The genuinely atomic order actually driving this tick's movement/turn --
## walks children[_active_child] recursively until it finds a leaf.
func active_leaf() -> Order:
    var node := current_order
    while node != null and not node.children.is_empty():
        node = node.children[node._active_child]
    return node
```

`Unit._think()` reads/advances `active_leaf()` instead of `current_order`
directly for the actual movement/turn logic (mirroring exactly how it reads
`current_order.phase` today — this is a small, mechanical rewrite of that
read site, not a new way of thinking about what drives a tick).

**Completing a leaf** advances the cursor at its PARENT: increment
`parent._active_child`. If that runs past the parent's own `children.size()`,
the PARENT itself just completed — recurse the same completion one level up
(increment ITS parent's `_active_child`), cascading until either a parent has
a next child to start, or the cascade reaches the top (`current_order`
itself is done, and `Unit.retire_current_order()` runs exactly as it does
today for a flat queue entry).

This is the same shape as `retire_current_order`/`_start_promoted_move`
already use for the FLAT queue — promoting the next entry and re-running
whatever "commit this order's first tick" logic that order type needs. The
tree version just runs that logic one level higher (at whichever ancestor's
turn it now is) instead of only ever at `Unit.orders`'s own head.

## What this replaces

- **`Order.Phase`** (`TURN`/`MARCH`/`REFORM`/`RETURN_TURN`) — the rear-move and
  lateral-pivot composites' internal phase field becomes real `children`
  instead. Whether `Order.Phase` can be deleted entirely once nothing builds a
  phased order is an open question (check every reader, including the
  transcript format, before removing).
- **#818's bare reform-hold fields** (`Unit._reform_timer`/`_reform_target`/
  `_reform_until_settled`/`_reform_settle_eps`) — become a REFORM leaf order's
  own fields (it needs the same settle-gated-hold data either way; the
  question is just whether that state lives on loose `Unit` fields or on the
  order node that represents it). This closes the original, narrower #822 gap
  (three parallel "hold, then commit" mechanisms) the same way as the
  composites above, not as a fourth mechanism.
- **`Unit.enqueue_macro`/`cancel_macro`'s `macro_id` tag** — superseded by
  real parent/child structure for anything that needs "these steps belong
  together." `macro_id` may still be worth keeping for the shallow case of "a
  few unrelated-otherwise orders that should cancel as a unit" if that comes
  up again, but the checkerboard/rear-move/lateral-pivot cases this design is
  actually about are better modeled as genuine children, not sibling entries
  sharing a tag.

## The #517/#518 regression risk (inherited concern, still applies)

The reason `orders-queue-design.md` chose *some* form of composition over
raw separate state mutations in the first place: dispatching the about-face
and the march as **independent state mutations** through the *old*
immediate-plus-drain double-apply path raced, and the second apply cancelled
the conversio mid-turn (#517/#518, already shipped and fixed). A nested tree
still needs to confirm it doesn't reopen that door: the tree's advancement
(`retire_current_order`-style promotion, one level up) has to run through the
SAME exactly-once apply path every other order transition already uses, not
a new ad hoc trigger. Verify this empirically (a live-battle GUT test
exercising the original race's conditions against a tree-based rear-move)
before relying on it, not just by analogy to the flat-queue case.

## HUD: the tree renders naturally

Once the queue genuinely nests, the unit stats panel's order display is a
direct tree render — no synthetic grouping-by-tag needed: `current_order`'s
own `describe()` (already exists) as the top row, indented children under it
recursively, with the currently-active leaf highlighted (`active_leaf()`) and
a expand/collapse control per composite node. This is pure UI, no sim
changes, and can land independently of the data-model work above (it can
start against today's FLAT queue, rendering every entry as a single-level
list, then automatically gain real nesting once the tree lands underneath it
with no further UI changes needed — `describe()`'s contract doesn't change).

## Suggested phasing (still a multi-PR effort)

- **Slice 0:** the `Order.children`/`_active_child`/`active_leaf()` data
  model itself, with the advancement/cascade logic, proven on a single
  composite (rear-move) end to end — including the #517/#518 regression test.
  Nothing else migrates yet.
- **Slice 1:** lateral-pivot composite onto the same mechanism.
- **Slice 2:** #818's form-up reform-hold onto a REFORM leaf order, retiring
  the bare fields.
- **Slice 3:** the group-level `FORM_UP` composite (checkerboard's per-unit
  split becomes real tree children instead of N independent `Battle`
  commands) — the piece that actually realizes "hierarchical decomposition
  by group-level AI" for a drag-line order specifically.
- **Slice 4:** HUD order-tree display — independent, could land first or in
  parallel with any of the above.

## Open questions

- Does `retire_current_order`'s existing MOVE/ATTACK promotion special-casing
  extend cleanly to "promote the next child at whatever ancestor level," or
  does it need a real rewrite (not just a recursive wrapper) once promotion
  can happen at any tree depth, not just at the flat queue's own head?
- Is `Order.Phase` fully removable once the two composites currently using it
  are ported, or does something else (transcript format stability for
  existing replays, a test) still expect it to exist?
- `macro_id`/`cancel_macro`: keep as a separate, shallower mechanism for a
  different future case, or remove now that its two real uses (this design's
  own composites) are moving to genuine children?
