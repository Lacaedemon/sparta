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


func test_a_unit_already_overlapping_terrain_can_still_move_along_it() -> void:
	# Centred at x 1250 the deep block's rear ranks already stand inside the hill. A
	# side-step east keeps exactly the same overlap, so it goes through: a unit already in
	# the terrain is not frozen there, only kept from going deeper.
	var u := _make_deep_block(Vector2(1250, 330))
	assert_gt(_slots_inside_hill(u, u.position, u.facing), 0, "sanity check: starts overlapping")
	_nudge(u, BattleScript.NudgeDir.RIGHT)
	assert_eq(u.move_target, Vector2(1280, 330), "a move that overlaps no more than the start is untouched")


func test_a_unit_already_overlapping_terrain_is_kept_from_going_deeper() -> void:
	# The same block stepping back (south) would push more of its rear ranks into the hill.
	var u := _make_deep_block(Vector2(1250, 330))
	_nudge(u, BattleScript.NudgeDir.BACK)
	assert_eq(u.move_target, Vector2(1250, 330), "no deeper than it already stands: it holds")


func test_an_undisciplined_march_is_validated_in_the_grid_it_keeps() -> void:
	# An undisciplined unit snaps facing onto a 90-degree turn and folds the snap into its
	# formation angle, so its 15-file frontage keeps running along x as it marches east.
	# The footprint must be that wide along x, not its shallow depth.
	var u: Unit = Unit.new()
	u.max_soldiers = 120
	u.disciplined = false
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2(1000, 400)
	u.move_target = Vector2(1120, 400)
	var half: Vector2 = u._formation_local_half_extents()
	assert_gt(half.x, half.y, "sanity check: wider than deep")
	var limit: float = _clear_x(u, half.x)
	assert_lte(u.move_target.x, limit, "the kept frontage stops at the hill edge")
	assert_gte(u.move_target.x, limit - OrderFootprint.SEARCH_TOLERANCE, "and no farther back")


func test_a_zero_length_move_keeps_the_current_facing() -> void:
	var u := _make_deep_block(Vector2(1250, 330))
	assert_eq(u._order_held_facing(u.position), Vector2.UP, "nowhere to travel: the current facing")


func test_overlap_area_is_the_exact_clipped_area() -> void:
	# A 20 x 20 square centred on the hill's north-west corner covers a 10 x 10 quarter.
	var area: float = PathField.active.footprint_overlap_area(HILL.position, Vector2.RIGHT, Vector2(10, 10))
	assert_almost_eq(area, 100.0, 0.001, "a quarter of the square lies inside the hill")
	assert_almost_eq(PathField.active.footprint_overlap_area(Vector2(100, 100), Vector2.RIGHT, Vector2(10, 10)),
		0.0, 0.001, "clear ground overlaps nothing")


func test_a_folded_grid_is_validated_as_it_stands() -> void:
	# Mid-march an undisciplined block can face east while a quarter fold keeps its
	# frontage running along x (the slot grid soldier_world_slots lays out). A leg
	# committed in that state must be validated in that grid, not a squared one.
	var u: Unit = Unit.new()
	u.max_soldiers = 120
	add_child_autofree(u)
	u.facing = Vector2.RIGHT
	u._formation_angle = -PI * 0.5
	u.position = Vector2(1000, 400)
	u.move_target = Vector2(1120, 400)
	var half: Vector2 = u._formation_local_half_extents()
	var limit: float = _clear_x(u, half.x)
	assert_lte(u.move_target.x, limit, "the folded frontage stops at the hill edge")
	assert_gte(u.move_target.x, limit - OrderFootprint.SEARCH_TOLERANCE, "and no farther back")


## The overlap area of `u`'s footprint centred on `at`, laid out as clamp_order_destination
## lays it out for a held north facing.
func _area_at(u: Unit, at: Vector2) -> float:
	var r: float = u.soldier_body_radius()
	return PathField.active.footprint_overlap_area(at, Vector2.UP.rotated(PI * 0.5),
			u._formation_local_half_extents() + Vector2(r, r))


func test_a_held_facing_past_the_snap_threshold_keeps_the_current_grid() -> void:
	# A drag-to-form-up ordering a north-facing deep block to face east: _face_dir() folds
	# a 90-degree snap into the formation angle, so the 3-file grid keeps running north and
	# arrives 36 wu wide, not 342. Its destination beside the hill is clear in that grid.
	var u := _make_deep_block(Vector2(900, 480))
	u.deploy_facing = Vector2.RIGHT
	u.ordered_facing = Vector2.RIGHT
	u.move_target = Vector2(1120, 480)
	assert_eq(u.move_target, Vector2(1120, 480), "validated in the kept narrow grid: clear, unchanged")


func test_a_hasty_march_keeps_its_grid_like_an_undisciplined_one() -> void:
	# A disciplined unit on a run/sprint (haste) order does not pivot either: past the
	# snap threshold its 15-file frontage keeps running along x as it marches east.
	var u: Unit = Unit.new()
	u.max_soldiers = 120
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2(1000, 400)
	assert_true(u.disciplined, "sanity check: a disciplined unit")
	u.set_current_order(Order.new_move(Vector2(1120, 400), 0, Unit.GAIT_RUN, true))
	u.move_target = Vector2(1120, 400)
	var limit: float = _clear_x(u, u._formation_local_half_extents().x)
	assert_lte(u.move_target.x, limit, "the kept frontage stops at the hill edge")
	assert_gte(u.move_target.x, limit - OrderFootprint.SEARCH_TOLERANCE, "and no farther back")


func test_repeated_small_orders_never_ratchet_an_overlapping_block_deeper() -> void:
	# From a start already overlapping the hill, twenty tiny steps south (each adding about
	# one 0.0625 square-wu step of the polygon clip's measured area resolution) must never
	# leave the block covering more hill than it started with.
	var u := _make_deep_block(Vector2(1250, 330))
	u.ordered_facing = u.facing
	var start_area: float = _area_at(u, u.position)
	assert_gt(start_area, 0.0, "sanity check: starts overlapping")
	for i in 20:
		u.move_target = u.position + Vector2(0, 0.001)
		u.position = u.move_target
	assert_lte(_area_at(u, u.position), start_area, "the overlap never grew past the first start's")


func test_overlap_area_counts_ground_two_rects_share_once() -> void:
	var field := PathField.new(Rect2(0, 0, 400, 400))
	field.block_rect(Rect2(0, 0, 100, 100))
	field.block_rect(Rect2(50, 0, 100, 100))
	var area: float = field.footprint_overlap_area(Vector2(75, 50), Vector2.RIGHT, Vector2(75, 50))
	assert_almost_eq(area, 15000.0, 0.01, "the union (150 x 100), not the sum of both rects (20000)")


# --- Write-site ordering --------------------------------------------------------------
# The clamp reads the held facing, frontage, tier and fold at the moment move_target is
# written, so every writer must set those first. Each test below drives a real writer from
# a clear start and then re-checks the destination against the unit's FINAL state: a
# writer that sets a field after the write leaves a destination the final grid overlaps.

## Whether `u`'s footprint at its committed destination, laid out from the unit's final
## state exactly as clamp_order_destination() would lay it out now, is clear of the hill.
func _clear_in_final_grid(u: Unit) -> bool:
	var r: float = u.soldier_body_radius()
	var axis: Vector2 = u._order_held_facing(u.move_target).rotated(PI * 0.5 + u._formation_angle)
	return not PathField.active.footprint_blocked(u.move_target, axis,
			u._formation_local_half_extents() + Vector2(r, r))


func test_a_relief_retreat_is_validated_in_the_facing_it_holds() -> void:
	# A tired deep column facing east (342 wu deep along x) west of the hill retreats north
	# toward its back edge. It holds its east facing, so at the destination its depth
	# reaches into the hill and the retreat is pulled back; laid out in the north bearing
	# instead it would look 36 wu wide and pass unclamped.
	var tired := _make_deep_block(Vector2(1000, 700))
	tired.facing = Vector2.RIGHT
	var reliever := _make_deep_block(Vector2(600, 900))
	UnitRelief.begin(reliever, tired, Order.new_relief(tired.uid))
	assert_eq(tired.ordered_facing, Vector2.RIGHT, "sanity check: the retreat holds the east facing")
	assert_true(_clear_in_final_grid(tired), "the retreat destination is clear in the facing held")
	var limit: float = HILL.end.y + tired._formation_local_half_extents().x + tired.soldier_body_radius()
	assert_gte(tired.move_target.y, limit, "stops south of the hill")
	assert_lte(tired.move_target.y, limit + OrderFootprint.SEARCH_TOLERANCE, "and no farther south")


func test_a_disengage_step_is_validated_in_its_final_grid() -> void:
	var u := _make_deep_block(Vector2(1250, 200))
	u.state = Unit.State.FIGHTING
	u.disengage()
	assert_ne(u.move_target, Vector2(1250, 270), "sanity check: the full step would enter the hill")
	assert_true(_clear_in_final_grid(u), "clear in the grid the disengage holds")


func test_a_disengage_with_sacrifice_is_validated_in_its_final_grid() -> void:
	# The sacrifice drops the headcount (and so the depth) before the step is written.
	var u := _make_deep_block(Vector2(1250, 200))
	u.state = Unit.State.FIGHTING
	u.disengage_with_sacrifice()
	assert_ne(u.move_target, Vector2(1250, 270), "sanity check: the full step would enter the hill")
	assert_true(_clear_in_final_grid(u), "clear in the grid the shrunken block holds")


func test_a_promoted_queued_leg_is_validated_in_its_final_grid() -> void:
	var u := _make_deep_block(Vector2(1000, 480))
	u.set_current_order(Order.new_move(Vector2(1000, 470)))
	u.append_order(Order.new_move(Vector2(1120, 480)))
	u.retire_current_order()
	assert_true(u.has_move_target, "sanity check: the queued leg committed its march")
	assert_ne(u.move_target, Vector2(1120, 480), "sanity check: the leg as queued would enter the hill")
	assert_true(_clear_in_final_grid(u), "the promoted leg is clear in its final grid")
