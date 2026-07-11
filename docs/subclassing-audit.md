# Audit: where would GDScript subclassing beat flag-based branching?

(#455) This is an audit, not a refactor mandate. It surveys the codebase for
`if`/`elif`/`match` chains that stand in for a genuine one-kind-forever
**tree**, where single inheritance would read better than a flag or enum, and
applies the same test the original `Unit` design discussion (#374) used to
rule inheritance *out* for `Unit`: **does any instance ever need two "kinds"
at once, or change kind at runtime?** If yes, composition/flags stay — GDScript
only has single inheritance, so a hierarchy breaks the moment a combinatorial
or mutable case shows up. If every instance genuinely has exactly one kind for
its whole life, subclassing is worth considering, but only where it
demonstrably improves readability/dispatch over the current branching.

## Correction to the issue's premise

The issue's background section says "`UnitRef` already `extends Unit` for one
clean reason." That's not accurate against the current (or any historical)
state of the code: `UnitRef` is a `preload("res://scripts/Unit.gd")` **const
alias** used purely for typed static access (`UnitRef.State.DEAD`,
`UnitRef.ORDER_HOLD`, ...), not a subclass — `grep -rn "extends Unit" .`
returns nothing anywhere in git history. In fact, as of this audit, **there is
no subclassing of any project-defined class anywhere in the codebase**: every
`class_name` extends only a Godot built-in (`Node2D`, `Resource`, `RefCounted`,
`Camera2D`, `CanvasLayer`, `AcceptDialog`, ...). This PR introduces the first
one (see Candidate 1).

## Candidates surveyed

### 1. Transient cosmetic effects (`Fallen`, `VolleyTrail`, `RoutShockwave`) — worth it, implemented here

Three purely-presentational `Node2D` classes (fallen-body heaps, arrow-volley
streaks, rout-shock ripples) each independently implemented the identical
"age up every frame, redraw, `queue_free()` once past `LIFETIME`" bookkeeping.
Each is spawned once via its own static `spawn()` factory, lives out one
lifetime, and frees itself — no instance is ever re-typed, combined with
another effect, or asked to be more than one kind. That's exactly the
"clean tree" case the issue describes, and here it's really a **degenerate
tree of one node per leaf** (no shared logic needing dispatch, no `match` on a
kind tag at all) — subclassing wins over the status quo not because there was
branching to eliminate, but because there was ~5 lines of identical
boilerplate duplicated three times with no dispatch involved either way.

Implemented as `scripts/TransientEffect.gd`: a small `Node2D` base owning
`_age`/`_lifetime` and the shared `_process()`. Each subclass keeps its own
`LIFETIME` constant (so `Fallen.LIFETIME` etc. stay directly referenceable,
matching the existing tests) and sets `_lifetime = LIFETIME` in its `spawn()`;
each subclass still owns its own `_draw()` entirely. This is about as small
and low-risk as a subclassing change gets: three private, single-purpose leaf
classes, no shared mutable state, no runtime reclassification, and full
existing test coverage (`test_fallen.gd`, `test_volley_trail.gd`,
`test_rout_shockwave.gd`) exercising the inherited behavior unchanged.

### 2. Order types (`Order.Type`, `docs/orders-queue-design.md`) — evaluated and correctly rejected already

This is the strongest candidate *shape* in the codebase — an order's `type`
genuinely is one mutually-exclusive kind at a time (MOVE, ATTACK, RELIEF,
WHEEL, ...), matching the issue's "clean tree" test on its face. The original
design doc (`docs/orders-queue-design.md`, "Taxonomy") explicitly sketched a
per-kind class hierarchy first (`MoveOrder`, `WheelOrder`, `AttackOrder`, ...)
and then chose a single tagged `Order` record with a `Type` enum instead,
noting "a tagged-record / enum-plus-data approach may beat a deep class tree
in places (evaluate during phase 1, per the avoid-nesting default)." PLAN.md's
compositionality pillar states the same conclusion project-wide: the orders
queue "explicitly rejects a deep nested order-tree/behavior-tree" in favor of
flat composition (phasing + macro-expansion) for legibility and determinism.

Why composition still wins here, beyond what the issue's tree test alone
would predict:

- **An order's `type` is read-only after construction, but the whole `Order`
  object itself is frequently *replaced*, not mutated in place** — the queue
  swaps in a fresh `Order` on every new player command, retirement, or
  interrupt. A class hierarchy doesn't remove that churn; it just relocates
  the same enum-like dispatch into `is`-checks or a virtual-method call per
  type, at every one of the ~10 call sites in `Unit.gd`/`Battle.gd` currently
  matching on `.type`.
- **Cross-cutting fields don't cleanly partition by type.** `guard`/
  `guard_param`/`guard_uid` (phase 4) apply to *any* order type, not one
  branch of a hierarchy; `phase` applies only to `MOVE` but is stored
  identically to every other field. A class-per-type split would need to
  either duplicate the guard/phase fields on every leaf class or push them
  back up to a common base — at which point the "base" already holds nearly
  everything and the leaf classes buy only the constructor-name sugar
  (`new_move()` static factories already give the same call-site clarity).
- **The transcript/replay format serializes `Order` as one flat shape.**
  Determinism (docs/orders-queue-design.md) depends on every order being the
  same replayable record; per-kind subclasses would need per-kind
  (de)serialization instead of the current single one.

Recommendation: no change. This is the one candidate that looks the most like
the issue's target case on the surface, but the design doc already ran the
evaluation the issue asks for and the codebase carries the reasoning inline —
re-confirming it here rather than re-litigating it.

### 3. `formation_mode` (tight/loose/square/shield-wall/testudo/...) — not worth it, for a reason beyond the issue's own test

`formation_mode` branching is scattered across four files (`Unit.gd`,
`UnitCombat.gd`, `FarTierRules.gd`, `SelectionManager.gd` — 34 references
total) and, unlike `Order.type`, each
unit genuinely has exactly one formation mode at a time with no combinatorial
overlap: the issue's "clean tree" test says yes.

But `formation_mode` fails a different, more basic test the issue doesn't
name: **it's mutable on a live object, in place, at will.**
`Unit._apply_formation_order()` does `formation_mode = mode` on the existing
`Unit` instance whenever a player gives a formation order — GDScript objects
cannot change their own class at runtime, so a
`Unit`/`TightFormationUnit`/`SquareFormationUnit`/... hierarchy would need to
destroy and recreate the whole `Unit` node (with all its per-soldier arrays,
signals, and scene-tree state) on every formation change, which is far more
invasive than the branching it would replace. This generalizes beyond
`formation_mode` specifically: **any "kind" that a single instance can
transition through during its lifetime is disqualified from subclassing
regardless of how tree-shaped the kind-space is**, because single-inheritance
GDScript has no reclassification story. Worth stating explicitly since the
issue's own test (combinatorial vs. tree) doesn't cover it, and this is the
concrete case that would otherwise look like a false positive.

The current shape — a plain `int` field plus scattered `match`/`if` dispatch,
some of it already factored into small pure static helpers
(`FarTierRules.gd`'s multiplier table) — is already the project's chosen
mitigation, and PLAN.md's #530/#534 direction is replacing the *multiplier*
abstraction with real per-soldier geometry, not introducing a class
hierarchy. Recommendation: no change.

### 4. HUD widgets and controls — no branching pattern to fix

The issue specifically asks about "HUD widgets/controls with type-tagged
branching logic." `HUD.gd` is a single 900-line `CanvasLayer` script with no
`.tscn`-defined widget hierarchy (deliberate per PLAN.md: "UI is built in code
... simpler, fewer scene files to corrupt"). Its two `match` blocks
(`_on_menu_id`, keyed on a `MenuButton` popup item id) dispatch **actions on
one singleton menu**, not behavior across multiple type-tagged widget
*instances* — there's exactly one `MenuButton`, so there's nothing to
subclass. The per-mode data (`_STANCE_ENTRIES`, `_FORMATION_NAMES`) is already
a single source-of-truth table rather than duplicated per-case logic, which is
the composition-friendly shape the issue is steering toward anyway. The only
other UI scripts (`KeybindingsDialog.gd`, `ShortcutsOverlay.gd`,
`MainMenu.gd`) are each already a single-purpose class extending a distinct
Godot built-in (`AcceptDialog`, `Control`) — no shared "widget kind" dispatch
exists to replace. No candidate here.

## Other areas checked, ruled out quickly

- **Projectiles (`ProjectileField.gd`):** plain-data parallel arrays (SoA), no
  node per projectile and no branching on a projectile "kind" at all yet
  (only one variant, the ranged volley, exists). This is a
  performance-motivated design (PLAN.md's 60fps-at-scale target explicitly
  rules out per-entity heap objects at this entity count) — the opposite
  direction from subclassing, not merely a non-candidate.
- **`Weapon`/`Shield` (`Weapon.gd`, `Shield.gd`):** already flat, shared,
  interned `Resource` data records with no per-type branching logic anywhere
  — PLAN.md's stated direction for #535 is exactly this shape ("concrete
  shared `Type` objects plus per-soldier array state, not per-soldier
  heap-allocated objects"), already achieved.
- **`OrderGuards.gd` (`Order.Guard`):** same shape and same reasoning as
  Candidate 2 — a small, explicitly bounded, closed enum dispatch
  (docs/orders-queue-design.md calls out "never inline scripting on the order
  itself" as the point). Grouped with Order rather than a separate entry.
- **Campaign layer (`scripts/campaign/*.gd`):** factions and provinces are
  plain dictionaries loaded from data-driven JSON (#125), not typed objects —
  no class-per-faction/province pattern exists to evaluate.

## Summary

| Candidate | Combinatorial or mutable? | Verdict |
|---|---|---|
| Transient effects (`Fallen`/`VolleyTrail`/`RoutShockwave`) | No — one kind, whole lifetime, never combined | **Worth it — implemented** (`TransientEffect` base) |
| Order types | No (tree-shaped), but `Order` objects are frequently replaced wholesale and cross-cutting fields (guard, phase) don't partition by type | Not worth it — already evaluated and rejected in the original design |
| `formation_mode` | Tree-shaped, but **mutable at runtime** on a live `Unit` | Not worth it — runtime reclassification isn't expressible in single-inheritance GDScript regardless of tree shape |
| HUD widgets | N/A — no type-tagged instance dispatch exists | No candidate |

Net effect of this audit: one small, low-risk subclassing refactor
(`TransientEffect`) that removes real duplication with zero behavior change,
and three explicit "no action" verdicts with the specific reasoning recorded
so a future session doesn't need to re-derive it.
