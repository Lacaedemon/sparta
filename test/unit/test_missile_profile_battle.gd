extends GutTest
## The design note's phase-2 acceptance scenario, run through the real Battle: a pilum-armed
## regiment staged 290 wu from an enemy fires at its own 300-wu reach, while an unprofiled
## Archers regiment beside it, the same 290 wu away, holds -- the enemy is past both its
## 160-wu reach and its 190-wu detection. A `missile` key on a scenario spec is how a demo
## or a test names the profile.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _unit_named(label_prefix: String, team: int) -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == team and u.unit_name.begins_with(label_prefix):
			return u
	return null


func test_a_pilum_unit_fires_at_its_own_range_while_an_unprofiled_one_holds() -> void:
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true            # never auto-ends; the enemy still deploys and fights
	_battle.all_teams_control = true     # no team-1 AI, so the enemy stands where posted
	# Both shooters 290 wu from the enemy block (160 across, ~241.9 down); the pilum's 300-wu
	# reach covers it, the bow's 160-wu reach and 190-wu detection do not. The shooters stand
	# 320 wu apart so their 252-wu lines never touch, and each spawns facing the enemy so no
	# turn-to-bear precedes the first volley (the same staging as the PR's demo).
	_battle.scenario = [
		{"team": 0, "type": "Archers", "x": 500, "y": 300, "count": 30,
				"missile": LoadoutRegistry.MISSILE_PILUM, "facing": [160, 241.87]},
		{"team": 0, "type": "Archers", "x": 820, "y": 300, "count": 30,
				"facing": [-160, 241.87]},
		{"team": 1, "type": "Archers", "x": 660, "y": 541.87, "count": 40},
	]
	add_child(_battle)
	await get_tree().physics_frame
	var units: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 0:
			units.append(u)
	assert_eq(units.size(), 2, "two player regiments spawned")
	var pilum: Unit = null
	var bow: Unit = null
	for u in units:
		if u.missile_type_id == LoadoutRegistry.MISSILE_PILUM:
			pilum = u
		else:
			bow = u
	assert_not_null(pilum, "the scenario's missile key equipped the pilum profile")
	assert_not_null(bow, "and the other regiment kept the default")
	if pilum == null or bow == null:
		return
	assert_eq(pilum.missile_range, 15.0 * WorldScaleRef.WU_PER_M, "pilum reach is 15 m")
	assert_eq(bow.missile_range, Unit.RANGED_RANGE, "the unprofiled reach is the default")
	var enemy: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 1:
			enemy = u
	assert_not_null(enemy, "the enemy deployed")
	if enemy == null:
		return
	var d_pilum: float = pilum.position.distance_to(enemy.position)
	var d_bow: float = bow.position.distance_to(enemy.position)
	assert_true(d_pilum > Unit.DETECTION_RANGE and d_pilum < pilum.missile_range,
		"staging: the enemy is past default detection (%.1f) but inside the pilum reach" % d_pilum)
	assert_true(d_bow > Unit.RANGED_RANGE,
		"staging: and past the unprofiled reach for the bow regiment (%.1f)" % d_bow)
	# A few ticks: acquisition and the turn-to-face happen on the first _think passes.
	for _i in range(30):
		await get_tree().physics_frame
	assert_eq(pilum.state, Unit.State.FIGHTING, "the pilum regiment is loosing at 290 wu")
	assert_eq(pilum.target_enemy, enemy, "at the staged enemy")
	assert_ne(bow.state, Unit.State.FIGHTING, "the unprofiled regiment beside it holds")
	assert_null(bow.target_enemy, "with nothing acquired")


func test_battle_snapshot_restore_preserves_pilum_profile() -> void:
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.all_teams_control = true
	_battle.scenario = [
		{"team": 0, "type": "Archers", "x": 500, "y": 300, "count": 30,
				"missile": LoadoutRegistry.MISSILE_PILUM, "facing": [160, 241.87]},
	]
	add_child(_battle)
	await get_tree().physics_frame
	var snap: Dictionary = _battle.capture_snapshot()
	_battle.restore_snapshot(snap)
	var pilum: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 0:
			pilum = u
			break
	assert_not_null(pilum, "restored pilum unit exists")
	if pilum == null:
		return
	assert_eq(pilum.missile_type_id, LoadoutRegistry.MISSILE_PILUM, "pilum profile preserved after rewind")
	assert_almost_eq(pilum.missile_range, 15.0 * WorldScaleRef.WU_PER_M, 0.001, "pilum reach preserved")
	assert_almost_eq(pilum.detection_range, 15.0 * WorldScaleRef.WU_PER_M, 0.001, "detection range preserved")
	assert_almost_eq(pilum.skirmish_kite_distance,
			15.0 * WorldScaleRef.WU_PER_M * Unit.SKIRMISH_KITE_FRACTION, 0.001, "kite distance preserved")


func test_unknown_missile_profile_in_scenario_warns_and_keeps_defaults() -> void:
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.all_teams_control = true
	_battle.scenario = [
		{"team": 0, "type": "Archers", "x": 500, "y": 300, "count": 30,
				"missile": 99},
	]
	add_child(_battle)
	await get_tree().physics_frame
	var spawned: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 0:
			spawned = u
			break
	assert_not_null(spawned, "unit spawned despite unknown missile profile id")
	if spawned == null:
		return
	assert_eq(spawned.missile_type_id, LoadoutRegistry.MISSILE_BOW, "unit keeps the default bow profile")
	assert_almost_eq(spawned.missile_range, Unit.RANGED_RANGE, 0.001, "keeps default range")
	assert_almost_eq(spawned.missile_interval, Unit.RANGED_INTERVAL, 0.001, "keeps default interval")
	assert_almost_eq(spawned.missile_damage_factor, Unit.RANGED_DAMAGE_FACTOR, 0.001, "keeps default damage factor")
	assert_almost_eq(spawned.missile_accuracy_at_max, Unit.RANGED_ACCURACY_AT_MAX, 0.001, "keeps default accuracy")
	assert_almost_eq(spawned.detection_range, Unit.DETECTION_RANGE, 0.001, "keeps default detection")
	assert_almost_eq(spawned.skirmish_kite_distance, Unit.SKIRMISH_KITE_DISTANCE, 0.001, "keeps default kite distance")


