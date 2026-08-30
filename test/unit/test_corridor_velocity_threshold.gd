extends GutTest

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func test_arrival_braking_approach_velocity_monotonic_crossing() -> void:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(_battle)
	await get_tree().physics_frame

	var units: Array = _battle.get_tree().get_nodes_in_group("units")
	assert_gt(units.size(), 0, "Units exist in battle")
	if units.is_empty():
		return
	var u: Unit = units[0]

	var dest: Vector2 = u.position + Vector2(0, 30)
	_battle._apply_order_cmd({"units": [u.uid], "x": dest.x, "y": dest.y, "target": -1})

	var threshold_crossings := 0
	var was_above_threshold := false
	var max_consecutive_near_boundary := 0
	var current_consecutive_near_boundary := 0
	var saw_cruise_speed := false
	var saw_arrival_stop := false

	for _i in range(300):
		await get_tree().physics_frame
		var v_sq: float = u._approach_velocity.length_squared()
		var is_above: bool = v_sq > 0.0001
		if is_above != was_above_threshold:
			threshold_crossings += 1
			was_above_threshold = is_above

		if v_sq > 50.0:  # speed > 7 wu/s
			saw_cruise_speed = true

		# Near boundary check: within [0.00005, 0.0002] (approx speed in [0.007, 0.014] wu/s)
		if v_sq >= 0.00005 and v_sq <= 0.0002:
			current_consecutive_near_boundary += 1
			max_consecutive_near_boundary = maxi(max_consecutive_near_boundary, current_consecutive_near_boundary)
		else:
			current_consecutive_near_boundary = 0

		if saw_cruise_speed and not is_above and u.state == Unit.State.IDLE:
			saw_arrival_stop = true
			break

	assert_true(saw_cruise_speed, "unit accelerated to cruise speed")
	assert_true(saw_arrival_stop, "unit arrived at destination and braked to a stop")
	# Threshold crossing: false -> true (startup) -> false (arrival). Exactly 2 transitions.
	assert_eq(threshold_crossings, 2, "threshold crossing occurs cleanly with exactly startup and arrival transitions")
	assert_lte(max_consecutive_near_boundary, 1, "velocity does not hover near 0.01 wu/s boundary")
