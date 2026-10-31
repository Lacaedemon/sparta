extends GutTest
## Two readers of the slot grid's turn off the heading while the grid still trails it by a
## large lag: an order's re-square (Unit._square_fold_for_order) can stand the fold on its
## square line with the grid up to a quarter-turn off it, turning out at a bounded rate.
##
## - Unit.terrain_clearance must not under-clear: the fold alone names the wrong half-extent
##   while the grid stands a quarter-turn off it. It takes the corner man's clearance while
##   such a lag stands, which does not depend on the lag, so it cannot feed the lag back. A
##   march's small heading lag is still left out, as before.
## - Unit._apply_file_double_step must transpose a grid that stands a quarter-turn off its
##   heading, and drop the lag with the fold, since it squares the whole grid.

const START := Vector2(500.0, 500.0)
# A long, shallow block: its two half-extents differ a lot, so reading the wrong one shows.
const MEN := 60
const FILES := 15
# Float slack on a clearance (wu): built from float32 slot positions.
const CLEAR_EPS := 0.01   # tuned in wu, solver epsilon


func _unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = MEN
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers
	u.uid = 1
	u.team = 0
	u.position = START
	u.facing = Vector2.UP
	u.frontage_override = FILES
	u.seed_sim_soldiers()
	return u


## Stand an order's re-square on `u`: the fold on its square line, the grid `lag` off it.
func _stand_resquare(u: Unit, fold: float, lag: float) -> void:
	u._formation_angle = fold
	u._grid_lag = lag
	u._grid_lag_resquare = true


## The swept width (plus body radius) of `u`'s grid turned `turn` off its heading, marching
## along `dir`: what terrain_clearance reads for a grid standing at that turn.
func _swept(u: Unit, turn: float, dir: Vector2) -> float:
	var he: Vector2 = u._formation_local_half_extents()
	var axis: Vector2 = Vector2.RIGHT.rotated(u.facing.angle() + PI * 0.5 + turn)
	return he.x * absf(axis.cross(dir)) + he.y * absf(axis.dot(dir)) + u.soldier_body_radius()


func test_terrain_clearance_covers_a_grid_a_quarter_turn_off_its_fold() -> void:
	var u := _unit()
	_stand_resquare(u, 0.0, PI * 0.5)
	# Marching across the heading: a grid square to it sweeps its short depth, but this grid
	# stands a quarter-turn off and sweeps its long frontage.
	var travel: Vector2 = u.facing.orthogonal()
	var as_it_stands: float = _swept(u, u.grid_fold(), travel)
	assert_gt(as_it_stands, _swept(u, 0.0, travel) + 10.0,
			"setup: the grid as it stands sweeps more than the fold alone says")
	var clearance: float = u.terrain_clearance(travel)
	assert_almost_eq(clearance, u.corner_clearance(), CLEAR_EPS,
			"the corner man's clearance while an order's re-square stands")
	assert_gte(clearance, as_it_stands - CLEAR_EPS, "which covers the grid as it stands")


func test_terrain_clearance_under_a_resquare_lag_does_not_depend_on_the_lag() -> void:
	# Reading the lag fed it back: the clearance steered the march, which turned the heading
	# and the lag. While the re-square closes, the clearance holds still.
	var u := _unit()
	var travel: Vector2 = u.facing.rotated(deg_to_rad(30.0))
	var readings: Array[float] = []
	for deg in [90.0, 60.0, 30.0, 5.0]:
		_stand_resquare(u, 0.0, deg_to_rad(deg))
		readings.append(u.terrain_clearance(travel))
	for r in readings:
		assert_almost_eq(r, readings[0], CLEAR_EPS, "the same clearance whatever the lag")


func test_terrain_clearance_still_leaves_a_march_lag_out() -> void:
	# A small heading lag (not an order's re-square) is read as before: the fold alone.
	var u := _unit()
	u._grid_lag = deg_to_rad(20.0)
	u._grid_lag_resquare = false
	var travel: Vector2 = u.facing
	assert_almost_eq(u.terrain_clearance(travel), _swept(u, 0.0, travel), CLEAR_EPS,
			"the swept width of the grid square to the heading")


func test_a_file_double_transposes_a_grid_a_quarter_turn_off_its_fold() -> void:
	# The same grid, standing a quarter-turn off its heading, once all in the fold and once as
	# an order's re-square with the fold square: both widen across the way the men face.
	var folded := _unit()
	folded._formation_angle = PI * 0.5
	folded._apply_file_double_step(Order.new_file_double(1))
	var lagged := _unit()
	_stand_resquare(lagged, 0.0, PI * 0.5)
	lagged._resquare_pending = true
	lagged._grid_lag_rate = 0.3
	assert_true(lagged._holds_quarter_fold(), "the grid as it stands holds a quarter")
	lagged._apply_file_double_step(Order.new_file_double(1))
	assert_eq(UnitFormation.frontage(lagged), UnitFormation.frontage(folded),
			"the lagged grid is transposed before it widens, as the folded one is")
	assert_ne(UnitFormation.frontage(lagged),
			UnitFormation.widened_files(MEN, FILES),
			"rather than doubling its files along the depth")
	assert_eq(lagged._formation_angle, 0.0, "the fold is squared")
	assert_eq(lagged._grid_lag, 0.0, "and the lag with it")
	assert_eq(lagged._grid_lag_rate, 0.0, "which no longer turns")
	assert_false(lagged._grid_lag_resquare, "no re-square stands")
	assert_false(lagged._resquare_pending, "and none waits")


func test_a_file_double_keeps_a_lag_that_stands_the_grid_square() -> void:
	# A quarter fold with the lag turning the grid back onto its heading: the files already run
	# across the facing, so the step widens them as they stand and the lag goes on closing.
	var u := _unit()
	_stand_resquare(u, PI * 0.5, -PI * 0.5)
	assert_false(u._holds_quarter_fold(), "the grid as it stands is square")
	u._apply_file_double_step(Order.new_file_double(1))
	assert_eq(UnitFormation.frontage(u), UnitFormation.widened_files(MEN, FILES),
			"the files widen as they stand")
	assert_almost_eq(u._grid_lag, -PI * 0.5, 0.0001, "the lag still stands")
	assert_true(u._grid_lag_resquare, "as the order's re-square")
