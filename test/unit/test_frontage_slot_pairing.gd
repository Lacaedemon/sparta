extends GutTest
## A FRONTAGE CHANGE in a LIVE battle -- the drag-resize / explicatio / duplicatio family --
## dealt by proximity rather than by array index. A file-major block derives every soldier's
## cell from his own persistent file id and his depth within that file, and both used to be
## handed out in raw array order, so a reshape sent a man to whatever file and rank his index
## happened to name rather than to the one nearest him.
##
## The live tests below stage a lone regiment, let it settle, change its frontage through the
## real order pipeline, and assert PER SOLDIER AND BY ARRAY INDEX that the men walk to a
## nearby cell: total travel far below what the index-order layout would have cost, and
## almost nobody crossing the block's own centreline to get there. Neither shows up in an
## aggregate reading -- a bbox, a Kabsch shape residual and a settled misslot count all read
## clean whether a man kept his own side of the block or traded places across it, which is
## why this bug family keeps recurring.
##
## Both casualty paths are covered, because they have opposite array semantics and only one
## of them can reach a desync: SoldierMelee.reap() splices every per-soldier array (so the
## arrays stay in sync), while UnitCombat.take_casualties drops `soldiers` alone and leaves
## the body layer larger than the live count.
##
## The pure dealing primitives have their own direct tests below the live-battle ones.

const INFANTRY_COUNT := 60          # 11 line files x 6 ranks at the default frontage
const SPAWN := Vector2(600, 420)
## Ticks allowed for a reshape to play out. The block moves a few dozen world units at a
## walk, so this is several times the motion's own duration.
const RESHAPE_TICKS := 240
## The widened frontage the drag-resize demo itself uses.
const WIDE_FILES := 19
## How far off the centreline a man must stand for a sign change to count as a real side
## flip rather than a soldier who was standing on the axis to begin with.
const SIDE_MARGIN_WU := 5.0
## Ceiling on (paired travel / index-order travel) over the same reshape. The index-order
## layout measured about 1.5x a greedy nearest-slot reference on the two demo clips that
## found this, so anything close to 1.0 here would mean the deal changed nothing.
const TRAVEL_RATIO_MAX := 0.85
## A narrowing or widening can genuinely force a man standing near the axis across it, where
## two target files straddle the centre. A handful is geometry; a third of the block is the bug.
const MAX_SIDE_CROSSINGS := 4

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


## Stage the lone-unit drill battle (no opponent, so nothing but the reshape moves anyone).
func _stage_lone_infantry() -> Unit:
	Replay.forced_seed = 885
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


func _run_ticks(count: int) -> void:
	for _tick in range(count):
		await get_tree().physics_frame


## Every live body in the unit's own local slot frame, index-aligned with _sim_soldier_pos.
## The de-rotation must use soldier_block_world_angle() -- facing plus _formation_angle --
## or a comparison spanning a reshape that folded the angle reads in the wrong frame.
func _local_positions(u: Unit) -> PackedVector2Array:
	var ang: float = u.soldier_block_world_angle()
	var out := PackedVector2Array()
	for p in u._sim_soldier_pos:
		out.push_back((p - u.position).rotated(-ang))
	return out


## Total body-to-own-cell distance for `target`, index-aligned against `start`.
func _total_travel(start: PackedVector2Array, target: PackedVector2Array) -> float:
	var n: int = mini(start.size(), target.size())
	var total: float = 0.0
	for i in range(n):
		total += start[i].distance_to(target[i])
	return total


## How many men would end up on the far side of their own block's centreline.
func _side_crossings(start: PackedVector2Array, target: PackedVector2Array) -> int:
	var n: int = mini(start.size(), target.size())
	var crossings: int = 0
	for i in range(n):
		var x0: float = start[i].x
		var x1: float = target[i].x
		if absf(x0) > SIDE_MARGIN_WU and absf(x1) > SIDE_MARGIN_WU and signf(x0) != signf(x1):
			crossings += 1
	return crossings


# --- The live battle ---------------------------------------------------------


func test_a_frontage_change_deals_the_men_by_proximity_not_by_array_index() -> void:
	# The headline case: a settled block is widened, and every man should head for the file
	# nearest him. The comparison is against the layout this replaced -- the same capacities
	# dealt in raw array order -- over the same start positions and the same target grid, so
	# the only difference measured is who goes where.
	var u: Unit = _stage_lone_infantry()
	assert_not_null(u, "the lone Infantry regiment spawned")
	if u == null:
		return
	await _run_ticks(60)
	var start: PackedVector2Array = _local_positions(u)
	var files_before: int = UnitFormation.frontage(u)
	assert_ne(files_before, WIDE_FILES, "precondition: the reshape really changes the frontage")

	u.set_frontage(WIDE_FILES)
	var paired: PackedVector2Array = u.formation_slots(u.soldiers)

	var capacities: PackedInt32Array = UnitFormation.file_capacities(u.soldiers, WIDE_FILES)
	var index_ids: PackedInt32Array = UnitFormation.file_ids_in_index_order(capacities)
	var index_order: PackedVector2Array = UnitFormation.file_major_block_slots(
			index_ids, WIDE_FILES, u.file_pitch_wu(), u.rank_pitch_wu())

	var paired_travel: float = _total_travel(start, paired)
	var index_travel: float = _total_travel(start, index_order)
	assert_gt(index_travel, 0.0, "precondition: the reshape actually moves people")
	assert_lt(paired_travel / index_travel, TRAVEL_RATIO_MAX,
		"the proximity deal walks the block markedly less far than the index-order layout"
		+ " (%.0f wu vs %.0f wu)" % [paired_travel, index_travel])
	assert_lte(_side_crossings(start, paired), MAX_SIDE_CROSSINGS,
		"almost nobody crosses his own block's centreline to reach his new file")
	assert_gt(_side_crossings(start, index_order), MAX_SIDE_CROSSINGS,
		"precondition: the index-order layout really does send men across the centreline")


func test_the_deal_survives_the_reshape_settling_without_re_dealing_every_tick() -> void:
	# Slot targets recomputed from jostling bodies every tick are the churn hazard this sim
	# has been bitten by before, so the deal is taken ONCE and then carried. Nothing should
	# move a man to a different file while the block is walking onto its new grid.
	var u: Unit = _stage_lone_infantry()
	assert_not_null(u, "the lone Infantry regiment spawned")
	if u == null:
		return
	await _run_ticks(60)
	u.set_frontage(WIDE_FILES)
	var _warm: PackedVector2Array = u.formation_slots(u.soldiers)
	var dealt := PackedInt32Array(u._sim_soldier_file)
	var ranks := PackedInt32Array(u._sim_soldier_rank)
	assert_eq(dealt.size(), u.soldiers, "precondition: the deal covers every living soldier")

	await _run_ticks(RESHAPE_TICKS)

	assert_eq(u._sim_soldier_file, dealt,
		"no soldier changed file while the block settled onto the new frontage")
	assert_eq(u._sim_soldier_rank, ranks,
		"nor changed his depth within it")


func test_a_per_soldier_casualty_closes_up_only_the_dead_mans_own_file() -> void:
	# The SoldierMelee.reap() path: every per-soldier array is spliced at the dead man's own
	# index, so the arrays stay in sync and each survivor keeps his file. His own file's rear
	# steps forward over the gap; no other file moves.
	var u: Unit = _stage_lone_infantry()
	assert_not_null(u, "the lone Infantry regiment spawned")
	if u == null:
		return
	await _run_ticks(60)
	u.set_frontage(WIDE_FILES)
	var _warm: PackedVector2Array = u.formation_slots(u.soldiers)
	await _run_ticks(RESHAPE_TICKS)
	assert_eq(u._sim_soldier_rank.size(), u.soldiers,
		"precondition: the settled block carries one rank per living soldier")

	var doomed: int = 23
	var dead_file: int = u._sim_soldier_file[doomed]
	var dead_rank: int = u._sim_soldier_rank[doomed]
	var before_files := PackedInt32Array(u._sim_soldier_file)
	var before_ranks := PackedInt32Array(u._sim_soldier_rank)
	u._sim_soldier_hp[doomed] = 0.0
	SoldierMelee.reap(u, null)

	assert_eq(u._sim_soldier_file.size(), u.soldiers, "the file ids shrank with the block")
	assert_eq(u._sim_soldier_rank.size(), u.soldiers, "and so did the ranks")
	assert_eq(u._sim_soldier_rank.size(), u._sim_soldier_pos.size(),
		"both stay index-aligned with the bodies")

	# Walk the survivors in their original order and check each one against what he held.
	var out: int = 0
	for i in range(before_files.size()):
		if i == doomed:
			continue
		assert_eq(u._sim_soldier_file[out], before_files[i],
			"survivor %d keeps his own file across a casualty" % i)
		var expected: int = before_ranks[i]
		if before_files[i] == dead_file and before_ranks[i] > dead_rank:
			expected -= 1   # his own file closed up over the gap
		assert_eq(u._sim_soldier_rank[out], expected,
			"survivor %d steps forward only if his own file lost the man ahead of him" % i)
		out += 1

	_assert_ranks_are_contiguous_per_file(u._sim_soldier_file, u._sim_soldier_rank)


func test_a_regiment_path_casualty_rebuilds_without_reading_the_jostled_bodies() -> void:
	# The OTHER casualty path. UnitCombat.take_casualties drops `soldiers` without splicing
	# any per-soldier array, so the assignment goes out of sync with the live count and has
	# to be rebuilt -- but the frontage has NOT changed, so this is attrition, not a reshape,
	# and it keeps the historical index-order fill.
	#
	# That distinction is load-bearing. Dealing a casualty rebuild from live bodies instead
	# would re-read every man's file off positions that contact impulses are shoving around,
	# on the tick of every casualty, for the whole of a melee. Measured on the residual
	# melee-lock swirl guard, doing so drove a matched 100-v-100 clash from about 20 degrees
	# of pivot to nearly 58.
	#
	# Driven into that state directly, since reap() is the one path that keeps the arrays in
	# sync and so never reaches this rebuild at all.
	var u: Unit = _stage_lone_infantry()
	assert_not_null(u, "the lone Infantry regiment spawned")
	if u == null:
		return
	await _run_ticks(60)
	u.set_frontage(WIDE_FILES)
	var _warm: PackedVector2Array = u.formation_slots(u.soldiers)
	await _run_ticks(RESHAPE_TICKS)

	var bodies_before: int = u._sim_soldier_pos.size()
	u.soldiers -= 3
	assert_eq(u._sim_soldier_pos.size(), bodies_before,
		"the regiment path leaves the body arrays untouched")

	var dealt := PackedInt32Array(u._sim_soldier_file)
	var _slots: PackedVector2Array = u.formation_slots(u.soldiers)

	assert_eq(u._sim_soldier_file.size(), u.soldiers, "the rebuild tracks the live soldier count")
	assert_eq(u._file_assignment_files, UnitFormation.frontage(u),
		"and commits its file count, so it is not redone on every query")

	var capacities: PackedInt32Array = UnitFormation.file_capacities(
			u.soldiers, UnitFormation.frontage(u))
	assert_eq(Array(u._sim_soldier_file),
		Array(UnitFormation.file_ids_in_index_order(capacities)),
		"attrition rebuilds in index order -- it never re-reads the bodies")
	assert_eq(u._sim_soldier_rank.size(), 0,
		"and drops the explicit ranks with them, since array order is the depth order again")
	assert_ne(Array(u._sim_soldier_file).slice(0, u.soldiers), Array(dealt).slice(0, u.soldiers),
		"precondition: the reshape's own deal really was something other than index order")


func test_a_deal_with_no_bodies_at_all_is_the_answer_and_commits() -> void:
	# There is nothing to deal against before the bodies exist -- a fresh spawn and a tier
	# promotion both build them FROM these slots -- so the index-order fill is the correct
	# answer there, not a placeholder, and it commits like any other.
	var u := Unit.new()
	autofree(u)
	assert_eq(u._sim_soldier_pos.size(), 0, "precondition: a bare unit has no bodies yet")

	u._ensure_file_assignment(24, 6)

	assert_eq(Array(u._sim_soldier_file),
		Array(UnitFormation.file_ids_in_index_order(UnitFormation.file_capacities(24, 6))),
		"it deals the historical index-order fill")
	assert_eq(u._sim_soldier_rank.size(), 0,
		"with no explicit ranks -- array order already is the depth order")
	assert_eq(u._file_assignment_files, 6,
		"and commits, so a far-tier unit does not re-deal on every query")


func test_a_reshape_that_finds_only_part_of_the_body_layer_is_never_cached() -> void:
	# The other fallback, and the one that must NOT be cached. UnitCombat.take_casualties
	# drops `soldiers` before SoldierBodies.step resizes the per-soldier arrays, so a reshape
	# landing inside that window sees a body layer too short to read. The fill it falls back
	# on is a placeholder for that tick; committing it would satisfy _ensure_file_assignment's
	# own early-out forever after and freeze the block on the index-order layout -- the exact
	# caching bug the sibling square fix had to correct in a follow-up.
	var u := Unit.new()
	autofree(u)
	u._sim_soldier_pos.resize(20)          # some bodies, but fewer than the count asked for
	u._file_assignment_files = 5           # so 24-over-6 reads as a genuine reshape

	u._ensure_file_assignment(24, 6)

	assert_eq(u._sim_soldier_file.size(), 24, "it still lays out every man")
	assert_eq(u._file_assignment_files, -1,
		"but leaves the file count invalid, so the next query deals again once the"
		+ " body layer has caught up")


## Every file's ranks run 0, 1, 2, ... with no gaps and no duplicates.
func _assert_ranks_are_contiguous_per_file(files: PackedInt32Array,
		ranks: PackedInt32Array) -> void:
	if ranks.is_empty():
		return
	var by_file := {}
	for i in range(files.size()):
		var f: int = files[i]
		if not by_file.has(f):
			by_file[f] = []
		(by_file[f] as Array).push_back(ranks[i])
	for f in by_file:
		var got: Array = by_file[f]
		got.sort()
		for r in range(got.size()):
			assert_eq(int(got[r]), r,
				"file %d holds rank %d exactly once, with nothing skipped" % [f, r])


# --- The pure dealing primitives ---------------------------------------------
# UnitFormation's file_capacities / file_ids_in_index_order / deal_file_ids_by_lateral_order
# / deal_ranks_by_depth / drop_rank_assignment, exercised directly: no battle, no bodies.


func test_file_capacities_fill_the_count_and_centre_the_partial_rank() -> void:
	for spec in [[60, 11], [140, 16], [140, 8], [24, 7], [9, 20]]:
		var n: int = spec[0]
		var files: int = spec[1]
		var caps: PackedInt32Array = UnitFormation.file_capacities(n, files)
		assert_eq(caps.size(), files, "one capacity per file (n=%d)" % n)
		var total: int = 0
		var deepest: int = 0
		var shallowest: int = 1 << 30
		for c in caps:
			total += c
			deepest = maxi(deepest, c)
			shallowest = mini(shallowest, c)
		assert_eq(total, n, "the capacities account for every man (n=%d, files=%d)" % [n, files])
		assert_lte(deepest - shallowest, 1,
			"no file is more than one rank deeper than another (n=%d)" % n)
		# The deeper files sit in a centred, contiguous span, so a full-strength block reads
		# symmetric rather than one flank permanently a rank deeper.
		var lead: int = 0
		while lead < files and caps[lead] == shallowest:
			lead += 1
		var trail: int = files - 1
		while trail >= 0 and caps[trail] == shallowest:
			trail -= 1
		if lead <= trail:
			assert_lte(absi(lead - (files - 1 - trail)), 1,
				"the deeper files are centred (n=%d, files=%d)" % [n, files])


func test_file_ids_in_index_order_reproduces_the_row_major_fill() -> void:
	# Pins the historical layout: rank by rank, and within a rank the occupied files in
	# ascending order. 10 men over 4 files is 2 full ranks plus a centred pair.
	var caps: PackedInt32Array = UnitFormation.file_capacities(10, 4)
	assert_eq(Array(caps), [2, 3, 3, 2] as Array, "two full ranks, the extra pair centred")
	var ids: PackedInt32Array = UnitFormation.file_ids_in_index_order(caps)
	assert_eq(Array(ids), [0, 1, 2, 3, 0, 1, 2, 3, 1, 2] as Array,
		"an unexpected fill order -- 10 men over 4 files")


func test_the_lateral_deal_gives_the_leftmost_men_the_leftmost_files() -> void:
	# Men strung out left to right in a single rank, deliberately in an array order that
	# has nothing to do with their positions.
	var positions := PackedVector2Array()
	var wanted := PackedInt32Array()
	var xs: Array = [30.0, -10.0, 10.0, -30.0, 0.0, 20.0]
	for x in xs:
		positions.push_back(Vector2(x, 0.0))
	var caps: PackedInt32Array = UnitFormation.file_capacities(positions.size(), 6)
	var ids: PackedInt32Array = UnitFormation.deal_file_ids_by_lateral_order(positions, caps)
	wanted.append_array([5, 1, 3, 0, 2, 4])
	assert_eq(Array(ids), Array(wanted),
		"each man takes the file matching his own place in the left-to-right order")


func test_the_lateral_deal_never_reorders_the_men_across_files() -> void:
	# The property that makes a centreline crossing structurally impossible: every man in
	# file f stands left of every man in file f + 1.
	var positions := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260728
	for _i in range(60):
		positions.push_back(Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-30.0, 30.0)))
	var caps: PackedInt32Array = UnitFormation.file_capacities(positions.size(), 11)
	var ids: PackedInt32Array = UnitFormation.deal_file_ids_by_lateral_order(positions, caps)

	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(11)
	hi.resize(11)
	lo.fill(INF)
	hi.fill(-INF)
	for i in range(ids.size()):
		lo[ids[i]] = minf(lo[ids[i]], positions[i].x)
		hi[ids[i]] = maxf(hi[ids[i]], positions[i].x)
	for f in range(10):
		assert_lte(hi[f], lo[f + 1],
			"file %d lies entirely left of file %d" % [f, f + 1])


func test_the_lateral_deal_falls_back_to_index_order_on_a_capacity_mismatch() -> void:
	var positions := PackedVector2Array([Vector2(1.0, 0.0), Vector2(-1.0, 0.0)])
	var caps: PackedInt32Array = UnitFormation.file_capacities(9, 4)   # nine men, not two
	assert_eq(Array(UnitFormation.deal_file_ids_by_lateral_order(positions, caps)),
		Array(UnitFormation.file_ids_in_index_order(caps)),
		"a deal it cannot make degrades to the historical layout rather than guessing")


func test_deal_ranks_by_depth_orders_each_file_front_to_back() -> void:
	# Two files of three, with the array order deliberately scrambled against depth.
	var positions := PackedVector2Array([
		Vector2(-9.0, 5.0), Vector2(9.0, -5.0), Vector2(-9.0, -5.0),
		Vector2(9.0, 5.0), Vector2(-9.0, 0.0), Vector2(9.0, 0.0),
	])
	var files := PackedInt32Array([0, 1, 0, 1, 0, 1])
	var ranks: PackedInt32Array = UnitFormation.deal_ranks_by_depth(positions, files)
	assert_eq(Array(ranks), [2, 0, 0, 2, 1, 1] as Array,
		"front (-Y) takes rank 0 within each file, independently of array order")


func test_deal_ranks_by_depth_breaks_a_depth_tie_by_index() -> void:
	var positions := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, 0.0), Vector2(0.0, 0.0),
	])
	var ranks: PackedInt32Array = UnitFormation.deal_ranks_by_depth(
			positions, PackedInt32Array([0, 0, 0]))
	assert_eq(Array(ranks), [0, 1, 2] as Array,
		"men standing at the same depth keep array order, so a replay deals identically")


func test_drop_rank_assignment_closes_only_the_dead_mans_own_file() -> void:
	var files := PackedInt32Array([0, 0, 0, 1, 1, 1])
	var ranks := PackedInt32Array([0, 1, 2, 0, 1, 2])
	# Kill file 0's middle man (array index 1, rank 1).
	var out: PackedInt32Array = UnitFormation.drop_rank_assignment(ranks, files, 1)
	assert_eq(Array(out), [0, 1, 0, 1, 2] as Array,
		"file 0's rear steps forward over the gap; file 1 is untouched")


func test_drop_rank_assignment_leaves_a_bad_index_alone() -> void:
	var files := PackedInt32Array([0, 0, 1])
	var ranks := PackedInt32Array([0, 1, 0])
	assert_eq(Array(UnitFormation.drop_rank_assignment(ranks, files, 7)), Array(ranks),
		"an out-of-range index is a no-op rather than a corruption")
	assert_eq(Array(UnitFormation.drop_rank_assignment(ranks, PackedInt32Array([0]), 1)),
		Array(ranks),
		"so is a file array that does not line up")


func test_file_major_block_slots_honours_explicit_ranks() -> void:
	var files := PackedInt32Array([0, 0, 1, 1])
	var ranks := PackedInt32Array([1, 0, 0, 1])
	var derived: PackedVector2Array = UnitFormation.file_major_block_slots(files, 2, 10.0, 10.0)
	var explicit: PackedVector2Array = UnitFormation.file_major_block_slots(
			files, 2, 10.0, 10.0, ranks)
	assert_eq(explicit[0], derived[1], "soldier 0 takes the rank the array names, not his own")
	assert_eq(explicit[1], derived[0], "and soldier 1 takes the other")
	assert_eq(explicit[2], derived[2], "file 1 was already in that order, so it does not move")
	assert_eq(explicit[3], derived[3], "nor does its second man")


func test_file_major_block_slots_ignores_a_wrong_sized_rank_array() -> void:
	var files := PackedInt32Array([0, 0, 1, 1])
	var short := PackedInt32Array([1, 0])
	assert_eq(UnitFormation.file_major_block_slots(files, 2, 10.0, 10.0, short),
		UnitFormation.file_major_block_slots(files, 2, 10.0, 10.0),
		"a rank array that does not cover the block falls back to array order")


func test_lateral_order_is_a_strict_total_order() -> void:
	var positions := PackedVector2Array([
		Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 5.0), Vector2(1.0, 0.0),
	])
	assert_eq(Array(UnitFormation.lateral_order(positions)), [2, 1, 3, 0] as Array,
		"x first, then depth, then array index -- no ambiguity left for a replay to resolve")


# --- The countermarch rank reversal ------------------------------------------
# UnitFormation.reversed_ranks_within_files: the file-major half of Unit.reform_ranks'
# depth reflection, exercised directly.


func test_reversed_ranks_within_files_flips_each_file_independently() -> void:
	# File 0 is three deep, file 1 only two -- so they reverse over different depths.
	var files := PackedInt32Array([0, 0, 0, 1, 1])
	var ranks := PackedInt32Array([0, 1, 2, 0, 1])
	assert_eq(Array(UnitFormation.reversed_ranks_within_files(files, ranks)),
		[2, 1, 0, 1, 0] as Array,
		"each file reverses over its OWN depth, not the block's deepest")


func test_reversed_ranks_within_files_is_its_own_inverse() -> void:
	var files := PackedInt32Array([0, 1, 0, 1, 0, 2])
	var ranks := PackedInt32Array([0, 0, 1, 1, 2, 0])
	var once: PackedInt32Array = UnitFormation.reversed_ranks_within_files(files, ranks)
	assert_eq(Array(UnitFormation.reversed_ranks_within_files(files, once)), Array(ranks),
		"reversing twice restores the original depths -- a reflection, not a rotation")


func test_reversed_ranks_within_files_derives_depth_from_array_order_when_unset() -> void:
	# The file-major layout's own fallback: a soldier's rank is how many EARLIER array
	# entries share his file id. An empty rank array must reverse the same block.
	var files := PackedInt32Array([0, 1, 0, 1, 0])
	assert_eq(Array(UnitFormation.reversed_ranks_within_files(files, PackedInt32Array())),
		[2, 1, 1, 0, 0] as Array,
		"array order IS the depth order when no explicit rank array is stored")


func test_reversed_ranks_within_files_degrades_on_a_stale_rank() -> void:
	# A rank at or past its own file's depth would reverse to a negative one.
	var files := PackedInt32Array([0, 0])
	assert_eq(Array(UnitFormation.reversed_ranks_within_files(files,
			PackedInt32Array([0, 9]))), [1, 0] as Array,
		"an out-of-range rank clamps to the front instead of going negative")
	assert_eq(Array(UnitFormation.reversed_ranks_within_files(
			PackedInt32Array(), PackedInt32Array())), [] as Array,
		"an empty block reverses to an empty block")
