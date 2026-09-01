extends GutTest

## Unit tests for Acies Triplex persistent line membership and queries.

func test_unit_line_membership_defaults_and_queries() -> void:
	var u := Unit.new()
	add_child_autofree(u)
	assert_eq(u.line_index, 0, "default line index is 0")
	assert_true(u.is_front_line(), "unit is front line by default")
	assert_false(u.is_reserve_line(), "unit is not reserve line by default")

	u.line_index = 1
	assert_false(u.is_front_line(), "unit with line 1 is not front line")
	assert_true(u.is_reserve_line(), "unit with line 1 is reserve line")

	u.line_index = 2
	assert_true(u.is_reserve_line(), "unit with line 2 is reserve line")

func test_checkerboard_slices_line_assignment() -> void:
	var sel_mgr := SelectionManager.new()
	add_child_autofree(sel_mgr)
	var u1 := Unit.new()
	var u2 := Unit.new()
	var u3 := Unit.new()
	var u4 := Unit.new()
	add_child_autofree(u1)
	add_child_autofree(u2)
	add_child_autofree(u3)
	add_child_autofree(u4)

	var units := [u1, u2, u3, u4]
	var slices := sel_mgr._checkerboard_slices(units, Vector2(0, 0), Vector2(400, 0))
	assert_eq(slices.size(), 4, "4 units produce 4 slices")
	assert_eq(slices[0]["unit"], u1)
	assert_eq(slices[0]["line"], 0, "first unit is line 0")
	assert_eq(slices[1]["unit"], u3)
	assert_eq(slices[1]["line"], 0, "third unit is line 0")
	assert_eq(slices[2]["unit"], u2)
	assert_eq(slices[2]["line"], 1, "second unit is line 1")
	assert_eq(slices[3]["unit"], u4)
	assert_eq(slices[3]["line"], 1, "fourth unit is line 1")
