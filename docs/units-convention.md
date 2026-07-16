# Units convention: author in metres, store in world units

The simulation runs on **world units** (wu). The world scale lives in one
place — `scripts/WorldScale.gd`:

```gdscript
const WU_PER_M := 20.0
```

`Battle.WORLD_UNITS_PER_METER` re-exports it, so either name reads the same
value. At 20 wu/m, the 1600x1000 field is an 80 m x 50 m engagement frontage.

## The three rules

1. **Physically-derived constants are authored in metres and folded at parse
   time.** A length/speed constant whose value has real physical provenance is
   written as a metric expression:

   ```gdscript
   const FORMATION_SPACING: float = 0.45 * WorldScaleRef.WU_PER_M  # synaspismos density
   ```

   GDScript folds const expressions at script load — zero runtime cost, and
   the metric figure in the source *is* the documentation. Never the legacy
   style of a bare wu literal with a metric comment (`9.0  # 0.45 m`): the
   comment and the value can drift apart; the expression cannot.

2. **Runtime state stays world units.** Positions, velocities, radii, reaches
   — everything the sim computes with per tick — is wu end to end. No
   conversions in hot loops; the reference battle already sits at the 60 fps
   tick budget. The only metric→wu conversions at runtime are the loadout
   spawn in `Battle.gd` (gait speeds, weapon reach — converted once per unit
   at spawn) — plus the parse-time const folding above.

3. **Every user-facing number displays in metric.** Any rendering of a
   length, distance, or speed the player sees must route through
   `DistanceLegend.gd`'s wu→metric conversions (`metres_for_world`,
   `mps_for_world_speed`, and their label helpers). A raw world-unit number is
   never shown to the player.

## Deliberately NOT metric

Not every number wants a metric costume:

- **Tuned wu-scale knobs with no physical derivation** (steering strengths,
  follow speeds, gravity-as-balance-knob): keep the wu literal and mark it
  `# tuned in wu` so the lint and reviewers know the classification is
  deliberate. Dressing a tuned value in metres manufactures false physical
  provenance.
- **Solver thresholds and epsilons** (arrive/rest/velocity gates): these are
  convergence tolerances chosen against float behavior at wu magnitudes, not
  measured quantities. Leave them alone.
- **Dimensionless scalars** (fractions, multipliers, morale/stamina numbers):
  nothing to convert.

## Naming

Metric values carry `_m` / `_mps` / `_mps2` suffixes (the loadout table's
existing convention: `walk_mps`, `reach_m`). An unsuffixed length or speed in
sim code is world units by definition. No `_wu` suffix churn on existing
names.

## Enforcement

`tools/check.sh units` (in the default check set, and CI's
check-comment-citations workflow) lints the **added lines** of each diff:

- **Fails** on a runtime multiplication by `WU_PER_M` /
  `WORLD_UNITS_PER_METER` outside const initializers and the boundary files
  (`WorldScale.gd`, `Battle.gd`'s loadout spawn, `DistanceLegend.gd`,
  `test/`).
- **Fails** on a new bare float literal documented by a metric comment (the
  legacy style rule 1 replaces).
- **Warns** (review nudge, not a gate) on a new length/speed-named const with
  a bare literal and no `# tuned in wu` marker.

The lint pins boundary topology; it cannot prove dimensional correctness —
nothing in GDScript can (no units-of-measure types, no operator overloading).
Review carries the rest: a new player-visible length/speed rendered without
`DistanceLegend`, or a suffix mismatch across an assignment, is a standard
review finding.

## Determinism

Conversions must be **bit-exact**: every converted constant carries a
permanent exact-equality pin test (`assert_eq`, never `assert_almost_eq`)
written test-first against the unchanged wu value. A metric form that fails
its pin keeps the wu literal (with a metric comment) — a failed pin downgrades
to documentation, never to a value change. Value changes are balance changes:
their own PR, demo, and review.
