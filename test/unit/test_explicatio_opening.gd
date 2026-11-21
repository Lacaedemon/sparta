extends GutTest
## When an explicatio's files open, against when its men step into the intervals
## (ExplicatioOpening.Reading; the sources are quoted there and in
## docs/historical-reshaping-maneuvers.md, "The explicatio drills"):
## - TOGETHER, the default: the files open out while the men step in, the sim's own inference.
## - FILES_FIRST: each old file opens out to its distance as a whole, its men keeping their places
##   in it, and only then do they step into the interval beside it, each once the man ahead of
##   him has gone (Bingham's note on Aelian 29.3, "must be done in open order"; Aelian 33 and
##   Bingham's note on it, the files "moue on till the first distance recouered").

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


func _stage(at: Vector2 = SPAWN, seed_run: int = 1967) -> Unit:
	Replay.forced_seed = seed_run
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [{"team": 0, "type": "Spearmen", "x": at.x, "y": at.y,
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


# --- The man ahead of him in his old file, and the hold ----------------------------


## Two old files of four men, standing in their columns 9 wu apart and facing south (+y), dealt
## alternate rank with every interval on the right: old file 0 is new files 0 (stays) and 1, old
## file 1 new files 2 and 3. Rank by rank down each column: file 0 r0, file 1 r0, file 0 r1,
## file 1 r1.
func _two_old_files() -> Dictionary:
	var files := PackedInt32Array([0, 1, 0, 1, 2, 3, 2, 3])
	var ranks := PackedInt32Array([0, 0, 1, 1, 0, 0, 1, 1])
	var roles := PackedByteArray([0, 2, 0, 0, 0, 2, 0, 0])
	var bodies := PackedVector2Array()
	var facings := PackedVector2Array()
	for i in range(8):
		bodies.append(Vector2(9.0 * float(i >> 2), -9.0 * float(i & 3)))
		facings.append(Vector2(0, 1))
	var plan: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, roles, 0, 0, 9.0,
			9.0)
	return {"files": files, "ranks": ranks, "bodies": bodies, "facings": facings, "plan": plan}


## hold_unopened on `f` (_two_old_files) with the men at `bodies`, `following`, what their
## bodies show (`seen`, _seen) and `released`.
func _hold(f: Dictionary, bodies: PackedVector2Array, following: PackedByteArray,
		seen: Dictionary = {}, released: PackedByteArray = PackedByteArray()) -> Dictionary:
	var plan: Dictionary = f["plan"]
	return ExplicatioOpening.hold_unopened(plan.duplicate(true), f["files"], f["ranks"], bodies,
			f["facings"], 0, false, following, seen, released, 9.0, 9.0)


## What `n` men's bodies show the men behind them (ExplicatioSettled.men): `placed` at rest on
## their places, `held` at rest off them and gone from where they stood, with nothing seen in their
## way (so only a file leader held settles); every other man at rest where he stood when the drill
## began. The men of `word` passed the word back on the last tick.
func _seen(n: int, placed: Array = [], held: Array = [], word: Array = []) -> Dictionary:
	var at_rest := PackedByteArray()
	at_rest.resize(n)
	at_rest.fill(1)
	var on := PackedByteArray()
	on.resize(n)
	var off := PackedByteArray()
	off.resize(n)
	var none := PackedByteArray()
	none.resize(n)
	for i in placed:
		on[i] = 1
	for i in held:
		off[i] = 1
	var told := PackedByteArray()
	told.resize(n)
	for i in word:
		told[i] = 1
	return {"at_rest": at_rest, "moved": off, "blocked": none, "placed": on, "word": told}


## While the front man of an old file has not settled, each man behind him follows the man ahead
## of him in it, a rank pitch behind, held from the drill; the front man keeps his own plan. Once
## he is seen at rest on his place only the man right behind him moves off: the man behind that man
## sees him ahead in his line, at rest where he stood when the drill began, and waits.
func test_the_men_of_a_file_not_yet_opened_keep_their_places_in_it() -> void:
	var f: Dictionary = _two_old_files()
	var drill_leaders: PackedInt32Array = (f["plan"]["leaders"] as PackedInt32Array).duplicate()
	var held: Dictionary = _hold(f, f["bodies"], PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1]),
			_seen(8, [0]))
	var leaders: PackedInt32Array = held["leaders"]
	var offsets: PackedVector2Array = held["offsets"]
	assert_eq(held["waiting"], PackedByteArray([0, 0, 1, 1, 0, 1, 1, 1]),
		"behind the placed leader only his epistates moves off; behind the other leader all wait")
	assert_eq(leaders[1], drill_leaders[1], "the man behind the placed leader has the drill's plan")
	assert_eq(leaders[4], drill_leaders[4], "the other file's front man keeps his plan")
	assert_eq(leaders[5], 4, "the epistates stays behind his file leader")
	assert_eq(leaders[6], 5, "the next man behind the epistates")
	assert_eq(leaders[7], 6, "and the last behind him")
	for i in [5, 6, 7]:
		assert_eq(offsets[i], Vector2(0.0, 9.0), "man %d a rank behind the man ahead" % i)
	assert_eq((held["guides"] as PackedInt32Array)[5], SoldierFollow.NOT_FOLLOWING,
		"dressing on nobody's line")


## A man goes once he sees the man ahead of him in his line settle, on his place or held
## at rest off it, or step out. A man a file pitch out, in the interval, is no longer in the line,
## so the man behind him sees the next man ahead, here the placed leader; 4 wu out, within half a
## file pitch, he is still in it and holds him.
func test_each_man_moves_off_once_he_sees_the_man_ahead_of_him_stand() -> void:
	var f: Dictionary = _two_old_files()
	var bodies: PackedVector2Array = (f["bodies"] as PackedVector2Array).duplicate()
	bodies[1] += Vector2(10.0, 0.0)   # the epistates has stepped out into his interval
	var following := PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1])
	var held: Dictionary = _hold(f, bodies, following, _seen(8, [0]))
	assert_eq((held["waiting"] as PackedByteArray).slice(0, 4), PackedByteArray([0, 0, 0, 1]),
		"the man behind the epistates sees the placed leader and goes; the last man waits")
	bodies[1] -= Vector2(6.0, 0.0)   # back to 4 wu out: within half a file pitch
	held = _hold(f, bodies, following, _seen(8, [0]))
	assert_eq((held["waiting"] as PackedByteArray)[2], 1, "a man still in the line holds him")
	held = _hold(f, bodies, following, _seen(8, [0, 2], [], [0]))   # the man behind him placed
	assert_eq((held["waiting"] as PackedByteArray)[3], 0, "the last man sees him placed and goes")
	assert_eq((held["waiting"] as PackedByteArray)[5], 1,
		"the man behind a leader at rest where he began waits")
	held = _hold(f, bodies, following, _seen(8, [0, 2], [4], [0]))   # old file 1's leader held
	assert_eq((held["waiting"] as PackedByteArray).slice(4, 8), PackedByteArray([0, 0, 1, 1]),
		"the man behind a leader held off his place goes; the men behind him wait")


## A man of the file that stays only ever trails his file as it opens, so his stepping aside lets
## nobody go, and neither does the leader's; a man the deal put in the interval file who stands
## over half a file pitch off the line has stepped out, and the man behind him goes. Who stepped
## out is read from the deal, not from the man's own waiting or released flags.
func test_only_a_man_of_the_interval_file_steps_out() -> void:
	var f: Dictionary = _two_old_files()
	var following := PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1])
	var bodies: PackedVector2Array = (f["bodies"] as PackedVector2Array).duplicate()
	bodies[4] += Vector2(5.0, 0.0)   # old file 1's leader, still following, has stepped aside
	var held: Dictionary = _hold(f, bodies, following)
	assert_eq((held["waiting"] as PackedByteArray)[5], 1, "the man behind the leader still waits")
	bodies = (f["bodies"] as PackedVector2Array).duplicate()
	bodies[6] += Vector2(5.0, 0.0)   # a man of the file that stays, trailing it sideways
	held = _hold(f, bodies, following)
	assert_eq((held["waiting"] as PackedByteArray)[7], 1, "the man behind him still waits on him")
	bodies = (f["bodies"] as PackedVector2Array).duplicate()
	bodies[5] += Vector2(5.0, 0.0)   # the epistates, of the interval file, steps out
	for released in [PackedByteArray(), PackedByteArray([0, 0, 0, 0, 0, 1, 0, 0])]:
		held = _hold(f, bodies, following, {}, released)
		assert_eq((held["waiting"] as PackedByteArray)[6], 0,
			"the man behind him sees him step out and goes, whatever the epistates' own flags")
	bodies[5] += Vector2(5.0, 0.0)   # now a file pitch out, in the interval, nearer than the leader
	held = _hold(f, bodies, following)
	assert_eq((held["waiting"] as PackedByteArray)[6], 1,
		"a man out in the interval is not in the line: the man behind waits on his leader")
	assert_eq((held["leaders"] as PackedInt32Array)[6], 4, "on the leader")


## A man of the old file who has come up ahead of its leader is not in the line ahead of the men
## behind the leader: the man behind the leader still waits on the leader.
func test_a_man_ahead_of_his_file_leader_is_not_in_the_column() -> void:
	var f: Dictionary = _two_old_files()
	var bodies: PackedVector2Array = (f["bodies"] as PackedVector2Array).duplicate()
	bodies[5] += Vector2(0, 20)   # old file 1's epistates, up past his file leader
	var held: Dictionary = _hold(f, bodies, PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1]))
	assert_eq((held["waiting"] as PackedByteArray)[5], 0, "the man ahead of the leader does not wait")
	assert_eq((held["waiting"] as PackedByteArray)[6], 1, "the man behind the leader waits")
	assert_eq((held["leaders"] as PackedInt32Array)[6], 4,
		"on the leader: the man up past him is not the man ahead of him")


## The man ahead is read the same whatever order the men are stored in: here the rear man comes
## before the man ahead of him, and still waits on him.
func test_the_man_ahead_is_read_the_same_in_any_order() -> void:
	var files := PackedInt32Array([0, 0, 0])   # the leader, the rear man, the man between
	var ranks := PackedInt32Array([0, 2, 1])
	var roles := PackedByteArray([0, 0, 0])
	var bodies := PackedVector2Array([Vector2(0, 0), Vector2(0, -18), Vector2(0, -9)])
	var facings := PackedVector2Array([Vector2(0, 1), Vector2(0, 1), Vector2(0, 1)])
	var plan: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, roles, 0, 0, 9.0,
			9.0)
	var held: Dictionary = ExplicatioOpening.hold_unopened(plan, files, ranks, bodies, facings,
			0, false, PackedByteArray([1, 1, 1]), _seen(3, [0]), PackedByteArray(), 9.0, 9.0)
	assert_eq(held["waiting"], PackedByteArray([0, 1, 0]),
		"the man between goes, the leader placed; the rear man, stored first, waits on him")


## Who has settled and passes the word back, from each man's body, the deal, and the word of the
## man he dresses on as passed on the last tick. Three men in a chain (man 1 dresses on man 0, the
## head, man 2 on man 1): a man at rest on his place settles once he has that man's word, the head
## needing none; a man gone from where he stood and at rest settles if he is the head, or another
## with rock or a man of another file in his way, whatever word he has; a man of the column merely
## at rest behind it does not, nor a man at rest where he began with a man in his way, nor a man
## still going.
func test_a_man_is_seen_settled_only_from_his_body_and_the_deal() -> void:
	var leaders := PackedInt32Array([-1, 0, 1])
	var head := PackedByteArray([1, 0, 0])
	var cases: Array = [   # at rest, gone, in his way, on his place, word last tick -> settled
		[[1, 1, 1], [0, 0, 0], [0, 0, 0], [1, 1, 1], [0, 0, 0], [1, 0, 0], "no word yet: the head"],
		[[1, 1, 1], [0, 0, 0], [0, 0, 0], [1, 1, 1], [1, 0, 0], [1, 1, 0], "the head's word heard"],
		[[1, 1, 1], [0, 0, 0], [0, 0, 0], [1, 1, 1], [1, 1, 0], [1, 1, 1], "and passed on"],
		[[1, 1, 1], [0, 0, 0], [0, 0, 0], [0, 1, 1], [0, 1, 0], [0, 0, 1], "only his dresser's word"],
		[[0, 0, 0], [0, 0, 0], [0, 0, 0], [1, 1, 1], [1, 1, 1], [0, 0, 0], "on their places, going"],
		[[1, 1, 1], [1, 0, 0], [0, 0, 0], [0, 1, 0], [0, 0, 0], [1, 0, 0], "the head held off his place"],
		[[0, 1, 1], [1, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0], "the head gone, still going"],
		[[1, 1, 1], [0, 1, 0], [0, 0, 0], [0, 0, 0], [1, 1, 1], [0, 0, 0], "a column man at rest"],
		[[1, 1, 1], [0, 1, 0], [0, 1, 0], [0, 0, 0], [0, 0, 0], [0, 1, 0], "gone, a man in his way"],
		[[0, 0, 0], [0, 1, 0], [0, 1, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0], "in his way, going"],
		[[1, 1, 1], [0, 0, 0], [0, 1, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0], "in his way where he began"],
	]
	for c in cases:
		var seen := {"at_rest": PackedByteArray(c[0]), "moved": PackedByteArray(c[1]),
				"blocked": PackedByteArray(c[2]), "placed": PackedByteArray(c[3]),
				"word": PackedByteArray(c[4])}
		assert_eq(ExplicatioSettled.men(leaders, head, seen, 3), PackedByteArray(c[5]), c[6])
	var unheard := {"at_rest": PackedByteArray([1, 1, 1]), "moved": PackedByteArray([0, 0, 0]),
			"blocked": PackedByteArray([0, 0, 0]), "placed": PackedByteArray([1, 1, 1]),
			"word": PackedByteArray([1])}
	assert_eq(ExplicatioSettled.men(leaders, head, unheard, 3), PackedByteArray([1, 0, 0]),
		"a word that does not line up tells nobody")
	for key in ["at_rest", "moved", "blocked", "placed"]:
		var short := {"at_rest": PackedByteArray([1, 1, 1]), "moved": PackedByteArray([1, 1, 1]),
				"blocked": PackedByteArray([1, 1, 1]), "placed": PackedByteArray([1, 1, 1])}
		short[key] = PackedByteArray([1])
		assert_eq(ExplicatioSettled.men(leaders, head, short, 3), PackedByteArray([0, 0, 0]),
			"a reading whose %s does not line up settles nobody" % key)
	var all := {"at_rest": PackedByteArray([1, 1, 1]), "moved": PackedByteArray([1, 1, 1]),
			"blocked": PackedByteArray([1, 1, 1]), "placed": PackedByteArray([1, 1, 1])}
	assert_eq(ExplicatioSettled.men(leaders, PackedByteArray([1]), all, 3),
		PackedByteArray([0, 0, 0]), "nor one whose heads do not")
	assert_eq(ExplicatioSettled.men(PackedInt32Array([-1]), head, all, 3),
		PackedByteArray([0, 0, 0]), "nor one whose leaders do not")


## The word goes back a man a tick: six men of a file, every one at rest on his place, each
## dressing on the man ahead, and each tick's word is the last tick's settling. The rear man has it
## on the sixth tick and not before, one man more each tick.
func test_the_word_reaches_the_rear_man_one_man_a_tick() -> void:
	var leaders := PackedInt32Array([-1, 0, 1, 2, 3, 4])
	var head := PackedByteArray([1, 0, 0, 0, 0, 0])
	var ones := PackedByteArray([1, 1, 1, 1, 1, 1])
	var zeros := PackedByteArray([0, 0, 0, 0, 0, 0])
	var word := PackedByteArray()
	for t in range(6):
		var seen := {"at_rest": ones, "moved": zeros, "blocked": zeros, "placed": ones,
				"word": word}
		word = ExplicatioSettled.men(leaders, head, seen, 6)
		assert_eq(word.count(1), t + 1, "tick %d: %d men have the word" % [t, t + 1])
		assert_eq(word[5], 1 if t == 5 else 0, "tick %d: the rear man" % t)


## A body is in a man's way to his place only when it is a man of another old file standing ahead
## of him along that way, within a body's breadth of it, and touching him; never the man himself or
## a man of his own old file, whose column he trails, nor a man behind him, one beside the way, or
## one further off.
func test_a_body_in_his_way_is_ahead_of_him_and_touching() -> void:
	var place := Vector2(10, 0)
	var cases: Array = [
		[Vector2(2.5, 0), true, "a man touching him straight ahead"],
		[Vector2(-2.5, 0), false, "a man touching him from behind"],
		[Vector2(1.0, 2.5), false, "a man touching him beside the way"],
		[Vector2(3.5, 0), false, "a man ahead, not touching"],
	]
	var other := PackedInt32Array([0, 1])
	for c in cases:
		var bodies := PackedVector2Array([Vector2.ZERO, c[0]])
		assert_eq(ExplicatioSettled.body_in_way(0, place, bodies, other, 1.0, 1.0), c[1], c[2])
	assert_false(ExplicatioSettled.body_in_way(0, place,
			PackedVector2Array([Vector2.ZERO, Vector2(2.5, 0)]), PackedInt32Array([0, 0]), 1.0, 1.0),
		"nor a man of his own old file, touching him straight ahead")
	assert_false(ExplicatioSettled.body_in_way(0, place, PackedVector2Array([Vector2.ZERO]),
			PackedInt32Array([0]), 1.0, 1.0), "nor himself")


## Two men facing each other are not each the man ahead of the other: a man is ahead of another
## only when each is behind the other by his own facing too, so they cannot wait on each other and
## hold the drill for ever. The man facing the front still waits on his leader.
func test_two_men_cannot_wait_on_each_other() -> void:
	var files := PackedInt32Array([0, 0, 0])
	var ranks := PackedInt32Array([0, 1, 2])
	var roles := PackedByteArray([0, 0, 0])
	var bodies := PackedVector2Array([Vector2(0, 0), Vector2(0, -9), Vector2(0, -18)])
	var facings := PackedVector2Array([Vector2(0, 1), Vector2(0, -1), Vector2(0, 1)])
	var plan: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, roles, 0, 0, 9.0,
			9.0)
	var held: Dictionary = ExplicatioOpening.hold_unopened(plan, files, ranks, bodies, facings,
			0, false, PackedByteArray([1, 1, 1]), {}, PackedByteArray(), 9.0, 9.0)
	assert_eq(held["waiting"], PackedByteArray([0, 0, 1]),
		"the man faced about sees nobody ahead; the man behind him waits on the leader")
	assert_eq((held["leaders"] as PackedInt32Array)[2], 0,
		"on the leader: the man faced about is not the man ahead of him")


## A man jostled across his file for a tick sees nobody ahead and does not wait, but he has not
## stepped out: faced to the front again, in his line, he waits again. Only standing off his
## leader's line once he has gone marks him out of his file for good.
func test_a_man_jostled_across_his_file_is_not_out_of_it() -> void:
	var f: Dictionary = _two_old_files()
	var facings: PackedVector2Array = (f["facings"] as PackedVector2Array).duplicate()
	facings[5] = Vector2(1, 0)   # old file 1's epistates faces east, across his file
	f["facings"] = facings
	var held: Dictionary = _hold(f, f["bodies"], PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1]))
	assert_eq((held["waiting"] as PackedByteArray)[5], 0, "faced across, he sees nobody ahead")
	assert_eq((held["released"] as PackedByteArray)[5], 0, "but he has not stepped out")
	f["facings"] = _two_old_files()["facings"]
	held = _hold(f, f["bodies"], PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1]), {}, held["released"])
	assert_eq((held["waiting"] as PackedByteArray)[5], 1, "faced front again, he waits")
	var bodies: PackedVector2Array = (f["bodies"] as PackedVector2Array).duplicate()
	bodies[5] += Vector2(6.0, 0.0)   # gone, the leader held off his place, out of his line
	held = _hold(f, bodies, PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1]), _seen(8, [], [4]))
	assert_eq((held["released"] as PackedByteArray)[5], 1, "he has stepped out")
	held = _hold(f, f["bodies"], PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1]), {}, held["released"])
	assert_eq((held["waiting"] as PackedByteArray)[5], 0, "and never waits again")


## Live, files first, alternate rank: in every old file the last man moves off some ticks after the
## man right behind its leader, not on the same tick, since each man moves off only once he sees
## the man ahead of him settle and pass the word back, or step out.
func test_the_rear_of_a_file_moves_off_after_its_front() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.CENTRE, ALTERNATE_RANK,
			OUTWARD, LENGTHEN, DuplicatioMarch.Reading.WALK, FILES_FIRST)
	var forward: Vector2 = u.facing
	var columns: Dictionary = {}   # old file -> its men, front to rear, as they stand at the start
	for i in range(u.soldiers):
		var k: int = u._sim_soldier_file[i] >> 1
		if not columns.has(k):
			columns[k] = []
		columns[k].append(i)
	var first: Dictionary = {}   # old file -> the man right behind its leader
	var last: Dictionary = {}    # old file -> its rear man
	for k in columns:
		var men: Array = columns[k]
		men.sort_custom(func(a: int, b: int) -> bool:
			return u._sim_soldier_pos[a].dot(forward) > u._sim_soldier_pos[b].dot(forward))
		if men.size() > 2:
			first[k] = men[1]
			last[k] = men[men.size() - 1]
	var gone := PackedInt32Array()
	gone.resize(u.soldiers)
	gone.fill(-1)
	var waited := PackedByteArray()
	waited.resize(u.soldiers)
	for t in range(DRILL_TICKS):
		await get_tree().physics_frame
		if not u.explicatio_drill_active():
			break
		if u._explicatio_waiting.size() != u.soldiers:
			continue
		for i in range(u.soldiers):
			if u._explicatio_waiting[i] == 1:
				waited[i] = 1
			elif waited[i] == 1 and gone[i] < 0:
				gone[i] = t
	var later: int = 0
	for k in last:
		if waited[first[k]] == 0:
			continue
		assert_gte(gone[first[k]], 0, "old file %d: the man behind the leader moved off" % k)
		assert_gt(gone[last[k]], gone[first[k]],
			"old file %d: its rear man moved off after the man behind its leader" % k)
		later += 1
	assert_gt(later, 0, "precondition: files whose men waited")


## Live, files first, alternate rank: a man waiting in his old file never stands, and a man who has
## stepped out of it never waits in it again. The test keeps its own record of who has stepped out
## (Unit._explicatio_released as it was each tick), closed up by hand when a man falls, so a reap
## that left the drill's own flags out of step could not hide a man waiting again. With `kill_after`
## men out, a man still waiting is killed then (SoldierMelee.reap).
func _assert_nobody_waits_again(kill_after: int) -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.CENTRE, ALTERNATE_RANK,
			OUTWARD, LENGTHEN, DuplicatioMarch.Reading.WALK, FILES_FIRST)
	var out := PackedByteArray()
	out.resize(u.soldiers)
	var again: int = 0
	var stood_waiting: int = 0
	var killed: bool = kill_after < 0
	for _t in range(DRILL_TICKS):
		await get_tree().physics_frame
		if not u.explicatio_drill_active():
			break
		if u._explicatio_waiting.size() != u.soldiers or out.size() != u.soldiers:
			continue
		for i in range(u.soldiers):
			if u._explicatio_waiting[i] == 1:
				if out[i] == 1:
					again += 1
				if u._explicatio_standing.size() == u.soldiers and u._explicatio_standing[i] == 1:
					stood_waiting += 1
			if u._explicatio_released.size() == u.soldiers and u._explicatio_released[i] == 1:
				out[i] = 1
		if not killed and out.count(1) >= kill_after:
			var victim: int = u._explicatio_waiting.find(1)
			u._sim_soldier_hp[victim] = 0.0
			SoldierMelee.reap(u, null)
			out.remove_at(victim)
			killed = true
			assert_eq(u._explicatio_released.size(), u.soldiers, "the flags close up with the men")
	assert_gt(out.count(1), 0, "precondition: men stepped out of their files")
	assert_true(killed, "precondition: the man was killed while men waited")
	assert_eq(again, 0, "no man who had stepped out of his file waited in it again")
	assert_eq(stood_waiting, 0, "no man stood while he waited")
	assert_false(u.explicatio_drill_active(), "the drill ended")


func test_no_man_waits_again_once_he_has_left_his_file() -> void:
	await _assert_nobody_waits_again(-1)


func test_a_casualty_after_men_have_stepped_out_brings_none_of_them_back() -> void:
	await _assert_nobody_waits_again(20)


## A snapshot taken files first while men wait in their old files restores a drill that plays on
## exactly as before: who waits and who stands on every tick, the tick it ends, and where every
## man stands after. What the men behind remember of each man's body, where he stood when the drill
## began and on the last tick, rides the snapshot, and so do the release flags: the snapshot is
## taken on a tick when each decides the next (_run_until_standing_and_waiting).
func test_a_files_first_drill_with_men_waiting_plays_on_alike_after_a_restore() -> void:
	await _assert_plays_on_alike("seen")


func test_a_files_first_drill_with_men_out_plays_on_alike_after_a_restore() -> void:
	await _assert_plays_on_alike("flags")


func _assert_plays_on_alike(want: String) -> void:
	var u: Unit = null
	if want == "seen":
		u = await _stage_against_rock()
	else:
		u = await _stage_alternate_rank()
	await _run_until_standing_and_waiting(u, want)
	assert_gt(u._explicatio_waiting.count(1), 0, "precondition: men wait in their files")
	var snap: Dictionary = u.to_snapshot_dict()
	var first: Dictionary = await _play_out(u)
	assert_gte(first["ended"], 0, "precondition: the drill ended")
	u.apply_snapshot_dict(snap)
	var again: Dictionary = await _play_out(u)
	assert_eq(again["ended"], first["ended"], "the drill ends on the same tick")
	var unlike: int = -1
	for t in range(mini(first["waiting"].size(), again["waiting"].size())):
		if first["waiting"][t] != again["waiting"][t] or first["standing"][t] != again["standing"][t]:
			unlike = t
			break
	assert_eq(unlike, -1, "the same men wait and stand on every tick")
	var worst: float = 0.0
	for i in range(u.soldiers):
		worst = maxf(worst, first["pos"][i].distance_to(u._sim_soldier_pos[i]))
	assert_lt(worst, 0.001, "every man stands where he stood the first time (%.4f wu off)" % worst)


## A centred files-first alternate-rank drill under way.
func _stage_alternate_rank() -> Unit:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.CENTRE, ALTERNATE_RANK,
			OUTWARD, LENGTHEN, DuplicatioMarch.Reading.WALK, FILES_FIRST)
	return u


## A centred files-first half-file drill under way at x 1090, 24 wu short of the field's hill, so
## the rock holds file leaders short of their places and the men behind them see them held there
## (test_explicatio_drill.gd's terrain drill): what the men remember of where each man stood
## decides who goes.
func _stage_against_rock() -> Unit:
	var u: Unit = await _stage(Vector2(1090, 470), 1948)
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.CENTRE, HALF_FILE,
			OUTWARD, LENGTHEN, DuplicatioMarch.Reading.WALK, FILES_FIRST)
	return u


## Run `u`'s files-first drill until the snapshot it would take carries state the next tick
## needs: `want` "seen", men whose memory of the men ahead decides whether they wait
## (_memory_matters); "flags", men whose release flags decide it (_release_flags_matter).
func _run_until_standing_and_waiting(u: Unit, want: String) -> void:
	for _t in range(DRILL_TICKS):
		await get_tree().physics_frame
		if (want == "seen" and _memory_matters(u)) \
				or (want == "flags" and _release_flags_matter(u)):
			return
	fail_test("precondition: no tick on which the %s decide the next" % want)


## Whether reading `u`'s files-first hold now without what the men remember of the men ahead,
## where each stood when the drill began and on the last tick, would set other men waiting: then a
## restore that lost it would play on otherwise.
func _memory_matters(u: Unit) -> bool:
	if not u.explicatio_drill_active() or u._explicatio_waiting.size() != u.soldiers:
		return false
	var with: PackedByteArray = _hold_now(u, u._explicatio_released)["waiting"]
	var start: PackedVector2Array = u._explicatio_start
	var last: PackedVector2Array = u._explicatio_seen_at
	var word: PackedByteArray = u._explicatio_word_passed
	u._explicatio_start = PackedVector2Array()
	u._explicatio_seen_at = PackedVector2Array()
	u._explicatio_word_passed = PackedByteArray()
	var without: PackedByteArray = _hold_now(u, u._explicatio_released)["waiting"]
	u._explicatio_start = start
	u._explicatio_seen_at = last
	u._explicatio_word_passed = word
	return with != without


## `u`'s files-first hold read now, from where its men stand, with `released`.
func _hold_now(u: Unit, released: PackedByteArray) -> Dictionary:
	var n: int = u.soldiers
	var plan: Dictionary = UnitFormation.explicatio_follow_plan(u._sim_soldier_file,
			u._sim_soldier_rank, u._sim_soldier_role, u._explicatio_lane_split,
			u._explicatio_stand_file, u.file_pitch_wu(), u.rank_pitch_wu(), u._explicatio_inward)
	return ExplicatioOpening.hold_unopened(plan, u._sim_soldier_file, u._sim_soldier_rank,
			u._sim_soldier_pos.slice(0, n), u._sim_soldier_facing.slice(0, n),
			u._explicatio_lane_split, u._explicatio_inward, u._explicatio_following,
			_seen_now(u, n), released, u.file_pitch_wu(), u.rank_pitch_wu())


## What `u`'s first `n` men show now, with the word each passed on the last tick.
func _seen_now(u: Unit, n: int) -> Dictionary:
	var seen: Dictionary = u._explicatio_seen(n)
	seen["word"] = u._explicatio_word_passed
	return seen


## Whether reading `u`'s files-first hold now without its release flags would set men waiting
## whom the flags keep out of their files: then a restore that lost them would play on otherwise.
func _release_flags_matter(u: Unit) -> bool:
	if u._explicatio_released.count(1) == 0 or not u.explicatio_drill_active():
		return false
	var bare: Dictionary = _hold_now(u, PackedByteArray())
	return (bare["waiting"] as PackedByteArray).count(1) > u._explicatio_waiting.count(1)


## A man killed while what the men remember of the men ahead decides who waits: reap closes that
## memory up with the men (SoldierMelee.reap), each man keeping where he stood when the drill began
## and on the last tick, and whether he had passed the word back.
func test_a_casualty_keeps_last_ticks_standing_lined_up() -> void:
	var u: Unit = await _stage_against_rock()
	await _run_until_standing_and_waiting(u, "seen")
	var start: PackedVector2Array = u._explicatio_start.duplicate()
	var last: PackedVector2Array = u._explicatio_seen_at.duplicate()
	var word: PackedByteArray = u._explicatio_word_passed.duplicate()
	assert_eq(start.size(), u.soldiers, "precondition: the memory lines up with the men")
	u._sim_soldier_hp[0] = 0.0   # the first man stored falls
	SoldierMelee.reap(u, null)
	start.remove_at(0)
	last.remove_at(0)
	word.remove_at(0)
	assert_eq(u._explicatio_start, start, "where each man stood when the drill began closes up")
	assert_eq(u._explicatio_seen_at, last, "and where each stood on the last tick")
	assert_eq(u._explicatio_word_passed, word, "and who had passed the word back")


## Walk `u`'s drill to its end, recording who waits and who stands on every tick, then 30 ticks
## more; return them, the tick it ended (-1 if it did not) and where each man stood.
func _play_out(u: Unit) -> Dictionary:
	var out := {"waiting": [], "standing": [], "ended": -1}
	for t in range(DRILL_TICKS):
		await get_tree().physics_frame
		if not u.explicatio_drill_active():
			out["ended"] = t
			break
		out["waiting"].append(u._explicatio_waiting.duplicate())
		out["standing"].append(u._explicatio_standing.duplicate())
	for _t in range(30):
		await get_tree().physics_frame
	out["pos"] = u._sim_soldier_pos.duplicate()
	return out


## A casualty closes up each file's ranks (SoldierMelee.reap, UnitFormation.drop_rank_assignment),
## so a man's rank in his new file no longer says who stood ahead of him. The man ahead is read
## from where the men stand: with the epistates of old file 0 fallen and the ranks closed up, the
## man behind him follows the file leader, and the interval man behind that man follows him; a
## plan whose flags do not line up holds nobody.
func test_a_man_whose_man_ahead_fell_follows_the_next_man_ahead() -> void:
	# Old file 0 of six, alternate rank: A0 A2 A4 stay (file 0), A1 A3 A5 go (file 1). A1 has
	# fallen: file 1's ranks closed up, so A3 is its rank 0 and A5 its rank 1.
	var files := PackedInt32Array([0, 0, 0, 1, 1])        # A0 A2 A4 A3 A5
	var ranks := PackedInt32Array([0, 1, 2, 0, 1])
	var roles := PackedByteArray([0, 0, 0, 2, 0])
	var bodies := PackedVector2Array([Vector2(0, 0), Vector2(0, -18), Vector2(0, -36),
			Vector2(0, -27), Vector2(0, -45)])
	var facings := PackedVector2Array()
	for _i in range(5):
		facings.append(Vector2(0, 1))
	var plan: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, roles, 0, 0, 9.0,
			9.0)
	var held: Dictionary = ExplicatioOpening.hold_unopened(plan.duplicate(true), files, ranks,
			bodies, facings, 0, false, PackedByteArray([1, 1, 1, 1, 1]), {}, PackedByteArray(),
			9.0, 9.0)
	var leaders: PackedInt32Array = held["leaders"]
	assert_eq(held["waiting"], PackedByteArray([0, 1, 1, 1, 1]), "every man behind A0 waits")
	assert_eq(leaders[1], 0, "A2 follows A0, the man now ahead of him")
	assert_eq(leaders[3], 1, "A3 follows A2, not the other way round")
	assert_eq(leaders[2], 3, "A4 follows A3")
	assert_eq(leaders[4], 2, "and A5 follows A4")
	var unlined: Dictionary = ExplicatioOpening.hold_unopened(plan.duplicate(true), files, ranks,
			bodies, facings, 0, false, PackedByteArray([1]), {}, PackedByteArray(), 9.0, 9.0)
	assert_eq(unlined["waiting"], PackedByteArray([0, 0, 0, 0, 0]),
		"flags that do not line up hold nobody")


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
## rank pitch) for 140 Spearmen 9 files by 16 centred and 1.24 wu held on the right, measured
## 2026-11-19. Files first, each file opens out with its men still in it and only then does its
## epistates step in beside the leader, so no file leader gets a fortieth of a rank pitch ahead.
## The column leaders still come up into line past it before they settle, 1.38 wu centred, a
## little further ahead than together, and 0.31 wu held on the right (measured 2026-11-20), within
## a quarter of a rank pitch, the bound every other reading keeps.
## The men wait in their files on the way, and the drill ends with the files doubled and nobody
## closer than a body radius to another man.
# TODO(#1989): a man coming up into line with way on across his front still overshoots it.
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


## A man killed mid-drill files first, the epistates of an old file still waiting to open: the
## ranks close up behind him, and every man still waiting goes on following the man actually
## ahead of him in his old file, never a man behind him, so nobody has to pass through his file.
## The drill ends with nobody closer than a body radius to another man.
func test_files_first_with_a_man_killed_mid_drill_follows_the_man_actually_ahead() -> void:
	var u: Unit = await _stage()
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.CENTRE, ALTERNATE_RANK,
			OUTWARD, LENGTHEN, DuplicatioMarch.Reading.WALK, FILES_FIRST)
	await get_tree().physics_frame
	var victim: int = -1
	for i in range(u.soldiers):
		if u._explicatio_waiting.size() == u.soldiers and u._explicatio_waiting[i] == 1 \
				and u._sim_soldier_rank[i] == 0:
			victim = i   # an interval's first man, still in his old file behind its leader
			break
	assert_gte(victim, 0, "precondition: an epistates waits in his old file")
	u._sim_soldier_hp[victim] = 0.0
	SoldierMelee.reap(u, null)
	var forward: Vector2 = u.facing
	var checked: int = 0
	var behind: int = 0
	var closest: float = INF
	var ended: int = -1
	for t in range(DRILL_TICKS):
		await get_tree().physics_frame
		if not u.explicatio_drill_active():
			ended = t
			break
		for i in range(u.soldiers):
			if u._explicatio_waiting.size() != u.soldiers or u._explicatio_waiting[i] == 0:
				continue
			checked += 1
			var j: int = u._explicatio_leaders[i]
			if u._sim_soldier_pos[j].dot(forward) <= u._sim_soldier_pos[i].dot(forward):
				behind += 1
		if t % 4 == 0:
			closest = minf(closest, _nearest_pair(u._sim_soldier_pos))
	assert_gt(checked, 0, "precondition: men waited after the casualty")
	assert_eq(behind, 0, "no waiting man followed a man behind him")
	assert_gte(ended, 0, "the drill ended")
	assert_gte(closest, u.soldier_body_radius(), "the nearest two men came within %.2f wu" % closest)


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
