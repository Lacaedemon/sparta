extends GutTest
## An order squaring a block that is marching when it comes keeps the line its last re-square took
## across MARCH_SQUARE_BAND either side of a quarter-turn: a block last squared onto square turns
## its whole fold out, one last squared onto the half-turn is reflected again
## (Unit.order_square_line, Unit._square_fold_for_order), but only while it continues that
## re-square. Whether the block is marching is read when the order comes, for the re-square, a
## re-run of it that waited, and a march correction of its lag, which re-runs the re-square only
## once the lag has grown past that band (Unit._reface).
##
## The regression this pins: a marching block split its fold about the nearer whole or half turn,
## so a fold a few degrees past a quarter was reflected by a half-turn and wheeled nearly a
## quarter-turn back, and one a few degrees short of it wheeled nearly a quarter-turn the other
## way (sweep_routers uid 4, whose first order re-square on the march stands 92 to 99 degrees
## off on seeds 0, 1 and 3, and later ones 103 and 112 degrees off on seeds 1 and 3).

const START := Vector2(500.0, 500.0)
const MEN := 120
const NEAR_DEG := 5.0   # how far off a quarter the near-quarter folds stand
const ANGLE_EPS := 0.0001   # solver epsilon
const TICK: float = 1.0 / 60.0
const CLEAR_TICKS := 40   # past the 30-tick contact clear time


func _unit(files: int = 0) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = MEN
	add_child_autofree(u)
	if files > 0:
		u.frontage_override = files
	u.position = START
	u.facing = Vector2.UP
	u.seed_sim_soldiers()
	return u


## Fold `u`'s grid `deg` degrees the way an engage re-face leaves it -- the heading turned, the
## fold compensating so the grid stays put -- and settle every body on its slot.
func _fold(u: Unit, deg: float) -> void:
	u.facing = u.facing.rotated(deg_to_rad(deg))
	u._formation_angle = wrapf(u._formation_angle - deg_to_rad(deg), -PI, PI)
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]


## A block on an attack or a chase: MOVING with no march target of its own.
func _marching_unit() -> Unit:
	var u := _unit()
	u.state = Unit.State.MOVING
	return u


func _reissue(u: Unit) -> void:
	u.set_current_order(Order.new_move(START + Vector2(0.0, -800.0)))
	u.start_order_response()


func test_order_square_line_keeps_the_last_line_across_the_band_on_the_march() -> void:
	var band: float = rad_to_deg(Unit.MARCH_SQUARE_BAND)
	# [fold degrees, reflected last, squares to]
	var cases: Array = [
		[90.0 - band - 0.1, false, 0.0], [90.0 + NEAR_DEG, false, 0.0],
		[90.0 + band - 0.1, false, 0.0], [90.0 + band + 0.1, false, 180.0],
		[90.0 - band - 0.1, true, 0.0], [90.0 - band + 0.1, true, 180.0],
		[90.0 - NEAR_DEG, true, 180.0], [90.0 + band + 0.1, true, 180.0],
	]
	for c in cases:
		for s in [1.0, -1.0]:
			var got: float = Unit.order_square_line(deg_to_rad(s * float(c[0])), false, true,
					bool(c[1]))
			assert_almost_eq(absf(rad_to_deg(got)), float(c[2]), 0.001,
					"%.1f degrees, reflected last %s, squares to %.0f" % [s * float(c[0]),
					str(c[1]), float(c[2])])


func test_order_square_line_off_the_march_takes_the_nearer_split_whatever_came_last() -> void:
	for reflected in [false, true]:
		var short: float = Unit.order_square_line(deg_to_rad(90.0 - NEAR_DEG), false, false,
				reflected)
		var past: float = Unit.order_square_line(deg_to_rad(90.0 + NEAR_DEG), false, false,
				reflected)
		assert_eq(short, 0.0, "reflected last %s: short of a quarter squares" % str(reflected))
		assert_almost_eq(absf(past), PI, ANGLE_EPS,
				"reflected last %s: past a quarter takes the half-turn" % str(reflected))


func test_a_marching_block_is_never_redealt_at_the_quarter() -> void:
	var got: float = Unit.order_square_line(deg_to_rad(90.0 - NEAR_DEG), true, true, false)
	assert_eq(got, 0.0, "a marching block wheels a near-quarter fold out")


func test_a_marching_block_wheels_a_fold_either_side_of_a_quarter_the_same_way() -> void:
	var lags: Array = []
	for deg in [90.0 - NEAR_DEG, 90.0 + NEAR_DEG]:
		var u := _marching_unit()
		_fold(u, deg)
		_reissue(u)
		assert_eq(u._last_redeal_tick, -1, "%.0f degrees: nothing is dealt again" % deg)
		assert_eq(u._formation_angle, 0.0, "%.0f degrees: the grid squares, unreflected" % deg)
		assert_false(u._order_square_reflected, "%.0f degrees: recorded as squared" % deg)
		assert_almost_eq(u._grid_lag, deg_to_rad(-deg), ANGLE_EPS,
				"%.0f degrees: the whole fold turns out" % deg)
		lags.append(u._grid_lag)
	assert_gt(float(lags[0]) * float(lags[1]), 0.0, "both turn out the same way")


## A reflected re-square whose lag is still turning: a fold past the band, reflected, with the
## lag then set so the grid stands `deg` degrees off on the same side.
func _reflected_and_turning(u: Unit, deg: float) -> void:
	_fold(u, rad_to_deg(Unit.MARCH_SQUARE_BAND) + 90.0 + NEAR_DEG)
	_reissue(u)
	assert_almost_eq(absf(u._formation_angle), PI, ANGLE_EPS, "setup: past the band, reflected")
	assert_true(u._order_square_reflected, "setup: recorded as reflected")
	assert_true(u._grid_lag_resquare, "setup: its lag still turns")
	u._grid_lag = wrapf(deg_to_rad(-deg) - u._formation_angle, -PI, PI)


func test_a_marching_block_continuing_a_reflection_is_reflected_again_short_of_a_quarter() -> void:
	var u := _marching_unit()
	_reflected_and_turning(u, 90.0 - NEAR_DEG)
	_reissue(u)
	assert_almost_eq(absf(u._formation_angle), PI, ANGLE_EPS, "the half-turn is taken again")
	assert_true(u._order_square_reflected, "and recorded")
	assert_almost_eq(absf(u._grid_lag), deg_to_rad(90.0 + NEAR_DEG), ANGLE_EPS,
			"the rest turns out the other way")


## The last line is kept only while the re-square it came from still runs: once that one has
## finished, a later fold of its own is split as if nothing came before it.
func test_a_finished_reflection_does_not_change_a_later_fold() -> void:
	for deg in [70.0, 90.0 - NEAR_DEG]:
		var u := _marching_unit()
		_reflected_and_turning(u, 90.0 - NEAR_DEG)
		u._grid_lag = 0.0   # the reflection's lag has turned out
		u._grid_lag_resquare = false
		u._formation_angle = deg_to_rad(-deg)   # and a new, unrelated fold
		assert_true(u._order_square_reflected, "setup: the flag still says reflected")
		_reissue(u)
		assert_eq(u._formation_angle, 0.0, "%.0f degrees: the grid squares, unreflected" % deg)
		assert_almost_eq(u._grid_lag, deg_to_rad(-deg), ANGLE_EPS,
				"%.0f degrees: the whole fold turns out" % deg)
		assert_false(u._order_square_reflected, "%.0f degrees: recorded as squared" % deg)


## A re-square in one step (an exact quarter here) leaves no reflection to continue.
func test_a_one_step_resquare_clears_the_last_line() -> void:
	var u := _marching_unit()
	_reflected_and_turning(u, 90.0 - NEAR_DEG)
	u._grid_lag = 0.0
	u._grid_lag_resquare = false
	u._formation_angle = -PI * 0.5
	_reissue(u)
	assert_false(u._order_square_reflected, "the exact quarter is dealt again, nothing reflected")


func test_a_standing_block_off_the_band_ignores_the_last_line() -> void:
	# 120 men on 20 files are too wide for the quarter re-deal, so a standing block splits about
	# the nearer whole or half turn.
	var u := _unit(20)
	assert_false(u._quarter_redeal_suits_shape(), "setup: too wide to re-deal")
	_fold(u, 90.0 - NEAR_DEG)
	u._order_square_reflected = true
	_reissue(u)
	assert_eq(u._formation_angle, 0.0, "short of a quarter it squares")
	assert_false(u._order_square_reflected, "and records that")


## A march's heading correction grows an order's re-square lag on a marching block: up to a
## quarter-turn plus the band the lag stands, past it the re-square runs again from the grown
## fold and takes the half-turn.
func test_a_march_correction_reruns_the_resquare_only_past_the_band() -> void:
	var u := _marching_unit()
	_fold(u, 90.0 + NEAR_DEG)
	_reissue(u)
	var lag: float = u._grid_lag
	assert_almost_eq(absf(lag), deg_to_rad(90.0 + NEAR_DEG), ANGLE_EPS, "setup: all residue")
	var grow: float = rad_to_deg(Unit.MARCH_SQUARE_BAND) - NEAR_DEG - 1.0
	u._reface(u.facing.rotated(-signf(lag) * deg_to_rad(grow)))
	assert_false(u._resquare_pending, "inside the band the grown lag stands")
	assert_almost_eq(absf(u._grid_lag), deg_to_rad(90.0 + NEAR_DEG + grow), ANGLE_EPS,
			"as it is")
	assert_true(u._grid_lag_resquare, "and is still the order's re-square")
	u._reface(u.facing.rotated(-signf(lag) * deg_to_rad(2.0)))   # one degree past the band
	assert_true(u._resquare_pending, "past the band the re-square waits to run again")
	u._advance_grid_lag(TICK)
	assert_false(u._resquare_pending, "it runs in the same tick's grid advance")
	assert_almost_eq(absf(u._formation_angle), PI, ANGLE_EPS, "taking the half-turn")
	assert_true(u._order_square_reflected, "recorded as reflected")


## A re-square that waited for the contact to clear runs as the order found the block, not as it
## stands once the order's march target is written: a block fighting when it is ordered to march
## splits about the nearer half-turn, and one already marching keeps the band.
func test_a_waiting_resquare_reads_whether_the_block_marched_when_the_order_came() -> void:
	for marching in [false, true]:
		var u := _unit()
		if marching:
			u.state = Unit.State.MOVING
		_fold(u, 90.0 + NEAR_DEG)
		u._in_enemy_contact = true
		_reissue(u)
		assert_true(u._resquare_pending, "setup: the re-square waits on the contact")
		# The order's march target is written after the response (Battle), and the block marches.
		u.has_move_target = true
		u.move_target = START + Vector2(0.0, -800.0)
		u.state = Unit.State.MOVING
		u._in_enemy_contact = false
		for t in range(CLEAR_TICKS):
			u._advance_grid_lag(TICK)
		assert_false(u._resquare_pending, "marching %s: the re-square ran" % str(marching))
		if marching:
			assert_eq(u._formation_angle, 0.0, "marching when ordered: the fold wheels out")
		else:
			assert_almost_eq(absf(u._formation_angle), PI, ANGLE_EPS,
					"fighting when ordered: the nearer half-turn")


## A lag standing on a quarter line (a near-quarter re-deal) is not one the band keeps: a march
## correction past a quarter-turn re-runs its re-square, marching or not.
func test_a_lag_on_a_quarter_line_reruns_past_a_quarter_turn() -> void:
	for line in [0.0, -PI * 0.5]:
		var u := _marching_unit()
		u._order_square_marching = true
		u._formation_angle = line
		u._grid_lag = deg_to_rad(-(90.0 - 2.0))
		u._grid_lag_resquare = true
		u._reface(u.facing.rotated(deg_to_rad(5.0)))   # grows the lag to 93 degrees
		if line == 0.0:
			assert_false(u._resquare_pending, "on the square line the band keeps the lag")
			assert_almost_eq(u._grid_lag, deg_to_rad(-93.0), ANGLE_EPS, "as it is")
		else:
			assert_true(u._resquare_pending, "on a quarter line the re-square waits to run again")
			assert_eq(u._grid_lag, 0.0, "its lag folded where it stands")
