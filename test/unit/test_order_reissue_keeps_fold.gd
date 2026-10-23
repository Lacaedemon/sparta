extends GutTest
## A fresh order squares a folded block back to its heading (Unit.start_order_response), but
## never by swinging the slot grid under the men in one tick (Unit._square_fold_for_order). A
## block in enemy contact keeps its fold until it is out; then the fold's nearer whole or half
## turn is reflected in place, and the residue is turned out after the heading at the bounded
## grid-turn rate.
##
## The regression this pins: reform_ranks dropped the whole fold at once, so an order the AI
## re-issued mid-fight swung a 120-man block's grid by 155 degrees in one tick (the
## battle_ai_leaders clip on its fourth perturbed seed), and a turn-in-place in progress was
## dropped with its partial turn still on the grid.

const START := Vector2(500.0, 500.0)
const MEN := 120
# A block with a short rear rank: the half-turn part of its fold is reflected in depth.
const PARTIAL_MEN := 116
# An engage re-face fold near a half-turn: a 180-degree half and a -24 degree residue.
const FOLD_DEG := 156.0
# A fold well off any whole, half or quarter turn: all residue.
const SKEW_DEG := 40.0
# Ticks to follow the residue's turn for: past its bounded settle time at either fold.
const TURN_TICKS := 600
# Float slack on a slot's position (wu): the grid is rebuilt through float32 facings.
const SLOT_EPS := 0.01   # tuned in wu, solver epsilon
const ANGLE_EPS := 0.0001   # solver epsilon


func _unit(men: int = MEN) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = men
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers
	u.uid = 1
	u.team = 0
	u.position = START
	u.facing = Vector2.UP
	u.seed_sim_soldiers()
	return u


func _tick() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


## Fold `u`'s grid `deg` degrees the way an engage re-face leaves it -- the heading turned, the
## fold compensating so the grid stays put -- and settle every body on its slot.
func _fold(u: Unit, deg: float) -> void:
	u.facing = u.facing.rotated(deg_to_rad(deg))
	u._formation_angle = wrapf(u._formation_angle - deg_to_rad(deg), -PI, PI)
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]


func _reissue(u: Unit) -> void:
	u.set_current_order(Order.new_move(START + Vector2(0.0, -800.0)))
	u.start_order_response()


## The farthest any slot of `after` lies from its slot in `before` (wu).
func _worst_move(before: PackedVector2Array, after: PackedVector2Array) -> float:
	var worst: float = 0.0
	for i in range(mini(before.size(), after.size())):
		worst = maxf(worst, after[i].distance_to(before[i]))
	return worst


## The most one tick of the bounded grid turn moves a slot: the farthest slot sits at the
## block's corner radius, and the grid turns at most jog_speed / radius rad/s.
func _turn_bound(u: Unit) -> float:
	return u.jog_speed * _tick() + SLOT_EPS


## Advance `u`'s grid lag `ticks` ticks, asserting each tick moves no slot faster than the
## bounded turn; returns how far the slots moved in all.
func _follow_lag(u: Unit, ticks: int) -> float:
	var start: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var slots: PackedVector2Array = start
	for t in range(ticks):
		u._advance_grid_lag(_tick())
		var now: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		assert_lte(_worst_move(slots, now), _turn_bound(u), "tick %d: a bounded turn" % t)
		slots = now
	return _worst_move(start, slots)


func test_a_fighting_block_keeps_its_slots_when_its_order_is_reissued() -> void:
	var u := _unit()
	assert_eq(u.soldiers % u.formation_files(u.soldiers), 0, "setup: a full grid")
	_fold(u, FOLD_DEG)
	u._in_enemy_contact = true
	u.state = Unit.State.FIGHTING
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var fold: float = u._formation_angle
	_reissue(u)
	# main dropped the fold here, moving the farthest slot 2 R sin(78 deg), about 1.96 R.
	assert_lte(_worst_move(before, u.soldier_world_slots(u.soldiers)), SLOT_EPS,
			"no slot moves on the re-issue")
	assert_eq(u._formation_angle, fold, "the fold is kept as it stands")
	assert_eq(u._grid_lag, 0.0, "with nothing lagged")
	assert_true(u._resquare_pending, "the re-square waits for the block to be out of contact")
	assert_lte(_follow_lag(u, TURN_TICKS), SLOT_EPS, "and nothing turns while it is in contact")


func test_the_waiting_resquare_turns_out_at_a_bounded_rate_once_out_of_contact() -> void:
	var u := _unit()
	_fold(u, FOLD_DEG)
	u._in_enemy_contact = true
	_reissue(u)
	u._in_enemy_contact = false
	assert_gt(_follow_lag(u, TURN_TICKS), 1.0, "the grid turns once the block is out")
	assert_false(u._resquare_pending, "the waiting re-square ran")
	assert_almost_eq(absf(u._formation_angle), PI, ANGLE_EPS, "its half-turn left folded")
	assert_almost_eq(u._grid_lag, 0.0, ANGLE_EPS, "and its residue turned out to square")
	assert_false(u._grid_lag_resquare, "so the re-square is done")


func test_a_resquare_carried_into_contact_waits_again() -> void:
	var u := _unit()
	_fold(u, SKEW_DEG)
	_reissue(u)
	assert_true(u._grid_lag_resquare, "setup: the re-square is turning out")
	u._in_enemy_contact = true
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._advance_grid_lag(_tick())
	assert_lte(_worst_move(before, u.soldier_world_slots(u.soldiers)), SLOT_EPS,
			"the grid stops where it stands")
	assert_true(u._resquare_pending, "and the rest of the re-square waits for the contact to end")


func test_a_rout_drops_a_waiting_resquare() -> void:
	var u := _unit()
	_fold(u, FOLD_DEG)
	u._in_enemy_contact = true
	_reissue(u)
	u._rout()
	assert_false(u._resquare_pending, "the rally squares the fold instead")


func test_a_partial_block_steps_no_man_more_than_a_rank_on_an_order() -> void:
	var u := _unit(PARTIAL_MEN)
	assert_ne(u.soldiers % u.formation_files(u.soldiers), 0, "setup: a short rear rank")
	_fold(u, FOLD_DEG)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	_reissue(u)
	assert_true(u._formation_mirror_x, "setup: the half-turn is reflected in depth")
	assert_lte(_worst_move(before, u.soldier_world_slots(u.soldiers)), u.rank_pitch_wu() + SLOT_EPS,
			"which moves a short file's men one rank at most")


func test_an_order_out_of_contact_turns_a_skewed_fold_out_gradually() -> void:
	var u := _unit()
	_fold(u, SKEW_DEG)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	_reissue(u)
	assert_lte(_worst_move(before, u.soldier_world_slots(u.soldiers)), SLOT_EPS,
			"no slot moves on the order")
	assert_eq(u._formation_angle, 0.0, "the fold is all residue")
	_follow_lag(u, TURN_TICKS)
	assert_almost_eq(u.grid_fold(), 0.0, ANGLE_EPS, "the grid ends square to the heading")


func test_an_engage_turn_in_progress_is_folded_where_the_men_stand() -> void:
	var u := _unit()
	var held: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._engage_turn_start_facing = u.facing
	u._engage_turn_target = Vector2.RIGHT
	u.facing = u.facing.rotated(deg_to_rad(30.0))   # a third of the turn done, the men waiting
	_reissue(u)
	assert_eq(u._engage_turn_target, Vector2.ZERO, "the order supersedes the turn")
	assert_lte(_worst_move(held, u.soldier_world_slots(u.soldiers)), SLOT_EPS,
			"the slots return under the men instead of staying turned")


func test_a_quarter_fold_in_contact_waits_too() -> void:
	var u := _unit()
	_fold(u, 90.0)
	u._in_enemy_contact = true
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	_reissue(u)
	assert_lte(_worst_move(before, u.soldier_world_slots(u.soldiers)), SLOT_EPS,
			"a quarter fold is not re-dealt under men held against the enemy")


func test_a_quarter_fold_out_of_contact_is_still_dealt_square_at_once() -> void:
	# The deliberate re-square: the men take the nearest cells of the squared grid where they
	# stand, as a frontage reshape does, rather than wheeling the block about its centre.
	var u := _unit()
	_fold(u, 90.0)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	_reissue(u)
	assert_eq(u._formation_angle, 0.0, "the quarter fold is squared")
	assert_eq(u._grid_lag, 0.0, "at once, with nothing lagged")
	assert_gt(_worst_move(before, u.soldier_world_slots(u.soldiers)), u.file_pitch_wu(),
			"the grid's axes swap in the one tick, as before")


func test_a_reface_shrinking_a_resquare_lag_past_the_threshold_keeps_it() -> void:
	var u := _unit()
	_fold(u, 85.0)   # off a quarter by more than the re-deal's tolerance: all residue
	_reissue(u)
	var lag: float = u._grid_lag
	assert_gt(absf(lag), Unit.FACING_SNAP_ABSORB_THRESHOLD, "setup: the lag stands past the threshold")
	u._reface(u.facing.rotated(signf(lag) * deg_to_rad(5.0)))
	assert_true(u._grid_lag_resquare, "a correction that closes the lag does not fold it")
	assert_lt(absf(u._grid_lag), absf(lag), "and shrinks it")
