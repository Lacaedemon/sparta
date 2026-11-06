extends GutTest
## A routing man who has fallen out of his rank's place gains on his slot while the flight
## changes its velocity. The flight builds its pace at the unit's accel, which is the bodies'
## own acceleration, and its grid turn adds to a slot's velocity change on top, so without
## more a man fallen behind his slot only keeps pace with it or loses ground. He takes the
## change in his own feed-forward on top of his acceleration (SoldierBodies.flight_accel_share),
## ramped in by how far he stands off his slot in rank pitches. These drive SoldierBodies.step
## directly, with the anchor fled by hand at the unit's own acceleration.

const TICK: float = 1.0 / 60.0


## A 30-man infantry block (the default type) routing with its heading DOWN, every body seeded
## on its slot at rest.
func _make_router() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 30
	add_child_autofree(u)
	u.position = Vector2(500, 500)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	u.state = Unit.State.ROUTING
	return u


## Displace the rear-rank body `i` of `u` straight back along its file by `pitches` rank
## pitches, at rest. Nobody behind him crowds his lane, so only how fast his velocity can
## change decides whether he closes on his slot.
func _fall_back(u: Unit, i: int, pitches: float) -> void:
	u._sim_soldier_pos[i] -= u.facing * u.rank_pitch_wu() * pitches
	u._sim_body_vel[i] = Vector2.ZERO


## Flee `u` straight ahead for `ticks` ticks from a standstill, its flight pace building at its
## own accel up to flee_speed() as Unit._process_rout builds it. Returns body `i`'s distance to
## its slot after each tick.
func _flee(u: Unit, i: int, ticks: int) -> PackedFloat32Array:
	var dists := PackedFloat32Array()
	var pace: float = 0.0
	for _t in range(ticks):
		pace = minf(pace + u.accel * TICK, u.flee_speed())
		u._flee_velocity = u.facing * pace
		u.position += u._flee_velocity * TICK
		SoldierBodies.step(u, TICK)
		var slot: Vector2 = u.soldier_world_slots(u.soldiers)[i]
		dists.append(u._sim_soldier_pos[i].distance_to(slot))
	return dists


func test_a_man_fallen_out_of_his_rank_gains_on_his_slot_while_the_flight_builds_up() -> void:
	var u := _make_router()
	var i: int = u.soldiers - 1
	var pitch: float = u.rank_pitch_wu()
	_fall_back(u, i, 1.5)
	var body_accel: float = maxf(u.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	assert_almost_eq(body_accel, u.accel, 0.0001,
			"setup: the flight builds its pace at the bodies' own acceleration")
	# The whole build-up to flee pace.
	var ticks: int = ceili(u.flee_speed() / u.accel / TICK)
	var dists: PackedFloat32Array = _flee(u, i, ticks)
	# At his own acceleration alone he only keeps pace with his slot and never comes back
	# within a rank pitch of it; with his feed-forward's change on top he closes on it at his
	# full acceleration until he is back in his rank's place.
	assert_lt(dists[dists.size() - 1], pitch,
			"the man 1.5 rank pitches behind his slot is back within one (%.0f wu) after the %.2f s build-up (%.1f wu)"
			% [pitch, ticks * TICK, dists[dists.size() - 1]])


func test_a_man_within_half_a_rank_pitch_takes_no_share() -> void:
	# Two identical routers, one granting no share at all: a man standing just inside half a
	# rank pitch of his slot moves the same in both, so a block whose men keep that close flees
	# as it did before the share existed.
	var plain := _make_router()
	var capped := _make_router()
	capped.flight_share_max_accel_mult = 0.0
	var i: int = plain.soldiers - 1
	for u in [plain, capped]:
		_fall_back(u, i, SoldierBodies.FLIGHT_SHARE_FROM_PITCHES * 0.9)
	var pace: float = 0.0
	for _t in range(30):
		pace = minf(pace + plain.accel * TICK, plain.flee_speed())
		for u in [plain, capped]:
			u._flee_velocity = u.facing * pace
			u.position += u._flee_velocity * TICK
			SoldierBodies.step(u, TICK)
	var slot: Vector2 = plain.soldier_world_slots(plain.soldiers)[i]
	var gap: float = plain._sim_soldier_pos[i].distance_to(slot)
	assert_true(gap > 1.0 and gap < plain.rank_pitch_wu() * SoldierBodies.FLIGHT_SHARE_FROM_PITCHES,
			"setup: he still stands off his slot, inside half a rank pitch (%.2f wu)" % gap)
	assert_eq(plain._sim_soldier_pos[i], capped._sim_soldier_pos[i],
			"he moves the same with or without the share")
	assert_eq(plain._sim_body_vel[i], capped._sim_body_vel[i], "and his velocity is the same")


func test_flight_accel_share_is_the_feed_forward_change_capped() -> void:
	var cap: float = 80.0
	assert_almost_eq(SoldierBodies.flight_accel_share(Vector2(0, 10), Vector2(0, 10), cap, TICK),
			0.0, 1e-4, "a steady feed-forward grants nothing")
	assert_almost_eq(SoldierBodies.flight_accel_share(Vector2(0, 10.5), Vector2(0, 10), cap, TICK),
			30.0, 1e-3, "gaining 0.5 wu/s in one tick grants 30 wu/s^2")
	assert_almost_eq(SoldierBodies.flight_accel_share(Vector2(0, 9.5), Vector2(0, 10), cap, TICK),
			30.0, 1e-3, "losing 0.5 wu/s in one tick grants as much")
	assert_almost_eq(SoldierBodies.flight_accel_share(Vector2(0.5, 10), Vector2(0, 10), cap, TICK),
			30.0, 1e-3, "and so does a sideways change of 0.5 wu/s")
	assert_almost_eq(SoldierBodies.flight_accel_share(Vector2(10, 0), Vector2(0, 10), cap, TICK),
			cap, 1e-4, "a one-tick swing grants no more than the cap")
	assert_almost_eq(SoldierBodies.flight_accel_share(Vector2(10, 0), Vector2(0, 10), cap, 0.0),
			0.0, 1e-4, "a zero-length step grants nothing")


func test_a_one_tick_swing_grants_no_more_than_the_cap() -> void:
	# The flight swings its direction in one tick (a step leaving a detour leg): the man's
	# velocity changes by no more than his own acceleration plus the cap, for one tick.
	var u := _make_router()
	var i: int = u.soldiers - 1
	_fall_back(u, i, 1.5)
	var pace: float = u.flee_speed() * 0.5
	u._flee_velocity = u.facing * pace
	SoldierBodies.step(u, TICK)
	var before: Vector2 = u._sim_body_vel[i]
	u._flee_velocity = u.facing.orthogonal() * pace
	SoldierBodies.step(u, TICK)
	var body_accel: float = maxf(u.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var bound: float = body_accel * (1.0 + u.flight_share_max_accel_mult) * TICK
	var change: float = u._sim_body_vel[i].distance_to(before)
	assert_gt(change, body_accel * TICK * 1.5, "setup: the swing grants him a share (%.3f wu/s)" % change)
	assert_lte(change, bound + 1e-3,
			"his velocity changes by at most %.3f wu/s in the tick (got %.3f)" % [bound, change])


func test_a_rout_starts_with_no_share_and_leaves_none_behind() -> void:
	# The first routing step has no feed-forward from a last step to read, so it grants none;
	# a step that is not routing leaves nothing for a later rout to read.
	var u := _make_router()
	assert_eq(u._body_flight_ff_prev.size(), 0, "setup: a fresh unit carries no flight feed-forward")
	var i: int = u.soldiers - 1
	_fall_back(u, i, 1.5)
	u._flee_velocity = u.facing * u.flee_speed()
	SoldierBodies.step(u, TICK)
	var body_accel: float = maxf(u.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	assert_lte(u._sim_body_vel[i].length(), body_accel * TICK + 1e-4,
			"the first routing step changes his velocity at his own acceleration only")
	assert_eq(u._body_flight_ff_prev.size(), u._sim_soldier_pos.size(),
			"a routing step records each man's feed-forward")
	u.state = Unit.State.IDLE
	SoldierBodies.step(u, TICK)
	assert_eq(u._body_flight_ff_prev.size(), 0, "a step that is not routing clears it")


func test_the_share_settings_ride_the_snapshot() -> void:
	var u := _make_router()
	u.flight_share_max_accel_mult = 1.25
	u.flight_share_from_pitches = 0.3
	u.flight_share_full_pitches = 0.9
	u._flee_velocity = u.facing * 20.0
	SoldierBodies.step(u, TICK)
	var d: Dictionary = u.to_snapshot_dict()
	var copy: Unit = Unit.new()
	copy.max_soldiers = 30
	add_child_autofree(copy)
	copy.apply_snapshot_dict(d)
	assert_almost_eq(copy.flight_share_max_accel_mult, 1.25, 1e-6, "the cap rides the snapshot")
	assert_almost_eq(copy.flight_share_from_pitches, 0.3, 1e-6, "so does the ramp's start")
	assert_almost_eq(copy.flight_share_full_pitches, 0.9, 1e-6, "and its end")
	assert_eq(copy._body_flight_ff_prev, u._body_flight_ff_prev,
			"and each man's last feed-forward")
