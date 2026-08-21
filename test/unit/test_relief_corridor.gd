extends GutTest
## Unit tests for line-relief corridor slot widening (UnitFormation.relief_corridor_slot_offset).


func test_relief_corridor_front_rank_unmoved() -> void:
	var perp := Vector2(1.0, 0.0)
	var off := UnitFormation.relief_corridor_slot_offset(Vector2(5.0, 0.0), 0, 8, perp, 0.5)
	assert_eq(off, Vector2.ZERO, "front rank stays put so the corridor opens behind it")


func test_relief_corridor_back_rank_pushes_flank_outward() -> void:
	var perp := Vector2(1.0, 0.0)
	var off := UnitFormation.relief_corridor_slot_offset(Vector2(5.0, 0.0), 4, 8, perp, 0.5)
	assert_gt(off.x, 0.0, "a flank man in a back rank steps further out")
	assert_eq(off.y, 0.0, "no displacement perpendicular to the spread direction")


func test_relief_corridor_symmetric_about_axis() -> void:
	var perp := Vector2(1.0, 0.0)
	var left := UnitFormation.relief_corridor_slot_offset(Vector2(-5.0, 0.0), 7, 8, perp, 0.5)
	var right := UnitFormation.relief_corridor_slot_offset(Vector2(5.0, 0.0), 7, 8, perp, 0.5)
	assert_eq(left.x, -right.x, "spread is symmetric about the corridor axis")


func test_relief_corridor_zero_on_centreline() -> void:
	var perp := Vector2(1.0, 0.0)
	var off := UnitFormation.relief_corridor_slot_offset(Vector2(0.0, 3.0), 3, 8, perp, 0.5)
	assert_eq(off, Vector2.ZERO, "centre-file men stay put to form the lane")


func test_relief_corridor_scales_with_spread_factor() -> void:
	var perp := Vector2(1.0, 0.0)
	var mark := Vector2(4.0, 0.0)
	var half := UnitFormation.relief_corridor_slot_offset(mark, 4, 8, perp, 0.25)
	var full := UnitFormation.relief_corridor_slot_offset(mark, 4, 8, perp, 0.50)
	assert_almost_eq(full.x, half.x * 2.0, 0.0001, "spread scales linearly with the factor")


func test_relief_corridor_deeper_back_ranks_spread_more() -> void:
	var perp := Vector2(1.0, 0.0)
	var mark := Vector2(4.0, 0.0)
	var mid := UnitFormation.relief_corridor_slot_offset(mark, 2, 8, perp, 0.5)
	var rear := UnitFormation.relief_corridor_slot_offset(mark, 7, 8, perp, 0.5)
	assert_gt(rear.x, mid.x, "deeper back ranks widen more than shallow ones")


func test_relief_corridor_works_for_diagonal_perp() -> void:
	var perp := Vector2(0.707107, 0.707107)
	var on_axis := UnitFormation.relief_corridor_slot_offset(Vector2(-1.0, 1.0), 5, 8, perp, 0.5)
	assert_almost_eq(on_axis.length(), 0.0, 0.01,
			"mark on a diagonal axis gets no spread offset")
	var off_axis := UnitFormation.relief_corridor_slot_offset(Vector2(3.0, 0.0), 5, 8, perp, 0.5)
	assert_gt(off_axis.length(), 0.0,
			"mark off a diagonal axis gets a non-zero spread offset")


func _spawn_battle() -> Node:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	return battle


func _unit_by_uid(battle: Node, uid: int) -> Unit:
	for node in battle.get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u != null and u.uid == uid:
			return u
	return null


func test_formation_slots_during_relief_does_not_recurse() -> void:
	## Regression: spread strength used to call soldier_block_extent(), which called
	## formation_slots() again, infinite recursion the moment a relief swap armed.
	var battle := _spawn_battle()
	for _k in range(10):
		await get_tree().physics_frame

	var tired: Unit = _unit_by_uid(battle, 0)
	var fresh: Unit = _unit_by_uid(battle, 1)
	assert_not_null(tired, "found tired unit")
	assert_not_null(fresh, "found fresh unit")
	if tired == null or fresh == null:
		return

	var relief_order := Order.new_relief(tired.uid)
	fresh.set_current_order(relief_order)
	UnitRelief.begin(fresh, tired, relief_order)
	assert_eq(fresh.current_order.friendly_target, tired, "relief swap armed")

	var base: PackedVector2Array = fresh.formation_slots(fresh.soldiers, false)
	var widened: PackedVector2Array = fresh.formation_slots(fresh.soldiers, true)
	assert_eq(base.size(), widened.size(), "corridor keeps slot count")
	# Extent queries must also complete (they use the base-grid path).
	var extent: float = fresh.soldier_block_extent()
	var partner_extent: float = tired.soldier_block_extent()
	assert_gt(extent, 0.0, "own base extent is finite")
	assert_gt(partner_extent, 0.0, "partner base extent is finite")
