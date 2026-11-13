extends GutTest
## A block's extent, footprint centre and front are measured from where its men stand, not from
## its slot grid: a block whose men are off their slots reports the men's measure, and no
## measure builds the grid. A block with no men yet (spawn, far tier) reads its layout.


func _block(n: int = 40, facing: Vector2 = Vector2.DOWN) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers
	u.facing = facing
	u.position = Vector2(500.0, 500.0)
	return u


func _seeded(n: int = 40, facing: Vector2 = Vector2.DOWN) -> Unit:
	var u: Unit = _block(n, facing)
	u.seed_sim_soldiers()
	return u


func test_men_on_their_slots_read_the_slot_grid_bounds() -> void:
	var u: Unit = _seeded()
	var half: Vector2 = u._formation_local_half_extents()
	var layout: Vector2 = u._far_tier_half_extents()
	assert_almost_eq(half.x, layout.x, 0.01, "half-width")
	assert_almost_eq(half.y, layout.y, 0.01, "half-depth")


func test_men_displaced_from_their_slots_report_their_own_extent() -> void:
	var u: Unit = _seeded()
	var before: Vector2 = u._formation_local_half_extents()
	var angle: float = u.soldier_block_world_angle()
	# One man stands 100 wu past the line's end, one 60 wu behind its rear rank.
	u._sim_soldier_pos[0] = u.position + Vector2(before.x + 100.0, 0.0).rotated(angle)
	u._sim_soldier_pos[1] = u.position + Vector2(0.0, before.y + 60.0).rotated(angle)
	var half: Vector2 = u._formation_local_half_extents()
	assert_almost_eq(half.x, before.x + 100.0, 0.01, "the block reaches the man off its flank")
	assert_almost_eq(half.y, before.y + 60.0, 0.01, "the block reaches the man off its rear")


func test_soldier_block_extent_is_the_farthest_man_padded() -> void:
	var u: Unit = _seeded()
	u._sim_soldier_pos[3] = u.position + Vector2(0.0, 400.0)
	assert_almost_eq(u.soldier_block_extent(), 400.0 + Unit.MARK_RADIUS + 2.0, 0.01)
	var half: Vector2 = u.soldier_block_half_extents()
	assert_gt(half.length(), 400.0, "the per-axis bound covers the straggler too")


func test_no_extent_measure_builds_the_slot_grid() -> void:
	var u: Unit = _seeded()
	u._sim_soldier_pos[0] += Vector2(30.0, 10.0)
	var calls: int = u._formation_slots_call_count
	u._formation_local_half_extents()
	u.soldier_block_extent()
	u.soldier_block_half_extents()
	u.block_centre_offset()
	SoldierFlock.compute_extent(u, true)
	assert_eq(u._formation_slots_call_count, calls, "measured from the men, with no slot rebuild")


func test_footprint_centre_follows_the_men() -> void:
	var u: Unit = _seeded()
	assert_lt(u.block_centre_offset().length(), 0.01, "a centred block has no offset")
	var shift := Vector2(25.0, -10.0)
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += shift
	var centre: Vector2 = u.block_centre_offset()
	assert_almost_eq(centre.x, shift.x, 0.01, "the whole block stands off its position: x")
	assert_almost_eq(centre.y, shift.y, 0.01, "the whole block stands off its position: y")


func test_melee_front_reads_the_men_across_the_front() -> void:
	var u: Unit = _seeded()   # facing down: its front runs along x
	var before: Vector2 = MeleeFrontGeometry.men_offset(u)
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(18.0, 7.0)
	u._front_profile = null   # a profile is kept per physics frame; a test stays in one frame
	var offset: Vector2 = MeleeFrontGeometry.men_offset(u)
	assert_almost_eq(offset.x - before.x, 18.0, 0.01, "the men stand 18 wu across the front")
	assert_almost_eq(offset.y, 0.0, 0.01, "along it the position already stands on the front men")


func test_a_block_with_no_men_reads_its_layout() -> void:
	var u: Unit = _block()
	assert_true(u._sim_soldier_pos.is_empty(), "setup: nothing seeded")
	var layout: Vector2 = u._far_tier_half_extents()
	assert_eq(u._formation_local_half_extents(), layout)
	assert_gt(layout.x, 0.0)
	u.set_frontage(10, 60.0)
	assert_almost_eq(u.block_centre_offset().length(), 60.0, 0.01,
			"the ordered anchor shift is the footprint centre before any man exists")


func test_layout_front_depth_is_the_farthest_slot_along_the_facing() -> void:
	for facing in [Vector2.DOWN, Vector2.UP, Vector2.RIGHT, Vector2(1.0, 1.0).normalized()]:
		var u: Unit = _block(37, facing)
		var farthest: float = -INF
		for slot in u.soldier_world_slots(u.soldiers):
			farthest = maxf(farthest, (slot - u.position).dot(u.facing))
		assert_almost_eq(u.layout_front_depth(), farthest, 0.01, "facing %s" % facing)
