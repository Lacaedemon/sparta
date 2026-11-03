extends GutTest
## UnitRelief.pair_by_lateral_order: a distributed relief pairs each reliever with the tired
## unit in front of it, flank to flank along the line, so the pairing does not depend on the
## order of the proximity-sorted pool -- whose order for two tired units at equal distance
## from the clicked one is set by float noise in their positions.


func _unit(uid: int, pos: Vector2) -> Unit:
	var u: Unit = autofree(Unit.new())
	u.uid = uid
	u.position = pos
	return u


## A fresh row at y 370 behind a tired row at y 470, laid out like a passage of lines: the
## clicked tired unit in the centre, its two neighbours equidistant from it.
func _rows() -> Dictionary:
	return {
		"fresh": [_unit(0, Vector2(600, 370)), _unit(1, Vector2(820, 370)),
				_unit(2, Vector2(1040, 370))],
		"left": _unit(3, Vector2(600, 470)),
		"centre": _unit(4, Vector2(820, 470)),
		"right": _unit(5, Vector2(1040, 470)),
	}


func _uids_of(pairing: Dictionary, fresh: Array) -> Array:
	var out: Array = []
	for f in fresh:
		out.append(pairing[f.uid].uid)
	return out


func test_each_reliever_takes_the_unit_in_front_whichever_flank_sorts_first() -> void:
	# The pool order is varied directly: either flank may come out of the proximity sort
	# first, since float noise decides between the two equidistant ones. The pairing must
	# be the same for both orders.
	var r := _rows()
	var near_left: Array = [r["centre"], r["left"], r["right"]]
	var near_right: Array = [r["centre"], r["right"], r["left"]]
	for pool in [near_left, near_right]:
		var pairing := UnitRelief.pair_by_lateral_order(r["fresh"], pool)
		assert_eq(_uids_of(pairing, r["fresh"]), [3, 4, 5],
				"left->left, centre->centre, right->right")


func test_pairing_ignores_the_order_the_relievers_are_listed_in() -> void:
	var r := _rows()
	var fresh: Array = r["fresh"]
	var reversed: Array = [fresh[2], fresh[0], fresh[1]]
	var pairing := UnitRelief.pair_by_lateral_order(reversed,
			[r["centre"], r["left"], r["right"]])
	assert_eq(_uids_of(pairing, fresh), [3, 4, 5], "selection order does not cross the pairs")


func test_only_the_nearest_tired_units_are_relieved_when_relievers_are_fewer() -> void:
	var r := _rows()
	var fresh: Array = r["fresh"]
	# Two relievers, the pool sorted with the centre and left nearest: those two are relieved,
	# the left reliever taking the left unit.
	var pairing := UnitRelief.pair_by_lateral_order([fresh[0], fresh[1]],
			[r["centre"], r["left"], r["right"]])
	assert_eq(pairing[0].uid, 3, "the left reliever takes the left tired unit")
	assert_eq(pairing[1].uid, 4, "the centre reliever takes the clicked one")


func test_extra_relievers_double_up_without_crossing() -> void:
	var fresh: Array = [_unit(0, Vector2(0, 0)), _unit(1, Vector2(100, 0)),
			_unit(2, Vector2(200, 0))]
	var tired: Array = [_unit(3, Vector2(50, 100)), _unit(4, Vector2(150, 100))]
	var pairing := UnitRelief.pair_by_lateral_order(fresh, tired)
	var partners: Array = _uids_of(pairing, fresh)
	assert_eq(partners, [3, 3, 4], "the extra reliever doubles up on its neighbour")
	for i in partners.size() - 1:
		assert_true(partners[i] <= partners[i + 1],
				"partners never step back along the line, so no two pairs cross")


func test_a_relieved_set_off_to_one_side_still_pairs_along_the_line() -> void:
	# Two relievers stand over the right end of a tired line; the click lands on the line's left
	# end, so the two relieved tired units sit far to the relievers' left. The left tired unit has
	# drifted 50 wu deeper than its neighbour. The axis along the line must come from the line
	# itself (its facing), not from the offset between the two sets' centres, which here tilts
	# almost onto the depth axis and would let that drift reorder the two tired units.
	var fresh: Array = [_unit(0, Vector2(660, 0)), _unit(1, Vector2(880, 0))]
	var pool: Array = [_unit(3, Vector2(0, 150)), _unit(4, Vector2(220, 100)),
			_unit(5, Vector2(440, 100)), _unit(6, Vector2(660, 100)), _unit(7, Vector2(880, 100))]
	var pairing := UnitRelief.pair_by_lateral_order(fresh, pool)
	assert_eq(_uids_of(pairing, fresh), [3, 4], "the left reliever takes the left relieved unit")


func _facing(u: Unit, f: Vector2) -> Unit:
	u.facing = f
	return u


func test_a_line_facing_east_pairs_along_its_north_south_length() -> void:
	# The tired line faces east (Vector2.RIGHT), so it runs north-south and the relievers stand
	# west of it. The uids run against the line, so an axis that ignored the facing (one fixed
	# east-west axis, on which every unit of a line projects alike) would fall back to uid
	# order and cross the pairs.
	var fresh: Array = [_unit(0, Vector2(0, 0)), _unit(1, Vector2(0, 220)),
			_unit(2, Vector2(0, 440))]
	var top: Unit = _facing(_unit(5, Vector2(100, 0)), Vector2.RIGHT)
	var middle: Unit = _facing(_unit(4, Vector2(100, 220)), Vector2.RIGHT)
	var bottom: Unit = _facing(_unit(3, Vector2(100, 440)), Vector2.RIGHT)
	var pairing := UnitRelief.pair_by_lateral_order(fresh, [middle, top, bottom])
	assert_eq(_uids_of(pairing, fresh), [5, 4, 3], "each reliever takes the unit beside it")


func test_cancelling_facings_fall_back_to_the_offset_between_the_lines() -> void:
	# Two relieved units facing opposite ways leave no mean facing; the axis then comes from
	# the offset between the two sets' centres (here east-west, so the line runs north-south).
	# The uids again run against the line, so a fixed east-west fallback would cross the pair.
	var fresh: Array = [_unit(0, Vector2(0, 0)), _unit(1, Vector2(0, 220))]
	var top: Unit = _facing(_unit(4, Vector2(100, 0)), Vector2.RIGHT)
	var bottom: Unit = _facing(_unit(3, Vector2(100, 220)), Vector2.LEFT)
	var pairing := UnitRelief.pair_by_lateral_order(fresh, [top, bottom])
	assert_eq(_uids_of(pairing, fresh), [4, 3], "each reliever takes the unit beside it")


func test_no_facing_and_no_offset_still_pairs_deterministically() -> void:
	# Degenerate input only (the two sets would have to share a centre with cancelling
	# facings): the fixed axis keeps the result deterministic rather than undefined.
	var fresh: Array = [_unit(0, Vector2(0, 0)), _unit(1, Vector2(100, 0))]
	var left: Unit = _facing(_unit(3, Vector2(0, 0)), Vector2.RIGHT)
	var right: Unit = _facing(_unit(4, Vector2(100, 0)), Vector2.LEFT)
	var pairing := UnitRelief.pair_by_lateral_order(fresh, [right, left])
	assert_eq(_uids_of(pairing, fresh), [3, 4], "ordered along the fixed east-west axis")


func test_empty_inputs_pair_nothing() -> void:
	assert_eq(UnitRelief.pair_by_lateral_order([], [_unit(3, Vector2.ZERO)]), {})
	assert_eq(UnitRelief.pair_by_lateral_order([_unit(0, Vector2.ZERO)], []), {})
