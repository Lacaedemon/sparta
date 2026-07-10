extends GutTest
## Sweep routers attack mode: a unit under this order prioritizes routing enemies
## (broken/shattered units) over still-fighting ones, even if a non-routing enemy is closer.
##
## The test stages three units: a team-0 unit under SWEEP_ROUTERS order, a far-away
## team-1 unit (will be routed), and a closer non-routing team-1 unit. When the far
## unit routs, the test verifies the sweeper re-targets it in preference to the closer
## still-fighting unit.


const Battle = preload("res://scripts/Battle.gd")
var _battle: Node = null


func after_each() -> void:
	# Free this test's battle before the next test spawns, so units don't linger in
	# the shared "units"/"routers" groups and pollute a later test's group scan.
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _spawn_three_unit_battle() -> Node:
	_battle = load("res://scenes/Battle.tscn").instantiate()
	# Team 0: one infantry unit that will be armed with SWEEP_ROUTERS, positioned center
	# Team 1: one unit far from team 0 (will be routed), and one closer unit (will remain fighting)
	#
	# Both team-1 units must sit within Unit.DETECTION_RANGE (190px) of the sweeper, or
	# UnitTargeting.nearest_enemy/nearest_routing_enemy never sees them at all and
	# target_enemy stays null regardless of which one should win priority. Both units
	# sit on the same +x side, at 80px and 170px, so distance-to-sweeper and the
	# tests' own "smaller x = closer" identification (both team-1 units share the
	# sweeper's y, so x-order and distance-order agree) stay consistent, and both
	# distances remain comfortably inside the 190px detection radius throughout.
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 500, "y": 500},
		{"team": 1, "type": "Infantry", "x": 580, "y": 500},    # Closer non-routing unit
		{"team": 1, "type": "Infantry", "x": 670, "y": 500},    # Far unit (will be routed)
	]
	add_child(_battle)
	return _battle


func _find_unit_of_team(team: int) -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == team:
			return unit
	return null


func _find_all_units_of_team(team: int) -> Array:
	var result: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == team:
			result.append(unit)
	for u in get_tree().get_nodes_in_group("routers"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == team:
			result.append(unit)
	return result


func test_sweep_routers_prioritizes_routing_over_closer_non_routing() -> void:
	var battle := _spawn_three_unit_battle()
	await get_tree().physics_frame  # _ready spawns the scenario units

	# Find all three units
	var sweeper: Unit = null
	var closer_enemy: Unit = null
	var far_enemy: Unit = null

	var team0_units = _find_all_units_of_team(0)
	assert_eq(team0_units.size(), 1, "one team-0 unit spawned")
	sweeper = team0_units[0]

	var team1_units = _find_all_units_of_team(1)
	assert_eq(team1_units.size(), 2, "two team-1 units spawned")

	# Identify which is closer and which is far based on position
	if team1_units[0].position.x < team1_units[1].position.x:
		closer_enemy = team1_units[0]
		far_enemy = team1_units[1]
	else:
		closer_enemy = team1_units[1]
		far_enemy = team1_units[0]

	# Verify distance assumptions: closer_enemy should be nearer to sweeper than far_enemy
	var dist_to_closer = sweeper.position.distance_to(closer_enemy.position)
	var dist_to_far = sweeper.position.distance_to(far_enemy.position)
	assert_lt(dist_to_closer, dist_to_far,
		"closer_enemy is indeed closer (%.1f < %.1f)" % [dist_to_closer, dist_to_far])

	# Arm the sweeper with SWEEP_ROUTERS order mode
	sweeper.order_mode = Battle.OrderMode.SWEEP_ROUTERS

	# Tick a few frames so the sweeper can acquire the closer (non-routing) target normally
	for _i in range(10):
		await get_tree().physics_frame

	# At this point, sweeper should have the closer non-routing enemy as target
	assert_eq(sweeper.target_enemy, closer_enemy,
		"initially targets the closer non-routing enemy")

	# Now route the far enemy (this moves it to the "routers" group). _rout() alone
	# doesn't keep it routing: an undamaged unit still has full morale, and
	# _process_rout rallies a routing unit back to IDLE on its very first tick once
	# morale is at/above RALLY_MORALE_THRESHOLD and it isn't in contact (see
	# Unit._can_rally) -- exactly this unit's situation, since the test never dealt
	# it any casualties. Force morale below the threshold first, the same pattern
	# test_morale_recovery_demo_scenario.gd uses, so it stays ROUTING long enough
	# for the sweeper to re-target it.
	far_enemy.morale = 1.0
	far_enemy._rout()
	assert_eq(far_enemy.state, Unit.State.ROUTING, "far_enemy is now routing")
	assert_true(far_enemy.is_in_group("routers"), "routed unit joined the routers group")

	# Tick a few more frames so SWEEP_ROUTERS targeting re-acquires
	for _i in range(5):
		await get_tree().physics_frame

	# The sweeper should now prioritize the routing enemy, even though it's still farther
	assert_eq(sweeper.target_enemy, far_enemy,
		"after routing, sweeper re-targets the routing enemy in preference to the closer still-fighting one")


func test_sweep_routers_falls_back_to_non_routing_if_no_routers_nearby() -> void:
	var battle := _spawn_three_unit_battle()
	await get_tree().physics_frame

	var sweeper: Unit = null
	var closer_enemy: Unit = null
	var team1_units = _find_all_units_of_team(1)

	if team1_units[0].position.x < team1_units[1].position.x:
		closer_enemy = team1_units[0]
	else:
		closer_enemy = team1_units[1]

	var team0_units = _find_all_units_of_team(0)
	sweeper = team0_units[0]

	# Arm the sweeper with SWEEP_ROUTERS
	sweeper.order_mode = Battle.OrderMode.SWEEP_ROUTERS

	# Tick a few frames for acquisition
	for _i in range(10):
		await get_tree().physics_frame

	# Verify it targets the closer enemy (no routers exist yet)
	assert_eq(sweeper.target_enemy, closer_enemy,
		"with no routing enemies, sweeper targets the nearest non-routing enemy")
