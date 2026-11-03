extends GutTest
## Two readers of the slot grid's turn off the heading while the grid still trails it by a
## large lag: an order's re-square (Unit._square_fold_for_order) can stand the fold on its
## square line with the grid up to a quarter-turn off it, turning out at a bounded rate, and the
## lag always closes onto the fold.
##
## - Unit.terrain_clearance must not under-clear: the fold alone names the wrong half-extent
##   while the grid stands far off it. While an order's re-square stands it takes the widest
##   swept width over the angles the grid has still to turn through, which narrows onto the
##   fold's own width as the lag closes. A march's small heading lag is still left out.
## - Unit._apply_file_double_step must leave the files across the facing both where the grid
##   stands and once the lag has closed.

const START := Vector2(500.0, 500.0)
# A long, shallow block: its two half-extents differ a lot, so reading the wrong one shows.
const MEN := 60
const FILES := 15
# Float slack on a clearance (wu): built from float32 slot positions.
const CLEAR_EPS := 0.01   # tuned in wu, solver epsilon
# Angles the reference maximum samples over an interval.
const SAMPLES := 2000


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


## Stand an order's re-square on `u`: the fold at `fold`, the grid `lag` off it.
func _stand_resquare(u: Unit, fold: float, lag: float) -> void:
	u._formation_angle = fold
	u._grid_lag = lag
	u._grid_lag_resquare = true


## The swept width (plus body radius) of `u`'s grid turned `turn` off its heading, marching
## along `dir`.
func _swept(u: Unit, turn: float, dir: Vector2) -> float:
	var he: Vector2 = u._formation_local_half_extents()
	var axis: Vector2 = Vector2.RIGHT.rotated(u.facing.angle() + PI * 0.5 + turn)
	return he.x * absf(axis.cross(dir)) + he.y * absf(axis.dot(dir)) + u.soldier_body_radius()


## The widest swept width over the grid turns from `from_turn` through `to_turn`, by sampling.
func _sampled_max(u: Unit, from_turn: float, to_turn: float, dir: Vector2) -> float:
	var best: float = 0.0
	for k in range(SAMPLES + 1):
		best = maxf(best, _swept(u, lerpf(from_turn, to_turn, float(k) / SAMPLES), dir))
	return best


## Let the lag close onto the fold, as _advance_grid_lag does over the coming ticks.
func _close_lag(u: Unit) -> void:
	u._grid_lag = 0.0
	u._grid_lag_resquare = false


## Whether a grid turned `turn` off its heading lies nearer a quarter turn than square or a
## half-turn, so its files run nearer the depth than across the facing.
func _quarter_off(turn: float) -> bool:
	return roundi(wrapf(turn, -PI, PI) / (PI * 0.5)) % 2 != 0


func test_terrain_clearance_covers_every_angle_a_large_lag_still_turns_through() -> void:
	# Marching across the heading: the fold square to it sweeps the short depth, but the grid
	# stands 60 degrees off and turns back through every angle in between.
	var u := _unit()
	var lag: float = deg_to_rad(60.0)
	_stand_resquare(u, 0.0, lag)
	var travel: Vector2 = u.facing.orthogonal()
	var expected: float = _sampled_max(u, 0.0, lag, travel)
	assert_gt(expected, _swept(u, 0.0, travel) + 10.0,
			"setup: the angles still to turn through sweep far more than the fold alone")
	assert_almost_eq(u.terrain_clearance(travel), expected, 0.05,
			"the widest swept width over the angles from the fold to where the grid stands")


func test_terrain_clearance_reaches_the_corner_when_the_lag_turns_through_a_diagonal() -> void:
	var u := _unit()
	_stand_resquare(u, 0.0, PI * 0.5)
	var travel: Vector2 = u.facing.orthogonal()
	assert_almost_eq(u.terrain_clearance(travel), u.corner_clearance(), CLEAR_EPS,
			"a quarter-turn lag sweeps through the diagonal, so it clears the corner man")


func test_terrain_clearance_for_a_small_residue_is_about_the_folds_swept_width() -> void:
	# No jump to the corner man's clearance for a few degrees of residue, and none when it closes.
	var u := _unit()
	var travel: Vector2 = u.facing.orthogonal()
	var square: float = _swept(u, 0.0, travel)
	_stand_resquare(u, 0.0, deg_to_rad(2.0))
	var residue: float = u.terrain_clearance(travel)
	assert_lt(residue, u.corner_clearance() - 20.0, "far below the corner man's clearance")
	assert_almost_eq(residue, _sampled_max(u, 0.0, deg_to_rad(2.0), travel), 0.05,
			"the widest swept width over the 2 degrees left")
	assert_almost_eq(residue, square, 5.0, "within a few wu of the fold's own swept width")
	_stand_resquare(u, 0.0, 0.0001)
	assert_almost_eq(u.terrain_clearance(travel), square, 0.05,
			"and it closes onto the fold's width without a jump")


func test_terrain_clearance_still_leaves_a_march_lag_out() -> void:
	# A small heading lag (not an order's re-square) is read as before: the fold alone.
	var u := _unit()
	u._grid_lag = deg_to_rad(20.0)
	u._grid_lag_resquare = false
	var travel: Vector2 = u.facing.orthogonal()
	assert_almost_eq(u.terrain_clearance(travel), _swept(u, 0.0, travel), CLEAR_EPS,
			"the swept width of the grid square to the heading")


func test_a_file_double_on_a_grid_standing_a_quarter_off_a_square_fold() -> void:
	# The grid stands a quarter-turn off its heading with the fold square: its files run along
	# the depth now. It widens across the way the men face, as the same grid folded a quarter
	# does, and keeps its files across the facing once the lag has closed.
	var folded := _unit()
	folded._formation_angle = PI * 0.5
	folded._apply_file_double_step(Order.new_file_double(1))
	var lagged := _unit()
	_stand_resquare(lagged, 0.0, PI * 0.5)
	lagged._resquare_pending = true
	lagged._grid_lag_rate = 0.3
	lagged._apply_file_double_step(Order.new_file_double(1))
	assert_eq(lagged._grid_lag, 0.0, "the transposition squares the whole grid, lag and all")
	assert_eq(lagged._grid_lag_rate, 0.0, "which no longer turns")
	assert_false(lagged._grid_lag_resquare, "no re-square stands")
	assert_false(lagged._resquare_pending, "and none waits")
	_close_lag(lagged)
	assert_false(_quarter_off(lagged.grid_fold()),
			"once any lag has closed the files lie across the facing")
	assert_eq(UnitFormation.frontage(lagged), UnitFormation.frontage(folded),
			"widened as the folded grid is, across the facing")
	assert_ne(UnitFormation.frontage(lagged), UnitFormation.widened_files(MEN, FILES),
			"not doubled along the depth")


func test_a_file_double_on_a_square_grid_over_a_quarter_fold() -> void:
	# The fold a quarter-turn one way, the lag a quarter-turn back: the grid stands square, its
	# files across the facing, but the lag would close it onto the quarter fold. The files widen
	# as they stand, and stay across the facing once the lag has closed.
	var u := _unit()
	_stand_resquare(u, PI * 0.5, -PI * 0.5)
	assert_false(u._holds_quarter_fold(), "setup: the grid as it stands is square")
	u._apply_file_double_step(Order.new_file_double(1))
	_close_lag(u)
	assert_false(_quarter_off(u.grid_fold()),
			"once the lag has closed the grid is still square, its files across the facing")
	assert_eq(UnitFormation.frontage(u), UnitFormation.widened_files(MEN, FILES),
			"the files widened as they stood across the facing")


func test_a_file_double_keeps_a_lag_that_closes_onto_a_square_fold() -> void:
	# A small residue over a square fold: the files lie across the facing now and once it
	# closes, so the step widens them as they stand and the lag goes on closing.
	var u := _unit()
	_stand_resquare(u, 0.0, deg_to_rad(20.0))
	u._apply_file_double_step(Order.new_file_double(1))
	assert_eq(UnitFormation.frontage(u), UnitFormation.widened_files(MEN, FILES),
			"the files widen as they stand")
	assert_almost_eq(u._grid_lag, deg_to_rad(20.0), 0.0001, "the lag still stands")
	assert_true(u._grid_lag_resquare, "as the order's re-square")


func test_a_file_double_over_a_folded_re_square_arms_it_to_run_again() -> void:
	# A quarter fold with a 60 degree re-square lag back toward square: the grid stands 30
	# degrees off, neither square nor a quarter. The files widen across the facing, the lag is
	# folded where the grid stands, and the re-square waits to run again from the new fold;
	# once it has run and turned out, the grid stands square with its files still across.
	var u := _unit()
	_stand_resquare(u, -PI * 0.5, PI / 3.0)
	u._apply_file_double_step(Order.new_file_double(1))
	var files: int = UnitFormation.frontage(u)
	assert_eq(files, UnitFormation.widened_files(MEN, FILES), "the files widen as they stand")
	assert_almost_eq(u.grid_fold(), -PI / 6.0, 0.0001, "the grid stays where it stood")
	assert_true(u._resquare_pending, "the folded re-square waits to run again")
	u._run_waiting_resquare()
	_close_lag(u)
	assert_almost_eq(wrapf(u.grid_fold(), -PI, PI), 0.0, 0.0001,
			"once it has run and closed the grid stands square")
	assert_eq(UnitFormation.frontage(u), files, "with its files still across the facing")


func test_a_transposition_off_a_half_turn_fold_turns_the_grid_as_the_whole_fold_would() -> void:
	# A half-turn fold with a re-square lag of minus 60 degrees stands the grid 120 degrees
	# off. The file double turns it onto the heading exactly as it would a 120 degree fold:
	# the same files on the same slots, with no point reflection of the half-turn.
	var split := _unit()
	_stand_resquare(split, PI, -PI / 3.0)
	var whole := _unit()
	whole._formation_angle = PI * 2.0 / 3.0
	for u in [split, whole]:
		u._apply_file_double_step(Order.new_file_double(1))
	assert_eq(UnitFormation.frontage(split), UnitFormation.frontage(whole), "the same files")
	assert_eq(split._formation_mirror_x, whole._formation_mirror_x, "the same mirroring")
	var a: PackedVector2Array = split.soldier_world_slots(split.soldiers)
	var b: PackedVector2Array = whole.soldier_world_slots(whole.soldiers)
	var worst: float = 0.0
	for i in range(a.size()):
		worst = maxf(worst, a[i].distance_to(b[i]))
	assert_lt(worst, CLEAR_EPS, "every man on the same slot")


func test_a_formed_pivot_never_writes_the_lag_the_clearance_reads() -> void:
	# The clearance reads a re-square lag only on a disciplined march, which turns its heading
	# by a formed pivot: the grid turns with the heading and the lag is left alone, so the
	# clearance cannot steer the lag. A re-face onto the bearing (an undisciplined or hasty
	# march) writes every correction into the lag, so such a block reads the fold alone.
	var u := _unit()
	_stand_resquare(u, 0.0, PI / 3.0)
	assert_true(u.lag_reading_cannot_feed_back(), "setup: a disciplined block, not in haste")
	u._rotate_facing_toward(u.facing.rotated(-0.3), 1.0 / 60.0, 2.0)
	assert_almost_eq(u._grid_lag, PI / 3.0, 0.0001, "a pivot leaves the lag where it was")
	u._reface(u.facing.rotated(0.2))
	assert_ne(u._grid_lag, PI / 3.0, "a re-face onto a bearing moves it")
	var loose := _unit()
	loose.disciplined = false
	_stand_resquare(loose, 0.0, PI / 3.0)
	var travel: Vector2 = loose.facing.orthogonal()
	assert_almost_eq(loose.terrain_clearance(travel), _swept(loose, 0.0, travel), CLEAR_EPS,
			"an undisciplined block reads the fold alone, lag or no lag")


func test_a_hasty_march_reads_the_fold_alone() -> void:
	# A disciplined block given a move in haste re-faces onto its path's bearing through
	# _reface, as an undisciplined one does, so it too reads the fold alone. The same move not
	# in haste pivots as a formation and reads the re-square lag.
	var u := _unit()
	_stand_resquare(u, 0.0, PI / 3.0)
	var travel: Vector2 = u.facing.orthogonal()
	u.set_current_order(Order.new_move(START + travel * 1000.0))
	assert_true(u.lag_reading_cannot_feed_back(), "setup: a move not in haste reads the lag")
	assert_gt(u.terrain_clearance(travel), _swept(u, 0.0, travel) + 10.0,
			"setup: and clears the angles the grid still turns through")
	u.current_order.haste = true
	assert_false(u.lag_reading_cannot_feed_back(), "a move in haste does not")
	assert_almost_eq(u.terrain_clearance(travel), _swept(u, 0.0, travel), CLEAR_EPS,
			"so a hasty march reads the fold alone, lag or no lag")


func test_a_file_double_over_a_folded_march_lag_squares_it_too() -> void:
	# A march's lag (not an order's re-square) of 60 degrees still trailing when a quarter-turn
	# drill folds a quarter under it: the grid stands 30 degrees off, neither square nor a
	# quarter. The lag would have closed onto the quarter fold, along which the widened files no
	# longer lie, so it is folded where the grid stands and a re-square waits to run, as it does
	# for an order's lag; once it has run and closed, the grid stands square.
	var u := _unit()
	u._reface(u.facing.rotated(PI / 3.0))
	assert_almost_eq(u._grid_lag, -PI / 3.0, 0.0001, "setup: a march leaves a 60 degree lag")
	assert_false(u._grid_lag_resquare, "setup: a march's lag, not an order's re-square")
	u._formation_angle = PI * 0.5
	assert_false(u._holds_quarter_fold(), "setup: the grid as it stands is not a quarter off")
	u._apply_file_double_step(Order.new_file_double(1))
	var files: int = UnitFormation.frontage(u)
	assert_eq(files, UnitFormation.widened_files(MEN, FILES), "the files widen as they stand")
	assert_almost_eq(u.grid_fold(), PI / 6.0, 0.0001, "the grid stays where it stood")
	assert_true(u._resquare_pending, "a re-square waits to run from the new fold")
	u._run_waiting_resquare()
	_close_lag(u)
	assert_almost_eq(wrapf(u.grid_fold(), -PI, PI), 0.0, 0.0001,
			"once it has run and closed the grid stands square")
	assert_eq(UnitFormation.frontage(u), files, "with its files still across the facing")
