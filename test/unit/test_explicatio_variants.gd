extends GutTest
## The readings of the explicatio where the sources differ or are silent, each its own named
## variant (UnitFormation.ExplicatioSide, UnitFormation.ExplicatioGround; the sources are quoted
## there and in docs/historical-reshaping-maneuvers.md, "The explicatio drills"):
## - OUTWARD (the default, Aelian 33's text) and INWARD (Bingham's note on it): which way each
##   wing's intervals open about the middle.
## - SPEAR_SIDE and SHIELD_SIDE: every interval on the right of its file, or on the left, where
##   Polyaenus 2.10.4 and Xenophon, Cyropaedia 2.3.21, do not say.
## - LENGTHEN (the default; Asclepiodotus 10.18, Polyaenus) and SAME_GROUND (Asclepiodotus 10.17,
##   Aelian 29.3): whether the doubled line keeps its file pitch or its ground.
## Each variant, live, keeps the front on its line, lets nobody pass the man ahead of him, and
## keeps the nearest two men as far apart as the default drill does.

const SPAWN := Vector2(500, 300)
const SPEARMEN := 140
const DRILL_TICKS := 1600
const HALF_FILE := UnitFormation.ExplicatioDrill.HALF_FILE
const ALTERNATE_RANK := UnitFormation.ExplicatioDrill.ALTERNATE_RANK
const OUTWARD := UnitFormation.ExplicatioSide.OUTWARD
const INWARD := UnitFormation.ExplicatioSide.INWARD
const SPEAR_SIDE := UnitFormation.ExplicatioSide.SPEAR_SIDE
const SHIELD_SIDE := UnitFormation.ExplicatioSide.SHIELD_SIDE
const LENGTHEN := UnitFormation.ExplicatioGround.LENGTHEN
const SAME_GROUND := UnitFormation.ExplicatioGround.SAME_GROUND
const CENTRE := UnitFormation.Anchor.CENTRE

var _battle: Node = null


func after_each() -> void:
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _stage(count: int = SPEARMEN) -> Unit:
	Replay.forced_seed = 1971
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y,
			"count": count, "facing": [0, 1]}]
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


func _right(u: Unit) -> Vector2:
	return SoldierFollow.right_of(u.facing.normalized())


func _extent(u: Unit, axis: Vector2) -> Vector2:
	var lo: float = INF
	var hi: float = -INF
	for p in u._sim_soldier_pos:
		lo = minf(lo, p.dot(axis))
		hi = maxf(hi, p.dot(axis))
	return Vector2(lo, hi)


## Walk the drill under way for up to `ticks` ticks: the farthest the front went ahead of the line
## it stood on and behind it ("ahead", "behind"), the farthest any man of the front rank ended off
## it ("end_line"), the closest two men came ("closest"), the farthest any man got ahead of the
## man ahead of him in his file along the facing ("overtake"), and the tick it ended ("ended", -1
## if it did not).
func _walk(u: Unit, ticks: int) -> Dictionary:
	var forward: Vector2 = u.facing.normalized()
	var front0: float = -INF
	for p in u._sim_soldier_pos:
		front0 = maxf(front0, p.dot(forward))
	var out := {"ahead": -INF, "behind": INF, "end_line": INF, "closest": INF,
			"overtake": -INF, "ended": -1}
	for t in range(ticks):
		await get_tree().physics_frame
		var front: float = -INF
		for p in u._sim_soldier_pos:
			front = maxf(front, p.dot(forward))
		out["ahead"] = maxf(out["ahead"], front - front0)
		out["behind"] = minf(out["behind"], front - front0)
		for i in range(u.soldiers):
			for j in range(i + 1, u.soldiers):
				out["closest"] = minf(out["closest"],
						u._sim_soldier_pos[i].distance_to(u._sim_soldier_pos[j]))
		var at: Dictionary = {}
		for i in range(u.soldiers):
			at[Vector2i(u._sim_soldier_file[i], u._sim_soldier_rank[i])] = i
		for i in range(u.soldiers):
			var j: int = int(at.get(Vector2i(u._sim_soldier_file[i], u._sim_soldier_rank[i] - 1), -1))
			if j >= 0:
				out["overtake"] = maxf(out["overtake"],
						(u._sim_soldier_pos[i] - u._sim_soldier_pos[j]).dot(forward))
		if not u.explicatio_drill_active():
			out["ended"] = t
			var end_line: float = 0.0
			for i in range(u.soldiers):
				if u._sim_soldier_rank[i] == 0:
					end_line = maxf(end_line, absf(u._sim_soldier_pos[i].dot(forward) - front0))
			out["end_line"] = end_line
			break
	return out


## The checks every variant meets, live: the drill ends with the files doubled, the front stays
## on its line within a quarter of a rank pitch, nobody gets a quarter of a rank pitch ahead of
## the man ahead of him, and the nearest two men stay `floor_wu` apart.
func _assert_drill(u: Unit, walk: Dictionary, files: int, floor_wu: float, what: String) -> void:
	var quarter: float = 0.25 * u.rank_pitch_wu()
	assert_gte(walk["ended"], 0, "%s: the drill ended" % what)
	assert_eq(UnitFormation.frontage(u), files, "%s: the files doubled" % what)
	assert_lt(walk["ahead"], quarter, "%s: the front went %.2f wu ahead" % [what, walk["ahead"]])
	assert_gt(walk["behind"], -quarter, "%s: the front fell %.2f wu back" % [what, -walk["behind"]])
	assert_lt(walk["end_line"], quarter,
		"%s: a man of the front rank ended %.2f wu off its line" % [what, walk["end_line"]])
	assert_lt(walk["overtake"], quarter,
		"%s: a man got %.2f wu ahead of the man ahead of him" % [what, walk["overtake"]])
	assert_gte(walk["closest"], floor_wu,
		"%s: the nearest two men came within %.2f wu" % [what, walk["closest"]])


## The nearest two men may come in the default half-file drill: a body radius is what it does not
## yet keep everywhere (TODO(#1974)), so the variants of the half-file drill are held to the bound
## the default is, and those of the alternate-rank drill to a body radius, as the default is.
func _floor(u: Unit, drill: int) -> float:
	if drill == ALTERNATE_RANK:
		return u.soldier_body_radius()
	return 2.0 * u.soldier_body_radius() * DemoDefects.OVERLAP_BODY_FRAC


# --- The pure primitives ---------------------------------------------------------


func test_the_side_reads_the_lane_split() -> void:
	for held in [-1, 0, 1]:
		assert_eq(UnitFormation.explicatio_lane_split(9, held, SPEAR_SIDE), 0,
			"held %d: every interval opens on the spear side, the right" % held)
		assert_eq(UnitFormation.explicatio_lane_split(9, held, SHIELD_SIDE), 9,
			"held %d: every interval opens on the shield side, the left" % held)
		assert_eq(UnitFormation.explicatio_lane_split(9, held, INWARD),
			UnitFormation.explicatio_lane_split(9, held, OUTWARD),
			"held %d: inward splits the wings where outward does" % held)
	assert_eq(UnitFormation.explicatio_lane_split(9, 0), 4, "outward by default")


func test_only_a_centred_widen_opens_inward() -> void:
	assert_true(UnitFormation.explicatio_inward(0, INWARD), "about the middle")
	assert_false(UnitFormation.explicatio_inward(1, INWARD), "held on the right: no inward reading")
	assert_false(UnitFormation.explicatio_inward(-1, INWARD), "held on the left: none either")
	for side in [OUTWARD, SPEAR_SIDE, SHIELD_SIDE]:
		assert_false(UnitFormation.explicatio_inward(0, side), "side %d is not inward" % side)


func test_inward_reverses_each_wing() -> void:
	# Split at 2 of 4 old files: outward, 0 and 1 open left and 2 and 3 right; inward the reverse.
	for k in range(4):
		assert_eq(UnitFormation.explicatio_opens_right(k, 2), k >= 2, "outward, old file %d" % k)
		assert_eq(UnitFormation.explicatio_opens_right(k, 2, true), k < 2, "inward, old file %d" % k)
	# Inward: old files 0, 1 stay in 0, 2 with intervals 1, 3; old files 2, 3 stay in 5, 7.
	for f in [0, 2, 5, 7]:
		assert_true(UnitFormation.explicatio_file_stays(f, 2, true), "file %d stays" % f)
	for f in [1, 3, 4, 6]:
		assert_false(UnitFormation.explicatio_file_stays(f, 2, true), "file %d is an interval" % f)


## Four files of four, dealt half-file inward about the middle: each left-wing file's rear half
## takes the interval on its right, each right-wing file's the interval on its left.
func test_the_inward_deal_sends_each_wings_rear_halves_toward_the_middle() -> void:
	var files := PackedInt32Array()
	var ranks := PackedInt32Array()
	for k in range(4):
		for r in range(4):
			files.push_back(k)
			ranks.push_back(r)
	var d: Dictionary = UnitFormation.explicatio_assignment(files, ranks, 4, 2, HALF_FILE, true)
	var out_files: PackedInt32Array = d["files"]
	for i in range(16):
		var k: int = files[i]
		var rear: bool = ranks[i] >= 2
		var want: int = 2 * k + (1 if (k < 2) == rear else 0)
		assert_eq(out_files[i], want, "old file %d rank %d" % [k, ranks[i]])
	var outward: Dictionary = UnitFormation.explicatio_assignment(files, ranks, 4, 2, HALF_FILE)
	assert_eq(outward["files"][3], 0, "outward, old file 0's rear half takes the interval on its left")


## The leader of an interval that opens on the right of its file comes up beside the file on his
## left, and the other way about; inward, each wing's column comes up on the middle side.
func test_the_inward_follow_plan_brings_each_column_up_on_the_middle_side() -> void:
	var files := PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7])
	var ranks := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var hl: int = UnitFormation.SoldierRole.HEMILOCHITES
	var roles := PackedByteArray([0, hl, 0, hl, hl, 0, hl, 0])
	# Stand file 5, the right-hand middle file's front, which opens on its left inward.
	var p: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, roles, 2, 5, 9.0, 8.0,
			true)
	var leaders: PackedInt32Array = p["leaders"]
	var offsets: PackedVector2Array = p["offsets"]
	assert_eq(leaders[5], SoldierFollow.STAND, "file 5 stands")
	assert_eq(leaders[1], 0, "interval 1 comes up on file 0's right")
	assert_eq(offsets[1], Vector2(9, 0))
	assert_eq(leaders[4], 5, "interval 4 comes up on file 5's left")
	assert_eq(offsets[4], Vector2(-9, 0))
	assert_eq(leaders[2], 5, "file 2 dresses on the standing file across both middle intervals")
	assert_eq(offsets[2], Vector2(-27, 0), "three file pitches to his left")
	assert_eq(leaders[7], 5, "file 7 dresses on file 5")
	assert_eq(offsets[7], Vector2(18, 0))


func test_the_denser_order_is_one_step_closer() -> void:
	assert_eq(Unit.denser_formation_mode(Unit.FORMATION_LOOSE), Unit.FORMATION_NORMAL)
	assert_eq(Unit.denser_formation_mode(Unit.FORMATION_NORMAL), Unit.FORMATION_TIGHT)
	for mode in [Unit.FORMATION_TIGHT, Unit.FORMATION_SHIELD_WALL, Unit.FORMATION_TESTUDO,
			Unit.FORMATION_SQUARE, Unit.FORMATION_SCHILTRON]:
		assert_eq(Unit.denser_formation_mode(mode), -1, "mode %d has no closer order" % mode)
	for mode in [Unit.FORMATION_LOOSE, Unit.FORMATION_NORMAL]:
		assert_almost_eq(Unit.spacing_scale_for_mode(Unit.denser_formation_mode(mode)),
				0.5 * Unit.spacing_scale_for_mode(mode), 0.0001, "mode %d halves its pitch" % mode)


## The readings ride the B order, the replay entry and a combo step; the defaults are left out of
## the replay, so a replay of the default drill is byte-identical, and an order or a replay saved
## before the readings plays back as the outward, lengthening drill.
func test_the_readings_ride_the_order_and_the_replay() -> void:
	var entry: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18,
			INF, 0, 0.0, -1, 0, 0, -1, -1, 0, HALF_FILE, 0, SHIELD_SIDE, SAME_GROUND)
	assert_eq(entry["explicatio_side"], SHIELD_SIDE, "the replay entry names the side")
	assert_eq(entry["explicatio_ground"], SAME_GROUND, "and the ground")
	var plain: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18,
			INF, 0, 0.0, -1, 0, 0, -1, -1, 0, HALF_FILE)
	assert_false(plain.has("explicatio_side"), "the outward side is left out")
	assert_false(plain.has("explicatio_ground"), "and the lengthening ground")
	var Decoder := preload("res://scripts/ReplayDecoder.gd")
	var back: Dictionary = Decoder._decode_order({"units": [1], "explicatio_side": INWARD,
			"explicatio_ground": SAME_GROUND})
	assert_eq(back["explicatio_side"], INWARD, "playback reads the side back")
	assert_eq(back["explicatio_ground"], SAME_GROUND, "and the ground")
	assert_false(Decoder._decode_order({"units": [1]}).has("explicatio_side"),
		"a replay from before the readings plays back none")
	var step := Order.new_file_double(1, ALTERNATE_RANK, SPEAR_SIDE, SAME_GROUND)
	var round_trip := Order.from_dict(step.to_dict())
	assert_eq(round_trip.explicatio_side, SPEAR_SIDE, "a combo step keeps its side")
	assert_eq(round_trip.explicatio_ground, SAME_GROUND, "and its ground")
	var old: Dictionary = step.to_dict()
	old.erase("explicatio_side")
	old.erase("explicatio_ground")
	assert_eq(Order.from_dict(old).explicatio_side, OUTWARD, "an old order opens outward")
	assert_eq(Order.from_dict(old).explicatio_ground, LENGTHEN, "and lengthens")
	assert_eq(Order.new_file_double(1).explicatio_side, OUTWARD, "outward by default")
	assert_eq(Order.new_file_double(1).explicatio_ground, LENGTHEN, "lengthening by default")


func test_a_demo_names_the_readings() -> void:
	var d: Dictionary = DemoExplicatio.parse({"drill": "alternate_rank", "side": "shield_side",
			"ground": "same_ground"})
	assert_eq(d["drill"], ALTERNATE_RANK)
	assert_eq(d["side"], SHIELD_SIDE)
	assert_eq(d["ground"], SAME_GROUND)
	var defaults: Dictionary = DemoExplicatio.parse({})
	assert_eq(defaults["drill"], HALF_FILE, "the half-file drill by default")
	assert_eq(defaults["side"], OUTWARD, "outward by default")
	assert_eq(defaults["ground"], LENGTHEN, "lengthening by default")
	assert_eq(DemoExplicatio.parse({"side": "inward"})["side"], INWARD)
	assert_eq(DemoExplicatio.parse({"side": "spear_side"})["side"], SPEAR_SIDE)
	assert_eq(DemoExplicatio.parse({"drill": "half_file", "ground": "lengthen"})["ground"],
		LENGTHEN)
	assert_true(DemoExplicatio.parse([]).has("error"), "a block that is not an object")
	assert_true(DemoExplicatio.parse({"wing": "inward"}).has("error"), "a field that does not exist")
	assert_true(DemoExplicatio.parse({"side": "sideways"}).has("error"), "a side that does not exist")


# --- Which side the intervals open on, live ---------------------------------------


## Each side, each drill, live about the middle: every man of an interval ends on the side of the
## file he opened from that his side names, and the flanks step out as many file pitches as the
## new files that open beyond them. Of 9 old files the standing file is old file 4: outward the
## left flank steps out 4 and the right 5; inward the left 5 and the right 4; on the spear side
## the left 4 and the right 5 (old file 8's interval opening beyond it); on the shield side the
## left 5 and the right 4.
func test_each_side_opens_where_it_says_and_keeps_the_drill() -> void:
	var steps := {OUTWARD: Vector2(4, 5), INWARD: Vector2(5, 4), SPEAR_SIDE: Vector2(4, 5),
			SHIELD_SIDE: Vector2(5, 4)}
	for drill in [HALF_FILE, ALTERNATE_RANK]:
		for side in [INWARD, SPEAR_SIDE, SHIELD_SIDE]:
			var what: String = "drill %d side %d" % [drill, side]
			var u: Unit = await _stage()
			var right: Vector2 = _right(u)
			var before: Vector2 = _extent(u, right)
			_battle.enqueue_file_double([u.uid], 1, CENTRE, drill, side)
			assert_true(u.explicatio_drill_active(), "%s: the widen is the drill" % what)
			assert_eq(u._explicatio_inward, side == INWARD, "%s: inward only when named" % what)
			var walk: Dictionary = await _walk(u, DRILL_TICKS)
			_assert_drill(u, walk, 18, _floor(u, drill), what)
			var after: Vector2 = _extent(u, right)
			var pitch: float = u.file_pitch_wu()
			var want: Vector2 = steps[side]
			assert_almost_eq(before.x - after.x, want.x * pitch, 0.25 * pitch,
				"%s: the left flank stepped out %.2f wu" % [what, before.x - after.x])
			assert_almost_eq(after.y - before.y, want.y * pitch, 0.25 * pitch,
				"%s: the right flank stepped out %.2f wu" % [what, after.y - before.y])
			await _free_battle()


## Where each interval's men stand beside the file they opened from, read off the deal before the
## men move: the side named, every man of the interval.
func test_each_side_deals_its_intervals_on_that_side() -> void:
	for side in [INWARD, SPEAR_SIDE, SHIELD_SIDE]:
		var u: Unit = await _stage()
		_battle.enqueue_file_double([u.uid], 1, CENTRE, ALTERNATE_RANK, side)
		var mid: int = u._explicatio_stand_file
		var right_of: int = 0
		var left_of: int = 0
		for i in range(u.soldiers):
			var f: int = u._sim_soldier_file[i]
			if UnitFormation.explicatio_file_stays(f, u._explicatio_lane_split, u._explicatio_inward):
				continue
			var on_right: bool = f % 2 == 1   # the interval of old file f / 2 that opens right
			if on_right:
				right_of += 1
			else:
				left_of += 1
			if side == INWARD:
				assert_eq(on_right, f < mid, "inward, interval %d opens toward the middle" % f)
		if side == SPEAR_SIDE:
			assert_eq(left_of, 0, "spear side: no interval on the left")
		if side == SHIELD_SIDE:
			assert_eq(right_of, 0, "shield side: no interval on the right")
		assert_eq(right_of + left_of, 70, "side %d: 70 epistates change file" % side)
		await _free_battle()


## The B key deals the readings SelectionManager holds, and the order it records carries them.
func test_the_b_key_deals_the_selection_managers_readings() -> void:
	var u: Unit = await _stage()
	var sm: Node = _battle.get_node("SelectionManager")
	assert_eq(sm.explicatio_drill, HALF_FILE, "the half-file drill by default")
	assert_eq(sm.explicatio_side, OUTWARD, "outward by default")
	assert_eq(sm.explicatio_ground, LENGTHEN, "lengthening by default")
	sm._select(u)
	sm.explicatio_drill = ALTERNATE_RANK
	sm.explicatio_side = SPEAR_SIDE
	sm.explicatio_ground = SAME_GROUND
	sm._issue_file_double(1)
	assert_true(u.explicatio_drill_active(), "the B key's widen is the drill")
	assert_eq(u._explicatio_drill, ALTERNATE_RANK, "the drill named")
	assert_eq(u._explicatio_lane_split, 0, "every interval on the spear side")
	assert_eq(u.formation_mode, Unit.FORMATION_TIGHT, "on the same ground")
	var cmd: Dictionary = _battle._pending_orders.back()
	assert_eq(cmd["explicatio_side"], SPEAR_SIDE, "the order carries the side")
	assert_eq(cmd["explicatio_ground"], SAME_GROUND, "and the ground")


## Held on a flank there is no inward reading: an inward widen held on the right is the outward
## one, the corner file standing and every interval opening on the left.
func test_an_inward_widen_held_on_a_flank_is_the_outward_one() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.RIGHT, HALF_FILE, INWARD)
	assert_false(u._explicatio_inward, "no inward reading held on a flank")
	assert_eq(u._explicatio_lane_split, 9, "every interval on the left")
	assert_eq(u._explicatio_stand_file, 17, "the right corner file stands")


# --- Length or density, live ------------------------------------------------------


## On the same ground the line keeps its length: the files double at half the pitch, the block
## closing one order (compact into locked shields, open into compact), the file leaders who stay
## keep their ground across the front, and the flanks stand where they stood but for the one file
## that opens beyond the right flank's last file, half an old pitch.
func test_the_same_ground_keeps_the_length_and_closes_the_order() -> void:
	for start in [Unit.FORMATION_NORMAL, Unit.FORMATION_LOOSE]:
		for drill in [HALF_FILE, ALTERNATE_RANK]:
			var what: String = "mode %d drill %d" % [start, drill]
			var u: Unit = await _stage()
			u.set_formation(start)
			for _i in range(DRILL_TICKS):
				await get_tree().physics_frame
			var old_pitch: float = u.file_pitch_wu()
			var right: Vector2 = _right(u)
			var before: Vector2 = _extent(u, right)
			var leaders_before: Dictionary = {}
			for i in range(u.soldiers):
				if u._sim_soldier_rank.size() == u.soldiers and u._sim_soldier_rank[i] == 0:
					leaders_before[i] = u._sim_soldier_pos[i].dot(right)
			_battle.enqueue_file_double([u.uid], 1, CENTRE, drill, OUTWARD, SAME_GROUND)
			assert_true(u.explicatio_drill_active(), "%s: the widen is the drill" % what)
			assert_eq(u.formation_mode, Unit.denser_formation_mode(start),
				"%s: the block closes one order" % what)
			assert_almost_eq(u.file_pitch_wu(), 0.5 * old_pitch, 0.001,
				"%s: at half the file pitch" % what)
			var walk: Dictionary = await _walk(u, DRILL_TICKS)
			_assert_drill(u, walk, 18, _floor(u, drill), what)
			var after: Vector2 = _extent(u, right)
			assert_almost_eq(after.x, before.x, 0.25 * u.file_pitch_wu(),
				"%s: the left flank stands where it stood" % what)
			assert_almost_eq(after.y - before.y, 0.5 * old_pitch, 0.25 * u.file_pitch_wu(),
				"%s: the right flank gains half an old pitch" % what)
			var drift: float = 0.0
			for i in leaders_before:
				if UnitFormation.explicatio_file_stays(u._sim_soldier_file[i], 4) \
						and u._sim_soldier_rank[i] == 0:
					drift = maxf(drift, absf(u._sim_soldier_pos[i].dot(right) - leaders_before[i]))
			assert_lt(drift, 0.25 * u.file_pitch_wu(),
				"%s: a file leader who stays moved %.2f wu across the front" % [what, drift])
			await _free_battle()


## A block at locked shields has no closer order: the B order on the same ground is not issued
## to it, and a widen on the same ground handed to it directly is refused, said out loud, its
## width and order left as they were.
func test_a_block_at_locked_shields_cannot_keep_its_ground() -> void:
	var u: Unit = await _stage()
	u.set_formation(Unit.FORMATION_TIGHT)
	var files: int = UnitFormation.frontage(u)
	_battle.enqueue_file_double([u.uid], 1, CENTRE, HALF_FILE, OUTWARD, SAME_GROUND)
	assert_eq(UnitFormation.frontage(u), files, "the order is not issued")
	assert_false(u.explicatio_drill_active(), "no drill")
	u.set_frontage(2 * files, 0.0, HALF_FILE, CENTRE, OUTWARD, SAME_GROUND)
	assert_push_error("needs a closer order", "the refusal is reported")
	assert_eq(UnitFormation.frontage(u), files, "the width stays")
	assert_eq(u.formation_mode, Unit.FORMATION_TIGHT, "the order stays")
	_battle.enqueue_file_double([u.uid], -1, CENTRE, HALF_FILE, OUTWARD, SAME_GROUND)
	assert_lt(UnitFormation.frontage(u), files, "a narrow ignores the ground and is issued")


## A plain widen that is not a drill keeps its ground by the order it names too, a block on the
## march included; the replay carries it, so playback deals the same.
func test_the_ground_rides_a_widen_that_is_not_the_drill() -> void:
	var u: Unit = await _stage()
	var files: int = UnitFormation.frontage(u)
	u.set_frontage(2 * files, 0.0, UnitFormation.ExplicatioDrill.NONE, CENTRE, OUTWARD,
			SAME_GROUND)
	assert_eq(u.formation_mode, Unit.FORMATION_NORMAL, "no drill named: the order stays")
	u.set_frontage(files, 0.0)
	u._sim_soldier_pos = PackedVector2Array()   # nothing to deal a drill from
	u.set_frontage(2 * files, 0.0, HALF_FILE, CENTRE, OUTWARD, SAME_GROUND)
	assert_false(u.explicatio_drill_active(), "no men to do the drill")
	assert_eq(u.formation_mode, Unit.FORMATION_TIGHT, "the lateral deal still keeps its ground")
