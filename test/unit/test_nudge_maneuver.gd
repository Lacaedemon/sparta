extends GutTest
## Arrow-key nudge maneuvers: Left / Right side-step, Down back-step, and Up
## forward-step a small fixed distance while holding facing. Two layers: the pure
## Battle.nudge_offset geometry (no SceneTree), and a live battle stepped tick by
## tick to confirm the selection actually shifts laterally / backward / forward and
## keeps its facing.

const BattleScript = preload("res://scripts/Battle.gd")


# --- pure geometry ---------------------------------------------------------

func test_left_and_right_offsets_are_lateral_and_opposite() -> void:
	# Facing UP (0,-1): the unit's right side is world +x, left is -x.
	var left: Vector2 = BattleScript.nudge_offset(Vector2.UP, BattleScript.NudgeDir.LEFT)
	var right: Vector2 = BattleScript.nudge_offset(Vector2.UP, BattleScript.NudgeDir.RIGHT)
	assert_almost_eq(left.x, -BattleScript.NUDGE_DISTANCE, 0.001, "left is world -x when facing up")
	assert_almost_eq(left.y, 0.0, 0.001, "left has no forward/back component")
	assert_almost_eq(right.x, BattleScript.NUDGE_DISTANCE, 0.001, "right is world +x when facing up")
	assert_almost_eq(right.y, 0.0, 0.001, "right has no forward/back component")


func test_back_offset_is_opposite_facing() -> void:
	# Facing UP (0,-1): back is straight down (+y).
	var back: Vector2 = BattleScript.nudge_offset(Vector2.UP, BattleScript.NudgeDir.BACK)
	assert_almost_eq(back.x, 0.0, 0.001, "back has no lateral component")
	assert_almost_eq(back.y, BattleScript.NUDGE_DISTANCE, 0.001, "back steps directly away from facing")


func test_forward_offset_is_along_facing() -> void:
	# Facing UP (0,-1): forward is straight up (-y).
	var fwd_off: Vector2 = BattleScript.nudge_offset(Vector2.UP, BattleScript.NudgeDir.FORWARD)
	assert_almost_eq(fwd_off.x, 0.0, 0.001, "forward has no lateral component")
	assert_almost_eq(fwd_off.y, -BattleScript.NUDGE_DISTANCE, 0.001, "forward steps directly along facing")


func test_offsets_are_fixed_length_and_relative_to_facing() -> void:
	# A different heading rotates the whole basis: facing RIGHT (1,0) -> back is -x.
	var back: Vector2 = BattleScript.nudge_offset(Vector2.RIGHT, BattleScript.NudgeDir.BACK)
	assert_almost_eq(back.x, -BattleScript.NUDGE_DISTANCE, 0.001, "back is -x when facing right")
	assert_almost_eq(back.y, 0.0, 0.001, "...with no lateral component")
	# Forward and back are exact opposites, whatever the heading.
	var fwd_off: Vector2 = BattleScript.nudge_offset(Vector2.RIGHT, BattleScript.NudgeDir.FORWARD)
	assert_almost_eq(fwd_off.x, BattleScript.NUDGE_DISTANCE, 0.001, "forward is +x when facing right")
	assert_true(fwd_off.is_equal_approx(-back), "forward is the exact opposite of back")
	# Every nudge is the same fixed distance, whatever the direction.
	for d in [BattleScript.NudgeDir.LEFT, BattleScript.NudgeDir.RIGHT,
			BattleScript.NudgeDir.BACK, BattleScript.NudgeDir.FORWARD]:
		var off: Vector2 = BattleScript.nudge_offset(Vector2.RIGHT, d)
		assert_almost_eq(off.length(), BattleScript.NUDGE_DISTANCE, 0.001,
			"a nudge is a fixed small distance")


func test_nudge_distance_stays_within_the_sidestep_ceiling() -> void:
	# Design guard on NUDGE_DISTANCE. The nudge bypasses UnitManeuver.is_sidestep()
	# entirely -- _apply_order_cmd sets ordered_facing directly -- but the distance
	# should stay small enough that it *would* read as a side-step if it ever went
	# through the classifier, so bumping it past the cap trips this test.
	assert_lt(BattleScript.NUDGE_DISTANCE, UnitManeuver.SIDESTEP_MAX_DISTANCE,
		"a lateral nudge is short enough to read as a side-step")


# --- live battle -----------------------------------------------------------

func _team0_unit_near(target: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0 and unit.state != Unit.State.DEAD:
			var d: float = unit.position.distance_to(target)
			if d < best_d:
				best_d = d
				best = unit
	return best


func test_left_nudge_shifts_laterally_and_holds_facing() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true   # rehearse in isolation; no enemy to pull the unit into a fight
	add_child_autofree(battle)
	for _k in range(40):
		await get_tree().physics_frame
	var u: Unit = _team0_unit_near(Vector2(650, 300))
	assert_not_null(u, "found a team-0 unit to nudge")
	if u == null:
		return
	var start_pos: Vector2 = u.position
	var start_facing: Vector2 = u.facing
	var fwd: Vector2 = start_facing.normalized()
	var perp := Vector2(-fwd.y, fwd.x)   # unit's right-hand side

	battle.enqueue_nudge([u.uid], BattleScript.NudgeDir.LEFT)
	assert_not_null(u.current_order, "the nudge occupies the orders queue")
	assert_eq(u.current_order.type, Order.Type.NUDGE,
		"and the queue reports it (transcript-visible)")
	# Budget from sim constants: the order-response delay, the step at no worse than half
	# walk pace (a side-step walks), and a settle margin.
	var budget: int = int(ceil((u.order_response_delay
			+ BattleScript.NUDGE_DISTANCE / maxf(u.walk_speed * 0.5, 1.0) + 1.0)
			* Replay.PHYSICS_TPS))
	for _i in range(budget):
		await get_tree().physics_frame
		if u.current_order == null:
			break

	var moved: Vector2 = u.position - start_pos
	var lateral: float = moved.dot(perp)    # to the unit's right (negative = left)
	var forward: float = moved.dot(fwd)
	assert_lt(lateral, -5.0, "a left nudge shifts the unit to its left")
	# The under-travel regression guard, by exact state: the step covers the FULL drill distance
	# (the arrival finalizes within its 5 px threshold), not the few-pixel creep the
	# double-apply produced.
	assert_almost_eq(absf(lateral), BattleScript.NUDGE_DISTANCE, 6.0,
		"the nudge translates the unit by the full NUDGE_DISTANCE")
	assert_null(u.current_order, "the nudge order retired on arrival")
	assert_lt(absf(forward), absf(lateral), "the shift is mainly lateral, not forward")
	assert_true(u.facing.is_equal_approx(start_facing),
		"a side-step holds facing — the unit does not pivot to face travel")


func test_down_nudge_steps_back_and_holds_facing() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	add_child_autofree(battle)
	for _k in range(40):
		await get_tree().physics_frame
	var u: Unit = _team0_unit_near(Vector2(650, 300))
	assert_not_null(u, "found a team-0 unit to nudge")
	if u == null:
		return
	var start_pos: Vector2 = u.position
	var start_facing: Vector2 = u.facing
	var fwd: Vector2 = start_facing.normalized()

	battle.enqueue_nudge([u.uid], BattleScript.NudgeDir.BACK)
	for _i in range(120):   # the order-response delay (~0.5 s) + the short walk + settle
		await get_tree().physics_frame

	var moved: Vector2 = u.position - start_pos
	var forward: float = moved.dot(fwd)   # negative = backward
	assert_lt(forward, -5.0, "a down nudge steps the unit backward")
	assert_true(u.facing.is_equal_approx(start_facing),
		"a back-step holds facing — the unit does not turn around")


func test_up_nudge_steps_forward_and_holds_facing() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	add_child_autofree(battle)
	for _k in range(40):
		await get_tree().physics_frame
	var u: Unit = _team0_unit_near(Vector2(650, 300))
	assert_not_null(u, "found a team-0 unit to nudge")
	if u == null:
		return
	var start_pos: Vector2 = u.position
	var start_facing: Vector2 = u.facing
	var fwd: Vector2 = start_facing.normalized()

	battle.enqueue_nudge([u.uid], BattleScript.NudgeDir.FORWARD)
	for _i in range(120):   # the order-response delay (~0.5 s) + the short walk + settle
		await get_tree().physics_frame

	var moved: Vector2 = u.position - start_pos
	var forward: float = moved.dot(fwd)   # positive = forward
	assert_gt(forward, 5.0, "an up nudge steps the unit forward")
	assert_true(u.facing.is_equal_approx(start_facing),
		"a forward-step holds facing — the unit does not turn to face travel")
