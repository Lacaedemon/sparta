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


func _bare_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 20
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


## Arm the one-sided link UnitRelief.begin() creates: the RELIEF order lives on the
## reliever and names the tired unit, and nothing at all is written to the tired side.
func _link(reliever: Unit, tired: Unit) -> void:
	var order := Order.new_relief(tired.uid)
	order.friendly_target = tired
	reliever.set_current_order(order)


func test_swap_partner_is_null_outside_the_tree() -> void:
	## A unit that was never added to the scene has no group to scan, so the reverse
	## lookup has to bail rather than touching get_tree().
	var orphan: Unit = autofree(Unit.new())
	orphan.max_soldiers = 20
	assert_false(orphan.is_inside_tree(), "the orphan really is outside the tree")
	assert_null(orphan._relief_swap_partner(), "no partner is discoverable off-tree")


func test_swap_partner_is_null_when_no_relief_link_exists() -> void:
	var a := _bare_unit()
	var b := _bare_unit()
	assert_null(a._relief_swap_partner(), "an unlinked unit has no swap partner")
	assert_null(b._relief_swap_partner(), "neither does its neighbour")


func test_swap_partner_reads_from_the_relievers_own_order() -> void:
	var reliever := _bare_unit()
	var tired := _bare_unit()
	_link(reliever, tired)
	assert_eq(reliever._relief_swap_partner(), tired,
			"the reliever reads its partner straight off its own RELIEF order")


func test_tired_side_discovers_the_partner_by_reverse_lookup() -> void:
	## The link is one-sided -- only the reliever's order names anyone -- so the tired
	## unit has to find it by scanning the units group for whoever names it.
	var reliever := _bare_unit()
	var tired := _bare_unit()
	_link(reliever, tired)
	assert_eq(tired._relief_swap_partner(), reliever,
			"the tired unit finds the reliever by reverse lookup")


func test_spread_strength_is_zero_without_a_partner() -> void:
	var u := _bare_unit()
	assert_eq(u._relief_corridor_spread_strength(null), 0.0,
			"no partner, no corridor")


func test_spread_strength_peaks_on_overlap_and_fades_with_distance() -> void:
	var reliever := _bare_unit()
	var tired := _bare_unit()
	_link(reliever, tired)

	tired.position = reliever.position
	assert_almost_eq(reliever._relief_corridor_spread_strength(tired),
			Unit.RELIEF_CORRIDOR_SPREAD_MAX, 0.0001,
			"fully overlapped blocks spread by the full maximum")

	var contact: float = reliever.separation_radius + tired.separation_radius \
			+ reliever.soldier_block_extent() + tired.soldier_block_extent()
	tired.position = reliever.position + Vector2(0.0, contact * 0.5)
	var half: float = reliever._relief_corridor_spread_strength(tired)
	assert_almost_eq(half, Unit.RELIEF_CORRIDOR_SPREAD_MAX * 0.5, 0.0001,
			"half a contact distance apart gives half the spread")

	tired.position = reliever.position + Vector2(0.0, contact * 2.0)
	assert_eq(reliever._relief_corridor_spread_strength(tired), 0.0,
			"blocks well clear of each other get no spread at all")


func test_corridor_is_a_no_op_on_an_empty_slot_set() -> void:
	var reliever := _bare_unit()
	var tired := _bare_unit()
	_link(reliever, tired)
	tired.position = reliever.position
	assert_eq(reliever._apply_relief_corridor_to_slots(PackedVector2Array(), 0).size(), 0,
			"no slots, nothing to widen")


func test_corridor_widens_when_the_partner_sits_exactly_on_top() -> void:
	## Coincident blocks leave no approach direction to derive the corridor axis from,
	## so the widening falls back to a fixed axis instead of normalizing a zero vector.
	var reliever := _bare_unit()
	var tired := _bare_unit()
	_link(reliever, tired)
	tired.position = reliever.position

	var base: PackedVector2Array = reliever.formation_slots(reliever.soldiers, false)
	var widened: PackedVector2Array = reliever._apply_relief_corridor_to_slots(
			base, reliever.soldiers)
	assert_eq(widened.size(), base.size(), "the corridor never adds or drops a slot")
	var moved := 0
	for i in range(base.size()):
		if not base[i].is_equal_approx(widened[i]):
			moved += 1
	assert_gt(moved, 0, "coincident blocks still open a corridor rather than bailing out")


func test_corridor_bails_out_when_rank_pitch_is_degenerate() -> void:
	## depth is the divisor that maps a slot's y back to its rank; a zero pitch would
	## make that division meaningless, so the widening is skipped entirely.
	var reliever := _bare_unit()
	var tired := _bare_unit()
	_link(reliever, tired)
	tired.position = reliever.position + Vector2(0.0, 4.0)

	var base: PackedVector2Array = reliever.formation_slots(reliever.soldiers, false)
	reliever.rank_pitch = 0.0
	var out: PackedVector2Array = reliever._apply_relief_corridor_to_slots(
			base, reliever.soldiers)
	assert_eq(out, base, "a degenerate rank pitch leaves every slot untouched")
