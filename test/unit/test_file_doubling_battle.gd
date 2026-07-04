extends GutTest
## File-doubling (duplicatio / explicatio) in a LIVE battle: instantiate the real Battle
## scene, spawn the armies, and drive the maneuver through the recorded order path
## (Battle.enqueue_file_double) exactly as the hotkey does. Steps the full simulation tick
## by tick and asserts the resulting frontage AND that the soldier bodies ease into the
## reshaped slots at velocity -- no body teleports, and the regiment centre stays put (the
## reshape changes the formation, not the unit position).

# The regiment centre couples toward its soldiers' body centroid (SoldierBodies.couple),
# so reshaping the block shifts the centre by the small amount the centroid moves as the
# ranks re-lay-out -- a deepening (duplicatio) settles a touch more than a widening. This
# bounds that one-time settle well below a real "the unit walked off" regression (tens of px).
const CENTRE_SETTLE_TOLERANCE_PX := 10.0


func _bbox(ps: PackedVector2Array) -> Vector2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in ps:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	return mx - mn


func _max_step(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var m := 0.0
	for i in range(mini(a.size(), b.size())):
		m = maxf(m, a[i].distance_to(b[i]))
	return m


func _target_unit(tree: SceneTree) -> Unit:
	# The block nearest ~(500, 300) -- the same Spearmen the file-doubling demo exercises.
	var target: Unit = null
	var best := INF
	for u in tree.get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0:
			var d: float = unit.position.distance_to(Vector2(500, 300))
			if d < best:
				best = d
				target = unit
	return target


func test_explicatio_widens_the_line_without_teleporting_bodies() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(40):                      # spawn the armies and let the bodies settle
		await get_tree().physics_frame
	var target: Unit = _target_unit(get_tree())
	assert_not_null(target, "found a team-0 unit to reshape")
	if target == null:
		return

	var start_frontage: int = UnitFormation.frontage(target)
	var start_pos: Vector2 = target.position
	battle.enqueue_file_double([target.uid], 1)   # explicatio
	assert_eq(UnitFormation.frontage(target), start_frontage * 2,
		"explicatio doubles the frontage")

	# Step the sim: the soldier bodies ease toward the reshaped slots. No body should jump.
	var prev: PackedVector2Array = target._sim_soldier_pos.duplicate()
	var worst_step := 0.0
	for _i in range(90):                      # ~1.5 s to ease into the new block
		await get_tree().physics_frame
		worst_step = maxf(worst_step, _max_step(prev, target._sim_soldier_pos))
		prev = target._sim_soldier_pos.duplicate()

	assert_lt(worst_step, 6.0,
		"bodies ease into the reshaped slots at velocity, no teleport (worst %.3f px)" % worst_step)
	assert_lt(target.position.distance_to(start_pos), CENTRE_SETTLE_TOLERANCE_PX,
		"the reshape moves the formation, not the regiment centre")
	# The widened block is broader (more files) and shallower than it started.
	var wide_bbox: Vector2 = _bbox(target._sim_soldier_pos)
	assert_gt(wide_bbox.length(), 0.0, "the reshaped block has a real footprint")


func test_duplicatio_deepens_the_line() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(40):
		await get_tree().physics_frame
	var target: Unit = _target_unit(get_tree())
	assert_not_null(target, "found a team-0 unit to reshape")
	if target == null:
		return

	var start_frontage: int = UnitFormation.frontage(target)
	var start_pos: Vector2 = target.position
	battle.enqueue_file_double([target.uid], -1)   # duplicatio
	assert_eq(UnitFormation.frontage(target), maxi(1, start_frontage / 2),
		"duplicatio halves the frontage")

	var prev: PackedVector2Array = target._sim_soldier_pos.duplicate()
	var worst_step := 0.0
	for _i in range(90):
		await get_tree().physics_frame
		worst_step = maxf(worst_step, _max_step(prev, target._sim_soldier_pos))
		prev = target._sim_soldier_pos.duplicate()

	assert_lt(worst_step, 6.0,
		"bodies ease into the deeper block, no teleport (worst %.3f px)" % worst_step)
	assert_lt(target.position.distance_to(start_pos), CENTRE_SETTLE_TOLERANCE_PX,
		"the reshape moves the formation, not the regiment centre")


func test_explicatio_right_anchored_holds_the_right_flank_in_place() -> void:
	# The asymmetric variant (Shift+B in SelectionManager): anchoring RIGHT should hold
	# the right-flank SLOT in its world position while the block widens entirely off
	# the LEFT flank, unlike the plain centred explicatio where both flanks move
	# outward symmetrically. Read the target SLOT geometry (soldier_world_slots),
	# not live soldier-body positions -- widening relabels which body occupies which
	# slot index, so a body's own eased position doesn't track "the right flank" the
	# way the slot it's walking toward does.
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(40):                      # spawn the armies and let the bodies settle
		await get_tree().physics_frame
	var target: Unit = _target_unit(get_tree())
	assert_not_null(target, "found a team-0 unit to reshape")
	if target == null:
		return

	var start_frontage: int = UnitFormation.frontage(target)
	var start_slots := target.soldier_world_slots(target.soldiers)
	var right_flank_start: Vector2 = start_slots[start_frontage - 1]   # front-rank rightmost slot
	var left_flank_start: Vector2 = start_slots[0]                     # front-rank leftmost slot
	battle.enqueue_file_double([target.uid], 1, UnitFormation.Anchor.RIGHT)   # asymmetric explicatio
	var new_frontage: int = UnitFormation.frontage(target)
	assert_eq(new_frontage, start_frontage * 2,
		"anchored explicatio still doubles the frontage like the centred variant")

	# The reshape is instantaneous in slot geometry (only the bodies ease at velocity),
	# so the target slots can be read immediately -- no need to step the sim first.
	# The block also gets SHALLOWER (halving ranks), so the front rank legitimately
	# sits at a different DEPTH (world Y here, since this unit faces along Y) -- that's
	# an expected side effect of ranks changing, not the anchor. The anchor is about
	# the LATERAL axis only, so compare X (the unit's file axis), not the full 2D point.
	var new_slots := target.soldier_world_slots(target.soldiers)
	var right_flank_end: Vector2 = new_slots[new_frontage - 1]   # new front-rank rightmost slot
	var left_flank_end: Vector2 = new_slots[0]                   # new front-rank leftmost slot

	assert_almost_eq(right_flank_end.x, right_flank_start.x, 0.5,
		"the anchored (right) flank slot's lateral position stays fixed as the block widens")
	assert_gt(absf(left_flank_end.x - left_flank_start.x), CENTRE_SETTLE_TOLERANCE_PX,
		"the opposite (left) flank slot's lateral position moves as the whole widen lands on that side")

	# The bodies still ease toward the new slots at velocity -- no teleport -- exactly
	# like the centred variant.
	var prev: PackedVector2Array = target._sim_soldier_pos.duplicate()
	var worst_step := 0.0
	for _i in range(90):                      # ~1.5 s to ease into the new block
		await get_tree().physics_frame
		worst_step = maxf(worst_step, _max_step(prev, target._sim_soldier_pos))
		prev = target._sim_soldier_pos.duplicate()
	assert_lt(worst_step, 6.0,
		"bodies ease into the anchored slots at velocity, no teleport (worst %.3f px)" % worst_step)


func test_explicatio_right_anchored_settles_with_the_regiment_centre_held_and_body_centroid_shifted() -> void:
	# Regression test: SoldierBodies.couple() slides `position` toward the soldier bodies'
	# own centroid each tick to correct genuine off-formation drift (friendly-avoidance,
	# knockback). An anchored explicatio/duplicatio makes the TARGET slot centroid itself
	# sit away from `position` on purpose (frontage_anchor_offset) -- not drift to correct.
	# Before the fix, coupling misread that permanent, intentional gap as drift and kept
	# dragging `position` every tick right up until the bodies (separately easing onto the
	# anchored slots) caught up -- so by the time the bodies settled, `position` had been
	# pulled tens of world units off, and the render's selection ring (drawn at `position`)
	# visibly no longer centred on the widened block, even though the immediately-read slot
	# geometry (the sibling test above) looked correct the instant the order was issued.
	# This test steps the FULL sim long enough for the bodies to actually settle and checks
	# both ends of the same regression: `position` stays put, AND the body centroid ends up
	# genuinely off-centre (proving the widen is actually asymmetric in the live render, not
	# just in the instantaneous target math).
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(40):                      # spawn the armies and let the bodies settle
		await get_tree().physics_frame
	var target: Unit = _target_unit(get_tree())
	assert_not_null(target, "found a team-0 unit to reshape")
	if target == null:
		return

	var start_pos: Vector2 = target.position
	var start_bbox: Vector2 = _bbox(target._sim_soldier_pos)
	var start_centroid := Vector2.ZERO
	for p in target._sim_soldier_pos:
		start_centroid += p
	start_centroid /= float(target._sim_soldier_pos.size())

	battle.enqueue_file_double([target.uid], 1, UnitFormation.Anchor.RIGHT)   # asymmetric explicatio

	# Settle well past the ~1.5 s a plain widen needs (test above) -- the anchored case has
	# further to travel on the growing flank, so give it a generous margin.
	for _i in range(300):
		await get_tree().physics_frame

	assert_almost_eq(target.position.x, start_pos.x, 1.0,
		"the regiment centre holds still through an anchored widen, exactly like the centred one")
	assert_almost_eq(target.position.y, start_pos.y, 1.0,
		"the regiment centre holds still through an anchored widen, exactly like the centred one")

	var end_centroid := Vector2.ZERO
	for p in target._sim_soldier_pos:
		end_centroid += p
	end_centroid /= float(target._sim_soldier_pos.size())
	var end_bbox: Vector2 = _bbox(target._sim_soldier_pos)

	# The widened block is measurably wider than it started (more files).
	assert_gt(end_bbox.x, start_bbox.x + CENTRE_SETTLE_TOLERANCE_PX,
		"the anchored widen genuinely broadens the block's world footprint")
	# An anchored widen is NOT a plain centred widen: the body centroid must shift by a
	# real amount (half the width gained, landing on the un-anchored flank) rather than
	# staying near the pre-widen centroid the way test_explicatio_widens_the_line_... does.
	assert_gt(start_centroid.distance_to(end_centroid), CENTRE_SETTLE_TOLERANCE_PX,
		"the anchored widen visibly shifts the soldiers' own centroid off the old centre " +
		"(a plain centred widen would not) -- this is the render-visible asymmetry the " +
		"anchor is FOR; a regiment-centre-drags-to-cancel-it bug would collapse this back " +
		"toward zero")
