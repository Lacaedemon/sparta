extends GutTest
## Regression guard for a Battle teardown leak (#477): spawning and freeing several full
## Battle scenes in one test run must never corrupt a LATER, unrelated battle's soldier-body
## seeding. Battle._exit_tree() used to guard its physics_frame disconnect with
## `get_tree().physics_frame.is_connected(...)` -- during real tree teardown get_tree() can
## already be null, so that guard itself throws, the disconnect never runs, and the two
## lines after it (PathField.active = null / ProjectileField.active = null) never execute
## either. Enough leaked battles left enough dangling physics_frame connections and freed-node
## references that a later, unrelated battle's soldier bodies failed to seed
## (_sim_soldier_pos.size() == 0), producing nan in formation math.
##
## This spawns+frees several battles in a row (well above the "one or two is fine" threshold
## the issue reported), then spawns one more and asserts its units seed real, finite soldier
## bodies -- the same failure mode test_quarter_turn_battle.gd hit downstream.


const SPAWN_COUNT := 6


func _await_ticks(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame


func test_many_battle_spawns_dont_corrupt_a_later_battles_soldier_seeding() -> void:
	for i in range(SPAWN_COUNT):
		var battle: Node = load("res://scenes/Battle.tscn").instantiate()
		add_child(battle)
		await _await_ticks(3)   # let _ready spawn the lines and a couple of soldier-body ticks run
		battle.queue_free()
		await _await_ticks(2)   # let queue_free() + _exit_tree() actually settle before the next spawn

	# One more battle after the leak-prone churn above: its units must seed real soldier bodies.
	var fresh: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(fresh)
	await _await_ticks(5)

	var team0_units: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0:
			team0_units.append(unit)

	assert_gt(team0_units.size(), 0, "the fresh battle actually spawned team-0 units")

	for unit: Unit in team0_units:
		assert_gt(unit._sim_soldier_pos.size(), 0,
				"%s seeded its soldier bodies (not left empty by a leaked prior battle)" % unit.unit_name)
		for p in unit._sim_soldier_pos:
			assert_false(is_nan(p.x) or is_nan(p.y),
					"%s's soldier positions are finite, not nan" % unit.unit_name)


func test_physics_frame_has_no_leaked_battle_connections_after_repeated_spawns() -> void:
	# Directly asserts the disconnect side of the leak: after N spawn+free cycles, the
	# SceneTree's physics_frame signal must have at most the ONE connection belonging to
	# whichever battle is currently alive (zero once the last one is freed) -- not one
	# per battle that ever existed.
	for i in range(SPAWN_COUNT):
		var battle: Node = load("res://scenes/Battle.tscn").instantiate()
		add_child(battle)
		await _await_ticks(2)
		battle.queue_free()
		await _await_ticks(2)

	var connections: Array = get_tree().physics_frame.get_connections()
	var battle_connections := 0
	for c in connections:
		var target: Object = c.get("callable", Callable()).get_object()
		if target != null and target.has_method("_on_soldier_tick"):
			battle_connections += 1

	assert_eq(battle_connections, 0,
			"no freed Battle's _on_soldier_tick stays connected to physics_frame (%d leaked)" \
			% battle_connections)
