extends GutTest
## The standalone reform primitive (Unit.reform_ranks) and its wiring into the rear-move
## composite: after an about-face, a depleted unit's short/partial rank -- previously the
## safe REAR rank -- sits at the NEW front purely by the facing flip. The reform re-squares
## the slot grid to the new heading so a full rank fronts it again (a countermarch: the
## bodies march themselves onto the re-squared slots; no index-aligned array is relabelled).
## Isolated-unit tests: _think() plus SoldierBodies.step() driven tick by tick, no Battle
## scene -- see test_reform_battle.gd for the full-scene proof.

const TICK: float = 1.0 / 60.0


## A seeded unit whose grid has a PARTIAL last rank: 60 men at 8 files = 7 full ranks + 4.
func _make_partial_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = 8
	u.seed_sim_soldiers()
	return u


## A seeded unit whose grid is FULL: 24 men at 8 files = exactly 3 ranks.
func _make_full_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 24
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = 8
	u.seed_sim_soldiers()
	return u


## How many bodies stand in the unit's FRONT row: within half a rank spacing of the
## front-most body, measured by projection onto the unit's facing.
func _front_row_count(u: Unit) -> int:
	var best: float = -INF
	var proj: PackedFloat32Array = PackedFloat32Array()
	for p in u._sim_soldier_pos:
		var d: float = (p - u.position).dot(u.facing)
		proj.push_back(d)
		best = maxf(best, d)
	var count: int = 0
	for d in proj:
		if best - d < Unit.FORMATION_SPACING * 0.5:
			count += 1
	return count


## True when body `index` stands in the unit's REAR row (within half a spacing of the
## rear-most body's projection onto facing).
func _in_rear_row(u: Unit, index: int) -> bool:
	var worst: float = INF
	for p in u._sim_soldier_pos:
		worst = minf(worst, (p - u.position).dot(u.facing))
	var d: float = (u._sim_soldier_pos[index] - u.position).dot(u.facing)
	return d - worst < Unit.FORMATION_SPACING * 0.5


## One sim tick of the isolated unit: the full unit layer (thinking, movement, and the
## stale-momentum reset an idle unit relies on -- _think alone would leave a phantom
## _approach_velocity feeding forward into the bodies after a march arrives) plus the
## soldier-body arrival, the same two layers Battle drives each physics tick.
func _tick(u: Unit) -> void:
	u._physics_process(TICK)
	SoldierBodies.step(u, TICK)


# --- the primitive ----------------------------------------------------------

func test_reform_noops_on_a_grid_already_square_to_the_heading() -> void:
	var u := _make_partial_unit()
	assert_false(u.reform_ranks(), "nothing to reform: the front rank is already full")
	assert_eq(u._formation_angle, 0.0)


func test_reform_resquares_a_flipped_partial_grid() -> void:
	var u := _make_partial_unit()
	# Exactly what a settled about-face leaves: facing reversed, the turn absorbed into
	# _formation_angle so the slots still reproduce every body's held position -- which
	# puts the partial rank at the NEW front.
	u.facing = Vector2.UP
	u._formation_angle = PI
	assert_true(u._reform_bodies_settled(), "the settled flip reproduces the held positions")
	assert_true(u.reform_ranks(), "a flipped partial grid has a short rank leading: reform")
	assert_eq(u._formation_angle, 0.0, "the grid is re-squared to the current heading")
	assert_false(u._reform_bodies_settled(),
		"the re-squared slots moved out from under the bodies: the countermarch has to run")


func test_reform_noops_on_a_flipped_full_grid() -> void:
	var u := _make_full_unit()
	u.facing = Vector2.UP   # a settled about-face: facing reversed, turn absorbed
	u._formation_angle = PI
	assert_false(u.reform_ranks(),
		"a full grid is centre-symmetric: the flip already fronts a full rank")
	assert_eq(u._formation_angle, PI, "the folded flip is left alone")


func test_reform_noops_on_a_single_rank() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = 6
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.frontage_override = 8   # clamped to max_soldiers: 6 men in one single rank
	u.seed_sim_soldiers()
	u.facing = Vector2.UP   # a settled about-face: facing reversed, turn absorbed
	u._formation_angle = PI
	assert_false(u.reform_ranks(), "one rank IS the fullest rank; a flip only mirrors it")


func test_bodies_settle_check_is_true_right_after_seeding() -> void:
	var u := _make_partial_unit()
	assert_true(u._reform_bodies_settled(), "seeded bodies stand exactly on their slots")


# --- the rear-move composite ------------------------------------------------

## Arm a rear-move composite as Battle._apply_order_cmd does: a MOVE order carrying the
## reform choice, made current, with the about-face TURN phase armed on it.
func _arm_rear_move(u: Unit, dest: Vector2, reform: bool) -> Order:
	var o := Order.new_move(dest)
	o.reform = reform
	u.set_current_order(o)
	u.has_move_target = false
	assert_true(u.begin_about_face(o), "the about-face armed")
	return o


func test_rear_move_with_reform_holds_the_march_until_the_ranks_re_form() -> void:
	var u := _make_partial_unit()
	var dest := Vector2(0, -200)   # straight behind a DOWN-facing unit
	_arm_rear_move(u, dest, true)   # the drilled variant: reform before stepping off

	# Run the turn out; the march must not start, and the reform hold must arm instead.
	var turn_budget: int = int(ceil(PI / Unit.CONVERSIO_TURN_RATE / TICK)) + 10
	for _i in range(turn_budget):
		_tick(u)
		if not u.is_order_turning():
			break
	assert_false(u.is_order_turning(), "the about-face completed within its budget")
	assert_false(u.has_move_target, "no march yet: the reform phase holds it")
	assert_gt(u._reform_timer, 0.0, "the reform hold armed on conversio completion")
	assert_true(u._reform_until_settled, "the hold ends on settle, not a fixed countdown")

	# Run the reform out: the march commits once every body stands on its re-squared slot,
	# within the timeout the unit derived from its own depth and pace.
	var reform_budget: int = int(ceil(u._reform_timeout() / TICK)) + 10
	var held_ticks: int = 0
	for _i in range(reform_budget):
		if u.has_move_target:
			break
		held_ticks += 1
		_tick(u)
	assert_true(u.has_move_target, "the parked march commits after the reform")
	assert_eq(u.move_target, dest, "to the parked rear destination")
	assert_gt(held_ticks, 5, "an actual hold happened (the countermarch takes real time)")
	assert_true(u._reform_bodies_settled(), "the march waited for the ranks, not a timer")
	assert_eq(_front_row_count(u), 8,
		"a FULL rank fronts the new heading at step-off (files = 8), not the 4-man partial")
	for i in range(56, 60):
		assert_true(_in_rear_row(u, i),
			"partial-rank body %d ends at the new REAR, no longer leading" % i)


func test_hasty_rear_move_marches_at_once_and_reforms_on_arrival() -> void:
	var u := _make_partial_unit()
	var dest := Vector2(0, -60)   # short rear leg so the march fits a tight tick budget
	_arm_rear_move(u, dest, false)   # the hasty variant: reform is deferred, not skipped

	var turn_budget: int = int(ceil(PI / Unit.CONVERSIO_TURN_RATE / TICK)) + 10
	for _i in range(turn_budget):
		_tick(u)
		if u.has_move_target:
			break
	assert_true(u.has_move_target, "the march starts straight off the about-face")
	assert_eq(u._reform_timer, 0.0, "no reform hold for a hasty order")
	assert_true(u._reform_on_arrival, "the reform is parked for arrival instead")
	assert_eq(_front_row_count(u), 4,
		"in haste the flipped grid marches as-is: the 4-man partial rank leads the transit")

	# March to arrival (~55 px at walk pace), then let the deferred reform settle.
	var march_budget: int = int(ceil(60.0 / maxf(u.walk_speed * 0.5, 1.0) / TICK)) + 60
	for _i in range(march_budget):
		_tick(u)
		if not u.has_move_target:
			break
	assert_false(u.has_move_target, "the march arrived within its budget")
	assert_false(u._reform_on_arrival, "the deferred reform fired on arrival")
	assert_eq(u._formation_angle, 0.0, "and re-squared the grid to the heading")
	var settle_budget: int = int(ceil(u._reform_timeout() / TICK)) + 10
	for _i in range(settle_budget):
		_tick(u)
		if u._reform_bodies_settled():
			break
	assert_true(u._reform_bodies_settled(), "the bodies re-formed at the destination")
	assert_eq(_front_row_count(u), 8, "a FULL rank fronts the heading at the destination")
	for i in range(56, 60):
		assert_true(_in_rear_row(u, i), "partial-rank body %d is back at the rear" % i)


func test_interrupted_about_face_drops_the_parked_reform_with_the_march() -> void:
	var u := _make_partial_unit()
	var o := _arm_rear_move(u, Vector2(0, -200), true)
	# A legacy march starts under the turn (an append-style pre-empt): the turn settles and
	# the order retires, taking the parked rear march AND its reform choice with it.
	u.has_move_target = true
	u.move_target = Vector2(300, 0)
	u._think(TICK)
	assert_eq(o.turn_target, Vector2.ZERO, "the interrupting order cancels the about-face")
	assert_null(u.current_order, "the turning order retired, dropping its parked march")
	assert_eq(u._reform_timer, 0.0, "and no reform hold survives it")


# --- regression: engage-turn / face-snap folds must not disturb an active mirror ------------
# _settle_engage_turn() and _face_dir()'s snap-absorb branch each fold a rotation into
# _formation_angle specifically to hold `ang` (soldier_world_slots' rotation) INVARIANT across
# the facing change so bodies don't surge. _formation_mirror_x has no bearing on whether `ang`
# is invariant, so clearing it inside either fold -- forcing it to a new value in the SAME tick
# `ang` is held constant -- flips every off-centre soldier's sign for that tick even though the
# rotation itself didn't change, reproducing the exact point-reflection/flank-swap bug this
# file's countermarch fix exists to eliminate, just triggered by a combat re-face instead of a
# reform (reachable whenever a unit engages combat, or gets a fresh chase target, while still
# marching off a countermarched reform -- the mirror flag stays true through that whole march).

## After reform_ranks() arms the mirror (the exact settled-about-face state
## test_reform_resquares_a_flipped_partial_grid stages), completing an unrelated engage-turn
## must not change ANY soldier's computed world slot -- that's the whole point of the fold. If
## _formation_mirror_x is wrongly cleared inside _settle_engage_turn(), the mirrored bodies'
## slots flip sign in this same tick even though nothing about the rotation changed.
func test_engage_turn_settle_does_not_disturb_an_active_countermarch_mirror() -> void:
	var u := _make_partial_unit()
	u.facing = Vector2.UP
	u._formation_angle = PI
	assert_true(u.reform_ranks(), "arms the countermarch mirror")
	assert_true(u._formation_mirror_x, "precondition: the mirror is active")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)

	# Arm and complete a small engage-turn in one step (facing already at the target, so
	# _settle_engage_turn's own fold turned angle is zero -- ang is trivially unchanged, which
	# is exactly the case that must leave every slot untouched).
	u._engage_turn_start_facing = u.facing
	u._engage_turn_target = u.facing
	u._settle_engage_turn()

	assert_true(u._formation_mirror_x,
		"the mirror survives an engage-turn settle: it doesn't affect ang invariance")
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(before.size()):
		assert_true(before[i].is_equal_approx(after[i]),
			"soldier %d's slot must not move: _settle_engage_turn holds ang constant" % i)


## Same regression, via _face_dir's large-snap fold instead of _settle_engage_turn.
func test_face_dir_snap_absorb_does_not_disturb_an_active_countermarch_mirror() -> void:
	var u := _make_partial_unit()
	u.facing = Vector2.UP
	u._formation_angle = PI
	assert_true(u.reform_ranks(), "arms the countermarch mirror")
	assert_true(u._formation_mirror_x, "precondition: the mirror is active")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)

	# A large snap (well past FACING_SNAP_ABSORB_THRESHOLD) folds into _formation_angle instead
	# of just rotating facing directly -- the branch under test.
	var large_snap: Vector2 = u.facing.rotated(PI * 0.9)
	u._face_dir(large_snap)

	assert_true(u._formation_mirror_x,
		"the mirror survives a face_dir snap-absorb: it doesn't affect ang invariance")
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(before.size()):
		assert_true(before[i].is_equal_approx(after[i]),
			"soldier %d's slot must not move: the snap-absorb fold holds ang constant" % i)
