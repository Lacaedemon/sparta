extends GutTest
## A hold-ground about-face re-square in a LIVE battle must leave the full files standing on
## the ground they hold. The staging is a 46-man Infantry block, 10 files by 4 full ranks plus a
## 6-man short rank (files 2-7), facing west, ordered to a point behind it. Its slot centroid
## sits 3.13 wu toward its front, off `position`, so SoldierBodies.couple used to read the
## turn's slot swing and the short files' step-up as drift and drag `position` back by about
## 7.7 wu, walking the 30 men of the full files backwards with it.
##
## Every assertion here is ABSOLUTE (positions against where the men stood before the order),
## not a delta against another build, so it fails on a build that still has the defect.

const COUNT := 46
const FILES := 10
const SPAWN := Vector2(900, 360)
const BEHIND := Vector2(1040, 360)   # straight behind the west-facing block
# How far a full-file man may stand off his starting point through the turn and re-square.
const HOLD_TOL := 0.5

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _stage(reform_before_move: bool) -> Unit:
	Replay.forced_seed = 90417
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": SPAWN.x, "y": SPAWN.y, "facing": [-1, 0],
			"count": COUNT, "frontage": FILES, "reform_before_move": reform_before_move},
	]
	add_child(_battle)
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 0:
			return u
	return null


## Settle the spawned bodies onto their slots.
func _settle(frames: int = 40) -> void:
	for _k in range(frames):
		await get_tree().physics_frame


## Body indices grouped by file, read off the bodies' lateral (y) coordinate: a file is the set
## of men standing at the same y. Returns [full_file_men, short_file_men].
func _split_files(u: Unit) -> Array:
	var by_file: Dictionary = {}
	for i in range(u._sim_soldier_pos.size()):
		var key: int = int(round(u._sim_soldier_pos[i].y))
		if not by_file.has(key):
			by_file[key] = []
		by_file[key].append(i)
	var deepest: int = 0
	for key in by_file:
		deepest = maxi(deepest, (by_file[key] as Array).size())
	var full: Array = []
	var short: Array = []
	for key in by_file:
		var men: Array = by_file[key]
		if men.size() == deepest:
			full.append_array(men)
		else:
			short.append_array(men)
	return [full, short]


func _order(u: Unit, dest: Vector2) -> void:
	_battle._apply_order_cmd({"units": [u.uid], "x": dest.x, "y": dest.y,
		"target": -1, "mode": 0})


## Worst distance any of `men` stands from where `before` had him.
func _worst_off(u: Unit, men: Array, before: PackedVector2Array) -> float:
	var worst: float = 0.0
	for i in men:
		worst = maxf(worst, u._sim_soldier_pos[i].distance_to(before[i]))
	return worst


func test_staging_is_ten_files_with_a_six_man_short_rank() -> void:
	var u := _stage(true)
	assert_not_null(u, "the scenario staged the block")
	if u == null:
		return
	await _settle()
	assert_eq(u.formation_files(u.soldiers), FILES, "46 men deploy 10 files wide")
	var split: Array = _split_files(u)
	assert_eq((split[0] as Array).size(), 30, "six full files of five men")
	assert_eq((split[1] as Array).size(), 16, "four short files of four men")


func test_drilled_about_face_resquare_holds_the_full_files_in_place() -> void:
	var u := _stage(true)
	assert_not_null(u, "the scenario staged the block")
	if u == null:
		return
	await _settle()
	var split: Array = _split_files(u)
	var full: Array = split[0]
	var short: Array = split[1]
	var before: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var start_anchor: Vector2 = u.position
	_order(u, BEHIND)

	# Turn, then the REFORM hold, until the march commits (or the budget runs out).
	var budget: int = int(ceil((u.order_response_delay + PI / Unit.CONVERSIO_TURN_RATE
			+ u._reform_timeout()) * Replay.PHYSICS_TPS)) + 60
	var worst_full: float = 0.0
	var worst_anchor: float = 0.0
	var saw_reform: bool = false
	for _i in range(budget):
		await get_tree().physics_frame
		if u._reform_holding():
			saw_reform = true
		if u.has_move_target:
			break
		worst_full = maxf(worst_full, _worst_off(u, full, before))
		worst_anchor = maxf(worst_anchor, u.position.distance_to(start_anchor))
	assert_true(saw_reform, "the order ran a REFORM hold after the turn")
	assert_true(u.has_move_target, "the march committed within the budget")
	assert_lt(worst_full, HOLD_TOL,
		"every full-file man held his ground through the turn and re-square (worst %.3f wu)"
			% worst_full)
	assert_lt(worst_anchor, HOLD_TOL,
		"the regiment centre held its ground until the march (worst %.3f wu)" % worst_anchor)
	# The short files stepped up one whole rank pitch toward the new (east) front, not part
	# of one: on the defect they stopped about 9.7 wu short of it.
	var pitch: float = u.rank_pitch_wu()
	for i in short:
		var step: Vector2 = u._sim_soldier_pos[i] - before[i]
		assert_almost_eq(step.x, pitch, Unit.REFORM_SETTLE_EPS,
			"short-file man %d stepped one rank pitch forward (%.3f wu)" % [i, step.x])
		assert_almost_eq(step.y, 0.0, Unit.REFORM_SETTLE_EPS,
			"short-file man %d kept his file (%.3f wu sideways)" % [i, step.y])
	assert_true(u._couple_transit.is_empty(), "every walker arrived, so no flag is left")


func test_hasty_about_face_resquare_on_arrival_holds_the_full_files_in_place() -> void:
	var u := _stage(false)
	assert_not_null(u, "the scenario staged the block")
	if u == null:
		return
	await _settle()
	var dest := SPAWN + Vector2(80, 0)   # a short rear leg so arrival fits the budget
	_order(u, dest)
	var turn_budget: int = int(ceil((u.order_response_delay + PI / Unit.CONVERSIO_TURN_RATE)
			* Replay.PHYSICS_TPS)) + 30
	for _i in range(turn_budget):
		await get_tree().physics_frame
		if u.has_move_target:
			break
	assert_true(u._reform_on_arrival, "the hasty variant parked its re-square for arrival")
	var march_budget: int = int(ceil(100.0 / maxf(u.walk_speed * 0.5, 1.0)
			* Replay.PHYSICS_TPS)) + 60
	for _i in range(march_budget):
		await get_tree().physics_frame
		if not u._reform_on_arrival:
			break
	assert_false(u._reform_on_arrival, "the re-square fired on arrival")
	assert_false(u._reform_holding(), "and it runs outside any REFORM hold")
	# From the arrival tick on, the full files must stand fast while the short files close up.
	var split: Array = _split_files(u)
	var full: Array = split[0]
	var arrived: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var arrived_anchor: Vector2 = u.position
	var settle_budget: int = int(ceil(u._reform_timeout() * Replay.PHYSICS_TPS)) + 30
	var worst_full: float = 0.0
	for _i in range(settle_budget):
		await get_tree().physics_frame
		worst_full = maxf(worst_full, _worst_off(u, full, arrived))
		if u._reform_bodies_settled():
			break
	assert_true(u._reform_bodies_settled(), "the ranks re-formed within the budget")
	assert_lt(worst_full, HOLD_TOL,
		"every full-file man held his ground through the arrival re-square (worst %.3f wu)"
			% worst_full)
	assert_lt(u.position.distance_to(arrived_anchor), HOLD_TOL,
		"the regiment centre held its ground through the arrival re-square (%.3f wu)"
			% u.position.distance_to(arrived_anchor))


## A block shoved by friends during a long re-square must still drift with the shove: only the
## walkers are left out of the coupling, so the men already on their slots carry the push into
## `position`. A whole-hold skip of coupling (no coupling at all while the REFORM hold runs)
## would leave `position` behind here.
func test_a_shove_during_the_resquare_still_moves_the_regiment() -> void:
	var u := _stage(true)
	assert_not_null(u, "the scenario staged the block")
	if u == null:
		return
	await _settle()
	_order(u, BEHIND)
	var budget: int = int(ceil((u.order_response_delay + PI / Unit.CONVERSIO_TURN_RATE)
			* Replay.PHYSICS_TPS)) + 30
	for _i in range(budget):
		await get_tree().physics_frame
		if u._reform_holding():
			break
	assert_true(u._reform_holding(), "the REFORM hold began")
	assert_false(u._couple_transit.is_empty(), "with the short-file walkers in transit")
	var y0: float = u.position.y
	# Shove every body 6 wu sideways (as a friendly regiment's push would), then let it run.
	var shove := Vector2(0, 6)
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += shove
	for _i in range(20):
		await get_tree().physics_frame
	assert_gt(u.position.y - y0, 1.0,
		"the regiment centre followed the shove (moved %.3f wu)" % (u.position.y - y0))


func test_transit_flags_only_men_whose_slot_moved() -> void:
	var u := _stage(true)
	assert_not_null(u, "the scenario staged the block")
	if u == null:
		return
	await _settle()
	var n: int = u._sim_soldier_pos.size()
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	# A man standing well off a slot that did not move (a block braking out of a flight) is
	# not in transit: the coupling must keep following him.
	u._sim_soldier_pos[0] += Vector2(30, 0)
	u.arm_couple_transit(slots, 10.0)
	assert_true(u._couple_transit.is_empty(), "no slot moved, no flag")
	# A man whose slot the re-deal moved is.
	var before: PackedVector2Array = slots.duplicate()
	before[5] += Vector2(18, 0)
	u.arm_couple_transit(before, 10.0)
	assert_eq(u._couple_transit.size(), n, "one flag per body")
	assert_eq(int(u._couple_transit[5]), 1, "the man whose slot moved is flagged")
	assert_eq(int(u._couple_transit[0]), 0, "the man merely off an unmoved slot is not")


func test_transit_flags_lapse_on_a_count_change_or_the_deadline() -> void:
	var u := _stage(true)
	assert_not_null(u, "the scenario staged the block")
	if u == null:
		return
	await _settle()
	var n: int = u._sim_soldier_pos.size()
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	before[0] += Vector2(18, 0)
	u.arm_couple_transit(before, 10.0)
	assert_true(u.couple_transit_active(n), "active at the matching count")
	assert_false(u.couple_transit_active(n - 1), "a count change clears the flags")
	assert_true(u._couple_transit.is_empty(), "and drops them")
	u.arm_couple_transit(before, 0.0)
	assert_false(u._couple_transit.is_empty(), "armed with a zero window")
	assert_false(u.couple_transit_active(n), "a lapsed deadline clears the flags")
	assert_true(u._couple_transit.is_empty(), "and drops them")


func test_transit_flags_survive_a_snapshot_round_trip() -> void:
	var u := _stage(true)
	assert_not_null(u, "the scenario staged the block")
	if u == null:
		return
	await _settle()
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	before[3] += Vector2(18, 0)
	u.arm_couple_transit(before, 10.0)
	var remaining: int = u._couple_transit_until_tick - Engine.get_physics_frames()
	var d: Dictionary = u.to_snapshot_dict()
	u.clear_couple_transit()
	u.apply_snapshot_dict(d)
	assert_eq(u._couple_transit.size(), u._sim_soldier_pos.size(), "the flags restored")
	assert_eq(int(u._couple_transit[3]), 1, "with the flagged man")
	assert_eq(u._couple_transit_until_tick - Engine.get_physics_frames(), remaining,
		"and the remaining window")
