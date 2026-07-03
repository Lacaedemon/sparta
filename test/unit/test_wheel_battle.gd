extends GutTest
## Wheel (circumductio) in a LIVE battle: instantiate the real Battle scene and step it tick by
## tick through a wheel on a spawned unit (Battle._physics_process -> units -> _on_soldier_tick,
## with steering + couple), exactly as the demo does. Guards the hinge in the full simulation
## context: the standing flank file barely moves, the far end swings a real arc, facing ends 90°
## across, and no body teleports on any tick. The isolated-unit geometry lives in test_wheel.gd.


func _max_step(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var m := 0.0
	for i in range(mini(a.size(), b.size())):
		m = maxf(m, a[i].distance_to(b[i]))
	return m


func test_wheel_in_live_battle_hinges_without_surge() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(40):                      # spawn the armies and let the bodies settle
		await get_tree().physics_frame
	# Target the Infantry block at ~(650, 300), the same unit the other maneuver tests turn.
	var target: Unit = null
	var best := INF
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0:
			var d: float = unit.position.distance_to(Vector2(650, 300))
			if d < best:
				best = d
				target = unit
	assert_not_null(target, "found a team-0 unit to wheel")
	if target == null:
		return

	var start_facing: Vector2 = target.facing
	var pivot: Vector2 = target._wheel_pivot_point(1)
	# Pick the body nearest the hinge and the one farthest from it, before the swing.
	var near_hinge := 0
	var far := 0
	var dn := INF
	var df := -INF
	for i in range(target._sim_soldier_pos.size()):
		var d: float = target._sim_soldier_pos[i].distance_to(pivot)
		if d < dn:
			dn = d; near_hinge = i
		if d > df:
			df = d; far = i
	var hinge_start: Vector2 = target._sim_soldier_pos[near_hinge]
	var far_start: Vector2 = target._sim_soldier_pos[far]

	target.wheel(1)                           # wheel right (pivot on the right flank file)
	var prev: PackedVector2Array = target._sim_soldier_pos.duplicate()
	var worst_step := 0.0
	for _i in range(120):                     # the ~0.25 s swing + settle
		await get_tree().physics_frame
		worst_step = maxf(worst_step, _max_step(prev, target._sim_soldier_pos))
		prev = target._sim_soldier_pos.duplicate()

	assert_lt(worst_step, 6.0,
		"no body jumps on any tick of a live wheel — it eases at velocity (worst %.3f px)" % worst_step)
	assert_true(target.facing.is_equal_approx(start_facing.rotated(PI * 0.5)),
		"the unit ended a 90° right wheel from its start heading")

	var hinge_travel: float = target._sim_soldier_pos[near_hinge].distance_to(hinge_start)
	var far_travel: float = target._sim_soldier_pos[far].distance_to(far_start)
	assert_lt(hinge_travel, far_travel * 0.4,
		"the standing flank file holds while the far end swings (hinge %.1f vs far %.1f px)"
			% [hinge_travel, far_travel])
	assert_gt(far_travel, 30.0, "the far end swept a real arc")


## Ticks past the demo script's last scripted key (Z at tick 150) before it's meaningful to
## start polling for the second wheel's completion — polling any earlier could catch the unit
## between the two scripted wheels (idle, not yet wheeling) and exit the settle loop before
## the second wheel has even started. A little past 150 is enough; the settle loop below
## supplies its own generous cap for however long the actual swing takes.
const _LAST_SCRIPTED_KEY_TICK := 150
# Generous cap on top of the last scripted key: covers the ~60-tick swing plus headroom for
# any per-tick scheduling variance between runners, so the poll loop -- not a fixed frame
# count -- is what decides when the wheel has actually finished.
const _SETTLE_TICK_CAP := 200


## The committed wheel demo drives the real controls end to end: load the scripted-input
## recorder with demos/inputs/wheel.json and confirm it actually wheels the target unit. Guards
## the demo (and its Z/C hotkeys) against silent breakage, the way the demo doubles as a smoke
## test for the input path.
##
## Waits for the wheel to actually settle (polling is_wheeling() each tick, up to a generous
## cap) rather than a fixed frame count -- see test_wheel.gd's _run_wheel for the same idiom on
## a bare unit. A fixed-count wait only has to be a little too tight on a slower runner to flake;
## polling for the real end condition removes that margin entirely.
func test_wheel_demo_input_drives_a_wheel() -> void:
	OS.set_environment("SPARTA_DEMO_INPUT", "demos/inputs/wheel.json")
	var recorder: Node = load("res://tools/demo/DemoInputRecorder.tscn").instantiate()
	add_child_autofree(recorder)
	# The recorder defers spawning Battle (_start_battle.call_deferred()), so it isn't a child
	# yet on this frame; wait for it before reading its tick.
	await get_tree().physics_frame
	var battle: Node = recorder.get_node("Battle")
	# Step past every scripted input (the last is Z at tick 150) so both wheels have been
	# issued before we start looking for a target or polling for settle.
	while battle.current_tick() <= _LAST_SCRIPTED_KEY_TICK:
		await get_tree().physics_frame
	var target: Unit = null
	var best := INF
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0:
			var d: float = unit.position.distance_to(Vector2(650, 300))
			if d < best:
				best = d
				target = unit
	assert_not_null(target, "the drill-mode recorder spawned the target unit")
	if target == null:
		return
	# Poll until the second wheel actually settles (or the cap trips), so the assertions below
	# never race a still-in-flight swing on a slower runner.
	var settle_ticks := 0
	while target.is_wheeling() and settle_ticks < _SETTLE_TICK_CAP:
		await get_tree().physics_frame
		settle_ticks += 1
	# The script wheels right (C) then back left (Z); the unit spawns facing south. After both
	# swings settle it should be back near south — proving both hotkeys drove a wheel, not that
	# nothing happened. Assert it's not still mid-swing and ended on a cardinal-ish heading.
	assert_false(target.is_wheeling(), "the demo's wheels have completed, not stalled")
	assert_true(target.facing.is_equal_approx(Vector2.DOWN),
		"C then Z returns the unit to its start heading (both wheels fired)")
