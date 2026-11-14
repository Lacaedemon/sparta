extends GutTest
## SoldierRally: riders a chase left scattered rally on their standard, each to his place beside
## the man he rallies on, and the troop moves off once its ilarch sees it formed on him.

const AT := Vector2(800, 800)
const DT := 1.0 / 60.0


func _troop(count: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	u.is_cavalry = true
	add_child_autofree(u)
	u.position = AT
	u.facing = Vector2.UP
	u.seed_sim_soldiers()
	return u


func _offsets(u: Unit) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in u.soldier_world_slots(u.soldiers):
		out.push_back((p - u.position).rotated(-u.soldier_block_world_angle()))
	return out


func test_each_man_rallies_on_the_man_ahead_in_his_file_and_the_front_on_the_ilarch() -> void:
	var u := _troop(12)
	var n: int = u._sim_soldier_pos.size()
	SoldierRally.begin(u, n)
	var on: PackedInt32Array = u._sim_rally_on
	var off := _offsets(u)
	var ilarch: int = on.find(-1)
	assert_eq(on.count(-1), 1, "one ilarch")
	for i in range(n):
		assert_true(off[ilarch].y <= off[i].y + 0.01, "the ilarch stands in the front rank (%d)" % i)
	for i in range(n):
		if i == ilarch or on[i] == ilarch:
			continue
		assert_almost_eq(off[on[i]].x, off[i].x, u.file_pitch_wu() * 0.5, "the man he rallies on is in his file")
		assert_lt(off[on[i]].y, off[i].y, "and ahead of him")
	u.chase_rally = SoldierRally.Mode.ILARCH
	SoldierRally.begin(u, n)
	for i in range(n):
		if u._sim_rally_on[i] != -1:
			assert_eq(u._sim_rally_on[i], ilarch, "under ILARCH every man rallies on the ilarch")


func test_scattered_riders_form_on_the_ilarch_and_the_troop_moves_off() -> void:
	var u := _troop(12)
	var n: int = u._sim_soldier_pos.size()
	SoldierRally.begin(u, n)
	var ilarch: int = u._sim_rally_on.find(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(n):   # scatter them over a few hundred wu, still riding
		u._sim_soldier_pos[i] = AT + Vector2(rng.randf_range(-250, 250), rng.randf_range(-250, 250))
		u._sim_body_vel[i] = Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
	u._sim_body_vel[ilarch] = Vector2.ZERO
	var start: Vector2 = u._sim_soldier_pos[ilarch]
	var ticks := 0
	while SoldierRally.step(u, n, DT) and ticks < 1800:
		ticks += 1
	assert_lt(ticks, 1800, "the troop forms on its ilarch and moves off (%d ticks)" % ticks)
	assert_false(SoldierRally.is_rallying(u), "and is no longer rallying")
	assert_lt(u._sim_soldier_pos[ilarch].distance_to(start), 2.0 * u.file_pitch_wu(),
			"the ilarch held his ground, give or take the riders who came up against him")
	var off := _offsets(u)
	var turn: float = u._sim_soldier_facing[ilarch].angle() + PI * 0.5
	for i in range(n):
		var place: Vector2 = u._sim_soldier_pos[ilarch] + (off[i] - off[ilarch]).rotated(turn)
		assert_lt(u._sim_soldier_pos[i].distance_to(place), 2.0 * u.file_pitch_wu() * u.standoff_off_slot_pitches * 3.0,
				"each man stands near his place in the troop (%d)" % i)


func test_a_rider_whose_place_is_behind_him_reins_in_rather_than_circling() -> void:
	var u := _troop(2)
	SoldierRally.begin(u, 2)
	var ilarch: int = u._sim_rally_on.find(-1)
	var other: int = 1 - ilarch
	u._sim_soldier_pos[ilarch] = AT
	u._sim_soldier_facing[ilarch] = Vector2.UP
	u._sim_soldier_pos[other] = AT + Vector2(0, -400)   # well past his place, ahead of the ilarch
	u._sim_body_vel[other] = Vector2(0, -150)   # galloping on away from it
	SoldierRally.step(u, 2, DT)
	assert_lt(u._sim_body_vel[other].length(), 150.0, "he slows to turn back")
	assert_lt(u._sim_body_vel[other].y, 0.0 + 1e-3, "rather than wheeling at the gallop")
