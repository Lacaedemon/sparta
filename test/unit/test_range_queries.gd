extends GutTest

## Unit tests for RangeQueries spatial manager and anti-dogpile target scoring.

func before_each() -> void:
	RangeQueries.clear()

func test_range_queries_registration_and_query() -> void:
	var u1 := Unit.new()
	var u2 := Unit.new()
	add_child_autofree(u1)
	add_child_autofree(u2)
	u1.team = 0
	u2.team = 1
	u1.position = Vector2(100, 100)
	u2.position = Vector2(200, 100)

	var all_units := [u1, u2]
	var results := RangeQueries.query_range(u1.position, 150.0, u1.team, true, all_units)
	assert_eq(results.size(), 1, "finds 1 enemy in range")
	assert_eq(results[0], u2, "found enemy is u2")

	var results_far := RangeQueries.query_range(u1.position, 50.0, u1.team, true, all_units)
	assert_eq(results_far.size(), 0, "finds 0 enemies out of range")

func test_range_queries_diff_callback() -> void:
	var u1 := Unit.new()
	var u2 := Unit.new()
	add_child_autofree(u1)
	add_child_autofree(u2)
	u1.team = 0
	u2.team = 1
	u1.position = Vector2(100, 100)
	u2.position = Vector2(300, 100)

	var added_list: Array = []
	var removed_list: Array = []
	var on_diff = func(added: Array, removed: Array) -> void:
		added_list.append_array(added)
		removed_list.append_array(removed)

	var qid := RangeQueries.register_query(u1, 150.0, true, on_diff)
	var all_units := [u1, u2]

	# First tick: u2 is out of range
	RangeQueries.tick(all_units)
	assert_eq(added_list.size(), 0, "initially no added enemies")

	# Move u2 into range
	u2.position = Vector2(150, 100)
	RangeQueries.tick(all_units)
	assert_eq(added_list.size(), 1, "u2 added when entered range")
	assert_eq(added_list[0], u2)

	# Move u2 out of range
	u2.position = Vector2(500, 100)
	RangeQueries.tick(all_units)
	assert_eq(removed_list.size(), 1, "u2 removed when exited range")
	assert_eq(removed_list[0], u2)

	RangeQueries.unregister_query(qid)

func test_anti_dogpile_scoring() -> void:
	var u1 := Unit.new()
	var u2 := Unit.new()
	var e1 := Unit.new()
	var e2 := Unit.new()
	add_child_autofree(u1)
	add_child_autofree(u2)
	add_child_autofree(e1)
	add_child_autofree(e2)
	u1.team = 0
	u2.team = 0
	e1.team = 1
	e2.team = 1
	u1.position = Vector2(100, 100)
	u2.position = Vector2(100, 120)
	e1.position = Vector2(150, 100)
	e2.position = Vector2(160, 100)

	# With 0 attackers, e1 is closer so score(e1) > score(e2)
	var s1 := UnitTargeting.score_target(u1, e1, u1.position)
	var s2 := UnitTargeting.score_target(u1, e2, u1.position)
	assert_gt(s1, s2, "closer target scores higher without dogpile")

	# If two friendly units already target e1, e1 receives anti-dogpile penalty
	var ally1 := Unit.new()
	var ally2 := Unit.new()
	add_child_autofree(ally1)
	add_child_autofree(ally2)
	ally1.team = 0
	ally2.team = 0
	ally1.target_enemy = e1
	ally2.target_enemy = e1

	var s1_dogpiled := UnitTargeting.score_target(u1, e1, u1.position)
	assert_lt(s1_dogpiled, s2, "dogpiled target with 2 attackers receives heavy penalty")
