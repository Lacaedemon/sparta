extends GutTest
## A LARGE lateral move order is a file march: the unit quarter-turns toward the
## destination's side in place, marches sideways to it KEEPING its pre-turn footprint
## (no reform -- the grid's rank/file axis stays fixed relative to the block, only the
## direction of travel and the soldiers' own facing change), then quarter-turns back to
## its original facing once it arrives. NOT a centre-pivot that repoints the whole block
## onto the new bearing permanently, and NOT a shuffle sideways (that's the SHORT case,
## is_sidestep/test_unit_maneuver.gd). Three layers: the pure
## UnitManeuver.is_lateral_pivot/lateral_pivot_dir classifiers (no SceneTree), a
## unit-level integration stepping _think tick by tick through the
## turn -> march -> return-turn phases, and a Battle-level integration confirming
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


## Arm a lateral-pivot composite exactly as Battle._apply_order_cmd does: a MOVE order
## with reform forced OFF, a signed quarter-turn TURN phase armed on it, and the return
## leg (the negated turn angle) recorded for the arrival handler to consume.
func _arm_lateral_pivot(u: Unit, dest: Vector2) -> Order:
	var o := Order.new_move(dest)
	o.reform = false
	u.set_current_order(o)
	u.has_move_target = false
	var angle: float = PI * 0.5 * Maneuver.lateral_pivot_dir(u.facing, dest - u.position)
	assert_true(u.begin_pivot(o, angle), "the quarter-turn armed (bodies were seeded)")
	o.pivot_return_angle = -angle
	return o


func test_lateral_pivot_turns_90_degrees_then_marches_keeping_its_shape() -> void:
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

	# Step through the turn to completion. _finish_order_turn runs synchronously the tick
	# the turn settles, so has_move_target/phase are already updated once the loop below
	# observes is_order_turning() go false.
	var turned := false
	for _i in range(120):
		u._think(0.016)
		if not u.is_order_turning():
			turned = true
			break
	assert_true(turned, "the quarter-turn completes")
	assert_true(u.facing.is_equal_approx(start_facing.rotated(PI * 0.5)),
		"the unit ends facing 90 degrees from its start heading, not reversed 180")
	assert_eq(o.effective_phase_name(), "MARCH",
		"the march starts the instant the turn settles -- no reform hold in between")
	assert_true(u.has_move_target, "the march is already committed")
	assert_eq(u.move_target, dest, "it marches straight to the lateral destination")
	assert_ne(wrapf(u._formation_angle, -PI, PI), 0.0,
		"the turned offset stays folded into _formation_angle -- the grid keeps its " +
		"pre-turn footprint instead of re-squaring to the new heading")

	# Step a bit further into the march and confirm the fold hasn't been disturbed: no
	# reform kicks in partway through, so the footprint stays exactly as it was.
	var angle_mid_turn: float = wrapf(u._formation_angle, -PI, PI)
	for _i in range(30):
		u._think(0.016)
	assert_almost_eq(wrapf(u._formation_angle, -PI, PI), angle_mid_turn, 0.001,
		"the footprint fold is unchanged mid-march -- nothing reforms the grid along the way")


func test_lateral_pivot_marches_toward_the_destination_keeping_its_facing() -> void:
	var u := _make_seeded_unit()
	var dest := Vector2(-200, 0)
	_arm_lateral_pivot(u, dest)
	var start_facing: Vector2 = u.facing
	# Run past the turn so the march is underway, but well short of arrival.
	for _i in range(150):
		u._think(0.016)
	assert_lt(u.position.x, 0.0,
		"the unit advances toward the lateral destination (its x decreases toward -200)")
	assert_true(u.facing.is_equal_approx(start_facing.rotated(PI * 0.5)),
		"mid-march the unit still faces the pivoted (travel) direction -- the return " +
		"turn hasn't started yet")


func test_lateral_pivot_turns_back_to_its_original_facing_on_arrival() -> void:
	var u := _make_seeded_unit()
	var start_facing: Vector2 = u.facing
	var dest := Vector2(-200, 0)
	var o := _arm_lateral_pivot(u, dest)

	# Run well past the turn and the march so the unit arrives at its destination.
	var arrived := false
	for _i in range(1200):
		u._think(0.016)
		if o.effective_phase_name() == "RETURN_TURN":
			arrived = true
			break
	assert_true(arrived, "the march completes and the return leg arms")
	assert_true(u.is_order_turning(), "the return leg is a fresh in-place turn")
	assert_false(u.has_move_target, "marching is done -- only the return turn remains")

	# Step through the return turn to completion.
	var turned_back := false
	for _i in range(120):
		u._think(0.016)
		if not u.is_order_turning():
			turned_back = true
			break
	assert_true(turned_back, "the return turn completes")
	assert_true(u.facing.is_equal_approx(start_facing),
		"the unit ends up facing exactly the way it started -- the whole point of the " +
		"maneuver is that it's a temporary reorientation, not a permanent one")
	assert_almost_eq(wrapf(u._formation_angle, -PI, PI), 0.0, 0.01,
		"the outbound and return turns cancel out -- the grid reads as fully square to " +
		"the (restored) facing again, with no fold left standing")
	assert_null(u.current_order,
		"the whole composite (turn, march, return turn) retires as one order once the " +
		"return turn settles")


func test_lateral_pivot_retires_correctly_when_grouped_under_a_shared_parent() -> void:
	# docs/atomic-order-decomposition-design.md: a multi-unit form-up's per-unit order
	# points `parent` at a shared FORM_UP group tag (Battle._apply_order_cmd). That group
	# order is never this unit's own current_order and its `_active_child` means nothing
	# (the group's per-unit orders run concurrently, not in sequence) -- so completing the
	# WHOLE composite (not just an intra-composite handoff) must still retire this unit's
	# own current_order to null, the same as an ungrouped lateral pivot does, instead of
	# the cascade climbing into the group order and silently swallowing the retirement
	# (see Unit._advance_order_tree's `node != current_order` stop condition).
	var u := _make_seeded_unit()
	var dest := Vector2(-200, 0)
	var o := _arm_lateral_pivot(u, dest)
	var group := Order.new_form_up()
	group.children = [o]
	o.parent = group

	var arrived := false
	for _i in range(1200):
		u._think(0.016)
		if o.effective_phase_name() == "RETURN_TURN":
			arrived = true
			break
	assert_true(arrived, "the march completes and the return leg arms, same as ungrouped")

	var turned_back := false
	for _i in range(120):
		u._think(0.016)
		if not u.is_order_turning():
			turned_back = true
			break
	assert_true(turned_back, "the return turn completes")
	assert_null(u.current_order,
			"the whole composite retires exactly as it would with no group parent at all -- " +
			"the cascade must not get stuck climbing into the shared group order")


func test_single_rank_unit_still_completes_a_lateral_pivot() -> void:
	# A lateral pivot never calls reform_ranks() (the maneuver keeps its footprint the
	# whole way through -- see test_reform_ranks.gd for that primitive's own single-rank
	# coverage), so this just confirms a single-rank line completes the whole
	# turn/march/return-turn composite the same as any other shape -- nothing about
	# is_order_turning() or the turn machinery singles out a one-rank grid.
	var u := UnitScript.new()
	u.max_soldiers = 8
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = FACING_DOWN
	u.frontage_override = 8   # force exactly one rank
	u.seed_sim_soldiers()
	var start_facing: Vector2 = u.facing
	var dest := Vector2(-200, 0)
	var o := _arm_lateral_pivot(u, dest)

	for _i in range(120):
		u._think(0.016)
		if not u.is_order_turning():
			break
	assert_false(u.is_order_turning(), "the quarter-turn completes even for a single-rank line")
	assert_eq(o.effective_phase_name(), "MARCH", "the march starts immediately, same as any other shape")

	for _i in range(600):
		u._think(0.016)
		if o.effective_phase_name() == "RETURN_TURN":
			break
	assert_eq(o.effective_phase_name(), "RETURN_TURN", "the single-rank unit still arrives and turns back")

	for _i in range(120):
		u._think(0.016)
		if not u.is_order_turning():
			break
	assert_true(u.facing.is_equal_approx(start_facing),
		"the single-rank unit ends facing its original heading")


# --- Battle-level integration ------------------------------------------------

func _unit(uid: int, pos: Vector2) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = uid
	u.position = pos
	u.max_soldiers = 60
	u.seed_sim_soldiers()
	# No reform hold to step through -- these tests are about the lateral-pivot
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


func test_large_lateral_move_arms_a_lateral_pivot() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = FACING_DOWN
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": -200.0, "y": 0.0, "target": -1})
	assert_true(u.is_order_turning(), "a large lateral move arms an in-place turn")
	assert_false(u.has_move_target, "the march is parked until the turn completes")
	assert_eq(u.current_maneuver(), UnitScript.Maneuver.QUARTER_TURN,
		"Battle-level dispatch also reads as a quarter-turn, not a centre-pivot or about-face")
	assert_false(u.current_order.reform,
		"a lateral pivot never reforms -- it keeps its pre-turn footprint through the march")
	assert_ne(u.current_order.pivot_return_angle, 0.0,
		"the return leg is recorded on the order so the unit turns back on arrival")


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
	assert_eq(u.current_order.pivot_return_angle, 0.0,
		"no return leg is recorded when the turn never armed -- there's nothing to turn back from")


func test_undisciplined_unit_does_not_arm_a_lateral_pivot() -> void:
	# The lateral-pivot maneuver is a formed drill (quarter-turn, file-march, quarter-turn
	# back) -- exactly the kind of professional maneuver an undisciplined unit should skip
	# in favor of turning to face the destination and walking there directly. Before this
	# fix, is_lateral_pivot's dispatch never read Unit.disciplined at all, so an
	# undisciplined unit given a large lateral move got the same formed composite as a
	# disciplined one.
	var u := _unit(1, Vector2.ZERO)
	u.facing = FACING_DOWN
	u.disciplined = false
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": -200.0, "y": 0.0, "target": -1})
	assert_false(u.is_order_turning(),
		"an undisciplined unit never arms the formed quarter-turn -- it falls back to a plain march")
	assert_true(u.has_move_target, "and marches immediately instead")
	assert_eq(u.current_order.pivot_return_angle, 0.0,
		"no return leg is recorded when the turn never armed -- there's nothing to turn back from")


func test_disciplined_unit_still_arms_a_lateral_pivot() -> void:
	# The sibling/contrast case: a disciplined unit given the identical order still takes
	# the formed maneuver -- the new gate only changes the undisciplined branch.
	var u := _unit(1, Vector2.ZERO)
	u.facing = FACING_DOWN
	u.disciplined = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": -200.0, "y": 0.0, "target": -1})
	assert_true(u.is_order_turning(), "a disciplined unit still arms the in-place quarter-turn")
	assert_false(u.has_move_target, "the march is still parked until the turn completes")
