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


## True when body `index` stands in the unit's FRONT row (within half a spacing of the
## front-most body's projection onto facing) -- the mirror of _in_rear_row below.
func _in_front_row(u: Unit, index: int) -> bool:
	var best: float = -INF
	for p in u._sim_soldier_pos:
		best = maxf(best, (p - u.position).dot(u.facing))
	var d: float = (u._sim_soldier_pos[index] - u.position).dot(u.facing)
	return best - d < Unit.FORMATION_SPACING * 0.5


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


## Regression: the single-rank early return above is scoped to the ABOUT-FACE (+-PI) fold
## specifically -- it used to fire for ANY fold angle, so a single-rank grid folded by a
## quarter-turn (e.g. a maneuver's own in-place pivot) never re-squared: reform_ranks()
## returned false and left _formation_angle standing, instead of dropping the fold like
## any other shape at a non-PI angle.
func test_reform_resquares_a_single_rank_folded_by_a_quarter_turn() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = 6
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.frontage_override = 8   # clamped to max_soldiers: 6 men in one single rank
	u.seed_sim_soldiers()
	u.facing = Vector2.RIGHT   # a settled 90-degree turn: facing rotated, turn absorbed
	u._formation_angle = -PI * 0.5
	assert_true(u.reform_ranks(),
		"a quarter-turn genuinely rotates the grid axis, even for a single rank -- unlike " +
		"the about-face's point-reflection no-op, this fold is not a mirror of the same row")
	assert_eq(u._formation_angle, 0.0, "the grid is re-squared to the current heading")


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
	assert_gt(u.active_leaf().reform_timer, 0.0, "the reform hold armed on conversio completion")
	assert_true(u.active_leaf().reform_until_settled, "the hold ends on settle, not a fixed countdown")

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
	assert_false(u._reform_holding(), "no reform hold for a hasty order")
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
	var turn_leaf := o.active_leaf()   # captured before the interrupt settles it
	# A legacy march starts under the turn (an append-style pre-empt): the turn settles and
	# the order retires, taking the parked rear march AND its reform choice with it.
	u.has_move_target = true
	u.move_target = Vector2(300, 0)
	u._think(TICK)
	assert_eq(turn_leaf.turn_target, Vector2.ZERO, "the interrupting order cancels the about-face")
	assert_null(u.current_order, "the turning order retired, dropping its parked march")
	assert_false(u._reform_holding(), "and no reform hold survives it")


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


# --- hold-ground reform (a rally, not an ordered drill) ---------------------
# reform_ranks(true) owes the same re-squared FOOTPRINT as the drill without marching the
# block through itself to reach it: re-squaring is a depth reflection, and reversing each
# file's own rank order cancels it. A rally takes this variant -- nothing ordered a
# countermarch there, the fold is only bookkeeping the flight left behind.


## Men in a file the partial rear rank reached are already standing where the re-squared
## grid wants them, so their slots must not move at all.
func test_hold_ground_reform_leaves_the_full_depth_files_standing_still() -> void:
	var u := _make_partial_unit()   # 60 at 8 files: files 2-5 are 8 deep, 0/1/6/7 are 7
	assert_true(u._effective_file_major_reform(),
		"precondition: units default to the file-major layout this reform reverses")
	u.facing = Vector2.UP
	u._formation_angle = PI
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_true(u.reform_ranks(true), "a flipped partial grid reforms")

	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var pitch: float = u.rank_pitch_wu()
	var still: int = 0
	var stepped: int = 0
	for i in range(before.size()):
		var moved: float = before[i].distance_to(after[i])
		if moved < 0.001:
			still += 1
		else:
			stepped += 1
			assert_almost_eq(moved, pitch, 0.001,
				"soldier %d closes up by exactly one rank pitch, not the block's depth" % i)
	assert_eq(still, 32, "the four 8-deep files (32 men) hold the ground they are on")
	assert_eq(stepped, 28, "only the four short files close up behind them")


## The reversal must not cost the reform its purpose: a FULL rank still ends up leading,
## which is the shape change the short files step forward to produce.
func test_hold_ground_reform_still_brings_a_full_rank_to_the_front() -> void:
	var u := _make_partial_unit()
	u.facing = Vector2.UP
	u._formation_angle = PI
	assert_eq(_front_slot_count(u), 4,
		"precondition: the flip leaves the 4-man partial rank leading")
	assert_true(u.reform_ranks(true), "a flipped partial grid reforms")
	assert_eq(_front_slot_count(u), 8, "a full 8-man rank fronts the re-squared grid")


## The two variants must reach the SAME footprint -- only which man holds which slot
## differs. Anything else would make this a shape change rather than a relabel.
func test_hold_ground_reform_reaches_the_same_footprint_as_the_drill() -> void:
	var drill := _make_partial_unit()
	drill.facing = Vector2.UP
	drill._formation_angle = PI
	assert_true(drill.reform_ranks(), "the ordered drill reforms")
	var held := _make_partial_unit()
	held.facing = Vector2.UP
	held._formation_angle = PI
	assert_true(held.reform_ranks(true), "so does the hold-ground variant")

	assert_eq(_sorted_slot_keys(drill), _sorted_slot_keys(held),
		"identical set of occupied slots; the men holding them are what differs")


## Default false: an ORDERED rear-move or countermarch still performs the drill, marching
## the men through the block. Scoping the reversal to the rally is the whole point -- an
## exelismos the player asked for is meant to move the files.
func test_plain_reform_still_marches_the_block_through_itself() -> void:
	var u := _make_partial_unit()
	u.facing = Vector2.UP
	u._formation_angle = PI
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_true(u.reform_ranks(), "a flipped partial grid reforms")

	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var farthest: float = 0.0
	for i in range(before.size()):
		farthest = maxf(farthest, before[i].distance_to(after[i]))
	assert_gt(farthest, u.rank_pitch_wu() * 5.0,
		"the drill still carries men most of the block's depth, unlike hold-ground")


## The rally takes the hold-ground variant: a unit that steadied its nerve reforms where it
## stands rather than countermarching, which is what stopped the whole block scrambling
## through itself the moment its rout timer expired.
func test_rally_reforms_without_marching_the_block_through_itself() -> void:
	var u := _make_partial_unit()
	u.facing = Vector2.UP
	u._rout()
	u._formation_angle = PI   # the flee turn re-folded the grid via _face_dir's snap-absorb
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)

	u._rally()

	assert_eq(u.state, Unit.State.IDLE, "the unit rallied")
	assert_eq(u._formation_angle, 0.0, "and re-squared the grid to its heading")
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var farthest: float = 0.0
	for i in range(before.size()):
		farthest = maxf(farthest, before[i].distance_to(after[i]))
	assert_almost_eq(farthest, u.rank_pitch_wu(), 0.001,
		"no man is sent further than one rank pitch to re-square")


## A squared block takes the square slot branch, which never reads the per-soldier file
## arrays -- so the hold-ground reversal must not touch them either. Calling
## _ensure_file_assignment here would commit a file count derived from square_files(), and
## nothing invalidates that when the unit later leaves square, so the stale count would
## force a lateral re-deal on the next ordinary layout.
func test_hold_ground_reform_leaves_a_squared_units_file_assignment_untouched() -> void:
	# 50 at 10 files: square_files(50) is 8, so the square count can't coincide with the
	# line's and hide a stale commit behind a matching number.
	var u: Unit = Unit.new()
	u.max_soldiers = 50
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = 10
	u.seed_sim_soldiers()
	var line_files: int = u._file_assignment_files
	assert_eq(line_files, 10, "precondition: the line layout dealt a 10-file assignment")

	u.set_formation(Unit.FORMATION_SQUARE)
	assert_true(u.in_square(), "precondition: the unit is squared")
	assert_eq(u.formation_files(u.soldiers), 8,
		"precondition: square derives a different file count than the line did")
	assert_eq(u._file_assignment_files, line_files,
		"precondition: squaring alone leaves the line's assignment in place")
	assert_true(u._effective_file_major_reform(),
		"precondition: the file-major mode the guard sits beside is otherwise on")
	u.facing = Vector2.UP
	u._formation_angle = PI

	assert_true(u.reform_ranks(true), "a squared block still re-squares its folded grid")

	assert_eq(u._formation_angle, 0.0, "the fold is dropped as usual")
	assert_eq(u._file_assignment_files, line_files,
		"no square-derived file count is committed for a later layout to inherit")


## How many SLOTS (not bodies) sit in the unit's front row: within half a rank pitch of the
## front-most slot, measured by projection onto facing. The slot-side counterpart of
## _front_row_count, so the grid can be checked before the bodies have marched onto it.
func _front_slot_count(u: Unit) -> int:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var best: float = -INF
	for p in slots:
		best = maxf(best, (p - u.position).dot(u.facing))
	var count: int = 0
	for p in slots:
		if best - (p - u.position).dot(u.facing) < u.rank_pitch_wu() * 0.5:
			count += 1
	return count


## The unit's occupied slots as an order-independent, rounded key list, so two layouts can
## be compared on FOOTPRINT alone without caring which soldier index holds which cell.
func _sorted_slot_keys(u: Unit) -> Array:
	var keys: Array = []
	for p in u.soldier_world_slots(u.soldiers):
		keys.append("%.2f,%.2f" % [p.x, p.y])
	keys.sort()
	return keys


# --- Row-major hold-ground reform -------------------------------------------------------
# The file-major branch cancels the hold-ground depth reflection by reversing each file's own
# rank order. Row major carries no per-soldier depth to reverse, so it cancels the same
# reflection with a slot pairing instead. Reachable in real play two ways: the unit-settings
# panel's own cycle, and AUTO on an undisciplined unit.


## A seeded ROW-MAJOR unit with a PARTIAL last rank: 60 men at 8 files = 7 full ranks + 4.
func _make_row_major_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = 8
	u.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	u.seed_sim_soldiers()
	return u


## How far the FARTHEST man's slot moves, and how many move at all -- the two numbers that
## separate "re-squared where it stands" from "marched the block through itself".
func _slot_travel(before: PackedVector2Array, after: PackedVector2Array,
		pitch: float) -> Dictionary:
	var moved: int = 0
	var farthest: float = 0.0
	var total: float = 0.0
	for i in range(before.size()):
		var d: float = before[i].distance_to(after[i])
		total += d
		farthest = maxf(farthest, d)
		if d > pitch * 0.5:
			moved += 1
	return {"moved": moved, "farthest": farthest, "mean": total / maxf(1.0, before.size())}


## The bug this fixes: under raw index-order assignment the depth reflection relabelled the
## whole block, so every man walked the block's full depth through the oncoming half.
func test_row_major_hold_ground_reform_leaves_the_block_where_it_stands() -> void:
	var u := _make_row_major_unit()
	assert_false(u._effective_file_major_reform(),
		"precondition: this fixture really is on the row-major branch")
	u.facing = Vector2.UP
	u._formation_angle = PI
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_true(u.reform_ranks(true), "a flipped partial grid reforms")

	var t: Dictionary = _slot_travel(before, u.soldier_world_slots(u.soldiers), u.rank_pitch_wu())
	# 56 of 60 pair exactly; only the front rank's four outer men have no counterpart in the
	# centred 4-man rear rank, so they hold their file and swap ends.
	assert_eq(int(t["moved"]), 4, "only the four unpairable men move; the other 56 hold")


## The reversal must not cost the reform its purpose: a FULL rank still ends up leading.
func test_row_major_hold_ground_reform_still_brings_a_full_rank_to_the_front() -> void:
	var u := _make_row_major_unit()
	u.facing = Vector2.UP
	u._formation_angle = PI
	assert_eq(_front_slot_count(u), 4,
		"precondition: the flip leaves the 4-man partial rank leading")
	assert_true(u.reform_ranks(true), "a flipped partial grid reforms")
	assert_eq(_front_slot_count(u), 8, "a full 8-man rank fronts the re-squared grid")


## Same footprint as the drill -- only WHICH man holds which cell differs. Anything else
## would make the hold-ground variant a shape change rather than a relabel.
func test_row_major_hold_ground_reform_reaches_the_same_footprint_as_the_drill() -> void:
	var drill := _make_row_major_unit()
	drill.facing = Vector2.UP
	drill._formation_angle = PI
	assert_true(drill.reform_ranks(), "the ordered drill reforms")
	var held := _make_row_major_unit()
	held.facing = Vector2.UP
	held._formation_angle = PI
	assert_true(held.reform_ranks(true), "so does the hold-ground variant")

	assert_eq(_sorted_slot_keys(drill), _sorted_slot_keys(held),
		"identical set of occupied slots; the men holding them are what differs")


## Default false is unchanged: an ORDERED rear-move or countermarch still means the drill,
## and still marches the men through the block. Scoping the pairing to the rally is the point.
func test_row_major_plain_reform_still_marches_the_block_through_itself() -> void:
	var u := _make_row_major_unit()
	u.facing = Vector2.UP
	u._formation_angle = PI
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_true(u.reform_ranks(), "a flipped partial grid reforms")

	var t: Dictionary = _slot_travel(before, u.soldier_world_slots(u.soldiers), u.rank_pitch_wu())
	assert_eq(int(t["moved"]), 60, "the drill still relabels the whole block")
	assert_gt(float(t["farthest"]), u.rank_pitch_wu() * 5.0,
		"and still carries men most of the block's depth, unlike hold-ground")


## The pairing is an involution, so a second hold-ground reform returns every man to the cell
## he started on rather than compounding into a third layout.
func test_row_major_hold_ground_reform_twice_returns_every_man_to_his_own_cell() -> void:
	var u := _make_row_major_unit()
	u.facing = Vector2.UP
	u._formation_angle = PI
	assert_true(u.reform_ranks(true), "first hold-ground reform")
	var once: PackedInt32Array = u._sim_soldier_row_slot.duplicate()
	assert_eq(once.size(), 60, "the pairing is held after the first reform")

	u._formation_angle = PI
	assert_true(u.reform_ranks(true), "second hold-ground reform")
	for i in range(u._sim_soldier_row_slot.size()):
		assert_eq(u._sim_soldier_row_slot[i], i,
			"soldier %d is back on his own cell" % i)


## A casualty trims the pairing at the dead man's own index, exactly like every other
## per-soldier array, so the survivors keep the cells they already held.
func test_row_major_pairing_survives_a_casualty_index_aligned() -> void:
	var u := _make_row_major_unit()
	u.facing = Vector2.UP
	u._formation_angle = PI
	assert_true(u.reform_ranks(true), "a flipped partial grid reforms")
	var before: PackedInt32Array = u._sim_soldier_row_slot.duplicate()

	var dropped: int = 3
	var trimmed: PackedInt32Array = UnitFormation.drop_slot_assignment(before, dropped)
	assert_eq(trimmed.size(), before.size() - 1, "one entry leaves with the dead man")
	var seen := {}
	for c in trimmed:
		assert_false(seen.has(c), "still a permutation after the trim")
		seen[c] = true
	assert_eq(trimmed.size(), seen.size(), "every remaining cell claimed exactly once")


## A genuine reshape changes what the cells MEAN, so a pairing computed against the old
## frontage is dropped rather than reinterpreted against the new one.
func test_row_major_pairing_is_dropped_when_the_frontage_reshapes() -> void:
	var u := _make_row_major_unit()
	u.facing = Vector2.UP
	u._formation_angle = PI
	assert_true(u.reform_ranks(true), "a flipped partial grid reforms")
	assert_eq(u._row_slot_files, 8, "the pairing records the frontage it was computed for")

	# Compared at formation_slots(), which is where the guard lives -- soldier_world_slots()
	# would additionally apply the still-armed _formation_mirror_x and rotate into world
	# space, neither of which is what this test is about.
	u.frontage_override = 10
	assert_eq(u.formation_files(u.soldiers), 10, "precondition: the grid really did reshape")
	var reshaped: PackedVector2Array = u.formation_slots(u.soldiers)
	var plain: PackedVector2Array = UnitFormation.slots(u, u.soldiers)
	assert_eq(reshaped.size(), plain.size(), "same soldier count either way")
	for i in range(reshaped.size()):
		assert_eq(reshaped[i], plain[i],
			"soldier %d falls back to the identity layout on the new grid" % i)


## The row-major pairing must not leak into the file-major branch, which cancels the same
## reflection its own way and would otherwise have the mirror applied twice.
func test_file_major_hold_ground_reform_holds_no_row_pairing() -> void:
	var u := _make_partial_unit()
	assert_true(u._effective_file_major_reform(),
		"precondition: the default fixture is file-major")
	u.facing = Vector2.UP
	u._formation_angle = PI
	assert_true(u.reform_ranks(true), "a flipped partial grid reforms")
	assert_eq(u._sim_soldier_row_slot.size(), 0,
		"the file-major branch leaves the row-major pairing untouched")
