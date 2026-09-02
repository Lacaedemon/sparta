extends GutTest
## Quarter-turn -> explicatio combo in a LIVE battle: instantiate the real Battle scene and
## step it tick by tick through the combo on a spawned column (Battle._physics_process ->
## units -> _on_soldier_tick, with steering + couple), exactly as the demo does. Guards the
## maneuver in the full simulation context -- no body surge on any tick, the regiment centre
## stays put, the block ends as a line across its NEW facing -- and the live-dispatched-order
## double-apply race every recorded drill regresses (see test_countermarch_battle.gd):
## Battle.enqueue_turn_explicatio applies immediately AND queues the same command for the
## next tick's drain, which must skip re-applying it.

const SPAWN := Vector2(520, 400)
## 40 men at 5 files: a 5-wide, 8-deep column, so the frontage presented after the turn is
## 8 and the explicatio measured against the new facing lands on 16.
const COLUMN_FILES := 5
const COLUMN_COUNT := 40

# The regiment centre couples toward its soldiers' body centroid (SoldierBodies.couple), so
# a reshape shifts it by the amount the centroid moves as the ranks re-lay-out -- the same
# one-time settle test_file_doubling_battle.gd bounds at 15 px for a plain explicatio. This
# combo re-lays a 5x8 column into a 16x3 line, so the far files walk ~135 wu and the settle
# is correspondingly larger: measured at 24 wu on the demo scenario (state dump, ticks
# 480-900 identical once every man is on his slot), well under a real "the unit walked off"
# regression (tens of px and still moving).
const CENTRE_SETTLE_TOLERANCE_PX := 30.0

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


func _extent_along(u: Unit, axis: Vector2) -> float:
	var lo: float = INF
	var hi: float = -INF
	for p in u._sim_soldier_pos:
		var d: float = (p - u.position).dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return hi - lo


## Stage a single Infantry column (drill_mode: no opponent -- see the "drill" default in
## demos/README.md) so nothing can interrupt the combo.
func _stage_lone_column() -> Unit:
	Replay.forced_seed = 31337
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": SPAWN.x, "y": SPAWN.y, "count": COLUMN_COUNT,
			"frontage": COLUMN_FILES, "facing": [0, 1]},
	]
	add_child(_battle)
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 0:
			return u
	return null


func test_live_dispatched_combo_turns_once_then_unfolds_into_line() -> void:
	var u := _stage_lone_column()
	assert_not_null(u, "the scenario staged the lone column")
	if u == null:
		return
	for _k in range(40):   # let the spawned bodies settle on their slots
		await get_tree().physics_frame
	assert_eq(UnitFormation.frontage(u), COLUMN_FILES, "sanity: the column spawned at 5 files")
	var start_facing: Vector2 = u.facing
	var start_pos: Vector2 = u.position

	# The real live-input path: applies immediately (installing the combo with its turn
	# armed) AND queues the same command for the next _physics_process tick, which must skip
	# re-applying it (the "applied_live" tag) -- exactly what the Shift+Q dispatch does.
	_battle.enqueue_turn_explicatio([u.uid], -1)
	assert_true(u.is_order_turning(), "the quarter-turn armed on the live apply")
	assert_eq(u.current_order.type, Order.Type.COMBO)
	assert_eq(u.current_maneuver(), Unit.Maneuver.QUARTER_TURN)
	assert_false(u.quarter_turn_explicatio(-1), "a second combo mid-turn is refused, like any drill")
	var turn_leaf_after_live: Order = u.active_leaf()
	var turn_target_after_live: Vector2 = turn_leaf_after_live.turn_target

	# Drive the REAL tick drain: if the composite were ever rebuilt by a second apply, the
	# turn would restart (or cancel) right here.
	await get_tree().physics_frame
	assert_eq(u.active_leaf(), turn_leaf_after_live,
		"the drain did not rebuild the combo's turn step")
	assert_eq(u.active_leaf().turn_target, turn_target_after_live,
		"the running quarter-turn keeps its exact goal across the drain (no restart)")

	var prev: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var worst_step := 0.0
	var completed := false
	for _i in range(300):
		await get_tree().physics_frame
		worst_step = maxf(worst_step, _max_step(prev, u._sim_soldier_pos))
		prev = u._sim_soldier_pos.duplicate()
		if u.current_order == null:
			completed = true
			break
	assert_true(completed, "the whole combo (turn, then reshape) finished within its budget")
	assert_true(u.facing.is_equal_approx(start_facing.rotated(-PI * 0.5)),
		"the unit ended a quarter-turn LEFT of its start heading")
	assert_eq(UnitFormation.frontage(u), 2 * (COLUMN_COUNT / COLUMN_FILES),
		"the explicatio doubled the 8 files the column presents after turning (8 -> 16)")
	assert_lt(absf(wrapf(u._formation_angle, -PI, PI)), 0.01,
		"the reshape re-squared the grid to the new heading")

	# Let the bodies ease onto the reshaped slots (the far files walk ~135 wu, settled by
	# ~420 ticks on the demo scenario), still watching every tick for a jump.
	for _i in range(420):
		await get_tree().physics_frame
		worst_step = maxf(worst_step, _max_step(prev, u._sim_soldier_pos))
		prev = u._sim_soldier_pos.duplicate()
	assert_lt(worst_step, 6.0,
		"no body jumps on any tick of a live combo -- they hold through the turn and ease into the line (worst %.3f px)"
			% worst_step)
	assert_lt(u.position.distance_to(start_pos), CENTRE_SETTLE_TOLERANCE_PX,
		"the combo reshapes the formation around the regiment centre, not away from it")
	var lateral: Vector2 = u.facing.rotated(PI * 0.5)
	assert_gt(_extent_along(u, lateral), 2.0 * _extent_along(u, u.facing),
		"the settled block is a LINE across the new facing, not a column along it")
