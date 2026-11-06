extends GutTest
## A routing man who has fallen well behind his slot gains on it while the flight changes its
## velocity. The flight builds its pace at the unit's accel, which is the bodies' own
## acceleration, and its grid turn adds to a slot's velocity change on top, so without more a
## man fallen behind his slot only keeps pace with it or loses ground. He takes the change in
## his own feed-forward on top of his acceleration (SoldierBodies.flight_accel_share), ramped
## in by how far he stands off his slot (Unit.flight_share_from_wu, Unit.flight_share_full_wu).
## These drive SoldierBodies.step directly, with the anchor fled by hand at the unit's own
## acceleration.

const TICK: float = 1.0 / 60.0


## A `count`-man infantry block (the default type, 30 men by default) routing with its
## heading DOWN, every body seeded on its slot at rest.
func _make_router(count: int = 30) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = Vector2(500, 500)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	u.state = Unit.State.ROUTING
	return u


## Displace the rear-rank body `i` of `u` straight back along its file by `dist` wu, at rest.
## Nobody behind him crowds his lane, so only how fast his velocity can change decides whether
## he closes on his slot.
func _fall_back(u: Unit, i: int, dist: float) -> void:
	u._sim_soldier_pos[i] -= u.facing * dist
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


## How long a man starting `gap` wu farther off his slot than he needs to be takes to close that
## gap, closing at the relative acceleration `net` (wu/s^2) up to the relative speed `cap_speed`.
## On a straight flight building its pace at the bodies' own acceleration the man's own
## acceleration only keeps pace with his slot, so `net` is whatever share he takes on top.
func _close_time(gap: float, net: float, cap_speed: float) -> float:
	if net <= 0.0:
		return INF
	var ramp: float = cap_speed * cap_speed / (2.0 * net)
	if ramp >= gap:
		return sqrt(2.0 * gap / net)
	return cap_speed / net + (gap - ramp) / cap_speed


## Body `i`'s distance to its slot after `ticks` ticks of _flee on a fresh router, `start` wu
## behind his slot, with the share capped at `mult` times his acceleration.
func _gap_after(start: float, ticks: int, mult: float) -> float:
	var u := _make_router()
	u.flight_share_max_accel_mult = mult
	var i: int = u.soldiers - 1
	_fall_back(u, i, start)
	var dists: PackedFloat32Array = _flee(u, i, ticks)
	return dists[dists.size() - 1]


func test_a_man_fallen_well_behind_gains_on_his_slot_while_the_flight_builds_up() -> void:
	# He starts half of flight_share_full_wu farther back than full, so he takes all of the
	# share until he is back at full. The flight's change, his share, is the unit's accel; he
	# closes on his slot at that much, up to his jog pace (the cap on his arrival), and a
	# half-strength share closes at half of it. The sample tick is midway between the two
	# times that model gives for reaching full: a whole share is inside full by then and a
	# half share is not. With no share at all he never closes.
	var probe := _make_router()
	var body_accel: float = maxf(probe.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	assert_almost_eq(body_accel, probe.accel, 0.0001,
			"setup: the flight builds its pace at the bodies' own acceleration")
	var full: float = probe.flight_share_full_wu
	var start: float = full * 1.5
	var t_whole: float = _close_time(start - full, probe.accel, probe.jog_speed)
	var t_half: float = _close_time(start - full, probe.accel * 0.5, probe.jog_speed)
	var ticks: int = roundi((t_whole + t_half) * 0.5 / TICK)
	assert_lt(ticks * TICK, probe.flee_speed() / probe.accel,
			"setup: the sample falls inside the flight's build-up")
	var whole: float = _gap_after(start, ticks, SoldierBodies.FLIGHT_SHARE_MAX_ACCEL_MULT)
	assert_lt(whole, full, "with the whole share he is within %.0f wu after %.2f s (%.1f wu)"
			% [full, ticks * TICK, whole])
	var half: float = _gap_after(start, ticks, 0.5)
	assert_gt(half, full, "a share capped at half his acceleration leaves him beyond %.0f wu (%.1f wu)"
			% [full, half])


func test_a_man_within_the_share_distance_takes_no_share() -> void:
	# Two identical routers, one granting no share at all: a man standing just inside
	# flight_share_from_wu of his slot (more than three rank pitches of this infantry block) moves the
	# same in both, so a block whose men keep that close flees as it did before the share
	# existed.
	var plain := _make_router()
	var capped := _make_router()
	capped.flight_share_max_accel_mult = 0.0
	var i: int = plain.soldiers - 1
	var from: float = plain.flight_share_from_wu
	for u in [plain, capped]:
		_fall_back(u, i, from * 0.9)
	var pace: float = 0.0
	for _t in range(30):
		pace = minf(pace + plain.accel * TICK, plain.flee_speed())
		for u in [plain, capped]:
			u._flee_velocity = u.facing * pace
			u.position += u._flee_velocity * TICK
			SoldierBodies.step(u, TICK)
	var slot: Vector2 = plain.soldier_world_slots(plain.soldiers)[i]
	var gap: float = plain._sim_soldier_pos[i].distance_to(slot)
	assert_true(gap > plain.rank_pitch_wu() and gap < from,
			"setup: he stands more than a rank pitch off his slot, inside %.0f wu (%.2f wu)" % [from, gap])
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
			0.0, 1e-4, "losing 0.5 wu/s in one tick grants nothing")
	assert_almost_eq(SoldierBodies.flight_accel_share(Vector2(-10, 0), Vector2(0, 10), cap, TICK),
			cap, 1e-4, "a swing at the same speed counts as a quickening one")
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
	_fall_back(u, i, u.flight_share_full_wu * 1.5)
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
	_fall_back(u, i, u.flight_share_full_wu * 1.5)
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
	u.flight_share_from_wu = 30.0
	u.flight_share_full_wu = 90.0
	# A distinct feed-forward for every man, so a snapshot that mixed them up or kept only one
	# would not compare equal.
	var ffs := PackedVector2Array()
	for k in range(u._sim_soldier_pos.size()):
		ffs.append(Vector2(float(k), -2.0 * float(k) - 1.0))
	u._body_flight_ff_prev = ffs
	var d: Dictionary = u.to_snapshot_dict()
	var copy: Unit = Unit.new()
	copy.max_soldiers = 30
	add_child_autofree(copy)
	copy.apply_snapshot_dict(d)
	assert_almost_eq(copy.flight_share_max_accel_mult, 1.25, 1e-6, "the cap rides the snapshot")
	assert_almost_eq(copy.flight_share_from_wu, 30.0, 1e-6, "so does the ramp's start")
	assert_almost_eq(copy.flight_share_full_wu, 90.0, 1e-6, "and its end")
	assert_eq(copy._body_flight_ff_prev, ffs, "and each man's own last feed-forward")


func test_a_slowing_flight_grants_no_share() -> void:
	# The flight pulls up (its pace drops between two steps): a man far behind his slot sheds
	# speed at his own rate only, as a march that slows grants none either.
	var u := _make_router()
	var i: int = u.soldiers - 1
	_fall_back(u, i, u.flight_share_full_wu * 1.5)
	var pace: float = u.flee_speed() * 0.5
	for _t in range(30):
		u._flee_velocity = u.facing * pace
		SoldierBodies.step(u, TICK)
	var before: Vector2 = u._sim_body_vel[i]
	u._flee_velocity = u.facing * (pace * 0.5)
	SoldierBodies.step(u, TICK)
	var body_accel: float = maxf(u.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var change: float = u._sim_body_vel[i].distance_to(before)
	assert_lte(change, body_accel * TICK + 1e-4,
			"his velocity changes at his own acceleration only (%.4f wu/s in the tick)" % change)


func test_leaving_the_engaged_tier_grants_no_share_spike() -> void:
	# A front-rank man engaged on one step takes only his friendly-contact steering as his
	# feed-forward; on the next he is unengaged and takes the whole flight. His recorded
	# feed-forward is the unengaged form either way, so with the flight unchanged between the
	# steps he takes no share for it. The grid is turning, and the man is pushed from one end
	# of the leading rank past its other end, so the engaged tier re-pairs him onto the
	# canonical slot at that far end: his recorded turning velocity must still be his own
	# slot's. The turn's sign makes the far-end slot's turning velocity point against the
	# flight, so reading it would look like a quickening feed-forward, not a slowing one that
	# grants nothing anyway.
	var u := _make_router()
	u._engaged_linger = 1.0
	u._flight_turn_rate = -0.2
	var n: int = u._sim_soldier_pos.size()
	var tier: PackedInt32Array = u.body_tier_soldier_indices(n)
	assert_gt(tier.size(), 0, "setup: the router has an engaged tier")
	if tier.is_empty():
		return
	# The tier's man at one end of the rank, pushed sideways past its other end, so he keeps
	# his place in the leading rank's line but stands nearest the far end's slot.
	var lat: Vector2 = u.facing.orthogonal()
	var i: int = tier[0]
	var lo: float = INF
	var hi: float = -INF
	for k in tier:
		var at: float = u._sim_soldier_pos[k].dot(lat)
		hi = maxf(hi, at)
		if at < lo:
			lo = at
			i = k
	var push: float = maxf(u.flight_share_full_wu * 1.5, hi - lo + u.file_pitch_wu())
	u._sim_soldier_pos[i] += lat * push
	u._sim_body_vel[i] = Vector2.ZERO
	u._flee_velocity = u.facing * u.flee_speed() * 0.5
	SoldierBodies.step(u, TICK)
	assert_true(i in u.body_tier_soldier_indices(n), "setup: he was engaged on the first step")
	u._engaged_linger = 0.0
	var before: Vector2 = u._sim_body_vel[i]
	SoldierBodies.step(u, TICK)
	var body_accel: float = maxf(u.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var change: float = u._sim_body_vel[i].distance_to(before)
	assert_lte(change, body_accel * TICK + 1e-4,
			"leaving the tier, his velocity changes at his own acceleration only (%.4f wu/s)" % change)


## Step `u` once at half flee pace with every man well off his slot, change its headcount by
## `change`, step again, and return the largest change any man's velocity took on the second
## step. With the flight and the turn the same on both steps, no man may take a share then.
func _worst_change_across_headcount(u: Unit, change: int) -> float:
	u._flight_turn_rate = 0.2
	u._flee_velocity = u.facing * u.flee_speed() * 0.5
	for k in range(u._sim_soldier_pos.size()):
		_fall_back(u, k, u.flight_share_full_wu * 1.5)
	SoldierBodies.step(u, TICK)
	var before: PackedVector2Array = u._sim_body_vel.duplicate()
	var n_before: int = before.size()
	u.soldiers += change
	SoldierBodies.step(u, TICK)
	assert_eq(u._sim_soldier_pos.size(), n_before + change, "setup: the step resized the bodies")
	var worst: float = 0.0
	for k in range(mini(n_before, u._sim_body_vel.size())):
		worst = maxf(worst, u._sim_body_vel[k].distance_to(before[k]))
	return worst


func test_a_headcount_change_between_steps_grants_no_share() -> void:
	# The last step's feed-forwards belong to a different headcount: a casualty leaves one fewer
	# body to pair them with, and a man joining (a reinforcement) leaves one with no last
	# feed-forward at all. The step reads no change across either, so no man takes a share.
	var body_accel: float = maxf(_make_router().accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var bound: float = body_accel * TICK + 1e-4
	var fell: float = _worst_change_across_headcount(_make_router(), -1)
	assert_lte(fell, bound,
			"after a casualty no man's velocity changes faster than his own acceleration (worst %.4f wu/s)"
			% fell)
	var grown := _make_router(31)
	grown.soldiers = 30
	SoldierBodies.seed(grown)
	var joined: float = _worst_change_across_headcount(grown, 1)
	assert_lte(joined, bound,
			"after a man joins no man's velocity changes faster than his own acceleration (worst %.4f wu/s)"
			% joined)


func test_seeding_the_bodies_clears_the_flight_feed_forward() -> void:
	var u := _make_router()
	u._flee_velocity = u.facing * 20.0
	SoldierBodies.step(u, TICK)
	assert_gt(u._body_flight_ff_prev.size(), 0, "setup: a routing step recorded the feed-forward")
	u.seed_sim_soldiers()
	assert_eq(u._body_flight_ff_prev.size(), 0, "fresh bodies carry no flight feed-forward")
