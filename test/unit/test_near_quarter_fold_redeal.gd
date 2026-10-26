extends GutTest
## An order squaring a block that is not marching, whose grid stands within QUARTER_REDEAL_BAND
## of a quarter-turn off its heading, deals the ranks again at that quarter in one step, from
## where the men stand, and turns out only the rest at the bounded rate (Unit.order_square_line,
## Unit._square_fold_for_order), when the block is not too wide for it.
##
## The regression this pins: the re-square split every fold about its nearer whole or half turn,
## so a fold a few degrees short of a quarter wheeled nearly a quarter-turn about the block's
## centre, and one a few degrees past it was reflected by a half-turn and wheeled nearly a
## quarter-turn back (sweep_routers uid 4 squared -85.6 one way and -91.0 the other).

const START := Vector2(500.0, 500.0)
const MEN := 120
const NEAR_DEG := 5.0   # how far off a quarter the near-quarter folds stand
const OUTSIDE_DEG := 70.0   # a fold off a quarter by more than the band
const TICK: float = 1.0 / 60.0
const SETTLE_TICKS := 1500   # past the settle time of every walk measured below
const CLEAR_TICKS := 40   # past the 30-tick contact clear time
const ANGLE_EPS := 0.0001   # solver epsilon


func _unit(men: int = MEN, files: int = 0, file_major: bool = true) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = men
	add_child_autofree(u)
	u.position = START
	u.facing = Vector2.UP
	if files > 0:
		u.frontage_override = files
	u.file_major_reform_mode = Unit.ReformMode.FILE_MAJOR if file_major \
			else Unit.ReformMode.ROW_MAJOR
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


func _reissue(u: Unit) -> void:
	u.set_current_order(Order.new_move(START + Vector2(0.0, -800.0)))
	u.start_order_response()


func test_folds_either_side_of_a_quarter_take_the_same_quarter() -> void:
	var lags: Array = []
	for deg in [90.0 - NEAR_DEG, 90.0 + NEAR_DEG]:
		var u := _unit()
		_fold(u, deg)
		_reissue(u)
		assert_eq(u._formation_angle, 0.0, "%.0f degrees: the quarter is dealt again" % deg)
		assert_false(u._formation_mirror_x, "%.0f degrees: nothing is reflected" % deg)
		assert_true(u._grid_lag_resquare, "%.0f degrees: the rest turns out" % deg)
		assert_almost_eq(absf(u._grid_lag), deg_to_rad(NEAR_DEG), ANGLE_EPS,
				"%.0f degrees: only the part off the quarter is left to turn" % deg)
		lags.append(u._grid_lag)
	assert_lt(float(lags[0]) * float(lags[1]), 0.0, "the two turn out the same way back to it")


## The band and the shape cut were measured on blocks squared holding ground: a block already
## marching when the order comes keeps the split about the nearer whole or half turn.
func test_a_marching_block_keeps_the_nearer_half_turn_split() -> void:
	for marching in [false, true]:
		var u := _unit()
		_fold(u, 90.0 - NEAR_DEG)
		u.move_target = START + Vector2(300.0, 0.0)
		u.has_move_target = marching
		_reissue(u)
		var what: String = "marching" if marching else "standing"
		assert_eq(u._last_redeal_tick != -1, not marching, "%s: re-dealt only standing" % what)
		var off_quarter: float = deg_to_rad(NEAR_DEG) if not marching else deg_to_rad(90.0 - NEAR_DEG)
		assert_almost_eq(absf(u._grid_lag), off_quarter, ANGLE_EPS, "%s: the lag left to turn" % what)


## A re-square that waited for the contact to clear is not the order's own response to a block
## standing clear, so it too keeps the nearer whole or half turn.
func test_a_waiting_resquare_of_a_near_quarter_fold_keeps_the_half_turn_split() -> void:
	var u := _unit()
	_fold(u, 90.0 + NEAR_DEG)
	u._in_enemy_contact = true
	_reissue(u)
	assert_true(u._resquare_pending, "setup: the re-square waits on the contact")
	u._in_enemy_contact = false
	for t in range(CLEAR_TICKS):
		u._advance_grid_lag(TICK)
	assert_false(u._resquare_pending, "the re-square ran once the block was clear")
	assert_eq(u._last_redeal_tick, -1, "without a re-deal at the quarter")
	assert_almost_eq(absf(u._formation_angle), PI, ANGLE_EPS, "taking the half-turn")


## A block in square keeps its own square assignment through a quarter re-square
## (_pair_after_quarter_fold deals nothing from the men), so it is never re-dealt at the quarter.
func test_a_block_in_square_is_not_redealt() -> void:
	var u := _unit()
	u.formation_mode = Unit.FORMATION_SQUARE
	assert_true(u.in_square(), "setup: the block stands in square")
	assert_false(u._quarter_redeal_suits_shape(), "a square never suits the re-deal")
	_fold(u, 90.0 - NEAR_DEG)
	_reissue(u)
	assert_eq(u._last_redeal_tick, -1, "nothing is dealt again")


## The near-quarter re-deal is stamped for the demo defect scan, which judges the men's walk to
## the reshaped footprint as a reshape's transit. A wheel re-deals nothing and stamps nothing, and
## a fold already at a quarter is re-dealt as before and judged as before, unstamped.
func test_the_redeal_is_stamped_and_a_wheel_or_exact_quarter_is_not() -> void:
	var near := _unit()
	_fold(near, 90.0 - NEAR_DEG)
	_reissue(near)
	assert_eq(near._last_redeal_tick, Engine.get_physics_frames(), "the re-deal is stamped")
	var outside := _unit()
	_fold(outside, OUTSIDE_DEG)
	_reissue(outside)
	assert_eq(outside._last_redeal_tick, -1, "a wheel is not")
	var exact := _unit()
	_fold(exact, 90.0)
	_reissue(exact)
	assert_eq(exact._formation_angle, 0.0, "setup: the exact quarter is squared")
	assert_eq(exact._last_redeal_tick, -1, "nor is a fold already at a quarter")


## A line much wider than it is deep walks further re-dealt than turned out (120 men on 20 files
## near a quarter: 1.37 times as far on average over the band), so it turns its whole fold out
## even inside the band.
func test_a_wide_line_inside_the_band_turns_out_whole() -> void:
	var u := _unit(MEN, 20)
	assert_false(u._quarter_redeal_suits_shape(), "setup: 20 files on 6 ranks is too wide")
	_fold(u, 90.0 - NEAR_DEG)
	_reissue(u)
	assert_eq(u._last_redeal_tick, -1, "nothing is dealt again")
	assert_eq(u._formation_angle, 0.0, "the fold is all residue")
	assert_almost_eq(u._grid_lag, deg_to_rad(NEAR_DEG - 90.0), ANGLE_EPS, "the whole fold turns out")


func test_the_shape_gate_cuts_between_the_measured_blocks() -> void:
	# 90 men on 15 files stand on 6 ranks: 14 file pitches against 5 rank pitches, exactly 2.8.
	for c in [[60, 12, true], [84, 14, true], [MEN, 15, true], [90, 15, true], [MEN, 18, false],
			[48, 12, false]]:
		var u := _unit(int(c[0]), int(c[1]))
		assert_eq(u._quarter_redeal_suits_shape(), bool(c[2]),
				"%d men on %d files" % [int(c[0]), int(c[1])])


func test_a_fold_outside_the_band_still_turns_out_whole() -> void:
	var u := _unit()
	_fold(u, OUTSIDE_DEG)
	_reissue(u)
	assert_eq(u._formation_angle, 0.0, "nothing to deal again")
	assert_almost_eq(u._grid_lag, deg_to_rad(-OUTSIDE_DEG), ANGLE_EPS, "the whole fold turns out")


## Each man's mean walk and the men who end across the block's centreline from where they stood,
## from the order until the block has squared, holding ground.
func _squared_walk(u: Unit) -> Dictionary:
	var start: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var prev: PackedVector2Array = start
	u._square_fold_for_order(true, true)
	var total: float = 0.0
	for t in range(SETTLE_TICKS):
		u._physics_process(TICK)
		SoldierBodies.step(u, TICK)
		for i in range(u.soldiers):
			total += u._sim_soldier_pos[i].distance_to(prev[i])
		prev = u._sim_soldier_pos.duplicate()
	var lateral: Vector2 = u.facing.orthogonal()
	var half: float = u.file_pitch_wu() * 0.5
	var crossed: int = 0
	for i in range(u.soldiers):
		var a: float = (start[i] - u.position).dot(lateral)
		var b: float = (prev[i] - u.position).dot(lateral)
		if a * b < 0.0 and absf(a) > half and absf(b) > half:
			crossed += 1
	return {"mean": total / float(u.soldiers), "crossed": crossed, "lag": u._grid_lag}


## Measured on a 60-man, 8-file block 85 degrees off: the wheel walked each man 89.9 wu on
## average and crossed 20 of them over the centreline, in either layout; the re-deal walks 13.4
## (row major) and 10.3 (file major) and crosses at most one.
func test_a_near_quarter_redeal_walks_the_men_less_than_a_wheel() -> void:
	for file_major in [false, true]:
		var u := _unit(60, 8, file_major)
		var layout: String = "file major" if file_major else "row major"
		_fold(u, 90.0 - NEAR_DEG)
		var m: Dictionary = _squared_walk(u)
		assert_eq(float(m["lag"]), 0.0, "setup: the block squared (%s)" % layout)
		assert_lt(float(m["mean"]), 2.0 * u.file_pitch_wu(),
				"%s: each man walks %.1f wu on average" % [layout, float(m["mean"])])
		assert_lte(int(m["crossed"]), 1,
				"%s: %d men cross the centreline" % [layout, int(m["crossed"])])


func test_order_square_line_takes_the_quarter_only_within_the_band() -> void:
	var band: float = rad_to_deg(Unit.QUARTER_REDEAL_BAND)
	var cases: Array = [
		[0.0, 0.0], [90.0 - band - 0.1, 0.0], [90.0 - band + 0.1, 90.0], [90.0, 90.0],
		[90.0 + band - 0.1, 90.0], [90.0 + band + 0.1, 180.0], [180.0, 180.0],
	]
	for c in cases:
		for s in [1.0, -1.0]:
			var got: float = Unit.order_square_line(deg_to_rad(s * float(c[0])))
			assert_almost_eq(absf(rad_to_deg(got)), float(c[1]), 0.001,
					"%.1f degrees squares to %.0f" % [s * float(c[0]), float(c[1])])
			if got != 0.0 and float(c[1]) < 180.0:   # +-PI is one line, whichever sign
				assert_eq(signf(got), s, "%.1f degrees squares on its own side" % (s * float(c[0])))
