extends GutTest
## The interned weapon/shield type registry (docs/soldier-loadout-design.md,
## phase 1). Pins the three properties the data model promises: every roster id
## resolves to a real typed object, lookups are interned (one shared instance
## per type, never a fresh allocation), and the registry carries exactly the
## stats combat already uses — so combat inputs stay bit-for-bit identical to
## the pre-registry dictionary literals.

const ROSTER_WEAPONS: Array = [
	LoadoutRegistry.WEAPON_SPEAR,
	LoadoutRegistry.WEAPON_GLADIUS,
	LoadoutRegistry.WEAPON_SIDEARM,
	LoadoutRegistry.WEAPON_SPATHA,
]
const ROSTER_SHIELDS: Array = [
	LoadoutRegistry.SHIELD_SCUTUM,
	LoadoutRegistry.SHIELD_ROUND,
	LoadoutRegistry.SHIELD_NONE,
]
const ROSTER_ARMORS: Array = [
	LoadoutRegistry.ARMOR_HAMATA,
	LoadoutRegistry.ARMOR_LINOTHORAX,
	LoadoutRegistry.ARMOR_TUNIC,
	LoadoutRegistry.ARMOR_SQUAMATA,
]
const ROSTER_MOUNTS: Array = [
	LoadoutRegistry.MOUNT_NONE,
	LoadoutRegistry.MOUNT_WARHORSE,
]


# --- every roster id resolves to a real, self-consistent type object ---------

func test_every_roster_weapon_resolves() -> void:
	for type_id in ROSTER_WEAPONS:
		var w: Weapon = LoadoutRegistry.weapon(type_id)
		assert_not_null(w, "weapon id %d resolves to a Weapon" % type_id)
		if w == null:
			continue
		assert_eq(w.id, type_id, "the weapon knows its own registry id")
		assert_ne(w.display_name, "", "the weapon has a display name")
		assert_gt(w.reach_m, 0.0, "every melee weapon has a positive reach")
		assert_gt(w.lethality, 0.0, "every weapon can wound")


func test_every_roster_shield_resolves() -> void:
	for type_id in ROSTER_SHIELDS:
		var s: Shield = LoadoutRegistry.shield(type_id)
		assert_not_null(s, "shield id %d resolves to a Shield" % type_id)
		if s == null:
			continue
		assert_eq(s.id, type_id, "the shield knows its own registry id")
		assert_ne(s.display_name, "", "the shield has a display name")


func test_every_roster_armor_resolves() -> void:
	for type_id in ROSTER_ARMORS:
		var a: Armor = LoadoutRegistry.armor(type_id)
		assert_not_null(a, "armor id %d resolves to an Armor" % type_id)
		if a == null:
			continue
		assert_eq(a.id, type_id, "the armor knows its own registry id")
		assert_ne(a.display_name, "", "the armor has a display name")
		assert_between(a.protection, 0.0, 1.0, "protection is a [0,1] wound fraction")
		assert_gt(a.weight_kg, 0.0, "every panoply weighs something")


func test_every_roster_mount_resolves() -> void:
	for type_id in ROSTER_MOUNTS:
		var m: Mount = LoadoutRegistry.mount(type_id)
		assert_not_null(m, "mount id %d resolves to a Mount" % type_id)
		if m == null:
			continue
		assert_eq(m.id, type_id, "the mount knows its own registry id")
		assert_ne(m.display_name, "", "the mount has a display name")
		assert_gte(m.mass_contribution, 0.0, "a mount never lightens its rider")


func test_id_helpers_cover_exactly_the_roster() -> void:
	var weapon_ids: PackedInt32Array = LoadoutRegistry.weapon_ids()
	var shield_ids: PackedInt32Array = LoadoutRegistry.shield_ids()
	assert_eq(weapon_ids.size(), ROSTER_WEAPONS.size(), "no unlisted weapon types")
	assert_eq(shield_ids.size(), ROSTER_SHIELDS.size(), "no unlisted shield types")
	for type_id in ROSTER_WEAPONS:
		assert_has(Array(weapon_ids), type_id, "weapon_ids() lists id %d" % type_id)
	for type_id in ROSTER_SHIELDS:
		assert_has(Array(shield_ids), type_id, "shield_ids() lists id %d" % type_id)
	var armor_ids: PackedInt32Array = LoadoutRegistry.armor_ids()
	var mount_ids: PackedInt32Array = LoadoutRegistry.mount_ids()
	assert_eq(armor_ids.size(), ROSTER_ARMORS.size(), "no unlisted armor types")
	assert_eq(mount_ids.size(), ROSTER_MOUNTS.size(), "no unlisted mount types")
	for type_id in ROSTER_ARMORS:
		assert_has(Array(armor_ids), type_id, "armor_ids() lists id %d" % type_id)
	for type_id in ROSTER_MOUNTS:
		assert_has(Array(mount_ids), type_id, "mount_ids() lists id %d" % type_id)


# --- interning: one shared instance per type ----------------------------------

func test_weapon_lookup_is_interned() -> void:
	for type_id in ROSTER_WEAPONS:
		var first: Weapon = LoadoutRegistry.weapon(type_id)
		var second: Weapon = LoadoutRegistry.weapon(type_id)
		assert_true(is_same(first, second),
			"weapon id %d returns the same shared instance on every lookup" % type_id)


func test_shield_lookup_is_interned() -> void:
	for type_id in ROSTER_SHIELDS:
		var first: Shield = LoadoutRegistry.shield(type_id)
		var second: Shield = LoadoutRegistry.shield(type_id)
		assert_true(is_same(first, second),
			"shield id %d returns the same shared instance on every lookup" % type_id)


func test_distinct_types_are_distinct_instances() -> void:
	var spear: Weapon = LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPEAR)
	var gladius: Weapon = LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_GLADIUS)
	assert_false(is_same(spear, gladius), "different ids are different type objects")


# --- unknown ids resolve to null, never alias another type --------------------

func test_unknown_or_cross_namespace_ids_return_null() -> void:
	assert_null(LoadoutRegistry.weapon(0), "0 is reserved invalid (a missed array fill)")
	assert_null(LoadoutRegistry.shield(0), "0 is reserved invalid (a missed array fill)")
	assert_null(LoadoutRegistry.armor(0), "0 is reserved invalid for armor too")
	assert_null(LoadoutRegistry.mount(0), "0 is reserved invalid for mounts too")
	assert_null(LoadoutRegistry.weapon(999), "an unknown weapon id returns null")
	assert_null(LoadoutRegistry.shield(999), "an unknown shield id returns null")
	assert_null(LoadoutRegistry.armor(999), "an unknown armor id returns null")
	assert_null(LoadoutRegistry.mount(999), "an unknown mount id returns null")
	# The id ranges are disjoint, so a weapon id read as a shield id (or the
	# reverse) surfaces as null instead of silently aliasing another type.
	assert_null(LoadoutRegistry.shield(LoadoutRegistry.WEAPON_SPEAR),
		"a weapon id is not a shield id")
	assert_null(LoadoutRegistry.weapon(LoadoutRegistry.SHIELD_SCUTUM),
		"a shield id is not a weapon id")
	assert_null(LoadoutRegistry.armor(LoadoutRegistry.SHIELD_SCUTUM),
		"a shield id is not an armor id")
	assert_null(LoadoutRegistry.mount(LoadoutRegistry.ARMOR_HAMATA),
		"an armor id is not a mount id")


func test_armor_protection_matches_the_pre_registry_profile_table() -> void:
	# The exact per-type armour scalars SoldierCombat.profile_for()'s rows carried
	# as hard-coded literals before the registry existed. Exact equality: the wound
	# calculation reads this through the unit's armor id, so any drift changes
	# combat outcomes.
	assert_eq(LoadoutRegistry.armor(LoadoutRegistry.ARMOR_HAMATA).protection,
		0.45, "infantry mail matches the pre-registry infantry armour literal")
	assert_eq(LoadoutRegistry.armor(LoadoutRegistry.ARMOR_LINOTHORAX).protection,
		0.35, "the linothorax matches the pre-registry spearman armour literal")
	assert_eq(LoadoutRegistry.armor(LoadoutRegistry.ARMOR_TUNIC).protection,
		0.10, "the padded tunic matches the pre-registry archer armour literal")
	assert_eq(LoadoutRegistry.armor(LoadoutRegistry.ARMOR_SQUAMATA).protection,
		0.40, "the scale shirt matches the pre-registry cavalry armour literal")


func test_make_builds_armor_and_mount_types_field_for_field() -> void:
	# Direct construction, mirroring what the registry's own static init does —
	# also guarantees the constructors are exercised regardless of the coverage
	# instrumentation's script-load order (a registry built before a class is
	# instrumented would otherwise leave its make() uncounted).
	var a: Armor = Armor.make(299, "Test panoply", 0.5, 9.0)
	assert_eq(a.id, 299)
	assert_eq(a.display_name, "Test panoply")
	assert_eq(a.protection, 0.5)
	assert_eq(a.weight_kg, 9.0)
	var m: Mount = Mount.make(399, "Test mount", 1.2, 320.0, 7.0)
	assert_eq(m.id, 399)
	assert_eq(m.display_name, "Test mount")
	assert_eq(m.mass_contribution, 1.2)
	assert_eq(m.mass_kg, 320.0)
	assert_eq(m.top_speed_mps, 7.0)


func test_warhorse_mass_composes_to_the_pre_registry_cavalry_mass() -> void:
	# Body (1.0) + warhorse contribution must equal the cavalry row's pre-registry
	# 2.5 mass literal exactly — contact physics reads the composed value.
	var horse: Mount = LoadoutRegistry.mount(LoadoutRegistry.MOUNT_WARHORSE)
	assert_eq(1.0 + horse.mass_contribution, 2.5,
		"body + warhorse composes to the pre-registry cavalry contact mass")
	assert_eq(LoadoutRegistry.mount(LoadoutRegistry.MOUNT_NONE).mass_contribution, 0.0,
		"on foot adds no mass")
	# The real mass is separate DATA (what the HUD reports, in absolute kg) — the
	# tuned relative contact scalar above is sim-internal and not derived from it.
	assert_gt(horse.mass_kg, 300.0, "a warhorse weighs like a horse, not a sim scalar")
	assert_eq(LoadoutRegistry.mount(LoadoutRegistry.MOUNT_NONE).mass_kg, 0.0,
		"on foot carries no mount mass")


# --- the registry carries today's stats, unchanged ----------------------------

func test_reach_matches_pre_registry_loadout_values() -> void:
	# The exact reach_m values Battle._default_loadout() carried as dictionary
	# literals before the registry existed. These feed attack_range at spawn, so
	# changing one changes combat — this is the equivalence pin.
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPEAR).reach_m, 2.4, 0.0001)
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_GLADIUS).reach_m, 1.3, 0.0001)
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SIDEARM).reach_m, 0.6, 0.0001)
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPATHA).reach_m, 1.5, 0.0001)


func test_lethality_matches_the_pre_registry_combat_table() -> void:
	# The exact per-type lethality values SoldierCombat.profile_for() carried as
	# literals before the strike-time reads moved to the registry, mapping
	# one-to-one onto the weapon each type carries. Exact equality: strike-time
	# combat reads these through the per-soldier weapon ids, so any drift
	# changes combat outcomes. (test_loadout_combat_equivalence.gd pins the
	# whole composed strike-input table.)
	assert_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPEAR).lethality,
		0.85, "spear lethality matches the pre-registry spearman literal")
	assert_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_GLADIUS).lethality,
		1.00, "gladius lethality matches the pre-registry infantry literal")
	assert_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SIDEARM).lethality,
		0.50, "sidearm lethality matches the pre-registry archer literal")
	assert_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPATHA).lethality,
		1.10, "spatha lethality matches the pre-registry cavalry literal")


func test_shield_block_values_compose_with_the_stance_residuals() -> void:
	# The shield's own block value plus the carrying type's stance residual
	# (profile_for's "shield_residual") must compose to the pre-split per-type
	# shield weight, exactly. Exact equality: the land contest reads the
	# composed value, so any drift changes combat outcomes.
	var spear_profile: Dictionary = SoldierCombat.profile_for(false, true, false, 0.5)
	var sword_profile: Dictionary = SoldierCombat.profile_for(false, false, false, 0.5)
	var ranged_profile: Dictionary = SoldierCombat.profile_for(false, false, true, 0.5)
	var cavalry_profile: Dictionary = SoldierCombat.profile_for(true, false, false, 0.5)
	var scutum: float = LoadoutRegistry.shield(LoadoutRegistry.SHIELD_SCUTUM).block_value
	var round_shield: float = LoadoutRegistry.shield(LoadoutRegistry.SHIELD_ROUND).block_value
	var none: float = LoadoutRegistry.shield(LoadoutRegistry.SHIELD_NONE).block_value
	assert_eq(float(spear_profile["shield_residual"]) + scutum, 0.65,
		"spearman residual + scutum composes to the pre-split 0.65")
	assert_eq(float(sword_profile["shield_residual"]) + scutum, 0.60,
		"infantry residual + scutum composes to the pre-split 0.60")
	assert_eq(float(ranged_profile["shield_residual"]) + none, 0.05,
		"archer residual + no shield composes to the pre-split 0.05")
	assert_eq(float(cavalry_profile["shield_residual"]) + round_shield, 0.25,
		"cavalry residual + round shield composes to the pre-split 0.25")
	assert_eq(none, 0.0, "no shield blocks nothing")


# --- the type methods: pure and edge-safe --------------------------------------

func test_effective_reach_scales_with_terrain_multiplier() -> void:
	var spear: Weapon = LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPEAR)
	assert_almost_eq(spear.effective_reach(1.0), spear.reach_m, 0.0001,
		"open ground leaves reach unchanged")
	assert_almost_eq(spear.effective_reach(0.6), spear.reach_m * 0.6, 0.0001,
		"slow terrain shortens the effective thrust proportionally")


func test_shield_covers_its_arc_and_wraps() -> void:
	var scutum: Shield = LoadoutRegistry.shield(LoadoutRegistry.SHIELD_SCUTUM)
	var half_arc: float = deg_to_rad(scutum.arc_deg) * 0.5
	assert_true(scutum.covers(0.0, 0.0), "a straight-on attack is covered")
	assert_true(scutum.covers(half_arc - 0.01, 0.0), "just inside the arc edge is covered")
	assert_false(scutum.covers(half_arc + 0.01, 0.0), "just outside the arc edge is not")
	assert_false(scutum.covers(PI, 0.0), "an attack from behind the shield is not covered")
	# Angles wrap at the -PI/PI seam: attack at ~-179 degrees against a hold at
	# ~+179 degrees is a ~2 degree difference, well inside the arc.
	assert_true(scutum.covers(-PI + 0.02, PI - 0.02), "coverage wraps across the angle seam")


func test_no_shield_covers_nothing() -> void:
	var none: Shield = LoadoutRegistry.shield(LoadoutRegistry.SHIELD_NONE)
	assert_false(none.covers(0.0, 0.0),
		"a zero-arc shield covers nothing, even a perfectly aligned attack")
