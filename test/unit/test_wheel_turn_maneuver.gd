extends GutTest
## A LARGE rear-sector move order -- oblique enough that a straight about-face (a full 180°
## reversal) would still leave a sizeable misalignment to the destination -- about-faces,
## THEN flank-pivots (wheels) the rest of the way onto the destination bearing, THEN
## marches. Rather than about-face-then-march alone (is_rear_move's own composite, which
## leaves the march's own gradual centre-pivot to close the leftover), the extra flank-pivot
## phase closes it with a drilled turn first. See UnitManeuver's own doc block and
## Unit.begin_about_face_with_wheel. Three layers, mirroring test_lateral_pivot_maneuver.gd:
## the pure UnitManeuver.is_wheel_turn/wheel_turn_dir classifiers (no SceneTree), a
## unit-level integration stepping _think tick by tick through the
## about-face -> wheel -> march phases, and a Battle-level integration confirming
## _apply_order_cmd picks this path over the sibling maneuvers.

const Maneuver = preload("res://scripts/UnitManeuver.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")
const DemoDefects = preload("res://tools/demo/DemoDefects.gd")

const FACING_RIGHT := Vector2.RIGHT
const FACING_DOWN := Vector2.DOWN


# --- pure classifiers -------------------------------------------------------

func test_residual_is_zero_when_destination_is_exactly_behind() -> void:
	assert_almost_eq(Maneuver.rear_move_wheel_residual_deg(FACING_RIGHT, Vector2(-100, 0)), 0.0, 0.01,
		"a destination exactly opposite the post-about-face heading needs no further pivot")


func test_residual_is_45_degrees_at_the_rear_move_boundary() -> void:
	var move_vec := FACING_RIGHT.rotated(deg_to_rad(135.0)) * 100.0
	assert_almost_eq(Maneuver.rear_move_wheel_residual_deg(FACING_RIGHT, move_vec), 45.0, 0.1,
		"the most oblique rear-sector move (135° off facing) leaves the largest residual")


func test_degenerate_inputs_have_zero_residual() -> void:
	assert_eq(Maneuver.rear_move_wheel_residual_deg(Vector2.ZERO, Vector2(-10, 0)), 0.0)
	assert_eq(Maneuver.rear_move_wheel_residual_deg(FACING_RIGHT, Vector2.ZERO), 0.0)


func test_wheel_turn_triggers_for_the_more_oblique_part_of_the_rear_sector() -> void:
	# 140° off facing -> residual 40° (>= WHEEL_MIN_RESIDUAL_ANGLE_DEG=30): wheel-turn.
	var oblique := FACING_RIGHT.rotated(deg_to_rad(140.0)) * 100.0
	assert_true(Maneuver.is_wheel_turn(FACING_RIGHT, oblique),
		"a residual past the threshold arms the extra flank-pivot phase")


func test_wheel_turn_does_not_trigger_near_straight_behind() -> void:
	# 160° off facing -> residual 20° (< 30): about-face+march alone handles it, same as today.
	var near_straight_behind := FACING_RIGHT.rotated(deg_to_rad(160.0)) * 100.0
	assert_true(Maneuver.is_rear_move(FACING_RIGHT, near_straight_behind), "still a rear move")
	assert_false(Maneuver.is_wheel_turn(FACING_RIGHT, near_straight_behind),
		"but too little residual to need the extra flank-pivot phase")


func test_wheel_turn_is_never_true_outside_the_rear_sector() -> void:
	assert_false(Maneuver.is_wheel_turn(FACING_RIGHT, Vector2(100, 0)),
		"marching forward is never a wheel-turn")
	assert_false(Maneuver.is_wheel_turn(FACING_RIGHT, Vector2(0, 100)),
		"a 90° flank move is never a wheel-turn (that's is_lateral_pivot's own case)")


func test_wheel_turn_boundary_matches_the_residual_threshold() -> void:
	# angle_to_facing = 150° -> residual exactly 30° (the boundary): included.
	# angle_to_facing = 151° -> residual 29° : excluded.
	var at_boundary := FACING_RIGHT.rotated(deg_to_rad(150.0)) * 100.0
	var just_past := FACING_RIGHT.rotated(deg_to_rad(151.0)) * 100.0
	assert_true(Maneuver.is_wheel_turn(FACING_RIGHT, at_boundary),
		"exactly WHEEL_MIN_RESIDUAL_ANGLE_DEG of residual still arms the wheel phase")
	assert_false(Maneuver.is_wheel_turn(FACING_RIGHT, just_past),
		"just under the threshold does not")


func test_degenerate_inputs_are_not_a_wheel_turn() -> void:
	assert_false(Maneuver.is_wheel_turn(Vector2.ZERO, Vector2(-100, 0)), "no facing")
	assert_false(Maneuver.is_wheel_turn(FACING_RIGHT, Vector2.ZERO), "zero-length move")


func test_wheel_turn_dir_turns_toward_the_destinations_side_of_the_new_heading() -> void:
	# facing DOWN: post-about-face heading is UP=(0,-1); UP.rotated(PI/2) = (1,0) = world
	# +x, so a destination on the -x side of the new heading turns dir=-1 (and +x -> dir=+1).
	assert_eq(Maneuver.wheel_turn_dir(FACING_DOWN, Vector2(-100, -150)), -1,
		"a destination toward -x of the reversed heading pivots dir=-1")
	assert_eq(Maneuver.wheel_turn_dir(FACING_DOWN, Vector2(100, -150)), 1,
		"a destination toward +x of the reversed heading pivots dir=+1")


# --- unit-level integration --------------------------------------------------

func _make_seeded_unit() -> Unit:
	var u: Unit = UnitScript.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = FACING_DOWN
	u.seed_sim_soldiers()
	return u


## Arm an about-face + wheel + march composite exactly as Battle._apply_order_cmd does.
func _arm_wheel_turn(u: Unit, dest: Vector2) -> Order:
	var o := Order.new_move(dest)
	o.reform = false
	u.set_current_order(o)
	u.has_move_target = false
	var move_vec: Vector2 = dest - u.position
	var wheel_dir: int = Maneuver.wheel_turn_dir(u.facing, move_vec)
	assert_true(u.begin_about_face_with_wheel(o, wheel_dir),
		"the about-face + wheel armed (bodies were seeded)")
	return o


func _step_until(u: Unit, predicate: Callable, max_ticks: int = 400) -> bool:
	for _i in range(max_ticks):
		u._think(0.016)
		if predicate.call():
			return true
	return false


func test_wheel_turn_refuses_when_the_about_face_cannot_arm() -> void:
	# Unseeded bodies are one of begin_pivot's own refusal conditions; the composite
	# must propagate that refusal so the caller falls back to a plain march.
	var u: Unit = UnitScript.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.facing = FACING_DOWN
	var o := Order.new_move(Vector2(200, -200))
	u.set_current_order(o)
	assert_false(u.begin_about_face_with_wheel(o, 1),
		"with no seeded soldier bodies the composite refuses instead of arming")


func test_wheel_turn_about_faces_first_holding_position() -> void:
	var u := _make_seeded_unit()
	var start_facing: Vector2 = u.facing
	var dest := FACING_DOWN.rotated(deg_to_rad(140.0)) * 200.0
	var o := _arm_wheel_turn(u, dest)

	assert_eq(o.effective_phase_name(), "TURN", "the composite opens with the about-face")
	assert_eq(u.current_maneuver(), UnitScript.Maneuver.CONVERSIO,
		"the opening about-face still reads as a full reversal, like a plain rear move's")

	u._think(0.016)
	assert_false(u.has_move_target, "no march starts until the about-face completes")
	assert_eq(u.position, Vector2.ZERO, "the block does not translate during the about-face")

	var reversed := _step_until(u, func(): return u.facing.is_equal_approx(-start_facing))
	assert_true(reversed, "the about-face completes, reversing facing exactly")


func test_wheel_turn_flank_pivots_after_the_about_face_then_marches() -> void:
	var u := _make_seeded_unit()
	var dest := FACING_DOWN.rotated(deg_to_rad(140.0)) * 200.0
	var o := _arm_wheel_turn(u, dest)
	var start_facing: Vector2 = u.facing

	# Run past the about-face; the wheel phase should now be live.
	var wheeling := _step_until(u, func(): return u.is_wheeling())
	assert_true(wheeling, "the flank pivot arms right after the about-face completes")
	assert_eq(o.effective_phase_name(), "WHEEL", "the composite reports its own WHEEL phase")
	assert_eq(u.current_maneuver(), UnitScript.Maneuver.WHEELING)
	assert_true(u.facing.is_equal_approx(-start_facing),
		"the wheel starts from the about-face's reversed heading")

	# Run past the wheel; the march should now be underway, aimed at the destination.
	var marching := _step_until(u, func(): return u.has_move_target)
	assert_true(marching, "the march starts once the flank pivot completes")
	assert_eq(o.effective_phase_name(), "MARCH")
	assert_eq(u.move_target, dest, "it marches to the original destination")
	assert_true(u.facing.is_equal_approx(dest.normalized()),
		"the flank pivot swung facing to point directly at the destination")
	assert_ne(u.position, Vector2.ZERO,
		"unlike the about-face, the wheel itself displaces the block along its hinge arc")


func test_wheel_hinge_sits_on_the_physical_front_after_the_about_face() -> void:
	# The completed about-face folds _formation_angle to ±PI, spinning the slot grid's
	# nominal axes 180°. The hinge must still land at the leading man of the standing
	# flank RELATIVE TO THE NEW FACING -- taking the spun axes raw instead puts it at the
	# rear corner of the opposite flank, and the whole block visibly wheels BACKWARD
	# around it (every soldier backpedaling through the swing).
	var u := _make_seeded_unit()
	var dest := FACING_DOWN.rotated(deg_to_rad(140.0)) * 200.0
	var o := _arm_wheel_turn(u, dest)
	var wheeling := _step_until(u, func(): return u.is_wheeling())
	assert_true(wheeling, "the flank pivot armed")

	var leaf: Order = u.active_leaf()
	var hinge_offset: Vector2 = leaf.pivot - u.position
	assert_gt(hinge_offset.dot(u.facing), 0.0,
		"the hinge sits AHEAD of the block centre along the post-about-face facing")

	# And the block must swing forward, not backpedal: track the centre through the whole
	# wheel -- its net displacement projects positively onto the (rotating) facing.
	var forward_travel: float = 0.0
	for _i in range(600):
		var before: Vector2 = u.position
		u._think(0.016)
		forward_travel += (u.position - before).dot(u.facing)
		if not u.is_wheeling():
			break
	assert_false(u.is_wheeling(), "the wheel completed within budget")
	assert_gt(forward_travel, 0.0,
		"the block's centre advances with facing through the swing -- a forward wheel")


func test_wheel_turn_reforms_on_arrival() -> void:
	var u := _make_seeded_unit()
	u.frontage_override = 8   # a partial last rank, so a reform is a real, detectable change
	u.seed_sim_soldiers()
	var dest := FACING_DOWN.rotated(deg_to_rad(140.0)) * 120.0
	var o := _arm_wheel_turn(u, dest)

	var arrived := _step_until(u, func(): return u.current_order == null, 1200)
	assert_true(arrived, "the whole composite (about-face, wheel, march) completes")
	assert_almost_eq(wrapf(u._formation_angle, -PI, PI), 0.0, 0.01,
		"the grid re-squares to the new heading on arrival, same as a plain rear move's " +
		"own un-checked default")
	# Post-turn arrival reform holds ground: mirror is armed and short files step forward
	assert_true(u._formation_mirror_x, "the depth-only mirror is armed for hold-ground reform")


## Regression test: after _finish_wheel + arrival, the zero-displacement property holds
## for full-depth files, short files step one pitch, and _reform_on_arrival is false afterwards.
func test_wheel_turn_arrival_holds_ground_and_clears_reform_on_arrival() -> void:
	var u: Unit = UnitScript.new()
	u.max_soldiers = 40
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = FACING_DOWN
	u.frontage_override = 3
	u.seed_sim_soldiers()

	assert_true(u._effective_file_major_reform(),
		"precondition: file-major reform is effective")
	# Destination straight along the post-wheel heading (140 degrees off facing DOWN)
	var dest: Vector2 = FACING_DOWN.rotated(deg_to_rad(140.0)) * 100.0
	var o := _arm_wheel_turn(u, dest)

	# Step until the wheel phase finishes and the march begins
	var marching := _step_until(u, func(): return u.has_move_target and not u.is_wheeling(), 600)
	assert_true(marching, "wheel finished and march started")
	assert_true(u._reform_on_arrival, "_reform_on_arrival is armed after wheel")

	# Straightens the post-wheel march so the relative-offset measurement has a constant heading, and is scaffolding for the march leg rather than the reform under test.
	u.move_target = u.position + u.facing * 100.0
	u.active_leaf().target_pos = u.move_target

	# Capture unit-relative offsets just before arrival reform triggers
	var pre_arrival_pos: Vector2 = u.position
	var pre_arrival_slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var pre_offsets: Array[Vector2] = []
	for s in pre_arrival_slots:
		pre_offsets.append(s - pre_arrival_pos)

	# Step until arrival at destination
	var arrived := _step_until(u, func(): return u.current_order == null, 1200)
	assert_true(arrived, "composite completed and arrived at destination")
	assert_false(u._reform_on_arrival, "_reform_on_arrival is false after arrival reform")
	assert_almost_eq(wrapf(u._formation_angle, -PI, PI), 0.0, 0.01,
		"formation angle re-squared to heading")

	# Compute displacement across the arrival reform using unit-relative offsets
	var post_arrival_pos: Vector2 = u.position
	var post_arrival_slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var post_offsets: Array[Vector2] = []
	for s in post_arrival_slots:
		post_offsets.append(s - post_arrival_pos)

	var pitch: float = u.rank_pitch_wu()
	var step_vec: Vector2 = u.facing * pitch
	var file_ids: PackedInt32Array = u._sim_soldier_file

	# Count soldiers per file and pick the full-depth file with 14 soldiers
	var file_counts: Dictionary = {}
	for fid in file_ids:
		file_counts[fid] = file_counts.get(fid, 0) + 1

	var full_depth_file: int = -1
	for fid in file_counts:
		if file_counts[fid] == 14:
			full_depth_file = fid
			break
	assert_ne(full_depth_file, -1, "found a full-depth file with 14 soldiers")

	var still_count: int = 0
	var stepped_count: int = 0

	for i in range(u.soldiers):
		var file_id: int = file_ids[i]
		var pre_rel: Vector2 = pre_offsets[i]
		var post_rel: Vector2 = post_offsets[i]
		if file_id == full_depth_file:
			still_count += 1
			assert_almost_eq(post_rel.x, pre_rel.x, 0.05,
				"soldier %d in full-depth file has zero relative x displacement" % i)
			assert_almost_eq(post_rel.y, pre_rel.y, 0.05,
				"soldier %d in full-depth file has zero relative y displacement" % i)
		else:
			stepped_count += 1
			var expected_rel: Vector2 = pre_rel + step_vec
			assert_almost_eq(post_rel.x, expected_rel.x, 0.05,
				"soldier %d in short file matches expected stepped relative x" % i)
			assert_almost_eq(post_rel.y, expected_rel.y, 0.05,
				"soldier %d in short file matches expected stepped relative y" % i)

	assert_eq(still_count, 14, "14 full-depth file soldiers hold ground")
	assert_eq(stepped_count, 26, "26 short-file soldiers step one pitch forward")


# --- Battle-level integration ------------------------------------------------

func _unit(uid: int, pos: Vector2) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = uid
	u.position = pos
	u.max_soldiers = 60
	u.facing = FACING_DOWN
	u.seed_sim_soldiers()
	# No reform hold to step through -- these tests are about the wheel-turn
	# classification, not the reform-before-move hold (reform_before_move is a per-unit
	# field now, defaulting true, unlike the raw cmd dict this file used to rely on
	# defaulting to reform:false when the key was simply omitted).
	u.reform_before_move = false
	return u


func _battle(units: Array) -> Node:
	var b = BattleScript.new()
	autofree(b)
	for u in units:
		b._by_uid[u.uid] = u
	return b


func test_oblique_rear_move_arms_a_wheel_turn_composite() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	var dest: Vector2 = FACING_DOWN.rotated(deg_to_rad(140.0)) * 200.0
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1})
	assert_true(u.is_order_turning(), "the about-face armed")
	assert_false(u.has_move_target, "the march is parked until the whole composite completes")
	assert_eq(u.current_order.children.size(), 3,
		"about-face, wheel, and march -- three phases, not the plain rear move's two")
	assert_eq(u.current_order.children[1].type, Order.Type.WHEEL,
		"the middle phase is the flank pivot")
	assert_false(u.current_order.reform,
		"a wheel-turn never reforms before marching -- it reforms on arrival instead")


func test_straight_rear_move_does_not_arm_a_wheel_turn() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})   # straight behind
	assert_true(u.is_order_turning(), "still an about-face")
	assert_eq(u.current_order.children.size(), 2,
		"the plain two-phase about-face+march composite, not the three-phase wheel-turn")


func test_near_straight_rear_move_does_not_arm_a_wheel_turn() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	# 160° off facing: still a rear move, but too little residual for the extra wheel phase.
	var dest: Vector2 = FACING_DOWN.rotated(deg_to_rad(160.0)) * 200.0
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1})
	assert_true(u.is_order_turning(), "still an about-face")
	assert_eq(u.current_order.children.size(), 2,
		"the plain about-face+march composite, not the three-phase wheel-turn")


func test_fighting_unit_does_not_arm_a_wheel_turn() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.state = UnitScript.State.FIGHTING
	var b := _battle([u])
	var dest: Vector2 = FACING_DOWN.rotated(deg_to_rad(140.0)) * 200.0
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1})
	assert_false(u.is_order_turning(), "a fighting unit can't turn in place -- plain march instead")
	assert_true(u.has_move_target, "and marches immediately instead")


func _make_cavalry_80(pos: Vector2 = Vector2.ZERO) -> Unit:
	var u: Unit = UnitScript.new()
	u.is_cavalry = true
	u.max_soldiers = 80
	u.soldiers = 80
	u.position = pos
	u.facing = Vector2.UP
	u.file_pitch = 20.0
	u.rank_pitch = 60.0
	u.walk_speed = 34.0
	u.jog_speed = 70.0
	u.move_speed = 170.0
	u.accel = 40.0
	u.decel = 40.0
	add_child_autofree(u)
	u.seed_sim_soldiers()
	return u


func test_deep_cavalry_formed_pivot_rate_bounded_for_tracking() -> void:
	var u := _make_cavalry_80(Vector2(800, 800))
	assert_almost_eq(u._pivot_radius(), 505.9644, 0.01,
		"80-mount cavalry block has 505.96 wu pivot radius")
	var start_facing: Vector2 = u.facing
	var delta: float = 0.016
	u._move_to(u.position + Vector2(1000, 0), delta, true)
	var facing_step: float = absf(angle_difference(start_facing.angle(), u.facing.angle()))
	var measured_rate: float = facing_step / delta
	var max_expected_rate: float = u.formed_turn_tracking_frac * u.jog_speed / u._pivot_radius()
	assert_lte(measured_rate, max_expected_rate + 0.001,
		"pivot rate must be bounded by formed_turn_tracking_frac (<= 0.083 rad/s)")


func test_deep_cavalry_formed_turn_maintains_cohesion() -> void:
	# Cohesion thresholds guard against regression (min NND >= 10 wu, residual <= 20 wu).
	var u := _make_cavalry_80(Vector2(807.6, 580.8))
	u.facing = Vector2(-0.03, -1.0).normalized()
	var target := Vector2(573.7, 446.5)
	u.move_target = target
	u.has_move_target = true
	u._current_speed = 34.0
	u._approach_velocity = u.facing * 34.0
	u.state = UnitScript.State.MOVING

	var delta: float = 0.016
	var worst_residual: float = 0.0
	var worst_min_nnd: float = INF
	var n: int = u.soldiers
	for _tick in range(180):
		u._physics_process(delta)
		SoldierBodies.step(u, delta)
		# kabsch_fit is typed to accept plain Arrays; soldier_world_slots and
		# _sim_soldier_pos return PackedVector2Array, so convert once and reuse the
		# converted Arrays for the nearest-neighbour loop below too.
		var pos: Array = Array(u._sim_soldier_pos)
		var slots: Array = Array(u.soldier_world_slots(n))
		var fit: Dictionary = DemoDefects.kabsch_fit(slots, pos)
		if fit["residual_rms"] > worst_residual:
			worst_residual = fit["residual_rms"]
		# Each pair once, on squared distances; one sqrt per body at the end.
		var best_d_sq: PackedFloat32Array = PackedFloat32Array()
		best_d_sq.resize(n)
		best_d_sq.fill(INF)
		for i in range(n):
			var p_i: Vector2 = pos[i]
			for j in range(i + 1, n):
				var d_sq: float = p_i.distance_squared_to(pos[j])
				if d_sq < best_d_sq[i]:
					best_d_sq[i] = d_sq
				if d_sq < best_d_sq[j]:
					best_d_sq[j] = d_sq
		for i in range(n):
			var best_d: float = sqrt(best_d_sq[i])
			if best_d < worst_min_nnd:
				worst_min_nnd = best_d

	# 10 wu floor is twice the 5 wu cavalry overlap floor (pre-change clip measured 3.5 wu).
	assert_gte(worst_min_nnd, 10.0,
		"minimum nearest-neighbour distance must stay >= 10.0 wu through the turn")
	# 20 wu tightens against pre-change residual 25.5 wu (clip 56 wu) with margin under analyzer 30 wu floor.
	assert_lte(worst_residual, 20.0,
		"shape residual RMS must stay <= 20.0 wu through the turn")
