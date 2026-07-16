extends GutTest
## The strike-time loadout re-express (docs/soldier-loadout-design.md, the
## follow-up to phase 1) must be byte-identical to the pre-split combat table:
## the per-type "shield" and "lethality" literals profile_for() carried before
## the reads moved to the registry. Pins, with EXACT float equality (the
## formulas consume these directly, so bit-for-bit inputs mean bit-for-bit
## outcomes): the composed table per roster type, the same values through the
## live spawn path's per-soldier arrays, and the helpers' defensive fallbacks.

const BattleScript = preload("res://scripts/Battle.gd")

const SEED: int = 12345

# The pre-split combat literals per roster type — the exact values
# profile_for() returned as "shield" and "lethality" before the loadout split.
# The registry-derived reads must reproduce them bit-for-bit.
const OLD_TABLE: Dictionary = {
	"Spearmen": {"shield": 0.65, "lethality": 0.85,
		"cavalry": false, "anti_cavalry": true, "ranged": false,
		"weapon": LoadoutRegistry.WEAPON_SPEAR, "shield_id": LoadoutRegistry.SHIELD_SCUTUM},
	"Infantry": {"shield": 0.60, "lethality": 1.00,
		"cavalry": false, "anti_cavalry": false, "ranged": false,
		"weapon": LoadoutRegistry.WEAPON_GLADIUS, "shield_id": LoadoutRegistry.SHIELD_SCUTUM},
	"Archers": {"shield": 0.05, "lethality": 0.50,
		"cavalry": false, "anti_cavalry": false, "ranged": true,
		"weapon": LoadoutRegistry.WEAPON_SIDEARM, "shield_id": LoadoutRegistry.SHIELD_NONE},
	"Cavalry": {"shield": 0.25, "lethality": 1.10,
		"cavalry": true, "anti_cavalry": false, "ranged": false,
		"weapon": LoadoutRegistry.WEAPON_SPATHA, "shield_id": LoadoutRegistry.SHIELD_ROUND},
}


func before_each() -> void:
	Replay.rng.seed = SEED   # deterministic draws for any combat side effects


# --- pure table equivalence: registry-derived == pre-split literal -----------

func test_composed_shield_weight_equals_the_pre_split_literal_for_every_type() -> void:
	for type_name in OLD_TABLE:
		var row: Dictionary = OLD_TABLE[type_name]
		var prof: Dictionary = SoldierCombat.profile_for(
			row["cavalry"], row["anti_cavalry"], row["ranged"], 0.5)
		var block: float = LoadoutRegistry.shield(row["shield_id"]).block_value
		var composed: float = float(prof["shield_residual"]) + block
		assert_eq(composed, float(row["shield"]),
			"%s residual + block composes bit-for-bit to the old shield weight" % type_name)


func test_registry_lethality_equals_the_pre_split_literal_for_every_type() -> void:
	for type_name in OLD_TABLE:
		var row: Dictionary = OLD_TABLE[type_name]
		var lethality: float = LoadoutRegistry.weapon(row["weapon"]).lethality
		assert_eq(lethality, float(row["lethality"]),
			"%s weapon lethality matches the old per-type literal bit-for-bit" % type_name)


# --- live spawn path: the id-array reads produce the same strike inputs ------

## One seeded live battle covers the real spawn path end to end: for every
## spawned roster unit, the strike inputs SoldierMelee now reads through the
## per-soldier id arrays (soldier_lethality, residual + soldier_shield_block)
## equal the pre-split per-type literals for every single soldier.
func test_spawned_soldiers_strike_inputs_match_the_old_table() -> void:
	Replay.forced_seed = SEED   # consumed by Battle's RNG setup before any roll
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(2):
		await get_tree().physics_frame   # let the soldier layer seed its arrays
	var checked: int = 0
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u == null:
			continue
		var type_name: String = u.unit_name.split(" ")[0]
		assert_true(OLD_TABLE.has(type_name),
			"unit type '%s' is a known roster type" % type_name)
		if not OLD_TABLE.has(type_name):
			continue
		var row: Dictionary = OLD_TABLE[type_name]
		var residual: float = u.combat_profile()["shield_residual"]
		var lethality_off: int = 0
		var shield_off: int = 0
		for i in range(u._sim_soldier_pos.size()):
			if u.soldier_lethality(i) != float(row["lethality"]):
				lethality_off += 1
			if residual + u.soldier_shield_block(i) != float(row["shield"]):
				shield_off += 1
		assert_eq(lethality_off, 0,
			"every %s soldier's strike lethality equals the old literal" % u.unit_name)
		assert_eq(shield_off, 0,
			"every %s soldier's composed shield weight equals the old literal" % u.unit_name)
		checked += 1
	assert_gt(checked, 0, "the battle spawned roster units to check")


## The typed armor/mount split (per-unit ids -> profile_for) must leave every
## spawned roster unit's armour and contact mass bit-identical to the
## pre-registry hard-coded rows — the same equivalence bar the weapon/shield
## split above already meets.
func test_spawned_units_armour_and_mass_match_the_old_table() -> void:
	Replay.forced_seed = SEED
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame
	var expected: Dictionary = {
		"Spearmen": {"armour": 0.35, "mass": 1.0},
		"Infantry": {"armour": 0.45, "mass": 1.0},
		"Archers": {"armour": 0.10, "mass": 0.9},
		"Cavalry": {"armour": 0.40, "mass": 2.5},
	}
	var checked: int = 0
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u == null:
			continue
		var type_name: String = u.unit_name.split(" ")[0]
		if not expected.has(type_name):
			continue
		var prof: Dictionary = u.combat_profile()
		assert_eq(prof["armour"], float(expected[type_name]["armour"]),
			"%s spawned armour equals the pre-registry literal" % u.unit_name)
		assert_eq(prof["mass"], float(expected[type_name]["mass"]),
			"%s spawned contact mass equals the pre-registry literal" % u.unit_name)
		checked += 1
	assert_gt(checked, 0, "the battle spawned roster units to check")


# --- helper fallbacks: an out-of-sync read still resolves to real stats ------

func test_out_of_range_index_falls_back_to_the_units_own_type() -> void:
	var u: Unit = _bare_unit(1)
	u.weapon_type_id = LoadoutRegistry.WEAPON_SPEAR
	u.shield_type_id = LoadoutRegistry.SHIELD_ROUND
	# No seeded arrays: any index is out of range, so both helpers resolve the
	# unit's own type ids.
	assert_eq(u.soldier_lethality(0),
		LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPEAR).lethality,
		"an out-of-range weapon read resolves the unit's own weapon type")
	assert_eq(u.soldier_shield_block(0),
		LoadoutRegistry.shield(LoadoutRegistry.SHIELD_ROUND).block_value,
		"an out-of-range shield read resolves the unit's own shield type")


func test_unknown_per_soldier_id_falls_back_to_the_units_own_type() -> void:
	var u: Unit = _bare_unit(2)
	u.weapon_type_id = LoadoutRegistry.WEAPON_GLADIUS
	u.shield_type_id = LoadoutRegistry.SHIELD_SCUTUM
	u.seed_sim_soldiers()
	u._sim_soldier_weapon_id[0] = 999   # a corrupt entry resolves to null...
	u._sim_soldier_shield_id[0] = 999
	assert_eq(u.soldier_lethality(0),
		LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_GLADIUS).lethality,
		"...so the weapon read falls back to the unit's own type")
	assert_eq(u.soldier_shield_block(0),
		LoadoutRegistry.shield(LoadoutRegistry.SHIELD_SCUTUM).block_value,
		"...and the shield read falls back to the unit's own type")


func test_unresolvable_unit_type_falls_back_to_baseline_stats() -> void:
	var u: Unit = _bare_unit(3)
	u.weapon_type_id = 999   # nothing resolves anywhere: baseline lethality,
	u.shield_type_id = 999   # and a shield that blocks nothing
	assert_eq(u.soldier_lethality(0), 1.0,
		"a fully unresolvable weapon read returns the baseline lethality")
	assert_eq(u.soldier_shield_block(0), 0.0,
		"a fully unresolvable shield read blocks nothing")


func _bare_unit(uid: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 8
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers, joins groups
	u.uid = uid
	u.team = 0
	return u
