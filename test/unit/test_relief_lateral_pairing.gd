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


func test_empty_inputs_pair_nothing() -> void:
	assert_eq(UnitRelief.pair_by_lateral_order([], [_unit(3, Vector2.ZERO)]), {})
	assert_eq(UnitRelief.pair_by_lateral_order([_unit(0, Vector2.ZERO)], []), {})
