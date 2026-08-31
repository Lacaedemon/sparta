# Design note: soldier weapon/shield loadout

Status: **phases 1-4 implemented** (#536, #537, #538, #539): the `Weapon`/`Shield` type
classes, the interned `LoadoutRegistry`, the per-soldier id arrays, and the
per-soldier shield hold-angle state are in the code, with the weapon type as
the single source of truth for spawn-time reach. The strike-time combat-read
re-express (#571, split out of phase 1) is implemented too: melee reads
lethality through the attacker's weapon id and composes the defensive shield
weight as the type's stance residual plus the struck soldier's shield
`block_value` (see phase 1 below). Phase 3's rendering now reads the actual
equipped weapon type for figure/mark mesh selection (`Unit._foot_kind()`,
preferring `weapon_type_id` over the coarse `anti_cavalry`/`is_ranged` flags),
orients the FOOT_SPEAR spear glyph and the infantry shield glyph by their
type's `default_hold_angle` (`Unit.weapon_rest_angle()`/`shield_rest_angle()`
-> `UnitMeshes.figure_mesh`), and eases a per-soldier render-only "strike lunge"
forward along facing while a soldier sits in `engaged_soldier_indices()` (see
phase 3 below for the details and what's still out of scope). Phase 4
(#539) is implemented too: a regiment can draw the other weapon its
soldiers carry mid-battle, via `Order.Type.SWITCH_WEAPON` and
`Unit.equip_weapon`.

The registry has since grown two more type families on the same contract
(interned, immutable, disjoint id ranges): `Armor` (protection -- the scalar
`profile_for()`'s rows used to hard-code -- plus a provisional panoply
`weight_kg`) and `Mount` (the animal's real `mass_kg` plus a provisional
`top_speed_mps`). Player-facing mass always reports in absolute kilograms
(the mount's `mass_kg`, and the per-type `body_mass_kg` in `profile_for()`'s
rows), never the sim's relative contact scalar -- the units convention's "no
raw sim number reaches the player," applied to mass.

**The contact-mass derivation is now done.**
`SoldierCombat.relative_mass_from_kg(mass_kg)` divides a real kilogram
figure by `CONTACT_MASS_BASELINE_KG` (80 kg, the heavy-foot body mass), and
`profile_for()` composes a soldier's relative contact mass as
`relative_mass_from_kg(body_mass_kg)` plus, when mounted,
`relative_mass_from_kg(mount.mass_kg)` -- real body-plus-mount kilograms end
to end, not a separately-tuned relative scalar living alongside them. This
changes combat: Spearmen and Infantry both weigh the 80 kg baseline, so
their mass is unchanged at 1.0, but Archers' 70 kg body now derives to
0.875 (was the tuned 0.9) and a mounted Cavalryman's 75 kg rider plus a
450 kg warhorse now derives to 6.5625 (was the tuned 2.5) -- a real ~525 kg
rider-and-horse relative to a foot soldier, not a hand-picked "cavalry hits
like 2.5 men" figure. `Mount` no longer carries a separate
`mass_contribution` field; `mass_kg` is the only source. Unlike
weapons/shields, `Armor`/`Mount` are referenced per UNIT
(`Unit.armor_type_id` / `Unit.mount_type_id`), not per soldier -- nothing
varies per soldier for them yet; the per-soldier array move is a natural
follow-on if a phase ever needs mixed panoplies inside one regiment.

## Motivation

The combat model (`docs/combat-model.md`) already gives each soldier type fixed
attributes -- skill, armour, shield, lethality, reach, mass -- but before phase 1
they lived as magic numbers and dictionary keys: `_default_loadout()` in
`scripts/Battle.gd` was an `Array` of untyped `Dictionary` literals
(`"reach_m": 2.4`, `"atk": 11`), and `Battle._spawn_unit` read them into scalar
fields defined on `Unit` (`attack`, `defense`, `attack_range`) at spawn time.
There was no `Weapon` or `Shield` object anywhere -- "spear" was a string name
plus a handful of loose numbers, not a thing.

The owner's directive: model weapons and shields as **concrete classed
objects** -- real fields and methods, not an enum or a dictionary of magic
numbers -- because "we want to keep making our object taxonomy more and more
concrete."

The catch: **soldiers themselves are not objects.** Per-soldier state lives in
parallel `Packed*Array`s on `Unit` -- `_sim_soldier_pos`, `_sim_body_vel`,
`_sim_steer`, `_sim_soldier_facing` (four `PackedVector2Array`s, 8 bytes each)
and `_sim_soldier_hp`, `_sim_prone`, `_sim_soldier_stamina` (three
`PackedFloat32Array`s, 4 bytes each) -- deliberately, for performance: roughly
`4*8 + 3*4 = 44` bytes/soldier by this author's count of `Unit.gd`'s current
`_sim_*` arrays (not a cited figure from CLAUDE.md -- CLAUDE.md documents the
SoA pattern and its rationale, but not this byte count), feeding `MultiMesh`
rendering, sized for hundreds of soldiers per unit across many units per
battle. A literal "one `Weapon` object + one `Shield` object per soldier"
instantiates two extra heap `RefCounted`s per soldier -- real allocation and
cache-locality cost the array-of-structs design exists to avoid. Concreteness
and the SoA hot loop pull in opposite directions, so this
doc resolves the tension before any code changes.

## The model: shared TYPE objects, per-soldier INSTANCE arrays

Split what's genuinely per-*type* from what's genuinely per-*soldier*:

- **`Weapon` and `Shield` are real GDScript classes** (`class_name Weapon`,
  `class_name Shield`) with concrete fields and methods -- reach, damage
  profile, defense/block value, default hold pose -- but as **shared, interned
  type definitions**. One instance per weapon/shield *type*
  (`WEAPON_SPEAR`, `SHIELD_SCUTUM`, ...), not one per soldier. Godot `Resource`
  semantics: loaded once at startup, referenced by id many times, never
  mutated after load.
- **Each soldier references its active loadout by id**, not by object -- new
  parallel arrays on `Unit`, index-aligned with `_sim_soldier_pos` exactly like
  the existing `_sim_soldier_hp` / `_sim_soldier_stamina`:
  - `_sim_soldier_weapon_id: PackedInt32Array`
  - `_sim_soldier_shield_id: PackedInt32Array`
- **Per-soldier STATE that genuinely varies** also lives in parallel arrays,
  never inside the shared type object (putting mutable per-soldier state on
  the type object would defeat interning -- two soldiers carrying the same
  scutum must not be able to fight over one shared "current hold angle"):
  - `_sim_soldier_shield_hold_angle: PackedFloat32Array` -- current hold
    angle/offset relative to the body: resting, bracing, raised.
  - a bracing/active-weapon flag array where a soldier can carry more than
    one weapon (phase 4; not needed for phase 1's single-weapon-per-type
    roster).

The type classes hold what's fixed per type (reach, damage, defense, default
hold pose); the per-soldier arrays hold what varies per instance (which type
is currently equipped, current hold state). This mirrors the pattern already
used for per-type combat/movement stats on `Battle._default_loadout` -- the
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

(Sparta has no `Terrain` class -- terrain is a plain `Array` of `Dictionary`
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
`arc_deg = 0.0`), not a null check scattered through combat -- Archers carry
it today (see the registry sketch below: Cavalry get the lighter
`SHIELD_ROUND`, not `SHIELD_NONE`), so callers already need a "no shield"
case; giving it an object keeps `covers()` uniform instead of an
`if shield_id == -1` special case at every call site.

## Type registry sketch

`scripts/Battle.gd`'s `_default_loadout()` fields four unit types --
Spearmen, Infantry, Archers, Cavalry -- each with one
melee weapon (a `reach_m`) and an implicit shield weight already hardcoded per
type in `SoldierCombat.profile_for()` (`scripts/SoldierCombat.gd:63-71`): a
`"shield"` value of 0.65 for Spearmen (anti-cavalry), 0.60 for Infantry, 0.05
for Archers (ranged), 0.25 for Cavalry. That gradient is exactly what
motivates the table below -- Spearmen/Infantry already carry a large shield's
worth of block value, Archers next to none, Cavalry something in between.
Phase 1 does not invent new unit types or new weapons; it names what already
exists concretely:

| id | type | reach_m (was `_default_loadout`'s literal, now `LoadoutRegistry`) | carried by |
|---|---|---|---|
| `WEAPON_SPEAR` | spear | 2.4 | Spearmen |
| `WEAPON_GLADIUS` | short sword | 1.3 | Infantry |
| `WEAPON_SIDEARM` | archer's melee backup (dagger/knife) | 0.6 | Archers |
| `WEAPON_SPATHA` | cavalry longsword | 1.5 | Cavalry |
| `WEAPON_PILUM` | heavy javelin | 2.0 | Infantry |
| `WEAPON_LANCE` | cavalry lance | 3.0 | Cavalry |

Archers' bow itself is not a `reach_m`-bearing melee weapon today -- ranged
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

(`WEAPON_PILUM`/javelin is named in the issue as a plausible future addition --
a thrown weapon distinct from the melee sidearm a legionary switches to after
the volley. It is not in the current roster; phase 1 does not add it. It is a
natural phase-4 addition once #516's `SwitchWeaponOrder` exists to model the
javelin→sword transition.)

The registry itself is a small `Dictionary[int, Weapon]` / `Dictionary[int,
Shield]` populated once, keyed by the same `int` constants the per-soldier
arrays store. Lookup is `registry[id]` -- O(1), no allocation. As implemented
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
  existing `_sim_soldier_hp[i] -= damage` -- an in-place `Packed*Array` write,
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
  behavior-preserving -- Spearmen (0.65) and Infantry (0.60) carry the same
  scutum, so the scutum carries the shared 0.60 and the spearmen keep a 0.05
  braced-footing residual (archers: 0.05 unshielded-deflection residual, no
  shield); every composition equals the pre-split per-type weight bit-for-bit
  (`test/unit/test_loadout_combat_equivalence.gd`). The defence math stays the
  continuous dot-product facing gate (`SoldierCombat.facing_gate()` +
  `land_chance()`), not a discrete arc check -- the
  `Shield.covers(attack_angle, hold_angle)` sketch above remains illustrative
  shape data nothing reads for gameplay yet; the wound formula is unchanged
  behaviorally throughout.
- **Rendering** (implemented, phase 3) -- the soldier's `MultiMesh` draw pose
  reads `weapon_id` (`Unit._foot_kind()`, which mesh/sprite) and each type's
  `default_hold_angle` (`Unit.weapon_rest_angle()`/`shield_rest_angle()`,
  where to draw the held item relative to the body). The per-soldier
  `_sim_soldier_shield_hold_angle` array itself stays a per-UNIT read at mesh-
  build time for now (every soldier in a unit shares one shield type, so the
  array is uniformly filled) rather than a genuinely per-soldier one -- see
  phase 3 below.
- **#530's formation geometry** (PR #534, open as of this writing) wants
  exactly the "shield relative to body" data this issue's per-soldier hold
  angle provides -- a shield-wall or testudo restructure reads
  `_sim_soldier_shield_hold_angle` to lock shields into an overlapping wall or
  a raised roof. #534 does not depend on this issue landing first (it can ship
  its geometry restructure against today's scalar stats), but once both land,
  #534's geometry code becomes a consumer of the hold-angle array introduced
  here in phase 2, and should be revisited to read it.
- **#516's future `SwitchWeaponOrder`** writes `_sim_soldier_weapon_id[i]` to
  the id of the newly active weapon type -- the concrete registry this issue
  builds is exactly what a switch order needs to switch *to* (a real id
  resolving to a real `Weapon`, not a magic number). This is a phase 4
  consumer; #516 itself is still in the design stage.

## Phase plan

Each phase: scope, dependencies, done-check, behavior-change label.

### Phase 1 -- type classes + registry + array wiring (no behavior change)
- **Scope:** Define `Weapon`/`Shield` classes (`scripts/Weapon.gd`,
  `scripts/Shield.gd`) and a small interned registry covering today's roster
  (`WEAPON_SPEAR`, `WEAPON_GLADIUS`, `WEAPON_SIDEARM`, `WEAPON_SPATHA`,
  `SHIELD_SCUTUM`, `SHIELD_ROUND`, `SHIELD_NONE`). Add
  `_sim_soldier_weapon_id` / `_sim_soldier_shield_id` to `Unit.gd`, wired into
  `Battle._spawn_unit`'s loadout. The weapon type's `reach_m` becomes the
  single source of truth for `attack_range` at spawn (the `"reach_m"`
  dictionary literals are gone). *As implemented*, the strike-time re-express
  -- combat reading lethality/block through the id arrays instead of
  `profile_for()`'s per-type literals -- split out to a follow-up (#571):
  the per-type shield weights fold stance factors beyond the shield itself
  (Spearmen 0.65 vs Infantry 0.60 for the same scutum), so that drop-in is
  not behavior-preserving until the shield-vs-stance split is decided. The
  follow-up then landed the split as `shield_residual` (per type, in
  `profile_for()`) + `block_value` (per shield type), composed at strike time
  -- see the combat-math consumer bullet above.
- **Dependencies:** none -- builds on current `main`.
- **Done-check:** existing GUT suite (`tools/check.sh`) passes unchanged, plus
  a targeted equivalence test asserting combat outcomes are bit-for-bit
  identical to pre-refactor `main` on a fixed-seed battle (reach, block
  chance, damage numbers unchanged for every existing unit type).
- **Behavior change:** **none.** Pure representation refactor.

### Phase 2 -- shield hold-angle/state per soldier
- **Scope:** Add `_sim_soldier_shield_hold_angle` (and any bracing flag phase
  1 didn't need) to `Unit.gd`. Default every soldier to `Shield.default_hold_angle`
  at spawn; update it wherever posture/bracing already changes today (braced
  stance, testudo/shield-wall formation entry once #530's geometry work
  defines what "locked" means spatially).
- **Dependencies:** #530 (PR #534) -- this phase's hold-angle array is the data
  #534's shield-wall/testudo geometry wants to read/write. Land after #534
  merges (or coordinate directly if both are in flight) so the two don't
  redefine the same concept independently.
- **Done-check:** hold angle is readable and defaults correctly for every
  soldier; a targeted test asserts the array stays index-aligned with
  `_sim_soldier_pos` through spawn, reverse, and formation changes (mirroring
  the existing `_sim_soldier_hp.reverse()` pattern in `Unit.gd`).
- **Behavior change:** **none to combat outcomes** -- this phase only makes the
  data available; nothing reads it for gameplay yet (rendering is phase 3).

### Phase 3 -- rendering reads weapon/shield type + hold state (implemented, #538)
- **Scope, as implemented:**
  - `Unit._foot_kind()` (the figure/mark archetype selector) now reads
    `weapon_type_id` first (`WEAPON_SPEAR` -> spear, `WEAPON_SIDEARM` ->
    archer), falling back to the `anti_cavalry`/`is_ranged` flags only when
    `weapon_type_id` doesn't resolve to either -- a bare/synthetic unit built
    directly in a test, which sets the flags but keeps `Unit`'s default
    `WEAPON_GLADIUS`. Under today's roster every real spawned unit's
    `weapon_type_id` and flags agree, so this is a behavior-preserving remap
    of the old flag-only logic; the id read is what lets a weapon switch
    (phase 4) reach the render at all. It is not sufficient on its own,
    though, and phase 4 found out the hard way: the figure meshes are built
    once and handed to the `MultiMesh`es, which keep their own reference
    until an LOD or facing flip re-hands them, so `equip_weapon` has to
    rebuild *and* re-apply them or the block goes on drawing the weapon it
    just put away. `_build_mark_meshes`
    now switches on `_foot_kind()` too, instead of duplicating the flag logic.
  - `UnitMeshes.figure_mesh` (and `_foot_figure_polys`/`_spear_polys`/
    `_shield_polys`) gained optional `weapon_hold_angle`/`shield_hold_angle`
    parameters (radians, defaulting to 0.0) that rotate the held-item polygon
    about a pivot near its grip (`UnitMeshes._rotate_polys_about`) rather than
    the geometry staying at a single hardcoded angle. `Unit._build_figure_meshes`
    resolves them via the new `Unit.weapon_rest_angle()` (mirroring the existing
    `shield_rest_angle()`) and threads them through. Only the FOOT_SPEAR spear
    glyph and the infantry shield glyph consume their angle today -- the bow
    has no matching registry weapon type yet, and cavalry's mounted figure has
    no held-item glyph at all. `LoadoutRegistry`'s weapons/shields carry real,
    distinct `default_hold_angle` values now instead of the uniform 0.0 every
    type defaulted to before this phase (`WEAPON_SPEAR` presented forward,
    `SHIELD_SCUTUM` raised into a guard; every other type stays at the neutral
    default pending a future glyph).
  - A render-only per-soldier "strike lunge" (`Unit._render_strike_progress`,
    `Unit._soldier_strike_offset`) eases a soldier's mark/figure position
    forward along its own facing while its index sits in
    `engaged_soldier_indices()` -- the same derived-not-simulated pattern as
    `_render_prone_progress`, so it reflects "hold state" (idle vs. actively
    striking) without any new per-soldier *simulation* array. Purely additive
    to the render position; `_sim_soldier_pos` (combat/collision) is untouched.
- **Dependencies:** phases 1-2.
- **Done-check:** visual spot-check (demo clip, plus before/after upscaled
  crops in the PR) shows the spear/shield hold angles and the strike lunge;
  no change to combat math, determinism, or sim tick performance (confirmed
  by a website-demo-diff transcript showing zero changed sim content).
- **Behavior change:** **new capability** (visual), no change to sim outcomes.

### Phase 4 -- gameplay layer: weapon switching (implemented, #539)
- **Scope, as implemented:**
  - `WEAPON_PILUM` joins the registry, and the Infantry roster row carries it
    as a `sidearm` while still *deploying* the gladius -- so spawn combat is
    unchanged and no existing demo, transcript or test outcome shifts.
  - `Order.Type.SWITCH_WEAPON` (appended last, so recorded transcripts keep
    their existing type values) plus `Battle.ORDER_SWITCH_WEAPON` and
    `enqueue_switch_weapon`, which rides the already-recorded `mode` field
    rather than adding one to the replay format. `Shift+I` in
    `SelectionManager` toggles between the deployed weapon and the sidearm.
  - `Unit.equip_weapon` rewrites the unit-level id, the per-soldier array and
    the derived `attack_range` together. Two consumers had to follow it: the
    three sites that refill per-soldier entries from `weapon_type_id` on a
    casualty/growth resize (`SoldierBodies`, `TierTransition`), and
    `SpawnFingerprint`, which now reads a spawn-pinned
    `spawn_weapon_type_id` so a mid-battle switch can't re-stamp a demo
    artifact's digest.
  - Reach is converted metres -> world units once per *type*
    (`Weapon.reach_wu`, via `WorldScale.m_to_wu`) rather than per equip.
- **Dependencies:** #516's orders-queue phases need to be far enough along
  that a concrete `Order` subtype can exist; this phase cannot start before
  #516 has at least its phase-1 skeleton (`current_order` + `orders` queue).
- **Done-check:** a soldier can switch weapon type mid-battle, combat math
  immediately reflects the new type's stats, deterministic on replay.
- **Behavior change:** **new capability** (gameplay) -- the first phase in this
  series that changes what a battle can do, not just how it's represented.

## Acceptance (mirrors #535)
- `Weapon`/`Shield` are real GDScript classes with concrete fields/methods --
  not an enum, not a dictionary of magic numbers.
- No per-soldier heap allocation for weapon/shield data -- type objects are
  shared/interned, referenced by id from per-soldier `Packed*Array`s.
- Existing combat/render performance is not regressed (spot-check with the
  existing formation/battle test suite + a stress scenario).
- This doc is committed before any implementation phase begins (this PR).
