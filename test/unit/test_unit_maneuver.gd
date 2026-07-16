extends GutTest
## UnitManeuver.is_sidestep: the pure classifier that decides whether a move
## order is a small lateral shift (shuffle sideways, hold facing) or a normal
## turn-and-march. Stateless, so these run without a SceneTree.

const Maneuver = preload("res://scripts/UnitManeuver.gd")

# Facing right (+x); "lateral" is then the +/-y axis, "forward" the +/-x axis.
const FACING_RIGHT := Vector2.RIGHT


func test_small_pure_lateral_move_is_a_sidestep() -> void:
	assert_true(Maneuver.is_sidestep(FACING_RIGHT, Vector2(0, -20)),
		"a short sideways shift holds facing and side-steps")
	assert_true(Maneuver.is_sidestep(FACING_RIGHT, Vector2(0, 20)),
		"either lateral direction side-steps")


func test_forward_move_is_not_a_sidestep() -> void:
	assert_false(Maneuver.is_sidestep(FACING_RIGHT, Vector2(20, 0)),
		"marching straight ahead turns to face travel, not a side-step")


func test_diagonal_move_is_not_a_sidestep() -> void:
	assert_false(Maneuver.is_sidestep(FACING_RIGHT, Vector2(15, -15)),
		"a 45-degree move is an advance, not a sideways shift")


func test_lateral_move_with_slight_forward_lean_still_side_steps() -> void:
	# lateral 30 vs forward 5 -> ratio 6 >= 2, and length < max
	assert_true(Maneuver.is_sidestep(FACING_RIGHT, Vector2(5, -30)),
		"a mostly-sideways shift with a small forward lean still side-steps")


func test_large_lateral_move_is_not_a_sidestep() -> void:
	assert_false(Maneuver.is_sidestep(FACING_RIGHT, Vector2(0, -100)),
		"a large lateral move is a file-march pivot (future work), not a shuffle")


func test_threshold_distance_is_the_boundary() -> void:
	var just_under := Maneuver.SIDESTEP_MAX_DISTANCE - 1.0
	var just_over := Maneuver.SIDESTEP_MAX_DISTANCE + 1.0
	assert_true(Maneuver.is_sidestep(FACING_RIGHT, Vector2(0, -just_under)),
		"a lateral shift just inside the distance cap side-steps")
	assert_false(Maneuver.is_sidestep(FACING_RIGHT, Vector2(0, -just_over)),
		"...and just outside it does not")


func test_degenerate_inputs_are_not_a_sidestep() -> void:
	assert_false(Maneuver.is_sidestep(Vector2.ZERO, Vector2(0, -10)),
		"no facing -> no side-step")
	assert_false(Maneuver.is_sidestep(FACING_RIGHT, Vector2.ZERO),
		"a zero-length move -> no side-step (re-click on the spot)")


func test_sidestep_is_relative_to_facing() -> void:
	# Facing DOWN (+y): now the +/-x axis is lateral. A move along +x side-steps.
	assert_true(Maneuver.is_sidestep(Vector2.DOWN, Vector2(20, 0)),
		"lateral is perpendicular to facing, whatever the heading")
	assert_false(Maneuver.is_sidestep(Vector2.DOWN, Vector2(0, 20)),
		"...and a move along facing is a forward advance")


func test_wheel_gait_rate_is_bounded_by_the_outer_file() -> void:
	# A wide block: the outer man at radius 100 jogging 36 wu/s can sustain only
	# 0.36 rad/s -- well under the PI/2 drill ceiling, so the gait binds.
	assert_almost_eq(Maneuver.wheel_gait_rate(PI * 0.5, 36.0, 100.0), 0.36, 0.0001,
		"a wide block's swing rate is its outer file's jog over its radius")


func test_wheel_gait_rate_keeps_the_drill_ceiling_for_a_narrow_block() -> void:
	# A narrow block: the outer man at radius 10 could jog 3.6 rad/s, but the drill
	# ceiling (PI/2) governs -- a small block still swings at the stately drill pace.
	assert_almost_eq(Maneuver.wheel_gait_rate(PI * 0.5, 36.0, 10.0), PI * 0.5, 0.0001,
		"a narrow block swings at the drill ceiling, not a whip-around")


func test_wheel_gait_rate_degenerate_radius_falls_back_to_the_ceiling() -> void:
	assert_almost_eq(Maneuver.wheel_gait_rate(PI * 0.5, 36.0, 0.0), PI * 0.5, 0.0001,
		"a lone man standing on the hinge has no pacing file -- the ceiling governs")
	assert_almost_eq(Maneuver.wheel_gait_rate(PI * 0.5, 36.0, -1.0), PI * 0.5, 0.0001,
		"a negative radius is degenerate input, not a division")
