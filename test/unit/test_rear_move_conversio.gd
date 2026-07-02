extends GutTest
## A move order into the unit's REAR sector should about-face (conversio) in place,
## then march to the destination facing it -- NOT pivot the whole block 180° about its
## centre. Two layers: the pure UnitManeuver.is_rear_move classifier (no SceneTree), and
## a unit-level integration that seeds soldier bodies, arms the conversio, and steps
## _think tick by tick, asserting the unit reverses facing and only then starts marching.

const Maneuver = preload("res://scripts/UnitManeuver.gd")

const FACING_RIGHT := Vector2.RIGHT


# --- pure classifier -------------------------------------------------------

func test_move_straight_behind_is_a_rear_move() -> void:
	assert_true(Maneuver.is_rear_move(FACING_RIGHT, Vector2(-100, 0)),
		"a destination directly behind (180°) is a rear move")


func test_move_straight_ahead_is_not_a_rear_move() -> void:
	assert_false(Maneuver.is_rear_move(FACING_RIGHT, Vector2(100, 0)),
		"marching forward is not a rear move")


func test_move_to_the_flank_is_not_a_rear_move() -> void:
	assert_false(Maneuver.is_rear_move(FACING_RIGHT, Vector2(0, 100)),
		"a 90° flank move is not in the rear sector")
	assert_false(Maneuver.is_rear_move(FACING_RIGHT, Vector2(0, -100)),
		"the other flank likewise")


func test_rear_boundary_is_135_degrees() -> void:
	# 140° behind facing -> rear; 130° behind -> not. Build the vectors by rotating
	# the reversed facing a little toward the flank.
	var just_rear := FACING_RIGHT.rotated(deg_to_rad(140.0)) * 100.0
	var just_outside_rear := FACING_RIGHT.rotated(deg_to_rad(130.0)) * 100.0
	assert_true(Maneuver.is_rear_move(FACING_RIGHT, just_rear),
		"140° off facing is inside the rear sector")
	assert_false(Maneuver.is_rear_move(FACING_RIGHT, just_outside_rear),
		"130° off facing is just outside the rear sector (oblique-rear, not rear enough)")


func test_rear_move_is_symmetric_across_facing() -> void:
	# The classifier keys off the absolute angle, so a rear destination reads the same
	# whether it lies behind-left or behind-right.
	assert_true(Maneuver.is_rear_move(FACING_RIGHT, FACING_RIGHT.rotated(deg_to_rad(150.0)) * 80.0),
		"behind and to one side is a rear move")
	assert_true(Maneuver.is_rear_move(FACING_RIGHT, FACING_RIGHT.rotated(deg_to_rad(-150.0)) * 80.0),
		"behind and to the other side is a rear move")


func test_degenerate_inputs_are_not_a_rear_move() -> void:
	assert_false(Maneuver.is_rear_move(Vector2.ZERO, Vector2(-10, 0)),
		"no facing -> no rear move")
	assert_false(Maneuver.is_rear_move(FACING_RIGHT, Vector2.ZERO),
		"a zero-length move -> no rear move")


# --- unit-level integration ------------------------------------------------

func _make_seeded_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()   # populate _sim_soldier_pos / _sim_soldier_facing so conversio can run
	return u


## Arm a rear-move composite exactly as Battle._apply_order_cmd does: a MOVE order (hasty
## variant, no reform phase) made current, with the about-face TURN phase armed on it.
func _arm_rear_move(u: Unit, dest: Vector2) -> Order:
	var o := Order.new_move(dest)
	u.set_current_order(o)
	u.has_move_target = false
	assert_true(u.begin_about_face(o), "the about-face armed (bodies were seeded)")
	return o


func test_rear_move_about_faces_then_marches() -> void:
	var u := _make_seeded_unit()
	var start_facing: Vector2 = u.facing   # DOWN
	var dest := Vector2(0, -200)           # straight behind a DOWN-facing unit
	var o := _arm_rear_move(u, dest)

	# While the about-face is turning, the unit must NOT be marching yet.
	u._think(0.016)
	assert_false(u.has_move_target, "no march starts until the about-face completes")
	assert_eq(u.position, Vector2.ZERO, "the block does not translate during the turn")

	# Step until the conversio finishes and the parked march commits.
	var started := false
	for _i in range(120):
		u._think(0.016)
		if u.has_move_target:
			started = true
			break
	assert_true(started, "the parked march commits once the about-face completes")
	assert_true(u.facing.is_equal_approx(-start_facing),
		"the unit ended facing the reverse of its start heading (about-faced, not pivoted mid-march)")
	assert_eq(u.move_target, dest, "it marches to the parked rear destination")
	assert_eq(o.phase, Order.Phase.MARCH, "the composite advanced to its march phase")


func test_rear_move_marches_toward_the_destination_not_backward() -> void:
	var u := _make_seeded_unit()
	_arm_rear_move(u, Vector2(0, -200))
	# Run well past the turn so the march is underway.
	for _i in range(200):
		u._think(0.016)
	assert_lt(u.position.y, 0.0,
		"the unit advances toward the rear destination (its y decreases toward -200)")
	assert_true(u.facing.y < 0.0,
		"and it faces the way it marches (upward), having about-faced rather than reversing")


func test_about_face_holds_every_soldier_at_its_own_position_through_think() -> void:
	# #541: a prior bug relabelled (reversed) the index-aligned body arrays on completion,
	# so every soldier ended at its MIRROR index's starting position instead of its own --
	# an identity swap invisible to aggregate bbox/centroid checks (the grid is symmetric)
	# but caught by tracking per-soldier position BY ARRAY INDEX across the whole turn, the
	# same method the issue's state-dump proof used. A true conversio holds every soldier's
	# own world position fixed for the entire turn; only facing changes.
	var u := _make_seeded_unit()
	# _make_seeded_unit sets max_soldiers = 60, so frontage_override = 8 gives an 8-file grid
	# with a partial last rank (60 = 7 full ranks of 8 + a 4-man rank) -- not a full grid, but
	# the position-holding assertion below doesn't depend on the grid being full (the full-grid
	# and partial-grid cases are covered explicitly in test_soldier_facing.gd).
	u.frontage_override = 8
	u.seed_sim_soldiers()
	var start_facing: Vector2 = u.facing
	var before: PackedVector2Array = u._sim_soldier_pos.duplicate()
	u.conversio()
	assert_true(u.is_order_turning(), "the conversio armed")
	for _i in range(120):
		u._think(0.016)
		if not u.is_order_turning():
			break
	assert_true(u.facing.is_equal_approx(-start_facing),
		"the about-face completed (facing reversed)")
	for i in range(before.size()):
		assert_true(u._sim_soldier_pos[i].is_equal_approx(before[i]),
			"soldier %d holds its OWN pre-turn position, not its mirror index's" % i)


func test_move_order_cancels_a_pending_rear_march() -> void:
	# A legacy march starting under the turning order (a waypoint append) pre-empts the
	# about-face: the turn settles and the order retires, taking its parked rear march
	# with it.
	var u := _make_seeded_unit()
	var o := _arm_rear_move(u, Vector2(0, -200))
	# Simulate the append-style pre-empt: has_move_target flips true under the turn.
	u.has_move_target = true
	u.move_target = Vector2(300, 0)
	u._think(0.016)
	assert_eq(o.turn_target, Vector2.ZERO, "the interrupting march cancels the about-face")
	assert_null(u.current_order, "and the turning order retired, dropping its parked march")
	assert_eq(u.move_target, Vector2(300, 0), "the pre-empting march is untouched")
