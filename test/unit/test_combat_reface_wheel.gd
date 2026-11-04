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
