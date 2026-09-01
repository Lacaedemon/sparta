extends GutTest


func before_each() -> void:
	RangeQueries.clear_all()


func test_create_and_unregister_query() -> void:
	var u := Unit.new()
	u.team = 0
	u.position = Vector2(100.0, 100.0)
	var q_id := RangeQueries.create_query(u, 50.0, 1)
	assert_gt(q_id, 0)
	RangeQueries.unregister_query(q_id)
	u.free()


func test_update_all_enter_and_exit_diffs() -> void:
	var u1 := Unit.new()
	u1.team = 0
	u1.position = Vector2(0.0, 0.0)

	var u2 := Unit.new()
	u2.team = 1
	u2.position = Vector2(20.0, 0.0)

	var q_id := RangeQueries.create_query(u1, 30.0, 1)

	var diffs := RangeQueries.update_all([u1, u2])
	assert_true(diffs.has(q_id))
	assert_eq(diffs[q_id]["added"].size(), 1)
	assert_eq(diffs[q_id]["added"][0], u2)
	assert_eq(diffs[q_id]["removed"].size(), 0)

	# Second update without movement produces no diffs
	diffs = RangeQueries.update_all([u1, u2])
	assert_false(diffs.has(q_id))

	# Move u2 out of range
	u2.position = Vector2(100.0, 0.0)
	diffs = RangeQueries.update_all([u1, u2])
	assert_true(diffs.has(q_id))
	assert_eq(diffs[q_id]["added"].size(), 0)
	assert_eq(diffs[q_id]["removed"].size(), 1)
	assert_eq(diffs[q_id]["removed"][0], u2)

	u1.free()
	u2.free()


func test_anti_dogpile_scoring() -> void:
	var target := Unit.new()
	target.team = 1
	target.position = Vector2(0.0, 0.0)

	var a1 := Unit.new()
	a1.team = 0
	a1.position = Vector2(10.0, 0.0)

	var a2 := Unit.new()
	a2.team = 0
	a2.position = Vector2(15.0, 0.0)

	var a3 := Unit.new()
	a3.team = 0
	a3.position = Vector2(20.0, 0.0)

	var s1 := RangeQueries.score_target_anti_dogpile(a1, target, 2)
	assert_gt(s1, 0.0)

	RangeQueries.record_assignment(a1, target)
	RangeQueries.record_assignment(a2, target)

	var s3 := RangeQueries.score_target_anti_dogpile(a3, target, 2)
	assert_lt(s3, 0.0)

	target.free()
	a1.free()
	a2.free()
	a3.free()
