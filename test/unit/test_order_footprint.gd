extends GutTest
## Unit-level move-order validation: a move_target write tests the formation's footprint
## at the destination, in the facing it will hold there, against impassable terrain, and
## pulls an overlapping destination back along the move (or holds position when nothing
## along the move is clear). See Unit.clamp_order_destination and OrderFootprint.

const BattleScript = preload("res://scripts/Battle.gd")
const HILL := Rect2(1150, 380, 250, 200)   # Battle.TERRAIN's default hill

var _old_field: PathField = null


func before_each() -> void:
	_old_field = PathField.active
	var field := PathField.new(Rect2(0, 0, 4000, 4000))
	field.block_rect(HILL)
	PathField.active = field


func after_each() -> void:
	PathField.active = _old_field


## A 3-file x 20-rank Infantry block facing north at `pos`: 36 x 342 wu, so its rear
## ranks reach well past the hill's top edge while its centre stays north of it.
func _make_deep_block(pos: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.frontage_override = 3
	u.facing = Vector2.UP
	u.position = pos
	return u


## Issue the same order Battle's arrow-key nudge does: hold facing, step to the side.
func _nudge(u: Unit, dir: int) -> void:
	u.ordered_facing = u.facing
	u.move_target = u.position + BattleScript.nudge_offset(u.facing, dir)
	u.has_move_target = true


## How many of `u`'s slots would stand inside the hill with the block centred on `at`,
## laid out facing `held`.
func _slots_inside_hill(u: Unit, at: Vector2, held: Vector2) -> int:
	var angle: float = held.angle() + PI * 0.5
	var inside: int = 0
	for s in u.formation_slots(u.soldiers, true):
		if HILL.has_point(at + s.rotated(angle)):
			inside += 1
	return inside


## The farthest-east centre x at which `u`'s footprint, `half_extent` wide (or deep)
## across the move plus its body radius, still clears the hill's west edge.
func _clear_x(u: Unit, half_extent: float) -> float:
	return HILL.position.x - half_extent - u.soldier_body_radius()


func test_side_step_beside_a_hill_is_pulled_back_off_it() -> void:
	# The reported case, one nudge from where it first overlaps: centred at x 1110 the
	# block's footprint is clear of the hill, but a 30 wu side-step to x 1140 would put its
	# right file's rear ranks inside it.
	var u := _make_deep_block(Vector2(1110, 330))
	var raw: Vector2 = u.position + BattleScript.nudge_offset(u.facing, BattleScript.NudgeDir.RIGHT)
	assert_gt(_slots_inside_hill(u, raw, u.facing), 0,
		"sanity check: the unclamped side-step would park men inside the hill")
	_nudge(u, BattleScript.NudgeDir.RIGHT)
	assert_eq(_slots_inside_hill(u, u.move_target, u.ordered_facing), 0,
		"no slot of the footprint at the clamped destination is inside the hill")
	var limit: float = _clear_x(u, u._formation_local_half_extents().x)
	assert_almost_eq(u.move_target.y, 330.0, 0.001, "pulled back along the move, not sideways")
	assert_lte(u.move_target.x, limit, "the footprint's right edge stays at or west of the hill")
	assert_gte(u.move_target.x, limit - OrderFootprint.SEARCH_TOLERANCE,
		"the step still goes as far as the terrain allows, within the search tolerance")


func test_a_clear_destination_is_unchanged() -> void:
	var u := _make_deep_block(Vector2(1080, 330))
	_nudge(u, BattleScript.NudgeDir.RIGHT)
	assert_eq(u.move_target, Vector2(1110, 330), "a side-step whose footprint is clear goes where ordered")


func test_a_move_with_no_clear_point_holds_position() -> void:
	# Already overlapping the hill (the state the unclamped bug left it in), a further
	# side-step into it has no clear point anywhere along the move: hold where it stands.
	var u := _make_deep_block(Vector2(1145, 330))
	_nudge(u, BattleScript.NudgeDir.RIGHT)
	assert_eq(u.move_target, Vector2(1145, 330), "no clear point along the move: the unit holds")


func test_a_far_tier_block_uses_the_far_tier_extents() -> void:
	var u := _make_deep_block(Vector2(1110, 330))
	TierTransition.demote(u)
	var before: int = u._formation_slots_call_count
	_nudge(u, BattleScript.NudgeDir.RIGHT)
	var calls: int = u._formation_slots_call_count - before
	assert_eq(calls, 0, "a far-tier block validates its order without building the slot layout")
	var limit: float = _clear_x(u, u._far_tier_half_extents().x)
	assert_almost_eq(u.move_target.y, 330.0, 0.001, "pulled back along the move")
	assert_lte(u.move_target.x, limit, "the far-tier footprint's right edge stays off the hill")
	assert_gte(u.move_target.x, limit - OrderFootprint.SEARCH_TOLERANCE,
		"pulled back only as far as needed")


func test_search_step_and_tolerance_are_caller_configurable() -> void:
	var u := _make_deep_block(Vector2(1110, 330))
	u.ordered_facing = u.facing
	var limit: float = _clear_x(u, u._formation_local_half_extents().x)
	var coarse: Vector2 = u.clamp_order_destination(Vector2(1140, 330), 30.0, 15.0)
	assert_lte(coarse.x, limit, "a coarse search still lands clear")
	assert_gte(coarse.x, limit - 15.0, "within the coarse tolerance of the clear point")
	assert_lt(coarse.x, limit - OrderFootprint.SEARCH_TOLERANCE,
		"and coarser than the default search, so the arguments were actually used")


func test_a_plain_march_is_validated_in_its_travel_facing() -> void:
	# No held facing: the block will turn to face east as it marches, so its depth runs
	# along x and the destination stops a half-depth (not a half-width) short of the hill.
	var u := _make_deep_block(Vector2(600, 480))
	u.move_target = Vector2(1100, 480)
	var limit: float = _clear_x(u, u._formation_local_half_extents().y)
	assert_lte(u.move_target.x, limit, "the deep block's front stops at the hill edge")
	assert_gte(u.move_target.x, limit - OrderFootprint.SEARCH_TOLERANCE, "and not short of it")


func test_a_form_up_is_validated_in_its_deployed_facing() -> void:
	# A form-up holds deploy_facing, not its travel direction: marching east but deployed
	# facing north, the block's narrow width (not its 342 wu depth) runs along x.
	var u := _make_deep_block(Vector2(600, 480))
	u.deploy_facing = Vector2.UP
	u.move_target = Vector2(1140, 480)
	var limit: float = _clear_x(u, u._formation_local_half_extents().x)
	assert_lte(u.move_target.x, limit, "the deployed block's right file stops at the hill edge")
	assert_gte(u.move_target.x, limit - OrderFootprint.SEARCH_TOLERANCE,
		"and no farther back than its half-width needs")


func test_the_same_point_reissued_after_moving_is_revalidated_from_the_new_position() -> void:
	# The clamp depends on where the unit stands, not only on the point ordered: the same
	# point issued again from farther west pulls back from the new start.
	var u := _make_deep_block(Vector2(1110, 330))
	u.ordered_facing = u.facing
	u.move_target = Vector2(1140, 330)
	var limit: float = _clear_x(u, u._formation_local_half_extents().x)
	assert_gte(u.move_target.x, limit - OrderFootprint.SEARCH_TOLERANCE, "sanity check: first clamp")
	u.position = Vector2(900, 330)
	u.move_target = Vector2(1140, 330)
	assert_lte(u.move_target.x, limit, "still clear of the hill from the new start")
	assert_gte(u.move_target.x, limit - OrderFootprint.SEARCH_TOLERANCE,
		"and pulled back only as far as the footprint needs")
	assert_ne(u.move_target, Vector2(1140, 330), "the reissued point was validated, not taken as is")
	var before: int = u._formation_slots_call_count
	u.move_target = Vector2(1140, 330)
	assert_eq(u._formation_slots_call_count - before, 1, "every write rebuilds the footprint")
	# Widened to 5 files, the same point must stop farther west than the 3-file clamp did.
	u.frontage_override = 5
	u.move_target = Vector2(1140, 330)
	var wide_limit: float = _clear_x(u, u._formation_local_half_extents().x)
	assert_lt(wide_limit, limit - OrderFootprint.SEARCH_TOLERANCE, "sanity check: the wider block needs more room")
	assert_lte(u.move_target.x, wide_limit, "the reshaped block is re-validated with its new width")


func test_a_snapshot_round_trip_restores_a_clamped_destination_exactly() -> void:
	# A side-stepped deep block's destination was clamped in its held north facing. A fresh
	# unit restored from the snapshot must get that exact value back: re-validating it
	# while the restore is only half done (facing held, frontage, tier not yet written)
	# would lay the footprint out differently and move it.
	var u := _make_deep_block(Vector2(1110, 330))
	_nudge(u, BattleScript.NudgeDir.RIGHT)
	var saved: Vector2 = u.move_target
	assert_ne(saved, Vector2(1140, 330), "sanity check: the saved destination was clamped")
	var snap: Dictionary = u.to_snapshot_dict()
	var fresh: Unit = Unit.new()
	fresh.max_soldiers = 60
	add_child_autofree(fresh)
	fresh.apply_snapshot_dict(snap)
	assert_eq(fresh.move_target, saved, "the restored destination is bit-exact")


func test_a_non_positive_search_step_holds_position_loudly() -> void:
	var field: PathField = PathField.active
	var held: Vector2 = OrderFootprint.clamp_destination(field, Vector2(1100, 330),
			Vector2(1200, 450), Vector2.RIGHT, Vector2(20, 20), 0.0, 1.0)
	assert_push_error("step and tolerance must be positive")
	assert_eq(held, Vector2(1100, 330), "a bad search parameter holds rather than loops")


func test_a_blocked_move_that_goes_nowhere_holds() -> void:
	var p := Vector2(1200, 450)   # inside the hill
	var held: Vector2 = OrderFootprint.clamp_destination(PathField.active, p, p,
			Vector2.RIGHT, Vector2(20, 20))
	assert_eq(held, p, "zero-length move into terrain: hold where it stands")


func test_footprint_separated_only_along_its_own_file_axis_is_clear() -> void:
	# A thin footprint turned 45 degrees across the hill's north-west corner: its
	# projections overlap the rect on both world axes, but along its own file axis it
	# sits clear of the corner -- only that axis separates them.
	var u_axis := Vector2(1, 1).normalized()
	var corner := HILL.position
	var centre := corner - u_axis * 85.0
	assert_false(PathField.active.footprint_blocked(centre, u_axis, Vector2(1, 160)),
		"separated along the file axis alone: clear")
	assert_true(PathField.active.footprint_blocked(corner + u_axis * 5.0, u_axis, Vector2(1, 160)),
		"moved onto the corner: blocked")
