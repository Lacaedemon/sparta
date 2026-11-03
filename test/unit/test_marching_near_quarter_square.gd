extends GutTest
## An order squaring a block that was marching when it came, whose half-turn would re-deal its men
## in depth (a short rank), keeps square, the line its grid stands on, up to MARCH_SQUARE_BAND past
## a quarter-turn (Unit.order_square_line, Unit._square_fold_for_order, Unit._march_keeps_line):
## it turns its whole fold out instead of being reflected, and a grid already reflected in depth
## (its fold dropped to square under a toggled mirror) is not reflected back. Whether the block is marching is read when
## the order comes, for the re-square, a re-run of it that waited, and a march correction of its
## lag, which re-runs the re-square only once the lag has grown past that band (Unit._reface).
##
## The regression this pins: a marching block split its fold about the nearer whole or half turn,
## so a fold a few degrees past a quarter was reflected by a half-turn and wheeled nearly a
## quarter-turn back, and one a few degrees short of it wheeled nearly a quarter-turn the other
## way (sweep_routers uid 4, 30 men on 8 files, whose first order re-square on the march stands 92
## to 99 degrees off on seeds 0, 1 and 3, and later ones 103 and 112 degrees off on seeds 1 and 3).

const START := Vector2(500.0, 500.0)
const PARTIAL_MEN := 118   # a short rear rank: the half-turn reflects it in depth
const FULL_MEN := 120
const FULL_FILES := 15   # 8 full ranks: the half-turn keeps the fold and moves no man
const NEAR_DEG := 5.0   # how far off a quarter the near-quarter folds stand
const ANGLE_EPS := 0.0001   # solver epsilon
const TICK: float = 1.0 / 60.0
const CLEAR_TICKS := 40   # past the 30-tick contact clear time


func _unit(men: int = PARTIAL_MEN, files: int = 0) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = men
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
func _marching_unit(men: int = PARTIAL_MEN, files: int = 0) -> Unit:
	var u := _unit(men, files)
	u.state = Unit.State.MOVING
	return u


func _reissue(u: Unit) -> void:
	u.set_current_order(Order.new_move(START + Vector2(0.0, -800.0)))
	u.start_order_response()


func _partial(u: Unit) -> bool:
	return u.soldiers % maxi(1, u.formation_files(u.soldiers)) != 0


func test_order_square_line_keeps_square_across_the_band() -> void:
	var band: float = rad_to_deg(Unit.MARCH_SQUARE_BAND)
	# [fold degrees, squares to]
	var cases: Array = [
		[90.0 - band - 0.1, 0.0], [90.0 + NEAR_DEG, 0.0], [90.0 + band - 0.1, 0.0],
		[90.0 + band + 0.1, 180.0], [180.0, 180.0],
	]
	for c in cases:
		for s in [1.0, -1.0]:
			var got: float = Unit.order_square_line(deg_to_rad(s * float(c[0])), false, true)
			assert_almost_eq(absf(rad_to_deg(got)), float(c[1]), 0.001,
					"%.1f degrees squares to %.0f" % [s * float(c[0]), float(c[1])])


func test_order_square_line_without_keeping_takes_the_nearer_split() -> void:
	var short: float = Unit.order_square_line(deg_to_rad(90.0 - NEAR_DEG), false, false)
	var past: float = Unit.order_square_line(deg_to_rad(90.0 + NEAR_DEG), false, false)
	assert_eq(short, 0.0, "short of a quarter squares")
	assert_almost_eq(absf(past), PI, ANGLE_EPS, "past a quarter takes the half-turn")


func test_a_block_keeping_square_is_never_redealt_at_the_quarter() -> void:
	var got: float = Unit.order_square_line(deg_to_rad(90.0 - NEAR_DEG), true, true)
	assert_eq(got, 0.0, "a marching block wheels a near-quarter fold out")


## A full grid keeps its fold on the half-turn as it stands (its half-turn moves no man), here
## 110 degrees off with the 70 degrees back to the half-turn still turning out. Once it loses men
## to a short rank, the next marching re-square wheels the grid round onto square rather than
## keeping the half-turn, which would now reflect the short rank in depth.
func test_a_full_grid_at_the_half_turn_that_lost_men_wheels_onto_square() -> void:
	var u := _marching_unit(FULL_MEN, FULL_FILES)
	assert_false(_partial(u), "setup: full ranks")
	_fold(u, 110.0)
	_reissue(u)
	assert_almost_eq(absf(u._formation_angle), PI, ANGLE_EPS, "setup: the half-turn kept as it stands")
	assert_almost_eq(absf(u._grid_lag), deg_to_rad(70.0), ANGLE_EPS, "setup: 70 degrees to turn")
	for i in [0, 1]:
		u._sim_soldier_hp[i] = 0.0
	SoldierMelee.reap(u, null)
	assert_true(_partial(u), "setup: a short rank now")
	_reissue(u)
	assert_eq(u._formation_angle, 0.0, "the grid squares")
	assert_almost_eq(absf(u._grid_lag), deg_to_rad(110.0), ANGLE_EPS,
			"and the whole 110 degrees turns out, nothing reflected in depth")


func test_a_marching_partial_block_wheels_a_fold_either_side_of_a_quarter_the_same_way() -> void:
	var lags: Array = []
	for deg in [90.0 - NEAR_DEG, 90.0 + NEAR_DEG]:
		var u := _marching_unit()
		assert_true(_partial(u), "setup: a short rear rank")
		_fold(u, deg)
		_reissue(u)
		assert_eq(u._last_redeal_tick, -1, "%.0f degrees: nothing is dealt again" % deg)
		assert_eq(u._formation_angle, 0.0, "%.0f degrees: the grid squares" % deg)
		assert_almost_eq(u._grid_lag, deg_to_rad(-deg), ANGLE_EPS,
				"%.0f degrees: the whole fold turns out" % deg)
		lags.append(u._grid_lag)
	assert_gt(float(lags[0]) * float(lags[1]), 0.0, "both turn out the same way")


## A full grid's half-turn moves no man (reform_ranks keeps its fold), so it takes the nearer
## split as before.
func test_a_marching_full_block_takes_the_nearer_split() -> void:
	var u := _marching_unit(FULL_MEN, FULL_FILES)
	assert_false(_partial(u), "setup: full ranks")
	_fold(u, 90.0 + NEAR_DEG)
	_reissue(u)
	assert_almost_eq(absf(u._formation_angle), PI, ANGLE_EPS, "past a quarter: the half-turn")
	assert_almost_eq(absf(u._grid_lag), deg_to_rad(90.0 - NEAR_DEG), ANGLE_EPS,
			"and the short way back")


## A partial block reflected in depth stands square under a toggled mirror, so the line it keeps
## is square: a later order whose fold has drifted back across a quarter does not reflect it
## back. Past the band, 120 degrees, it is reflected; its lag then stands 85 degrees off square.
func test_a_reflected_partial_block_is_not_reflected_back() -> void:
	var u := _marching_unit()
	var past: float = rad_to_deg(Unit.MARCH_SQUARE_BAND) + 90.0 + NEAR_DEG
	_fold(u, past)
	_reissue(u)
	assert_almost_eq(absf(u._grid_lag), deg_to_rad(180.0 - past), ANGLE_EPS,
			"setup: past the band it takes the half-turn, the short way left to turn")
	assert_eq(u._formation_angle, 0.0, "setup: its fold stands square under the reflection")
	assert_true(u._grid_lag_resquare, "setup: its lag still turns")
	for deg in [70.0, 90.0 + NEAR_DEG]:
		u._grid_lag = deg_to_rad(-deg)
		u._grid_lag_resquare = true
		_reissue(u)
		assert_almost_eq(u._grid_lag, deg_to_rad(-deg), ANGLE_EPS,
				"%.0f degrees: the lag turns out as it stands" % deg)


## The line kept is the grid's own, not a record of an earlier order: a reflection that finished
## long ago, then an order that waits on contact, still splits the new fold off the grid's line.
func test_a_deferred_resquare_after_a_finished_reflection_is_not_reflected_back() -> void:
	var u := _marching_unit()
	var past: float = rad_to_deg(Unit.MARCH_SQUARE_BAND) + 90.0 + NEAR_DEG
	_fold(u, past)
	_reissue(u)
	assert_almost_eq(absf(u._grid_lag), deg_to_rad(180.0 - past), ANGLE_EPS,
			"setup: reflected, the short way left to turn")
	u._grid_lag = 0.0   # the reflection's lag has turned out
	u._grid_lag_resquare = false
	_fold(u, 70.0)   # a new fold, then an order in contact
	u._in_enemy_contact = true
	_reissue(u)
	assert_true(u._resquare_pending, "setup: the re-square waits on the contact")
	u._in_enemy_contact = false
	for t in range(CLEAR_TICKS):
		u._advance_grid_lag(TICK)
		if not u._resquare_pending:
			break
	assert_false(u._resquare_pending, "the re-square ran")
	assert_eq(u._formation_angle, 0.0, "the grid stands square")
	assert_almost_eq(u._grid_lag, deg_to_rad(-70.0), deg_to_rad(2.0),
			"it is not reflected back: the new fold turns out as it stands")


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
	assert_almost_eq(absf(u._grid_lag), deg_to_rad(180.0 - 90.0 - NEAR_DEG - grow - 2.0), ANGLE_EPS,
			"the half-turn taken, the short way left to turn")


## A re-square that waited for the contact to clear runs as the order found the block, not as it
## stands once the order's march target is written: a block fighting when it is ordered to march
## splits about the nearer half-turn, and one already marching keeps its line.
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
			if not u._resquare_pending:
				break
		assert_false(u._resquare_pending, "marching %s: the re-square ran" % str(marching))
		var left: float = 90.0 + NEAR_DEG if marching else 90.0 - NEAR_DEG
		assert_almost_eq(absf(u._grid_lag), deg_to_rad(left), deg_to_rad(5.0),
				"marching %s: reflected only when the block was fighting" % str(marching))
