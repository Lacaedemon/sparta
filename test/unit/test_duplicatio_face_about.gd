extends GutTest
## The countermarch reading of the duplicatio that undoes an explicatio (DuplicatioMarch): the men
## who went up the intervals face about where they stand, march back down them with each column's
## rear man leading, and face front again on their stations (Asclepiodotus 10.20, Aelian 29.3:
## "countermarch"). Each man turns through his own facing at CONVERSIO_TURN_RATE, never in a
## snap. Alt+N chooses it; the walk stays the default.

const SelectionManagerScript = preload("res://scripts/SelectionManager.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")
const ReplayOrderEntryScript = preload("res://scripts/ReplayOrderEntry.gd")
const ReplayDecoderScript = preload("res://scripts/ReplayDecoder.gd")

const SPAWN := Vector2(500, 300)
const SPEARMEN := 140
const DRILL_TICKS := 1500
const HALF_FILE := UnitFormation.ExplicatioDrill.HALF_FILE
const ALTERNATE_RANK := UnitFormation.ExplicatioDrill.ALTERNATE_RANK
const CENTRE := UnitFormation.Anchor.CENTRE
const OUTWARD := UnitFormation.ExplicatioSide.OUTWARD
const LENGTHEN := UnitFormation.ExplicatioGround.LENGTHEN
const WALK := DuplicatioMarch.Reading.WALK
const FACE_ABOUT := DuplicatioMarch.Reading.FACE_ABOUT

var _battle: Node = null


## Records what the selection manager tells the HUD.
class StubHud:
	extends RefCounted
	var flashes: Array = []

	func flash_message(text: String) -> void:
		flashes.append(text)

	func show_unit(_u: Node, _count: int) -> void:
		pass

	func clear_unit() -> void:
		pass


func after_each() -> void:
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _stage(count: int = SPEARMEN) -> Unit:
	Replay.forced_seed = 1985
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
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


func _key(keycode: int, alt: bool = true) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.alt_pressed = alt
	return ev


# --- Pure --------------------------------------------------------------------------------


func test_only_a_returning_man_on_his_way_faces_about() -> void:
	assert_true(DuplicatioMarch.faces_about(FACE_ABOUT, true, true), "on his way back")
	assert_false(DuplicatioMarch.faces_about(FACE_ABOUT, true, false), "on his station")
	assert_false(DuplicatioMarch.faces_about(FACE_ABOUT, false, true), "a man who stayed")
	assert_false(DuplicatioMarch.faces_about(WALK, true, true), "the walk faces front")


## A man turns by at most his step, through his right when he faces exactly away, and lands on
## the facing he wants once it is within his step.
func test_a_man_turns_at_his_rate_through_his_right() -> void:
	var front := Vector2(0, 1)
	var turned: Vector2 = DuplicatioMarch.turn_toward(front, -front, 0.1)
	assert_almost_eq(turned.angle_to(front), -0.1, 1e-5, "a tenth of a radian, no more")
	assert_gt(turned.dot(SoldierFollow.right_of(front)), 0.0, "through his right")
	var back: Vector2 = DuplicatioMarch.turn_toward(-front, front, 0.1)
	assert_gt(back.dot(SoldierFollow.right_of(-front)), 0.0, "and through his right again")
	var near := Vector2.from_angle(front.angle() + 0.05)
	assert_eq(DuplicatioMarch.turn_toward(near, front, 0.1), front, "onto the facing within a step")
	var left := Vector2.from_angle(front.angle() - 1.0)
	assert_almost_eq(DuplicatioMarch.turn_toward(left, front, 0.1).angle_to(front), 0.9, 1e-5,
		"the shorter way round")


## A man who went up an interval reads his file's front off his file leader; a man who stayed,
## and a man whose file has no leader, as given.
func test_the_drill_front_is_the_file_leaders() -> void:
	var facings := PackedVector2Array([Vector2(0, 1), Vector2(0, -1), Vector2(1, 0)])
	var fronts: PackedVector2Array = DuplicatioMarch.drill_fronts(facings,
			PackedByteArray([0, 1, 1]), PackedInt32Array([0, 0, -1]), Vector2(0, 1))
	assert_eq(fronts[0], Vector2(0, 1), "the leader his own")
	assert_eq(fronts[1], Vector2(0, 1), "a man turned about reads his leader's")
	assert_eq(fronts[2], Vector2(0, 1), "no leader: the block's")


# --- Live --------------------------------------------------------------------------------


## B then Alt+N's reading with N: every man is back in his file and rank, the line as long as it
## was, the front on its line; each man of an interval faces about on his way and front again on
## his station, and no man's facing turns faster than his turn rate in any tick.
func test_the_countermarch_undoes_the_explicatio() -> void:
	for drill in [HALF_FILE, ALTERNATE_RANK]:
		var u: Unit = await _stage()
		var start_files: PackedInt32Array = u._sim_soldier_file.duplicate()
		var start_ranks: PackedInt32Array = u._sim_soldier_rank.duplicate()
		var width0: float = u.file_pitch_wu() * 8.0
		_battle.enqueue_file_double([u.uid], 1, CENTRE, drill)
		assert_gte(await _settle(u), 0, "drill %d: precondition: the explicatio ended" % drill)
		var front0: float = _front(u)
		_battle.enqueue_file_double([u.uid], -1, CENTRE, drill, OUTWARD, LENGTHEN, FACE_ABOUT)
		assert_true(u._explicatio_reverse, "drill %d: the narrowing is the drill" % drill)
		assert_eq(int((_battle._pending_orders.back() as Dictionary)["duplicatio_march"]),
			FACE_ABOUT, "drill %d: the order records the reading" % drill)
		var returning: PackedByteArray = u._duplicatio_returning.duplicate()
		var turned_about: Dictionary = {}
		var prev: PackedVector2Array = u._sim_soldier_facing.duplicate()
		var worst := {"turn": 0.0, "front": 0.0, "closest": INF}
		var max_step: float = Unit.CONVERSIO_TURN_RATE / float(Engine.physics_ticks_per_second)
		var ended: int = -1
		for t in range(DRILL_TICKS):
			await get_tree().physics_frame
			worst["front"] = maxf(worst["front"], absf(_front(u) - front0))
			for i in range(u.soldiers):
				worst["turn"] = maxf(worst["turn"], absf(prev[i].angle_to(u._sim_soldier_facing[i])))
				if u._sim_soldier_facing[i].dot(u.facing) < -0.99:
					turned_about[i] = true
				for j in range(i + 1, u.soldiers):
					worst["closest"] = minf(worst["closest"],
							u._sim_soldier_pos[i].distance_to(u._sim_soldier_pos[j]))
			prev = u._sim_soldier_facing.duplicate()
			if not u.explicatio_drill_active() and ended < 0:
				ended = t
			if ended >= 0 and not u._duplicatio_facing_owned:
				break
		var what: String = "drill %d" % drill
		assert_gte(ended, 0, "%s: the countermarch ended" % what)
		var about: int = 0
		for i in range(u.soldiers):
			if returning[i] == 1:
				about += 1
				assert_true(turned_about.has(i), "%s: man %d faced about" % [what, i])
			else:
				assert_false(turned_about.has(i), "%s: man %d, who stayed, did not" % [what, i])
		assert_gt(about, 0, "%s: precondition: men went back" % what)
		assert_lte(worst["turn"], max_step + 1e-4,
			"%s: a man turned %.3f rad in a tick" % [what, worst["turn"]])
		assert_lt(worst["front"], 0.25 * u.rank_pitch_wu(),
			"%s: the front moved %.2f wu" % [what, worst["front"]])
		assert_gte(worst["closest"], 0.5 * u.soldier_body_radius(),
			"%s: two men came within %.2f wu" % [what, worst["closest"]])
		assert_false(u._duplicatio_facing_owned, "%s: the facings are handed back" % what)
		assert_false(u._per_soldier_facing, "%s: to the block's heading" % what)
		for i in range(u.soldiers):
			assert_gt(u._sim_soldier_facing[i].dot(u.facing), 0.999, "%s: man %d faces front" % [what, i])
		assert_eq(u._sim_soldier_file, start_files, "%s: every man is back in his file" % what)
		if start_ranks.size() == u.soldiers:
			assert_eq(u._sim_soldier_rank, start_ranks, "%s: and his rank" % what)
		var right: Vector2 = SoldierFollow.right_of(u.facing)
		var lo: float = INF
		var hi: float = -INF
		for p in u._sim_soldier_pos:
			lo = minf(lo, p.dot(right))
			hi = maxf(hi, p.dot(right))
		assert_almost_eq(hi - lo, width0, 0.25 * u.file_pitch_wu(),
			"%s: the line is as long as it was" % what)
		await _free_battle()


## The walk stays the default: N with no reading records none and nobody turns.
func test_the_walk_is_the_default() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, CENTRE, HALF_FILE)
	assert_gte(await _settle(u), 0, "precondition: the explicatio ended")
	_battle.enqueue_file_double([u.uid], -1, CENTRE, HALF_FILE)
	assert_false((_battle._pending_orders.back() as Dictionary).has("duplicatio_march"),
		"the walk is not recorded")
	assert_eq(u._duplicatio_march, WALK, "the men walk")
	assert_false(u._per_soldier_facing, "and keep the block's heading")
	for _t in range(60):
		await get_tree().physics_frame
	for i in range(u.soldiers):
		assert_eq(u._sim_soldier_facing[i], u.facing, "man %d faces front" % i)


## A narrowing that undoes no explicatio ignores the reading: the lateral deal, nobody turns.
func test_a_plain_narrowing_ignores_the_reading() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], -1, CENTRE, HALF_FILE, OUTWARD, LENGTHEN, FACE_ABOUT)
	assert_false((_battle._pending_orders.back() as Dictionary).has("duplicatio_march"),
		"nothing to undo, nothing recorded")
	assert_false(u._explicatio_reverse, "the lateral deal")
	assert_false(u._duplicatio_facing_owned, "nobody turns")


## A countermarch cut short (the block ordered to move) leaves no man turned: each turns on to the
## front at his rate, and the facings go back to the block's heading once all face it.
func test_a_countermarch_cut_short_turns_the_men_front() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, CENTRE, HALF_FILE)
	assert_gte(await _settle(u), 0, "precondition: the explicatio ended")
	_battle.enqueue_file_double([u.uid], -1, CENTRE, HALF_FILE, OUTWARD, LENGTHEN, FACE_ABOUT)
	for _t in range(40):
		await get_tree().physics_frame
	var turned: int = 0
	for i in range(u.soldiers):
		if u._sim_soldier_facing[i].dot(u.facing) < 0.0:
			turned += 1
	assert_gt(turned, 0, "precondition: men stand turned")
	u._end_explicatio_drill()
	var prev: PackedVector2Array = u._sim_soldier_facing.duplicate()
	var max_step: float = Unit.CONVERSIO_TURN_RATE / float(Engine.physics_ticks_per_second)
	var worst: float = 0.0
	for _t in range(120):
		await get_tree().physics_frame
		for i in range(mini(prev.size(), u._sim_soldier_facing.size())):
			worst = maxf(worst, absf(prev[i].angle_to(u._sim_soldier_facing[i])))
		prev = u._sim_soldier_facing.duplicate()
		if not u._duplicatio_facing_owned:
			break
	assert_lte(worst, max_step + 1e-4, "no man snapped: %.3f rad in a tick" % worst)
	assert_false(u._duplicatio_facing_owned, "every man faces front, and the facings go back")


## The reading and the hold on the facings ride the snapshot.
func test_the_reading_rides_the_snapshot() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, CENTRE, HALF_FILE)
	assert_gte(await _settle(u), 0, "precondition: the explicatio ended")
	_battle.enqueue_file_double([u.uid], -1, CENTRE, HALF_FILE, OUTWARD, LENGTHEN, FACE_ABOUT)
	var d: Dictionary = u.to_snapshot_dict()
	u._duplicatio_march = WALK
	u._duplicatio_facing_owned = false
	u.apply_snapshot_dict(d)
	assert_eq(u._duplicatio_march, FACE_ABOUT, "the reading")
	assert_true(u._duplicatio_facing_owned, "the hold on the facings")


## The replay entry carries the reading, omitted for the walk, and decodes back.
func test_the_replay_carries_the_reading() -> void:
	var entry: Dictionary = ReplayOrderEntryScript.build(3, [1], Vector2.ZERO, -4, 0, 0, 9, INF, 0, 0.0,
			-1, 0, 0, -1, -1, 0, HALF_FILE, 0, 0, 0, FACE_ABOUT)
	assert_eq(int(entry["duplicatio_march"]), FACE_ABOUT, "recorded")
	assert_false(ReplayOrderEntryScript.build(3, [1], Vector2.ZERO, -4).has("duplicatio_march"),
		"the walk is omitted")
	var decoded: Dictionary = ReplayDecoderScript._decode_order(entry)
	assert_eq(int(decoded["duplicatio_march"]), FACE_ABOUT, "decoded")


# --- Keys --------------------------------------------------------------------------------


func test_alt_n_steps_the_reading_and_orders_nothing() -> void:
	var sm = SelectionManagerScript.new()
	add_child_autofree(sm)
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = 7
	u.soldiers = 120
	u.max_soldiers = 120
	b._by_uid[7] = u
	sm._select(u)
	var hud := StubHud.new()
	sm._hud = hud
	var start: int = UnitFormation.frontage(u)
	assert_eq(sm.duplicatio_march, WALK, "the walk by default")
	assert_true(sm._dispatch_key(_key(KEY_N)), "Alt+N is handled")
	assert_eq(sm.duplicatio_march, FACE_ABOUT, "the countermarch")
	assert_eq(hud.flashes.back(), "Duplicatio: face about", "and named")
	assert_eq(UnitFormation.frontage(u), start, "Alt+N only chooses; the frontage stays")
	assert_true(b._pending_orders.is_empty(), "and nothing is enqueued")
	sm._dispatch_key(_key(KEY_N))
	assert_eq(sm.duplicatio_march, WALK, "and wraps back to the walk")
