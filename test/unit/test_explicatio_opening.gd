extends GutTest
## When an explicatio's files open, against when its men step into the intervals
## (ExplicatioOpening.Reading; the sources are quoted there and in
## docs/historical-reshaping-maneuvers.md, "The explicatio drills"):
## - TOGETHER, the default: the files open out while the men step in, the sim's own inference.
## - FILES_FIRST: each old file opens out to its distance as a whole, its men keeping their places
##   in it, and only then do they step into the interval beside it (Asclepiodotus 10.17 inserts
##   between files already open; Bingham's note on Aelian 29.3, "must be done in open order";
##   Aelian 33, the files "moue on till the first distance recouered").

const SPAWN := Vector2(500, 300)
const SPEARMEN := 140
const DRILL_TICKS := 2400
const HALF_FILE := UnitFormation.ExplicatioDrill.HALF_FILE
const ALTERNATE_RANK := UnitFormation.ExplicatioDrill.ALTERNATE_RANK
const TOGETHER := ExplicatioOpening.Reading.TOGETHER
const FILES_FIRST := ExplicatioOpening.Reading.FILES_FIRST
const OUTWARD := UnitFormation.ExplicatioSide.OUTWARD
const LENGTHEN := UnitFormation.ExplicatioGround.LENGTHEN

var _battle: Node = null


func after_each() -> void:
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _stage() -> Unit:
	Replay.forced_seed = 1967
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y,
			"count": SPEARMEN, "facing": [0, 1]}]
	add_child(_battle)
	for _i in range(40):
		await get_tree().physics_frame
	for child in _battle._units.get_children():
		if child is Unit:
			return child
	return null


func _free_battle() -> void:
	_battle.free()
	_battle = null
	await get_tree().physics_frame


func _front(u: Unit, forward: Vector2) -> float:
	var best: float = -INF
	for p in u._sim_soldier_pos:
		best = maxf(best, p.dot(forward))
	return best


func _nearest_pair(points: PackedVector2Array) -> float:
	var best: float = INF
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			best = minf(best, points[i].distance_to(points[j]))
	return best


## Widen `u` by `drill` held on `anchor` with `opening`, and walk the drill: the farthest the
## front stood ahead of where it began ("ahead") and behind it ("behind"), the closest two men
## came ("closest"), the tick the drill ended ("ended", -1 if it did not), the most men held in
## their old files on any tick ("held"), and the farthest the leader of any file that stays, the
## front of an old file, stood ahead of where the front began ("leaders_ahead").
func _walk(u: Unit, drill: int, anchor: int, opening: int) -> Dictionary:
	var forward: Vector2 = u.facing
	var front0: float = _front(u, forward)
	_battle.enqueue_file_double([u.uid], 1, anchor, drill, OUTWARD, LENGTHEN,
			DuplicatioMarch.Reading.WALK, opening)
	var out := {"ahead": -INF, "behind": INF, "closest": INF, "ended": -1, "held": 0,
			"leaders_ahead": -INF}
	for t in range(DRILL_TICKS):
		await get_tree().physics_frame
		var front: float = _front(u, forward) - front0
		out["ahead"] = maxf(out["ahead"], front)
		out["behind"] = minf(out["behind"], front)
		for i in range(u.soldiers):
			if u.explicatio_drill_active() and u._sim_soldier_rank[i] == 0 \
					and UnitFormation.explicatio_file_stays(u._sim_soldier_file[i],
							u._explicatio_lane_split, u._explicatio_inward):
				out["leaders_ahead"] = maxf(out["leaders_ahead"],
						u._sim_soldier_pos[i].dot(forward) - front0)
		if t % 4 == 0:
			out["closest"] = minf(out["closest"], _nearest_pair(u._sim_soldier_pos))
		var held: int = 0
		for w in u._explicatio_waiting:
			held += w
		out["held"] = maxi(out["held"], held)
		if not u.explicatio_drill_active():
			out["ended"] = t
			break
	return out


# --- The man who stood ahead of him, and the hold ---------------------------------


## In the alternate-rank deal the man at rank 2m of the old file stays at rank m and the man at
## 2m + 1 goes to rank m of the interval, so the man ahead of a man who stayed is the interval man
## a rank up, and the man ahead of an interval man is the man of the file who stayed beside him.
## In the half-file deal the rear half follows the front half, the hemilochites the last man of it.
func test_old_ahead_reads_each_deal_back() -> void:
	var none := Vector2i(-1, -1)
	assert_eq(ExplicatioOpening.old_ahead(4, 0, true, 5, 8, ALTERNATE_RANK), none,
		"a file leader has nobody ahead")
	assert_eq(ExplicatioOpening.old_ahead(4, 2, true, 5, 8, ALTERNATE_RANK), Vector2i(5, 1),
		"old rank 4 stood behind old rank 3, the interval's rank 1")
	assert_eq(ExplicatioOpening.old_ahead(5, 1, false, 4, 8, ALTERNATE_RANK), Vector2i(4, 1),
		"old rank 3 stood behind old rank 2, the file's rank 1")
	assert_eq(ExplicatioOpening.old_ahead(4, 3, true, 5, 8, HALF_FILE), Vector2i(4, 2),
		"the front half keeps its order")
	assert_eq(ExplicatioOpening.old_ahead(5, 0, false, 4, 8, HALF_FILE), Vector2i(4, 7),
		"the hemilochites stood behind the last man of the front half")
	assert_eq(ExplicatioOpening.old_ahead(5, 3, false, 4, 8, HALF_FILE), Vector2i(5, 2),
		"the rear half keeps its order")


## While the leader of an old file is still following, every other man of it follows the man who
## stood ahead of him in it, a rank pitch behind, held from the drill; the leader keeps his own
## plan, and so does every man of a file whose leader has taken his place.
func test_the_men_of_a_file_not_yet_opened_keep_their_places_in_it() -> void:
	# Two old files of four, alternate rank, every interval on the right (lane split 0):
	# old file 0 is new files 0 (stays) and 1, old file 1 new files 2 and 3.
	var files := PackedInt32Array([0, 1, 0, 1, 2, 3, 2, 3])
	var ranks := PackedInt32Array([0, 0, 1, 1, 0, 0, 1, 1])
	var roles := PackedByteArray([0, 2, 0, 0, 0, 2, 0, 0])
	var plan: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, roles, 0, 0, 9.0,
			9.0)
	var drill_leaders: PackedInt32Array = (plan["leaders"] as PackedInt32Array).duplicate()
	var following := PackedByteArray([0, 1, 1, 1, 1, 1, 1, 1])   # old file 0 has opened
	var held: Dictionary = ExplicatioOpening.hold_unopened(plan, files, ranks, 0, false,
			ALTERNATE_RANK, following, 9.0)
	var leaders: PackedInt32Array = held["leaders"]
	assert_eq(held["waiting"], PackedByteArray([0, 0, 0, 0, 0, 1, 1, 1]),
		"the men behind the leader of the file not yet opened wait")
	assert_eq(leaders[4], drill_leaders[4], "that file's leader keeps his plan")
	assert_eq(leaders[5], 4, "the epistates stays behind his file leader")
	assert_eq(leaders[6], 5, "the next man behind the epistates")
	assert_eq(leaders[7], 6, "and the last behind him")
	assert_eq((held["offsets"] as PackedVector2Array)[5], Vector2(0.0, 9.0), "a rank behind")
	assert_eq((held["guides"] as PackedInt32Array)[5], SoldierFollow.NOT_FOLLOWING,
		"dressing on nobody's line")
	for i in range(4):
		assert_eq(leaders[i], drill_leaders[i], "man %d of the opened file has the drill's plan" % i)


## A man whose man ahead in the old file has fallen keeps the drill's plan rather than wait on a
## man who is not there; a plan whose flags do not line up holds nobody.
func test_a_man_with_nobody_ahead_left_is_not_held() -> void:
	var files := PackedInt32Array([0, 0, 1])
	var ranks := PackedInt32Array([0, 1, 1])   # the epistates of old file 0 has fallen
	var roles := PackedByteArray([0, 0, 0])
	var plan: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, roles, 0, 0, 9.0,
			9.0)
	var held: Dictionary = ExplicatioOpening.hold_unopened(plan.duplicate(true), files, ranks, 0,
			false, ALTERNATE_RANK, PackedByteArray([1, 1, 1]), 9.0)
	assert_eq(held["waiting"], PackedByteArray([0, 0, 1]),
		"the man behind the fallen epistates keeps the drill's plan; the interval man behind him waits")
	var unlined: Dictionary = ExplicatioOpening.hold_unopened(plan.duplicate(true), files, ranks,
			0, false, ALTERNATE_RANK, PackedByteArray([1]), 9.0)
	assert_eq(unlined["waiting"], PackedByteArray([0, 0, 0]), "flags that do not line up hold nobody")


# --- The reading rides the order, the replay, the snapshot and the demo ----------


func test_the_reading_rides_the_order_the_replay_and_the_demo() -> void:
	assert_eq(Order.new_file_double(1).explicatio_opening, TOGETHER, "together by default")
	var o: Order = Order.new_file_double(1, HALF_FILE, OUTWARD, LENGTHEN, FILES_FIRST)
	assert_eq(Order.from_dict(o.to_dict()).explicatio_opening, FILES_FIRST,
		"the order carries it through to_dict and back")
	assert_eq(Order.from_dict({"type": Order.Type.FRONTAGE}).explicatio_opening, TOGETHER,
		"an order saved before the reading is together")
	var entry: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18,
			INF, 0, 0.0, -1, 0, 0, -1, -1, 0, HALF_FILE, 0, 0, 0, 0, FILES_FIRST)
	assert_eq(entry["explicatio_opening"], FILES_FIRST, "the replay entry names it")
	var plain: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18,
			INF, 0, 0.0, -1, 0, 0, -1, -1, 0, HALF_FILE)
	assert_false(plain.has("explicatio_opening"), "and leaves the default out")
	assert_eq(DemoExplicatio.parse({"opening": "files_first"})["opening"], FILES_FIRST,
		"a demo names it")
	assert_eq(DemoExplicatio.parse({})["opening"], TOGETHER, "together by default")
	assert_true(DemoExplicatio.parse({"opening": "later"}).has("error"),
		"a reading that does not exist")
	assert_eq(ExplicatioChoice.summary(HALF_FILE, OUTWARD, LENGTHEN, FILES_FIRST),
		"half-file, outward, lengthen, files first", "the HUD words it")


func test_the_reading_rides_the_live_order_and_a_snapshot() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.CENTRE, ALTERNATE_RANK,
			OUTWARD, LENGTHEN, DuplicatioMarch.Reading.WALK, FILES_FIRST)
	var cmd: Dictionary = _battle._pending_orders.back()
	assert_eq(int(cmd["explicatio_opening"]), FILES_FIRST, "the recorded order names it")
	assert_eq(u._explicatio_opening, FILES_FIRST, "the drill under way reads it")
	var snap: Dictionary = u.to_snapshot_dict()
	u._explicatio_opening = TOGETHER
	u.apply_snapshot_dict(snap)
	assert_eq(u._explicatio_opening, FILES_FIRST, "a snapshot carries it")


# --- Live ---------------------------------------------------------------------------


## Together, the alternate-rank drill's file leaders run ahead of the line they stood on: each
## epistates steps out from right behind his file leader while the leader is still opening out, and
## comes up inside a body's width of his back, pressing him forward, 1.07 wu (an eighth of the 9 wu
## rank pitch) for 140 Spearmen 9 files by 16 centred and 1.24 wu held on the right, measured on
## this build. Files first, each file opens out with its men still in it and only then does its
## epistates step in beside the leader, so no file leader gets a fortieth of a rank pitch ahead.
## The column leaders still come up into line a little past it before they settle, as they do
## together, so the front as a whole runs no further ahead files first than a quarter of a rank
## pitch, the bound every other reading keeps (TODO(#1989): a man coming up into line with way on
## across his front still overshoots it). The men wait in their files on the way, and the drill
## ends with the files doubled and nobody closer than a body radius to another man.
func test_files_first_keeps_the_alternate_rank_file_leaders_on_their_line() -> void:
	for anchor in [UnitFormation.Anchor.CENTRE, UnitFormation.Anchor.RIGHT]:
		var u: Unit = await _stage()
		var together: Dictionary = await _walk(u, ALTERNATE_RANK, anchor, TOGETHER)
		assert_gt(together["leaders_ahead"], 0.1 * u.rank_pitch_wu(),
			"precondition, anchor %d: together a file leader went %.2f wu ahead"
			% [anchor, together["leaders_ahead"]])
		await _free_battle()
		u = await _stage()
		var walk: Dictionary = await _walk(u, ALTERNATE_RANK, anchor, FILES_FIRST)
		assert_gte(walk["ended"], 0, "anchor %d: the drill ended" % anchor)
		assert_eq(UnitFormation.frontage(u), 18, "the explicatio doubled 9 files to 18")
		assert_gt(walk["held"], 0, "anchor %d: men waited in their files" % anchor)
		assert_lt(walk["leaders_ahead"], 0.025 * u.rank_pitch_wu(),
			"anchor %d: a file leader went %.2f wu ahead" % [anchor, walk["leaders_ahead"]])
		assert_lt(walk["ahead"], 0.25 * u.rank_pitch_wu(),
			"anchor %d: the front went %.2f wu ahead" % [anchor, walk["ahead"]])
		assert_gt(walk["behind"], -0.25 * u.rank_pitch_wu(),
			"anchor %d: the front fell %.2f wu back" % [anchor, -walk["behind"]])
		assert_gte(walk["closest"], u.soldier_body_radius(),
			"anchor %d: the nearest two men came within %.2f wu" % [anchor, walk["closest"]])
		await _free_battle()


## Together, the default, nobody waits in his old file.
func test_together_holds_nobody_in_his_file() -> void:
	var u: Unit = await _stage()
	var walk: Dictionary = await _walk(u, ALTERNATE_RANK, UnitFormation.Anchor.CENTRE, TOGETHER)
	assert_gte(walk["ended"], 0, "the drill ended")
	assert_eq(walk["held"], 0, "nobody waited in his file")


## Files first, the half-file drill opens its files with their rear halves in them and still ends
## with the front on its line.
func test_files_first_half_file_ends_with_the_front_on_its_line() -> void:
	var u: Unit = await _stage()
	var walk: Dictionary = await _walk(u, HALF_FILE, UnitFormation.Anchor.CENTRE, FILES_FIRST)
	assert_gte(walk["ended"], 0, "the drill ended")
	assert_gt(walk["held"], 0, "men waited in their files")
	assert_lt(walk["ahead"], 0.25 * u.rank_pitch_wu(), "the front went %.2f wu ahead"
			% walk["ahead"])
	assert_gte(walk["closest"], u.soldier_body_radius(),
		"the nearest two men came within %.2f wu" % walk["closest"])
