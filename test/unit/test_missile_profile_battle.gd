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
	# Both shooters 290 wu from the enemy block (80 across, ~278.6 down); the pilum's 300-wu
	# reach covers it, the bow's 160-wu reach and 190-wu detection do not.
	_battle.scenario = [
		{"team": 0, "type": "Archers", "x": 580, "y": 300, "count": 30,
				"missile": LoadoutRegistry.MISSILE_PILUM},
		{"team": 0, "type": "Archers", "x": 740, "y": 300, "count": 30},
		{"team": 1, "type": "Archers", "x": 660, "y": 578.6, "count": 40},
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
