extends GutTest
## Cavalry lance thrust vs body collision separation (docs/combat-model.md):
## For charging cavalry, the rider's lance thrust damage (occurring at weapon reach ~3.0 m)
## lands on an earlier tick than the physical horse body collision (occurring at body
## contact radius ~1.8 m). Body collision delivers massive kinetic knockback, blunt collision
## damage, and prone knockdown, whereas the lance thrust delivers piercing damage.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")


func _make_cavalry_unit(uid: int, team: int, pos: Vector2, count: int = 10) -> Unit:
	var u := Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.position = pos
	u.is_cavalry = true
	u.mount_type_id = LoadoutRegistry.MOUNT_WARHORSE
	u.weapon_type_id = LoadoutRegistry.WEAPON_LANCE
	u.spawn_weapon_type_id = LoadoutRegistry.WEAPON_LANCE
	u.sidearm_type_id = LoadoutRegistry.WEAPON_SPATHA
	u.shield_type_id = LoadoutRegistry.SHIELD_ROUND
	u.armor_type_id = LoadoutRegistry.ARMOR_SQUAMATA
	u.attack_range = LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_LANCE).reach_wu
	u.facing = Vector2.DOWN if team == 0 else Vector2.UP
	u.seed_sim_soldiers()
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.0)
	return u


func _make_infantry_unit(uid: int, team: int, pos: Vector2, count: int = 10) -> Unit:
	var u := Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.position = pos
	u.is_cavalry = false
	u.weapon_type_id = LoadoutRegistry.WEAPON_GLADIUS
	u.spawn_weapon_type_id = LoadoutRegistry.WEAPON_GLADIUS
	u.sidearm_type_id = LoadoutRegistry.WEAPON_PILUM
	u.shield_type_id = LoadoutRegistry.SHIELD_SCUTUM
	u.armor_type_id = LoadoutRegistry.ARMOR_HAMATA
	u.facing = Vector2.UP if team == 1 else Vector2.DOWN
	u.seed_sim_soldiers()
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.0)
	return u


func before_each() -> void:
	Replay.rng.seed = 42


func test_lance_reach_is_longer_than_body_collision_radius() -> void:
	var lance: Weapon = LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_LANCE)
	assert_not_null(lance, "lance exists in LoadoutRegistry")
	assert_true(lance.is_piercing, "lance is piercing weapon")
	assert_gt(lance.reach_wu, 50.0, "lance reach is greater than 50 world units (~2.5m)")

	var cav := _make_cavalry_unit(1, 0, Vector2.ZERO, 1)
	var inf := _make_infantry_unit(2, 1, Vector2.ZERO, 1)
	var body_contact_radius: float = cav.soldier_body_radius() + inf.soldier_body_radius() \
			+ cav.formation_containment_margin() + inf.formation_containment_margin()
	assert_lt(body_contact_radius, lance.reach_wu,
		"lance reach exceeds physical body collision contact radius")


func test_lance_strikes_at_reach_before_body_collision_distance() -> void:
	# Place cavalry and infantry at 50 wu apart (within lance reach of 60 wu, but outside
	# body contact radius of ~36 wu).
	var cav := _make_cavalry_unit(1, 0, Vector2(0, -50), 1)
	var inf := _make_infantry_unit(2, 1, Vector2.ZERO, 1)
	cav._sim_soldier_pos[0] = Vector2(0, -50)
	inf._sim_soldier_pos[0] = Vector2.ZERO
	cav._approach_velocity = Vector2(0, 100)

	var inf_hp_before: float = inf._sim_soldier_hp[0]
	cav.resolve_soldier_melee(inf)
	assert_lt(inf._sim_soldier_hp[0], inf_hp_before,
		"lance strike lands at 50 wu reach, dealing damage before body contact")

	# Verify that body contact accumulation at this distance produces NO collision damage
	# because bodies are not touching.
	var inf_hp_after_strike: float = inf._sim_soldier_hp[0]
	SoldierEnemyContact.accumulate([cav, inf], 99101)
	assert_almost_eq(inf._sim_soldier_hp[0], inf_hp_after_strike, 1e-4,
		"no body collision damage occurs while bodies are outside contact radius")


func test_body_collision_delivers_damage_and_knockdown_on_contact() -> void:
	# Place cavalry and infantry within body contact radius (e.g. 10 wu) closing fast.
	var cav := _make_cavalry_unit(1, 0, Vector2(0, -10), 1)
	var inf := _make_infantry_unit(2, 1, Vector2.ZERO, 1)
	cav._sim_soldier_pos[0] = Vector2(0, -10)
	inf._sim_soldier_pos[0] = Vector2.ZERO

	# Cavalry charging at 170 wu/s (8.5 m/s)
	cav._sim_body_vel[0] = Vector2(0, 170.0)
	inf._sim_body_vel[0] = Vector2.ZERO

	var inf_hp_before: float = inf._sim_soldier_hp[0]
	SoldierEnemyContact.accumulate([cav, inf], 99102)

	assert_lt(inf._sim_soldier_hp[0], inf_hp_before,
		"body collision delivers collision damage on physical contact")
	assert_gt(inf._sim_body_vel[0].length(), 10.0,
		"body collision delivers substantial knockback to infantry")


func test_body_collision_prone_knockdown_on_hard_impact() -> void:
	# Heavy charging cavalry impact at maximum gallop fells prone
	var cav := _make_cavalry_unit(1, 0, Vector2(0, -10), 1)
	var inf := _make_infantry_unit(2, 1, Vector2.ZERO, 1)
	cav._sim_soldier_pos[0] = Vector2(0, -10)
	inf._sim_soldier_pos[0] = Vector2.ZERO
	cav._sim_body_vel[0] = Vector2(0, 170.0)
	inf._sim_body_vel[0] = Vector2.ZERO

	# Seed RNG to ensure prone fall roll passes
	Replay.rng.seed = 1
	SoldierEnemyContact.accumulate([cav, inf], 99103)
	assert_gt(inf._sim_prone[0], 0.0,
		"hard cavalry collision impact fells infantry soldier prone")


func test_cavalry_weapon_switch_between_lance_and_spatha() -> void:
	var cav := _make_cavalry_unit(1, 0, Vector2.ZERO, 5)
	assert_eq(cav.weapon_type_id, LoadoutRegistry.WEAPON_LANCE)
	assert_true(cav.can_equip_weapon(LoadoutRegistry.WEAPON_SPATHA),
		"cavalry can equip spatha")
	assert_true(cav.equip_weapon(LoadoutRegistry.WEAPON_SPATHA),
		"equipping spatha succeeds")
	assert_eq(cav.weapon_type_id, LoadoutRegistry.WEAPON_SPATHA)
	assert_almost_eq(cav.attack_range,
		LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_SPATHA).reach_wu, 1e-4)

	assert_true(cav.can_equip_weapon(LoadoutRegistry.WEAPON_LANCE),
		"cavalry can switch back to lance")
	assert_true(cav.equip_weapon(LoadoutRegistry.WEAPON_LANCE),
		"equipping lance succeeds")
	assert_eq(cav.weapon_type_id, LoadoutRegistry.WEAPON_LANCE)
	assert_almost_eq(cav.attack_range,
		LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_LANCE).reach_wu, 1e-4)

