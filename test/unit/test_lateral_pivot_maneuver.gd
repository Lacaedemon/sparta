extends GutTest
## A LARGE lateral move order should quarter-turn the unit toward the destination's
## side in place, widen back into a line facing it, then march -- NOT centre-pivot
## the whole block onto the new bearing while already under way, and NOT shuffle
## sideways (that's the SHORT case, is_sidestep/test_unit_maneuver.gd). Three
## layers: the pure UnitManeuver.is_lateral_pivot/lateral_pivot_dir classifiers (no
## SceneTree), a unit-level integration stepping _think tick by tick through the
## turn -> reform -> march phases, and a Battle-level integration confirming
## _apply_order_cmd picks this path over the sibling maneuvers.

const Maneuver = preload("res://scripts/UnitManeuver.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")

const FACING_DOWN := Vector2.DOWN


# --- pure classifiers -------------------------------------------------------

func test_large_flank_move_is_a_lateral_pivot() -> void:
	assert_true(Maneuver.is_lateral_pivot(FACING_DOWN, Vector2(200, 0)),
		"a large pure-lateral destination is a lateral pivot")


func test_small_flank_move_is_not_a_lateral_pivot() -> void:
	assert_false(Maneuver.is_lateral_pivot(FACING_DOWN, Vector2(20, 0)),
		"a short lateral move side-steps instead (see test_unit_maneuver.gd)")


func test_forward_move_is_not_a_lateral_pivot() -> void:
	assert_false(Maneuver.is_lateral_pivot(FACING_DOWN, Vector2(0, 200)),
		"marching straight ahead is not a lateral pivot")


func test_rear_move_is_not_a_lateral_pivot() -> void:
	assert_false(Maneuver.is_lateral_pivot(FACING_DOWN, Vector2(0, -200)),
		"a move straight behind is a rear move (about-face), not a lateral pivot")


func test_threshold_distance_is_the_boundary() -> void:
	var flank := Vector2.RIGHT
	var just_under := flank * (Maneuver.SIDESTEP_MAX_DISTANCE - 1.0)
	var just_over := flank * (Maneuver.SIDESTEP_MAX_DISTANCE + 1.0)
	assert_false(Maneuver.is_lateral_pivot(FACING_DOWN, just_under),
		"a lateral move just inside the distance cap side-steps instead")
	assert_true(Maneuver.is_lateral_pivot(FACING_DOWN, just_over),
		"...and just outside it is a lateral pivot")


func test_degenerate_inputs_are_not_a_lateral_pivot() -> void:
	assert_false(Maneuver.is_lateral_pivot(Vector2.ZERO, Vector2(200, 0)),
		"no facing -> no lateral pivot")
	assert_false(Maneuver.is_lateral_pivot(FACING_DOWN, Vector2.ZERO),
		"a zero-length move -> no lateral pivot")


func test_lateral_pivot_dir_turns_toward_the_destinations_side() -> void:
	# facing DOWN: quarter_turn's own dir=+1 rotates facing.rotated(PI/2), which for
	# DOWN=(0,1) lands on (-1,0) -- i.e. dir=+1 is the unit's own right, toward -x.
	assert_eq(Maneuver.lateral_pivot_dir(FACING_DOWN, Vector2(-200, 0)), 1,
		"a destination on the unit's right (-x, facing DOWN) turns dir=+1")
	assert_eq(Maneuver.lateral_pivot_dir(FACING_DOWN, Vector2(200, 0)), -1,
		"a destination on the unit's left (+x, facing DOWN) turns dir=-1")


# --- unit-level integration --------------------------------------------------

func _make_seeded_unit() -> Unit:
	var u: Unit = UnitScript.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = FACING_DOWN
	u.seed_sim_soldiers()
	return u


## Arm a lateral-pivot composite exactly as Battle._apply_order_cmd does: a MOVE
## order with reform forced on, and a signed quarter-turn TURN phase armed on it.
func _arm_lateral_pivot(u: Unit, dest: Vector2) -> Order:
	var o := Order.new_move(dest)
	o.reform = true
	u.set_current_order(o)
	u.has_move_target = false
	var angle: float = PI * 0.5 * Maneuver.lateral_pivot_dir(u.facing, dest - u.position)
	assert_true(u.begin_pivot(o, angle), "the quarter-turn armed (bodies were seeded)")
	return o


func test_lateral_pivot_turns_90_degrees_then_reforms_then_marches() -> void:
	var u := _make_seeded_unit()
	var start_facing: Vector2 = u.facing   # DOWN
	var dest := Vector2(-200, 0)           # due right of a DOWN-facing unit (see dir test above)
	var o := _arm_lateral_pivot(u, dest)

	# While the turn runs, the unit must NOT be marching yet, and must read as a
	# QUARTER_TURN (not a CONVERSIO -- the about_face_goal fix this maneuver needs).
	u._think(0.016)
	assert_false(u.has_move_target, "no march starts until the turn completes")
	assert_eq(u.position, Vector2.ZERO, "the block does not translate during the turn")
	assert_eq(u.current_maneuver(), UnitScript.Maneuver.QUARTER_TURN,
		"a 90-degree turn reads as QUARTER_TURN, not CONVERSIO")
	assert_eq(u.about_face_goal(), Vector2.ZERO,
		"a 90-degree turn is not an about-face reversal for render/reporting purposes")

	# Step through the turn to completion.
	var turned := false
	for _i in range(120):
		u._think(0.016)
		if not u.is_order_turning():
			turned = true
			break
	assert_true(turned, "the quarter-turn completes")
	assert_true(u.facing.is_equal_approx(start_facing.rotated(PI * 0.5)),
		"the unit ends facing 90 degrees from its start heading, not reversed 180")
	assert_eq(o.phase, Order.Phase.REFORM,
		"the composite advances into its reform phase -- widening back into a line is not optional")
	assert_false(u.has_move_target, "still not marching -- the reform hold is in progress")

	# Step through the reform (bodies settle onto the re-squared slots) to the march.
	var marching := false
	for _i in range(600):
		u._think(0.016)
		if u.has_move_target:
			marching = true
			break
	assert_true(marching, "the parked march commits once the reform settles")
	assert_eq(u.move_target, dest, "it marches to the parked lateral destination")
	assert_eq(o.phase, Order.Phase.MARCH, "the composite advanced to its march phase")
	assert_almost_eq(wrapf(u._formation_angle, -PI, PI), 0.0, 0.01,
		"the grid re-squared to the new heading -- the turned offset was folded away, not left standing")


func test_lateral_pivot_marches_toward_the_destination_after_reforming() -> void:
	var u := _make_seeded_unit()
	var dest := Vector2(-200, 0)
	_arm_lateral_pivot(u, dest)
	# Run well past the turn and reform so the march is underway.
	for _i in range(700):
		u._think(0.016)
	assert_lt(u.position.x, 0.0,
		"the unit advances toward the lateral destination (its x decreases toward -200)")


# --- Battle-level integration ------------------------------------------------

func _unit(uid: int, pos: Vector2) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = uid
	u.position = pos
	u.max_soldiers = 60
	u.seed_sim_soldiers()
	return u


func _battle(units: Array) -> Node:
	var b = BattleScript.new()
	autofree(b)
	for u in units:
		b._by_uid[u.uid] = u
	return b


func test_large_lateral_move_arms_a_lateral_pivot() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = FACING_DOWN
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": -200.0, "y": 0.0, "target": -1})
	assert_true(u.is_order_turning(), "a large lateral move arms an in-place turn")
	assert_false(u.has_move_target, "the march is parked until the turn (and reform) complete")
	assert_eq(u.current_maneuver(), UnitScript.Maneuver.QUARTER_TURN,
		"Battle-level dispatch also reads as a quarter-turn, not a centre-pivot or about-face")


func test_small_lateral_move_does_not_arm_a_lateral_pivot() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = FACING_DOWN
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": -20.0, "y": 0.0, "target": -1})
	assert_false(u.is_order_turning(), "a short lateral move side-steps instead of turning")


func test_forward_move_does_not_arm_a_lateral_pivot() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = FACING_DOWN
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 200.0, "target": -1})
	assert_false(u.is_order_turning(), "marching straight ahead never arms a lateral pivot")


func test_fighting_unit_does_not_arm_a_lateral_pivot() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = FACING_DOWN
	u.state = UnitScript.State.FIGHTING
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": -200.0, "y": 0.0, "target": -1})
	assert_false(u.is_order_turning(),
		"a fighting unit can't turn in place -- it falls back to a plain march")
	assert_true(u.has_move_target, "and marches immediately instead")
