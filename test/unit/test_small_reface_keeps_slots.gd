extends GutTest
## A march that turns its heading without a formed pivot (an undisciplined or hasty march) turns
## `facing` at once but, out of enemy contact, leaves its slot grid where the men stand
## (Unit._reface); the grid then turns after the heading no faster than the man on its farthest
## slot can follow (Unit._advance_grid_lag). In contact the grid still turns with the heading.
##
## The regression this pins: such a correction went through _face_dir unfolded, so the whole
## slot grid turned about the anchor in the same tick and a block's corner slots jumped by a
## chord of its corner radius.

const START := Vector2(500.0, 500.0)
const MEN := 120
# The correction: well under the snap-absorb threshold, so main leaves it unfolded.
const TURN_DEG := 35.0
# A correction still under the threshold, but wide enough that the grid's turn reaches its rate
# cap (checked in the test that uses it).
const WIDE_TURN_DEG := 70.0
# Ticks to follow the grid's turn for: past the bounded turn's settle time for TURN_DEG.
const TURN_TICKS := 240
# How far off the march destination lies (wu): far enough that the first tick only turns.
const MARCH_RANGE := 1000.0
# Float slack on a slot's position (wu): the grid is rebuilt through float32 facings.
const SLOT_EPS := 0.01   # tuned in wu, solver epsilon
# Float slack on an angle (rad).
const ANGLE_EPS := 0.0001   # solver epsilon
# The fed-forward gap must be under this share of the arrival-only gap. Measured on this
# staging the share is 0.13; 0.25 leaves about a factor-two margin.
const FED_GAP_SHARE := 0.25


func _unit(face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = MEN
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers
	u.uid = 1
	u.team = 0
	u.position = START
	u.facing = face
	u.seed_sim_soldiers()
	return u


func _tick() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


## The farthest any slot of `after` lies from its slot in `before` carried by `shift` (wu):
## how far the grid turned its slots about the anchor, beyond translating with it.
func _worst_slot_turn(before: PackedVector2Array, after: PackedVector2Array, shift: Vector2) -> float:
	var worst: float = 0.0
	for i in range(mini(before.size(), after.size())):
		worst = maxf(worst, after[i].distance_to(before[i] + shift))
	return worst


## The most one tick can move a slot by turning the grid: the farthest slot sits at the
## block's corner radius, and the grid turns at most jog_speed / radius rad/s.
func _slot_turn_bound(u: Unit) -> float:
	return u.jog_speed * _tick() + SLOT_EPS


func _bearing(deg: float) -> Vector2:
	return Vector2.UP.rotated(deg_to_rad(deg))


## Turn `u`'s heading `deg` degrees off north the way a march without a formed pivot does.
func _reface_to(u: Unit, deg: float) -> void:
	u._reface(_bearing(deg))


func test_an_undisciplined_march_turns_its_heading_but_not_its_grid() -> void:
	var u := _unit(Vector2.UP)
	u.disciplined = false
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var anchor_before: Vector2 = u.position
	u._move_to(START + _bearing(TURN_DEG) * MARCH_RANGE, _tick(), true)
	assert_almost_eq(angle_difference(u.facing.angle(), _bearing(TURN_DEG).angle()), 0.0, ANGLE_EPS,
			"the heading takes the travel direction at once, as before")
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_lte(_worst_slot_turn(before, after, u.position - anchor_before), _slot_turn_bound(u),
			"the slots only carry along with the anchor (main turned the grid %.0f degrees in one tick)"
			% TURN_DEG)


func test_a_hasty_march_turns_its_heading_but_not_its_grid() -> void:
	var u := _unit(Vector2.UP)
	u.set_current_order(Order.new_move(START + _bearing(TURN_DEG) * MARCH_RANGE))
	u.current_order.haste = true
	assert_true(u._is_move_order_in_haste(), "setup: a hasty order marches without a formed pivot")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var anchor_before: Vector2 = u.position
	u._move_to(START + _bearing(TURN_DEG) * MARCH_RANGE, _tick(), true)
	assert_lte(_worst_slot_turn(before, u.soldier_world_slots(u.soldiers), u.position - anchor_before),
			_slot_turn_bound(u), "the slots only carry along with the anchor")


func test_a_combat_march_still_snaps_its_grid_with_the_heading() -> void:
	# A chase or a caracole's peel follows a moving target; a grid trailing it changed where the
	# body coupling drew the anchor, so a combat (not orderly) march keeps main's snap, which
	# moves the farthest slot by the chord 2 R sin(theta / 2).
	var u := _unit(Vector2.UP)
	u.disciplined = false
	var radius: float = u._formation_local_half_extents().length()
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var anchor_before: Vector2 = u.position
	u._move_to(START + _bearing(TURN_DEG) * MARCH_RANGE, _tick())
	assert_eq(u._grid_lag, 0.0, "a combat march leaves no lag")
	assert_almost_eq(_worst_slot_turn(before, u.soldier_world_slots(u.soldiers), u.position - anchor_before),
			2.0 * radius * sin(deg_to_rad(TURN_DEG) * 0.5), 0.5,
			"the grid turned with the heading, as on main")


func test_a_lag_carried_into_contact_is_folded_where_the_grid_stands() -> void:
	# A hasty march that turns just before it meets the enemy arrives with its grid still
	# trailing; in contact the grid must not keep turning under men whose front is held.
	var u := _unit(Vector2.UP)
	u.set_current_order(Order.new_move(START + _bearing(TURN_DEG) * MARCH_RANGE))
	u.current_order.haste = true
	u._move_to(START + _bearing(TURN_DEG) * MARCH_RANGE, _tick(), true)
	var lag: float = u._grid_lag
	assert_ne(lag, 0.0, "setup: the march arrives with its grid trailing the heading")
	u._in_enemy_contact = true
	var fold_before: float = u._formation_angle
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for t in range(TURN_TICKS):
		u._advance_grid_lag(_tick())
		var now: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		assert_lte(_worst_slot_turn(slots, now, Vector2.ZERO), SLOT_EPS,
				"tick %d: the grid does not turn under the men in contact" % t)
		assert_eq(u._grid_lag_rate, 0.0, "tick %d: and feeds no turn forward" % t)
		slots = now
	assert_eq(u._grid_lag, 0.0, "the lag is folded")
	assert_almost_eq(u._formation_angle, fold_before + lag, ANGLE_EPS, "into _formation_angle")


func test_a_reface_in_contact_still_turns_the_grid_with_the_heading() -> void:
	# With its front men held against the enemy's, a grid left trailing the heading lets the
	# blocks grind into each other and holds a block that breaks in the press, so contact keeps
	# the old snap. A grid turned by the whole correction moves its farthest slot by the chord
	# 2 R sin(theta / 2).
	var u := _unit(Vector2.UP)
	u._in_enemy_contact = true
	var radius: float = u._formation_local_half_extents().length()
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	_reface_to(u, TURN_DEG)
	assert_eq(u._grid_lag, 0.0, "no lag is left in contact")
	assert_almost_eq(_worst_slot_turn(before, u.soldier_world_slots(u.soldiers), Vector2.ZERO),
			2.0 * radius * sin(deg_to_rad(TURN_DEG) * 0.5), 0.5,
			"the grid turned with the heading, as on main")


func test_the_grid_follows_the_heading_at_a_bounded_rate_until_square() -> void:
	var u := _unit(Vector2.UP)
	_reface_to(u, WIDE_TURN_DEG)
	var radius: float = u._formation_local_half_extents().length()
	assert_gt(radius, 0.0, "setup: the block has an extent")
	# The bounded profile (bounded_turn_step): the rate builds at a = body accel / radius up to
	# w = jog_speed / radius, and sheds again to stop on the heading. A turn of theta takes
	# theta / w + w / a when it reaches w, and 2 sqrt(theta / a) when it does not; two ticks
	# cover the stepping.
	var theta: float = deg_to_rad(WIDE_TURN_DEG)
	var w: float = u.jog_speed / radius
	var a: float = maxf(u.accel, SoldierBodies.BODY_ACCEL_FLOOR) / radius
	assert_gte(theta, w * w / a, "setup: the turn is wide enough to reach the rate cap")
	var settle: float = theta / w + w / a
	var ticks: int = ceili(settle / _tick()) + 2
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var rate: float = 0.0
	for t in range(ticks):
		u._advance_grid_lag(_tick())
		var now: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		assert_lte(_worst_slot_turn(slots, now, Vector2.ZERO), _slot_turn_bound(u),
				"tick %d: no slot moves sideways faster than jog_speed" % t)
		# The closing tick takes whatever is left, so only the ticks before it are paced.
		if u._grid_lag != 0.0:
			assert_lte(absf(u._grid_lag_rate - rate), a * _tick() + ANGLE_EPS,
					"tick %d: the turn rate changes no faster than the bodies can follow" % t)
		rate = u._grid_lag_rate
		slots = now
	assert_almost_eq(u._grid_lag, 0.0, ANGLE_EPS, "the grid is square to the heading within %d ticks" % ticks)
	assert_almost_eq(u._grid_lag_rate, 0.0, ANGLE_EPS, "and has stopped turning")
	u._advance_grid_lag(_tick())
	assert_eq(u._grid_lag_rate, 0.0, "a square grid feeds no turn forward to the bodies")


func test_the_lag_waits_while_the_heading_itself_turns() -> void:
	# A pivot or an in-place turn already moves the grid at its own bounded rate this tick; the
	# lag turning on top of it would sweep the corner slot faster than jog_speed.
	var u := _unit(Vector2.UP)
	_reface_to(u, TURN_DEG)
	var lag: float = u._grid_lag
	assert_ne(lag, 0.0, "setup: the grid trails the heading")
	u._is_facing_turning = true
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._advance_grid_lag(_tick())
	assert_eq(u._grid_lag, lag, "the lag waits on a turning tick")
	assert_eq(u._grid_lag_rate, 0.0, "and feeds nothing forward")
	assert_lte(_worst_slot_turn(before, u.soldier_world_slots(u.soldiers), Vector2.ZERO), SLOT_EPS,
			"so the lag moves no slot that tick")


func test_terrain_clearance_reads_the_heading_not_the_trailing_grid() -> void:
	# The clearance a march plans around is that of the block square to its heading, which the
	# lag closes on; read off the trailing grid it would steer the march, re-face it, and feed
	# the lag back.
	var u := _unit(Vector2.UP)
	_reface_to(u, TURN_DEG)
	assert_ne(u._grid_lag, 0.0, "setup: the grid trails the heading")
	var square := _unit(_bearing(TURN_DEG))
	var travel: Vector2 = _bearing(TURN_DEG + 20.0)
	assert_almost_eq(u.terrain_clearance(travel), square.terrain_clearance(travel), SLOT_EPS,
			"the same clearance as a block already square to that heading")


func test_a_lag_past_the_threshold_folds_where_the_grid_stands() -> void:
	# A heading swinging faster than the grid follows: three 30-degree corrections in a row
	# leave a 90-degree lag, past the threshold, so it is folded and the men turn in place.
	var u := _unit(Vector2.UP)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for k in range(1, 4):
		_reface_to(u, 30.0 * k)
	assert_almost_eq(angle_difference(u.facing.angle(), _bearing(90.0).angle()), 0.0, ANGLE_EPS,
			"the heading follows every correction")
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_lte(_worst_slot_turn(before, after, Vector2.ZERO), _slot_turn_bound(u),
			"the grid stays where it stood")
	assert_eq(u._grid_lag, 0.0, "the lag past the threshold is folded")
	assert_almost_eq(u._formation_angle, deg_to_rad(-90.0), ANGLE_EPS,
			"into _formation_angle, as one snap that large would be")


func test_a_rout_folds_the_lag_where_the_grid_stands() -> void:
	var u := _unit(Vector2.UP)
	_reface_to(u, TURN_DEG)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._rout()
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_eq(u._grid_lag, 0.0, "a router carries no lag: its own heading turn is bounded")
	assert_almost_eq(u._formation_angle, deg_to_rad(-TURN_DEG), ANGLE_EPS, "the lag is folded")
	assert_lte(_worst_slot_turn(before, after, Vector2.ZERO), _slot_turn_bound(u),
			"and the grid stays where it stood")


## The largest mean body-to-slot gap (wu) over the grid's turn after a TURN_DEG re-face, with
## the turn fed forward to the bodies or, when `fed` is false, hidden from SoldierBodies.step
## so the men chase their slots on the arrival term alone.
func _worst_mean_gap(fed: bool) -> float:
	var u := _unit(Vector2.UP)
	_reface_to(u, TURN_DEG)
	var worst: float = 0.0
	for _t in range(TURN_TICKS):
		u._advance_grid_lag(_tick())
		var rate: float = u._grid_lag_rate
		if not fed:
			u._grid_lag_rate = 0.0
		SoldierBodies.step(u, _tick())
		u._grid_lag_rate = rate
		var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		var total: float = 0.0
		for i in range(slots.size()):
			total += u._sim_soldier_pos[i].distance_to(slots[i])
		worst = maxf(worst, total / float(slots.size()))
	return worst


func test_the_bodies_turn_with_the_grid() -> void:
	# The grid's turn is fed forward to the bodies (SoldierBodies.step), as a router's is, so the
	# men move with their slots. Without it a man can only chase his slot on the arrival term,
	# whose speed sqrt(2 a d) matches the slot's sideways speed v only once he is v^2 / (2 a)
	# behind it, so the block trails its own grid through the whole turn.
	var fed: float = _worst_mean_gap(true)
	var chased: float = _worst_mean_gap(false)
	assert_gt(chased, 0.0, "setup: the grid turned")
	assert_lt(fed, chased * FED_GAP_SHARE,
			"fed forward, the men stay well inside the gap the arrival term alone leaves")
