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


func test_two_pursuing_riders_touching_give_way_to_each_other_at_once() -> void:
	var r: Unit = _unit(1)
	r.team = 0
	r._sim_soldier_pos[0] = AT + Vector2(0, -1000)   # one runner far to the north
	r._rout()
	var p: Unit = _unit(2)
	p.team = 1
	p.is_cavalry = true
	p.target_enemy = r
	p.state = Unit.State.MOVING
	var gap: float = p.soldier_body_radius()   # half a body into each other
	p._sim_soldier_pos[0] = AT
	p._sim_soldier_pos[1] = AT + Vector2(gap, 0)
	SoldierPursuitStep.step(p, 2, {}, 1.0 / 60.0)
	assert_gt(p._sim_soldier_pos[1].x - p._sim_soldier_pos[0].x, gap,
			"they part sideways in the one tick, not only as fast as they can turn")
