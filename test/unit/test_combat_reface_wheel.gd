extends GutTest
## A fighting cavalry block in enemy contact that re-faces by a small correction (up to
## ENGAGE_TURN_THRESHOLD) wheels its heading onto the enemy at a bounded rate instead of
## snapping it there in one tick. The slot grid is laid out from the heading, so a snap turned
## the whole grid about the anchor at once: a deep block's corner slot moved its radius times the
## turn in a single tick while the riders, held in the press, stayed where they stood. A
## correction within combat_reface_snap_turn (a few degrees) still snaps, and so does every
## correction out of contact, on a far-tier block, and on a foot block (riders inside a foot
## block fold the turn into the grid instead: test_melee_reface_inside_block.gd).

const DT := 1.0 / 60.0
const FACING_TOL := 1e-5
# Float slack on a slot's sweep against the bound it must stay under.
const SWEEP_TOL := 1e-3


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _make_block() -> Unit:
	var u := _make_unit()
	u.uid = 1
	u.is_cavalry = true
	u._in_enemy_contact = true
	return u


func _make_enemy(pos: Vector2) -> Unit:
	var e := _make_unit(20)
	e.uid = 2
	e.team = 1
	e.position = pos
	e.state = Unit.State.FIGHTING
	return e


## A point `deg` degrees off the block's DOWN heading, far outside its footprint.
func _bearing_point(deg: float) -> Vector2:
	return Vector2.DOWN.rotated(deg_to_rad(deg)) * 2000.0


func _max_slot_shift(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(a.size()):
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


## One tick of the wheel as _think runs it: the turn flags clear at the top of every tick, and
## the wheel ran on the tick before when `followed` (GUT calls within one test share a physics
## frame, so the tick stamp is set by hand).
func _wheel_tick(u: Unit, e: Unit, followed: bool) -> bool:
	u._is_facing_turning = false
	u._facing_turn_step = 0.0
	u._combat_wheel_tick = Engine.get_physics_frames() - (1 if followed else 5)
	return u._face_for_action(e.position, DT, e)


func test_a_small_reface_in_contact_wheels_the_heading_from_rest() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(30.0))
	var radius: float = u._formation_local_half_extents().length()
	var first: float = u.bounded_turn_accel(radius) * DT * DT
	assert_lt(first, deg_to_rad(30.0), "sanity: one tick from rest is far short of the turn")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_true(_wheel_tick(u, e, false), "30 degrees off, the block fights on as it wheels")
	assert_almost_eq(absf(Vector2.DOWN.angle_to(u.facing)), first, FACING_TOL,
		"from rest the heading turns one tick of bounded_turn_accel toward the enemy")
	assert_gt(Vector2.DOWN.angle_to(u.facing) * deg_to_rad(30.0), 0.0, "and it turns toward him")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), u.jog_speed * DT + SWEEP_TOL,
		"no slot sweeps faster than the men can jog")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no turn-in-place is armed")
	assert_eq(u._formation_angle, 0.0, "nothing is folded into the grid")


func test_the_wheel_builds_to_the_bounded_rate_and_no_faster() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(70.0))
	var rate: float = u.bounded_turn_rate()
	var worst := 0.0
	var bearing: float = (e.position - u.position).angle()
	for i in range(240):
		var prev: float = u.facing.angle()
		if absf(angle_difference(prev, bearing)) <= u.combat_reface_snap_turn:
			break   # the last few degrees snap
		_wheel_tick(u, e, i > 0)
		worst = maxf(worst, absf(angle_difference(prev, u.facing.angle())))
	assert_almost_eq(worst, rate * DT, FACING_TOL, "the wheel's fastest tick is the bounded rate")


func test_the_wheel_reaches_the_enemy_and_then_holds_on_him() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(30.0))
	for i in range(600):
		_wheel_tick(u, e, i > 0)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"the heading comes onto the enemy")


func test_the_wheel_withholds_blows_past_the_fight_tolerance() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(70.0))
	assert_gt(deg_to_rad(70.0), Unit.ENGAGE_TURN_FIGHT_TOLERANCE, "sanity: past the tolerance")
	assert_lt(deg_to_rad(70.0), Unit.ENGAGE_TURN_THRESHOLD, "sanity: under the turn-in-place threshold")
	assert_false(_wheel_tick(u, e, false), "70 degrees off its enemy, the block does not strike")
	var faced := false
	for i in range(600):
		faced = _wheel_tick(u, e, true)
		var off: float = absf(angle_difference(u.facing.angle(), (e.position - u.position).angle()))
		assert_eq(faced, off <= Unit.ENGAGE_TURN_FIGHT_TOLERANCE,
			"it strikes exactly when its front is within the tolerance, as after a turn in place")
		if faced:
			break
	assert_true(faced, "and once the wheel brings its front to bear it fights")


func test_a_resquare_hold_shortens_the_wheel_and_the_rate_records_it() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(30.0))
	for i in range(30):
		_wheel_tick(u, e, i > 0)
	var free_rate: float = u._combat_wheel_rate
	assert_gt(absf(free_rate), 0.0, "sanity: the wheel is turning")
	# An order's re-square closing the same way the wheel turns holds the pivot back
	# (_hold_pivot_for_resquare), so the wheel takes less than its own step.
	u._grid_lag = -signf(free_rate) * deg_to_rad(40.0)
	u._grid_lag_resquare = true
	u._grid_lag_rate = signf(free_rate) * u.bounded_turn_rate()
	var prev: float = u.facing.angle()
	_wheel_tick(u, e, true)
	var turned: float = angle_difference(prev, u.facing.angle())
	assert_lt(absf(turned), absf(free_rate) * DT, "the hold shortens the wheel's step")
	assert_almost_eq(u._combat_wheel_rate, turned / DT, FACING_TOL,
		"the carried rate is the turn actually made")


func test_a_correction_within_the_snap_turn_still_snaps() -> void:
	var u := _make_block()
	var turn: float = 0.9 * u.combat_reface_snap_turn
	assert_gt(turn, u.bounded_turn_rate() * DT,
		"sanity: the correction is past one tick of the bounded rate")
	var e := _make_enemy(_bearing_point(rad_to_deg(turn)))
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"a correction within combat_reface_snap_turn snaps at once")


func test_the_snap_turn_is_configurable() -> void:
	var u := _make_block()
	u.combat_reface_snap_turn = deg_to_rad(40.0)
	var e := _make_enemy(_bearing_point(30.0))
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"a correction within a raised snap turn snaps at once")


func test_a_small_reface_out_of_contact_still_snaps() -> void:
	var u := _make_block()
	u._in_enemy_contact = false
	var e := _make_enemy(_bearing_point(30.0))
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"out of contact the re-face snaps as before")


func test_a_far_tier_block_still_snaps() -> void:
	var u := _make_block()
	u.tier = FormationTier.FAR
	var e := _make_enemy(_bearing_point(30.0))
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"a far-tier block has no bodies on its slots, so it snaps")


func test_a_large_offset_still_turns_in_place() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(120.0))
	assert_false(u._face_for_action(e.position, DT, e), "the strike waits while the block turns")
	assert_ne(u._engage_turn_target, Vector2.ZERO, "a turn-in-place is armed, as before")


func test_a_foot_block_in_contact_still_snaps() -> void:
	var u := _make_block()
	u.is_cavalry = false
	var e := _make_enemy(_bearing_point(30.0))
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"a compact foot block snaps onto its enemy as before")


func test_a_reface_onto_a_routing_enemy_still_snaps() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(30.0))
	e.state = Unit.State.ROUTING
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"a pursuer in contact keeps its front on a fleeing enemy")


func test_a_reface_onto_a_square_still_snaps() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(30.0))
	e.formation_mode = Unit.FORMATION_SQUARE
	assert_true(e.in_square(), "sanity: the enemy stands in a square")
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"a troop keeps snapping onto an omnidirectional block")


func test_an_enemy_inside_the_block_is_struck_while_the_wheel_turns() -> void:
	# The bearing from the anchor to an enemy among the ranks names no front, and one circling
	# close to the anchor can keep the heading a constant angle behind it.
	var u := _make_block()
	var e := _make_enemy(u.position + Vector2.DOWN.rotated(deg_to_rad(70.0)) * 10.0)
	assert_true(u._enemy_inside_own_footprint(e), "sanity: the enemy stands inside the footprint")
	assert_true(_wheel_tick(u, e, false), "the block strikes an enemy inside its own ranks")
	assert_lt(absf(Vector2.DOWN.angle_to(u.facing)), deg_to_rad(10.0), "while its heading still wheels")


func test_a_reversal_sheds_the_rate_through_zero() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(60.0))
	for i in range(60):
		_wheel_tick(u, e, i > 0)
	var rate: float = u._combat_wheel_rate
	assert_gt(rate, 0.0, "sanity: the wheel is turning toward the enemy")
	# The enemy crosses to the heading's other side: the wheel brakes at bounded_turn_accel and
	# carries on its old way this tick, rather than stopping dead.
	e.position = u.position + Vector2.from_angle(u.facing.angle() - deg_to_rad(40.0)) * 2000.0
	var radius: float = u._formation_local_half_extents().length()
	var prev: float = u.facing.angle()
	_wheel_tick(u, e, true)
	assert_almost_eq(u._combat_wheel_rate, rate - u.bounded_turn_accel(radius) * DT, FACING_TOL,
		"the rate sheds one tick of bounded_turn_accel")
	assert_gt(angle_difference(prev, u.facing.angle()), 0.0, "and the heading still turns its old way")


func test_an_enemy_sweeping_round_as_fast_as_the_wheel_is_still_struck() -> void:
	var u := _make_block()
	var deg := 60.0
	var e := _make_enemy(_bearing_point(deg))
	assert_false(_wheel_tick(u, e, false), "sanity: 60 degrees off, the first tick withholds")
	var struck := false
	for i in range(120):
		# The enemy's bearing moves on at the wheel's top rate, so the heading cannot close on it.
		deg += rad_to_deg(u.bounded_turn_rate() * DT)
		e.position = u.position + Vector2.DOWN.rotated(deg_to_rad(deg)) * 2000.0
		if _wheel_tick(u, e, true):
			struck = true
			break
	assert_true(struck, "a wheel that cannot close on its enemy does not withhold its blows for ever")


## The heading's offset (rad) from `e` as the block stands.
func _offset(u: Unit, e: Unit) -> float:
	return absf(angle_difference(u.facing.angle(), (e.position - u.position).angle()))


## A block whose wheel has run onto an enemy at `deg` degrees for 30 ticks, carrying a rate.
func _running_wheel(deg: float) -> Array:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(deg))
	for i in range(30):
		_wheel_tick(u, e, i > 0)
	return [u, e]


## A point `deg` degrees off `u`'s heading, `dist` wu from its anchor.
func _off_heading(u: Unit, deg: float, dist: float) -> Vector2:
	return u.position + Vector2.from_angle(u.facing.angle() + deg_to_rad(deg)) * dist


func test_a_running_wheel_keeps_wheeling_past_the_turn_threshold_onto_an_enemy_among_its_ranks() -> void:
	var pair: Array = _running_wheel(60.0)
	var u: Unit = pair[0]
	var e: Unit = pair[1]
	var rate: float = u._combat_wheel_rate
	assert_gt(rate, 0.0, "sanity: the wheel is turning")
	# The enemy's centre has come in among the ranks, and its bearing has run on past
	# ENGAGE_TURN_THRESHOLD, faster than the wheel can follow.
	e.position = _off_heading(u, 80.0, 10.0)
	assert_true(u._enemy_inside_own_footprint(e), "sanity: the enemy stands inside the footprint")
	assert_gt(_offset(u, e), Unit.ENGAGE_TURN_THRESHOLD, "sanity: past the turn-in-place threshold")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var radius: float = u._formation_local_half_extents().length()
	assert_true(_wheel_tick(u, e, true), "the block strikes an enemy among its ranks")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no turn in place is armed")
	assert_almost_eq(u._combat_wheel_rate, rate + u.bounded_turn_accel(radius) * DT, FACING_TOL,
		"the wheel carries on from its rate")
	assert_eq(u._formation_angle, 0.0, "the grid turns with the heading, nothing is folded")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), u.jog_speed * DT + SWEEP_TOL,
		"no slot sweeps faster than the men can jog")


func test_a_running_wheel_turns_in_place_past_the_threshold_onto_an_enemy_outside_its_ranks() -> void:
	var pair: Array = _running_wheel(60.0)
	var u: Unit = pair[0]
	var e: Unit = pair[1]
	e.position = _off_heading(u, 80.0, 2000.0)
	assert_false(u._enemy_inside_own_footprint(e), "sanity: the enemy stands outside the footprint")
	assert_false(_wheel_tick(u, e, true), "the strike waits while the block turns")
	assert_ne(u._engage_turn_target, Vector2.ZERO, "a turn in place is armed, as before")


func test_a_wheel_onto_a_new_enemy_past_the_threshold_turns_in_place_and_holds_its_blows() -> void:
	var pair: Array = _running_wheel(20.0)
	var u: Unit = pair[0]
	var flanker := _make_enemy(_off_heading(u, 150.0, 10.0))
	flanker.uid = 3
	assert_true(u._enemy_inside_own_footprint(flanker), "sanity: even one among the ranks")
	assert_false(_wheel_tick(u, flanker, true), "the strike waits while the block turns")
	assert_ne(u._engage_turn_target, Vector2.ZERO, "a new enemy past the threshold is turned onto in place")


func test_a_wheel_onto_a_new_enemy_starts_from_rest_and_judges_afresh() -> void:
	var pair: Array = _running_wheel(60.0)
	var u: Unit = pair[0]
	var other := _make_enemy(_off_heading(u, 70.0, 2000.0))
	other.uid = 3
	var radius: float = u._formation_local_half_extents().length()
	assert_false(_wheel_tick(u, other, true), "70 degrees off a new enemy, the block withholds")
	assert_almost_eq(absf(u._combat_wheel_rate), u.bounded_turn_accel(radius) * DT, FACING_TOL,
		"the wheel onto the new enemy starts from rest")
	assert_almost_eq(u._combat_wheel_offset, _offset(u, other), FACING_TOL,
		"and is judged from its offset now, not from the nearest it came to the first enemy")


func test_a_target_flipping_between_two_enemies_side_by_side_keeps_the_wheel_running() -> void:
	# A block holding its ground against two enemies pressed side by side can have its target
	# flip between them every tick. Their bearings lie closer than combat_reface_snap_turn, so
	# the wheel carries its rate across each flip and builds it exactly as onto one enemy.
	var u := _make_block()
	var a := _make_enemy(_bearing_point(60.0))
	var b := _make_enemy(_bearing_point(60.0 + 0.5 * rad_to_deg(u.combat_reface_snap_turn)))
	b.uid = 3
	var radius: float = u._formation_local_half_extents().length()
	var accel_step: float = u.bounded_turn_accel(radius) * DT
	var ticks := 30
	# Over the run the rate stays under the bounded rate and under sqrt(2 a d), so every tick
	# builds it by one accel_step: from rest it reaches ticks * accel_step.
	assert_lt(ticks * accel_step, u.bounded_turn_rate(radius), "sanity: the run stays under the rate cap")
	var faced_any := false
	for i in range(ticks):
		var e: Unit = a if i % 2 == 0 else b
		faced_any = _wheel_tick(u, e, i > 0) or faced_any
	# The rate is read back from the turn the float32 heading took, which costs well under 1% of
	# it here; a wheel restarted from rest on every flip would hold one accel_step, 1 / ticks of it.
	var built: float = ticks * accel_step
	assert_almost_eq(absf(u._combat_wheel_rate), built, 0.01 * built,
		"the rate built on every tick across the flips")
	assert_false(faced_any, "and the flips alone never let a blow through 60 degrees off")


func test_a_bearing_that_jumps_past_the_threshold_turns_in_place_and_holds_its_blows() -> void:
	var pair: Array = _running_wheel(60.0)
	var u: Unit = pair[0]
	var e: Unit = pair[1]
	# The same enemy, now straight behind the block.
	e.position = _off_heading(u, 179.0, 2000.0)
	assert_false(_wheel_tick(u, e, true), "the strike waits while the block turns")
	assert_ne(u._engage_turn_target, Vector2.ZERO, "a turn in place is armed")


func test_a_bearing_that_jumps_by_more_than_the_band_is_judged_afresh() -> void:
	var pair: Array = _running_wheel(20.0)
	var u: Unit = pair[0]
	var e: Unit = pair[1]
	# The same enemy jumps from about 20 to 70 degrees off, under the turn-in-place threshold: a
	# fresh re-face withholds until its front is within the tolerance, and so does the wheel.
	e.position = _off_heading(u, 70.0, 2000.0)
	var faced := false
	for i in range(600):
		faced = _wheel_tick(u, e, true)
		assert_eq(faced, _offset(u, e) <= Unit.ENGAGE_TURN_FIGHT_TOLERANCE,
			"tick %d: it strikes exactly when its front is within the tolerance" % i)
		if faced:
			break
	assert_true(faced, "and it comes round to strike")


func test_a_wheel_that_catches_up_again_holds_its_blows_as_it_comes_round() -> void:
	var u := _make_block()
	var deg := 60.0
	var e := _make_enemy(_bearing_point(deg))
	_wheel_tick(u, e, false)
	# The enemy draws away a tenth of the band a tick until the wheel has fallen behind ...
	var step: float = 0.1 * u.combat_reface_snap_turn
	var i := 0
	while not u._combat_wheel_behind and i < 600:
		deg += rad_to_deg(step)
		e.position = u.position + Vector2.DOWN.rotated(deg_to_rad(deg)) * 2000.0
		_wheel_tick(u, e, true)
		i += 1
	assert_true(u._combat_wheel_behind, "sanity: the wheel fell behind")
	# ... then stands, and the wheel closes on it.
	var furthest: float = u._combat_wheel_offset
	var caught_up := false
	for j in range(600):
		var faced: bool = _wheel_tick(u, e, true)
		var off: float = _offset(u, e)
		if off <= Unit.ENGAGE_TURN_FIGHT_TOLERANCE:
			break
		if off < furthest - u.combat_reface_snap_turn:
			caught_up = true
			assert_false(faced, "tick %d: %.2f degrees off and catching up, it withholds" % [j, rad_to_deg(off)])
	assert_true(caught_up, "sanity: the wheel came back more than the band before the tolerance")


func test_an_enemy_that_routs_mid_wheel_is_turned_onto_in_place_past_the_threshold() -> void:
	# A router among the ranks streaming out through the block is held against instead
	# (_router_streaming_through), as on main; this one leads the anchor along its line of
	# flight, so it is not streaming through, and stands inside the footprint, so only the
	# ROUTING clause of _combat_wheel_applies stops the wheel carrying on.
	var pair: Array = _running_wheel(60.0)
	var u: Unit = pair[0]
	var e: Unit = pair[1]
	e.position = _off_heading(u, 80.0, 10.0)
	assert_true(u._enemy_inside_own_footprint(e), "sanity: the router stands among the ranks")
	e.state = Unit.State.ROUTING
	e._flee_velocity = (e.position - u.position).normalized() * 50.0
	assert_false(u._router_streaming_through(e), "sanity: it leads the anchor, so it is not streaming through")
	_wheel_tick(u, e, true)
	assert_ne(u._engage_turn_target, Vector2.ZERO, "past the threshold a router is turned onto in place")


func test_a_block_that_drops_to_the_far_tier_mid_wheel_turns_in_place_past_the_threshold() -> void:
	var pair: Array = _running_wheel(60.0)
	var u: Unit = pair[0]
	var e: Unit = pair[1]
	e.position = _off_heading(u, 80.0, 10.0)
	assert_true(u._enemy_inside_own_footprint(e), "sanity: the enemy stands among the ranks")
	u.tier = FormationTier.FAR
	_wheel_tick(u, e, true)
	assert_ne(u._engage_turn_target, Vector2.ZERO, "past the threshold a far-tier block turns in place")


func test_a_wheel_that_ran_does_not_carry_on_onto_a_square() -> void:
	var pair: Array = _running_wheel(60.0)
	var u: Unit = pair[0]
	var e: Unit = pair[1]
	e.position = _off_heading(u, 80.0, 10.0)
	e.formation_mode = Unit.FORMATION_SQUARE
	assert_true(e.in_square(), "sanity: the enemy stands in a square")
	_wheel_tick(u, e, true)
	assert_ne(u._engage_turn_target, Vector2.ZERO, "past the threshold a square is turned onto in place")


func test_a_wheel_that_lost_contact_turns_in_place_past_the_threshold() -> void:
	var pair: Array = _running_wheel(60.0)
	var u: Unit = pair[0]
	var e: Unit = pair[1]
	u._in_enemy_contact = false
	e.position = _off_heading(u, 80.0, 10.0)
	_wheel_tick(u, e, true)
	assert_ne(u._engage_turn_target, Vector2.ZERO, "out of contact a large re-face turns in place")


func test_a_fresh_reface_past_the_threshold_turns_in_place_after_a_snap() -> void:
	# A snap ends the wheel, so the next large re-face is a fresh one, not a wheel carrying on.
	var u := _make_block()
	var e := _make_enemy(_bearing_point(0.5 * rad_to_deg(u.combat_reface_snap_turn)))
	u._face_for_action(e.position, DT, e)
	assert_eq(u._combat_wheel_tick, -2, "sanity: the small correction snapped")
	e.position = u.position + Vector2.DOWN.rotated(deg_to_rad(100.0)) * 10.0
	assert_false(u._face_for_action(e.position, DT, e), "the strike waits while the block turns")
	assert_ne(u._engage_turn_target, Vector2.ZERO, "a turn in place is armed")


func test_jitter_in_the_bearing_does_not_release_withheld_blows() -> void:
	var u := _make_block()
	var deg := 70.0
	var e := _make_enemy(_bearing_point(deg))
	# The bearing swings between +0.4 and -0.4 of combat_reface_snap_turn about a fixed enemy, so
	# it moves 0.8 of the band from one tick to the next: under the band, so no tick counts as
	# a jump, and the offset never stands more than 0.8 of the band above the nearest it has come.
	var jitter: float = 0.4 * u.combat_reface_snap_turn
	var ticks := 30
	# The wheel turns at most bounded_turn_rate a tick, less than the 0.8-band swing, so every
	# swing away from the heading raises the offset: every other tick, so at least ticks / 2 - 1
	# rises once the first tick has set the wheel going.
	assert_lt(u.bounded_turn_rate() * DT, 2.0 * jitter, "sanity: a swing away outruns one tick of the wheel")
	# And the wheel cannot close from 70 degrees to the tolerance within the run, so every tick
	# is one it must withhold on.
	assert_lt(u.bounded_turn_rate() * DT * ticks, deg_to_rad(deg) - Unit.ENGAGE_TURN_FIGHT_TOLERANCE - jitter,
		"sanity: the whole run stays past the tolerance")
	var withheld := 0
	var rose := 0
	var prev: float = INF
	for i in range(ticks):
		var sign_i: float = 1.0 if i % 2 == 0 else -1.0
		e.position = u.position + Vector2.DOWN.rotated(deg_to_rad(deg) + sign_i * jitter) * 2000.0
		var faced: bool = _wheel_tick(u, e, i > 0)
		var off: float = _offset(u, e)
		if off > prev:
			rose += 1
		prev = off
		assert_false(faced, "tick %d: %.2f degrees off, the block still withholds" % [i, rad_to_deg(off)])
		if not faced:
			withheld += 1
	assert_gte(rose, ticks / 2 - 1, "the offset rose on every swing away from the heading")
	assert_eq(withheld, ticks, "and every tick was a withheld one")


func test_a_wheel_that_falls_more_than_the_snap_turn_behind_strikes() -> void:
	var u := _make_block()
	var deg := 60.0
	var e := _make_enemy(_bearing_point(deg))
	assert_false(_wheel_tick(u, e, false), "sanity: 60 degrees off, the first tick withholds")
	var nearest: float = _offset(u, e)
	# The enemy draws away a tenth of the snap turn a tick, faster than the wheel closes.
	var step: float = 0.1 * u.combat_reface_snap_turn
	var struck := false
	for i in range(60):
		deg += rad_to_deg(step)
		e.position = u.position + Vector2.DOWN.rotated(deg_to_rad(deg)) * 2000.0
		var faced: bool = _wheel_tick(u, e, true)
		var off: float = _offset(u, e)
		nearest = minf(nearest, off)
		assert_eq(faced, off > nearest + u.combat_reface_snap_turn,
			"tick %d: it strikes once it is more than the snap turn behind its nearest" % i)
		struck = struck or faced
	assert_true(struck, "and it does fall that far behind")


func test_a_wheel_restored_from_a_snapshot_carries_on_at_its_saved_rate() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(60.0))
	for i in range(40):
		_wheel_tick(u, e, i > 0)
	var rate: float = u._combat_wheel_rate
	assert_gt(rate, 0.0, "sanity: the wheel is turning")
	u._combat_wheel_tick = Engine.get_physics_frames() - 1   # it ran on the tick before
	var d: Dictionary = u.to_snapshot_dict()
	var r := _make_block()
	r.apply_snapshot_dict(d)
	assert_eq(r._combat_wheel_tick, Engine.get_physics_frames() - 1,
		"the stamp is rebased onto the current clock")
	r._is_facing_turning = false
	r._facing_turn_step = 0.0
	var radius: float = r._formation_local_half_extents().length()
	r._face_for_action(e.position, DT, e)
	assert_almost_eq(r._combat_wheel_rate, rate + r.bounded_turn_accel(radius) * DT, 1e-4,
		"the restored wheel builds on its saved rate rather than starting from rest")


func test_a_wheel_closer_than_one_step_lands_exactly_on_the_bearing() -> void:
	var u := _make_block()
	var deg := 4.0
	assert_gt(deg_to_rad(deg), u.combat_reface_snap_turn, "sanity: past the snap turn, so it wheels")
	var e := _make_enemy(_bearing_point(deg))
	# A wheel still carrying a fast rate from the tick before: one tick's step at that rate is
	# longer than the offset left.
	u._combat_wheel_rate = 10.0
	u._combat_wheel_enemy_uid = e.uid   # onto this same enemy
	assert_gt(u._combat_wheel_rate * DT, deg_to_rad(deg), "sanity: one step overshoots the bearing")
	_wheel_tick(u, e, true)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"the heading stops on the bearing rather than past it")


func test_no_enemy_is_not_inside_the_footprint() -> void:
	var u := _make_block()
	assert_false(u._enemy_inside_own_footprint(null), "a missing enemy stands nowhere")
