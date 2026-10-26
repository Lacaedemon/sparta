extends GutTest
## Squaring a fold absorbed onto riders inside a foot block (_bleed_absorbed_fold) gives the
## absorbed turns back only while each step brings the grid nearer its nearest square line (0 or
## a half-turn, square_reach). An absorb that ran against an engage fold made before it undid
## part of that fold: giving it back would turn the grid further off its heading, so the grid
## stays, or stops on the square line, and the rest of the count is dropped. The rest of the
## squaring is covered in test_absorbed_fold_squares_when_clear.gd.

const DT := 1.0 / 60.0
# 39.8 degrees either side of a DOWN heading, turned with the block's heading, and near enough
# the anchor to lie inside a 60-man block's footprint however its grid is folded: a re-face onto
# the first folds -39.8 degrees in, onto the second +39.8.
const INSIDE_LEFT := Vector2(-10.0, 12.0)
const INSIDE_RIGHT := Vector2(10.0, 12.0)
const ABSORB_DEG := 39.8
const SLOT_KEEP_TOL := 0.01
const ANGLE_TOL := 1e-5


func _make_block() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.uid = 1
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	u._in_enemy_contact = true
	return u


## Settle an engage turn-in-place that leaves a fold of `fold_deg` degrees, as a block that
## turned in place onto a foot enemy before any riders came inside it.
func _engage_fold(u: Unit, fold_deg: float) -> void:
	u._engage_turn_start_facing = u.facing
	u.facing = u.facing.rotated(-deg_to_rad(fold_deg))
	u._engage_turn_target = u.facing
	u._settle_engage_turn()
	assert_almost_eq(rad_to_deg(u._formation_angle), fold_deg, 1e-3, "sanity: the engage fold")


## Re-face onto a rider at `offset` (as for a DOWN heading, turned with the block's heading)
## inside the block, so the turn is absorbed on top.
func _absorb_reface(u: Unit, offset: Vector2) -> void:
	var e: Unit = Unit.new()
	e.max_soldiers = 20
	add_child_autofree(e)
	e.uid = 2
	e.team = 1
	e.position = u.position + offset.rotated(angle_difference(Vector2.DOWN.angle(), u.facing.angle()))
	e.state = Unit.State.FIGHTING
	e.is_cavalry = true
	u._face_for_action(e.position, DT, e)
	assert_ne(u._absorbed_fold, 0.0, "sanity: the re-face was absorbed")


## Step the grid clear of contact for `ticks`, returning the largest one-tick slot move.
func _run_clear(u: Unit, ticks: int) -> float:
	u._in_enemy_contact = false
	var worst := 0.0
	for _i in range(ticks):
		var prev: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		u._advance_grid_lag(DT)
		var now: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		for k in range(prev.size()):
			worst = maxf(worst, prev[k].distance_to(now[k]))
	return worst


## Off its nearest square line (degrees, 0 to 90).
func _off_square_deg(fold: float) -> float:
	var a: float = absf(rad_to_deg(wrapf(fold, -PI, PI)))
	return minf(a, 180.0 - a)


func test_an_absorb_that_undid_part_of_an_engage_fold_is_not_given_back() -> void:
	# Engage fold +60, then riders inside on the other side absorb -39.8: the fold is +20.2.
	# Giving the absorb back would turn the grid to +60 again, three times as far off.
	var u := _make_block()
	_engage_fold(u, 60.0)
	_absorb_reface(u, INSIDE_LEFT)
	var before: float = u.grid_fold()
	assert_almost_eq(rad_to_deg(before), 60.0 - ABSORB_DEG, 0.1, "sanity: the absorb undid part")
	var worst: float = _run_clear(u, 600)
	assert_lte(absf(u.grid_fold()), absf(before) + ANGLE_TOL,
		"the grid ends no further from its heading than before the bleed")
	assert_almost_eq(u.grid_fold(), before, ANGLE_TOL, "it stays where the absorb left it")
	assert_eq(u._absorbed_fold, 0.0, "the count that could only turn it off square is dropped")
	assert_lt(worst, SLOT_KEEP_TOL, "no slot moves")


func test_an_absorb_past_square_is_given_back_only_to_square() -> void:
	# Engage fold +20, then an absorb of -39.8 carries the fold past square to -19.8. Giving it
	# all back would end at +20; the grid stops square instead.
	var u := _make_block()
	_engage_fold(u, 20.0)
	_absorb_reface(u, INSIDE_LEFT)
	var before: float = u.grid_fold()
	assert_lt(before, 0.0, "sanity: the absorb carried the fold past square")
	var radius: float = u._formation_local_half_extents().length()
	var bound: float = 1.01 * u.bounded_turn_rate(radius) * DT * u.soldier_block_extent()
	var worst: float = _run_clear(u, 600)
	assert_almost_eq(u.grid_fold(), 0.0, ANGLE_TOL, "the grid ends square")
	assert_eq(u._absorbed_fold, 0.0, "and the rest of the count is dropped")
	assert_lt(worst, bound, "no tick moves a slot further than the bounded turn allows")
	assert_eq(u._grid_lag_rate, 0.0, "the turn eased to a stop on the square line")


func test_past_a_quarter_the_absorb_is_given_back_toward_the_half_turn() -> void:
	# Engage fold -150, then an absorb of +39.8 takes it to -110.2: giving it back turns the grid
	# toward its nearest square, the half-turn, so all of it is given back.
	var u := _make_block()
	_engage_fold(u, -150.0)
	_absorb_reface(u, INSIDE_RIGHT)
	var mirror: bool = u._formation_mirror_x
	_run_clear(u, 900)
	assert_almost_eq(rad_to_deg(u.grid_fold()), -150.0, 1e-3, "the engage fold is back")
	assert_eq(u._absorbed_fold, 0.0, "all of it was given back")
	assert_eq(u._formation_mirror_x, mirror, "no half-turn reflection ran")


func test_each_tick_brings_the_grid_no_further_from_square() -> void:
	for fold_deg in [60.0, 20.0, -20.0, -60.0, 110.0, -110.0, 150.0, -150.0, 70.0, -70.0]:
		for offset in [INSIDE_LEFT, INSIDE_RIGHT]:
			var u := _make_block()
			_engage_fold(u, fold_deg)
			_absorb_reface(u, offset)
			u._in_enemy_contact = false
			for _i in range(900):
				var before: float = _off_square_deg(u.grid_fold())
				u._advance_grid_lag(DT)
				assert_lte(_off_square_deg(u.grid_fold()), before + 1e-4,
					"engage %.0f, absorb %s: a step turned the grid off square" % [fold_deg, offset])



func test_square_reach_measures_to_the_nearest_square_line() -> void:
	var r := deg_to_rad(1.0)
	assert_almost_eq(Unit.square_reach(40.0 * r, -1.0), 40.0 * r, ANGLE_TOL, "toward 0")
	assert_eq(Unit.square_reach(40.0 * r, 1.0), 0.0, "away from 0")
	assert_almost_eq(Unit.square_reach(-99.5 * r, -1.0), 80.5 * r, ANGLE_TOL, "toward -180")
	assert_eq(Unit.square_reach(-99.5 * r, 1.0), 0.0, "past a quarter, back toward 0 is away")
	assert_almost_eq(Unit.square_reach(PI * 0.5, 1.0), PI * 0.5, ANGLE_TOL,
		"exactly a quarter, toward the half-turn")
	assert_almost_eq(Unit.square_reach(PI * 0.5, -1.0), PI * 0.5, ANGLE_TOL,
		"exactly a quarter, toward 0")
	assert_eq(Unit.square_reach(0.0, 1.0), 0.0, "square already")
	assert_eq(Unit.square_reach(PI, -1.0), 0.0, "the half-turn is square too")
	assert_eq(Unit.square_reach(-PI, 1.0), 0.0, "either sign of it")
