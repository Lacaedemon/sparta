extends GutTest
## SoldierPress: which men of a block stand within reach of an enemy man who fights.

const AT := Vector2(500, 500)


func _unit(team: int, at: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 1
	add_child_autofree(u)
	u.team = team
	u.position = at
	u.seed_sim_soldiers()
	u._sim_soldier_pos[0] = at
	return u


func _pressed(unit: Unit) -> bool:
	SoldierPress.reset()
	var want := PackedByteArray([1])
	return SoldierPress.mask(unit, want, 2.0 * unit.soldier_reach())[0] == 1


func test_a_foe_man_body_to_body_with_another_block_does_not_press_this_one() -> void:
	var ours := _unit(0, AT)
	var r: float = ours.soldier_body_radius()
	var gap: float = 1.5 * ours.soldier_reach()   # within twice the reach of ours, not touching
	var other := _unit(0, AT + Vector2(gap + r, 0))
	var foe := _unit(1, AT + Vector2(gap, 0))
	assert_false(_pressed(ours), "a foe man touching a man of another block fights that block")
	other._sim_soldier_pos[0] = AT + Vector2(5000, 0)
	ours.target_enemy = foe
	foe.target_enemy = other
	assert_false(_pressed(ours), "nor does this block's aim, or his, make him fight it")
	foe._sim_soldier_pos[0] = AT + Vector2(r, 0)
	assert_true(_pressed(ours), "touching a man of this block, he presses it")


func test_an_engaged_foe_man_presses_whichever_block_is_near_him() -> void:
	var ours := _unit(0, AT)
	var foe := _unit(1, AT + Vector2(1.5 * ours.soldier_reach(), 0))
	var other := _unit(0, AT + Vector2(5000, 0))
	foe.target_enemy = other
	foe.state = Unit.State.FIGHTING
	foe.engaged_soldier_indices(1)   # as its melee picks them, each tick it fights
	assert_true(_pressed(ours), "a man of a fight with another block still fights, near this one")
	foe._sim_soldier_pos[0] = AT + Vector2(2.0 * ours.soldier_reach() + 5.0, 0)
	assert_false(_pressed(ours), "past twice the reach he presses no one")
	foe._sim_soldier_pos[0] = AT + Vector2(1.5 * ours.soldier_reach(), 0)
	foe.state = Unit.State.IDLE
	foe.engaged_soldier_indices(1)
	assert_false(_pressed(ours), "out of the fight and out of touch, he presses no one")


func test_a_running_man_presses_no_one_even_body_to_body() -> void:
	var ours := _unit(0, AT)
	var foe := _unit(1, AT + Vector2(ours.soldier_body_radius(), 0))
	foe._sim_flight_dir = PackedVector2Array([Vector2.RIGHT])
	assert_false(_pressed(ours), "running, he fights no one")
	foe._sim_flight_dir[0] = Vector2.ZERO
	assert_true(_pressed(ours), "standing his ground, he does")


func test_a_dead_foe_man_presses_no_one() -> void:
	var ours := _unit(0, AT)
	var foe := _unit(1, AT + Vector2(ours.soldier_body_radius(), 0))
	foe._sim_soldier_hp[0] = 0.0
	assert_false(_pressed(ours), "a dead man presses no one")
