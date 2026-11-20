extends GutTest
## SoldierTakeUp: a horse unit's riders take up a chase only when one of them has a man of a
## ROUTING foe within his reach; a foe that has not broken, or a routed man farther off, starts
## none.

const AT := Vector2(500, 500)


func _unit(team: int, at: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 1
	u.team = team
	add_child_autofree(u)
	u.position = at
	u.seed_sim_soldiers()
	u._sim_soldier_pos[0] = at
	return u


func _rider() -> Unit:
	var p := _unit(1, AT)
	p.is_cavalry = true
	p.state = Unit.State.MOVING
	return p


func _take_up(p: Unit, foe: Unit) -> void:
	await get_tree().physics_frame   # a new tick, so the spreads and perception are read afresh
	SoldierFlight.prepare(Engine.get_physics_frames(), [p, foe], [], null)
	SoldierTakeUp.take_up(p, 1)


func test_a_foe_that_has_not_broken_starts_no_chase() -> void:
	var p := _rider()
	var foe := _unit(0, AT + Vector2(0.5 * p.soldier_reach(), 0))
	foe.state = Unit.State.FIGHTING
	await _take_up(p, foe)
	assert_true(p._sim_chase_dir.is_empty(), "a man in his reach who has not broken is no quarry")


func test_a_routed_man_just_out_of_reach_starts_no_chase() -> void:
	var p := _rider()
	var foe := _unit(0, AT + Vector2(1.5 * p.soldier_reach(), 0))
	foe._rout()
	foe.position = foe._sim_soldier_pos[0]
	assert_eq(SoldierCornered.foes_near(p, p.position,
			p.soldier_reach() + SoldierCornered._spread(p)).size(), 1,
			"sanity: the routed unit is near enough to be weighed")
	await _take_up(p, foe)
	assert_true(p._sim_chase_dir.is_empty(), "his one man is beyond the rider's reach")
	foe._sim_soldier_pos[0] = AT + Vector2(0.5 * p.soldier_reach(), 0)
	foe.position = foe._sim_soldier_pos[0]
	await _take_up(p, foe)
	assert_true(SoldierPursuitStep.is_pursuing(p), "within his reach, the rider takes up the chase")
