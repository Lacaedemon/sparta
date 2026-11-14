extends GutTest
## SoldierBodies.standoff_free: men who run free of any slot (a pursuing rider, a rallied man
## pulling up) keep off the men of their own unit by the same body contact as men in ranks.

const AT := Vector2(500, 500)
const DT := 1.0 / 60.0


func _unit(count: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = AT
	u.seed_sim_soldiers()
	return u


func _rider_after(runner_at: Vector2, count: int) -> Unit:
	var r: Unit = _unit(1)
	r.team = 0
	r._sim_soldier_pos[0] = runner_at
	r._rout()
	var p: Unit = _unit(count)
	p.team = 1
	p.is_cavalry = true
	p.target_enemy = r
	p.state = Unit.State.MOVING
	return p


func test_a_pressed_pair_is_pushed_apart_and_a_clear_man_is_not() -> void:
	var p := _unit(3)
	var r: float = p.soldier_body_radius()
	p._sim_soldier_pos[0] = AT
	p._sim_soldier_pos[1] = AT + Vector2(r, 0)    # pressed half a body into him
	p._sim_soldier_pos[2] = AT + Vector2(0, 10.0 * r)   # well clear of both
	var push: PackedVector2Array = SoldierBodies.standoff_free(p, 3, 1000.0)
	assert_lt(push[0].x, 0.0, "away from his friend")
	assert_almost_eq(push[0] + push[1], Vector2.ZERO, Vector2(0.001, 0.001), "and the friend equally away")
	assert_eq(push[2], Vector2.ZERO, "a man no friend touches is left alone")
	p._sim_soldier_pos[1] = AT   # two on one spot still part
	push = SoldierBodies.standoff_free(p, 3, 1000.0)
	assert_gt(push[0].length(), 0.0, "two on one spot are pushed apart too")
	assert_almost_eq((push[0] + push[1]).length(), 0.0, 0.001, "each the other's way")
	assert_eq(SoldierBodies.standoff_free(p, 1, 1000.0).size(), 0, "one man has nobody to touch")


func test_a_closing_pair_inside_the_contact_band_has_its_closing_cancelled() -> void:
	var p := _unit(2)
	var r: float = p.soldier_body_radius()
	p._sim_soldier_pos[0] = AT
	p._sim_soldier_pos[1] = AT + Vector2(0.4 * r, 0)   # inside the contact band
	p._sim_body_vel[0] = Vector2(300.0, 0)   # riding into each other at a gallop
	p._sim_body_vel[1] = Vector2(-300.0, 0)
	var push: PackedVector2Array = SoldierBodies.standoff_free(p, 2, 1000.0)
	assert_lt(push[0].x, -300.0, "his closing is cancelled, not only the overlap pushed")
	var capped: PackedVector2Array = SoldierBodies.standoff_free(p, 2, 50.0)
	assert_almost_eq(capped[0].length(), 50.0, 0.001, "no more than the cap a man is given")


func test_the_contact_wins_over_a_mans_own_drive_under_the_cap() -> void:
	var shove := Vector2(0, 60)
	assert_eq(SoldierBodies.with_contact(Vector2(50, 0), shove, 200.0), Vector2(50, 60),
		"under the cap the two simply add")
	var got: Vector2 = SoldierBodies.with_contact(Vector2(180, 0), shove, 180.0)
	assert_almost_eq(got.length(), 180.0, 0.001, "over it the sum meets the cap")
	assert_almost_eq(got.y, 60.0, 0.001, "with the whole shove kept")
	assert_lt(got.x, 180.0, "and his own drive cut back")
	assert_eq(SoldierBodies.with_contact(Vector2(10, 0), Vector2(0, 300), 100.0), Vector2(0, 100),
		"a shove past the cap alone is held to it")


func test_riders_galloping_head_on_do_not_ride_through_each_other() -> void:
	var p: Unit = _rider_after(AT + Vector2(0, -1000), 2)
	var two: float = 2.0 * p.soldier_body_radius()
	p._sim_soldier_pos[0] = AT + Vector2(-3.0 * two, 0)
	p._sim_soldier_pos[1] = AT + Vector2(3.0 * two, 0)
	p._sim_body_vel[0] = Vector2(p.move_speed, 0)
	p._sim_body_vel[1] = Vector2(-p.move_speed, 0)
	var closest: float = INF
	for t in range(60):
		SoldierPursuitStep.step(p, 2, {}, DT)
		closest = minf(closest, p._sim_soldier_pos[0].distance_to(p._sim_soldier_pos[1]))
	assert_gt(closest, two * 0.25, "they never come within a quarter of two bodies (%.2f)" % closest)


func test_two_pursuing_riders_touching_part() -> void:
	var p: Unit = _rider_after(AT + Vector2(0, -1000), 2)
	var gap: float = p.soldier_body_radius()   # half a body into each other
	p._sim_soldier_pos[0] = AT
	p._sim_soldier_pos[1] = AT + Vector2(gap, 0)
	SoldierPursuitStep.step(p, 2, {}, DT)
	assert_gt(p._sim_soldier_pos[1].x - p._sim_soldier_pos[0].x, gap, "they part sideways")


func test_men_pulling_up_part_from_a_friend_they_touch() -> void:
	var u: Unit = _unit(2)
	u._rout()
	u._rally()   # its men pull up on their own
	var gap: float = u.soldier_body_radius()
	u._sim_soldier_pos[0] = AT
	u._sim_soldier_pos[1] = AT + Vector2(gap, 0)
	u._sim_body_vel[0] = Vector2(0, -u.jog_speed * 2.0)   # both still running north
	u._sim_body_vel[1] = Vector2(0, -u.jog_speed * 2.0)
	assert_true(SoldierBodies.pull_up_rallied(u, 2, 60.0, DT), "setup: still running")
	assert_gt(u._sim_soldier_pos[1].x - u._sim_soldier_pos[0].x, gap, "they part sideways as they slow")
	assert_almost_eq(u._sim_body_vel[1].x, 0.0, 0.001, "the contact moves him, his run is his own")


func test_a_unit_left_standing_when_its_chase_ends_pulls_up_first() -> void:
	var p: Unit = _rider_after(AT + Vector2(0, -1000), 2)
	SoldierPursuitStep.step(p, 2, {}, DT)
	p.state = Unit.State.IDLE   # its quarry is gone and it has nowhere to go
	p.step_sim_soldiers(DT)
	assert_true(p._rally_pending, "its riders pull up from the gallop before it forms up")
	assert_true(p._sim_flight_dir.is_empty(), "with no chase left to remember")
