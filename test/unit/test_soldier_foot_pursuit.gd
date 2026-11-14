extends GutTest
## SoldierFootPursuit: under SHORT a foot unit breaks off a routed target once the runners are out
## of its reach; under FOLLOW (the default) it follows on, and horse always ride the rout down.

const AT := Vector2(500, 500)


func _unit(team: int, count: int, at: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	u.team = team
	add_child_autofree(u)
	u.position = at
	u.seed_sim_soldiers()
	return u


func _foot_after_a_rout() -> Array:
	var r := _unit(1, 4, AT + Vector2(0, -100))   # within the block's detection range
	r._rout()
	var f := _unit(0, 12, AT)
	f.target_enemy = r
	f._in_enemy_contact = false
	return [f, r]


func test_foot_follow_a_rout_by_default() -> void:
	var pair: Array = _foot_after_a_rout()
	assert_eq(pair[0].foot_pursuit, SoldierFootPursuit.Mode.FOLLOW, "FOLLOW is the default")
	assert_eq(UnitTargeting.current_target(pair[0]), pair[1], "it keeps after the runners")


func test_under_short_foot_break_off_once_the_runners_are_out_of_reach() -> void:
	var pair: Array = _foot_after_a_rout()
	var f: Unit = pair[0]
	f.foot_pursuit = SoldierFootPursuit.Mode.SHORT
	f._in_enemy_contact = true
	assert_eq(UnitTargeting.current_target(f), pair[1], "in reach of them it fights on")
	f._in_enemy_contact = false
	assert_null(UnitTargeting.current_target(f), "out of reach it breaks off")
	assert_null(f.target_enemy, "and takes up no routed unit again")
	f.target_enemy = pair[1]
	f.is_cavalry = true
	assert_eq(UnitTargeting.current_target(f), pair[1], "horse ride the rout down whatever the reading")

