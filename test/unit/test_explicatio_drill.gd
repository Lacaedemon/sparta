extends GutTest
## The explicatio as the drill manuals describe it: the front stays where it stands, and
## the men who change file step sideways into the interval beside their own file and march
## straight up it in column, the man who leads the column first and nobody overtaking the man
## ahead of him. Two drills choose who changes file (UnitFormation.ExplicatioDrill):
## - HALF_FILE, the default: each file's rear half, led by its half-file leader, the hemilochites
##   (Asclepiodotus, Tactics 2.2; Xenophon, Cyropaedia 2.3.21).
## - ALTERNATE_RANK: every second man, led by the epistates behind the file leader (Bingham's
##   notes on Aelian ch. 29; the ancient source is not yet verified).
##
## The live tests stage a lone block of Spearmen in drill mode and widen it through the order
## the B key issues (Battle.enqueue_file_double).

const SPAWN := Vector2(500, 300)
const SPEARMEN := 140
## Ticks for the drill to play out: the farthest rear man steps about four file pitches sideways
## and then marches eight rank pitches up his lane, the column entering behind its leader; the
## block measured on this build finishes within 340 ticks.
const DRILL_TICKS := 400
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


func _spearmen(facing: Array = [0, 1], at: Vector2 = SPAWN) -> Dictionary:
	return {"team": 0, "type": "Spearmen", "x": at.x, "y": at.y, "count": SPEARMEN,
			"facing": facing}


func _run(ticks: int) -> void:
	for _i in range(ticks):
		await get_tree().physics_frame


## How far ahead along `forward` the block's front-most body stands.
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


func _count_role(u: Unit, role: int) -> int:
	var n: int = 0
	for i in range(u.soldiers):
		if u.soldier_role(i) == role:
			n += 1
	return n


## Walk the drill `ticks` ticks after the deal and check the columns: every man who changes file
## stays behind the man ahead of him in his new file along the facing (`forward`), and steps into
## his interval (is struck off as a lane walker) no earlier than that man does. Returns
## {"overtake": the farthest any man got ahead of the man ahead of him (negative when every man
## stayed behind), "early": how many men entered their interval before the man ahead of them}.
## `kill_tick` >= 0 kills man `kill_index` on that tick through SoldierMelee.reap.
func _walk_columns(u: Unit, forward: Vector2, ticks: int, kill_tick: int = -1,
		kill_index: int = -1) -> Dictionary:
	var overtake: float = -INF
	var early: int = 0
	var entered: Dictionary = {}   # man index -> tick he stepped into his interval
	for t in range(ticks):
		if t == kill_tick:
			u._sim_soldier_hp[kill_index] = 0.0
			SoldierMelee.reap(u, null)
			entered.clear()   # indices above the dead man moved down by one
		await get_tree().physics_frame
		if u._sim_soldier_lane_walker.size() != u.soldiers:
			break   # everyone is in his interval
		var ahead: PackedInt32Array = UnitFormation.man_ahead_in_file(u._sim_soldier_file,
				u._sim_soldier_rank)
		for i in range(u.soldiers):
			var j: int = ahead[i]
			if j < 0:
				continue
			if not (u.is_lane_walker(i) or u.is_lane_walker(j) or entered.has(i)):
				continue
			overtake = maxf(overtake,
					(u._sim_soldier_pos[i] - u._sim_soldier_pos[j]).dot(forward))
			if not u.is_lane_walker(i) and not entered.has(i):
				entered[i] = t
				if u.is_lane_walker(j):
					early += 1
	return {"overtake": overtake, "early": early}


# --- The half-file drill, live ---------------------------------------------------


## The front rank stands where it stood. On main the shallower block re-centred on the old
## centre and the front walked back half the depth the block lost: four rank pitches (36 wu)
## for 140 Spearmen going from 16 ranks to 8. The bound is a quarter of a rank pitch.
func test_the_front_rank_holds_its_ground() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var forward: Vector2 = u.facing
	var front_before: float = _front(u, forward)
	_battle.enqueue_file_double([u.uid], 1)
	await _run(DRILL_TICKS)
	assert_eq(UnitFormation.frontage(u), 18, "precondition: the explicatio doubled 9 files to 18")
	assert_almost_eq(_front(u, forward), front_before, 0.25 * u.rank_pitch_wu(),
		"the front rank holds its ground")


## No man of a front half-file ever steps back: he only moves sideways as the line opens.
## The bound is a quarter of a rank pitch of body jitter.
func test_no_man_of_a_front_half_steps_back() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var forward: Vector2 = u.facing
	var start: PackedVector2Array = u._sim_soldier_pos.duplicate()
	_battle.enqueue_file_double([u.uid], 1)
	var front_half: Array = []
	for i in range(u.soldiers):
		if u._sim_soldier_file[i] % 2 == 0:   # the lane is on the right: front halves in 2k
			front_half.append(i)
	assert_eq(front_half.size(), 72, "precondition: 72 of 140 men keep the front halves")
	var worst: float = 0.0
	for _t in range(DRILL_TICKS):
		await get_tree().physics_frame
		for i in front_half:
			worst = maxf(worst, (start[i] - u._sim_soldier_pos[i]).dot(forward))
	assert_lt(worst, 0.25 * u.rank_pitch_wu(),
		"the farthest any front-half man stepped back is %.2f wu" % worst)


## Each rear man steps sideways into his interval before he marches up it: while he is still on
## his way in (a lane walker) he gains no more than a quarter of a rank pitch of ground.
func test_the_rear_men_step_into_the_interval_before_marching_up_it() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var forward: Vector2 = u.facing
	var start: PackedVector2Array = u._sim_soldier_pos.duplicate()
	_battle.enqueue_file_double([u.uid], 1)
	var walkers: int = 0
	for i in range(u.soldiers):
		if u.is_lane_walker(i):
			walkers += 1
	assert_eq(walkers, 68, "precondition: 68 rear men step into the intervals")
	var worst: float = 0.0
	for _t in range(DRILL_TICKS):
		await get_tree().physics_frame
		for i in range(u.soldiers):
			if u.is_lane_walker(i):
				worst = maxf(worst, (u._sim_soldier_pos[i] - start[i]).dot(forward))
	assert_lt(worst, 0.25 * u.rank_pitch_wu(),
		"the most ground a rear man gained before he was in his interval is %.2f wu" % worst)


## Nobody passes through anybody: no two men of the block come closer than the overlap floor the
## demo defect scan judges a reshape by, a quarter of two touching bodies
## (DemoDefects.OVERLAP_BODY_FRAC of twice the body radius, 2.25 wu). Held on the right flank,
## main's deal brought two men to 1.68 wu.
func test_an_anchored_explicatio_brings_no_two_men_onto_each_other() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var floor_wu: float = 2.0 * u.soldier_body_radius() * DemoDefects.OVERLAP_BODY_FRAC
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.RIGHT)
	var closest: float = INF
	for _t in range(DRILL_TICKS):
		await get_tree().physics_frame
		closest = minf(closest, _nearest_pair(u._sim_soldier_pos))
	assert_gte(closest, floor_wu, "the nearest two men came within %.2f wu" % closest)


## A unit widening on the march keeps its front's progress. On main the widened front fell back
## half the depth the block lost, 36 wu. The men of the front halves step sideways as the line
## opens while the block marches, and each carries the ground he lost doing it into the
## coupling when he arrives: this build measured the front 2.5 wu behind a twin that does not
## widen, so the bound is half a rank pitch.
func test_a_unit_widening_on_the_march_keeps_its_fronts_progress() -> void:
	var units: Array = await _stage([_spearmen([0, 1], Vector2(400, 150)),
			_spearmen([0, 1], Vector2(800, 150))])
	var widen: Unit = units[0]
	var twin: Unit = units[1]
	_battle._apply_order_cmd({"units": [widen.uid], "x": 400.0, "y": 700.0, "target": -1})
	_battle._apply_order_cmd({"units": [twin.uid], "x": 800.0, "y": 700.0, "target": -1})
	var marching: int = 0
	while marching < 600 and not (widen.state == Unit.State.MOVING
			and twin.state == Unit.State.MOVING):
		await get_tree().physics_frame
		marching += 1
	assert_eq(widen.state, Unit.State.MOVING, "precondition: both units are marching")
	await _run(30)
	_battle.enqueue_file_double([widen.uid], 1)
	await _run(240)
	var forward := Vector2(0, 1)
	assert_gt(_front(widen, forward), _front(twin, forward) - 0.5 * widen.rank_pitch_wu(),
		"the widened front is %.1f wu behind its twin's"
		% (_front(twin, forward) - _front(widen, forward)))


## The march destination and every queued leg move up with the centre, so the unit does not walk
## back to its old centre's goal.
func test_the_destination_and_queued_legs_move_up_with_the_centre() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle._apply_order_cmd({"units": [u.uid], "x": 500.0, "y": 700.0, "target": -1})
	var leg := Order.new_move(Vector2(500, 800))
	u.orders.append(leg)
	var waited: int = 0
	while not u.has_move_target and waited < 600:
		await get_tree().physics_frame
		waited += 1
	assert_true(u.has_move_target, "precondition: the unit is marching on its destination")
	var target_before: Vector2 = u.move_target
	var position_before: Vector2 = u.position
	_battle.enqueue_file_double([u.uid], 1)
	var shift: Vector2 = u.position - position_before
	assert_gt(shift.length(), 0.0, "precondition: the centre moved up to hold the front")
	assert_almost_eq(u.move_target.x, target_before.x + shift.x, 0.01, "the destination moved up")
	assert_almost_eq(u.move_target.y, target_before.y + shift.y, 0.01, "the destination moved up")
	assert_almost_eq(leg.target_pos.x, 500.0 + shift.x, 0.01, "the queued leg moved up")
	assert_almost_eq(leg.target_pos.y, 800.0 + shift.y, 0.01, "the queued leg moved up")


## The rear half-files take the interval on the unit's right, its spear side, whichever way it
## faces and whether or not an about-face mirror stands on its grid: set_frontage bakes the
## mirror first, so the slot frame's +x is the right.
func test_the_lanes_open_on_the_units_right() -> void:
	for facing in [[0, 1], [1, 0]]:
		for mirrored in [false, true]:
			var units: Array = await _stage([_spearmen(facing)])
			var u: Unit = units[0]
			u.formation_slots(u.soldiers)
			if mirrored:
				u._formation_mirror_x = true
			_battle.enqueue_file_double([u.uid], 1)
			assert_false(u._formation_mirror_x, "the mirror is baked before the deal")
			var right := Vector2(-u.facing.y, u.facing.x)
			var local: PackedVector2Array = u.formation_slots(u.soldiers, false, false)
			var ang: float = u.soldier_block_world_angle()
			var on_right: int = 0
			var pairs: int = 0
			for i in range(u.soldiers):
				if u._sim_soldier_file[i] % 2 != 1:
					continue
				for j in range(u.soldiers):
					if u._sim_soldier_file[j] == u._sim_soldier_file[i] - 1 \
							and u._sim_soldier_rank[j] == u._sim_soldier_rank[i]:
						pairs += 1
						var d: Vector2 = (local[i] - local[j]).rotated(ang)
						if d.dot(right) > 0.0:
							on_right += 1
			assert_gt(pairs, 0, "precondition: rear men beside their front-half partners")
			assert_eq(on_right, pairs, "facing %s, mirror %s: every lane is on the right"
					% [str(facing), str(mirrored)])
			_battle.free()
			_battle = null
			await get_tree().physics_frame


## An explicatio held on its right flank opens its lanes on the left, so the right flank's own
## front half-file keeps its ground.
func test_an_explicatio_held_on_the_right_opens_its_lanes_on_the_left() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.RIGHT)
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


## A file-major block widened any other way keeps main's lateral deal: a [ ] style absolute
## resize to twice the files is not the drill, and the centre stays where it was.
func test_an_absolute_resize_to_twice_the_files_is_not_the_drill() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var position_before: Vector2 = u.position
	u.set_frontage(18)
	u.formation_slots(u.soldiers)
	assert_eq(u.position, position_before, "the centre stays put")
	assert_true(u._sim_soldier_lane_walker.is_empty(), "nobody is sent up a lane")
	assert_eq(_count_role(u, UnitFormation.SoldierRole.HEMILOCHITES), 0, "nobody leads a column")


## An explicatio ordered while a duplicatio is still walking deals files whose men may still
## stand abreast of each other: each falls in behind the man ahead of him in his column instead
## of onto him. Ordered 110 ticks after the duplicatio (as in the file-doubling demo), the
## follower who stood abreast of his leader once walked onto him, 0.0 wu apart.
func test_an_explicatio_during_a_duplicatio_brings_no_two_men_onto_each_other() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var floor_wu: float = 2.0 * u.soldier_body_radius() * DemoDefects.OVERLAP_BODY_FRAC
	_battle.enqueue_file_double([u.uid], -1)
	await _run(110)
	_battle.enqueue_file_double([u.uid], 1)
	var closest: float = INF
	for _t in range(2 * DRILL_TICKS):
		await get_tree().physics_frame
		closest = minf(closest, _nearest_pair(u._sim_soldier_pos))
	assert_gte(closest, floor_wu, "the nearest two men came within %.2f wu" % closest)


# --- The column and its leader, live ---------------------------------------------


## Each half-file's leader, the man who stood at the head of its rear half, is its hemilochites
## and heads his new file: one for each of the 9 old files.
func test_the_half_file_leader_is_the_hemilochites_and_heads_his_new_file() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	var leaders: int = 0
	for i in range(u.soldiers):
		if u.soldier_role(i) != UnitFormation.SoldierRole.HEMILOCHITES:
			continue
		leaders += 1
		assert_eq(u._sim_soldier_rank[i], 0, "the hemilochites heads his new file")
		assert_true(u.is_lane_walker(i), "the hemilochites steps into the interval")
	assert_eq(leaders, 9, "one hemilochites for each old file")


## The hemilochites steps into the interval first and each man follows the man ahead of him in:
## no man enters before the man ahead of him has, and no man ever stands ahead of him along the
## facing while either is on his way in.
func test_nobody_overtakes_the_man_ahead_of_him_in_his_column() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var forward: Vector2 = u.facing
	_battle.enqueue_file_double([u.uid], 1)
	var walk: Dictionary = await _walk_columns(u, forward, DRILL_TICKS)
	assert_eq(walk["early"], 0, "no man stepped in before the man ahead of him")
	assert_lt(walk["overtake"], 0.0,
		"the nearest any man came to passing the man ahead of him is %.2f wu" % walk["overtake"])


## A hemilochites who falls on the way in hands the lead to the man behind him: that man takes
## the role and heads the file, and the column still follows him in without overtaking.
func test_a_fallen_hemilochites_hands_the_lead_to_the_man_behind_him() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var forward: Vector2 = u.facing
	_battle.enqueue_file_double([u.uid], 1)
	var leader: int = -1
	for i in range(u.soldiers):
		if u.soldier_role(i) == UnitFormation.SoldierRole.HEMILOCHITES:
			leader = i
			break
	var file: int = u._sim_soldier_file[leader]
	var heir: int = -1
	for i in range(u.soldiers):
		if u._sim_soldier_file[i] == file and u._sim_soldier_rank[i] == 1:
			heir = i
	assert_gte(heir, 0, "precondition: a man stands behind the hemilochites")
	var walk: Dictionary = await _walk_columns(u, forward, DRILL_TICKS, 10, leader)
	var heir_now: int = heir - 1 if heir > leader else heir
	assert_eq(u.soldiers, SPEARMEN - 1, "precondition: the hemilochites fell")
	assert_eq(u.soldier_role(heir_now), UnitFormation.SoldierRole.HEMILOCHITES,
		"the man behind him took the lead")
	assert_eq(u._sim_soldier_rank[heir_now], 0, "and heads the file")
	assert_eq(_count_role(u, UnitFormation.SoldierRole.HEMILOCHITES), 9,
		"each half-file still has one leader")
	assert_eq(walk["early"], 0, "no man stepped in before the man ahead of him")
	assert_lt(walk["overtake"], 0.0,
		"the nearest any man came to passing the man ahead of him is %.2f wu" % walk["overtake"])


## Each man's role is his own: a snapshot carries it, and a reinforcement's bodies appended to
## the block leave the host's leaders on the host's men and add the reserve's own.
func test_the_roles_ride_a_snapshot_and_a_reinforcement() -> void:
	var units: Array = await _stage([_spearmen(), _spearmen([0, 1], Vector2(800, 300))])
	var u: Unit = units[0]
	var reserve: Unit = units[1]
	_battle.enqueue_file_double([u.uid], 1)
	var roles: PackedByteArray = u._sim_soldier_role.duplicate()
	assert_eq(roles.size(), SPEARMEN, "precondition: every man has a role entry")
	var snap: Dictionary = u.to_snapshot_dict()
	u._sim_soldier_role = PackedByteArray()
	u.apply_snapshot_dict(snap)
	assert_eq(u._sim_soldier_role, roles, "the snapshot restores each man's role")
	reserve._sim_soldier_role = PackedByteArray()
	reserve._sim_soldier_role.resize(reserve._sim_soldier_pos.size())
	reserve._sim_soldier_role[0] = UnitFormation.SoldierRole.EPISTATES
	u.append_soldier_bodies(reserve)
	assert_eq(u._sim_soldier_role.size(), u._sim_soldier_pos.size(), "one role for each body")
	assert_eq(u._sim_soldier_role.slice(0, SPEARMEN), roles, "the host's men keep theirs")
	assert_eq(u._sim_soldier_role[SPEARMEN], UnitFormation.SoldierRole.EPISTATES,
		"the reserve's men bring theirs")


# --- The alternate-rank drill, live -----------------------------------------------


## The alternate-rank drill, chosen on the order: the front rank holds its ground, every second
## man steps into the interval beside the man who stood ahead of him, led by the epistates, and
## the column follows him in without overtaking.
func test_the_alternate_rank_drill_keeps_the_front_and_its_columns() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var forward: Vector2 = u.facing
	var front_before: float = _front(u, forward)
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.CENTRE, ALTERNATE_RANK)
	assert_eq(_count_role(u, UnitFormation.SoldierRole.EPISTATES), 9,
		"one epistates for each old file")
	assert_eq(_count_role(u, UnitFormation.SoldierRole.HEMILOCHITES), 0, "and no hemilochites")
	var walk: Dictionary = await _walk_columns(u, forward, DRILL_TICKS)
	assert_eq(walk["early"], 0, "no man stepped in before the man ahead of him")
	assert_lt(walk["overtake"], 0.0,
		"the nearest any man came to passing the man ahead of him is %.2f wu" % walk["overtake"])
	await _run(DRILL_TICKS)
	assert_eq(UnitFormation.frontage(u), 18, "precondition: the explicatio doubled 9 files to 18")
	assert_almost_eq(_front(u, forward), front_before, 0.25 * u.rank_pitch_wu(),
		"the front rank holds its ground")


## The alternate-rank drill held on a flank brings no two men below the overlap floor either.
func test_an_anchored_alternate_rank_drill_brings_no_two_men_onto_each_other() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	var floor_wu: float = 2.0 * u.soldier_body_radius() * DemoDefects.OVERLAP_BODY_FRAC
	_battle.enqueue_file_double([u.uid], 1, UnitFormation.Anchor.RIGHT, ALTERNATE_RANK)
	var closest: float = INF
	for _t in range(DRILL_TICKS):
		await get_tree().physics_frame
		closest = minf(closest, _nearest_pair(u._sim_soldier_pos))
	assert_gte(closest, floor_wu, "the nearest two men came within %.2f wu" % closest)


## The drill rides the recorded order: the replay entry carries it, and a combo's widen step
## carries it through Order.to_dict and back.
func test_the_drill_rides_the_order_and_the_replay() -> void:
	var entry: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18,
			INF, 0, 0.0, -1, 0, 0, -1, -1, 0, ALTERNATE_RANK)
	assert_eq(entry["explicatio"], ALTERNATE_RANK, "the replay entry names the drill")
	var plain: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18)
	assert_false(plain.has("explicatio"), "a plain resize records no drill")
	var decoder := preload("res://scripts/ReplayDecoder.gd")
	assert_eq(decoder._decode_order({"units": [1], "explicatio": true})["explicatio"], HALF_FILE,
		"an entry recorded as a flag plays back as the half-file drill")
	var step := Order.new_file_double(1, ALTERNATE_RANK)
	assert_eq(Order.from_dict(step.to_dict()).explicatio_drill, ALTERNATE_RANK,
		"a combo step keeps its drill through a snapshot")
	assert_eq(Order.new_file_double(1).explicatio_drill, HALF_FILE, "the half-file by default")


# --- The pure primitives ---------------------------------------------------------


func test_the_half_file_deal_keeps_the_front_halves_and_sends_the_rear_up_the_lanes() -> void:
	# Two files of four, index order: file 0 ranks 0-3, then file 1 ranks 0-3.
	var files := PackedInt32Array([0, 0, 0, 0, 1, 1, 1, 1])
	var d: Dictionary = UnitFormation.explicatio_assignment(files, PackedInt32Array(), 2, true)
	assert_eq(d["files"], PackedInt32Array([0, 0, 1, 1, 2, 2, 3, 3]))
	assert_eq(d["ranks"], PackedInt32Array([0, 1, 0, 1, 0, 1, 0, 1]),
		"the front half keeps ranks 0-1; old rank 2, the half-file leader, leads the new file")
	assert_eq(d["walkers"], PackedByteArray([0, 0, 1, 1, 0, 0, 1, 1]))
	var hl: int = UnitFormation.SoldierRole.HEMILOCHITES
	assert_eq(d["roles"], PackedByteArray([0, 0, hl, 0, 0, 0, hl, 0]),
		"old rank 2 of each file is its hemilochites")
	var left: Dictionary = UnitFormation.explicatio_assignment(files, PackedInt32Array(), 2, false)
	assert_eq(left["files"], PackedInt32Array([1, 1, 0, 0, 3, 3, 2, 2]),
		"with the lane on the left the front half takes 2k + 1")


func test_the_half_file_deal_reads_explicit_ranks_and_splits_each_file_by_its_length() -> void:
	# File 0 holds 5 men listed rear to front; file 1 has lost one, holding 3.
	var files := PackedInt32Array([0, 0, 0, 0, 0, 1, 1, 1])
	var ranks := PackedInt32Array([4, 3, 2, 1, 0, 2, 1, 0])
	var d: Dictionary = UnitFormation.explicatio_assignment(files, ranks, 2, true)
	# File 0: h = 3, so ranks 0-2 stay in file 0 and ranks 3-4 go to file 1 as ranks 0-1.
	# File 1: h = 2, so ranks 0-1 stay in file 2 and rank 2 goes to file 3 as rank 0.
	assert_eq(d["files"], PackedInt32Array([1, 1, 0, 0, 0, 3, 2, 2]))
	assert_eq(d["ranks"], PackedInt32Array([1, 0, 2, 1, 0, 0, 1, 0]))


func test_the_alternate_rank_deal_sends_every_second_man_beside_the_man_ahead() -> void:
	# One file of five: ranks 0-4 in index order.
	var files := PackedInt32Array([0, 0, 0, 0, 0])
	var d: Dictionary = UnitFormation.explicatio_assignment(files, PackedInt32Array(), 1, true,
			ALTERNATE_RANK)
	assert_eq(d["files"], PackedInt32Array([0, 1, 0, 1, 0]),
		"ranks 1 and 3 step into the interval on the right")
	assert_eq(d["ranks"], PackedInt32Array([0, 0, 1, 1, 2]),
		"each beside the man who stood ahead of him")
	assert_eq(d["walkers"], PackedByteArray([0, 1, 0, 1, 0]))
	var ep: int = UnitFormation.SoldierRole.EPISTATES
	assert_eq(d["roles"], PackedByteArray([0, ep, 0, 0, 0]), "old rank 1 is the epistates")


func test_the_deal_refuses_inputs_that_do_not_line_up() -> void:
	assert_true((UnitFormation.explicatio_assignment(PackedInt32Array([0, 2]), PackedInt32Array(),
		2)["files"] as PackedInt32Array).is_empty(), "a file id beyond the old files")
	assert_true((UnitFormation.explicatio_assignment(PackedInt32Array(), PackedInt32Array(),
		2)["files"] as PackedInt32Array).is_empty(), "no men")
	assert_true((UnitFormation.explicatio_assignment(PackedInt32Array([0]), PackedInt32Array(),
		1, true, UnitFormation.ExplicatioDrill.NONE)["files"] as PackedInt32Array).is_empty(),
		"no drill")


func test_max_rank_count_reads_explicit_ranks_or_counts_each_file() -> void:
	assert_eq(UnitFormation.max_rank_count(PackedInt32Array([0, 0, 1]), PackedInt32Array()), 2)
	assert_eq(UnitFormation.max_rank_count(PackedInt32Array([0, 0, 1]),
		PackedInt32Array([0, 1, 4])), 5)
	assert_eq(UnitFormation.max_rank_count(PackedInt32Array(), PackedInt32Array()), 0)


func test_man_ahead_and_successor_read_the_file_order() -> void:
	var files := PackedInt32Array([1, 1, 0, 1])
	var ranks := PackedInt32Array([2, 0, 0, 1])
	assert_eq(UnitFormation.man_ahead_in_file(files, ranks), PackedInt32Array([3, -1, -1, 1]))
	assert_eq(UnitFormation.man_ahead_in_file(files, PackedInt32Array()),
		PackedInt32Array([-1, -1, -1, -1]), "no ranks, no order")
	assert_eq(UnitFormation.successor_in_file(files, ranks, 1, 1, 0), 3,
		"the man now at the fallen man's rank")
	assert_eq(UnitFormation.successor_in_file(files, ranks, 0, 1, 0), -1, "nobody behind him")
	assert_eq(UnitFormation.successor_in_file(PackedInt32Array([0, 1, 0]), PackedInt32Array(),
		0, -1, 1), 2, "without ranks, the next man of his file in index order")


func test_lane_first_waypoints_send_a_walker_sideways_until_he_is_in_his_lane() -> void:
	var slots := PackedVector2Array([Vector2(9, -10), Vector2(9, -10), Vector2(0, -10)])
	var bodies := PackedVector2Array([Vector2(0, 20), Vector2(8, 20), Vector2(0, 20)])
	var walkers := PackedByteArray([1, 1, 0])
	var out: PackedVector2Array = UnitFormation.apply_lane_first_waypoints(slots, bodies,
			walkers, 2.25)
	assert_eq(out[0], Vector2(9, 20), "off his lane: level with him in it")
	assert_eq(out[1], Vector2(9, -10), "within the tolerance: straight up to his slot")
	assert_eq(out[2], Vector2(0, -10), "not a walker: his slot")
	assert_eq(UnitFormation.apply_lane_first_waypoints(slots, PackedVector2Array(), walkers, 2.25),
		slots, "bodies that do not line up leave the slots alone")


func test_a_follower_steps_no_nearer_his_interval_than_the_man_ahead_of_him() -> void:
	# Man 1 follows man 0 into the interval at x = 9: man 0 is 6 off it, man 1 still 9 off.
	var slots := PackedVector2Array([Vector2(9, -10), Vector2(9, -5)])
	var bodies := PackedVector2Array([Vector2(3, 20), Vector2(0, 25)])
	var walkers := PackedByteArray([1, 1])
	var ahead := PackedInt32Array([-1, 0])
	var out: PackedVector2Array = UnitFormation.apply_lane_first_waypoints(slots, bodies,
			walkers, 1.0, ahead)
	assert_eq(out[0], Vector2(9, 20), "the leader steps straight into the interval")
	assert_eq(out[1], Vector2(3, 25), "the follower comes only as near as the leader stands")
	walkers[0] = 0
	out = UnitFormation.apply_lane_first_waypoints(slots, bodies, walkers, 1.0, ahead)
	assert_eq(out[1], Vector2(9, 25), "once the leader is in, the follower steps in after him")


func test_a_follower_abreast_of_his_leader_falls_in_behind_him() -> void:
	# Man 1 stands abreast of man 0, his leader, both 6 off the interval at x = 9.
	var slots := PackedVector2Array([Vector2(9, -10), Vector2(9, -1)])
	var bodies := PackedVector2Array([Vector2(3, 20), Vector2(3, 20)])
	var walkers := PackedByteArray([1, 1])
	var ahead := PackedInt32Array([-1, 0])
	var out: PackedVector2Array = UnitFormation.apply_lane_first_waypoints(slots, bodies,
			walkers, 1.0, ahead, 9.0)
	assert_eq(out[0], Vector2(9, 20), "the leader steps into the interval")
	assert_eq(out[1], Vector2(3, 29), "the follower falls in a man's place behind him")
	# On the interval's line already, the follower still waits behind the man ahead.
	bodies = PackedVector2Array([Vector2(5, 20), Vector2(9, 20)])
	out = UnitFormation.apply_lane_first_waypoints(slots, bodies, walkers, 1.0, ahead, 9.0)
	assert_eq(out[1], Vector2(9, 29), "a follower on the line waits behind the man still stepping in")
