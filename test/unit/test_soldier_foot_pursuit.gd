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


func test_a_foot_block_following_a_rout_takes_the_contact_band() -> void:
	var pair: Array = _foot_after_a_rout()
	var f: Unit = pair[0]
	f.state = Unit.State.MOVING
	assert_true(SoldierFootPursuit.follows_rout(f), "a foot block after a routed target follows it")
	var pitch: float = minf(f.file_pitch_wu(), f.rank_pitch_wu())
	var min_sep: float = SoldierBodies.STANDOFF_MIN_SEP_FRAC * minf(2.0 * f.soldier_body_radius(), pitch)
	var far := PackedVector2Array()
	for i in range(12):
		far.push_back(AT + Vector2(0, 500 + 40 * i))   # every man off his place
	var apart := AT + Vector2(2000, 0)   # clear of the rest of the block
	f._sim_soldier_pos[0] = apart
	# Just inside the contact band, where the overlap push alone is under the per-man cap.
	f._sim_soldier_pos[1] = apart + Vector2(0.9 * SoldierBodies.STANDOFF_CONTACT_SEP_FRAC * min_sep, 0)
	f._sim_body_vel[0] = Vector2(8.0, 0)   # walking into each other
	f._sim_body_vel[1] = Vector2(-8.0, 0)
	var with_band: PackedVector2Array = SoldierBodies._separate_same_unit(f, 12, far, PackedByteArray(), 1.0 / 60.0)
	f.target_enemy = null
	assert_false(SoldierFootPursuit.follows_rout(f), "with no routed target it follows nothing")
	var without: PackedVector2Array = SoldierBodies._separate_same_unit(f, 12, far, PackedByteArray(), 1.0 / 60.0)
	assert_gt(with_band[0].dot(Vector2.LEFT), without[0].dot(Vector2.LEFT),
		"following the rout, the pair's closing is cancelled as well as the overlap pushed")
	f.target_enemy = pair[1]
	f.is_cavalry = true
	assert_false(SoldierFootPursuit.follows_rout(f), "horse ride a rout down man by man instead")
