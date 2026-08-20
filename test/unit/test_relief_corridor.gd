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
