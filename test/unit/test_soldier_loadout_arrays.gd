extends GutTest
## Per-soldier loadout id arrays (docs/soldier-loadout-design.md, phase 1):
## every spawned soldier carries its unit type's interned weapon/shield ids in
## PackedInt32Arrays index-aligned with _sim_soldier_pos, and the arrays stay
## aligned through growth and casualty compaction. Also pins the equivalence
## the phase promises: the unit's attack_range — the scalar combat actually
## reads — still equals the pre-registry per-type reach for every roster type,
## so combat inputs are unchanged.

const BattleScript = preload("res://scripts/Battle.gd")

const SEED: int = 12345

# Per unit-type expectations: the registry ids the type carries and the reach
# (metres) its attack_range must still resolve to — the exact values the
# loadout table carried as "reach_m" literals before the registry existed.
const EXPECTED: Dictionary = {
	"Spearmen": {"weapon": LoadoutRegistry.WEAPON_SPEAR, "shield": LoadoutRegistry.SHIELD_SCUTUM, "reach_m": 2.4},
	"Infantry": {"weapon": LoadoutRegistry.WEAPON_GLADIUS, "shield": LoadoutRegistry.SHIELD_SCUTUM, "reach_m": 1.3},
	"Archers": {"weapon": LoadoutRegistry.WEAPON_SIDEARM, "shield": LoadoutRegistry.SHIELD_NONE, "reach_m": 0.6},
	"Cavalry": {"weapon": LoadoutRegistry.WEAPON_SPATHA, "shield": LoadoutRegistry.SHIELD_ROUND, "reach_m": 1.5},
}


func before_each() -> void:
	Replay.rng.seed = SEED   # deterministic draws for any combat side effects


## One live battle covers the whole spawn path: every unit of every roster type
## gets its type's ids, its soldiers all carry them index-aligned, and its
## attack_range matches the pre-registry reach bit-for-bit.
func test_spawned_units_carry_their_types_loadout() -> void:
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
		assert_true(EXPECTED.has(type_name),
			"unit type '%s' is a known roster type" % type_name)
		if not EXPECTED.has(type_name):
			continue
		var expected: Dictionary = EXPECTED[type_name]
		assert_eq(u.weapon_type_id, int(expected["weapon"]),
			"%s carries its type's weapon id" % u.unit_name)
		assert_eq(u.shield_type_id, int(expected["shield"]),
			"%s carries its type's shield id" % u.unit_name)
		assert_almost_eq(u.attack_range,
			float(expected["reach_m"]) * BattleScript.WORLD_UNITS_PER_METER, 0.0001,
			"%s attack_range still equals the pre-registry reach" % u.unit_name)
		var n: int = u._sim_soldier_pos.size()
		assert_gt(n, 0, "%s spawned soldier bodies" % u.unit_name)
		assert_eq(u._sim_soldier_weapon_id.size(), n,
			"%s weapon ids are index-aligned with the bodies" % u.unit_name)
		assert_eq(u._sim_soldier_shield_id.size(), n,
			"%s shield ids are index-aligned with the bodies" % u.unit_name)
		var mismatched: int = 0
		for i in range(n):
			if u._sim_soldier_weapon_id[i] != u.weapon_type_id \
					or u._sim_soldier_shield_id[i] != u.shield_type_id:
				mismatched += 1
		assert_eq(mismatched, 0,
			"every %s soldier carries the unit's loadout ids" % u.unit_name)
		checked += 1
	assert_gt(checked, 0, "the battle spawned roster units to check")


## Casualty compaction (SoldierMelee.reap) removes the dead soldier's entry from
## the loadout arrays exactly like the other per-soldier arrays, so the ids stay
## index-aligned with the surviving bodies.
func test_casualty_compaction_keeps_loadout_arrays_aligned() -> void:
	var u: Unit = _bare_unit(1, 0, 12)
	u.weapon_type_id = LoadoutRegistry.WEAPON_SPEAR
	u.shield_type_id = LoadoutRegistry.SHIELD_SCUTUM
	u.seed_sim_soldiers()
	var killer: Unit = _bare_unit(2, 1, 4)
	u._sim_soldier_hp[3] = 0.0
	u._sim_soldier_hp[7] = 0.0
	SoldierMelee.reap(u, killer)
	assert_eq(u.soldiers, 10, "two casualties left ten soldiers")
	var n: int = u._sim_soldier_pos.size()
	assert_eq(u._sim_soldier_weapon_id.size(), n,
		"weapon ids compact in step with the bodies")
	assert_eq(u._sim_soldier_shield_id.size(), n,
		"shield ids compact in step with the bodies")
	var mismatched: int = 0
	for i in range(n):
		if u._sim_soldier_weapon_id[i] != LoadoutRegistry.WEAPON_SPEAR \
				or u._sim_soldier_shield_id[i] != LoadoutRegistry.SHIELD_SCUTUM:
			mismatched += 1
	assert_eq(mismatched, 0, "every survivor still carries the unit's loadout ids")


## Growth (SoldierBodies.step resizing to a larger live count) seeds every fresh
## tail body with the unit's own type ids, exactly like the hp/stamina tails.
func test_growth_seeds_tail_bodies_with_the_units_loadout() -> void:
	var u: Unit = _bare_unit(3, 0, 12)
	u.weapon_type_id = LoadoutRegistry.WEAPON_SPATHA
	u.shield_type_id = LoadoutRegistry.SHIELD_ROUND
	u.seed_sim_soldiers()
	u.soldiers = 15   # a merge/relief-style gain; step resizes to the live count
	u.step_sim_soldiers(1.0 / 60.0)
	assert_eq(u._sim_soldier_weapon_id.size(), u._sim_soldier_pos.size(),
		"weapon ids grew in step with the bodies")
	assert_eq(u._sim_soldier_shield_id.size(), u._sim_soldier_pos.size(),
		"shield ids grew in step with the bodies")
	var mismatched: int = 0
	for i in range(u._sim_soldier_weapon_id.size()):
		if u._sim_soldier_weapon_id[i] != LoadoutRegistry.WEAPON_SPATHA \
				or u._sim_soldier_shield_id[i] != LoadoutRegistry.SHIELD_ROUND:
			mismatched += 1
	assert_eq(mismatched, 0, "fresh tail bodies carry the unit's loadout ids")


func _bare_unit(uid: int, team: int, n: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers, joins groups
	u.uid = uid
	u.team = team
	return u
