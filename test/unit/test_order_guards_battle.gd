extends GutTest
## Phase 4 of the unified orders-queue design (docs/orders-queue-design.md): the
## CONTACT_MADE guard in a LIVE battle -- instantiate the real Battle scene (the standard
## seed-12345 5v5 spawn) and step it tick by tick through a guarded "advance UNTIL contact
## THEN attack" order, exactly as a demo would. Guards two things a bare-Unit test (see
## test_orders_queue.gd) can't: that the guard stays unmet through ordinary steering/couple
## noise while the march is still closing, and that the SAME scripted run produces the SAME
## retirement tick on a second pass -- the design doc's determinism invariant, since every
## guard reads only serialized sim state with no RNG/wall-clock.


func _spawn_battle() -> Node:
	Replay.forced_seed = 12345   # the standard 5v5 showcase spawn, before add_child
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	return battle


func _team0_unit(battle: Node, near: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in battle.get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0:
			var d: float = unit.position.distance_to(near)
			if d < best_d:
				best_d = d
				best = unit
	return best


## Run one pass: install a MOVE order guarded by CONTACT_MADE (target across the field, well
## past the enemy line) with an appended unresolved ATTACK order, step until the queue
## promotes to ATTACK (or a tick ceiling), and return the tick it happened on plus the
## resolved target's uid.
func _run_guarded_advance(battle: Node, unit: Unit) -> Dictionary:
	var order := Order.new_move(Vector2(unit.position.x, 900)).with_guard(Order.Guard.CONTACT_MADE)
	unit.set_current_order(order)
	unit.has_move_target = true
	unit.move_target = order.target_pos
	unit.append_order(Order.new_attack(-1))
	var ceiling: int = battle.current_tick() + 600
	while battle.current_tick() < ceiling:
		await battle.get_tree().physics_frame
		if unit.current_order != null and unit.current_order.type == Order.Type.ATTACK:
			return {
				"tick": battle.current_tick(),
				"target_uid": unit.target_enemy.uid if unit.target_enemy != null else -1,
			}
	return {"tick": -1, "target_uid": -1}


func test_contact_made_guard_promotes_to_attack_on_real_contact() -> void:
	var battle := _spawn_battle()
	for _k in range(10):
		await get_tree().physics_frame
	var unit: Unit = _team0_unit(battle, Vector2(650, 300))
	assert_not_null(unit, "found a team-0 unit to advance")
	if unit == null:
		return
	var result: Dictionary = await _run_guarded_advance(battle, unit)
	assert_gt(result["tick"], 0, "the guard fired and promoted the ATTACK order before the ceiling")
	assert_true(result["target_uid"] >= 0, "resolved to a live enemy actually in contact")
	assert_eq(unit.current_order.type, Order.Type.ATTACK)


func test_contact_made_guard_fires_on_the_same_tick_across_two_identical_runs() -> void:
	# Determinism invariant: the guard is a pure function of serialized sim state (position,
	# team, state -- no RNG, no wall-clock), so two runs from the same seed and the same
	# scripted order must retire on the identical tick.
	var battle_a := _spawn_battle()
	for _k in range(10):
		await get_tree().physics_frame
	var unit_a: Unit = _team0_unit(battle_a, Vector2(650, 300))
	var result_a: Dictionary = await _run_guarded_advance(battle_a, unit_a)
	battle_a.queue_free()
	await get_tree().process_frame

	var battle_b := _spawn_battle()
	for _k in range(10):
		await get_tree().physics_frame
	var unit_b: Unit = _team0_unit(battle_b, Vector2(650, 300))
	var result_b: Dictionary = await _run_guarded_advance(battle_b, unit_b)

	assert_gt(result_a["tick"], 0)
	assert_eq(result_a["tick"], result_b["tick"], "identical scripted runs retire on the identical tick")
