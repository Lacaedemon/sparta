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


func test_id_helpers_cover_exactly_the_roster() -> void:
	var weapon_ids: PackedInt32Array = LoadoutRegistry.weapon_ids()
	var shield_ids: PackedInt32Array = LoadoutRegistry.shield_ids()
	assert_eq(weapon_ids.size(), ROSTER_WEAPONS.size(), "no unlisted weapon types")
	assert_eq(shield_ids.size(), ROSTER_SHIELDS.size(), "no unlisted shield types")
	for type_id in ROSTER_WEAPONS:
		assert_has(Array(weapon_ids), type_id, "weapon_ids() lists id %d" % type_id)
	for type_id in ROSTER_SHIELDS:
		assert_has(Array(shield_ids), type_id, "shield_ids() lists id %d" % type_id)


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
	assert_null(LoadoutRegistry.weapon(999), "an unknown weapon id returns null")
	assert_null(LoadoutRegistry.shield(999), "an unknown shield id returns null")
	# The id ranges are disjoint, so a weapon id read as a shield id (or the
	# reverse) surfaces as null instead of silently aliasing another type.
	assert_null(LoadoutRegistry.shield(LoadoutRegistry.WEAPON_SPEAR),
		"a weapon id is not a shield id")
	assert_null(LoadoutRegistry.weapon(LoadoutRegistry.SHIELD_SCUTUM),
		"a shield id is not a weapon id")


# --- the registry carries today's stats, unchanged ----------------------------

func test_reach_matches_pre_registry_loadout_values() -> void:
	# The exact reach_m values Battle._default_loadout() carried as dictionary
	# literals before the registry existed. These feed attack_range at spawn, so
	# changing one changes combat — this is the equivalence pin.
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPEAR).reach_m, 2.4, 0.0001)
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_GLADIUS).reach_m, 1.3, 0.0001)
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SIDEARM).reach_m, 0.6, 0.0001)
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPATHA).reach_m, 1.5, 0.0001)


func test_lethality_matches_combat_profile_table() -> void:
	# Each unit type's lethality in SoldierCombat.profile_for() maps one-to-one
	# onto the weapon that type carries; the registry must agree with the table
	# combat actually reads, or the representation lies about the sim.
	var spear_profile: Dictionary = SoldierCombat.profile_for(false, true, false, 0.5)
	var sword_profile: Dictionary = SoldierCombat.profile_for(false, false, false, 0.5)
	var ranged_profile: Dictionary = SoldierCombat.profile_for(false, false, true, 0.5)
	var cavalry_profile: Dictionary = SoldierCombat.profile_for(true, false, false, 0.5)
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPEAR).lethality,
		float(spear_profile["lethality"]), 0.0001, "spear lethality matches the spearman profile")
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_GLADIUS).lethality,
		float(sword_profile["lethality"]), 0.0001, "gladius lethality matches the infantry profile")
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SIDEARM).lethality,
		float(ranged_profile["lethality"]), 0.0001, "sidearm lethality matches the archer profile")
	assert_almost_eq(LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPATHA).lethality,
		float(cavalry_profile["lethality"]), 0.0001, "spatha lethality matches the cavalry profile")


func test_shield_block_values_match_their_profile_sources() -> void:
	# The scutum carries the plain infantry shield weight; the spearmen's higher
	# 0.65 in profile_for folds anti-cavalry bracing on top of the same shield
	# and stays there. The round shield matches the cavalry weight exactly.
	var sword_profile: Dictionary = SoldierCombat.profile_for(false, false, false, 0.5)
	var cavalry_profile: Dictionary = SoldierCombat.profile_for(true, false, false, 0.5)
	assert_almost_eq(LoadoutRegistry.shield(LoadoutRegistry.SHIELD_SCUTUM).block_value,
		float(sword_profile["shield"]), 0.0001, "scutum block matches the infantry shield weight")
	assert_almost_eq(LoadoutRegistry.shield(LoadoutRegistry.SHIELD_ROUND).block_value,
		float(cavalry_profile["shield"]), 0.0001, "round shield block matches the cavalry weight")
	assert_almost_eq(LoadoutRegistry.shield(LoadoutRegistry.SHIELD_NONE).block_value,
		0.0, 0.0001, "no shield blocks nothing")


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
