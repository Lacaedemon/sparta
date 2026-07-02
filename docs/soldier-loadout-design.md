# Design note: soldier weapon/shield loadout

Status: **phases 1-2 implemented** (#536, #537): the `Weapon`/`Shield` type
classes, the interned `LoadoutRegistry`, the per-soldier id arrays, and the
per-soldier shield hold-angle state are in the code, with the weapon type as
the single source of truth for spawn-time reach. The strike-time combat-read
re-express (#571, split out of phase 1) is implemented too: melee reads
lethality through the attacker's weapon id and composes the defensive shield
weight as the type's stance residual plus the struck soldier's shield
`block_value` (see phase 1 below). Phases 3-4 (#538-#539) are design-only so
far.

## Motivation

The combat model (`docs/combat-model.md`) already gives each soldier type fixed
attributes — skill, armour, shield, lethality, reach, mass — but before phase 1
they lived as magic numbers and dictionary keys: `_default_loadout()` in
`scripts/Battle.gd` was an `Array` of untyped `Dictionary` literals
(`"reach_m": 2.4`, `"atk": 11`), and `Battle._spawn_unit` read them into scalar
fields defined on `Unit` (`attack`, `defense`, `attack_range`) at spawn time.
There was no `Weapon` or `Shield` object anywhere — "spear" was a string name
plus a handful of loose numbers, not a thing.

The owner's directive: model weapons and shields as **concrete classed
objects** — real fields and methods, not an enum or a dictionary of magic
numbers — because "we want to keep making our object taxonomy more and more
concrete."

The catch: **soldiers themselves are not objects.** Per-soldier state lives in
parallel `Packed*Array`s on `Unit` — `_sim_soldier_pos`, `_sim_body_vel`,
`_sim_steer`, `_sim_soldier_facing` (four `PackedVector2Array`s, 8 bytes each)
and `_sim_soldier_hp`, `_sim_prone`, `_sim_soldier_stamina` (three
`PackedFloat32Array`s, 4 bytes each) — deliberately, for performance: roughly
`4*8 + 3*4 = 44` bytes/soldier by this author's count of `Unit.gd`'s current
`_sim_*` arrays (not a cited figure from CLAUDE.md — CLAUDE.md documents the
SoA pattern and its rationale, but not this byte count), feeding `MultiMesh`
rendering, sized for hundreds of soldiers per unit across many units per
battle. A literal "one `Weapon` object + one `Shield` object per soldier"
instantiates two extra heap `RefCounted`s per soldier — real allocation and
cache-locality cost the array-of-structs design exists to avoid. Concreteness
and the SoA hot loop pull in opposite directions, so this
doc resolves the tension before any code changes.

## The model: shared TYPE objects, per-soldier INSTANCE arrays

Split what's genuinely per-*type* from what's genuinely per-*soldier*:

- **`Weapon` and `Shield` are real GDScript classes** (`class_name Weapon`,
  `class_name Shield`) with concrete fields and methods — reach, damage
  profile, defense/block value, default hold pose — but as **shared, interned
  type definitions**. One instance per weapon/shield *type*
  (`WEAPON_SPEAR`, `SHIELD_SCUTUM`, ...), not one per soldier. Godot `Resource`
  semantics: loaded once at startup, referenced by id many times, never
  mutated after load.
- **Each soldier references its active loadout by id**, not by object — new
  parallel arrays on `Unit`, index-aligned with `_sim_soldier_pos` exactly like
  the existing `_sim_soldier_hp` / `_sim_soldier_stamina`:
  - `_sim_soldier_weapon_id: PackedInt32Array`
  - `_sim_soldier_shield_id: PackedInt32Array`
- **Per-soldier STATE that genuinely varies** also lives in parallel arrays,
  never inside the shared type object (putting mutable per-soldier state on
  the type object would defeat interning — two soldiers carrying the same
  scutum must not be able to fight over one shared "current hold angle"):
  - `_sim_soldier_shield_hold_angle: PackedFloat32Array` — current hold
    angle/offset relative to the body: resting, bracing, raised.
  - a bracing/active-weapon flag array where a soldier can carry more than
    one weapon (phase 4; not needed for phase 1's single-weapon-per-type
    roster).

The type classes hold what's fixed per type (reach, damage, defense, default
hold pose); the per-soldier arrays hold what varies per instance (which type
is currently equipped, current hold state). This mirrors the pattern already
used for per-type combat/movement stats on `Battle._default_loadout` — the
data doesn't get duplicated per soldier there either, it gets read once at
spawn and stored as a scalar on `Unit`. The new piece is that the *type* data
itself becomes a real object instead of a dictionary literal, and the
per-soldier reference becomes an id into a registry instead of a copied
scalar.

### Sketch: `Weapon`

```gdscript
class_name Weapon
extends Resource

@export var id: int
@export var display_name: String
@export var reach_m: float          # melee range in metres
@export var lethality: float        # wounding power, feeds SoldierMelee
@export var default_hold_angle: float  # rest pose, radians relative to facing

func effective_reach(terrain_speed_multiplier: float) -> float:
    return reach_m * terrain_speed_multiplier
```

(Sparta has no `Terrain` class — terrain is a plain `Array` of `Dictionary`
patches, `Battle.TERRAIN`, and a speed multiplier at a position is looked up
via `PathField.active.speed_at(position) -> float`, as `Unit.gd:884` already
does for movement. `effective_reach` would take that same multiplier as a
plain `float`, not an object, consistent with how the rest of the sim reads
terrain.)

### Sketch: `Shield`

```gdscript
class_name Shield
extends Resource

@export var id: int
@export var display_name: String
@export var block_value: float      # folds into the defence contest
@export var arc_deg: float          # degrees of coverage centred on hold angle
@export var default_hold_angle: float

func covers(attack_angle: float, hold_angle: float) -> bool:
    return absf(wrapf(attack_angle - hold_angle, -PI, PI)) <= deg_to_rad(arc_deg) * 0.5
```

`SHIELD_NONE` is a real interned instance too (`block_value = 0.0`,
`arc_deg = 0.0`), not a null check scattered through combat — Archers carry
it today (see the registry sketch below: Cavalry get the lighter
`SHIELD_ROUND`, not `SHIELD_NONE`), so callers already need a "no shield"
case; giving it an object keeps `covers()` uniform instead of an
`if shield_id == -1` special case at every call site.

## Type registry sketch

`scripts/Battle.gd`'s `_default_loadout()` fields four unit types —
Spearmen, Infantry, Archers, Cavalry — each with one
melee weapon (a `reach_m`) and an implicit shield weight already hardcoded per
type in `SoldierCombat.profile_for()` (`scripts/SoldierCombat.gd:63-71`): a
`"shield"` value of 0.65 for Spearmen (anti-cavalry), 0.60 for Infantry, 0.05
for Archers (ranged), 0.25 for Cavalry. That gradient is exactly what
motivates the table below — Spearmen/Infantry already carry a large shield's
worth of block value, Archers next to none, Cavalry something in between.
Phase 1 does not invent new unit types or new weapons; it names what already
exists concretely:

| id | type | reach_m (was `_default_loadout`'s literal, now `LoadoutRegistry`) | carried by |
|---|---|---|---|
| `WEAPON_SPEAR` | spear | 2.4 | Spearmen |
| `WEAPON_GLADIUS` | short sword | 1.3 | Infantry |
| `WEAPON_SIDEARM` | archer's melee backup (dagger/knife) | 0.6 | Archers |
| `WEAPON_SPATHA` | cavalry longsword | 1.5 | Cavalry |

Archers' bow itself is not a `reach_m`-bearing melee weapon today — ranged
attacks use a fixed `RANGED_RANGE` constant (160 world units,
`scripts/Unit.gd:310`), not `attack_range`/`reach_m`. The 0.6 m reach (now
`WEAPON_SIDEARM`'s `reach_m`) is the archer's melee sidearm reach, used only
when an enemy closes to melee contact (per `Battle.gd`'s own loadout comment:
"the archers' sidearm is short (they fight at range)"). A
`WEAPON_BOW` type is a plausible future addition once ranged range is folded
into the same registry, but that is a separate, larger change (`RANGED_RANGE`
is currently a single shared constant, not per-type) and out of scope for
phase 1.

| id | type | carried by |
|---|---|---|
| `SHIELD_SCUTUM` | large infantry shield | Spearmen, Infantry |
| `SHIELD_ROUND` | light shield | Cavalry |
| `SHIELD_NONE` | no shield | Archers |

(`WEAPON_PILUM`/javelin is named in the issue as a plausible future addition —
a thrown weapon distinct from the melee sidearm a legionary switches to after
the volley. It is not in the current roster; phase 1 does not add it. It is a
natural phase-4 addition once #516's `SwitchWeaponOrder` exists to model the
javelin→sword transition.)

The registry itself is a small `Dictionary[int, Weapon]` / `Dictionary[int,
Shield]` populated once, keyed by the same `int` constants the per-soldier
arrays store. Lookup is `registry[id]` — O(1), no allocation. As implemented
it is a `class_name LoadoutRegistry` (`scripts/LoadoutRegistry.gd`) whose
dictionaries are `static var`s built at class load: pure immutable data needs
no scene-tree presence, so a static class does the interning without an
autoload registration (the design sketch's "dedicated autoload" suggestion
turned out to be more machinery than the data needs).

## Determinism

- **Type lookups are pure.** `id -> shared immutable type object` is a
  dictionary read against data built once at startup from a constant table;
  no RNG, no per-call allocation, identical on every replay.
- **Per-soldier arrays follow the existing pure-array-mutation pattern.**
  Writing `_sim_soldier_weapon_id[i] = new_id` is the same shape as the
  existing `_sim_soldier_hp[i] -= damage` — an in-place `Packed*Array` write,
  no object churn, index-aligned with `_sim_soldier_pos`.
- Type objects are never mutated after registry load. If a future phase needs
  a *soldier-specific* variant of a type (e.g. a wounded weapon), that is new
  per-soldier state in a new array, not a write to the shared type object.

## Consumers

- **Combat math** (`scripts/SoldierMelee.gd`, `scripts/SoldierCombat.gd`)
  reads reach, lethality, and block weight from the type the soldier's
  `weapon_id` / `shield_id` resolve to, instead of the scalar `u.attack_range`
  copied at spawn and the per-type `"shield"` literal hardcoded in
  `SoldierCombat.profile_for()`. *Implemented* (#571, split out of phase 1):
  `SoldierMelee.resolve` reads the blow's lethality through the attacker's
  `_sim_soldier_weapon_id` (`Unit.soldier_lethality`) and composes the
  defender's shield weight as the type's **stance residual**
  (`profile_for()`'s `shield_residual`) plus the struck soldier's
  `_sim_soldier_shield_id` -> `Shield.block_value`
  (`Unit.soldier_shield_block`). The split is what makes the re-express
  behavior-preserving — Spearmen (0.65) and Infantry (0.60) carry the same
  scutum, so the scutum carries the shared 0.60 and the spearmen keep a 0.05
  braced-footing residual (archers: 0.05 unshielded-deflection residual, no
  shield); every composition equals the pre-split per-type weight bit-for-bit
  (`test/unit/test_loadout_combat_equivalence.gd`). The defence math stays the
  continuous dot-product facing gate (`SoldierCombat.facing_gate()` +
  `land_chance()`), not a discrete arc check — the
  `Shield.covers(attack_angle, hold_angle)` sketch above remains illustrative
  shape data nothing reads for gameplay yet; the wound formula is unchanged
  behaviorally throughout.
- **Rendering** — the soldier's `MultiMesh` draw pose reads `weapon_id` /
  `shield_id` (which mesh/sprite) plus `shield_hold_angle` (where to draw it
  relative to the body) once phase 3 wires visuals.
- **#530's formation geometry** (PR #534, open as of this writing) wants
  exactly the "shield relative to body" data this issue's per-soldier hold
  angle provides — a shield-wall or testudo restructure reads
  `_sim_soldier_shield_hold_angle` to lock shields into an overlapping wall or
  a raised roof. #534 does not depend on this issue landing first (it can ship
  its geometry restructure against today's scalar stats), but once both land,
  #534's geometry code becomes a consumer of the hold-angle array introduced
  here in phase 2, and should be revisited to read it.
- **#516's future `SwitchWeaponOrder`** writes `_sim_soldier_weapon_id[i]` to
  the id of the newly active weapon type — the concrete registry this issue
  builds is exactly what a switch order needs to switch *to* (a real id
  resolving to a real `Weapon`, not a magic number). This is a phase 4
  consumer; #516 itself is still in the design stage.

## Phase plan

Each phase: scope, dependencies, done-check, behavior-change label.

### Phase 1 — type classes + registry + array wiring (no behavior change)
- **Scope:** Define `Weapon`/`Shield` classes (`scripts/Weapon.gd`,
  `scripts/Shield.gd`) and a small interned registry covering today's roster
  (`WEAPON_SPEAR`, `WEAPON_GLADIUS`, `WEAPON_SIDEARM`, `WEAPON_SPATHA`,
  `SHIELD_SCUTUM`, `SHIELD_ROUND`, `SHIELD_NONE`). Add
  `_sim_soldier_weapon_id` / `_sim_soldier_shield_id` to `Unit.gd`, wired into
  `Battle._spawn_unit`'s loadout. The weapon type's `reach_m` becomes the
  single source of truth for `attack_range` at spawn (the `"reach_m"`
  dictionary literals are gone). *As implemented*, the strike-time re-express
  — combat reading lethality/block through the id arrays instead of
  `profile_for()`'s per-type literals — split out to a follow-up (#571):
  the per-type shield weights fold stance factors beyond the shield itself
  (Spearmen 0.65 vs Infantry 0.60 for the same scutum), so that drop-in is
  not behavior-preserving until the shield-vs-stance split is decided. The
  follow-up then landed the split as `shield_residual` (per type, in
  `profile_for()`) + `block_value` (per shield type), composed at strike time
  — see the combat-math consumer bullet above.
- **Dependencies:** none — builds on current `main`.
- **Done-check:** existing GUT suite (`tools/check.sh`) passes unchanged, plus
  a targeted equivalence test asserting combat outcomes are bit-for-bit
  identical to pre-refactor `main` on a fixed-seed battle (reach, block
  chance, damage numbers unchanged for every existing unit type).
- **Behavior change:** **none.** Pure representation refactor.

### Phase 2 — shield hold-angle/state per soldier
- **Scope:** Add `_sim_soldier_shield_hold_angle` (and any bracing flag phase
  1 didn't need) to `Unit.gd`. Default every soldier to `Shield.default_hold_angle`
  at spawn; update it wherever posture/bracing already changes today (braced
  stance, testudo/shield-wall formation entry once #530's geometry work
  defines what "locked" means spatially).
- **Dependencies:** #530 (PR #534) — this phase's hold-angle array is the data
  #534's shield-wall/testudo geometry wants to read/write. Land after #534
  merges (or coordinate directly if both are in flight) so the two don't
  redefine the same concept independently.
- **Done-check:** hold angle is readable and defaults correctly for every
  soldier; a targeted test asserts the array stays index-aligned with
  `_sim_soldier_pos` through spawn, reverse, and formation changes (mirroring
  the existing `_sim_soldier_hp.reverse()` pattern in `Unit.gd`).
- **Behavior change:** **none to combat outcomes** — this phase only makes the
  data available; nothing reads it for gameplay yet (rendering is phase 3).

### Phase 3 — rendering reads weapon/shield type + hold state
- **Scope:** Soldier `MultiMesh` draw pose reads `weapon_id` / `shield_id` to
  select the correct mesh/sprite and `shield_hold_angle` to orient it relative
  to the body.
- **Dependencies:** phases 1-2.
- **Done-check:** visual spot-check (demo clip) shows shields oriented per
  soldier state; no change to combat math or sim tick performance (stress
  test with the existing hundreds-of-soldiers scenario).
- **Behavior change:** **new capability** (visual), no change to sim outcomes.

### Phase 4 — gameplay layer: weapon switching
- **Scope:** `SwitchWeaponOrder` (from #516) writes `_sim_soldier_weapon_id`;
  add any additional weapon types needed for a real switch (e.g.
  `WEAPON_PILUM` for a javelin-then-sword legionary).
- **Dependencies:** #516's orders-queue phases need to be far enough along
  that a concrete `Order` subtype can exist; this phase cannot start before
  #516 has at least its phase-1 skeleton (`current_order` + `orders` queue).
- **Done-check:** a soldier can switch weapon type mid-battle, combat math
  immediately reflects the new type's stats, deterministic on replay.
- **Behavior change:** **new capability** (gameplay) — the first phase in this
  series that changes what a battle can do, not just how it's represented.

## Acceptance (mirrors #535)
- `Weapon`/`Shield` are real GDScript classes with concrete fields/methods —
  not an enum, not a dictionary of magic numbers.
- No per-soldier heap allocation for weapon/shield data — type objects are
  shared/interned, referenced by id from per-soldier `Packed*Array`s.
- Existing combat/render performance is not regressed (spot-check with the
  existing formation/battle test suite + a stress scenario).
- This doc is committed before any implementation phase begins (this PR).
