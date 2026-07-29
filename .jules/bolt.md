## 2024-07-22 - Optimize high-frequency loop distance calculations
**Learning:** In GDScript, `distance_to` computes an expensive square root. In high-frequency loops, such as per-soldier combat resolution in `SoldierMelee.gd` against all defending soldiers in an engaged block, using `distance_squared_to` and comparing it to the squared threshold distance significantly avoids compute overhead without breaking readability.
**Action:** Always prefer `distance_squared_to` over `distance_to` when evaluating thresholds (e.g. reach, range, contact) inside O(N^2) loops or hot paths like targeting and spatial queries.
## 2024-11-20 - Ensure zip files and .import changes don't get committed
**Learning:** When downloading headless Godot to run tests, Godot updates auto-generated `.import` files. Those changes, and the Godot zip file/executable, must not be committed.
**Action:** Always clean up downloaded tools and revert `.import` files modified by the headless engine run before committing.
## 2024-11-20 - Precompute loop invariants
**Learning:** Even trivial math like squaring a constant (`RANGED_RANGE * RANGED_RANGE`) should be precomputed before entering a high-frequency loop to squeeze out maximum performance and address review feedback about repeated recomputation.
**Action:** Always extract invariant math operations (like threshold squares) out of `for` and `while` loops.

## 2026-07-25 - Optimize high-frequency loop distance calculations in Unit AI
**Learning:** In GDScript, `distance_to` computes an expensive square root. In high-frequency O(N) loops like `Unit._think` or `Unit._support_tick` that run every frame for every unit, evaluating thresholds using `distance_squared_to` against a squared threshold is a low-risk, high-impact optimization that avoids the `sqrt` compute overhead.
**Action:** Always prefer `distance_squared_to` over `distance_to` when evaluating threshold ranges (e.g. `RANGED_RANGE`, `attack_range + RADIUS`, `SKIRMISH_KITE_DISTANCE`) in unit AI update loops.
## 2026-07-28 - Optimize minimum distance loop variables
**Learning:** When replacing `distance_to` with `distance_squared_to` inside loops that find the minimum distance, ensure the tracking variable (e.g., `nearest_dist`) is appropriately renamed to `nearest_dist_sq` and stores squared values for correct comparisons and maintainability.
**Action:** Always rename distance tracking variables to indicate they store squared values when applying the `distance_squared_to` optimization to prevent logical bugs later in the function.
