extends GutTest
## SoldierPursuitStep and SoldierTakeUp: horse take up a chase when a rider has a routed man in
## his reach, each rider rides at the nearest routed man he sees, of any routed foe, and the chase
## lasts while one still sees one; riders strike the routed men they reach.

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
	p.is_cavalry = true
	p.target_enemy = r
	p.state = Unit.State.MOVING
	return [r, p]


func test_riders_take_up_the_chase_with_a_routed_man_in_reach() -> void:
	var pair: Array = _split_rout()
	var p: Unit = pair[1]
	SoldierFlight.prepare(Engine.get_physics_frames(), pair, [], null)
	SoldierTakeUp.take_up(p, 1)
	assert_true(p._sim_chase_dir.is_empty(), "a runner 200 wu off is out of his reach")
	assert_false(SoldierPursuitStep.is_pursuing(p), "so he is not chasing")
	p._sim_soldier_pos[0] = pair[0]._sim_soldier_pos[0] + Vector2(0, 0.5 * p.soldier_reach())
	p.position = p._sim_soldier_pos[0]   # a unit's position reads its men
	await get_tree().physics_frame   # a new tick, so the spread and the perception are read again
	SoldierFlight.prepare(Engine.get_physics_frames(), pair, [], null)
	p.state = Unit.State.IDLE
	SoldierTakeUp.take_up(p, 1)
	assert_true(p._sim_chase_dir.is_empty(), "under no order to move or fight, no chase")
	p.state = Unit.State.MOVING
	p.is_cavalry = false
	SoldierTakeUp.take_up(p, 1)
	assert_true(p._sim_chase_dir.is_empty(), "foot follow a rout in their ranks")
	p.is_cavalry = true
	SoldierTakeUp.take_up(p, 1)
	assert_true(SoldierPursuitStep.is_pursuing(p), "a runner in his reach: he takes up the chase")
	p._sim_chase_dir[0] = Vector2.ZERO
	assert_false(SoldierPursuitStep.is_pursuing(p), "a rider who sees no runner chases no one")


func test_the_chase_goes_on_after_his_unit_s_target_rallies_while_he_sees_another() -> void:
	var pair: Array = _split_rout()
	var p: Unit = pair[1]
	var other := _unit(0, 1, AT + Vector2(-200, 200))   # a second routed foe, not his unit's target
	other._sim_soldier_pos[0] = AT + Vector2(-200, 200)
	other._rout()
	pair[0].state = Unit.State.IDLE   # his unit's target rallies
	p._sim_chase_dir = PackedVector2Array([Vector2.UP])
	await _ride_one_look(p, [pair[0], p, other])
	assert_almost_eq(p._sim_chase_dir[0], Vector2.RIGHT, Vector2(0.0001, 0.0001),
		"he rides on at the runner he still sees")
	assert_true(SoldierPursuitStep.is_pursuing(p), "and the chase goes on")
	other.state = Unit.State.IDLE   # that one rallies too: he sees no runner
	await _ride_one_look(p, [pair[0], p, other])
	assert_eq(p._sim_chase_dir[0], Vector2.ZERO, "seeing none, he stops")
	assert_false(SoldierPursuitStep.is_pursuing(p), "and the chase is over")


## Step rider unit `p` through one look-round, with the men of `units` in play, every man held
## where he stood and every unit in its state (a bare router runs and rallies on its own).
func _ride_one_look(p: Unit, units: Array) -> void:
	var held: Array = units.map(func(u: Unit) -> Array: return [u._sim_soldier_pos.duplicate(),
			u.state])
	for k in range(p.rout_reaction_ticks() + 1):   # a tick of his own to look round comes up
		await get_tree().physics_frame
		for m in range(units.size()):
			(units[m] as Unit)._sim_soldier_pos = held[m][0]
			(units[m] as Unit).state = held[m][1]
		SoldierFlight.tick = k
		SoldierFlight.prepare(Engine.get_physics_frames(), units, [], null)
		SoldierPursuitStep.step(p, 1, {}, TICK)
		p._sim_soldier_pos[0] = AT + Vector2(-300, 200)   # hold him where he stood


func test_each_rider_rides_at_the_runner_nearest_him_not_the_routed_unit_s_centre() -> void:
	var pair: Array = _split_rout()
	var p: Unit = pair[1]
	p._sim_chase_dir = PackedVector2Array([Vector2.RIGHT])   # his last look sent him east
	await _ride_one_look(p, pair)
	assert_almost_eq(p._sim_chase_dir[0].x, 0.0, 0.0001, "straight at the west runner above him")
	assert_almost_eq(p._sim_chase_dir[0].y, -1.0, 0.0001, "not toward the empty centre to his east")
	assert_lt(p._sim_body_vel[0].y, 0.0, "and he rides off after him")
	assert_true(p._sim_flight_dir.is_empty(), "a rider is not a running man (SoldierPress)")


func test_a_rider_rides_at_the_nearest_routed_man_of_any_routed_foe() -> void:
	var pair: Array = _split_rout()
	var p: Unit = pair[1]
	var other := _unit(0, 1, AT + Vector2(-200, 200))   # a second routed foe, not his unit's target
	other._sim_soldier_pos[0] = AT + Vector2(-200, 200)
	other._rout()
	var standing := _unit(0, 1, AT + Vector2(-300, 230))   # a foe in good order, nearer still
	standing._sim_soldier_pos[0] = AT + Vector2(-300, 230)
	p._sim_chase_dir = PackedVector2Array([Vector2.UP])
	await _ride_one_look(p, [pair[0], p, other, standing])
	assert_almost_eq(p._sim_chase_dir[0], Vector2.RIGHT, Vector2(0.0001, 0.0001),
		"at the routed man of the other routed foe, nearest him; the formed foe is no runner")


func test_riders_strike_the_runners_within_reach_while_on_the_move() -> void:
	var pair: Array = _split_rout()
	var r: Unit = pair[0]
	var p: Unit = pair[1]
	p._sim_soldier_pos[0] = r._sim_soldier_pos[0] + Vector2(0, 10)
	p.facing = Vector2.UP
	p._sim_soldier_facing[0] = Vector2.UP   # he faces the runner he has caught
	var before: float = r._sim_soldier_hp[0] + r._sim_soldier_hp[1]
	p._sim_chase_dir = PackedVector2Array([Vector2.UP])   # he rides at the runner
	var struck: bool = false
	for _k in range(40):
		struck = SoldierPursuitStep.strike(p) or struck
	assert_true(struck, "a rider on the move among the runners strikes")
	var other := _unit(0, 1, p._sim_soldier_pos[0] + Vector2(10, 0))   # a routed foe not his target
	other._sim_soldier_pos[0] = p._sim_soldier_pos[0] + Vector2(10, 0)
	other._rout()
	var other_hp: float = other._sim_soldier_hp[0]
	for _k in range(80):
		SoldierPursuitStep.strike(p)
	assert_true(other._sim_soldier_pos.is_empty() or other._sim_soldier_hp[0] < other_hp,
		"he strikes the routed men of any routed foe in his reach")
	var after: float = 0.0
	for hp in r._sim_soldier_hp:   # a runner cut down is reaped out of the arrays
		after += hp
	assert_lt(after, before, "and his blows land")
	p.state = Unit.State.FIGHTING
	assert_false(SoldierPursuitStep.strike(p), "once FIGHTING, the unit's own strike takes over")


func test_a_rider_turns_onto_a_new_runner_at_his_pace_rather_than_pulling_up() -> void:
	var vel := Vector2(100, 0)
	var next: Vector2 = SoldierPursuitStep.ride(vel, Vector2(0, 170), 30.0, PI, TICK)
	assert_almost_eq(next.length(), 100.5, 0.001, "he keeps his pace, gaining at his own rate")
	assert_almost_eq(Vector2.RIGHT.angle_to(next), PI * TICK, 0.0001, "swinging at his turn rate")
	var halted: Vector2 = SoldierPursuitStep.ride(Vector2.ZERO, Vector2(0, 170), 30.0, PI, TICK)
	assert_almost_eq(halted, Vector2(0, 0.5), Vector2(0.0001, 0.0001),
		"from rest he sets off at once")
	var shoved: Vector2 = SoldierPursuitStep.ride(Vector2(-260, 0), Vector2(170, 0), 30.0, PI, TICK)
	assert_almost_eq(shoved, Vector2(-259.5, 0), Vector2(0.0001, 0.0001),
		"a shove is shed, not turned onto his line")


func test_a_unit_whose_chase_has_ended_forms_up_where_its_riders_stand() -> void:
	var pair: Array = _split_rout()
	var p: Unit = pair[1]
	SoldierFlight.prepare(Engine.get_physics_frames(), pair, [], null)   # this test's men in play
	SoldierPursuitStep.step(p, 1, {}, TICK)
	assert_eq(p._sim_chase_dir.size(), 1, "a rider in the chase remembers his line")
	p._sim_chase_dir[0] = Vector2.ZERO   # he looked round and saw no runner: the chase is over
	p.step_sim_soldiers(TICK)
	assert_true(p._sim_chase_dir.is_empty(), "nothing is left to remember")
	assert_eq(p._last_redeal_tick, Engine.get_physics_frames(),
			"and the unit re-forms where he stands")
