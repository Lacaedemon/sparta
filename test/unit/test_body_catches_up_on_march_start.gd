extends GutTest
## A man walking back to his slot as his block sets off. Two things decide whether he
## catches up: his velocity has to change faster than his slot's does while the march speeds
## up (SoldierBodies.march_accel_budget), and his arrival target must not swing round the
## instant the march begins (SoldierBodies.advance_march_target_frac and arrival_target). These drive
## SoldierBodies.step directly, with the anchor marched by hand at the unit's own
## acceleration up to walk pace. That ramp approximates the one _move_to gives a block from a
## standstill on open ground: _set_off leaves out terrain, travel_frac and the gait ladder.

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
	# approach, a hasty move -- keeps the ordinary rate, so he only keeps pace with his slot.
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


func test_a_routing_block_grants_no_share_even_with_the_orderly_flag_set() -> void:
	# A router's bodies take the flight velocity as their feed-forward, and the flight speeds
	# up like a march does, but a rout is not an orderly march: two identical routing blocks,
	# one with the orderly flag set and one without, flee on the same ramp with the same man
	# displaced, and he moves the same in both.
	var flagged := _make_block()
	var plain := _make_block()
	var i: int = flagged.soldiers - 1
	for u in [flagged, plain]:
		u.state = Unit.State.ROUTING
		u._sim_soldier_pos[i] -= u.facing * 20.0
		u._sim_body_vel[i] = Vector2.ZERO
	var speed: float = 0.0
	for _t in range(30):
		speed = minf(speed + flagged.accel * TICK, flagged.walk_speed)
		for u in [flagged, plain]:
			u._flee_velocity = u.facing * speed
			u._body_march_orderly = u == flagged
			u.position += u._flee_velocity * TICK
			SoldierBodies.step(u, TICK)
	var slot: Vector2 = flagged.soldier_world_slots(flagged.soldiers)[i]
	assert_gt(flagged._sim_soldier_pos[i].distance_to(slot), flagged.file_pitch_wu() * 0.5,
		"precondition: he is still far enough off his slot to take a share")
	assert_eq(flagged._sim_soldier_pos[i], plain._sim_soldier_pos[i],
		"the routing man moves the same whether or not the orderly flag is set")
	assert_eq(flagged._sim_body_vel[i], plain._sim_body_vel[i],
		"and his velocity is the same")


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
	# The cap is the unit's own knob, a multiple of body_accel.
	u.march_share_max_accel_mult = 0.5
	assert_almost_eq(SoldierBodies.march_accel_budget(u, Vector2(10, 0), body_accel, TICK),
			body_accel * 0.5, 1e-4, "a cap of half a body_accel grants at most half of it")
	assert_almost_eq(SoldierBodies.march_accel_budget(u, Vector2(0, 10.25), body_accel, TICK), 15.0, 1e-3,
		"a change under the cap is granted in full")
	u.march_share_max_accel_mult = 0.0
	assert_almost_eq(SoldierBodies.march_accel_budget(u, Vector2(10, 0), body_accel, TICK), 0.0, 1e-4,
		"a cap of 0 grants nothing")


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


## Man 0 of `u` set two pitches across files and two across ranks off his slot (2.83 pitches):
## outside the standing band, so standing he walks the perimeter corridor; inside the
## marching band, so on the march he walks direct. That is the man whose target the march
## start used to swing. Returns his slot.
func _place_between_bands(u: Unit) -> Vector2:
	var spacing: float = u.file_pitch_wu()
	var slot: Vector2 = u._sim_soldier_pos[0]
	u._sim_soldier_pos[0] = slot + Vector2(spacing * 2.0, -spacing * 2.0)
	return slot


## Man 0's arrival target on `u` after advancing the blend one tick.
func _target_after_tick(u: Unit, slot: Vector2) -> Vector2:
	return SoldierBodies.arrival_target(u, 0, slot, u.soldiers,
			SoldierBodies.advance_march_target_frac(u, TICK), not u.is_turning())


func test_his_arrival_target_does_not_jump_when_the_march_begins() -> void:
	var u := _make_block()
	var slot: Vector2 = _place_between_bands(u)
	var direct: Vector2 = slot - u._sim_soldier_pos[0]
	u.state = Unit.State.MOVING
	u._approach_velocity = Vector2.ZERO
	var standing: Vector2 = _target_after_tick(u, slot)
	assert_gt(rad_to_deg(absf(standing.angle_to(direct))), 10.0,
		"precondition: standing, he is routed round the corridor, not sent direct")
	# The first tick of a march from a standstill: speed accel * TICK.
	u._approach_velocity = u.facing * (u.accel * TICK)
	var first: Vector2 = _target_after_tick(u, slot)
	var swing: float = rad_to_deg(absf(standing.angle_to(first)))
	assert_lt(swing, 1.0,
		"the first tick of the march turns his target by %.3f degrees, not round to the direct line" % swing)
	assert_lt((first - standing).length(), 1.0,
		"the first tick of the march moves his target by %.3f wu" % (first - standing).length())
	# Every tick of the ramp moves the target by a small step, and once the ramp is over it is
	# the marching (direct) target.
	var prev: Vector2 = first
	var worst: float = 0.0
	for _t in range(ceili(SoldierBodies.march_target_ramp_s(u) / TICK) + 1):
		var t: Vector2 = _target_after_tick(u, slot)
		worst = maxf(worst, (t - prev).length())
		prev = t
	assert_lt(worst, 2.0, "no tick of the ramp moves his target by more than %.3f wu" % worst)
	assert_almost_eq(prev.x, direct.x, 1e-3, "after the ramp he walks direct (x)")
	assert_almost_eq(prev.y, direct.y, 1e-3, "after the ramp he walks direct (y)")


func test_a_stop_switches_his_target_back_at_once() -> void:
	# A march that stops (here zeroed in one tick, as a move that runs into contact is) puts
	# him straight back on the standing target, as before the blend: easing it back there kept
	# an attacker's men walking direct into the press.
	var u := _make_block()
	var slot: Vector2 = _place_between_bands(u)
	u.state = Unit.State.MOVING
	u._approach_velocity = u.facing * u.walk_speed
	for _t in range(ceili(SoldierBodies.march_target_ramp_s(u) / TICK) + 1):
		_target_after_tick(u, slot)
	u._approach_velocity = Vector2.ZERO
	assert_eq(SoldierBodies.advance_march_target_frac(u, TICK), 0.0,
		"the blend is 0 the step the march stops")
	# The standing target, computed straight from the corridor router with the narrow band,
	# not through arrival_target.
	var standing: Vector2 = SoldierBodies._corridor_to_slot(u, 0, slot, u.soldiers,
			SoldierBodies.CORRIDOR_PROXIMITY_MULT, false)
	var direct: Vector2 = slot - u._sim_soldier_pos[0]
	assert_gt(rad_to_deg(absf(standing.angle_to(direct))), 10.0,
		"precondition: the standing target routes him round the corridor, not direct")
	assert_eq(_target_after_tick(u, slot), standing,
		"on the next stopped step his target is the standing one")
	# Once the stop outlasts its grace, the ramp itself is gone too: the next march starts it
	# again from nothing.
	_target_after_tick(u, slot)
	assert_eq(u._march_target_frac, 0.0, "a stop of three steps drops the ramp to 0")


func test_a_one_or_two_tick_dip_does_not_restart_the_ramp() -> void:
	# A march that dips to a standstill for a tick or two and goes on picks its ramp up where
	# it left it; only a real stop (more than Unit.march_target_stop_grace_ticks steps) starts
	# it again.
	# During the dip the target is the standing one, as on any stop.
	for dip in [1, 2, 3]:
		var u := _make_block()
		u.state = Unit.State.MOVING
		var ramp_ticks: int = ceili(SoldierBodies.march_target_ramp_s(u) / TICK)
		u._approach_velocity = u.facing * u.walk_speed
		var before: float = 0.0
		for _t in range(ramp_ticks / 2):
			before = SoldierBodies.advance_march_target_frac(u, TICK)
		u._approach_velocity = Vector2.ZERO
		for _t in range(dip):
			assert_eq(SoldierBodies.advance_march_target_frac(u, TICK), 0.0,
				"a %d-tick dip: the target is the standing one while it lasts" % dip)
		u._approach_velocity = u.facing * u.walk_speed
		var after: float = SoldierBodies.advance_march_target_frac(u, TICK)
		var step_frac: float = TICK / SoldierBodies.march_target_ramp_s(u)
		if dip <= 2:
			assert_almost_eq(after, before + step_frac, 1e-5,
				"a %d-tick dip keeps the ramp: %.3f before, %.3f after" % [dip, before, after])
		else:
			assert_almost_eq(after, step_frac, 1e-5,
				"a %d-tick stop restarts the ramp: %.3f after" % [dip, after])


func test_the_stop_grace_is_the_units_own_knob() -> void:
	# With no grace, a one-tick dip restarts the ramp; with a grace of three, a three-tick dip
	# keeps it.
	for grace in [0, 3]:
		var u := _make_block()
		u.march_target_stop_grace_ticks = grace
		u.state = Unit.State.MOVING
		var ramp_ticks: int = ceili(SoldierBodies.march_target_ramp_s(u) / TICK)
		u._approach_velocity = u.facing * u.walk_speed
		var before: float = 0.0
		for _t in range(ramp_ticks / 2):
			before = SoldierBodies.advance_march_target_frac(u, TICK)
		u._approach_velocity = Vector2.ZERO
		var dip: int = maxi(grace, 1)
		for _t in range(dip):
			SoldierBodies.advance_march_target_frac(u, TICK)
		u._approach_velocity = u.facing * u.walk_speed
		var after: float = SoldierBodies.advance_march_target_frac(u, TICK)
		var step_frac: float = TICK / SoldierBodies.march_target_ramp_s(u)
		var want: float = step_frac if grace == 0 else before + step_frac
		assert_almost_eq(after, want, 1e-5,
			"grace %d, a %d-tick dip: %.3f before, %.3f after" % [grace, dip, before, after])


func test_march_target_frac_ramps_by_time_not_by_speed() -> void:
	var u := _make_block()
	var ramp_s: float = SoldierBodies.march_target_ramp_s(u)
	assert_almost_eq(ramp_s, u.march_target_full_speed() / u.accel, 1e-5,
		"the ramp takes as long as the march takes to reach its full speed from rest")
	u._approach_velocity = Vector2.ZERO
	assert_eq(SoldierBodies.advance_march_target_frac(u, TICK), 0.0,
		"a block standing still has the standing target")
	# A march held well below the full speed still reaches the marching target, in the ramp's
	# time: a block marching steadily at a slow pace has its men walk direct like any other.
	u._approach_velocity = u.facing * (u.march_target_full_speed() * 0.2)
	var half_ticks: int = roundi(ramp_s * 0.5 / TICK)
	var frac: float = 0.0
	for _t in range(half_ticks):
		frac = SoldierBodies.advance_march_target_frac(u, TICK)
	assert_almost_eq(frac, 0.5, 0.02, "half the ramp's time, half the way, whatever the speed")
	for _t in range(half_ticks + 2):
		frac = SoldierBodies.advance_march_target_frac(u, TICK)
	assert_eq(frac, 1.0, "after the ramp's time, all the way")
	u._approach_velocity = Vector2.ZERO
	assert_eq(SoldierBodies.advance_march_target_frac(u, TICK), 0.0, "a stop drops it at once")
	u.march_target_walk_frac = 0.0
	u._approach_velocity = u.facing * 5.0
	assert_eq(SoldierBodies.advance_march_target_frac(u, TICK), 1.0,
		"a zero full speed switches at once")


func test_the_blended_target_keeps_its_length() -> void:
	# step() reads a man's desired speed off his target's length, so the blend of two targets
	# that point apart must not be shorter than both: two 30 wu targets at right angles keep
	# 30 wu at every point of the blend (a plain lerp would give 21.2 wu halfway).
	var a := Vector2(30, 0)
	var b := Vector2(0, 30)
	for k in range(11):
		var f: float = k / 10.0
		var t: Vector2 = SoldierBodies.blend_targets(a, b, f)
		assert_almost_eq(t.length(), 30.0, 1e-3, "at %.1f of the way the target is %.3f wu long" % [f, t.length()])
	var half: Vector2 = SoldierBodies.blend_targets(a, b, 0.5)
	assert_almost_eq(rad_to_deg(half.angle()), 45.0, 1e-3, "and halfway it points halfway between them")
	# Lengths that differ blend linearly.
	assert_almost_eq(SoldierBodies.blend_targets(Vector2(10, 0), Vector2(0, 30), 0.25).length(),
			15.0, 1e-3, "a quarter of the way from 10 to 30 wu is 15 wu")
	# Two targets pointing exactly apart turn through the half-turn at the same constant rate,
	# their length still running linearly.
	assert_almost_eq(SoldierBodies.blend_targets(Vector2(10, 0), Vector2(-20, 0), 0.5),
			Vector2(0, 15), Vector2(1e-3, 1e-3), "opposed targets, halfway: a quarter-turn, 15 wu")
	assert_almost_eq(SoldierBodies.blend_targets(Vector2(10, 0), Vector2(-20, 0), 0.25),
			Vector2.from_angle(PI / 4.0) * 12.5, Vector2(1e-3, 1e-3),
			"opposed targets, a quarter: an eighth-turn, 12.5 wu")
	# A zero-length end blends to the other end's direction, linearly in length.
	assert_almost_eq(SoldierBodies.blend_targets(Vector2.ZERO, Vector2(0, 20), 0.5),
			Vector2(0, 10), Vector2(1e-3, 1e-3), "from nothing, halfway")
	assert_almost_eq(SoldierBodies.blend_targets(Vector2(0, 20), Vector2.ZERO, 0.75),
			Vector2(0, 5), Vector2(1e-3, 1e-3), "to nothing, three quarters")


func test_the_blended_target_turns_at_a_constant_rate() -> void:
	# Over the ramp the target turns from the standing direction to the marching one by the
	# same angle every tick, however far apart the two point: two targets 170 degrees apart
	# turn 170 / 90 = 1.9 degrees a tick over a 90-tick ramp. A normalized lerp of the two
	# turns 14.3 degrees in its worst tick, near halfway, and barely at all near the ends.
	var u := _make_block()
	u.state = Unit.State.MOVING
	u._approach_velocity = u.facing * u.walk_speed
	var ramp_ticks: int = ceili(SoldierBodies.march_target_ramp_s(u) / TICK)
	for spread in [90.0, 170.0, 179.9, 180.0]:
		u._march_target_frac = 0.0
		var a := Vector2(25, 0)
		var b := Vector2.from_angle(deg_to_rad(spread)) * 25.0
		var even: float = spread * TICK / SoldierBodies.march_target_ramp_s(u)
		var prev: Vector2 = a
		var worst: float = 0.0
		var total: float = 0.0
		for _t in range(ramp_ticks):
			var t: Vector2 = SoldierBodies.blend_targets(a, b,
					SoldierBodies.advance_march_target_frac(u, TICK))
			var turn: float = rad_to_deg(absf(prev.angle_to(t)))
			worst = maxf(worst, turn)
			total += turn
			prev = t
		assert_lt(worst, even * 1.01 + 1e-3,
			"targets %.1f degrees apart: the worst tick turns %.3f degrees, an even turn is %.3f"
			% [spread, worst, even])
		assert_almost_eq(total, spread, 0.01,
			"targets %.1f degrees apart: the ramp turns %.3f degrees in all" % [spread, total])
		assert_almost_eq(prev, b, Vector2(1e-3, 1e-3), "and ends on the marching target")


func test_the_blended_target_keeps_its_length_in_step() -> void:
	# The same, on a man between the two bands as his block sets off: at every tick of the
	# ramp his target is at least as long as the shorter of the standing and marching ones.
	var u := _make_block()
	var slot: Vector2 = _place_between_bands(u)
	u.state = Unit.State.MOVING
	u._approach_velocity = u.facing * (u.accel * TICK)
	var worst: float = INF
	for _t in range(ceili(SoldierBodies.march_target_ramp_s(u) / TICK)):
		var frac: float = SoldierBodies.advance_march_target_frac(u, TICK)
		var standing: Vector2 = SoldierBodies.arrival_target(u, 0, slot, u.soldiers, 0.0, true)
		var marching: Vector2 = SoldierBodies.arrival_target(u, 0, slot, u.soldiers, 1.0, true)
		var t: Vector2 = SoldierBodies.arrival_target(u, 0, slot, u.soldiers, frac, true)
		worst = minf(worst, t.length() - minf(standing.length(), marching.length()))
	assert_gt(worst, -1e-3, "the blended target is never shorter than both ends (worst %.4f wu)" % worst)


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


# How far off a march's destination or an attack's enemy lies (wu): far enough that one tick
# only sets off, never arrives or makes contact.
const GATE_RANGE: float = 600.0   # tuned in wu


## A block with a fresh MOVE order to GATE_RANGE ahead, set to step off at once (no reform hold).
func _block_ordered_to_move(haste: bool) -> Unit:
	var u := _make_block()
	u.reform_before_move = false
	var dest: Vector2 = u.position + u.facing * GATE_RANGE
	u.set_current_order(Order.new_move(dest, 0, -1, haste))
	u.move_target = dest
	u.has_move_target = true
	u.state = Unit.State.MOVING
	return u


func test_a_plain_move_order_marches_orderly() -> void:
	var u := _block_ordered_to_move(false)
	var start: Vector2 = u.position
	u._physics_process(TICK)
	assert_ne(u.position, start, "setup: the block stepped off on this tick")
	assert_true(u._body_march_orderly, "a plain move order's march grants the share")


func test_a_hasty_move_order_does_not_march_orderly() -> void:
	var u := _block_ordered_to_move(true)
	assert_true(u._is_move_order_in_haste(), "setup: the order is in haste")
	var start: Vector2 = u.position
	u._physics_process(TICK)
	assert_ne(u.position, start, "setup: the block stepped off on this tick")
	assert_false(u._body_march_orderly, "a hasty move order's march grants no share")


func test_an_attack_approach_does_not_march_orderly() -> void:
	var u := _make_block()
	u.uid = 1
	u.team = 0
	var foe: Unit = Unit.new()
	foe.max_soldiers = 30
	add_child_autofree(foe)
	foe.uid = 2
	foe.team = 1
	foe.position = u.position + u.facing * GATE_RANGE
	foe.facing = Vector2.UP
	foe.seed_sim_soldiers()
	u.set_current_order(Order.new_attack(foe.uid))
	u.target_enemy = foe
	u.state = Unit.State.MOVING
	var start: Vector2 = u.position
	u._physics_process(TICK)
	assert_ne(u.position, start, "setup: the block closed on its enemy on this tick")
	assert_false(u._body_march_orderly, "an attack's approach grants no share")


func test_the_orderly_flag_is_cleared_every_tick() -> void:
	# A tick on which _move_to does not run (here the block stands idle) must not inherit the
	# flag from the tick before: only _move_to sets it, so _physics_process clears it first.
	var u := _block_ordered_to_move(false)
	u._physics_process(TICK)
	assert_true(u._body_march_orderly, "setup: the march set the flag")
	u.set_current_order(null)
	u.has_move_target = false
	u._approach_velocity = Vector2.ZERO
	u._current_speed = 0.0
	u.state = Unit.State.IDLE
	u._physics_process(TICK)
	assert_false(u._body_march_orderly, "an idle tick reads the flag as clear")
