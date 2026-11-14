extends GutTest
## The duplicatio as the explicatio in reverse (DuplicatioDrill): a block whose files an
## explicatio dealt halves its front by sending the men who went up the intervals back to the
## stations they left (Asclepiodotus 10.20, Aelian 29.3). The front rank holds its line, the men
## of each interval fall back down it and step in behind the man they will follow, and nobody
## walks to a slot. A block with no explicatio to undo keeps the lateral deal.

const SPAWN := Vector2(500, 300)
const SPEARMEN := 140
const DRILL_TICKS := 1200
const HALF_FILE := UnitFormation.ExplicatioDrill.HALF_FILE
const ALTERNATE_RANK := UnitFormation.ExplicatioDrill.ALTERNATE_RANK
const CENTRE := UnitFormation.Anchor.CENTRE
const OUTWARD := UnitFormation.ExplicatioSide.OUTWARD
const LENGTHEN := UnitFormation.ExplicatioGround.LENGTHEN
const SAME_GROUND := UnitFormation.ExplicatioGround.SAME_GROUND

var _battle: Node = null


func after_each() -> void:
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _stage() -> Unit:
	Replay.forced_seed = 1966
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
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


## Run the drill under way to its end, or `ticks` ticks; the tick it ended, -1 if it did not.
func _settle(u: Unit, ticks: int = DRILL_TICKS) -> int:
	for t in range(ticks):
		await get_tree().physics_frame
		if not u.explicatio_drill_active():
			return t
	return -1


func _front(u: Unit) -> float:
	var best: float = -INF
	for p in u._sim_soldier_pos:
		best = maxf(best, p.dot(u.facing))
	return best


# --- The deal back -----------------------------------------------------------------------


## The deal back of either drill's deal is the block it was dealt from: every man returns to his
## old file and rank, and the men of the intervals are the ones who return.
func test_the_deal_back_undoes_each_drill() -> void:
	var files := PackedInt32Array()
	var ranks := PackedInt32Array()
	for k in range(4):
		for r in range(7):
			files.append(k)
			ranks.append(r)
	for drill in [HALF_FILE, ALTERNATE_RANK]:
		for split in [0, 2, 4]:
			var dealt: Dictionary = UnitFormation.explicatio_assignment(files, ranks, 4, split, drill)
			var back: Dictionary = DuplicatioDrill.reverse_assignment(dealt["files"],
					dealt["ranks"], dealt["roles"], 4, split, false)
			assert_eq(back["files"], files, "drill %d split %d: the old files" % [drill, split])
			assert_eq(back["ranks"], ranks, "drill %d split %d: the old ranks" % [drill, split])
			assert_eq(back["drill"], drill, "drill %d: read off the roles" % drill)
			var returning: PackedByteArray = back["returning"]
			for i in range(files.size()):
				var stays: bool = UnitFormation.explicatio_file_stays(
						(dealt["files"] as PackedInt32Array)[i], split)
				assert_eq(returning[i], 0 if stays else 1, "drill %d: man %d returns" % [drill, i])


## A file a casualty has shortened still deals back into one unbroken file.
func test_the_deal_back_closes_a_shortened_file() -> void:
	# Old file 0's interval opens on its right (split 0): file 0 stays, file 1 is its interval.
	var files := PackedInt32Array([0, 0, 0, 1])
	var ranks := PackedInt32Array([0, 1, 2, 0])
	var roles := PackedByteArray([0, 0, 0, UnitFormation.SoldierRole.EPISTATES])
	var back: Dictionary = DuplicatioDrill.reverse_assignment(files, ranks, roles, 1, 0, false)
	assert_eq(back["ranks"], PackedInt32Array([0, 2, 3, 1]), "alternate: the file and interval interleave")
	roles[3] = UnitFormation.SoldierRole.HEMILOCHITES
	back = DuplicatioDrill.reverse_assignment(files, ranks, roles, 1, 0, false)
	assert_eq(back["ranks"], PackedInt32Array([0, 1, 2, 3]), "half-file: the interval falls in behind")


## Only an explicatio's own deal is undone: no man with a role, a role off the head of an
## interval, a role in a file that stayed, or a file out of range is not one.
func test_the_deal_back_refuses_what_no_explicatio_dealt() -> void:
	var files := PackedInt32Array([0, 1, 1])
	var ranks := PackedInt32Array([0, 0, 1])
	var hemi: int = UnitFormation.SoldierRole.HEMILOCHITES
	for case in [[PackedByteArray([0, 0, 0]), files, "no roles"],
			[PackedByteArray([0, 0, hemi]), files, "a role off the head"],
			[PackedByteArray([hemi, 0, 0]), files, "a role in a file that stayed"],
			[PackedByteArray([0, hemi, 0]), PackedInt32Array([0, 1, 2]), "a file out of range"]]:
		var back: Dictionary = DuplicatioDrill.reverse_assignment(case[1], ranks, case[0], 1, 0,
				false)
		assert_true(back.is_empty(), case[2])
	assert_true(DuplicatioDrill.reverse_assignment(PackedInt32Array(), PackedInt32Array(),
			PackedByteArray(), 1, 0, false).is_empty(), "no men")
	assert_eq(Unit.nearest_led_file({}, 3), -1, "no leader, no file")
	assert_eq(Unit.nearest_led_file({2: 0, 4: 1}, 3), 2, "the lower of a tie")


## Every file closes on the file that stands: its leader holds his ground, each other leader
## follows the next one toward it a file pitch across, and every man behind follows the man
## ahead of him a rank pitch behind.
func test_the_follow_plan_closes_on_the_file_that_stands() -> void:
	var files := PackedInt32Array([0, 1, 2, 2, 0])
	var ranks := PackedInt32Array([0, 0, 0, 1, 2])
	var plan: Dictionary = DuplicatioDrill.follow_plan(files, ranks, 1, 9.0, 8.0)
	assert_eq(plan["leaders"], PackedInt32Array([1, SoldierFollow.STAND, 1, 2, 0]), "leaders")
	assert_eq(plan["offsets"][0], Vector2(-9.0, 0.0), "left of the guide's file")
	assert_eq(plan["offsets"][2], Vector2(9.0, 0.0), "right of it")
	assert_eq(plan["offsets"][4], Vector2(0.0, 16.0), "two ranks behind past a gap")
	assert_eq(plan["guides"], PackedInt32Array([1, SoldierFollow.STAND, 1,
			SoldierFollow.NOT_FOLLOWING, SoldierFollow.NOT_FOLLOWING]), "leaders dress on the guide")


# --- Live --------------------------------------------------------------------------------


## B then N: the men who went up go back, the files close, and the block stands as it stood.
## The front rank holds its line, no man of the files that stayed steps forward, the men of each
## interval keep their order as they fall back, and nobody comes within a body radius of another.
func test_the_duplicatio_undoes_the_explicatio() -> void:
	for drill in [HALF_FILE, ALTERNATE_RANK]:
		var u: Unit = await _stage()
		var start_files: PackedInt32Array = u._sim_soldier_file.duplicate()
		var width0: float = u.file_pitch_wu() * 8.0
		_battle.enqueue_file_double([u.uid], 1, CENTRE, drill)
		assert_gte(await _settle(u), 0, "drill %d: precondition: the explicatio ended" % drill)
		var front0: float = _front(u)
		var stayed0: PackedVector2Array = u._sim_soldier_pos.duplicate()
		# Each man of an interval and the man ahead of him in it, as the explicatio left them.
		var dealt_at: Dictionary = {}
		for i in range(u.soldiers):
			dealt_at[Vector2i(u._sim_soldier_file[i], u._sim_soldier_rank[i])] = i
		var ahead := PackedInt32Array()
		for i in range(u.soldiers):
			ahead.append(int(dealt_at.get(Vector2i(u._sim_soldier_file[i],
					u._sim_soldier_rank[i] - 1), -1)))
		# The N key carries the player's drill choice, here the other one: the roles decide.
		_battle.enqueue_file_double([u.uid], -1, CENTRE,
				ALTERNATE_RANK if drill == HALF_FILE else HALF_FILE)
		assert_true(u._explicatio_reverse, "drill %d: the narrowing is the drill" % drill)
		assert_eq(UnitFormation.frontage(u), 9, "drill %d: 18 files back to 9" % drill)
		assert_eq(int((_battle._pending_orders.back() as Dictionary)["explicatio"]), drill,
			"drill %d: the order records the drill the roles say was done" % drill)
		var returning: PackedByteArray = u._duplicatio_returning.duplicate()
		var worst := {"front": 0.0, "forward": -INF, "order": -INF, "closest": INF, "pairs": 0}
		var ended: int = -1
		for t in range(DRILL_TICKS):
			await get_tree().physics_frame
			worst["front"] = maxf(worst["front"], absf(_front(u) - front0))
			for i in range(u.soldiers):
				if returning[i] == 0:
					worst["forward"] = maxf(worst["forward"],
							(u._sim_soldier_pos[i] - stayed0[i]).dot(u.facing))
				for j in range(i + 1, u.soldiers):
					worst["closest"] = minf(worst["closest"],
							u._sim_soldier_pos[i].distance_to(u._sim_soldier_pos[j]))
			for i in range(u.soldiers):
				var j: int = ahead[i]
				if returning[i] == 1 and j >= 0:
					worst["pairs"] += 1
					worst["order"] = maxf(worst["order"],
							(u._sim_soldier_pos[i] - u._sim_soldier_pos[j]).dot(u.facing))
			if not u.explicatio_drill_active():
				ended = t
				break
		var what: String = "drill %d" % drill
		assert_gte(ended, 0, "%s: the duplicatio ended" % what)
		assert_lt(worst["front"], 0.25 * u.rank_pitch_wu(),
			"%s: the front moved %.2f wu" % [what, worst["front"]])
		assert_lt(worst["forward"], 0.25 * u.rank_pitch_wu(),
			"%s: a man who stayed stepped %.2f wu forward" % [what, worst["forward"]])
		assert_gt(worst["pairs"], 0, "%s: precondition: the column order was read" % what)
		assert_lt(worst["order"], 0.0,
			"%s: a returning man came level with the man ahead of him in his interval" % what)
		assert_gte(worst["closest"], u.soldier_body_radius(),
			"%s: two men came within %.2f wu" % [what, worst["closest"]])
		assert_eq(u._sim_soldier_file, start_files, "%s: every man is back in his file" % what)
		var right: Vector2 = SoldierFollow.right_of(u.facing)
		var lo: float = INF
		var hi: float = -INF
		for p in u._sim_soldier_pos:
			lo = minf(lo, p.dot(right))
			hi = maxf(hi, p.dot(right))
		assert_almost_eq(hi - lo, width0, 0.25 * u.file_pitch_wu(),
			"%s: the line is as long as it was" % what)
		assert_true(u._sim_soldier_role.is_empty(), "%s: the roles are gone" % what)
		await _free_battle()


## Every man covers his file leader: his place's line across his front is the leader's place's,
## even where the man he follows still stands in an interval (every second man, where each man of
## the file follows a man of the interval).
func test_each_man_covers_his_file_leader() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, CENTRE, ALTERNATE_RANK)
	assert_gte(await _settle(u), 0, "precondition: the explicatio ended")
	_battle.enqueue_file_double([u.uid], -1, CENTRE, ALTERNATE_RANK)
	await get_tree().physics_frame
	assert_true(u._refresh_explicatio_follow(u.soldiers), "precondition: the reverse runs")
	var places: PackedVector2Array = u._explicatio_places
	var head: Dictionary = {}
	for i in range(u.soldiers):
		if u._sim_soldier_rank[i] == 0:
			head[u._sim_soldier_file[i]] = i
	var worst: float = 0.0
	for i in range(u.soldiers):
		var right: Vector2 = SoldierFollow.right_of(u._sim_soldier_facing[i].normalized())
		var h: int = head[u._sim_soldier_file[i]]
		worst = maxf(worst, absf((places[i] - places[h]).dot(right)))
	assert_lt(worst, 0.01, "a man's place stood %.2f wu off his file leader's line" % worst)


## On the same ground the men of the intervals go back out of the gaps and the block opens one
## order, the files that stayed keeping their places (Asclepiodotus 10.20 on 10.17).
func test_the_same_ground_opens_the_order() -> void:
	var u: Unit = await _stage()
	u.set_formation(Unit.FORMATION_NORMAL)
	await _settle(u, 600)
	_battle.enqueue_file_double([u.uid], 1, CENTRE, HALF_FILE, OUTWARD, SAME_GROUND)
	assert_gte(await _settle(u), 0, "precondition: the explicatio ended")
	assert_eq(u.formation_mode, Unit.FORMATION_TIGHT, "precondition: closed one order")
	var right: Vector2 = SoldierFollow.right_of(u.facing)
	var across0: Dictionary = {}
	for i in range(u.soldiers):
		if u._sim_soldier_rank[i] == 0 and u._sim_soldier_role[i] == 0 \
				and UnitFormation.explicatio_file_stays(u._sim_soldier_file[i],
				u._explicatio_lane_split):
			across0[i] = u._sim_soldier_pos[i].dot(right)
	_battle.enqueue_file_double([u.uid], -1, CENTRE, HALF_FILE, OUTWARD, SAME_GROUND)
	assert_eq(u.formation_mode, Unit.FORMATION_NORMAL, "the block opens one order")
	assert_gte(await _settle(u), 0, "the duplicatio ended")
	var drift: float = 0.0
	for i in across0:
		drift = maxf(drift, absf(u._sim_soldier_pos[i].dot(right) - across0[i]))
	assert_lt(drift, 0.25 * u.file_pitch_wu(), "a file leader moved %.2f wu across" % drift)
	assert_eq(Unit.sparser_formation_mode(Unit.FORMATION_LOOSE), -1, "open order opens no further")
	assert_eq(Unit.sparser_formation_mode(Unit.FORMATION_NORMAL), Unit.FORMATION_LOOSE,
		"compact opens into open order")


## A man who falls while the files go back leaves the drill running: the man behind him closes
## up, and the rest still follow the men they can see until the block stands on 9 files.
func test_a_casualty_mid_drill_keeps_the_drill() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, CENTRE, HALF_FILE)
	assert_gte(await _settle(u), 0, "precondition: the explicatio ended")
	_battle.enqueue_file_double([u.uid], -1, CENTRE, HALF_FILE)
	for _t in range(30):
		await get_tree().physics_frame
	var victim: int = -1
	for i in range(u.soldiers):
		if u._duplicatio_returning[i] == 1 and u._explicatio_following[i] == 1:
			victim = i
			break
	assert_gte(victim, 0, "precondition: a man of an interval is still on his way")
	var count: int = u.soldiers
	u._sim_soldier_hp[victim] = 0.0
	SoldierMelee.reap(u, null)
	assert_eq(u.soldiers, count - 1, "precondition: he fell")
	assert_eq(u._duplicatio_returning.size(), u.soldiers, "the drill's own record closes up")
	await get_tree().physics_frame
	assert_true(u.explicatio_drill_active(), "the drill runs on")
	assert_gte(await _settle(u), 0, "and ends")
	assert_eq(UnitFormation.frontage(u), 9, "on 9 files")


## A countermarch since the explicatio turns the block about, so the heads of its intervals stand
## at its rear: the roles go, and N narrows with the lateral deal. Nor is a block undone while an
## about-face's mirror still stands over its files.
func test_a_turned_block_is_not_undone() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, CENTRE, HALF_FILE)
	assert_gte(await _settle(u), 0, "precondition: the explicatio ended")
	assert_true(u.explicatio_undoable(), "precondition: undoable before the turn")
	u._formation_mirror_x = true
	assert_false(u.explicatio_undoable(), "not while the mirror stands")
	u._formation_mirror_x = false
	_battle.enqueue_countermarch([u.uid], Unit.CountermarchVariant.CHORAL)
	var turned: bool = false
	for _t in range(600):
		await get_tree().physics_frame
		turned = turned or u._sim_soldier_role.is_empty()
		if turned and u.state == Unit.State.IDLE and not u.has_move_target:
			break
	assert_true(u._sim_soldier_role.is_empty(), "the countermarch took the roles away")
	assert_false(u.explicatio_undoable(), "nothing left to undo")
	_battle.enqueue_file_double([u.uid], -1)
	assert_false(u.explicatio_drill_active(), "N narrows with the lateral deal")


## A block no explicatio dealt keeps the lateral deal, and its narrowing records no drill.
func test_a_block_with_no_explicatio_keeps_the_lateral_deal() -> void:
	var u: Unit = await _stage()
	assert_false(u.explicatio_undoable(), "precondition: nothing to undo")
	assert_eq(u.explicatio_undo_drill(), UnitFormation.ExplicatioDrill.NONE, "no drill to undo")
	_battle.enqueue_file_double([u.uid], -1)
	assert_false(u.explicatio_drill_active(), "no drill")
	assert_false((_battle._pending_orders.back() as Dictionary).has("explicatio"),
		"the order is the plain narrowing")
