extends GutTest
## A combat re-face on riders inside a foot block folds into _formation_angle (_face_dir's
## absorb) and is also counted in _absorbed_fold. On every tick the block is out of enemy
## contact and not turning in place, _advance_grid_lag squares that part alone, with no order,
## a bounded step at a time straight off the fold (_bleed_absorbed_fold). The rest of the fold
## (an engage re-face, a drill) stays, so a block whose fold sits near a quarter-turn is not
## reflected by a half-turn to square a few degrees of it (#1859). The absorb itself is covered
## in test_melee_reface_inside_block.gd.

const DT := 1.0 / 60.0
# Inside a 60-man block's footprint: 39.8 degrees off the block's DOWN heading.
const INSIDE_OFFSET := Vector2(-20.0, 24.0)
const SLOT_KEEP_TOL := 0.01
const ANGLE_TOL := 1e-5
# An engage fold just past a quarter-turn, as sweep_routers uid 4 carries one (#1847).
const NEAR_QUARTER_FOLD := -1.736   # -99.5 degrees


func _make_block() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.uid = 1
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	u._in_enemy_contact = true
	return u


func _make_rider(pos: Vector2) -> Unit:
	var e: Unit = Unit.new()
	e.max_soldiers = 20
	add_child_autofree(e)
	e.uid = 2
	e.team = 1
	e.position = pos
	e.state = Unit.State.FIGHTING
	e.is_cavalry = true
	return e


func _max_slot_shift(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(a.size()):
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


## The farthest any slot may move in one tick of a bounded grid turn, with 1% slack.
func _per_tick_bound(u: Unit) -> float:
	var radius: float = u._formation_local_half_extents().length()
	return 1.01 * u.bounded_turn_rate(radius) * DT * u.soldier_block_extent()


## Re-face onto a rider inside the block, so the turn is absorbed. Returns the absorbed turn.
func _absorb_reface(u: Unit) -> float:
	var e := _make_rider(u.position + INSIDE_OFFSET)
	var fold_before: float = u._formation_angle
	u._face_for_action(e.position, DT, e)
	var absorbed: float = angle_difference(fold_before, u._formation_angle)
	assert_gt(absf(absorbed), 0.5, "sanity: the re-face folded tens of degrees")
	return absorbed


## Step the grid lag clear of contact for `ticks`, returning the largest one-tick slot move.
func _run_clear(u: Unit, ticks: int) -> float:
	u._in_enemy_contact = false
	var worst := 0.0
	for _i in range(ticks):
		var prev: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		u._advance_grid_lag(DT)
		worst = maxf(worst, _max_slot_shift(prev, u.soldier_world_slots(u.soldiers)))
	return worst


func test_the_absorb_is_counted_apart_from_the_fold() -> void:
	var u := _make_block()
	u._formation_angle = NEAR_QUARTER_FOLD
	var absorbed: float = _absorb_reface(u)
	assert_almost_eq(u._absorbed_fold, absorbed, ANGLE_TOL, "the absorbed part is counted on its own")


func test_an_absorbed_fold_squares_once_clear_without_an_order() -> void:
	var u := _make_block()
	_absorb_reface(u)
	assert_false(u._resquare_pending, "sanity: no order's re-square is armed")
	var worst: float = _run_clear(u, 600)
	assert_almost_eq(u.grid_fold(), 0.0, ANGLE_TOL, "ten seconds clear, the grid is square")
	assert_eq(u._absorbed_fold, 0.0, "nothing is left to square")
	assert_lt(worst, _per_tick_bound(u), "no tick moves a slot further than the bounded turn allows")


func test_each_tick_turns_the_fold_by_a_bounded_step() -> void:
	# The fold itself turns smoothly, so every reader of it (the anchor's near-front ranks among
	# them) sees no jump, as it would if tens of degrees went to the lag in one tick.
	var u := _make_block()
	_absorb_reface(u)
	u._in_enemy_contact = false
	var radius: float = u._formation_local_half_extents().length()
	var bound: float = 1.0001 * u.bounded_turn_rate(radius) * DT
	var worst := 0.0
	for _i in range(600):
		var before: float = u._formation_angle
		u._advance_grid_lag(DT)
		worst = maxf(worst, absf(angle_difference(before, u._formation_angle)))
		assert_eq(u._grid_lag, 0.0, "nothing goes through the lag")
	assert_gt(worst, 0.0, "sanity: the fold turned")
	assert_lt(worst, bound, "no tick turns the fold past the bounded rate")


func test_only_the_absorbed_part_squares_and_a_near_quarter_fold_is_not_reflected() -> void:
	# The earlier attempt squared the whole fold: -99.5 plus a few absorbed degrees is past a
	# quarter, so the order's re-square reflected it by a half-turn and left a residue near a
	# quarter-turn for the grid to turn out. Squaring only the absorbed part leaves the engage
	# fold where it stands.
	var u := _make_block()
	u._formation_angle = NEAR_QUARTER_FOLD
	_absorb_reface(u)
	var mirror: bool = u._formation_mirror_x
	var worst: float = _run_clear(u, 600)
	assert_almost_eq(u.grid_fold(), NEAR_QUARTER_FOLD, ANGLE_TOL, "the engage fold is left as it was")
	assert_eq(u._formation_mirror_x, mirror, "no half-turn reflection ran")
	assert_lt(worst, _per_tick_bound(u), "no tick moves a slot further than the bounded turn allows")


func test_back_in_contact_the_squaring_stops_and_the_rest_waits() -> void:
	var u := _make_block()
	var absorbed: float = _absorb_reface(u)
	_run_clear(u, 20)
	var left: float = u._absorbed_fold
	assert_lt(absf(left), absf(absorbed), "sanity: some of it has been squared")
	assert_gt(absf(left), 0.0, "sanity: and some is left")
	u._in_enemy_contact = true
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._advance_grid_lag(DT)
	assert_eq(u._absorbed_fold, left, "in contact the rest waits")
	assert_eq(u._grid_lag_rate, 0.0, "and the grid stops turning")
	assert_false(u._resquare_pending, "no order's whole-fold re-square is armed")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_KEEP_TOL,
		"no slot moves on the contact tick")
	_run_clear(u, 600)
	assert_almost_eq(u.grid_fold(), 0.0, ANGLE_TOL, "clear again, it squares the rest")


func test_no_squaring_while_turning_in_place() -> void:
	var u := _make_block()
	var absorbed: float = _absorb_reface(u)
	var fold: float = u._formation_angle
	u._in_enemy_contact = false
	u._engage_turn_target = Vector2.RIGHT
	u._advance_grid_lag(DT)
	assert_eq(u._absorbed_fold, absorbed, "an engage turn in place holds the squaring back")
	assert_eq(u._formation_angle, fold, "and the fold stays")


func test_a_march_lag_turns_out_first() -> void:
	var u := _make_block()
	var absorbed: float = _absorb_reface(u)
	u._in_enemy_contact = false
	u._grid_lag = 0.05
	u._advance_grid_lag(DT)
	assert_eq(u._absorbed_fold, absorbed, "the absorbed part waits while a lag turns")
	_run_clear(u, 600)
	assert_almost_eq(u.grid_fold(), 0.0, ANGLE_TOL, "then both are squared")


func test_a_pivot_at_the_full_rate_the_same_way_leaves_no_room() -> void:
	# A heading pivot this tick turns the grid too; the squaring step is held so the grid's own
	# turn stays within bounded_turn_rate.
	var u := _make_block()
	var absorbed: float = _absorb_reface(u)
	u._in_enemy_contact = false
	var radius: float = u._formation_local_half_extents().length()
	u._facing_turn_step = -signf(absorbed) * u.bounded_turn_rate(radius) * DT
	u._is_facing_turning = true
	u._advance_grid_lag(DT)
	assert_eq(u._absorbed_fold, absorbed, "a pivot at the full rate leaves no room this tick")


func test_an_order_squares_the_whole_fold_and_drops_the_absorbed_count() -> void:
	var u := _make_block()
	_absorb_reface(u)
	u.start_order_response()
	assert_true(u._resquare_pending, "sanity: in the fight the order's re-square waits")
	u._in_enemy_contact = false
	u._contact_clear_time = 0.0
	var absorbed: float = u._absorbed_fold
	u._advance_grid_lag(DT)
	assert_eq(u._absorbed_fold, absorbed, "a waiting order's re-square holds the squaring back")
	u._contact_clear_time = Unit.RESQUARE_CONTACT_CLEAR_TIME
	var worst: float = _run_clear(u, 600)
	assert_eq(u._absorbed_fold, 0.0, "the order's re-square took the absorbed part with the rest")
	assert_almost_eq(u.grid_fold(), 0.0, ANGLE_TOL, "and squared the grid")
	assert_lt(worst, _per_tick_bound(u), "a bounded turn at a time")


func test_reform_ranks_drops_the_absorbed_count_even_when_the_fold_reads_square() -> void:
	# An engage fold the other way can cancel the absorbed part, so the fold reads square and
	# reform_ranks returns early. Squaring the count afterwards would turn the grid off square.
	var u := _make_block()
	_absorb_reface(u)
	u._formation_angle = 0.0
	assert_ne(u._absorbed_fold, 0.0, "sanity: the count is still set")
	u.reform_ranks(true)
	assert_eq(u._absorbed_fold, 0.0, "reform_ranks drops it")
	_run_clear(u, 120)
	assert_almost_eq(u.grid_fold(), 0.0, ANGLE_TOL, "and the grid stays square")


func test_a_rout_drops_the_absorbed_count() -> void:
	var u := _make_block()
	_absorb_reface(u)
	u._rout()
	assert_eq(u._absorbed_fold, 0.0, "the rally squares the whole fold, so nothing waits")
