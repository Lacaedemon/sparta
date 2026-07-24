## 2024-07-22 - Optimize high-frequency loop distance calculations
**Learning:** In GDScript, `distance_to` computes an expensive square root. In high-frequency loops, such as per-soldier combat resolution in `SoldierMelee.gd` against all defending soldiers in an engaged block, using `distance_squared_to` and comparing it to the squared threshold distance significantly avoids compute overhead without breaking readability.
**Action:** Always prefer `distance_squared_to` over `distance_to` when evaluating thresholds (e.g. reach, range, contact) inside O(N^2) loops or hot paths like targeting and spatial queries.
## 2024-11-20 - Ensure zip files and .import changes don't get committed
**Learning:** When downloading headless Godot to run tests, Godot updates auto-generated `.import` files. Those changes, and the Godot zip file/executable, must not be committed.
**Action:** Always clean up downloaded tools and revert `.import` files modified by the headless engine run before committing.
