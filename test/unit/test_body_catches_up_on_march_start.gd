extends GutTest
## A man walking back to his slot as his block sets off. Two things decide whether he
## catches up: his velocity has to change faster than his slot's does while the march speeds
## up (SoldierBodies.march_accel_budget), and his arrival target must not swing round the
## instant the march begins (SoldierBodies.march_target_frac and arrival_target). These drive
## SoldierBodies.step directly, with the anchor marched by hand at the unit's own
## acceleration, so the march ramp is exactly the one _move_to gives a block from a standstill.

const TICK: float = 1.0 / 60.0


## A 30-man infantry block (the default type: accel 30 wu/s^2, walk 45 wu/s) facing DOWN,
## every body seeded on its slot at rest.
func _make_block() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 30
	add_child_autofree(u)
	u.position = Vector2(500, 500)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	return u


## March `u` straight ahead for `ticks` ticks from a standstill, its speed ramping at its own
## accel up to walk pace as _move_to ramps it, stepping the bodies each tick. Returns the
## distance from body `i` to its slot after each tick. `orderly` stands in for _move_to's own
## flag (Unit._body_march_orderly): true for a player move order, false for a pursuit or a
## charge.
func _set_off(u: Unit, i: int, ticks: int, orderly: bool = true) -> PackedFloat32Array:
	var dists := PackedFloat32Array()
	u.state = Unit.State.MOVING
	var speed: float = 0.0
	for _t in range(ticks):
		speed = minf(speed + u.accel * TICK, u.walk_speed)
		u._approach_velocity = u.facing * speed
		u._body_march_orderly = orderly
		u.position += u._approach_velocity * TICK
		SoldierBodies.step(u, TICK)
		var slot: Vector2 = u.soldier_world_slots(u.soldiers)[i]
		dists.append(u._sim_soldier_pos[i].distance_to(slot))
	return dists


func test_a_man_behind_his_slot_gains_on_it_while_the_block_sets_off() -> void:
	var u := _make_block()
	# The last body stands in the rear rank, so nobody behind him crowds his file lane, and he
	# is displaced straight back along his own file: no corridor detour applies to him, so
	# only how fast his velocity can change decides whether he closes on his slot.
	var i: int = u.soldiers - 1
	var gap: float = 20.0
	u._sim_soldier_pos[i] -= u.facing * gap
	u._sim_body_vel[i] = Vector2.ZERO
	# The ramp to walk pace takes walk_speed / accel = 1.5 s.
	var ticks: int = ceili(u.walk_speed / u.accel / TICK)
	var dists: PackedFloat32Array = _set_off(u, i, ticks)
	# At his slot's own acceleration he would only keep pace with it and stay ~20 wu behind
	# for the whole ramp; with the march's acceleration granted on top he closes on it.
	assert_lt(dists[dists.size() - 1], gap * 0.25,
		"the man %.1f wu behind his slot is within a quarter of that after the %.2f s ramp (%.2f wu)"
		% [gap, ticks * TICK, dists[dists.size() - 1]])
	var halfway: float = dists[ticks / 2]
	assert_lt(halfway, gap * 0.75,
		"he is already gaining halfway through the ramp (%.2f wu of %.1f)" % [halfway, gap])


func test_a_pursuit_or_charge_grants_no_share() -> void:
	# The same man on a march that is not an orderly one -- a pursuit, a charge, a combat
	# approach, a hasty move -- keeps the ordinary rate, so he only keeps pace with his slot
	# and the fights such a march closes into come out as they did before the share.
	var u := _make_block()
	var i: int = u.soldiers - 1
	var gap: float = 20.0
	u._sim_soldier_pos[i] -= u.facing * gap
	u._sim_body_vel[i] = Vector2.ZERO
	var ticks: int = ceili(u.walk_speed / u.accel / TICK)
	var dists: PackedFloat32Array = _set_off(u, i, ticks, false)
	assert_gt(dists[dists.size() - 1], gap * 0.75,
		"with no share he is still %.2f wu of %.1f behind after the ramp"
		% [dists[dists.size() - 1], gap])


func test_march_accel_budget_is_the_march_change_rate_capped_at_body_accel() -> void:
	var u := _make_block()
	var body_accel: float = maxf(u.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	u._body_march_ff_prev = Vector2(0, 10)
	assert_almost_eq(SoldierBodies.march_accel_budget(u, Vector2(0, 10), body_accel, TICK), 0.0, 1e-4,
		"a steady march grants nothing")
	assert_almost_eq(SoldierBodies.march_accel_budget(u, Vector2(0, 10.5), body_accel, TICK), 30.0, 1e-3,
		"a march gaining 0.5 wu/s in one tick grants 30 wu/s^2")
	assert_almost_eq(SoldierBodies.march_accel_budget(u, Vector2(0, 9.5), body_accel, TICK), 0.0, 1e-4,
		"a march that slows grants nothing")
	assert_almost_eq(SoldierBodies.march_accel_budget(u, Vector2(10, 0), body_accel, TICK), body_accel, 1e-4,
		"a march that turns sharply in one tick grants no more than the body's own acceleration")
	assert_almost_eq(SoldierBodies.march_accel_budget(u, Vector2(0, -50), body_accel, 0.0), 0.0, 1e-4,
		"a zero-length step grants nothing")


func test_an_engaged_body_takes_no_share_of_the_march_acceleration() -> void:
	# Engaged bodies take no march feed-forward, so the share would only let a fighting man
	# re-form faster than his own acceleration: two identical blocks, one engaged, step one
	# tick of a march ramp with a man displaced, and the engaged man moves as he would with
	# no ramp at all.
	var ramp := _make_block()
	var flat := _make_block()
	var front: PackedInt32Array = PackedInt32Array()
	for u in [ramp, flat]:
		u.state = Unit.State.FIGHTING
		u._engaged_linger = Unit.ENGAGED_LINGER
		front = u.body_tier_soldier_indices(u.soldiers)
		assert_false(front.is_empty(), "precondition: the fighting block has an engaged tier")
		# Shoved sideways along his own rank, so he stays in the front the tier selects.
		u._sim_soldier_pos[front[0]] += u.facing.orthogonal() * 20.0
		u._body_march_orderly = true
	var i: int = front[0]
	assert_true(ramp.body_tier_soldier_indices(ramp.soldiers).has(i),
		"precondition: the shoved man is still in the engaged tier")
	ramp._body_march_ff_prev = Vector2.ZERO
	ramp._approach_velocity = ramp.facing * 0.5
	flat._body_march_ff_prev = flat.facing * 0.5
	flat._approach_velocity = flat.facing * 0.5
	SoldierBodies.step(ramp, TICK)
	SoldierBodies.step(flat, TICK)
	assert_gt(flat._sim_body_vel[i].length(), 0.0, "precondition: he is walking back")
	assert_eq(ramp._sim_body_vel[i], flat._sim_body_vel[i],
		"the engaged man's velocity is the same whether or not the march is speeding up")


func test_his_arrival_target_does_not_jump_when_the_march_begins() -> void:
	var u := _make_block()
	var spacing: float = u.file_pitch_wu()
	var i: int = 0
	var slot: Vector2 = u._sim_soldier_pos[i]
	# Two pitches across files and two across ranks (2.83 pitches off): outside the standing
	# band, so standing he walks the perimeter corridor; inside the marching band, so on the
	# march he walks direct. That is the man whose target the march start used to swing.
	u._sim_soldier_pos[i] = slot + Vector2(spacing * 2.0, -spacing * 2.0)
	var direct: Vector2 = slot - u._sim_soldier_pos[i]
	u.state = Unit.State.MOVING
	u._approach_velocity = Vector2.ZERO
	var standing: Vector2 = SoldierBodies.arrival_target(u, i, slot, u.soldiers,
			SoldierBodies.march_target_frac(u), not u.is_turning())
	assert_gt(rad_to_deg(absf(standing.angle_to(direct))), 10.0,
		"precondition: standing, he is routed round the corridor, not sent direct")
	# The first tick of a march from a standstill: speed accel * TICK.
	u._approach_velocity = u.facing * (u.accel * TICK)
	var first: Vector2 = SoldierBodies.arrival_target(u, i, slot, u.soldiers,
			SoldierBodies.march_target_frac(u), not u.is_turning())
	var swing: float = rad_to_deg(absf(standing.angle_to(first)))
	assert_lt(swing, 1.0,
		"the first tick of the march turns his target by %.3f degrees, not round to the direct line" % swing)
	assert_lt((first - standing).length(), 1.0,
		"the first tick of the march moves his target by %.3f wu" % (first - standing).length())
	# Every tick of the ramp moves the target by a small step, and at walk pace it is the
	# marching (direct) target.
	var prev: Vector2 = first
	var speed: float = u.accel * TICK
	var worst: float = 0.0
	while speed < u.walk_speed:
		speed = minf(speed + u.accel * TICK, u.walk_speed)
		u._approach_velocity = u.facing * speed
		var t: Vector2 = SoldierBodies.arrival_target(u, i, slot, u.soldiers,
				SoldierBodies.march_target_frac(u), not u.is_turning())
		worst = maxf(worst, (t - prev).length())
		prev = t
	assert_lt(worst, 2.0, "no tick of the ramp moves his target by more than %.3f wu" % worst)
	assert_almost_eq(prev.x, direct.x, 1e-3, "at walk pace he walks direct (x)")
	assert_almost_eq(prev.y, direct.y, 1e-3, "at walk pace he walks direct (y)")


func test_march_target_frac_rises_with_the_march_to_its_full_speed() -> void:
	var u := _make_block()
	u._approach_velocity = Vector2.ZERO
	assert_eq(SoldierBodies.march_target_frac(u), 0.0, "a block standing still has the standing target")
	u._approach_velocity = u.facing * (u.march_target_full_speed() * 0.5)
	assert_almost_eq(SoldierBodies.march_target_frac(u), 0.5, 1e-5, "half the full speed, half the way")
	u._approach_velocity = u.facing * (u.march_target_full_speed() * 3.0)
	assert_eq(SoldierBodies.march_target_frac(u), 1.0, "past the full speed, all the way")
	u.march_target_walk_frac = 0.5
	u._approach_velocity = u.facing * (u.walk_speed * 0.25)
	assert_almost_eq(SoldierBodies.march_target_frac(u), 0.5, 1e-5,
		"the full speed follows the unit's own march_target_walk_frac")
	u.march_target_walk_frac = 0.0
	assert_eq(SoldierBodies.march_target_frac(u), 1.0, "a zero full speed marches at once")


func test_march_share_frac_ramps_from_half_a_pitch_to_a_pitch() -> void:
	assert_eq(SoldierBodies.march_share_frac(4.0, 18.0, 0.5, 1.0), 0.0, "inside half a pitch: none")
	assert_eq(SoldierBodies.march_share_frac(9.0, 18.0, 0.5, 1.0), 0.0, "at half a pitch: none")
	assert_almost_eq(SoldierBodies.march_share_frac(13.5, 18.0, 0.5, 1.0), 0.5, 1e-6, "halfway: half")
	assert_eq(SoldierBodies.march_share_frac(18.0, 18.0, 0.5, 1.0), 1.0, "at a pitch: all")
	assert_eq(SoldierBodies.march_share_frac(90.0, 18.0, 0.5, 1.0), 1.0, "beyond: all")
	assert_eq(SoldierBodies.march_share_frac(5.0, 18.0, 0.5, 0.5), 0.0, "a step at the edge: none inside")
	assert_eq(SoldierBodies.march_share_frac(10.0, 18.0, 0.5, 0.5), 1.0, "a step at the edge: all outside")


func test_a_man_near_his_slot_moves_as_he_did_without_the_share() -> void:
	# A block marching in good order is untouched: a man a few world units off his slot (under
	# half a file pitch) steps exactly as he would with the march holding its speed.
	var ramp := _make_block()
	var flat := _make_block()
	var i: int = ramp.soldiers - 1
	var off: float = ramp.file_pitch_wu() * 0.3
	for u in [ramp, flat]:
		u.state = Unit.State.MOVING
		u._body_march_orderly = true
		u._sim_soldier_pos[i] -= u.facing * off
	ramp._body_march_ff_prev = Vector2.ZERO
	ramp._approach_velocity = ramp.facing * (ramp.accel * TICK)
	flat._body_march_ff_prev = flat.facing * (flat.accel * TICK)
	flat._approach_velocity = flat.facing * (flat.accel * TICK)
	SoldierBodies.step(ramp, TICK)
	SoldierBodies.step(flat, TICK)
	assert_eq(ramp._sim_body_vel[i], flat._sim_body_vel[i],
		"a man %.1f wu off his slot takes no share of the march's acceleration" % off)
	assert_eq(ramp._sim_soldier_pos[i], flat._sim_soldier_pos[i], "and steps to the same place")
