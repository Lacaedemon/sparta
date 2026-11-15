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


func test_a_foe_man_touching_a_foe_body_presses_whoever_is_near_him() -> void:
	var ours := _unit(0, AT)
	var foe := _unit(1, AT + Vector2(1.5 * ours.soldier_reach(), 0))
	var other := _unit(0, AT + Vector2(5000, 0))
	ours.target_enemy = foe
	foe.target_enemy = other
	assert_false(_pressed(ours), "not engaged and touching no one, he fights no one")
	foe._sim_touching_foe = PackedByteArray([1])   # as the enemy body-contact pass marks him
	assert_true(_pressed(ours), "touching a foe body, he fights, whichever block he touches")
	foe._sim_soldier_pos[0] = AT + Vector2(2.0 * ours.soldier_reach() + 5.0, 0)
	assert_false(_pressed(ours), "past twice the reach he presses no one")


func test_an_engaged_foe_man_presses_whichever_block_is_near_him() -> void:
	var ours := _unit(0, AT)
	var foe := _unit(1, AT + Vector2(1.5 * ours.soldier_reach(), 0))
	foe.target_enemy = _unit(0, AT + Vector2(5000, 0))
	foe.state = Unit.State.FIGHTING
	foe.engaged_soldier_indices(1)   # as its melee picks them, each tick it fights
	assert_true(_pressed(ours), "a man of a fight with another block still fights, near this one")
	foe._sim_soldier_pos[0] = AT + Vector2(2.0 * ours.soldier_reach() + 5.0, 0)
	assert_false(_pressed(ours), "past twice the reach he presses no one")
	foe._sim_soldier_pos[0] = AT + Vector2(1.5 * ours.soldier_reach(), 0)
	foe.state = Unit.State.IDLE
	foe.engaged_soldier_indices(1)
	assert_false(_pressed(ours), "out of the fight and out of touch, he presses no one")


func test_a_running_man_presses_no_one_even_touching_a_foe() -> void:
	var ours := _unit(0, AT)
	var foe := _unit(1, AT + Vector2(ours.soldier_body_radius(), 0))
	foe._sim_touching_foe = PackedByteArray([1])
	foe._sim_flight_dir = PackedVector2Array([Vector2.RIGHT])
	assert_false(_pressed(ours), "running, he fights no one")
	foe._sim_flight_dir[0] = Vector2.ZERO
	assert_true(_pressed(ours), "standing his ground, he does")


func test_a_dead_foe_man_presses_no_one() -> void:
	var ours := _unit(0, AT)
	var foe := _unit(1, AT + Vector2(ours.soldier_body_radius(), 0))
	foe._sim_touching_foe = PackedByteArray([1])
	foe._sim_soldier_hp[0] = 0.0
	assert_false(_pressed(ours), "a dead man presses no one")


func test_the_contact_pass_marks_the_men_whose_bodies_touch_a_foe() -> void:
	var ours := _unit(0, AT)
	var foe := _unit(1, AT + Vector2(0.5 * ours.soldier_body_radius(), 0))
	var far := _unit(1, AT + Vector2(5000, 0))
	for k in range(3):
		var u: Unit = [ours, foe, far][k]
		u.uid = 70 + k   # distinct soldier ids, as a battle gives them
		u.state = Unit.State.FIGHTING
		u._sim_touching_foe = PackedByteArray([1])   # stale marks the pass must clear
	far.target_enemy = ours
	SoldierEnemyContact.accumulate([ours, foe, far], -Engine.get_physics_frames() - 7)
	assert_eq(ours._sim_touching_foe, PackedByteArray([1]), "a man pressed against a foe is marked")
	assert_eq(foe._sim_touching_foe, PackedByteArray([1]), "and so is the foe")
	assert_true(far._sim_touching_foe.is_empty() or far._sim_touching_foe[0] == 0,
		"a man touching no one is not")
