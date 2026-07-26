## 2024-07-22 - Optimize high-frequency loop distance calculations
**Learning:** In GDScript, `distance_to` computes an expensive square root. In high-frequency loops, such as per-soldier combat resolution in `SoldierMelee.gd` against all defending soldiers in an engaged block, using `distance_squared_to` and comparing it to the squared threshold distance significantly avoids compute overhead without breaking readability.
**Action:** Always prefer `distance_squared_to` over `distance_to` when evaluating thresholds (e.g. reach, range, contact) inside O(N^2) loops or hot paths like targeting and spatial queries.

## 2026-07-25 - Optimize high-frequency loop distance calculations in Unit AI
**Learning:** In GDScript, `distance_to` computes an expensive square root. In high-frequency O(N) loops like `Unit._think` or `Unit._support_tick` that run every frame for every unit, evaluating thresholds using `distance_squared_to` against a squared threshold is a low-risk, high-impact optimization that avoids the `sqrt` compute overhead.
**Action:** Always prefer `distance_squared_to` over `distance_to` when evaluating threshold ranges (e.g. `RANGED_RANGE`, `attack_range + RADIUS`, `SKIRMISH_KITE_DISTANCE`) in unit AI update loops.
