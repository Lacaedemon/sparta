extends GutTest
## Post-about-face reform in a LIVE battle: instantiate the real Battle scene, stage a lone
## depleted-grid Spearmen regiment (40 men at 9 files = 4 full ranks + a 4-man partial rank,
## the same staging as demos/inputs/about-face.json), issue a rear-sector move through the
## real order pipeline, and step the full simulation tick by tick. Guards, per soldier and by
## array index, that:
##   - the pure facing-flip still holds every body at its own position (the identity-holding
##     invariant -- no regression to the true-conversio fix),
##   - the drilled order (reform:true) re-forms a FULL rank onto the new front before the
##     march steps off, with the old partial rank returned to the rear,
##   - the hasty order (reform:false) marches at once with the flipped grid and re-forms on
##     arrival instead.
## The isolated-unit sequencing lives in test_reform_ranks.gd; this is the full-scene proof
## (steering + couple + the real order dispatch), the layer where aggregate-only checks have
## missed an about-face bug before.

const SPEARMEN_COUNT := 40          # 9 files -> 4 full ranks + a 4-man partial rank
const SPAWN := Vector2(500, 430)
const PARTIAL_FIRST_INDEX := 36     # rank-major layout: the last 4 indices are the partial rank

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


## Stage the lone-unit drill battle (no opponent) and settle the bodies onto their slots.
func _stage_lone_spearmen() -> Unit:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads them
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y,
			"count": SPEARMEN_COUNT, "facing": [0, 1]},
	]
	add_child(_battle)
	var unit: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 0:
			unit = u
	return unit


## How many bodies stand in the unit's FRONT row (within half a rank spacing of the
## front-most body, by projection onto the unit's facing).
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


## True when body `index` stands in the unit's REAR row.
func _in_rear_row(u: Unit, index: int) -> bool:
	var worst: float = INF
	for p in u._sim_soldier_pos:
		worst = minf(worst, (p - u.position).dot(u.facing))
	var d: float = (u._sim_soldier_pos[index] - u.position).dot(u.facing)
	return d - worst < Unit.FORMATION_SPACING * 0.5


## Tick budget for the order-response delay plus the 180-degree turn, with margin.
func _turn_budget(u: Unit) -> int:
	var seconds: float = u.order_response_delay + PI / Unit.CONVERSIO_TURN_RATE
	return int(ceil(seconds * Replay.PHYSICS_TPS)) + 30


## Signed lateral offset of body `index` from the unit's own centre, projected onto a FIXED
## world-space axis -- which flank of the block it stands on and how far out. Deliberately a
## FIXED axis (captured once, e.g. from the unit's pre-turn facing), not `u.facing.rotated(PI
## * 0.5)` re-read at each call: an about-face rotates facing a full 180°, which flips that
## axis to point the opposite way in world space, so re-deriving it from the CURRENT facing at
## two different times would flag every soldier as having "crossed sides" even when none of
## them actually moved sideways at all -- exactly the same-file/opposite-file ambiguity the
## fix itself has to resolve (see soldier_world_slots' _formation_mirror_x doc). Comparing
## before/after on one FIXED axis is what actually answers "did this soldier end up on the
## same physical flank it started on".
func _lateral_offset(u: Unit, index: int, file_axis: Vector2) -> float:
	return (u._sim_soldier_pos[index] - u.position).dot(file_axis)


func test_drilled_rear_move_refills_the_front_rank_before_marching() -> void:
	var u := _stage_lone_spearmen()
	assert_not_null(u, "the scenario staged the lone spearmen regiment")
	if u == null:
		return
	for _k in range(40):   # let the spawned bodies settle on their slots
		await get_tree().physics_frame
	var files: int = u.formation_files(u.soldiers)
	assert_eq(files, 9, "40 spearmen deploy 9 files wide (4 full ranks + a 4-man partial)")
	var dest := SPAWN + Vector2(0, -180)   # straight behind the DOWN-facing unit
	var before: PackedVector2Array = u._sim_soldier_pos.duplicate()

	_battle._apply_order_cmd({"units": [u.uid], "x": dest.x, "y": dest.y,
		"target": -1, "mode": 0, "reform": true})

	# Phase 1 -- the pure facing-flip: every body holds its OWN position (by array index)
	# for the whole turn. This is the identity-holding invariant the true-conversio fix
	# established; the reform must not erode it during the flip itself.
	var worst_hold := 0.0
	for _i in range(_turn_budget(u)):
		await get_tree().physics_frame
		if not u.is_order_turning():
			break
		for i in range(before.size()):
			worst_hold = maxf(worst_hold, u._sim_soldier_pos[i].distance_to(before[i]))
	assert_false(u.is_order_turning(), "the about-face completed within its budget")
	assert_lt(worst_hold, 1.0,
		"every soldier held its own position through the turn (worst drift %.3f px)" % worst_hold)
	assert_true(u.facing.is_equal_approx(Vector2.UP), "the unit ended facing its destination")

	# Phase 2 -- the reform: the march holds while the countermarch brings a full rank onto
	# the new front, then commits. The timer is the unit's own depth/pace-derived timeout.
	assert_false(u.has_move_target, "no march at turn end: the reform phase holds it")
	assert_gt(u._reform_timer, 0.0, "the reform hold armed on conversio completion")
	# The order bookkeeping (_update_current_order) runs at the top of the NEXT _think
	# tick, so give it one frame before reading the phase.
	await get_tree().physics_frame
	if u.current_order != null:
		assert_eq(u.current_order.phase, Order.Phase.REFORM,
			"the order transcript shows the REFORM phase")
	var reform_budget: int = int(ceil(u._reform_timeout() * Replay.PHYSICS_TPS)) + 30
	var start_pos: Vector2 = u.position
	for _i in range(reform_budget):
		await get_tree().physics_frame
		if u.has_move_target:
			break
	assert_true(u.has_move_target, "the parked march commits once the ranks re-form")
	# A partial rear rank centres on fewer columns than a full one, so the block's own local
	# grid (UnitFormation.block_slots) is not perfectly centred on `position` -- its true mean
	# sits a fraction of a rank off, front-to-back. SoldierBodies.couple() gently follows the
	# soldiers' actual centroid toward that mean while they arrive on their (re-)squared slots,
	# so `position` always wobbles a little during any reform, independent of which soldier
	# lands on which slot. The countermarch fix changes each soldier's individual target (see
	# soldier_world_slots' _formation_mirror_x), which changes how far bodies travel and so
	# exactly where in its decaying oscillation couple() gets caught at the instant the ranks
	# finish settling -- a strictly smaller total march can commit sooner and catch the wobble
	# at a slightly less-settled point than a slower one does. On top of that, the settling
	# window itself (_reform_timeout()) is derived from the unit's own back_speed_fraction: a
	# slower per-type backward pace widens the window and so accumulates more follow drift.
	# Bound the wobble at one file spacing scaled by how much slower THIS type's own fraction
	# is than the 0.5 baseline the countermarch fix was tuned against -- loose enough not to be
	# a coin flip on exactly which tick the reform happens to commit, at any type's pace.
	var creep_tolerance: float = Unit.FORMATION_SPACING * (0.5 / u.back_speed_fraction)
	assert_lt(u.position.distance_to(start_pos), creep_tolerance,
		"the regiment held its ground for the reform (no march creep, tolerance %.3f px)"
			% creep_tolerance)
	assert_true(u._reform_bodies_settled(), "the march waited for the ranks, not the timeout")
	assert_eq(_front_row_count(u), files,
		"a FULL rank fronts the new heading at step-off, not the 4-man partial")
	for i in range(PARTIAL_FIRST_INDEX, SPEARMEN_COUNT):
		assert_true(_in_rear_row(u, i),
			"partial-rank body %d ends at the new REAR, no longer leading" % i)

	# And the march is real: the unit closes on the destination (and the order transcript,
	# one bookkeeping tick behind the commit, has advanced REFORM -> MARCH).
	for _i in range(int(Replay.PHYSICS_TPS)):
		await get_tree().physics_frame
	assert_lt(u.position.y, start_pos.y - 1.0, "the unit is marching toward the rear destination")
	if u.current_order != null:
		assert_eq(u.current_order.phase, Order.Phase.MARCH,
			"the order transcript advanced REFORM -> MARCH")


## Regression test for the countermarch file-swap bug: a completed drilled about-face +
## reform must keep every soldier on its OWN FLANK (only rank/depth order reverses within a
## file), never swap it to the opposite side of the block. Before the fix, reform_ranks()
## dropped _formation_angle straight to 0 and soldier_world_slots rotated the whole grid by
## the resulting `ang` in one rigid step -- a POINT reflection of every local slot, which
## negates the lateral (file) coordinate along with the depth (rank) coordinate. That put the
## leftmost soldier (index 0, file 0) on the RIGHT flank after reform and vice versa: soldiers
## visually "collapsed and expanded" across the block instead of just trading front-for-rear
## within their own file. Confirmed via state-dump on demos/inputs/back-speed-by-type.json's
## Spearmen regiment: soldier 0 moved from world x=431.5 to x=368.5 while soldier 7 moved the
## opposite direction (368.5 to 431.5) -- an exact file-0/file-7 swap.
func test_drilled_reform_keeps_every_soldier_on_its_own_flank() -> void:
	var u := _stage_lone_spearmen()
	assert_not_null(u, "the scenario staged the lone spearmen regiment")
	if u == null:
		return
	for _k in range(40):   # let the spawned bodies settle on their slots
		await get_tree().physics_frame
	var files: int = u.formation_files(u.soldiers)
	assert_eq(files, 9, "40 spearmen deploy 9 files wide (4 full ranks + a 4-man partial)")
	var dest := SPAWN + Vector2(0, -180)   # straight behind the DOWN-facing unit

	# A FIXED reference axis, captured once from the PRE-turn facing -- the about-face reverses
	# facing a full 180°, which would flip a same-tick-derived "facing.rotated(PI/2)" axis to
	# point the opposite way, so re-deriving it fresh at each measurement would flag every
	# soldier as having switched flanks even when none of them actually did. One fixed axis
	# answers "is this soldier still on the physical side of the battlefield it started on".
	var file_axis: Vector2 = u.facing.rotated(PI * 0.5)

	# Capture each body's lateral (flank) offset before the about-face -- the invariant a
	# countermarch must preserve is this side, not the world-frame x/y (those necessarily
	# change as the block reverses heading).
	var lateral_before: PackedFloat32Array = PackedFloat32Array()
	for i in range(SPEARMEN_COUNT):
		lateral_before.push_back(_lateral_offset(u, i, file_axis))

	_battle._apply_order_cmd({"units": [u.uid], "x": dest.x, "y": dest.y,
		"target": -1, "mode": 0, "reform": true})

	# Run the about-face out.
	for _i in range(_turn_budget(u)):
		await get_tree().physics_frame
		if not u.is_order_turning():
			break
	assert_false(u.is_order_turning(), "the about-face completed within its budget")

	# Run the reform out until the parked march commits (ranks re-formed onto the new slots).
	await get_tree().physics_frame   # let _update_current_order advance the phase bookkeeping
	var reform_budget: int = int(ceil(u._reform_timeout() * Replay.PHYSICS_TPS)) + 30
	for _i in range(reform_budget):
		await get_tree().physics_frame
		if u.has_move_target:
			break
	assert_true(u.has_move_target, "the parked march commits once the ranks re-form")
	assert_true(u._reform_bodies_settled(), "the march waited for the ranks, not the timeout")

	# The core assertion: every body's lateral offset kept its SIGN (same flank) across the
	# whole about-face + reform. A point-reflection bug flips the sign for every soldier not
	# sitting exactly on the centreline; a correct depth-only reflection never does.
	var flipped: Array = []
	for i in range(SPEARMEN_COUNT):
		var before_l: float = lateral_before[i]
		var after_l: float = _lateral_offset(u, i, file_axis)
		# Bodies near the centreline (|offset| well under half a file spacing) carry no
		# meaningful flank to preserve; skip them to avoid a sign flip on float noise.
		if absf(before_l) < Unit.FORMATION_SPACING * 0.25:
			continue
		if sign(before_l) != sign(after_l):
			flipped.append(i)
	assert_eq(flipped, [], "no soldier crossed to the opposite flank during the countermarch")

	# Concretely, the reported case: the leftmost and rightmost bodies of the original front
	# rank (indices 0 and files-1) must still be the leftmost/rightmost bodies after reform,
	# not swapped.
	var first_sign: float = sign(lateral_before[0])
	var last_sign: float = sign(lateral_before[files - 1])
	assert_eq(sign(_lateral_offset(u, 0, file_axis)), first_sign,
		"soldier 0 is still on the flank it started on after reform")
	assert_eq(sign(_lateral_offset(u, files - 1, file_axis)), last_sign,
		"soldier %d is still on the flank it started on after reform" % (files - 1))


func test_hasty_rear_move_marches_with_the_flipped_grid_and_reforms_on_arrival() -> void:
	var u := _stage_lone_spearmen()
	assert_not_null(u, "the scenario staged the lone spearmen regiment")
	if u == null:
		return
	for _k in range(40):
		await get_tree().physics_frame
	var files: int = u.formation_files(u.soldiers)
	var dest := SPAWN + Vector2(0, -80)   # short rear leg so arrival fits the tick budget

	_battle._apply_order_cmd({"units": [u.uid], "x": dest.x, "y": dest.y,
		"target": -1, "mode": 0, "reform": false})

	for _i in range(_turn_budget(u)):
		await get_tree().physics_frame
		if u.has_move_target:
			break
	assert_true(u.has_move_target, "a hasty rear move steps off straight from the about-face")
	assert_eq(u._reform_timer, 0.0, "no reform hold in haste")
	assert_true(u._reform_on_arrival, "the reform is parked for arrival instead")
	assert_eq(_front_row_count(u), SPEARMEN_COUNT - PARTIAL_FIRST_INDEX,
		"in haste the 4-man partial rank leads the transit (the deliberate tradeoff)")

	# March to arrival: ~75 px at no worse than half walk pace, plus margin.
	var march_budget: int = int(ceil(80.0 / maxf(u.walk_speed * 0.5, 1.0) * Replay.PHYSICS_TPS)) + 60
	for _i in range(march_budget):
		await get_tree().physics_frame
		if not u.has_move_target:
			break
	assert_false(u.has_move_target, "the march arrived within its budget")
	assert_false(u._reform_on_arrival, "the deferred reform fired on arrival")
	assert_eq(u._formation_angle, 0.0, "and re-squared the grid to the heading")

	# The bodies re-form at the destination: a full rank fronts the heading again.
	var settle_budget: int = int(ceil(u._reform_timeout() * Replay.PHYSICS_TPS)) + 30
	for _i in range(settle_budget):
		await get_tree().physics_frame
		if u._reform_bodies_settled():
			break
	assert_true(u._reform_bodies_settled(), "the bodies re-formed at the destination")
	assert_eq(_front_row_count(u), files, "a FULL rank fronts the heading at the destination")
	for i in range(PARTIAL_FIRST_INDEX, SPEARMEN_COUNT):
		assert_true(_in_rear_row(u, i), "partial-rank body %d is back at the rear" % i)
