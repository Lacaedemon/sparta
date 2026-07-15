extends GutTest
## Countermarch in a LIVE battle: instantiate the real Battle scene and step it tick by tick
## through a Macedonian countermarch on a spawned unit (Battle._physics_process -> units ->
## _on_soldier_tick, with steering + couple), exactly as the demo does. Guards the maneuver in
## the full simulation context -- no body surge on any tick -- and the live-dispatched-order
## double-apply race Battle.enqueue_order's rear-move counterpart already regresses (see
## test_rear_move_live_double_apply.gd): Battle.enqueue_countermarch applies immediately AND
## queues the same command for the next tick's drain, which must skip re-applying it.

const SPAWN := Vector2(500, 430)

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _max_step(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var m := 0.0
	for i in range(mini(a.size(), b.size())):
		m = maxf(m, a[i].distance_to(b[i]))
	return m


## Stage a single Spearmen unit (drill_mode: no opponent -- see the "drill" default in
## demos/README.md) so the countermarch has nothing to interrupt it.
func _stage_lone_unit() -> Unit:
	Replay.forced_seed = 24681
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y, "count": 60, "facing": [0, 1]},
	]
	add_child(_battle)
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 0:
			return u
	return null


func test_live_dispatched_countermarch_arms_the_about_face_exactly_once() -> void:
	var u := _stage_lone_unit()
	assert_not_null(u, "the scenario staged the lone unit")
	if u == null:
		return
	for _k in range(40):   # let the spawned bodies settle on their slots
		await get_tree().physics_frame
	var start_facing: Vector2 = u.facing

	# The real live-input path: applies immediately (arming the about-face on a fresh
	# composite) AND queues the same command for the next _physics_process tick, which must
	# skip re-applying it (the "applied_live" tag) -- exactly what the V-key dispatch does.
	_battle.enqueue_countermarch([u.uid], Unit.CountermarchVariant.MACEDONIAN)
	assert_true(u.is_order_turning(), "the about-face armed on the live apply")
	assert_eq(u.current_maneuver(), Unit.Maneuver.COUNTERMARCH)
	var turn_leaf_after_live: Order = u.active_leaf()
	var turn_target_after_live: Vector2 = turn_leaf_after_live.turn_target

	# Drive the REAL tick drain: if the composite were ever rebuilt by a second apply, the
	# turn would restart (or cancel) right here.
	await get_tree().physics_frame
	assert_eq(u.active_leaf(), turn_leaf_after_live,
		"the drain did not rebuild the composite's turn child")
	assert_eq(u.active_leaf().turn_target, turn_target_after_live,
		"the running about-face keeps its exact goal across the drain (no restart)")

	var prev: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var worst_step := 0.0
	var completed := false
	for _i in range(600):
		await get_tree().physics_frame
		worst_step = maxf(worst_step, _max_step(prev, u._sim_soldier_pos))
		prev = u._sim_soldier_pos.duplicate()
		if u.current_order == null:
			completed = true
			break
	assert_true(completed, "the whole composite (turn, reform, march) finished within its budget")
	assert_lt(worst_step, 6.0,
		"no body jumps on any tick of a live countermarch -- it eases at velocity (worst %.3f px)"
			% worst_step)
	assert_true(u.facing.is_equal_approx(-start_facing),
		"the unit ended facing the reverse of its start heading")
	assert_lt(u.position.y, SPAWN.y - 10.0,
		"Macedonian: the regiment advanced toward the new-facing ground (y decreased)")
