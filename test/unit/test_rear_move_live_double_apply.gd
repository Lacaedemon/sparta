extends GutTest
## Live-battle regression for the historical double-apply race, now against the tree-based
## rear-move composite (docs/atomic-order-decomposition-design.md). The race: dispatching a
## rear-sector move through the REAL live-input path (Battle.enqueue_order applies it
## immediately AND queues the same command for the next tick's drain) must arm the about-face
## EXACTLY once. The old flat-Phase composite could be hit by mutating the same order
## object's turn_target/phase a second time if the drain ever re-applied it; the tree-based
## rewrite must run its own advancement (begin_pivot building Order.children, the
## _finish_order_turn cascade) through the identical exactly-once _apply_order_live/
## _pending_orders path, not a new or duplicate trigger. A live Battle SCENE (not a bare
## Battle script, as test_battle.gd's unit-level coverage of this same race uses) is what
## actually exercises _physics_process's real tick drain end to end.

const SPAWN := Vector2(500, 430)

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _stage_lone_unit() -> Unit:
	Replay.forced_seed = 54321
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y, "count": 40, "facing": [0, 1]},
	]
	add_child(_battle)
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 0:
			# The hasty variant: no reform hold to step through (reform_before_move is a
			# per-unit field now; Spearmen's own spawn default is true, so this test's unit
			# needs an explicit override to keep exercising the no-reform path).
			u.reform_before_move = false
			return u
	return null


func test_live_dispatched_rear_move_arms_the_about_face_exactly_once() -> void:
	var u := _stage_lone_unit()
	assert_not_null(u, "the scenario staged the lone unit")
	if u == null:
		return
	for _k in range(40):   # let the spawned bodies settle on their slots
		await get_tree().physics_frame
	var start_facing: Vector2 = u.facing
	var before: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var dest := SPAWN + Vector2(0, -180)   # straight behind the DOWN-facing unit

	# The real live-input path: applies immediately (arming the about-face on a fresh
	# tree-based composite) AND queues the same command for the next _physics_process tick,
	# which must skip re-applying it (the "applied_live" tag) -- exactly what
	# SelectionManager's right-click dispatch does.
	_battle.enqueue_order([u.uid], dest, -1)
	assert_true(u.is_order_turning(), "the about-face armed on the live apply")
	var turn_leaf_after_live: Order = u.active_leaf()
	var turn_target_after_live: Vector2 = turn_leaf_after_live.turn_target

	# Drive the REAL tick drain (Battle._physics_process, not a hand-rolled stand-in): if the
	# composite's tree were ever rebuilt by a second apply, the turn would restart (or
	# cancel) right here -- the exact historical failure mode this regresses.
	await get_tree().physics_frame
	assert_eq(u.active_leaf(), turn_leaf_after_live,
		"the drain did not rebuild the composite's turn child")
	assert_eq(u.active_leaf().turn_target, turn_target_after_live,
		"the running about-face keeps its exact goal across the drain (no restart)")
	assert_false(u.has_move_target, "no march started by a phantom second apply")

	# Step the about-face out for real: the identity-holding invariant must survive a
	# live-dispatched order exactly as it does a directly-applied one -- every soldier holds
	# its own position; the block does not translate or rotate through centre.
	var worst_drift := 0.0
	for _i in range(240):
		await get_tree().physics_frame
		if not u.is_order_turning():
			break
		for i in range(before.size()):
			worst_drift = maxf(worst_drift, u._sim_soldier_pos[i].distance_to(before[i]))
	assert_false(u.is_order_turning(), "the about-face completed within its budget")
	assert_lt(worst_drift, 1.0,
		"every soldier held its own position through the turn (worst drift %.3f px)" % worst_drift)
	assert_true(u.facing.is_equal_approx(-start_facing),
		"the unit ended facing the reverse of its start heading")

	# And the parked march commits cleanly afterward -- the composite's tree cursor actually
	# advanced to its march child, not stuck mid-turn or duplicated by the drain.
	var started := false
	for _i in range(60):
		await get_tree().physics_frame
		if u.has_move_target:
			started = true
			break
	assert_true(started, "the parked march commits once the about-face completes")
	assert_eq(u.move_target, dest, "it marches to the destination the live order carried")
