extends GutTest
## A widening dealt from the bodies splits each old file across new ones, and the lateral deal
## alone decides which of a file's men go where by the depth tie-break: the rear half to one
## new file and the front half to the next, so the two halves walk straight through each other
## to reach a shallower block. UnitFormation.untangle_column_routes re-pairs the men of each
## file line so that no two of their straight routes cross.
##
## The live tests stage the case that found it: a lone block of 140 Spearmen (9 files of 16)
## doubled to 18 files by an explicatio held on its right flank, the clip
## `file-doubling-asymmetric` shows.

const SPAWN := Vector2(500, 300)
const SPEARMEN := 140
## Ticks for the explicatio to play out: the farthest man walks about 90 wu, two and a half
## seconds at a jog, and the reshape measured on main settles within 260 ticks of the order.
const RESHAPE_TICKS := 300

var _battle: Node = null


func after_each() -> void:
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _stage_spearmen() -> Unit:
	Replay.forced_seed = 1929
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y,
			"count": SPEARMEN, "facing": [0, 1]},
	]
	add_child(_battle)
	for _i in range(40):
		await get_tree().physics_frame
	return _battle._units.get_child(0) as Unit


## Pairs of men laterally closer than the unit's own tie width whose straight routes from
## where they stand to their dealt slots properly cross, clear of the unit's own touch margin.
func _file_line_crossings(u: Unit) -> int:
	var live: PackedVector2Array = u.to_slot_frame(u._sim_soldier_pos)
	var slots: PackedVector2Array = u.formation_slots(u.soldiers, false, false)
	var tie: float = u.file_pitch_wu() * u.column_tie_pitch_frac
	var margin: float = u.soldier_body_radius() * u.route_touch_body_frac
	var crossings: int = 0
	for i in range(live.size()):
		for j in range(i + 1, live.size()):
			if absf(live[i].x - live[j].x) < tie \
					and UnitFormation.routes_cross(live[i], slots[i], live[j], slots[j], margin):
				crossings += 1
	return crossings


## A proper crossing: each route's ends strictly on opposite sides of the other's line.
func _cross(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var d1: float = (a2 - a1).cross(b1 - a1)
	var d2: float = (a2 - a1).cross(b2 - a1)
	var d3: float = (b2 - b1).cross(a1 - b1)
	var d4: float = (b2 - b1).cross(a2 - b1)
	return d1 * d2 < 0.0 and d3 * d4 < 0.0


func _nearest_pair(points: PackedVector2Array) -> float:
	var best: float = INF
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			best = minf(best, points[i].distance_to(points[j]))
	return best


# --- The live explicatio ------------------------------------------------------


## The deal sends no two men of one file line on crossing routes. The depth tie-break alone
## sends the rear half of each file one way and the front half the other: here 178 pairs of
## men of one file line were on crossing routes before the untangle.
func test_an_anchored_explicatio_sends_no_two_men_of_a_file_line_through_each_other() -> void:
	var u: Unit = await _stage_spearmen()
	assert_not_null(u, "the lone Spearmen block spawned")
	if u == null:
		return
	assert_eq(UnitFormation.frontage(u), 9, "precondition: 140 spearmen on 16-man files stand on 9 files")
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.RIGHT)
	assert_eq(UnitFormation.frontage(u), 18, "the explicatio doubles the frontage")
	assert_eq(_file_line_crossings(u), 0,
		"no two men of one file line are sent on crossing routes")


## The unit untangles with its own touch margin, a tenth of a body radius: the file that stays
## on its own line in a widening held on that flank sends men straight up it onto spots others
## are stepping out of, and the bodies' jitter tips some of those touches into crossings of a
## few hundredths of a wu, which a trade would turn into diagonals round men standing still.
func test_the_deal_untangles_with_the_units_own_touch_margin() -> void:
	var u: Unit = await _stage_spearmen()
	assert_not_null(u, "the lone Spearmen block spawned")
	if u == null:
		return
	var live: PackedVector2Array = u.to_slot_frame(u._sim_soldier_pos)
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.RIGHT)
	u.formation_slots(u.soldiers)   # the deal runs on the first slot query after the reshape
	var files: int = UnitFormation.frontage(u)
	var dealt: PackedInt32Array = UnitFormation.deal_file_ids_by_lateral_order(live,
			UnitFormation.file_capacities(u.soldiers, files))
	var ranks: PackedInt32Array = UnitFormation.deal_ranks_by_depth(live, dealt)
	var slots: PackedVector2Array = UnitFormation.apply_frontage_anchor_offset(
			UnitFormation.file_major_block_slots(dealt, files, u.file_pitch_wu(), u.rank_pitch_wu(),
					ranks), u.frontage_anchor_offset)
	var tie: float = u.file_pitch_wu() * u.column_tie_pitch_frac
	var margin: float = u.soldier_body_radius() * u.route_touch_body_frac
	var with_margin: PackedInt32Array = UnitFormation.untangle_column_routes(live, slots, tie, margin)
	var without: PackedInt32Array = UnitFormation.untangle_column_routes(live, slots, tie, 0.0)
	assert_ne(with_margin, without, "precondition: the margin changes who trades here")
	var expected := PackedInt32Array()
	for i in range(with_margin.size()):
		expected.push_back(dealt[with_margin[i]])
	assert_eq(u._sim_soldier_file, expected, "the unit's files are the deal untangled with its margin")


## The men never close below the overlap floor the demo defect scan judges a reshape by:
## a quarter of two touching bodies (DemoDefects.OVERLAP_BODY_FRAC of twice the body radius,
## 2.25 wu for a Spearman). Before the untangle the halves of each file passed through one
## another and brought two men to 1.69 wu of each other here, 215 ticks into the reshape.
func test_an_anchored_explicatio_never_brings_two_men_onto_each_other() -> void:
	var u: Unit = await _stage_spearmen()
	assert_not_null(u, "the lone Spearmen block spawned")
	if u == null:
		return
	var floor_wu: float = 2.0 * u.soldier_body_radius() * DemoDefects.OVERLAP_BODY_FRAC
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.RIGHT)
	var closest: float = INF
	var closest_tick: int = -1
	for tick in range(RESHAPE_TICKS):
		await get_tree().physics_frame
		var d: float = _nearest_pair(u._sim_soldier_pos)
		if d < closest:
			closest = d
			closest_tick = tick
	assert_gte(closest, floor_wu,
		"the nearest two men come within %.2f wu (tick %d); the floor is %.2f wu"
		% [closest, closest_tick, floor_wu])


# --- The pure primitives ------------------------------------------------------


## One file line of `n` men standing a pitch apart in depth, centred on x = 0.
func _column(n: int, pitch: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for r in range(n):
		out.push_back(Vector2(0.0, (r - (n - 1) * 0.5) * pitch))
	return out


## The column of 8 split the way the lateral deal splits it when the block widens off its far
## flank, so both new files lie to one side of the old one: the rear four to the farther new
## file and the front four to the nearer, on a block half as deep. The rear half walks forward
## past the front half walking back, and the halves cross; once untangled no two routes cross.
## (Two new files straddling the old one, as
## the centre file of a centred explicatio splits, cannot cross: each half keeps to its side.)
func test_untangle_interleaves_a_file_split_by_the_depth_tie_break() -> void:
	var pitch: float = 9.0
	var men: PackedVector2Array = _column(8, pitch)
	var slots := PackedVector2Array()
	for r in range(8):
		var file_x: float = -2.0 * pitch if r < 4 else -pitch
		slots.push_back(Vector2(file_x, (r % 4 - 1.5) * pitch))
	var before: int = _crossings(men, slots, UnitFormation.identity_assignment(8))
	assert_gt(before, 0, "precondition: the depth tie-break's split sends the halves across each other")
	var perm: PackedInt32Array = UnitFormation.untangle_column_routes(men, slots, 0.25 * pitch)
	assert_eq(_crossings(men, slots, perm), 0, "no two routes cross once untangled")
	assert_eq(_sorted(perm), UnitFormation.identity_assignment(8), "every slot is still taken once")


## A trade can set up a crossing with a man the pass has already gone by, so the loop runs
## until a pass trades nobody. A file of 16 split across three new files to one side, dealt in
## depth order (the rear six to the nearest, the next six to the middle one, the front four to
## the farthest), still has crossing routes after a single pass.
func test_untangle_runs_until_no_routes_cross() -> void:
	var pitch: float = 9.0
	var men: PackedVector2Array = _column(16, pitch)
	var per_file: int = 6
	var slots := PackedVector2Array()
	for r in range(16):
		slots.push_back(Vector2(-(1 + floori(float(r) / per_file)) * pitch,
				(r % per_file - (per_file - 1) * 0.5) * pitch))
	assert_gt(_crossings(men, slots, UnitFormation.identity_assignment(16)), 0,
		"precondition: the depth-order split crosses")
	var perm: PackedInt32Array = UnitFormation.untangle_column_routes(men, slots, 0.25 * pitch)
	assert_eq(_crossings(men, slots, perm), 0, "no two routes cross once untangled")


## Men further apart laterally than the tie width belong to different files, whose order the
## lateral deal settles; the untangle never trades them, however their routes run.
func test_untangle_never_trades_men_of_different_file_lines() -> void:
	var men := PackedVector2Array([Vector2(0.0, 0.0), Vector2(9.0, 0.0)])
	var slots := PackedVector2Array([Vector2(9.0, 9.0), Vector2(0.0, 9.0)])
	assert_eq(_crossings(men, slots, UnitFormation.identity_assignment(2)), 1,
		"precondition: the two routes cross")
	assert_eq(UnitFormation.untangle_column_routes(men, slots, 2.25),
		UnitFormation.identity_assignment(2), "men 9 wu apart with a 2.25 wu tie are left alone")
	assert_eq(UnitFormation.untangle_column_routes(men, slots, 18.0),
		PackedInt32Array([1, 0]), "the same men inside the tie width trade")


func test_untangle_leaves_a_mismatched_or_trivial_input_alone() -> void:
	var men: PackedVector2Array = _column(3, 9.0)
	var identity: PackedInt32Array = UnitFormation.identity_assignment(3)
	assert_eq(UnitFormation.untangle_column_routes(men, PackedVector2Array([Vector2.ZERO]), 9.0),
		identity, "slots that do not line up with the men")
	assert_eq(UnitFormation.untangle_column_routes(men, men, 0.0), identity, "no tie width")
	assert_eq(UnitFormation.untangle_column_routes(PackedVector2Array([Vector2.ZERO]),
		PackedVector2Array([Vector2.ONE]), 9.0), PackedInt32Array([0]), "a lone man")




## The demo scan's file_line_routes_crossing field judges a file line, and a crossing, by the
## same widths the sim's deal untangles them by.
func test_the_demo_scan_reads_file_lines_at_the_sims_own_widths() -> void:
	assert_eq(DemoDefects.FILE_LINE_TIE_FRAC, UnitFormation.COLUMN_TIE_PITCH_FRAC)
	assert_eq(DemoDefects.ROUTE_TOUCH_BODY_FRAC, UnitFormation.ROUTE_TOUCH_BODY_FRAC)


## When a file's near new file is its own line, a man of the rear half walks straight up the
## line onto the spot a man of the front half is stepping out of. The routes only touch, and the
## rear man follows the other in; trading them would send him on a diagonal round a man who
## stands still, which a settled rank can block. The untangle leaves them.
func test_untangle_leaves_a_man_following_another_into_his_spot() -> void:
	var pitch: float = 9.0
	var men: PackedVector2Array = _column(4, pitch)
	var slots := PackedVector2Array([Vector2(0.0, -0.5 * pitch), Vector2(0.0, 0.5 * pitch),
			Vector2(-pitch, -0.5 * pitch), Vector2(-pitch, 0.5 * pitch)])
	var identity: PackedInt32Array = UnitFormation.identity_assignment(4)
	assert_eq(UnitFormation.untangle_column_routes(men, slots, 0.25 * pitch), identity,
		"the men keep the places the deal gave them")


## A crossing that passes within the margin of a route's end reads as a touch: the jitter of men
## standing on their slots must not trade them.
func test_untangle_leaves_a_crossing_inside_the_margin() -> void:
	var men := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.2, 9.0)])
	var slots := PackedVector2Array([Vector2(0.0, 18.0), Vector2(-9.0, 9.0)])
	assert_eq(_crossings(men, slots, UnitFormation.identity_assignment(2)), 1,
		"precondition: the routes properly cross, one starting 0.2 wu off the other's line")
	assert_eq(UnitFormation.untangle_column_routes(men, slots, 2.25, 0.45),
		UnitFormation.identity_assignment(2), "inside a 0.45 wu margin they are left alone")
	assert_eq(UnitFormation.untangle_column_routes(men, slots, 2.25, 0.0),
		PackedInt32Array([1, 0]), "with no margin they trade")


func test_routes_cross_counts_only_a_proper_crossing_clear_of_the_margin() -> void:
	assert_true(UnitFormation.routes_cross(Vector2(0, 0), Vector2(2, 2), Vector2(0, 2), Vector2(2, 0)),
		"an X crosses")
	assert_false(UnitFormation.routes_cross(Vector2(0, 0), Vector2(2, 2), Vector2(0, 2), Vector2(2, 0), 1.5),
		"the same X with every end within the margin of the other line does not")
	assert_false(UnitFormation.routes_cross(Vector2(0, 0), Vector2(2, 0), Vector2(1, 0), Vector2(1, 2)),
		"a route starting on another only touches it")
	assert_false(UnitFormation.routes_cross(Vector2(0, 0), Vector2(2, 0), Vector2(0, 1), Vector2(2, 1)),
		"parallel routes do not")
	assert_false(UnitFormation.routes_cross(Vector2(0, 0), Vector2(1, 0), Vector2(2, -1), Vector2(2, 1)),
		"a route that ends short of the other's line does not")
	assert_false(UnitFormation.routes_cross(Vector2(1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(2, 0)),
		"a man standing still crosses nothing")
	# One route starting 0.2 wu off the other's line, read with each route first.
	var a1 := Vector2(0, 0)
	var a2 := Vector2(0, 18)
	var b1 := Vector2(0.2, 9)
	var b2 := Vector2(-9, 9)
	assert_true(UnitFormation.routes_cross(a1, a2, b1, b2) and UnitFormation.routes_cross(b1, b2, a1, a2),
		"with no margin it crosses either way round")
	assert_false(UnitFormation.routes_cross(a1, a2, b1, b2, 0.45), "inside the margin, read one way")
	assert_false(UnitFormation.routes_cross(b1, b2, a1, a2, 0.45), "inside the margin, read the other way")


func _crossings(men: PackedVector2Array, slots: PackedVector2Array, perm: PackedInt32Array) -> int:
	var count: int = 0
	for i in range(men.size()):
		for j in range(i + 1, men.size()):
			if _cross(men[i], slots[perm[i]], men[j], slots[perm[j]]):
				count += 1
	return count


func _sorted(perm: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array(perm)
	out.sort()
	return out
