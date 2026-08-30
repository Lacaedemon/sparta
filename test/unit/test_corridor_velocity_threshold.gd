extends GutTest

const SPAWN := Vector2(600, 420)
var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func test_arrival_braking_approach_velocity_monotonic_crossing() -> void:
	_battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(_battle)
	await get_tree().physics_frame

	var u: Unit = _battle.get_node_or_null("Units/Infantry_0")
	if u == null:
		var units: Array = _battle.get_tree().get_nodes_in_group("units")
		if not units.is_empty():
			u = units[0]
	assert_not_null(u, "Infantry unit exists in battle")
	if u == null:
		return

	u.position = SPAWN
	var ord: Order = Order.new_move(SPAWN + Vector2(0, 100))
	ord.gait = Unit.GAIT_WALK
	u.set_current_order(ord)

	var threshold_crossings := 0
	var was_above_threshold := false
	var consecutive_ticks_near_boundary := 0

	for _i in range(120):
		_battle._physics_process(1.0 / 60.0)
		var v_sq: float = u._approach_velocity.length_squared()
		var is_above: bool = v_sq > 0.0001
		if is_above != was_above_threshold:
			threshold_crossings += 1
			was_above_threshold = is_above

		# Near boundary check: within [0.00005, 0.0002] (approx speed in [0.007, 0.014] wu/s)
		if v_sq >= 0.00005 and v_sq <= 0.0002:
			consecutive_ticks_near_boundary += 1

	# Marching threshold transitions from false -> true (startup) -> false (arrival).
	# At most 2 transitions (startup and arrival), never oscillating back and forth.
	assert_lte(threshold_crossings, 2, "threshold crossing occurs cleanly without oscillation")
	assert_lte(consecutive_ticks_near_boundary, 1, "velocity does not hover near 0.01 wu/s boundary")
