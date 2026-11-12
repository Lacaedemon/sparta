extends GutTest
## The explicatio as the drill manuals describe it: the front stays where it stands, and the men
## who change file step sideways into the interval beside their own file and come up it in
## column, the man who leads the column first and nobody passing the man ahead of him. Nobody
## walks to a slot laid out from the unit's position: each man follows a man he can see
## (SoldierFollow, UnitFormation.explicatio_follow_plan), and the block's position is read off
## its men. Two drills choose who changes file (UnitFormation.ExplicatioDrill):
## - HALF_FILE, the default: each file's rear half, led by its half-file leader, the hemilochites
##   (Asclepiodotus, Tactics 2.2; Xenophon, Cyropaedia 2.3.21).
## - ALTERNATE_RANK: every second man, led by the epistates behind the file leader (Bingham's
##   notes on Aelian ch. 29; the ancient source is not yet verified).
##
## The live tests stage a lone block of Spearmen in drill mode and widen it through the order
## the B key issues (Battle.enqueue_file_double).

const SPAWN := Vector2(500, 300)
const SPEARMEN := 140
## Ticks for the drill to play out: the half-file drill measured on this build ends by tick 560
## centred and tick 730 held on a flank.
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
		var parity: int = u._explicatio_stay_parity
		var end_line: float = 0.0
		for i in range(u.soldiers):
			if u._sim_soldier_rank[i] != 0:
				continue
			var off: float = absf(u._sim_soldier_pos[i].dot(forward) - front0)
			end_line = maxf(end_line, off)
			if posmod(u._sim_soldier_file[i], 2) == parity:
				out["line"] = maxf(out["line"], off)
		if not u.explicatio_drill_active():
			out["ended"] = t
			out["end_line"] = end_line
			break
		var ahead_of: PackedInt32Array = UnitFormation.man_ahead_in_file(u._sim_soldier_file,
				u._sim_soldier_rank)
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
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var worst: float = 0.0
	for i in range(u.soldiers):
		worst = maxf(worst, slots[i].distance_to(u._sim_soldier_pos[i]))
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
		if u._sim_soldier_file[i] % 2 == 1:
			rear.append(i)
	assert_eq(rear.size(), 68, "precondition: 68 rear men step into the intervals")
	var gained: Dictionary = {}
	var off_line_ticks: int = 0
	for _t in range(DRILL_TICKS):
		if not u.explicatio_drill_active():
			break
		var before: PackedVector2Array = u._sim_soldier_pos.duplicate()
		var places: PackedVector2Array = u._explicatio_follow(u.soldiers)["places"]
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
## flank. Held on the right flank, main's deal brought two men to 1.68 wu.
func test_no_two_men_come_onto_each_other() -> void:
	for anchor in [UnitFormation.Anchor.CENTRE, UnitFormation.Anchor.RIGHT,
			UnitFormation.Anchor.LEFT]:
		var units: Array = await _stage([_spearmen()])
		var u: Unit = units[0]
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
		_battle.free()
		_battle = null
		await get_tree().physics_frame


## A block on the march keeps main's lateral deal for now: the drill is for a block standing
## still, and no man is set to follow another.
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


## A drill starts from files and ranks the men stand in: ordered while a duplicatio is still
## walking, the widen keeps main's lateral deal. Started from there, the follow plan ran from
## men who were not yet in their files and never settled within 900 ticks.
func test_an_explicatio_during_a_duplicatio_is_not_dealt_the_drill() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], -1)
	await _run(110)
	_battle.enqueue_file_double([u.uid], 1)
	assert_false(u.explicatio_drill_active(), "no drill from a block still reshaping")


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
				# A standing mirror, and the men re-formed on it, as an about-face leaves them.
				u._formation_mirror_x = true
				await _run(DRILL_TICKS)
			_battle.enqueue_file_double([u.uid], 1)
			assert_true(u.explicatio_drill_active(), "precondition: the widen is the drill")
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


# --- The column and its leader, live ---------------------------------------------


## Each half-file's leader, the man who stood at the head of its rear half, is its hemilochites,
## heads his new file and comes up beside his own file leader.
func test_the_hemilochites_comes_up_beside_his_file_leader() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	var leaders: int = 0
	for i in range(u.soldiers):
		if u.soldier_role(i) != UnitFormation.SoldierRole.HEMILOCHITES:
			continue
		leaders += 1
		assert_eq(u._sim_soldier_rank[i], 0, "the hemilochites heads his new file")
		var lead: int = u.follow_leader(i)
		assert_gte(lead, 0, "the hemilochites follows a man")
		assert_eq(u._sim_soldier_file[lead], u._sim_soldier_file[i] - 1,
			"he follows the leader of the file he opened from")
		assert_eq(u._sim_soldier_rank[lead], 0, "that man is its file leader")
	assert_eq(leaders, 9, "one hemilochites for each old file")


## Every man behind a file leader follows the man ahead of him in his file, and nobody gets ahead
## of him along the facing while the drill runs: a man who stands abreast of him is held to a
## quarter of a rank pitch of body jitter.
func test_nobody_passes_the_man_ahead_of_him() -> void:
	var units: Array = await _stage([_spearmen()])
	var u: Unit = units[0]
	_battle.enqueue_file_double([u.uid], 1)
	var ahead: PackedInt32Array = UnitFormation.man_ahead_in_file(u._sim_soldier_file,
			u._sim_soldier_rank)
	for i in range(u.soldiers):
		if ahead[i] >= 0:
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
		if u.soldier_role(i) == UnitFormation.SoldierRole.HEMILOCHITES:
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
	assert_eq(u.soldier_role(heir_now), UnitFormation.SoldierRole.HEMILOCHITES,
		"the man behind him took the lead")
	assert_eq(u._sim_soldier_rank[heir_now], 0, "and heads the file")
	assert_eq(_count_role(u, UnitFormation.SoldierRole.HEMILOCHITES), 9,
		"each half-file still has one leader")
	assert_gte(walk["ended"], 0, "the drill still ended")
	assert_lt(walk["overtake"], 0.25 * u.rank_pitch_wu(),
		"the farthest any man got ahead of the man ahead of him is %.2f wu" % walk["overtake"])


## Each man's role is his own: a snapshot carries it, and a reinforcement's bodies appended to
## the block leave the host's leaders on the host's men and add the reserve's own. A snapshot
## also carries the drill under way.
func test_the_roles_and_the_drill_ride_a_snapshot_and_a_reinforcement() -> void:
	var units: Array = await _stage([_spearmen(), _spearmen([0, 1], Vector2(800, 300))])
	var u: Unit = units[0]
	var reserve: Unit = units[1]
	_battle.enqueue_file_double([u.uid], 1)
	var roles: PackedByteArray = u._sim_soldier_role.duplicate()
	assert_eq(roles.size(), SPEARMEN, "precondition: every man has a role entry")
	var snap: Dictionary = u.to_snapshot_dict()
	var stand: Vector2 = u._explicatio_stand_point
	u._sim_soldier_role = PackedByteArray()
	u._end_explicatio_drill()
	u.apply_snapshot_dict(snap)
	assert_eq(u._sim_soldier_role, roles, "the snapshot restores each man's role")
	assert_true(u.explicatio_drill_active(), "the snapshot restores the drill under way")
	assert_eq(u._explicatio_stand_point, stand, "and the ground its standing file holds")
	reserve._sim_soldier_role = PackedByteArray()
	reserve._sim_soldier_role.resize(reserve._sim_soldier_pos.size())
	reserve._sim_soldier_role[0] = UnitFormation.SoldierRole.EPISTATES
	u.append_soldier_bodies(reserve)
	assert_eq(u._sim_soldier_role.size(), u._sim_soldier_pos.size(), "one role for each body")
	assert_eq(u._sim_soldier_role.slice(0, SPEARMEN), roles, "the host's men keep theirs")
	assert_eq(u._sim_soldier_role[SPEARMEN], UnitFormation.SoldierRole.EPISTATES,
		"the reserve's men bring theirs")


# --- The alternate-rank drill, live -----------------------------------------------


## The alternate-rank drill, chosen on the order: every second man steps into the interval beside
## the man who stood ahead of him, led by the epistates, without anyone passing the man ahead of
## him or two men coming onto each other, and the drill ends with the files doubled. Its front
## does not hold as well as the half-file drill's: each epistates comes up from one rank behind
## his file leader while the line is still opening, overshoots, and steps back. This build
## measured the front up to 5.0 wu ahead centred and 4.2 wu held on the right, so the bound is
## two thirds of a rank pitch (6 wu) until the files open before the epistatai step in.
func test_the_alternate_rank_drill_keeps_its_columns() -> void:
	for anchor in [UnitFormation.Anchor.CENTRE, UnitFormation.Anchor.RIGHT]:
		var units: Array = await _stage([_spearmen()])
		var u: Unit = units[0]
		var floor_wu: float = 2.0 * u.soldier_body_radius() * DemoDefects.OVERLAP_BODY_FRAC
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
		assert_lt(walk["ahead"], 2.0 / 3.0 * u.rank_pitch_wu(),
			"anchor %d: the front went %.2f wu ahead" % [anchor, walk["ahead"]])
		assert_lt(walk["end_line"], 0.25 * u.rank_pitch_wu(),
			"anchor %d: a man of the front rank ended %.2f wu off its line" % [anchor, walk["end_line"]])
		assert_gt(walk["behind"], -0.25 * u.rank_pitch_wu(),
			"anchor %d: the front fell %.2f wu back" % [anchor, -walk["behind"]])
		_battle.free()
		_battle = null
		await get_tree().physics_frame


## The drill rides the recorded order: the replay entry carries it, and a combo's widen step
## carries it through Order.to_dict and back.
func test_the_drill_rides_the_order_and_the_replay() -> void:
	var entry: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18,
			INF, 0, 0.0, -1, 0, 0, -1, -1, 0, ALTERNATE_RANK)
	assert_eq(entry["explicatio"], ALTERNATE_RANK, "the replay entry names the drill")
	var plain: Dictionary = Replay.ReplayOrderEntryRef.build(5, [1], Vector2.ZERO, -4, 0, 0, 18)
	assert_false(plain.has("explicatio"), "a plain resize records no drill")
	var decoder := preload("res://scripts/ReplayDecoder.gd")
	assert_eq(decoder._decode_order({"units": [1], "explicatio": ALTERNATE_RANK})["explicatio"],
		ALTERNATE_RANK, "playback reads the drill back")
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


## Six files after the deal: 0, 2, 4 stay (even, the lane on the right) and 1, 3, 5 are
## intervals; file 2 stands. Each file holds two ranks.
func test_the_follow_plan_names_whom_each_man_follows() -> void:
	var files := PackedInt32Array([0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
	var ranks := PackedInt32Array([0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1])
	var p: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, 0, 2, 9.0, 8.0)
	var leaders: PackedInt32Array = p["leaders"]
	var offsets: PackedVector2Array = p["offsets"]
	var flanks: PackedInt32Array = p["flanks"]
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
	assert_eq(flanks[2], 4, "and sees the gap open to file 2's leader")
	assert_eq(leaders[10], 8, "file 5's leader comes up beside file 4's")
	assert_eq(flanks[10], -1, "his interval is on the flank: nobody beyond it")
	assert_eq(flanks[0], -1, "a file that stays steps into no gap")
	var guides: PackedInt32Array = p["guides"]
	for i in [0, 2, 6, 8, 10]:
		assert_eq(guides[i], 4, "file leader %d dresses on the guide himself" % i)
	assert_eq(guides[4], SoldierFollow.STAND, "the guide dresses on no one")
	for i in [1, 3, 5, 7, 9, 11]:
		assert_eq(guides[i], SoldierFollow.NOT_FOLLOWING, "man %d dresses on no guide" % i)


func test_the_follow_plan_skips_a_fallen_link() -> void:
	# File 2's leader has fallen and nobody closed up: file 0's leader dresses on file 4's,
	# which stands, four pitches off.
	var files := PackedInt32Array([0, 2, 4])
	var ranks := PackedInt32Array([0, 1, 0])
	var p: Dictionary = UnitFormation.explicatio_follow_plan(files, ranks, 0, 4, 9.0, 8.0)
	assert_eq(p["leaders"][0], 2, "the next file leader along the chain")
	assert_eq(p["offsets"][0], Vector2(-36, 0))
	assert_eq(p["leaders"][1], SoldierFollow.HOLD, "a man with nobody ahead of him holds")
	assert_true((UnitFormation.explicatio_follow_plan(files, PackedInt32Array([0]), 0, 4, 9.0,
		8.0)["leaders"] as PackedInt32Array).is_empty(), "ranks that do not line up")


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


func test_room_between_two_men_opens_from_shoulder_to_shoulder() -> void:
	var f := Vector2(0, 1)
	assert_eq(SoldierFollowSteer.room_between(Vector2(0, 0), Vector2(9, 3), f, 9.0), 0.0,
		"shoulder to shoulder: no room")
	assert_eq(SoldierFollowSteer.room_between(Vector2(0, 0), Vector2(13.5, 0), f, 9.0), 0.5)
	assert_eq(SoldierFollowSteer.room_between(Vector2(0, 0), Vector2(-27, 0), f, 9.0), 1.0,
		"two pitches or more apart: all the room")
	assert_eq(SoldierFollowSteer.room_between(Vector2(0, 0), Vector2(1, 0), f, 0.0), 1.0,
		"no line width: all the room")
