extends GutTest
## The explicatio as the drill manuals describe it: the front stays where it stands, and the men
## who change file step sideways into the interval beside their own file and come up it in
## column, the man who leads the column first and nobody passing the man ahead of him. Nobody
## walks to a slot laid out from the unit's position: each man follows a man he can see
## (SoldierFollow, UnitFormation.explicatio_follow_plan) until he has taken his place, and the
## block's position is read off its men. Two drills choose who changes file
## (UnitFormation.ExplicatioDrill):
## - HALF_FILE, the default: each file's rear half, led by its half-file leader, the hemilochites
##   (Asclepiodotus, Tactics 2.2; Bingham's note on Aelian 29.3).
## - ALTERNATE_RANK: every second man, led by the epistates behind the file leader (Polyaenus,
##   Stratagems 2.10.4; Bingham's note on Aelian 29.3).
## Which files stand is Aelian's (ch. 33): the corner file of a held flank, or the files next to
## the middle, each wing opening outward.
##
## The live tests stage a lone block of Spearmen in drill mode and widen it through the order
## the B key issues (Battle.enqueue_file_double).

const SPAWN := Vector2(500, 300)
const SPEARMEN := 140
## Ticks for the drill to play out: the half-file drill measured on this build ends by tick 620
## centred and tick 737 held on a flank, the alternate-rank drill by ticks 389 and 476.
const DRILL_TICKS := 800
const HALF_FILE := UnitFormation.ExplicatioDrill.HALF_FILE
const ALTERNATE_RANK := UnitFormation.ExplicatioDrill.ALTERNATE_RANK

var _battle: Node = null


func after_each() -> void:
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _stage(units: Array) -> Array:
	Replay.forced_seed = 1948
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = units
	add_child(_battle)
	for _i in range(40):
		await get_tree().physics_frame
	var out: Array = []
	for child in _battle._units.get_children():
		if child is Unit:
			out.append(child)
	return out


func _spearmen(facing: Array = [0, 1], at: Vector2 = SPAWN, count: int = SPEARMEN) -> Dictionary:
	return {"team": 0, "type": "Spearmen", "x": at.x, "y": at.y, "count": count,
			"facing": facing}


func _run(ticks: int) -> void:
	for _i in range(ticks):
		await get_tree().physics_frame


func _free_battle() -> void:
	_battle.free()
	_battle = null
	await get_tree().physics_frame


## How far ahead along `forward` the block's front-most body stands.
func _front(u: Unit, forward: Vector2) -> float:
	var best: float = -INF
	for p in u._sim_soldier_pos:
		best = maxf(best, p.dot(forward))
	return best


## The block's bodies' extent along `axis`: [least, greatest].
func _extent(u: Unit, axis: Vector2) -> Vector2:
	var lo: float = INF
	var hi: float = -INF
	for p in u._sim_soldier_pos:
		lo = minf(lo, p.dot(axis))
		hi = maxf(hi, p.dot(axis))
	return Vector2(lo, hi)


func _nearest_pair(points: PackedVector2Array) -> float:
	var best: float = INF
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			best = minf(best, points[i].distance_to(points[j]))
	return best


## Man `i`'s role (UnitFormation.SoldierRole), NONE when the roles do not line up with the men.
func _role(u: Unit, i: int) -> int:
	if i < 0 or i >= u._sim_soldier_role.size() or u._sim_soldier_role.size() != u.soldiers:
		return UnitFormation.SoldierRole.NONE
	return u._sim_soldier_role[i]


func _count_role(u: Unit, role: int) -> int:
	var n: int = 0
	for i in range(u.soldiers):
		if _role(u, i) == role:
			n += 1
	return n


## For each man of `u`, the index of the man directly ahead of him in his own file (rank one
## less), or -1 for the head of a file.
func _man_ahead(u: Unit) -> PackedInt32Array:
	var at: Dictionary = {}
	for i in range(u.soldiers):
		at[Vector2i(u._sim_soldier_file[i], u._sim_soldier_rank[i])] = i
	var out := PackedInt32Array()
	out.resize(u.soldiers)
	for i in range(u.soldiers):
		out[i] = int(at.get(Vector2i(u._sim_soldier_file[i], u._sim_soldier_rank[i] - 1), -1))
	return out


## Whether man `i` of `u` stands in a file that stays (the front of an old file) in the
## explicatio under way, rather than in an interval.
func _stays(u: Unit, i: int) -> bool:
	return UnitFormation.explicatio_file_stays(u._sim_soldier_file[i], u._explicatio_lane_split)


## The file a man of an interval opened from: the file that stays beside his.
func _partner_file(u: Unit, f: int) -> int:
	return f + 1 if f / 2 < u._explicatio_lane_split else f - 1


## This tick's places of the explicatio under way.
func _places(u: Unit) -> PackedVector2Array:
	u._refresh_explicatio_follow(u.soldiers)
	return u._explicatio_places


## The farthest any man of `u` stands from his slot.
func _worst_off_slot(u: Unit) -> float:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var worst: float = 0.0
	for i in range(u.soldiers):
		worst = maxf(worst, slots[i].distance_to(u._sim_soldier_pos[i]))
	return worst


## Walk the drill for up to `ticks` ticks and measure it: the farthest the front stood ahead of
## and behind where it began ("ahead", "behind"); the farthest any leader of a file that stays
## stood off the line the front stood on, either way, while the drill ran ("line"), and the
## farthest any man of the front rank stood off it when the drill ended ("end_line"); the closest
## two men came ("closest"); the farthest any man stood ahead of the man ahead of him in his file
## along the facing ("overtake", negative when every man stayed behind); and the tick it ended
## ("ended", -1 if it did not). `kill_tick` >= 0 kills man `kill_index` on that tick through
## SoldierMelee.reap.
func _walk(u: Unit, ticks: int, kill_tick: int = -1, kill_index: int = -1) -> Dictionary:
	var forward: Vector2 = u.facing
	var front0: float = _front(u, forward)
	var out := {"ahead": -INF, "behind": INF, "line": 0.0, "end_line": INF, "closest": INF,
			"overtake": -INF, "ended": -1}
	for t in range(ticks):
		if t == kill_tick:
			u._sim_soldier_hp[kill_index] = 0.0
			SoldierMelee.reap(u, null)
		await get_tree().physics_frame
		var front: float = _front(u, forward) - front0
		out["ahead"] = maxf(out["ahead"], front)
		out["behind"] = minf(out["behind"], front)
		out["closest"] = minf(out["closest"], _nearest_pair(u._sim_soldier_pos))
		var end_line: float = 0.0
		for i in range(u.soldiers):
			if u._sim_soldier_rank[i] != 0:
				continue
			var off: float = absf(u._sim_soldier_pos[i].dot(forward) - front0)
			end_line = maxf(end_line, off)
			if u.explicatio_drill_active() and _stays(u, i):
				out["line"] = maxf(out["line"], off)
		if not u.explicatio_drill_active():
			out["ended"] = t
			out["end_line"] = end_line
			break
		var ahead_of: PackedInt32Array = _man_ahead(u)
		for i in range(u.soldiers):
			var j: int = ahead_of[i]
			if j >= 0:
				out["overtake"] = maxf(out["overtake"],
						(u._sim_soldier_pos[i] - u._sim_soldier_pos[j]).dot(forward))
	return out


# --- The half-file drill, live ---------------------------------------------------


## The front rank stays on the line it stood on, and the block stands doubled. On main the
## shallower block re-centred on the old centre and the front walked back half the depth the
## block lost: four rank pitches (36 wu) for 140 Spearmen going from 16 ranks to 8. The bound is
## a quarter of a rank pitch.
func test_the_front_rank_holds_its_ground() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	assert_true(u.explicatio_drill_active(), "precondition: the B key's widen is the drill")
	var walk: Dictionary = await _walk(u, DRILL_TICKS)
	assert_eq(UnitFormation.frontage(u), 18, "the explicatio doubled 9 files to 18")
	assert_gte(walk["ended"], 0, "the drill ended")
	assert_lt(walk["ahead"], 0.25 * u.rank_pitch_wu(),
		"the front went %.2f wu ahead of where it stood" % walk["ahead"])
	assert_gt(walk["behind"], -0.25 * u.rank_pitch_wu(),
		"the front fell %.2f wu back from where it stood" % -walk["behind"])
	assert_lt(walk["line"], 0.25 * u.rank_pitch_wu(),
		"a file leader stood %.2f wu off the front's line while it opened" % walk["line"])
	assert_lt(walk["end_line"], 0.25 * u.rank_pitch_wu(),
		"a man of the front rank ended %.2f wu off the line the front stood on" % walk["end_line"])


## When the drill ends the slot grid is laid on the men where they stand: every man is within the
## drill's settle distance (REFORM_SETTLE_EPS) of his slot, and the unit's position is the grid's
## reading of its men.
func test_the_grid_is_laid_on_the_men_where_they_stand() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	var walk: Dictionary = await _walk(u, DRILL_TICKS)
	assert_gte(walk["ended"], 0, "precondition: the drill ended")
	var worst: float = _worst_off_slot(u)
	assert_lt(worst, Unit.REFORM_SETTLE_EPS, "the farthest man stands %.2f wu off his slot" % worst)
	assert_almost_eq(u.position.x, u.explicatio_grid_position().x, 0.01, "position is the men's")
	assert_almost_eq(u.position.y, u.explicatio_grid_position().y, 0.01, "position is the men's")


## While the drill is under way the block's position is read off its men each tick
## (explicatio_grid_position), never laid down for them to follow.
func test_the_position_is_read_off_the_men_during_the_drill() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	var worst: float = 0.0
	for _t in range(120):
		await get_tree().physics_frame
		worst = maxf(worst, u.position.distance_to(u.explicatio_grid_position()))
	assert_true(u.explicatio_drill_active(), "precondition: still under way")
	assert_lt(worst, 0.01, "position strayed %.3f wu from the men's reading" % worst)


## No man of a file that stays ever steps back: he only moves sideways as the line opens. The
## bound is a quarter of a rank pitch of body jitter.
func test_no_man_of_a_front_half_steps_back() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var forward: Vector2 = u.facing
	var start: PackedVector2Array = u._sim_soldier_pos.duplicate()
	_battle.enqueue_file_double([u.uid], 1)
	var front_half: Array = []
	for i in range(u.soldiers):
		if _stays(u, i):
			front_half.append(i)
	assert_eq(front_half.size(), 72, "precondition: 72 of 140 men keep the front halves")
	var worst: float = 0.0
	for _t in range(DRILL_TICKS):
		await get_tree().physics_frame
		for i in front_half:
			worst = maxf(worst, (start[i] - u._sim_soldier_pos[i]).dot(forward))
	assert_lt(worst, 0.25 * u.rank_pitch_wu(),
		"the farthest any front-half man stepped back is %.2f wu" % worst)


## Each rear man steps out of his file before he comes up: on every tick he stands a full file
## pitch or more off his place's line across the front, he gains no ground along it. Summed over
## those ticks, the most any rear man gained is held to a quarter of a rank pitch of jitter.
func test_the_rear_men_step_out_of_the_file_before_coming_up() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var forward: Vector2 = u.facing
	var right := Vector2(-forward.y, forward.x)
	_battle.enqueue_file_double([u.uid], 1)
	var rear: Array = []
	for i in range(u.soldiers):
		if not _stays(u, i):
			rear.append(i)
	assert_eq(rear.size(), 68, "precondition: 68 rear men step into the intervals")
	var gained: Dictionary = {}
	var off_line_ticks: int = 0
	for _t in range(DRILL_TICKS):
		if not u.explicatio_drill_active():
			break
		var before: PackedVector2Array = u._sim_soldier_pos.duplicate()
		var places: PackedVector2Array = _places(u).duplicate()
		await get_tree().physics_frame
		for i in rear:
			if absf((places[i] - before[i]).dot(right)) >= u.file_pitch_wu():
				off_line_ticks += 1
				gained[i] = float(gained.get(i, 0.0)) \
						+ maxf(0.0, (u._sim_soldier_pos[i] - before[i]).dot(forward))
	var worst: float = 0.0
	for g in gained.values():
		worst = maxf(worst, g)
	assert_gt(off_line_ticks, 0, "precondition: rear men stood off their lines")
	assert_lt(worst, 0.25 * u.rank_pitch_wu(),
		"the most ground a rear man gained off his line is %.2f wu" % worst)


## Nobody passes through anybody: no two men of the block come closer than the overlap floor the
## demo defect scan judges a reshape by, a quarter of two touching bodies
## (DemoDefects.OVERLAP_BODY_FRAC of twice the body radius, 2.25 wu), centred or held on either
## flank, since a man in an interval comes up only while nobody of another file stands in his
## lane. Held on the right flank, main's deal brought two men to 1.68 wu. The bound is not yet a
## body radius (4.5 wu): this build measured 4.44 wu centred and 4.33 wu held, a man stepping
## sideways toward his lane while the rear man of a file beside it slides across to open out,
## and gating that sideways step on the space beside him left held drills that never ended.
func test_no_two_men_come_onto_each_other() -> void:
	for anchor in [UnitFormation.Anchor.CENTRE, UnitFormation.Anchor.RIGHT,
			UnitFormation.Anchor.LEFT]:
		var units: Array = await _stage([_spearmen()])
		var u: Unit = units[0]
		# TODO(#1974): one body radius once men avoid each other body to body; the centred and both
		# held cases measure 4.44, 4.33 and 4.33 wu.
		var floor_wu: float = 2.0 * u.soldier_body_radius() * DemoDefects.OVERLAP_BODY_FRAC
		_battle.enqueue_file_double([u.uid], 1, anchor)
		var walk: Dictionary = await _walk(u, DRILL_TICKS)
		assert_gte(walk["ended"], 0, "anchor %d: the drill ended" % anchor)
		assert_gte(walk["closest"], floor_wu,
			"anchor %d: the nearest two men came within %.2f wu" % [anchor, walk["closest"]])
		assert_lt(walk["ahead"], 0.25 * u.rank_pitch_wu(),
			"anchor %d: the front went %.2f wu ahead" % [anchor, walk["ahead"]])
		assert_lt(walk["end_line"], 0.25 * u.rank_pitch_wu(),
			"anchor %d: a man of the front rank ended %.2f wu off its line" % [anchor, walk["end_line"]])
		await _free_battle()


# --- Which files stand, live -----------------------------------------------------


## Widened about the middle, the files next to the middle stand and each wing opens outward
## (Aelian 33): the left wing's intervals open on the left of its files and the right wing's on
## the right, whichever way the block faces and whether or not an about-face mirror stands on its
## grid (set_frontage bakes the mirror first, so the slot frame's +x is the right). Of 9 old files
## the left wing is 4 and the right wing 5 with the middle file, so the left flank steps out 4
## file pitches and the right 5; on main every interval opened on the right of its file and the
## guide was the middle file, so the left flank stepped out 4 and the right 5 too, but every file
## of the left wing crossed the line of the file beside it.
func test_a_centred_explicatio_opens_each_wing_outward() -> void:
	for facing in [[0, 1], [1, 0]]:
		for mirrored in [false, true]:
			var units: Array = await _stage([_spearmen(facing)])
			var u: Unit = units[0]
			u.formation_slots(u.soldiers)
			if mirrored:
				# A standing mirror, and the men re-formed on it, as an about-face leaves them.
				u._formation_mirror_x = true
				await _run(DRILL_TICKS)
			var right := Vector2(-u.facing.y, u.facing.x)
			var before: Vector2 = _extent(u, right)
			_battle.enqueue_file_double([u.uid], 1)
			assert_true(u.explicatio_drill_active(), "precondition: the widen is the drill")
			assert_false(u._formation_mirror_x, "the mirror is baked before the deal")
			assert_eq(u._explicatio_lane_split, 4, "the left wing is the 4 files left of the middle")
			var local: PackedVector2Array = u.formation_slots(u.soldiers, false, false)
			var ang: float = u.soldier_block_world_angle()
			var outward: int = 0
			var pairs: int = 0
			for i in range(u.soldiers):
				if _stays(u, i):
					continue
				var f: int = u._sim_soldier_file[i]
				for j in range(u.soldiers):
					if u._sim_soldier_file[j] == _partner_file(u, f) \
							and u._sim_soldier_rank[j] == u._sim_soldier_rank[i]:
						pairs += 1
						var side: float = (local[i] - local[j]).rotated(ang).dot(right)
						if (side < 0.0) == (f / 2 < u._explicatio_lane_split):
							outward += 1
			assert_gt(pairs, 0, "precondition: rear men beside their front-half partners")
			assert_eq(outward, pairs, "facing %s, mirror %s: every lane opens away from the middle"
					% [str(facing), str(mirrored)])
			var walk: Dictionary = await _walk(u, DRILL_TICKS)
			assert_gte(walk["ended"], 0, "precondition: the drill ended")
			var after: Vector2 = _extent(u, right)
			var pitch: float = u.file_pitch_wu()
			assert_almost_eq(before.x - after.x, 4.0 * pitch, 0.25 * pitch,
				"facing %s, mirror %s: the left flank stepped out %.2f wu"
					% [str(facing), str(mirrored), before.x - after.x])
			assert_almost_eq(after.y - before.y, 5.0 * pitch, 0.25 * pitch,
				"facing %s, mirror %s: the right flank stepped out %.2f wu"
					% [str(facing), str(mirrored), after.y - before.y])
			await _free_battle()


## With an even count of files both flanks step out alike: 96 men in 6 files of 16 open 3 file
## pitches on each side, the two middle files standing.
func test_an_even_block_opens_both_flanks_alike() -> void:
	var units: Array = await _stage([_spearmen([0, 1], SPAWN, 96)])
	var u: Unit = units[0]
	var right := Vector2(-u.facing.y, u.facing.x)
	var before: Vector2 = _extent(u, right)
	_battle.enqueue_file_double([u.uid], 1)
	assert_eq(UnitFormation.frontage(u), 12, "precondition: 6 files doubled to 12")
	var walk: Dictionary = await _walk(u, DRILL_TICKS)
	assert_gte(walk["ended"], 0, "precondition: the drill ended")
	var after: Vector2 = _extent(u, right)
	var pitch: float = u.file_pitch_wu()
	assert_almost_eq(before.x - after.x, 3.0 * pitch, 0.25 * pitch,
		"the left flank stepped out %.2f wu" % (before.x - after.x))
	assert_almost_eq(after.y - before.y, 3.0 * pitch, 0.25 * pitch,
		"the right flank stepped out %.2f wu" % (after.y - before.y))


## An explicatio held on its right flank opens its lanes on the left, so the right flank's own
## front half-file keeps its ground.
func test_an_explicatio_held_on_the_right_opens_its_lanes_on_the_left() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.RIGHT)
	assert_true(u.explicatio_drill_active(), "precondition: the widen is the drill")
	var rear: int = 0
	var left_of_partner: int = 0
	var local: PackedVector2Array = u.formation_slots(u.soldiers, false, false)
	for i in range(u.soldiers):
		if u._sim_soldier_file[i] % 2 != 0:   # with the lane on the left the rear takes 2k
			continue
		rear += 1
		for j in range(u.soldiers):
			if u._sim_soldier_file[j] == u._sim_soldier_file[i] + 1 \
					and u._sim_soldier_rank[j] == u._sim_soldier_rank[i]:
				if local[i].x < local[j].x:
					left_of_partner += 1
	assert_eq(rear, 68, "68 rear men take the even files, the lanes on the left")
	assert_eq(left_of_partner, 68, "each lane is on the left of its front half-file")
	assert_eq(u._explicatio_stand_file, 17, "the right corner file stands")


## A plain B after a held widen is widened about the middle: the flank it holds is the order's,
## not read off the offset the held widen left standing. Before, Shift+B then B (and Ctrl+B then
## B) read the standing offset as a held flank and stood a corner file.
func test_a_plain_widen_after_a_held_one_stands_the_middle_files() -> void:
	for anchor in [UnitFormation.Anchor.RIGHT, UnitFormation.Anchor.LEFT]:
		var units: Array = await _stage([_spearmen([0, 1], SPAWN, 72)])
		var u: Unit = units[0]
		_battle.enqueue_file_double([u.uid], 1, anchor)
		var walk: Dictionary = await _walk(u, DRILL_TICKS)
		assert_gte(walk["ended"], 0, "precondition: the held drill ended")
		assert_ne(u.frontage_anchor_offset, 0.0, "precondition: the held widen left an offset")
		var old_files: int = UnitFormation.frontage(u)
		_battle.enqueue_file_double([u.uid], 1)
		assert_true(u.explicatio_drill_active(), "precondition: the second widen is the drill")
		assert_eq(u._explicatio_lane_split, old_files / 2,
			"anchor %d then B: each wing opens outward" % anchor)
		assert_eq(u._explicatio_stand_file, 2 * (old_files / 2),
			"anchor %d then B: the file next to the middle stands" % anchor)
		await _free_battle()


## The order carries the flank it holds into the replay, and playback reads it back.
func test_the_held_flank_rides_the_replay() -> void:
	var entry: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18,
			INF, 0, 3.0, -1, 0, 0, -1, -1, 0, HALF_FILE, UnitFormation.Anchor.RIGHT)
	assert_eq(entry["explicatio_held"], UnitFormation.Anchor.RIGHT, "the entry names the flank")
	var centred: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18,
			INF, 0, 0.0, -1, 0, 0, -1, -1, 0, HALF_FILE)
	assert_false(centred.has("explicatio_held"), "a widen about the middle records none")
	var Decoder := preload("res://scripts/ReplayDecoder.gd")
	assert_eq(Decoder._decode_order({"units": [1], "explicatio_held": -1})["explicatio_held"], -1,
		"playback reads it back")


# --- When the block does the drill -----------------------------------------------


## A block on the march keeps main's lateral deal: the drill is for a block standing still
## (the drill on the march is still to do), and no man is set to follow another.
func test_a_unit_widening_on_the_march_is_not_dealt_the_drill() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle._apply_order_cmd({"units": [u.uid], "x": 500.0, "y": 700.0, "target": -1})
	var waited: int = 0
	while u.state != Unit.State.MOVING and waited < 600:
		await get_tree().physics_frame
		waited += 1
	assert_eq(u.state, Unit.State.MOVING, "precondition: the unit is marching")
	_battle.enqueue_file_double([u.uid], 1)
	assert_eq(UnitFormation.frontage(u), 18, "the files still double")
	assert_false(u.explicatio_drill_active(), "no drill on the march")
	assert_eq(_count_role(u, UnitFormation.SoldierRole.HEMILOCHITES), 0, "nobody leads a column")


## A block that has just halted, with every second file still three quarters of a rank pitch
## short of its slots, does the drill from where its men stand: before, a man more than
## REFORM_SETTLE_EPS_RESHAPE off his slot sent the block to main's lateral deal. It ends, doubled,
## with no two men within a body radius of each other (this build measured 5.27 wu).
func test_a_block_widened_as_it_halts_does_the_drill_from_where_its_men_stand() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle._apply_order_cmd({"units": [u.uid], "x": 500.0, "y": 380.0, "target": -1})
	var waited: int = 0
	while u.state != Unit.State.MOVING and waited < 600:
		await get_tree().physics_frame
		waited += 1
	while (u.state != Unit.State.IDLE or u.has_move_target) and waited < 1800:
		await get_tree().physics_frame
		waited += 1
	assert_eq(u.state, Unit.State.IDLE, "precondition: the block halted")
	for i in range(u.soldiers):
		if u._sim_soldier_file[i] % 2 == 1:
			u._sim_soldier_pos[i] -= u.facing * 0.75 * u.rank_pitch_wu()
	var unsettled: float = _worst_off_slot(u)
	assert_gt(unsettled, Unit.REFORM_SETTLE_EPS_RESHAPE,
		"precondition: a man stands %.2f wu off his slot" % unsettled)
	_battle.enqueue_file_double([u.uid], 1)
	assert_true(u.explicatio_drill_active(), "the halted block does the drill")
	var floor_wu: float = u.soldier_body_radius()
	var walk: Dictionary = await _walk(u, DRILL_TICKS)
	assert_gte(walk["ended"], 0, "the drill ended")
	assert_eq(UnitFormation.frontage(u), 18, "the files doubled")
	assert_gte(walk["closest"], floor_wu, "the nearest two men came within %.2f wu" % walk["closest"])
	assert_lt(_worst_off_slot(u), Unit.REFORM_SETTLE_EPS, "every man stands on his slot")


## A widen ordered while a duplicatio is still walking is the drill too, from the files and ranks
## the duplicatio dealt and from where the men stand, and it ends with the block doubled.
func test_an_explicatio_during_a_duplicatio_is_the_drill_and_ends() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], -1)
	await _run(110)
	_battle.enqueue_file_double([u.uid], 1)
	assert_true(u.explicatio_drill_active(), "the widen is the drill")
	var walk: Dictionary = await _walk(u, 2 * DRILL_TICKS)
	assert_gte(walk["ended"], 0, "the drill ended")
	assert_lt(_worst_off_slot(u), Unit.REFORM_SETTLE_EPS, "every man stands on his slot")


## A march ends the drill as the block sets off, with the grid laid on the men where they stand.
func test_a_march_order_ends_the_drill() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await _run(60)
	assert_true(u.explicatio_drill_active(), "precondition: under way")
	_battle._apply_order_cmd({"units": [u.uid], "x": 500.0, "y": 700.0, "target": -1})
	var waited: int = 0
	var reading: Vector2 = u.explicatio_grid_position()
	while u.state != Unit.State.MOVING and waited < 600:
		reading = u.explicatio_grid_position()
		await get_tree().physics_frame
		waited += 1
	assert_eq(u.state, Unit.State.MOVING, "precondition: the unit set off")
	assert_false(u.explicatio_drill_active(), "the march ends the drill")
	assert_lt(u.position.distance_to(reading), u.rank_pitch_wu(),
		"the grid is laid where the men stood (%.2f wu)" % u.position.distance_to(reading))


## Demoted to the far tier mid-drill, the block lays its grid on the men before they go, and no
## drill is left under way for men who no longer exist.
func test_a_demotion_ends_the_drill_with_the_grid_on_the_men() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await _run(60)
	assert_true(u.explicatio_drill_active(), "precondition: under way")
	var reading: Vector2 = u.explicatio_grid_position()
	TierTransition.demote(u)
	assert_false(u.explicatio_drill_active(), "the demotion ends the drill")
	assert_almost_eq(u.position.x, reading.x, 0.01, "the grid is laid on the men")
	assert_almost_eq(u.position.y, reading.y, 0.01, "the grid is laid on the men")


## A deal that comes back empty is a bug, said out loud: the block widens with the lateral deal,
## its files re-dealt from the bodies, rather than with its frontage doubled over files half dealt.
func test_an_empty_deal_says_so_and_widens_with_the_lateral_deal() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	u._sim_soldier_file[0] = 99   # a file id the deal refuses
	_battle.enqueue_file_double([u.uid], 1)
	assert_push_error("came back empty", "the empty deal is reported")
	assert_false(u.explicatio_drill_active(), "no drill")
	assert_eq(UnitFormation.frontage(u), 18, "the files still double")
	u.formation_slots(u.soldiers)
	assert_eq(u._file_assignment_files, 18, "and are dealt afresh from the bodies")
	var widest: int = 0
	for f in u._sim_soldier_file:
		widest = maxi(widest, f)
	assert_lt(widest, 18, "every man in a file of the new width")


## A deal with no file leader to stand is a bug, said out loud: the files are dealt but no drill
## starts, and the men take their slots.
func test_a_deal_with_no_file_leader_to_stand_says_so() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var dealt: Dictionary = UnitFormation.explicatio_assignment(u._sim_soldier_file,
			u._sim_soldier_rank, 9, 4)
	var ranks: PackedInt32Array = dealt["ranks"]
	for i in range(ranks.size()):
		ranks[i] += 1   # nobody at rank 0
	u._begin_explicatio(dealt, 9, 0, HALF_FILE, 4, false)
	assert_push_error("no file leader to stand", "the missing guide is reported")
	assert_false(u.explicatio_drill_active(), "no drill starts")


## A block whose grid stands a half-turn from its facing, as an about-face leaves it, has its
## file leaders behind its men and its file ids growing to their left: dealt the drill, each file
## leader would dress on the far side of the file he dresses on and the files would cross. It
## widens with the lateral deal.
func test_a_block_about_faced_on_its_grid_is_not_dealt_the_drill() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	u.facing = u.facing.rotated(PI)
	u._formation_angle = wrapf(u._formation_angle - PI, -PI, PI)
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]
	assert_almost_eq(absf(u.grid_fold()), PI, 1e-4, "precondition: a half-turn fold")
	_battle.enqueue_file_double([u.uid], 1)
	assert_eq(UnitFormation.frontage(u), 18, "the files still double")
	assert_false(u.explicatio_drill_active(), "no drill on a grid turned from the men")


## The turn-and-unfold combo's widen doubles the turned block's files against the width it had
## before the turn, so a block deeper than it is wide widens with the lateral deal; the turn's
## transposed grid leaves the files to be dealt afresh from where the men stand.
func test_the_combo_widen_of_a_deep_block_keeps_the_lateral_deal() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	assert_true(u.quarter_turn_explicatio(1), "precondition: the combo starts")
	var waited: int = 0
	while UnitFormation.frontage(u) == 9 and waited < 600:
		await get_tree().physics_frame
		waited += 1
	assert_ne(UnitFormation.frontage(u), 9, "precondition: the combo widened")
	assert_false(u.explicatio_drill_active(), "the combo's widen is not the drill")
	u.formation_slots(u.soldiers)
	assert_eq(u._file_assignment_files, UnitFormation.frontage(u),
		"the files are dealt afresh for the new width")


## A file-major block widened any other way keeps main's lateral deal: a [ ] style absolute
## resize to twice the files is not the drill, and the centre stays where it was.
func test_an_absolute_resize_to_twice_the_files_is_not_the_drill() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var position_before: Vector2 = u.position
	u.set_frontage(18)
	u.formation_slots(u.soldiers)
	assert_eq(u.position, position_before, "the centre stays put")
	assert_false(u.explicatio_drill_active(), "nobody follows anybody")
	assert_eq(u.follow_leader(0), SoldierFollow.NOT_FOLLOWING, "every man keeps to his slot")
	assert_eq(u.follow_room(0), 1.0, "and steps into no gap")
	assert_eq(_count_role(u, UnitFormation.SoldierRole.HEMILOCHITES), 0, "nobody leads a column")


# --- When the drill ends ----------------------------------------------------------


## Each man stops following once he has taken his place, and not before the man he follows has
## taken his: the guide at once, since he holds the ground he stands on; the men behind a file
## leader still opening out, though they already stand a rank behind him, only after he has. The
## drill ends when no man is still following.
func test_each_man_stops_following_once_he_has_taken_his_place() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await get_tree().physics_frame
	var guide: int = -1
	var behind_outer: int = -1
	for i in range(u.soldiers):
		if u._sim_soldier_file[i] == u._explicatio_stand_file and u._sim_soldier_rank[i] == 0:
			guide = i
		if u._sim_soldier_file[i] == 1 and u._sim_soldier_rank[i] == 1:
			behind_outer = i   # the left corner file's second man: his leader opens 4 pitches
	assert_eq(u._explicatio_following[guide], 0, "the guide has taken his place")
	assert_eq(u.follow_leader(guide), SoldierFollow.NOT_FOLLOWING, "and keeps to it as a slot")
	assert_eq(u._explicatio_following[behind_outer], 1,
		"the man behind a file leader still opening out still follows")
	var left: int = 0
	var last_following: PackedByteArray = PackedByteArray()
	while u.explicatio_drill_active() and left < DRILL_TICKS:
		last_following = u._explicatio_following.duplicate()
		await get_tree().physics_frame
		left += 1
	assert_false(u.explicatio_drill_active(), "the drill ended")
	assert_gt(last_following.count(1), 0,
		"the tick before it ended a man still followed: the last of them taking his place ended it")
	assert_gt(left, 1, "and it ran past its first tick")


## A man pressed by a man of another regiment can come no nearer his place, so he takes it where
## he stands once the man he follows has taken his; a man not pressed and off his place goes on
## following.
func test_a_man_pressed_by_another_regiment_takes_his_place_where_he_stands() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await get_tree().physics_frame
	var places: PackedVector2Array = _places(u)
	var pressed: int = -1
	var free: int = -1
	for i in range(u.soldiers):
		var a: int = u._explicatio_leaders[i]
		if u._explicatio_following[i] == 0 or a < 0 or u._explicatio_following[a] != 0 \
				or u._sim_soldier_pos[i].distance_to(places[i]) <= Unit.REFORM_SETTLE_EPS:
			continue
		if pressed < 0:
			pressed = i
		elif free < 0:
			free = i
	assert_gte(free, 0, "precondition: two men off their places whose leaders have taken theirs")
	u._sim_steer[pressed] = Vector2(5.0, 0.0)
	u._sim_steer[free] = Vector2.ZERO
	u._advance_explicatio_drill()
	assert_eq(u._explicatio_following[pressed], 0, "the pressed man takes his place")
	assert_eq(u._explicatio_following[free], 1, "the free man goes on following")


## A man of another file standing in a hemilochites' lane, a little ahead of him on his line,
## takes his room away; while that man still follows, the lane may yet clear, and once he has
## stopped following it is shut, and the hemilochites stops following where he stands.
func test_a_man_in_his_lane_holds_him_back_and_a_settled_one_shuts_it() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await _run(5)
	var h: int = -1
	for i in range(u.soldiers):
		if _role(u, i) == UnitFormation.SoldierRole.HEMILOCHITES and u._explicatio_following[i] == 1:
			h = i
			break
	var b: int = -1
	for j in range(u.soldiers):
		if u._sim_soldier_file[j] != u._sim_soldier_file[h] and _stays(u, j) \
				and u._sim_soldier_rank[j] > 0 and u._explicatio_following[j] == 1:
			b = j
			break
	var front: Vector2 = u._sim_soldier_facing[h].normalized()
	var right := Vector2(-front.y, front.x)
	var line_off: float = (u._explicatio_places[h] - u._sim_soldier_pos[h]).dot(right)
	u._sim_soldier_pos[b] = u._sim_soldier_pos[h] + right * line_off + front * 4.0
	u._explicatio_following[u._explicatio_leaders[h]] = 0   # his leader has taken his place
	u._explicatio_follow_frame = -1
	u._refresh_explicatio_follow(u.soldiers)
	assert_eq(u._explicatio_rooms[h], 0.0, "a man in his lane leaves him no room")
	assert_eq(u._explicatio_shut[h], 0, "while that man still follows, the lane is not shut")
	var everyone := PackedInt32Array(range(u.soldiers))
	var lane: PackedInt32Array = SoldierFollowSteer.lane_blockers(u._sim_soldier_pos[h], front,
			u._explicatio_places[h], u._sim_soldier_pos, everyone, u._sim_soldier_file,
			u._sim_soldier_file[h], u.explicatio_lane_clear(), u.rank_pitch_wu(),
			u.soldier_body_radius())
	assert_true(lane.has(b), "precondition: that man stands in his lane")
	for j in lane:
		u._explicatio_following[j] = 0   # every man in his lane has taken his place
	u._explicatio_follow_frame = -1
	u._advance_explicatio_drill()
	assert_eq(u._explicatio_shut[h], 1, "that man settled, the lane is shut")
	assert_eq(u._explicatio_following[h], 0, "and he stops following where he stands")


## The cells each man's lane is read from (_explicatio_cells, _explicatio_cell_men) hold every
## man who stands in it: over a drill, every tenth tick, the room read from the cells matches
## lane_blockers handed every man of the block, with the men facing the block's way and with each
## man's facing turned a little off it, alternately each way.
func test_the_cells_hold_every_man_in_a_lane() -> void:
	for tilt in [0.0, 0.2]:
		var units: Array = await _stage([_spearmen()])
		var u: Unit = units[0]
		_battle.enqueue_file_double([u.uid], 1)
		var everyone := PackedInt32Array(range(u.soldiers))
		var checked: int = 0
		var blocked: int = 0
		var mismatched: int = 0
		for t in range(DRILL_TICKS):
			await get_tree().physics_frame
			if not u.explicatio_drill_active():
				break
			if t % 10 != 0:
				continue
			for i in range(u.soldiers):
				u._sim_soldier_facing[i] = u.facing.rotated(tilt if i % 2 == 0 else -tilt)
			u._explicatio_follow_frame = -1
			assert_true(u._refresh_explicatio_follow(u.soldiers), "precondition: a plan")
			for i in range(u.soldiers):
				if _stays(u, i):
					continue
				var lane: PackedInt32Array = SoldierFollowSteer.lane_blockers(
						u._sim_soldier_pos[i], u._sim_soldier_facing[i], u._explicatio_places[i],
						u._sim_soldier_pos, everyone, u._sim_soldier_file, u._sim_soldier_file[i],
						u.explicatio_lane_clear(), u.rank_pitch_wu(), u.soldier_body_radius())
				checked += 1
				if not lane.is_empty():
					blocked += 1
				if (u._explicatio_rooms[i] == 0.0) != (not lane.is_empty()):
					mismatched += 1
		assert_gt(blocked, 0, "tilt %.1f: precondition: men stood in lanes" % tilt)
		assert_eq(mismatched, 0, "tilt %.1f: of %d lanes read, %d differed" % [tilt, checked,
				mismatched])
		await _free_battle()


## The cells a man's lane is read from reach its far corner for a man turned the most the cells
## allow for (Unit.EXPLICATIO_TILT_MAX): at the close-order pitch (cells 9 wu, lane 8 wu each side),
## a man standing on his line just short of a cell's edge, turned that far, has the far corner of
## his lane, a rank ahead and a lane's width across, past the next cell over; a man of another
## file standing there is among the men read.
func test_the_cells_reach_the_far_corner_of_a_turned_mans_lane() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var cell: float = maxf(u.rank_pitch_wu(), u.explicatio_lane_clear())
	var clear: float = u.explicatio_lane_clear()
	assert_almost_eq(cell, 9.0, 0.001, "precondition: 9 wu cells")
	var front: Vector2 = u.facing.normalized()
	var right := Vector2(-front.y, front.x)
	var pos: Vector2 = right * (cell - 0.1) + front * (0.5 * cell)
	var own_front: Vector2 = front.rotated(-Unit.EXPLICATIO_TILT_MAX)
	var own_right := Vector2(-own_front.y, own_front.x)
	if own_right.dot(right) < 0.0:
		own_right = -own_right
	var corner: Vector2 = pos + own_front * cell + own_right * (clear - 0.01)
	if corner.dot(right) < pos.dot(right) + clear:
		own_front = front.rotated(Unit.EXPLICATIO_TILT_MAX)
		own_right = Vector2(-own_front.y, own_front.x)
		if own_right.dot(right) < 0.0:
			own_right = -own_right
		corner = pos + own_front * cell + own_right * (clear - 0.01)
	assert_gt(floori(corner.dot(right) / cell), floori(pos.dot(right) / cell) + 1,
		"precondition: the corner lies past the next cell over")
	var cells: Dictionary = u._explicatio_cells(PackedVector2Array([pos, corner]), cell)
	assert_true(u._explicatio_cell_men(cells, pos, pos, cell, clear,
			u.soldier_body_radius()).has(1), "the man at the corner of his lane is among the men read")


## And its rear corner: in a shield wall (cells and pitch 6.75 wu, lane 5.75 wu each side), a man
## a file pitch off his line, just into a cell along the block's facing and turned the most the
## cells allow for, has the rear corner of his lane, a body radius behind him on the far side of
## his line, two cells behind him; a man of another file standing there is among the men read.
func test_the_cells_reach_the_rear_corner_of_a_turned_mans_lane() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	u.set_formation(Unit.FORMATION_SHIELD_WALL)
	var clear: float = u.explicatio_lane_clear()
	var cell: float = maxf(u.rank_pitch_wu(), clear)
	var r: float = u.soldier_body_radius()
	assert_almost_eq(cell, 6.75, 0.001, "precondition: 6.75 wu cells")
	var front: Vector2 = u.facing.normalized()
	var right := Vector2(-front.y, front.x)
	var pos: Vector2 = front * 0.1 + right * (0.5 * cell)
	var level: Vector2 = pos + right * u.file_pitch_wu()
	var worst: Vector2 = pos
	for sign in [-1.0, 1.0]:
		var own_front: Vector2 = front.rotated(sign * Unit.EXPLICATIO_TILT_MAX)
		var own_right := Vector2(-own_front.y, own_front.x)
		var side: float = signf((level - pos).dot(own_right))
		var across: float = (level - pos).dot(own_right) + side * (clear - 0.01)
		var corner: Vector2 = pos - own_front * (r - 0.01) + own_right * across
		if corner.dot(front) < worst.dot(front):
			worst = corner
	assert_lt(floori(worst.dot(front) / cell), floori(pos.dot(front) / cell) - 1,
		"precondition: the rear corner lies past the cell behind him")
	var cells: Dictionary = u._explicatio_cells(PackedVector2Array([pos, worst]), cell)
	assert_true(u._explicatio_cell_men(cells, pos, level, cell, clear, r).has(1),
		"the man at the rear corner of his lane is among the men read")


## A man coming up an interval that has not yet opened where he is goes on following when a man
## of another regiment presses on him: the man beside him, not the press, holds him back, and
## leaving the follow mode would walk him up the interval before it opened.
func test_a_pressed_column_leader_waits_for_his_interval_to_open() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await get_tree().physics_frame
	var h: int = -1
	for i in range(u.soldiers):
		if _role(u, i) == UnitFormation.SoldierRole.HEMILOCHITES \
				and u._explicatio_rooms[i] < 1.0 and u._explicatio_following[i] == 1:
			h = i
			break
	assert_gte(h, 0, "precondition: a hemilochites whose interval has not opened")
	u._explicatio_following[u._explicatio_leaders[h]] = 0   # his leader has taken his place
	u._sim_steer[h] = Vector2(5.0, 0.0)
	u._advance_explicatio_drill()
	assert_eq(u._explicatio_following[h], 1, "he goes on following")


## Shot down mid-drill, the guide's whole file falls and nobody closes up into his place: the
## leader of the nearest file that stays becomes the guide where he stands, and the front rank
## dresses on him, a man, not on the ground the dead guide held. The drill still ends.
func test_a_guide_shot_down_with_his_file_hands_the_line_to_the_next_file_leader() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await _run(30)
	var dead_file: int = u._explicatio_stand_file
	var i: int = 0
	while i < u.soldiers:
		if u._sim_soldier_file[i] == dead_file:
			u._sim_soldier_hp[i] = 0.0
			SoldierMelee.reap(u, null)
			i = 0
			continue
		i += 1
	assert_false(u._sim_soldier_file.has(dead_file), "precondition: the guide's file is gone")
	await get_tree().physics_frame
	assert_true(u.explicatio_drill_active(), "the drill goes on")
	assert_ne(u._explicatio_stand_file, dead_file, "another file stands")
	var guide: int = -1
	for j in range(u.soldiers):
		if u._sim_soldier_file[j] == u._explicatio_stand_file and u._sim_soldier_rank[j] == 0:
			guide = j
	assert_gte(guide, 0, "a man leads the file that stands")
	assert_true(UnitFormation.explicatio_file_stays(u._explicatio_stand_file,
			u._explicatio_lane_split), "and it is a file that stays")
	var walk: Dictionary = await _walk(u, DRILL_TICKS)
	assert_gte(walk["ended"], 0, "the drill ended")


## A man who falls takes his entry in the follow flags with him, and the plan is read afresh for
## the men left the same tick, so the drill goes on with every man lined up.
func test_a_casualty_mid_drill_keeps_the_follow_flags_lined_up() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await get_tree().physics_frame
	assert_true(u._refresh_explicatio_follow(u.soldiers), "precondition: a plan this tick")
	u._sim_soldier_hp[5] = 0.0
	SoldierMelee.reap(u, null)
	assert_eq(u.soldiers, SPEARMEN - 1, "precondition: a man fell")
	assert_eq(u._explicatio_following.size(), u.soldiers, "one flag for each man left")
	assert_true(u._refresh_explicatio_follow(u.soldiers), "the plan is read for the men left")
	assert_eq(u._explicatio_places.size(), u.soldiers, "one place for each man left")
	await get_tree().physics_frame
	assert_true(u.explicatio_drill_active(), "the drill goes on")


## A friendly block standing where the right wing opens out crowds the drill: the men it presses
## take their places where they stand, and the drill still ends. Before, it ran until every man
## stood on his place, and kept running while a friend held one off it.
func test_a_drill_crowded_by_a_friendly_block_still_ends() -> void:
	var units: Array = await _stage([_spearmen(), _spearmen([0, 1], SPAWN + Vector2(-110, 0))])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	assert_true(u.explicatio_drill_active(), "precondition: the widen is the drill")
	var pressed_off: int = 0
	var ended: int = -1
	for t in range(2 * DRILL_TICKS):
		var following: PackedByteArray = u._explicatio_following.duplicate()
		var places: PackedVector2Array = _places(u).duplicate()
		var pos: PackedVector2Array = u._sim_soldier_pos.duplicate()
		var steer: PackedVector2Array = u._sim_steer.duplicate()
		await get_tree().physics_frame
		for i in range(mini(following.size(), u._explicatio_following.size())):
			if following[i] == 1 and u._explicatio_following[i] == 0 \
					and pos[i].distance_to(places[i]) > Unit.REFORM_SETTLE_EPS:
				pressed_off += 1
		if not u.explicatio_drill_active():
			ended = t
			break
	assert_gt(pressed_off, 0, "precondition: the friend held a man off his place")
	assert_gte(ended, 0, "the drill ended")


# --- The column and its leader, live ---------------------------------------------


## Each half-file's leader, the man who stood at the head of its rear half, is its hemilochites,
## heads his new file and comes up beside his own file leader.
func test_the_hemilochites_comes_up_beside_his_file_leader() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await get_tree().physics_frame
	var leaders: int = 0
	for i in range(u.soldiers):
		if _role(u, i) != UnitFormation.SoldierRole.HEMILOCHITES:
			continue
		leaders += 1
		assert_eq(u._sim_soldier_rank[i], 0, "the hemilochites heads his new file")
		var lead: int = u.follow_leader(i)
		assert_gte(lead, 0, "the hemilochites follows a man")
		assert_eq(u._sim_soldier_file[lead], _partner_file(u, u._sim_soldier_file[i]),
			"he follows the leader of the file he opened from")
		assert_eq(u._sim_soldier_rank[lead], 0, "that man is its file leader")
	assert_eq(leaders, 9, "one hemilochites for each old file")


## Only the man with the role leads his column up the interval: the plan read without his role
## has him follow nobody and stay where he is, and read with it, follow the file he opened from.
func test_only_the_man_with_the_role_leads_his_column() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	var h: int = -1
	for i in range(u.soldiers):
		if _role(u, i) == UnitFormation.SoldierRole.HEMILOCHITES:
			h = i
			break
	u._sim_soldier_role[h] = UnitFormation.SoldierRole.NONE
	u._explicatio_follow_frame = -1   # read the plan afresh this tick
	assert_true(u._refresh_explicatio_follow(u.soldiers), "precondition: a plan")
	assert_eq(u._explicatio_leaders[h], SoldierFollow.HOLD, "without the role he holds where he is")
	u._sim_soldier_role[h] = UnitFormation.SoldierRole.HEMILOCHITES
	u._explicatio_follow_frame = -1
	u._refresh_explicatio_follow(u.soldiers)
	var lead: int = u._explicatio_leaders[h]
	assert_gte(lead, 0, "with it he follows a man")
	assert_eq(u._sim_soldier_file[lead], _partner_file(u, u._sim_soldier_file[h]),
		"the leader of the file he opened from")


## Every man behind a file leader follows the man ahead of him in his file, and nobody gets ahead
## of him along the facing while the drill runs: a man who stands abreast of him is held to a
## quarter of a rank pitch of body jitter.
func test_nobody_passes_the_man_ahead_of_him() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await get_tree().physics_frame
	var ahead: PackedInt32Array = _man_ahead(u)
	for i in range(u.soldiers):
		if ahead[i] >= 0 and u._explicatio_following[i] == 1:
			assert_eq(u.follow_leader(i), ahead[i], "man %d follows the man ahead of him" % i)
	var walk: Dictionary = await _walk(u, DRILL_TICKS)
	assert_lt(walk["overtake"], 0.25 * u.rank_pitch_wu(),
		"the farthest any man got ahead of the man ahead of him is %.2f wu" % walk["overtake"])


## A hemilochites who falls on the way in hands the lead to the man behind him: that man takes
## the role, heads the file and follows its file leader, and the column still follows him in
## without passing.
func test_a_fallen_hemilochites_hands_the_lead_to_the_man_behind_him() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	var leader: int = -1
	for i in range(u.soldiers):
		if _role(u, i) == UnitFormation.SoldierRole.HEMILOCHITES:
			leader = i
			break
	var file: int = u._sim_soldier_file[leader]
	var heir: int = -1
	for i in range(u.soldiers):
		if u._sim_soldier_file[i] == file and u._sim_soldier_rank[i] == 1:
			heir = i
	assert_gte(heir, 0, "precondition: a man stands behind the hemilochites")
	var walk: Dictionary = await _walk(u, DRILL_TICKS, 10, leader)
	var heir_now: int = heir - 1 if heir > leader else heir
	assert_eq(u.soldiers, SPEARMEN - 1, "precondition: the hemilochites fell")
	assert_eq(_role(u, heir_now), UnitFormation.SoldierRole.HEMILOCHITES,
		"the man behind him took the lead")
	assert_eq(u._sim_soldier_rank[heir_now], 0, "and heads the file")
	assert_eq(_count_role(u, UnitFormation.SoldierRole.HEMILOCHITES), 9,
		"each half-file still has one leader")
	assert_gte(walk["ended"], 0, "the drill still ended")
	assert_lt(walk["overtake"], 0.25 * u.rank_pitch_wu(),
		"the farthest any man got ahead of the man ahead of him is %.2f wu" % walk["overtake"])


## A snapshot carries each man's role and the drill under way, with whom has taken his place.
## A reinforcement re-deals the block: the roles go, and the drill ends with the grid laid on the
## men.
func test_the_roles_and_the_drill_ride_a_snapshot_and_a_reinforcement_ends_them() -> void:
	var units: Array = await _stage([_spearmen(), _spearmen([0, 1], Vector2(800, 300))])
	var u: Unit = units[0]
	var reserve: Unit = units[1]
	_battle.enqueue_file_double([u.uid], 1)
	await get_tree().physics_frame
	var roles: PackedByteArray = u._sim_soldier_role.duplicate()
	var following: PackedByteArray = u._explicatio_following.duplicate()
	assert_eq(roles.size(), SPEARMEN, "precondition: every man has a role entry")
	var snap: Dictionary = u.to_snapshot_dict()
	var stand: Vector2 = u._explicatio_stand_point
	u._sim_soldier_role = PackedByteArray()
	u._end_explicatio_drill()
	u.apply_snapshot_dict(snap)
	assert_eq(u._sim_soldier_role, roles, "the snapshot restores each man's role")
	assert_true(u.explicatio_drill_active(), "the snapshot restores the drill under way")
	assert_eq(u._explicatio_following, following, "and who has taken his place")
	assert_eq(u._explicatio_stand_point, stand, "and the ground its standing file holds")
	u.append_soldier_bodies(reserve)
	assert_true(u._sim_soldier_role.is_empty(), "the reinforcement takes the roles away")
	u._advance_explicatio_drill()
	assert_false(u.explicatio_drill_active(), "and ends the drill")


## A later reshape that re-deals the files, a duplicatio, takes the roles away: they belonged to
## the files the explicatio dealt.
func test_a_duplicatio_after_the_drill_takes_the_roles_away() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	var walk: Dictionary = await _walk(u, DRILL_TICKS)
	assert_gte(walk["ended"], 0, "precondition: the drill ended")
	assert_eq(_count_role(u, UnitFormation.SoldierRole.HEMILOCHITES), 9,
		"precondition: the hemilochitai still lead their files")
	_battle.enqueue_file_double([u.uid], -1)
	u.formation_slots(u.soldiers)
	assert_eq(_count_role(u, UnitFormation.SoldierRole.HEMILOCHITES), 0, "nobody leads a column")


# --- The alternate-rank drill, live -----------------------------------------------


## The alternate-rank drill, chosen on the order: every second man steps into the interval beside
## the man who stood ahead of him, led by the epistates, without anyone passing the man ahead of
## him or two men coming within a body radius of each other, and the drill ends with the files
## doubled. Its front holds as the half-file drill's does, to a quarter of a rank pitch: each
## epistates comes up only while nobody of another file stands in his lane. Measuring the interval
## between the file leaders instead let each one come up from one rank behind his file leader
## while the line was still opening, overshoot, and step back, the front running up to 5.0 wu
## ahead.
func test_the_alternate_rank_drill_keeps_its_columns() -> void:
	for anchor in [UnitFormation.Anchor.CENTRE, UnitFormation.Anchor.RIGHT,
			UnitFormation.Anchor.LEFT]:
		var units: Array = await _stage([_spearmen()])
		var u: Unit = units[0]
		var floor_wu: float = u.soldier_body_radius()
		_battle.enqueue_file_double([u.uid], 1, anchor, ALTERNATE_RANK)
		assert_eq(_count_role(u, UnitFormation.SoldierRole.EPISTATES), 9,
			"one epistates for each old file")
		assert_eq(_count_role(u, UnitFormation.SoldierRole.HEMILOCHITES), 0, "and no hemilochites")
		var walk: Dictionary = await _walk(u, DRILL_TICKS)
		assert_gte(walk["ended"], 0, "anchor %d: the drill ended" % anchor)
		assert_eq(UnitFormation.frontage(u), 18, "the explicatio doubled 9 files to 18")
		assert_lt(walk["overtake"], 0.25 * u.rank_pitch_wu(), "anchor %d: the farthest any man "
				% anchor + "got ahead of the man ahead of him is %.2f wu" % walk["overtake"])
		assert_gte(walk["closest"], floor_wu,
			"anchor %d: the nearest two men came within %.2f wu" % [anchor, walk["closest"]])
		assert_lt(walk["ahead"], 0.25 * u.rank_pitch_wu(),
			"anchor %d: the front went %.2f wu ahead" % [anchor, walk["ahead"]])
		assert_lt(walk["end_line"], 0.25 * u.rank_pitch_wu(),
			"anchor %d: a man of the front rank ended %.2f wu off its line" % [anchor, walk["end_line"]])
		assert_gt(walk["behind"], -0.25 * u.rank_pitch_wu(),
			"anchor %d: the front fell %.2f wu back" % [anchor, -walk["behind"]])
		await _free_battle()


## The drill rides the recorded order: the replay entry carries it, and a combo's widen step
## carries it through Order.to_dict and back. An order or a replay saved before the drill
## carries none, and its widen plays back as the lateral deal it was.
func test_the_drill_rides_the_order_and_the_replay() -> void:
	var entry: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18,
			INF, 0, 0.0, -1, 0, 0, -1, -1, 0, ALTERNATE_RANK)
	assert_eq(entry["explicatio"], ALTERNATE_RANK, "the replay entry names the drill")
	var plain: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18)
	assert_false(plain.has("explicatio"), "a plain resize records no drill")
	var Decoder := preload("res://scripts/ReplayDecoder.gd")
	assert_eq(Decoder._decode_order({"units": [1], "explicatio": ALTERNATE_RANK})["explicatio"],
		ALTERNATE_RANK, "playback reads the drill back")
	assert_false(Decoder._decode_order({"units": [1]}).has("explicatio"),
		"a replay from before the drill plays back no drill")
	var step := Order.new_file_double(1, ALTERNATE_RANK)
	assert_eq(Order.from_dict(step.to_dict()).explicatio_drill, ALTERNATE_RANK,
		"a combo step keeps its drill through a snapshot")
	assert_eq(Order.new_file_double(1).explicatio_drill, HALF_FILE, "the half-file by default")
	var old: Dictionary = step.to_dict()
	old.erase("explicatio_drill")
	assert_eq(Order.from_dict(old).explicatio_drill, UnitFormation.ExplicatioDrill.NONE,
		"an order saved before the drill resumes as the lateral deal")


# --- The pure primitives ---------------------------------------------------------


func test_the_half_file_deal_keeps_the_front_halves_and_sends_the_rear_up_the_lanes() -> void:
	# Two files of four, index order: file 0 ranks 0-3, then file 1 ranks 0-3.
	var files := PackedInt32Array([0, 0, 0, 0, 1, 1, 1, 1])
	var d: Dictionary = UnitFormation.explicatio_assignment(files, PackedInt32Array(), 2, 0)
	assert_eq(d["files"], PackedInt32Array([0, 0, 1, 1, 2, 2, 3, 3]))
	assert_eq(d["ranks"], PackedInt32Array([0, 1, 0, 1, 0, 1, 0, 1]),
		"the front half keeps ranks 0-1; old rank 2, the half-file leader, leads the new file")
	var hl: int = UnitFormation.SoldierRole.HEMILOCHITES
	assert_eq(d["roles"], PackedByteArray([0, 0, hl, 0, 0, 0, hl, 0]),
		"old rank 2 of each file is its hemilochites")
	var left: Dictionary = UnitFormation.explicatio_assignment(files, PackedInt32Array(), 2, 2)
	assert_eq(left["files"], PackedInt32Array([1, 1, 0, 0, 3, 3, 2, 2]),
		"with every lane on the left the front half takes 2k + 1")
	var wings: Dictionary = UnitFormation.explicatio_assignment(files, PackedInt32Array(), 2, 1)
	assert_eq(wings["files"], PackedInt32Array([1, 1, 0, 0, 2, 2, 3, 3]),
		"split at 1: file 0's lane opens on its left, file 1's on its right")


func test_the_half_file_deal_reads_explicit_ranks_and_splits_each_file_by_its_length() -> void:
	# File 0 holds 5 men listed rear to front; file 1 has lost one, holding 3.
	var files := PackedInt32Array([0, 0, 0, 0, 0, 1, 1, 1])
	var ranks := PackedInt32Array([4, 3, 2, 1, 0, 2, 1, 0])
	var d: Dictionary = UnitFormation.explicatio_assignment(files, ranks, 2, 0)
	# File 0: h = 3, so ranks 0-2 stay in file 0 and ranks 3-4 go to file 1 as ranks 0-1.
	# File 1: h = 2, so ranks 0-1 stay in file 2 and rank 2 goes to file 3 as rank 0.
	assert_eq(d["files"], PackedInt32Array([1, 1, 0, 0, 0, 3, 2, 2]))
	assert_eq(d["ranks"], PackedInt32Array([1, 0, 2, 1, 0, 0, 1, 0]))


func test_the_alternate_rank_deal_sends_every_second_man_beside_the_man_ahead() -> void:
	# One file of five: ranks 0-4 in index order.
	var files := PackedInt32Array([0, 0, 0, 0, 0])
	var d: Dictionary = UnitFormation.explicatio_assignment(files, PackedInt32Array(), 1, 0,
			ALTERNATE_RANK)
	assert_eq(d["files"], PackedInt32Array([0, 1, 0, 1, 0]),
		"ranks 1 and 3 step into the interval on the right")
	assert_eq(d["ranks"], PackedInt32Array([0, 0, 1, 1, 2]),
		"each beside the man who stood ahead of him")
	var ep: int = UnitFormation.SoldierRole.EPISTATES
	assert_eq(d["roles"], PackedByteArray([0, ep, 0, 0, 0]), "old rank 1 is the epistates")


func test_the_deal_refuses_inputs_that_do_not_line_up() -> void:
	assert_true((UnitFormation.explicatio_assignment(PackedInt32Array([0, 2]), PackedInt32Array(),
		2)["files"] as PackedInt32Array).is_empty(), "a file id beyond the old files")
	assert_true((UnitFormation.explicatio_assignment(PackedInt32Array(), PackedInt32Array(),
		2)["files"] as PackedInt32Array).is_empty(), "no men")
	assert_true((UnitFormation.explicatio_assignment(PackedInt32Array([0]), PackedInt32Array(),
		1, 0, UnitFormation.ExplicatioDrill.NONE)["files"] as PackedInt32Array).is_empty(),
		"no drill")


## Aelian 33: held on the left every interval opens on the right and the left corner file
## stands; held on the right the mirror; about the middle each wing opens outward and the file
## next to the middle on the right stands.
func test_the_held_flank_chooses_the_lanes_and_the_file_that_stands() -> void:
	assert_eq(UnitFormation.explicatio_lane_split(9, -1), 0)
	assert_eq(UnitFormation.explicatio_stand_old_file(9, -1), 0)
	assert_eq(UnitFormation.explicatio_lane_split(9, 1), 9)
	assert_eq(UnitFormation.explicatio_stand_old_file(9, 1), 8)
	assert_eq(UnitFormation.explicatio_lane_split(9, 0), 4)
	assert_eq(UnitFormation.explicatio_stand_old_file(9, 0), 4)
	assert_eq(UnitFormation.explicatio_lane_split(6, 0), 3)
	assert_eq(UnitFormation.explicatio_stand_old_file(6, 0), 3)
	# Split at 3: old files 0-2 stay in 1, 3, 5; old files 3-5 in 6, 8, 10.
	for f in [1, 3, 5, 6, 8, 10]:
		assert_true(UnitFormation.explicatio_file_stays(f, 3), "file %d stays" % f)
	for f in [0, 2, 4, 7, 9, 11]:
		assert_false(UnitFormation.explicatio_file_stays(f, 3), "file %d is an interval" % f)


## Six files after the deal, every lane on the right: 0, 2, 4 stay and 1, 3, 5 are intervals;
## file 2 stands. Each file holds two ranks, and each interval's leader holds the role.
func test_the_follow_plan_names_whom_each_man_follows() -> void:
	var files := PackedInt32Array([0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
	var ranks := PackedInt32Array([0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1])
	var hl: int = UnitFormation.SoldierRole.HEMILOCHITES
	var roles := PackedByteArray([0, 0, hl, 0, 0, 0, hl, 0, 0, 0, hl, 0])
	var p: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, roles, 0, 2, 9.0, 8.0)
	var leaders: PackedInt32Array = p["leaders"]
	var offsets: PackedVector2Array = p["offsets"]
	for i in [1, 3, 5, 7, 9, 11]:
		assert_eq(leaders[i], i - 1, "man %d follows the man ahead of him" % i)
		assert_eq(offsets[i], Vector2(0, 8), "a rank pitch behind him")
	assert_eq(leaders[4], SoldierFollow.STAND, "the leader of the standing file holds his ground")
	assert_eq(leaders[0], 4, "file 0's leader dresses on file 2's")
	assert_eq(offsets[0], Vector2(-18, 0), "two file pitches to his left, level")
	assert_eq(leaders[8], 4, "file 4's leader dresses on file 2's")
	assert_eq(offsets[8], Vector2(18, 0), "two file pitches to his right, level")
	assert_eq(leaders[2], 0, "file 1's leader comes up beside file 0's, the file he opened from")
	assert_eq(offsets[2], Vector2(9, 0), "one file pitch to his right, level")
	assert_eq(leaders[10], 8, "file 5's leader comes up beside file 4's")
	var guides: PackedInt32Array = p["guides"]
	for i in [0, 2, 6, 8, 10]:
		assert_eq(guides[i], 4, "file leader %d dresses on the guide himself" % i)
	assert_eq(guides[4], SoldierFollow.STAND, "the guide dresses on no one")
	for i in [1, 3, 5, 7, 9, 11]:
		assert_eq(guides[i], SoldierFollow.NOT_FOLLOWING, "man %d dresses on no guide" % i)
	roles[6] = UnitFormation.SoldierRole.NONE
	p = UnitFormation.explicatio_follow_plan(files, ranks, roles, 0, 2, 9.0, 8.0)
	assert_eq(p["leaders"][6], SoldierFollow.HOLD,
		"the head of an interval without the role leads nobody and holds")
	assert_eq(p["leaders"][7], 6, "his file still follows him")


## Two wings split at old file 1 of 2: file 0 of the left wing stays in new file 1 with its
## interval 0 on its left, file 1 of the right wing in 2 with its interval 3 on its right; file 2
## stands.
func test_the_follow_plan_opens_each_wing_outward() -> void:
	var files := PackedInt32Array([0, 1, 2, 3])
	var ranks := PackedInt32Array([0, 0, 0, 0])
	var hl: int = UnitFormation.SoldierRole.HEMILOCHITES
	var roles := PackedByteArray([hl, 0, 0, hl])
	var p: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, roles, 1, 2, 9.0, 8.0)
	assert_eq(p["leaders"][2], SoldierFollow.STAND, "file 2 stands")
	assert_eq(p["leaders"][1], 2, "file 1, beside it, dresses on it")
	assert_eq(p["offsets"][1], Vector2(-9, 0), "one file pitch to his left")
	assert_eq(p["leaders"][0], 1, "interval 0 comes up on file 1's left")
	assert_eq(p["offsets"][0], Vector2(-9, 0))
	assert_eq(p["leaders"][3], 2, "interval 3 comes up on file 2's right")
	assert_eq(p["offsets"][3], Vector2(9, 0))


func test_the_follow_plan_skips_a_fallen_link() -> void:
	# File 2's leader has fallen and nobody closed up: file 0's leader dresses on file 4's,
	# which stands, four pitches off.
	var files := PackedInt32Array([0, 2, 4])
	var ranks := PackedInt32Array([0, 1, 0])
	var roles := PackedByteArray([0, 0, 0])
	var p: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, roles, 0, 4, 9.0, 8.0)
	assert_eq(p["leaders"][0], 2, "the next file leader along the chain")
	assert_eq(p["offsets"][0], Vector2(-36, 0))
	assert_eq(p["leaders"][1], SoldierFollow.HOLD, "a man with nobody ahead of him holds")
	assert_true((UnitFormation.explicatio_follow_plan(files, PackedInt32Array([0]), roles, 0, 4,
		9.0, 8.0)["leaders"] as PackedInt32Array).is_empty(), "ranks that do not line up")
	assert_true((UnitFormation.explicatio_follow_plan(files, ranks, PackedByteArray(), 0, 4,
		9.0, 8.0)["leaders"] as PackedInt32Array).is_empty(), "roles that do not line up")


func test_successor_reads_the_file_order() -> void:
	var files := PackedInt32Array([1, 1, 0, 1])
	var ranks := PackedInt32Array([2, 0, 0, 1])
	assert_eq(UnitFormation.successor_in_file(files, ranks, 1, 1, 0), 3,
		"the man now at the fallen man's rank")
	assert_eq(UnitFormation.successor_in_file(files, ranks, 0, 1, 0), -1, "nobody behind him")
	assert_eq(UnitFormation.successor_in_file(PackedInt32Array([0, 1, 0]), PackedInt32Array(),
		0, -1, 1), 2, "without ranks, the next man of his file in index order")
	assert_eq(UnitFormation.successor_in_file(PackedInt32Array([0, 1, 0]), PackedInt32Array(),
		1, -1, 2), -1, "without ranks, nobody of his file after him")


# --- SoldierFollow ---------------------------------------------------------------


func test_a_place_is_the_leader_plus_the_offset_in_the_followers_frame() -> void:
	# Facing south (+y): his right is west (-x), behind him is north (-y).
	assert_eq(SoldierFollow.place(Vector2(10, 10), Vector2(9, 0), Vector2(0, 1)), Vector2(1, 10))
	assert_eq(SoldierFollow.place(Vector2(10, 10), Vector2(0, 8), Vector2(0, 1)), Vector2(10, 2))
	# Facing east (+x): his right is south (+y).
	assert_eq(SoldierFollow.place(Vector2(10, 10), Vector2(9, 8), Vector2(1, 0)), Vector2(2, 19))


func test_places_read_leaders_points_and_holds() -> void:
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(0, -8), Vector2(5, 5), Vector2(7, 7)])
	var face := PackedVector2Array([Vector2(0, 1), Vector2(0, 1), Vector2(0, 1), Vector2(0, 1)])
	var leaders := PackedInt32Array([SoldierFollow.STAND, 0, SoldierFollow.HOLD,
			SoldierFollow.NOT_FOLLOWING])
	var offsets := PackedVector2Array([Vector2.ZERO, Vector2(0, 8), Vector2.ZERO, Vector2.ZERO])
	var points := PackedVector2Array([Vector2(1, 1), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var out: PackedVector2Array = SoldierFollow.places(pos, face, leaders, offsets, points)
	assert_eq(out[0], Vector2(1, 1), "a man who stands holds his point")
	assert_eq(out[1], Vector2(0, -8), "a follower a rank behind his leader")
	assert_eq(out[2], Vector2(5, 5), "a man who holds stays where he is")
	assert_eq(out[3], Vector2(7, 7), "a man not following is placed where he stands")
	assert_true(SoldierFollow.places(pos, PackedVector2Array(), leaders, offsets).is_empty(),
		"arrays that do not line up")


func test_a_file_leader_dresses_on_the_guide_where_he_stands() -> void:
	# Facing south (+y). The guide (man 0) has run 3 ahead of his point; man 1 follows man 2, who
	# stands level with the point, but dresses on the guide's body, so he takes the guide's depth.
	var pos := PackedVector2Array([Vector2(0, 3), Vector2(20, 0), Vector2(30, 0)])
	var face := PackedVector2Array([Vector2(0, 1), Vector2(0, 1), Vector2(0, 1)])
	var leaders := PackedInt32Array([SoldierFollow.STAND, 2, SoldierFollow.HOLD])
	var offsets := PackedVector2Array([Vector2.ZERO, Vector2(-9, 0), Vector2.ZERO])
	var points := PackedVector2Array([Vector2(0, 0), Vector2.ZERO, Vector2.ZERO])
	var guides := PackedInt32Array([SoldierFollow.STAND, 0, SoldierFollow.NOT_FOLLOWING])
	var out: PackedVector2Array = SoldierFollow.places(pos, face, leaders, offsets, points, guides)
	assert_eq(out[1], Vector2(39, 3), "level with the guide's body")
	guides[1] = SoldierFollow.STAND
	out = SoldierFollow.places(pos, face, leaders, offsets, points, guides)
	assert_eq(out[1], Vector2(39, 0), "dressing on the guide's old point, not on him")
	guides[1] = SoldierFollow.NOT_FOLLOWING
	out = SoldierFollow.places(pos, face, leaders, offsets, points, guides)
	assert_eq(out[1], Vector2(39, 0), "no guide: level with his own leader")


func test_a_man_steps_onto_the_line_before_closing_along_it() -> void:
	var f := Vector2(0, 1)   # facing south; along = +y, across = x
	assert_eq(SoldierFollowSteer.steer_point(Vector2(0, 0), f, Vector2(9, 20), 9.0), Vector2(9, 0),
		"a file pitch off the line: across only")
	assert_eq(SoldierFollowSteer.steer_point(Vector2(0, 0), f, Vector2(4.5, 20), 9.0), Vector2(4.5, 10),
		"half a pitch off: half the step along")
	assert_eq(SoldierFollowSteer.steer_point(Vector2(0, 0), f, Vector2(0, 20), 9.0), Vector2(0, 20),
		"on the line: all of it")
	assert_eq(SoldierFollowSteer.steer_point(Vector2(0, 0), f, Vector2(0, 20), 9.0, 0.25),
		Vector2(0, 5), "a quarter of the gap open: a quarter of the step along")
	assert_eq(SoldierFollowSteer.steer_point(Vector2(0, 0), f, Vector2(9, 20), 0.0), Vector2(9, 20),
		"no line width: straight for it")
	assert_eq(SoldierFollowSteer.steer_point(Vector2(0, 0), f, Vector2(9, -20), 9.0, 0.0),
		Vector2(9, -20), "falling back: straight for it, gap or no gap")


## A man at (0, 0) of file 0, facing south, comes up the line x = 0 to (0, 40): the men in his
## lane are those of other files less than `clear` off it, from a body radius behind him to a rank
## pitch (9) ahead. `clear` is the lesser of a body's width and the pitch less the settle
## distance: 9 in a loose order (here), 8 at the 9 wu pitch, 5.75 in a 6.75 wu shield wall.
func test_lane_blockers_are_the_men_in_his_lane() -> void:
	var f := Vector2(0, 1)
	var line := Vector2(0, 40)
	var men := PackedVector2Array([Vector2(0, 0), Vector2(0, -9), Vector2(8.9, 5),
			Vector2(-9, 5), Vector2(3, 20), Vector2(2, -6), Vector2(-27, 4), Vector2(5, 3)])
	var files := PackedInt32Array([0, 0, 1, 1, 1, 1, 1, 1])   # men 0 and 1: his own column
	var all := PackedInt32Array(range(men.size()))
	var out: PackedInt32Array = SoldierFollowSteer.lane_blockers(men[0], f, line, men, all, files,
			0, 9.0, 9.0, 4.5)
	assert_eq(out, PackedInt32Array([2, 7]),
		"8.9 and 5 off the line level with him block; 9 and 27 off do not, nor a man 20 ahead "
		+ "or 6 behind, nor his own column")
	out = SoldierFollowSteer.lane_blockers(men[0], f, line, men, all, files, 0, 5.75, 9.0, 4.5)
	assert_eq(out, PackedInt32Array([7]), "shield wall: only the man 5 off, inside its clearance")
	assert_eq(SoldierFollowSteer.lane_blockers(men[0], f, line, men, PackedInt32Array([2, 3]),
			files, 0, 9.0, 9.0, 4.5), PackedInt32Array([2]), "only the candidates he is handed")


## Of the files that stay and have a leader, the guide's is the nearest the file that stood, the
## lower of a tie; the file that stood while it still has a leader; none when no file that stays
## has one. Split at 0, so the even files stay.
func test_the_guide_passes_to_the_nearest_staying_file_the_lower_of_a_tie() -> void:
	assert_eq(UnitFormation.explicatio_guide_file({4: 1, 2: 1, 10: 1}, 4, 0), 4,
		"the file that stood, while it has a leader")
	assert_eq(UnitFormation.explicatio_guide_file({2: 1, 10: 1, 7: 1}, 4, 0), 2,
		"the nearest, not the farthest, and an interval's leader is no guide")
	assert_eq(UnitFormation.explicatio_guide_file({6: 1, 2: 1}, 4, 0), 2, "the lower of a tie")
	assert_eq(UnitFormation.explicatio_guide_file({2: 1, 6: 1}, 4, 0), 2,
		"the lower of a tie, whichever is listed first")
	assert_eq(UnitFormation.explicatio_guide_file({1: 1, 3: 1}, 4, 0), -1,
		"no file that stays has a leader")


## With no file that stays left a leader to be the guide, the drill says so and ends, with the
## grid laid on the men where they stand: the front rank does not dress on ground no man holds.
func test_a_drill_with_no_guide_left_says_so_and_ends() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	await get_tree().physics_frame
	for i in range(u.soldiers):
		if _stays(u, i) and u._sim_soldier_rank[i] == 0:
			u._sim_soldier_rank[i] = 99   # no file that stays has a man at its head
	u._explicatio_follow_frame = -1
	var reading: Vector2 = u.explicatio_grid_position()
	u._advance_explicatio_drill()
	assert_push_error("no file that stays has a leader", "the missing guide is reported")
	assert_false(u.explicatio_drill_active(), "the drill ended")
	assert_almost_eq(u.position.x, reading.x, 0.01, "the grid is laid on the men")
	assert_almost_eq(u.position.y, reading.y, 0.01, "the grid is laid on the men")


## The drill reads the room off the men's bodies, not the pitch, so it plays out in close order
## (the Spearmen's own, a 9 wu pitch), in a looser and in a closer order: it ends, the files
## doubled. Its lane is the lesser of a body's width and the pitch less REFORM_SETTLE_EPS: 8 wu at
## the 9 wu pitch, 9 wu in normal order's 18 wu pitch, 5.75 wu in a shield wall's 6.75 wu. In
## normal order no two men come within a body radius of each other; in close order and in the
## shield wall, closer than two bodies' radii, the bound is the demo scan's overlap floor (2.25 wu),
## for the reason test_no_two_men_come_onto_each_other gives.
func test_the_drill_plays_out_in_close_loose_order_and_a_shield_wall() -> void:
	var lanes := {Unit.FORMATION_TIGHT: 8.0, Unit.FORMATION_NORMAL: 9.0,
			Unit.FORMATION_SHIELD_WALL: 5.75}
	for mode in [Unit.FORMATION_TIGHT, Unit.FORMATION_NORMAL, Unit.FORMATION_SHIELD_WALL]:
		var units: Array = await _stage([_spearmen()])
		var u: Unit = units[0]
		u.set_formation(mode)
		await _run(DRILL_TICKS)
		assert_almost_eq(u.file_pitch_wu(), 9.0 * Unit.spacing_scale_for_mode(mode), 0.01,
			"precondition: mode %d stands at its pitch" % mode)
		var files: int = UnitFormation.frontage(u)
		assert_almost_eq(u.follow_line_width(),
				minf(u.file_pitch_wu(), 2.0 * u.soldier_body_radius()), 0.001,
				"mode %d: a man clears his line by a body's width, or the pitch if closer" % mode)
		assert_almost_eq(u.explicatio_lane_clear(), float(lanes[mode]), 0.001,
			"mode %d: the lane's half-width" % mode)
		_battle.enqueue_file_double([u.uid], 1)
		assert_true(u.explicatio_drill_active(), "mode %d: the widen is the drill" % mode)
		var walk: Dictionary = await _walk(u, 2 * DRILL_TICKS)
		assert_gte(walk["ended"], 0, "mode %d: the drill ended" % mode)
		assert_eq(UnitFormation.frontage(u), 2 * files, "mode %d: the files doubled" % mode)
		# TODO(#1974): one body radius in close order and the shield wall too, which measure
		# 4.44 and 3.75 wu, once men avoid each other body to body.
		var floor_wu: float = u.soldier_body_radius() if mode == Unit.FORMATION_NORMAL \
				else 2.0 * u.soldier_body_radius() * DemoDefects.OVERLAP_BODY_FRAC
		assert_gte(walk["closest"], floor_wu,
			"mode %d: the nearest two men came within %.2f wu" % [mode, walk["closest"]])
		await _free_battle()
