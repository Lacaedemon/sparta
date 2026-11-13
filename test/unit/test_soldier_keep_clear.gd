extends GutTest
## SoldierKeepClear: a man with no place keeps off the men of his own unit.

const AT := Vector2(500, 500)


func _unit(count: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = AT
	u.seed_sim_soldiers()
	return u


func test_riders_closing_on_one_runner_turn_off_each_other_not_through() -> void:
	var p := _unit(3)
	var r: float = p.soldier_body_radius()
	p._sim_soldier_pos[0] = AT
	p._sim_soldier_pos[1] = AT + Vector2(r, 0)    # pressed half a body into him
	p._sim_soldier_pos[2] = AT + Vector2(0, 10.0 * r)   # well clear of both
	var clear: PackedVector2Array = SoldierKeepClear.bias(p, 3, 100.0)
	assert_almost_eq(clear[0], Vector2(-50.0, 0.0), Vector2(0.001, 0.001), "away from his friend, half his pace")
	assert_almost_eq(clear[1], Vector2(50.0, 0.0), Vector2(0.001, 0.001), "and the friend away from him")
	assert_eq(clear[2], Vector2.ZERO, "a rider no friend touches rides on unturned")
	p._sim_soldier_pos[1] = AT   # two on one spot still part
	clear = SoldierKeepClear.bias(p, 3, 100.0)
	assert_almost_eq(clear[0].length(), 100.0, 0.001, "at his full pace")
	assert_almost_eq((clear[0] + clear[1]).length(), 0.0, 0.001, "each the other's way")
