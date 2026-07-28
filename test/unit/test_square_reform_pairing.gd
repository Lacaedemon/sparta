extends GutTest
## NORMAL -> SQUARE reform in a LIVE battle: instantiate the real Battle scene, stage a lone
## 120-man Infantry regiment, let it settle onto its wide-line grid, then order the square
## through the real order pipeline and step the full simulation until the block settles
## again. Guards, PER SOLDIER AND BY ARRAY INDEX, that the men walk to a sensible nearby
## cell rather than to whichever cell happens to share their index:
##   - total travel stays within a small factor of a greedy nearest-slot assignment over the
##     same start positions and the same target cells (greedy is itself an upper bound on
##     the optimal assignment, so the real headroom is at least this large),
##   - almost nobody crosses the block's own lateral centreline. Some inward motion is
##     forced -- the square is narrower than the line it came from -- but a side FLIP is not.
##
## Both are invisible to aggregate checks: a bbox, a Kabsch-fitted shape residual, and a
## settled misslot count all read clean whether each man kept his own side of the block or
## traded places with someone across it. That blind spot is why this bug family (the
## about-face identity swap, the countermarch flank swap) keeps recurring, so the assertions
## here are deliberately per-index rather than per-block.
##
## The pure pairing primitive has its own direct tests below the live-battle ones; this file
## is the full-scene proof (steering + couple + the real order dispatch) as well.

const INFANTRY_COUNT := 120         # 15 line files -> 8 ranks; square_files(120) = 11
const SPAWN := Vector2(700, 450)
# Ticks allowed for the reform to play out. The block moves a few dozen world units at a
# walk, so this is several times the motion's own duration.
const REFORM_TICKS := 400
# How far off the centreline a man must stand for a sign change to count as a real side
# flip, rather than a soldier who was standing on the axis to begin with.
const SIDE_MARGIN_WU := 5.0
# Ceiling on (paired travel / greedy nearest-slot travel). Greedy is an upper bound on the
# optimal assignment, so this is a loose but meaningful "not doing anything silly" bar; the
# index-order layout this replaced measured about 3x the same reference.
const TRAVEL_RATIO_MAX := 1.6
# The narrowing can genuinely force a man standing near the axis across it, where two
# target files straddle the centre. A handful is geometry; a quarter of the block is the bug.
const MAX_SIDE_CROSSINGS := 6

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


## Stage the lone-unit drill battle (no opponent, so nothing but the reform moves anyone).
func _stage_lone_infantry() -> Unit:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": SPAWN.x, "y": SPAWN.y,
			"count": INFANTRY_COUNT, "facing": [0, 1]},
	]
	add_child(_battle)
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 0:
			return u
	return null


## Every live body in the unit's own local slot frame, index-aligned with _sim_soldier_pos.
## The de-rotation must use soldier_block_world_angle() -- facing plus _formation_angle --
## or a comparison spanning a reform that folded the angle reads in the wrong frame entirely.
func _local_positions(u: Unit) -> PackedVector2Array:
	var ang: float = u.soldier_block_world_angle()
	var out := PackedVector2Array()
	for p in u._sim_soldier_pos:
		out.push_back((p - u.position).rotated(-ang))
	return out


## Mean distance from each body to the slot it is steering onto -- the "has this block
## stopped moving" reading, taken as a mean so one straggler can't stand in for the block.
func _mean_slot_error(u: Unit) -> float:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var n: int = mini(slots.size(), u._sim_soldier_pos.size())
	if n <= 0:
		return INF
	var total: float = 0.0
	for i in range(n):
		total += u._sim_soldier_pos[i].distance_to(slots[i])
	return total / float(n)


func _run_ticks(count: int) -> void:
	for _tick in range(count):
		await get_tree().physics_frame


## Total travel of a greedy nearest-slot assignment from `start` onto `target`: take the
## globally shortest remaining soldier-to-cell pair, repeatedly. Greedy is an upper bound on
## the optimal assignment's cost, so a paired total near this really is near-minimal. One
## O(n^2 log n) pass over every pair, which is fine for a one-off reference inside a test.
func _greedy_total(start: PackedVector2Array, target: PackedVector2Array) -> float:
	var n: int = mini(start.size(), target.size())
	if n <= 0:
		return 0.0
	var dists := PackedFloat32Array()
	dists.resize(n * n)
	for i in range(n):
		for s in range(n):
			dists[i * n + s] = start[i].distance_to(target[s])
	var order: Array = range(n * n)
	order.sort_custom(func(a: int, b: int) -> bool:
		if dists[a] != dists[b]:
			return dists[a] < dists[b]
		return a < b)
	var soldier_free := PackedByteArray()
	var cell_free := PackedByteArray()
	soldier_free.resize(n)
	cell_free.resize(n)
	soldier_free.fill(1)
	cell_free.fill(1)
	var total: float = 0.0
	var matched: int = 0
	for key in order:
		var i: int = key / n
		var s: int = key % n
		if soldier_free[i] == 0 or cell_free[s] == 0:
			continue
		soldier_free[i] = 0
		cell_free[s] = 0
		total += dists[key]
		matched += 1
		if matched >= n:
			break
	return total


func test_square_reform_keeps_each_soldier_near_its_own_side_and_cell() -> void:
	var u: Unit = _stage_lone_infantry()
	assert_not_null(u, "the lone Infantry regiment spawned")
	if u == null:
		return
	await _run_ticks(60)   # let the spawned line settle before anything is asked of it
	var before: PackedVector2Array = _local_positions(u)
	assert_eq(before.size(), INFANTRY_COUNT, "every body is accounted for before the reform")

	_battle.enqueue_formation([u.uid], Unit.FORMATION_SQUARE)
	await _run_ticks(REFORM_TICKS)
	assert_eq(u.soldiers, INFANTRY_COUNT,
		"no casualties in a drill battle, so an array index still means the same man")
	assert_lt(_mean_slot_error(u), 4.0,
		"the square has settled onto its slots, so the travel below is the whole reform")

	var after: PackedVector2Array = _local_positions(u)
	var total: float = 0.0
	var crossings: int = 0
	var worst_travel: float = 0.0
	for i in range(before.size()):
		var d: float = before[i].distance_to(after[i])
		total += d
		worst_travel = maxf(worst_travel, d)
		var x0: float = before[i].x
		var x1: float = after[i].x
		if absf(x0) > SIDE_MARGIN_WU and absf(x1) > SIDE_MARGIN_WU and signf(x0) != signf(x1):
			crossings += 1

	# Measure the greedy reference against the SAME target cells the reform actually used,
	# so it isolates the assignment from any drift in where the block ended up.
	var target: PackedVector2Array = u.formation_slots(u.soldiers)
	var greedy: float = _greedy_total(before, target)
	assert_gt(greedy, 0.0, "the greedy reference produced a usable non-zero bound")
	print("[square reform] total travel %.0f wu, greedy bound %.0f wu, ratio %.2f, " % [
			total, greedy, total / maxf(greedy, 0.001)]
		+ "%d side crossings, worst single travel %.1f wu" % [crossings, worst_travel])
	assert_lt(total / maxf(greedy, 0.001), TRAVEL_RATIO_MAX,
		"the reform's per-soldier travel stays near the greedy nearest-slot reference")
	assert_lte(crossings, MAX_SIDE_CROSSINGS,
		"almost nobody trades sides of the block to reach a cell")


func test_square_reform_still_faces_the_ring_outward_after_pairing() -> void:
	# The pairing decides WHO stands on the perimeter, so the outward-facing ring has to
	# follow the paired cell rather than the array index. A facing keyed off the index would
	# leave interior men pointing outward and ring men pointing along the unit heading.
	var u: Unit = _stage_lone_infantry()
	assert_not_null(u, "the lone Infantry regiment spawned")
	if u == null:
		return
	await _run_ticks(60)
	_battle.enqueue_formation([u.uid], Unit.FORMATION_SQUARE)
	await _run_ticks(120)

	var n: int = u.soldiers
	var slots: PackedVector2Array = u.soldier_world_slots(n)
	var facings: PackedVector2Array = u.soldier_world_facings(n)
	var ang: float = u.soldier_block_world_angle()
	# Classify the ring from the grid's own OUTER EDGE rather than from a radius: the block
	# is square, so a corner cell sits further from the centre than an edge cell without
	# being any more exposed, and a radius threshold picks up interior cells near the
	# corners -- which legitimately keep the unit heading. Reading the edge also avoids
	# asking square_is_perimeter about an index, which is the very thing the pairing
	# redefines, so this stays an independent check rather than a tautology.
	var local := PackedVector2Array()
	var max_x: float = 0.0
	var max_y: float = 0.0
	for p in slots:
		var l: Vector2 = (p - u.position).rotated(-ang)
		local.push_back(l)
		max_x = maxf(max_x, absf(l.x))
		max_y = maxf(max_y, absf(l.y))
	var edge: float = u.file_pitch_wu() * 0.5
	var checked: int = 0
	for i in range(n):
		var on_edge: bool = absf(absf(local[i].x) - max_x) < edge \
				or absf(absf(local[i].y) - max_y) < edge
		if not on_edge:
			continue   # interior fill; its facing is the unit heading by design
		checked += 1
		var outward: Vector2 = local[i].rotated(ang)
		assert_gt(facings[i].dot(outward.normalized()), 0.5,
			"soldier %d, standing on the block's outer edge, faces away from its centre" % i)
	assert_gt(checked, 30, "spot-checked a meaningful number of ring soldiers")


# --- The pure pairing primitive ---------------------------------------------
# UnitFormation.pair_slots_by_lateral_file and its two companions, exercised directly:
# no battle, no bodies, just the geometry the live tests above prove end to end.


func _grid(n: int, files: int) -> PackedVector2Array:
	return UnitFormation.block_slots(n, files, Unit.FORMATION_SPACING)


func test_pairing_is_a_permutation_and_never_flips_a_soldier_across_the_centreline() -> void:
	for spec in [[120, 15], [140, 15], [90, 13], [40, 9], [24, 7]]:
		var n: int = spec[0]
		var line_files: int = spec[1]
		var sq_files: int = UnitFormation.square_files(n)
		var start: PackedVector2Array = _grid(n, line_files)
		var target: PackedVector2Array = _grid(n, sq_files)
		var perm: PackedInt32Array = UnitFormation.pair_slots_by_lateral_file(
				start, target, sq_files)

		assert_eq(perm.size(), n, "the pairing covers every soldier (n=%d)" % n)
		var seen := {}
		for cell in perm:
			seen[cell] = true
		assert_eq(seen.size(), n, "the pairing is a bijection onto the cells (n=%d)" % n)

		var crossings: int = 0
		for i in range(n):
			var x0: float = start[i].x
			var x1: float = target[perm[i]].x
			if absf(x0) > SIDE_MARGIN_WU and absf(x1) > SIDE_MARGIN_WU and signf(x0) != signf(x1):
				crossings += 1
		assert_lte(crossings, MAX_SIDE_CROSSINGS,
			"n=%d: the pairing leaves at most a handful of forced centreline crossings" % n)


func test_pairing_beats_index_order_on_total_travel() -> void:
	var n: int = 120
	var sq_files: int = UnitFormation.square_files(n)
	var start: PackedVector2Array = _grid(n, 15)
	var target: PackedVector2Array = _grid(n, sq_files)
	var perm: PackedInt32Array = UnitFormation.pair_slots_by_lateral_file(start, target, sq_files)

	var paired: float = 0.0
	var index_order: float = 0.0
	for i in range(n):
		paired += start[i].distance_to(target[perm[i]])
		index_order += start[i].distance_to(target[i])
	var greedy: float = _greedy_total(start, target)
	print("[pure pairing] paired %.0f wu, index-order %.0f wu, greedy bound %.0f wu" % [
			paired, index_order, greedy])
	assert_lt(paired, index_order * 0.6,
		"pairing by proximity costs well under the index-order layout it replaces")
	assert_lt(paired / maxf(greedy, 0.001), TRAVEL_RATIO_MAX,
		"and stays near the greedy nearest-slot reference")


func test_pairing_falls_back_to_identity_when_there_is_nothing_to_pair_against() -> void:
	var target: PackedVector2Array = _grid(30, 6)
	# No bodies at all: a fresh spawn builds its bodies FROM the slots, so identity is the
	# right answer here, not a degraded one.
	assert_eq(UnitFormation.pair_slots_by_lateral_file(PackedVector2Array(), target, 6),
		UnitFormation.identity_assignment(30),
		"an empty position array pairs to the identity layout")
	# A mismatched length degrades the same way rather than reading out of bounds.
	assert_eq(UnitFormation.pair_slots_by_lateral_file(_grid(12, 4), target, 6),
		UnitFormation.identity_assignment(30),
		"a position array of the wrong length pairs to the identity layout")


func test_permute_slots_relabels_without_moving_the_grid() -> void:
	var slots: PackedVector2Array = _grid(9, 3)
	var perm := PackedInt32Array([8, 7, 6, 5, 4, 3, 2, 1, 0])
	var out: PackedVector2Array = UnitFormation.permute_slots(slots, perm)
	assert_eq(out.size(), slots.size(), "the relabelled grid has the same number of cells")
	for i in range(slots.size()):
		assert_eq(out[i], slots[perm[i]], "cell %d is the one the pairing named" % i)
	# The SET of occupied cells -- and so the footprint -- is untouched by the relabelling.
	var before_sum := Vector2.ZERO
	var after_sum := Vector2.ZERO
	for i in range(slots.size()):
		before_sum += slots[i]
		after_sum += out[i]
	assert_true(before_sum.is_equal_approx(after_sum),
		"relabelling moves nobody: the occupied cells are the same set")
	assert_eq(UnitFormation.permute_slots(slots, PackedInt32Array([0, 1])), slots,
		"a pairing of the wrong size leaves the grid alone rather than reading out of bounds")


func test_dropping_a_casualty_keeps_the_pairing_a_permutation() -> void:
	var perm := PackedInt32Array([3, 0, 4, 1, 2])
	assert_eq(UnitFormation.drop_slot_assignment(perm, 2), PackedInt32Array([3, 0, 1, 2]),
		"the vacated cell (4) is removed and no other id has to move")
	assert_eq(UnitFormation.drop_slot_assignment(perm, 1), PackedInt32Array([2, 3, 0, 1]),
		"vacating cell 0 steps every remaining cell id down by exactly one")
	for bad in [-1, 5, 99]:
		assert_eq(UnitFormation.drop_slot_assignment(perm, bad), perm,
			"an out-of-range index (%d) leaves the pairing untouched" % bad)


func test_repeated_casualties_leave_a_valid_permutation() -> void:
	var n: int = 40
	var sq_files: int = UnitFormation.square_files(n)
	var perm: PackedInt32Array = UnitFormation.pair_slots_by_lateral_file(
			_grid(n, 9), _grid(n, sq_files), sq_files)
	# Walk a plausible casualty sequence: high-to-low within one reap, then a fresh reap.
	for removal in [37, 20, 19, 3, 0, 11]:
		perm = UnitFormation.drop_slot_assignment(perm, mini(removal, perm.size() - 1))
		var seen := {}
		for cell in perm:
			assert_true(cell >= 0 and cell < perm.size(),
				"cell id %d stays inside the shrunken grid" % cell)
			seen[cell] = true
		assert_eq(seen.size(), perm.size(),
			"the pairing is still a bijection after %d casualties" % (n - perm.size()))
