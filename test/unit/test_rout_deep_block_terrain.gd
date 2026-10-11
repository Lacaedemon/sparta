extends GutTest
## A routing block that has to detour around impassable terrain keeps its flight pace and
## stays together.
## - The step a router's anchor takes rounds the terrain with the block's own swept width,
##   not just the anchor's margin, so the block's flank files clear the terrain too
##   (Unit._rout_step_clearance, Unit._flight_step).
## - Its heading turns onto each new flight direction at a bounded rate, so the slot grid
##   never swings its corner slots off the men in one tick (Unit._turn_flight_toward).
## - A routing man whose run would carry him onto the terrain veers along it while he can
##   still turn (SoldierBodies.router_terrain_avoid), instead of being held against the face
##   by the soldier backstop.
## - The detour never leads the block off the field.
##
## The regression this pins: the flee detour rounded the hill with the anchor's own margin
## alone, so the block's flank files ran straight on into the hill. The backstop held those
## men against its face while their slots ran on past it, and SoldierBodies.couple() --
## reading the held men as the block standing off formation -- dragged the anchor back
## toward them: the router fled at about half its pace and its block stretched by hundreds
## of world units.

const HILL := Rect2(1150.0, 380.0, 250.0, 200.0)   # Battle.TERRAIN's block rect
# The issue's staging: a default-geometry 80-mount Cavalry block routs northward from
# directly south of the default map's hill, with an idle enemy off to one side
# (all_teams_control skips team 1's AI), so nothing but the rout and the terrain moves it.
const DEEP_START := Vector2(1230.0, 1300.0)
const DEEP_ENEMY := Vector2(900.0, 1300.0)
const MOUNTS := 80
# A wide, shallow line (default 120-man Infantry) routing northward with its eastern files
# across the hill's western half.
const LINE_START := Vector2(1180.0, 1000.0)
const LINE_ENEMY := Vector2(700.0, 1000.0)
const LINE_MEN := 120
# Ticks watched after the rout: long enough for the flight to build up, round the hill and
# carry the whole block past it, and short of the field's far edge, where the router
# escapes.
const WATCH_TICKS := 900
# The steady-state window the anchor speed is averaged over once the whole block has passed
# the hill: test_close_tier_rout_speed.gd's window.
const MEASURE_TICKS := 60
# How far the anchor's pace may sit from flee_speed() over that window: the tolerance
# test_close_tier_rout_speed.gd holds a router on open ground to.
const SPEED_TOLERANCE_FRAC := 0.1
# A hill reaching almost across a narrow field, leaving its only way round 380 wu wide
# beside the field's eastern edge, with a deep block routing south from just north of it.
# Its rout ends (rout_time) and it rallies and coasts to a stop inside the watch.
const EDGE_FIELD := Rect2(0.0, 0.0, 1800.0, 2400.0)
const EDGE_HILL := Rect2(0.0, 1220.0, 1420.0, 200.0)
const EDGE_START := Vector2(1300.0, 600.0)
const EDGE_ENEMY := Vector2(900.0, 400.0)
const EDGE_WATCH_TICKS := 480
# The close-start staging (demos/inputs/deep-router-rounds-hill.json's first draft): an
# 80-mount Cavalry block already routing south, its front rank only 40 wu short of a hill
# across its eastern half, on a declared field with an idle squadron keeping it in the close
# tier. Sampled at CLOSE_START_TICK, just before its 6 s rout timer runs out.
const CLOSE_FIELD := Rect2(0.0, 0.0, 1800.0, 2400.0)
const CLOSE_HILL := Rect2(780.0, 1220.0, 260.0, 200.0)
const CLOSE_START := Vector2(820.0, 700.0)
const CLOSE_ENEMY := Vector2(1420.0, 760.0)
const CLOSE_START_TICK := 350
# The men counted as fallen out of their block: more than this far from their slots (wu).
const FALLEN_OUT_WU := 100.0
# Measured at CLOSE_START_TICK on this branch: 5 men fallen out and a worst gap of 382 wu;
# on main 12 and 426. The bounds sit one man and about 5 percent above the branch's figures,
# below main's: they pin the improvement, not a clean result.
# TODO(#1787): tighten once the close-start lag is fixed.
const CLOSE_MAX_FALLEN_OUT := 6
const CLOSE_MAX_WORST_WU := 400.0
# Pure-function fixtures for router_terrain_avoid: a rect (already grown by the body radius)
# north of a man running north, and the man's own acceleration.
const FACE_RECT := Rect2(-100.0, -300.0, 300.0, 100.0)   # south face at y = -200
const RUN_SPEED := 200.0
const BODY_ACCEL := 40.0
const TICK := 1.0 / 60.0

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


## Spawn `scenario` on the default map (or `field` and `terrain`, when given) and return the
## first unit (uid 0, the router).
func _spawn(scenario: Array, field := Rect2(), terrain: Array = []) -> Unit:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	if field.has_area():
		_battle.field = field
		_battle.terrain = terrain
	_battle.scenario = scenario
	add_child(_battle)
	await get_tree().physics_frame
	for u in get_tree().get_nodes_in_group("units") + get_tree().get_nodes_in_group("routers"):
		var unit: Unit = u as Unit
		if unit != null and unit.uid == 0:
			return unit
	return null


## Await physics frames until the battle's own tick counter advances by `n`.
func _advance_ticks(n: int) -> void:
	var target: int = _battle.current_tick() + n
	var safety: int = n * 20 + 200
	while _battle.current_tick() < target and safety > 0:
		safety -= 1
		await get_tree().physics_frame


## Rout `router` for good (no rally, no timeout) and watch it flee north past HILL for
## WATCH_TICKS. Returns {cleared: the tick its whole block passed the hill (-1 if never),
## pace: its mean anchor speed over the MEASURE_TICKS after that (wu/tick, -1 if not
## reached), held: man-ticks held at the hill's face, mean_gap: the largest mean
## body-to-slot gap over the flight (wu), turn_excess: the most any one tick turned the
## heading beyond rout_turn_rate() (rad; turns past the snap-absorb threshold excluded)}.
func _watch_flight(router: Unit) -> Dictionary:
	var half: Vector2 = router._formation_local_half_extents()
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router._rout()
	var flee_per_tick: float = router.flee_speed() / float(Engine.physics_ticks_per_second)
	var tick_s: float = 1.0 / float(Engine.physics_ticks_per_second)
	# A man held at the hill: within one tick of flight travel of the backstop's edge (the
	# drawn hill grown by his body radius) and moving at under half the flight pace.
	var margin: Rect2 = HILL.grow(router.soldier_body_radius() + flee_per_tick)
	var held_speed: float = 0.5 * router.flee_speed()
	var out := {"cleared": -1, "pace": -1.0, "held": 0, "mean_gap": 0.0, "turn_excess": 0.0}
	var start := Vector2.ZERO
	var heading: float = router.facing.angle()
	for k in range(WATCH_TICKS):
		await _advance_ticks(1)
		if not is_instance_valid(router) or router.state != Unit.State.ROUTING:
			break
		var turned: float = absf(angle_difference(heading, router.facing.angle()))
		heading = router.facing.angle()
		if turned <= Unit.FACING_SNAP_ABSORB_THRESHOLD:
			out["turn_excess"] = maxf(out["turn_excess"], turned - router.rout_turn_rate() * tick_s)
		var slots: PackedVector2Array = router.soldier_world_slots(router.soldiers)
		var n: int = mini(slots.size(), router._sim_soldier_pos.size())
		var gap_sum: float = 0.0
		for i in range(n):
			var p: Vector2 = router._sim_soldier_pos[i]
			gap_sum += p.distance_to(slots[i])
			if margin.has_point(p) and router._sim_body_vel[i].length() < held_speed:
				out["held"] += 1
		out["mean_gap"] = maxf(out["mean_gap"], gap_sum / float(maxi(1, n)))
		# The whole block has passed the hill once its rear (half its depth behind the
		# anchor, along its northward flight) is beyond the hill's far face.
		if out["cleared"] < 0 and router.position.y + half.y < HILL.position.y:
			out["cleared"] = k
			start = router.position
		elif out["cleared"] >= 0 and out["pace"] < 0.0 and k - out["cleared"] == MEASURE_TICKS:
			out["pace"] = router.position.distance_to(start) / float(MEASURE_TICKS)
	return out


func test_a_deep_router_rounds_a_hill_at_flight_pace_with_its_block_together() -> void:
	var router: Unit = await _spawn([
		{"team": 0, "type": "Cavalry", "count": MOUNTS, "x": DEEP_START.x, "y": DEEP_START.y,
				"facing": [0, -1]},
		{"team": 1, "type": "Cavalry", "count": MOUNTS, "x": DEEP_ENEMY.x, "y": DEEP_ENEMY.y,
				"facing": [0, -1]},
	])
	assert_not_null(router, "the team-0 cavalry deployed")
	if router == null:
		return
	assert_eq(router.tier, FormationTier.CLOSE, "the router is simulated in the close tier")
	var half: Vector2 = router._formation_local_half_extents()
	assert_gt(half.y, half.x, "setup: a deep block (half-extents %s wu)" % half)
	assert_true(HILL.position.x < DEEP_START.x and DEEP_START.x < HILL.end.x,
			"setup: the hill stands across the router's line of flight")
	assert_almost_eq(router._rout_step_clearance(), half.x + router.soldier_body_radius(), 0.001,
			"the flight step rounds terrain with the block's half-width plus a body radius")
	var flee_per_tick: float = router.flee_speed() / float(Engine.physics_ticks_per_second)
	var rank_pitch: float = router.rank_pitch_wu()
	var r: Dictionary = await _watch_flight(router)
	assert_true(r["cleared"] >= 0, "the whole block passed the hill within %d ticks" % WATCH_TICKS)
	assert_almost_eq(r["pace"], flee_per_tick, flee_per_tick * SPEED_TOLERANCE_FRAC,
			"past the hill the router flees at flee_speed() (got %.3f wu/tick, flee %.3f)"
			% [r["pace"], flee_per_tick])
	assert_eq(r["held"], 0, "no man is held at the hill's face (man-ticks held: %d)" % r["held"])
	# The block holds together through the whole detour: on average, a man never stands
	# farther from his place than the distance between two of the block's ranks.
	assert_lt(r["mean_gap"], rank_pitch,
			"mean body-to-slot gap stays under one rank pitch %.1f (largest %.1f wu)"
			% [rank_pitch, r["mean_gap"]])
	assert_almost_eq(r["turn_excess"], 0.0, 0.0001,
			"the heading never turns faster than rout_turn_rate() (excess %.4f rad)" % r["turn_excess"])


func test_a_wide_shallow_line_rounds_a_hill_without_pinning_its_flank() -> void:
	# The swept width applies to any block wider than the anchor's own margin, not only a
	# deep one: a wide line's flank files sweep the terrain the anchor passes just the same.
	var router: Unit = await _spawn([
		{"team": 0, "type": "Infantry", "count": LINE_MEN, "x": LINE_START.x, "y": LINE_START.y,
				"facing": [0, -1]},
		{"team": 1, "type": "Infantry", "count": LINE_MEN, "x": LINE_ENEMY.x, "y": LINE_ENEMY.y,
				"facing": [0, -1]},
	])
	assert_not_null(router, "the team-0 infantry deployed")
	if router == null:
		return
	var half: Vector2 = router._formation_local_half_extents()
	assert_gt(half.x, half.y, "setup: a wide, shallow line (half-extents %s wu)" % half)
	assert_gt(LINE_START.x + half.x, HILL.position.x,
			"setup: the line's eastern files stand across the hill's line")
	var flee_per_tick: float = router.flee_speed() / float(Engine.physics_ticks_per_second)
	var r: Dictionary = await _watch_flight(router)
	assert_true(r["cleared"] >= 0, "the whole line passed the hill within %d ticks" % WATCH_TICKS)
	assert_almost_eq(r["pace"], flee_per_tick, flee_per_tick * SPEED_TOLERANCE_FRAC,
			"past the hill the line flees at flee_speed() (got %.3f wu/tick, flee %.3f)"
			% [r["pace"], flee_per_tick])
	assert_eq(r["held"], 0, "no man is held at the hill's face (man-ticks held: %d)" % r["held"])


func test_a_detour_beside_the_field_edge_keeps_the_block_on_the_field() -> void:
	# The only way round leaves too little room for the block's swept width beside the
	# field's edge: the flight falls back to the anchor's own margin rather than leading the
	# block off the field, so the rally's coast that follows stays on it too.
	var router: Unit = await _spawn([
		{"team": 1, "type": "Cavalry", "count": MOUNTS, "x": EDGE_START.x, "y": EDGE_START.y,
				"facing": [0, 1]},
		{"team": 0, "type": "Cavalry", "count": 24, "x": EDGE_ENEMY.x, "y": EDGE_ENEMY.y,
				"facing": [1, 0]},
	], EDGE_FIELD, [{"rect": EDGE_HILL, "type": "hill", "kind": "block"}])
	assert_not_null(router, "the team-1 cavalry deployed")
	if router == null:
		return
	assert_eq(router.tier, FormationTier.CLOSE, "the router is simulated in the close tier")
	router.morale = 0.0
	router._rout()
	var off_field: int = 0
	var rallied: bool = false
	for k in range(EDGE_WATCH_TICKS):
		await _advance_ticks(1)
		if not is_instance_valid(router):
			break
		rallied = rallied or router.state == Unit.State.IDLE
		for p in router._sim_soldier_pos:
			if not EDGE_FIELD.has_point(p):
				off_field += 1
	assert_true(is_instance_valid(router), "the router stayed in play")
	if not is_instance_valid(router):
		return
	assert_true(rallied, "setup: the router rallied inside the watch")
	assert_eq(off_field, 0, "no man left the field (man-ticks off it: %d)" % off_field)
	assert_true(EDGE_FIELD.has_point(router.position),
			"the rallied anchor stands on the field (%s)" % router.position)


func test_a_close_start_router_keeps_more_of_its_front_than_before() -> void:
	# A block whose front rank starts within a few strides of the hill cannot turn away in
	# time, so its leading men still meet the hill's face and fall behind. This pins the
	# improvement over the anchor-margin detour.
	# TODO(#1787): the leading men of a close-start block still fall behind.
	var router: Unit = await _spawn([
		{"team": 1, "type": "Cavalry", "count": MOUNTS, "x": CLOSE_START.x, "y": CLOSE_START.y,
				"morale": 1.0, "starting_state": 3, "facing": [0, 1]},
		{"team": 0, "type": "Cavalry", "count": 24, "x": CLOSE_ENEMY.x, "y": CLOSE_ENEMY.y,
				"facing": [-1, 0]},
	], CLOSE_FIELD, [{"rect": CLOSE_HILL, "type": "hill", "kind": "block"}])
	assert_not_null(router, "the team-1 cavalry deployed")
	if router == null:
		return
	await _advance_ticks(CLOSE_START_TICK - _battle.current_tick())
	assert_eq(_battle.current_tick(), CLOSE_START_TICK, "setup: sampled at tick %d" % CLOSE_START_TICK)
	assert_eq(router.state, Unit.State.ROUTING, "setup: still routing at the sample")
	assert_eq(router.tier, FormationTier.CLOSE, "setup: still in the close tier")
	var slots: PackedVector2Array = router.soldier_world_slots(router.soldiers)
	var fallen_out: int = 0
	var worst: float = 0.0
	for i in range(mini(slots.size(), router._sim_soldier_pos.size())):
		var gap: float = router._sim_soldier_pos[i].distance_to(slots[i])
		worst = maxf(worst, gap)
		if gap > FALLEN_OUT_WU:
			fallen_out += 1
	assert_lte(fallen_out, CLOSE_MAX_FALLEN_OUT,
			"at most %d men more than %.0f wu off their slots (got %d)"
			% [CLOSE_MAX_FALLEN_OUT, FALLEN_OUT_WU, fallen_out])
	assert_lt(worst, CLOSE_MAX_WORST_WU, "worst body-to-slot gap under %.0f wu (got %.1f)"
			% [CLOSE_MAX_WORST_WU, worst])


func test_a_turning_router_feeds_its_turn_forward_to_its_men() -> void:
	# Each unengaged man of a router turning its flight is carried with his slot's own turning
	# velocity, turn rate x the slot's offset from the anchor turned a quarter, not only the
	# march.
	var router: Unit = await _spawn([
		{"team": 0, "type": "Cavalry", "count": MOUNTS, "x": DEEP_START.x, "y": DEEP_START.y,
				"facing": [0, -1]},
		{"team": 1, "type": "Cavalry", "count": MOUNTS, "x": DEEP_ENEMY.x, "y": DEEP_ENEMY.y,
				"facing": [0, -1]},
	])
	assert_not_null(router, "the team-0 cavalry deployed")
	if router == null:
		return
	router._rout()
	router._in_enemy_contact = false
	router._flee_velocity = Vector2.ZERO
	var rate: float = 0.1
	router._flight_turn_rate = rate
	router._sim_soldier_pos = router.soldier_world_slots(router.soldiers)
	for i in range(router._sim_body_vel.size()):
		router._sim_body_vel[i] = Vector2.ZERO
	SoldierBodies.step(router, TICK)
	var slots: PackedVector2Array = router.soldier_world_slots(router.soldiers)
	var corner: int = slots.size() - 1
	var arm: Vector2 = slots[corner] - router.position
	var expected: Vector2 = Vector2(-arm.y, arm.x) * rate
	var got: Vector2 = router._sim_body_vel[corner]
	assert_gt(got.length(), 0.0, "the corner man starts moving with his turning slot")
	assert_almost_eq(got.normalized().dot(expected.normalized()), 1.0, 0.001,
			"along his slot's turning velocity (got %s, slot moves %s)" % [got, expected])


## FACE_RECT as the typed rect list router_terrain_avoid takes.
func _face_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = [FACE_RECT]
	return rects


## How far a man running at RUN_SPEED covers while shedding it at BODY_ACCEL, plus one tick.
func _reach() -> float:
	return RUN_SPEED * RUN_SPEED / (2.0 * BODY_ACCEL) + RUN_SPEED * TICK


func test_a_run_that_clears_the_terrain_is_left_alone() -> void:
	# Running north past the rect's west end: his run never meets it.
	var pos := Vector2(FACE_RECT.position.x - 1.0, 0.0)
	var desired := Vector2(0.0, -RUN_SPEED)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, desired, pos + Vector2(0.0, -900.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_eq(out, desired, "a run clear of the terrain keeps its desired velocity")


func test_a_run_beyond_turning_reach_of_the_face_is_left_alone() -> void:
	# The face lies just past the distance he needs to turn his run: not yet his concern.
	var pos := Vector2(0.0, FACE_RECT.end.y + _reach() + 1.0)
	var desired := Vector2(0.0, -RUN_SPEED)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, desired, Vector2(-300.0, -600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_eq(out, desired, "a face beyond his turning reach leaves his desired velocity alone")


func test_a_run_at_a_face_turns_along_it_toward_the_shorter_way_round() -> void:
	# Within turning reach of the south face, running straight at it, with his slot beyond the
	# rect to the north-west: the west end is the shorter way round.
	var pos := Vector2(0.0, FACE_RECT.end.y + _reach() - 1.0)
	var desired := Vector2(0.0, -RUN_SPEED)
	var west: Vector2 = SoldierBodies.router_terrain_avoid(pos, desired, Vector2(-300.0, -600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(west.x, -RUN_SPEED, 0.001, "he runs west along the face at the same speed")
	assert_almost_eq(west.y, 0.0, 0.001, "with nothing left heading into the face")
	# The same run with his slot beyond the rect to the north-east goes round by the east end.
	var east: Vector2 = SoldierBodies.router_terrain_avoid(pos, desired, Vector2(500.0, -600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(east.x, RUN_SPEED, 0.001, "he runs east along the face at the same speed")
	assert_almost_eq(east.y, 0.0, 0.001, "with nothing left heading into the face")


func test_the_way_round_counts_the_far_corner_when_the_straight_way_on_crosses_the_rect() -> void:
	# His slot lies just beyond the rect's north face, over its western half, and he stands
	# near the east end. In straight lines the east end looks shorter (348 wu against 385),
	# but from either end the straight line on to his slot crosses the rect; counted round the
	# far corners, the west end is shorter (409 wu against 422).
	var pos := Vector2(150.0, FACE_RECT.end.y + 50.0)
	var desired := Vector2(0.0, -RUN_SPEED)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, desired, Vector2(-50.0, -320.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(out.x, -RUN_SPEED, 0.001, "he goes round by the west end")
	assert_almost_eq(out.y, 0.0, 0.001, "with nothing left heading into the face")


func test_a_slot_on_his_own_side_turns_him_toward_it() -> void:
	# His run carries him at the face, but his slot is on his own side of it, to the east:
	# he only has to stop running into the rock, so he turns east, toward the slot.
	var pos := Vector2(0.0, FACE_RECT.end.y + 50.0)
	var vel := Vector2(0.0, -RUN_SPEED)
	var desired := Vector2(0.0, -RUN_SPEED)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, vel, Vector2(150.0, -100.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(out.x, RUN_SPEED, 0.001, "he turns east, toward his slot")
	assert_almost_eq(out.y, 0.0, 0.001, "with nothing left heading into the face")


func test_only_the_part_heading_into_the_face_is_turned() -> void:
	# A run carrying him at the face while he already wants to go partly sideways keeps that
	# sideways part and has only the part heading in turned along the face.
	var pos := Vector2(0.0, FACE_RECT.end.y + 50.0)
	var vel := Vector2(0.0, -RUN_SPEED)
	var desired := Vector2(-30.0, -150.0)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, vel, Vector2(-300.0, -600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(out.x, -180.0, 0.001, "sideways part kept, the inward 150 turned west")
	assert_almost_eq(out.y, 0.0, 0.001, "nothing left heading into the face")


func test_a_man_standing_at_the_face_is_turned_too() -> void:
	# Standing still on the face (no run to look along), wanting to go straight into it:
	# where he wants to go this tick meets the face, so that is turned along it.
	var pos := Vector2(0.0, FACE_RECT.end.y)
	var desired := Vector2(0.0, -RUN_SPEED)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, Vector2.ZERO, Vector2(-300.0, -600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(out.x, -RUN_SPEED, 0.001, "he runs west along the face")
	assert_almost_eq(out.y, 0.0, 0.001, "with nothing left heading into the face")


func test_a_man_already_running_away_from_the_face_is_left_alone() -> void:
	# His run still carries him at the face, but he already wants to run away from it.
	var pos := Vector2(0.0, FACE_RECT.end.y + 50.0)
	var vel := Vector2(0.0, -RUN_SPEED)
	var desired := Vector2(0.0, 80.0)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, vel, Vector2(0.0, 600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_eq(out, desired, "a man wanting to run away from the face keeps his desired velocity")
