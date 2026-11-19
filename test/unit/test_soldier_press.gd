extends GutTest
## SoldierPress and SoldierTouch: which men of a block stand within reach of an enemy man who
## fights, and which men's bodies touch a foe.

const AT := Vector2(500, 500)


func _unit(team: int, at: Vector2, count: int = 1) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
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
	ours.target_enemy = foe
	foe.target_enemy = _unit(0, AT + Vector2(5000, 0))
	foe.state = Unit.State.FIGHTING
	assert_false(_pressed(ours), "fighting in name but touching no one, he presses no one")
	foe._sim_touching_foe = PackedByteArray([1])   # as SoldierTouch marks him
	assert_true(_pressed(ours), "touching a foe body, he fights, whichever block he touches")
	foe._sim_soldier_pos[0] = AT + Vector2(2.0 * ours.soldier_reach() + 5.0, 0)
	assert_false(_pressed(ours), "past twice the reach he presses no one")


func test_a_running_man_presses_no_one_even_touching_a_foe() -> void:
	var ours := _unit(0, AT)
	var foe := _unit(1, AT + Vector2(ours.soldier_body_radius(), 0))
	foe._sim_touching_foe = PackedByteArray([1])
	foe._sim_flight_dir = PackedVector2Array([Vector2.RIGHT])
	assert_false(_pressed(ours), "running, he fights no one")
	foe._sim_flight_dir[0] = Vector2.ZERO
	assert_true(_pressed(ours), "standing his ground, he does")
	foe._sim_soldier_hp[0] = 0.0
	assert_false(_pressed(ours), "a dead man presses no one")


func test_touch_marks_every_man_whose_body_touches_a_foe_wherever_he_stands() -> void:
	var ours := _unit(0, AT, 3)
	var r: float = ours.soldier_body_radius()
	ours._sim_soldier_pos[1] = AT + Vector2(0, 40)   # a rear-rank man, at the block's back
	ours._sim_soldier_pos[2] = AT + Vector2(-40, 0)   # a flank-file man
	var foe := _unit(1, AT + Vector2(-40 - 1.5 * r, 0))   # body to body with the flank man
	var behind := _unit(1, AT + Vector2(0, 40 + 2.5 * r))   # two radii and a half off the rear man
	ours._sim_touching_foe = PackedByteArray([1, 1, 1])   # stale marks the pass must clear
	SoldierTouch.mark([ours, foe, behind])
	assert_eq(ours._sim_touching_foe, PackedByteArray([0, 0, 1]),
		"the flank man touching a foe is marked, whatever the state of his block; no one else")
	assert_eq(foe._sim_touching_foe, PackedByteArray([1]), "and so is the foe he touches")
	assert_eq(behind._sim_touching_foe, PackedByteArray([0]), "a man past the two radii is not")


func test_touch_marks_a_cornered_router_standing_against_a_foe() -> void:
	var router := _unit(0, AT)
	router._rout()
	router._sim_flight_dir = PackedVector2Array([Vector2.ZERO])   # standing to fight
	var foe := _unit(1, AT + Vector2(router.soldier_body_radius(), 0))
	SoldierTouch.mark([router, foe])
	assert_eq(router._sim_touching_foe, PackedByteArray([1]), "a cornered router is marked")
	var ours := _unit(1, AT + Vector2(1.5 * router.soldier_reach(), 0))
	assert_true(_pressed(ours), "and, standing, he presses a block near him")
	router._sim_soldier_hp[0] = 0.0
	SoldierTouch.mark([router, foe])
	assert_eq(router._sim_touching_foe, PackedByteArray([0]), "a dead man touches no one")


func test_touch_leaves_a_unit_with_no_enemy_near_unmarked() -> void:
	var lone := _unit(0, AT)
	lone._sim_touching_foe = PackedByteArray([1])   # a stale mark
	var far := _unit(1, AT + Vector2(5000, 0))
	SoldierTouch.mark([lone, far])
	assert_true(lone._sim_touching_foe.is_empty(), "the stale mark is cleared")


func test_reap_trims_the_touching_marks_with_the_bodies() -> void:
	var u := _unit(0, AT, 3)
	u._sim_touching_foe = PackedByteArray([1, 0, 1])
	u._sim_soldier_hp[1] = 0.0
	SoldierMelee.reap(u, null)
	assert_eq(u._sim_touching_foe, PackedByteArray([1, 1]), "each survivor keeps his own mark")
