extends GutTest
## The scenario spec's optional `order_mode` key: a demo stages a unit's starting stance
## by the Battle.ORDER_MODE_NAMES display name (case-insensitive, underscores accepted
## for spaces) or the raw Battle.OrderMode int. HOLD is the staging workhorse -- a held
## unit stands its ground instead of auto-advancing on a near enemy, so a scenario can
## bait a charge onto a fixed spot (the routing-terrain demo). An unrecognized value
## warns and keeps the default stance, mirroring starting_state's lenient handling.

const BattleScript = preload("res://scripts/Battle.gd")


func _spawn_with_scenario(scenario: Array) -> Dictionary:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	battle.scenario = scenario
	add_child_autofree(battle)
	await get_tree().physics_frame
	var by_name: Dictionary = {}
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null:
			by_name[unit.unit_name] = unit
	return by_name


func test_hold_stance_by_name_lands_on_the_spawned_unit() -> void:
	var units: Dictionary = await _spawn_with_scenario([
		{"team": 0, "type": "Infantry", "x": 300.0, "y": 300.0, "count": 20,
			"order_mode": "Hold"},
		{"team": 0, "type": "Spearmen", "x": 600.0, "y": 300.0, "count": 20},
	])
	assert_eq((units["Infantry 1"] as Unit).order_mode, int(BattleScript.OrderMode.HOLD),
		"the spec's order_mode name lands on the spawned unit")
	assert_eq((units["Spearmen 1"] as Unit).order_mode, int(BattleScript.OrderMode.NORMAL),
		"a spec without the key keeps the default stance")


func test_name_matching_is_case_insensitive_and_accepts_underscores() -> void:
	var units: Dictionary = await _spawn_with_scenario([
		{"team": 0, "type": "Infantry", "x": 300.0, "y": 300.0, "count": 20,
			"order_mode": "attack_flank"},
		{"team": 0, "type": "Spearmen", "x": 600.0, "y": 300.0, "count": 20,
			"order_mode": int(BattleScript.OrderMode.SKIRMISH)},
	])
	assert_eq((units["Infantry 1"] as Unit).order_mode,
		int(BattleScript.OrderMode.ATTACK_FLANK),
		"a lowercase, underscored name still matches its display name")
	assert_eq((units["Spearmen 1"] as Unit).order_mode, int(BattleScript.OrderMode.SKIRMISH),
		"a raw OrderMode int passes straight through")


func test_unknown_mode_warns_and_keeps_the_default_stance() -> void:
	var units: Dictionary = await _spawn_with_scenario([
		{"team": 0, "type": "Infantry", "x": 300.0, "y": 300.0, "count": 20,
			"order_mode": "charge_wildly"},
	])
	assert_eq((units["Infantry 1"] as Unit).order_mode, int(BattleScript.OrderMode.NORMAL),
		"an unrecognized order_mode leaves the unit at the default stance")
