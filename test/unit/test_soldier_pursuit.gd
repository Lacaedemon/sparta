extends GutTest
## SoldierPursuitStep: a unit riding a router down sends each man after the runner nearest him,
## not after the routed unit's centre, and strikes the runners its men reach.

const TICK := 1.0 / 60.0
const AT := Vector2(500, 500)


func _unit(team: int, count: int, at: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	u.team = team
	add_child_autofree(u)
	u.position = at
	u.seed_sim_soldiers()
	return u


## A two-man router split wide, its centre empty, and a one-man pursuer below its west runner.
func _split_rout() -> Array:
	var r := _unit(0, 2, AT)
	r._sim_soldier_pos[0] = AT + Vector2(-300, 0)
	r._sim_soldier_pos[1] = AT + Vector2(300, 0)
	r._rout()
	var p := _unit(1, 1, AT + Vector2(-300, 200))
	p._sim_soldier_pos[0] = AT + Vector2(-300, 200)
	p.target_enemy = r
	p.state = Unit.State.MOVING
	return [r, p]


func test_a_unit_after_a_router_is_pursuing() -> void:
	var pair: Array = _split_rout()
	var p: Unit = pair[1]
	assert_true(SoldierPursuitStep.is_pursuing(p), "on the move after a router")
	p.state = Unit.State.IDLE
	assert_false(SoldierPursuitStep.is_pursuing(p), "not standing")
	p.state = Unit.State.MOVING
	pair[0].state = Unit.State.IDLE
	assert_false(SoldierPursuitStep.is_pursuing(p), "nor after a unit that is not routing")


func test_each_rider_rides_at_the_runner_nearest_him_not_the_routed_unit_s_centre() -> void:
	var pair: Array = _split_rout()
	var p: Unit = pair[1]
	p._sim_flight_dir = PackedVector2Array([Vector2.RIGHT])   # his last look sent him east
	for _k in range(p.rout_reaction_ticks() + 1):   # a tick of his own to look round comes up
		await get_tree().physics_frame
		SoldierPursuitStep.step(p, 1, {}, TICK)
		p._sim_soldier_pos[0] = AT + Vector2(-300, 200)   # hold him where he stood
	assert_almost_eq(p._sim_flight_dir[0].x, 0.0, 0.0001, "straight at the west runner above him")
	assert_almost_eq(p._sim_flight_dir[0].y, -1.0, 0.0001, "not toward the empty centre to his east")
	assert_lt(p._sim_body_vel[0].y, 0.0, "and he rides off after him")


func test_riders_strike_the_runners_within_reach_while_on_the_move() -> void:
	var pair: Array = _split_rout()
	var r: Unit = pair[0]
	var p: Unit = pair[1]
	p._sim_soldier_pos[0] = r._sim_soldier_pos[0] + Vector2(0, 10)
	p.facing = Vector2.UP
	p._sim_soldier_facing[0] = Vector2.UP   # he faces the runner he has caught
	var before: float = r._sim_soldier_hp[0] + r._sim_soldier_hp[1]
	var struck: bool = false
	for _k in range(40):
		struck = SoldierPursuitStep.strike(p) or struck
	assert_true(struck, "a rider on the move among the runners strikes")
	var after: float = 0.0
	for hp in r._sim_soldier_hp:   # a runner cut down is reaped out of the arrays
		after += hp
	assert_lt(after, before, "and his blows land")
	p.state = Unit.State.FIGHTING
	assert_false(SoldierPursuitStep.strike(p), "once FIGHTING, the unit's own strike takes over")
