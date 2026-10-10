extends GutTest
## A routing deep block that has to detour around impassable terrain keeps its flight pace
## and stays together. The step a router's anchor takes rounds the terrain with the block's
## own swept width, not just the anchor's margin, so the block's flank files clear the
## terrain too (Unit._rout_step_clearance); and a routing man whose run would carry him onto
## the terrain veers along it while he can still turn (SoldierBodies.router_terrain_avoid),
## instead of being held against the face by the soldier backstop.
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
const ROUTER_START := Vector2(1230.0, 1300.0)
const ENEMY_START := Vector2(900.0, 1300.0)
const MOUNTS := 80
# Ticks watched after the rout: long enough for the flight to build up (about 5.5 s for
# Cavalry), round the hill and carry the whole block past it (measured: the block's rear
# passes the hill's far face about 650 ticks after the rout), and short of the field's far
# edge, where the router escapes.
const WATCH_TICKS := 900
# The steady-state window the anchor speed is averaged over once the whole block has passed
# the hill: test_close_tier_rout_speed.gd's window.
const MEASURE_TICKS := 60
# How far the anchor's pace may sit from flee_speed() over that window: the tolerance
# test_close_tier_rout_speed.gd holds a router on open ground to.
const SPEED_TOLERANCE_FRAC := 0.1
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


func _spawn() -> Unit:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.scenario = [
		{"team": 0, "type": "Cavalry", "count": MOUNTS, "x": ROUTER_START.x, "y": ROUTER_START.y,
				"facing": [0, -1]},
		{"team": 1, "type": "Cavalry", "count": MOUNTS, "x": ENEMY_START.x, "y": ENEMY_START.y,
				"facing": [0, -1]},
	]
	add_child(_battle)
	await get_tree().physics_frame
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0:
			return unit
	return null


## Await physics frames until the battle's own tick counter advances by `n`.
func _advance_ticks(n: int) -> void:
	var target: int = _battle.current_tick() + n
	var safety: int = n * 20 + 200
	while _battle.current_tick() < target and safety > 0:
		safety -= 1
		await get_tree().physics_frame


## FACE_RECT as the typed rect list router_terrain_avoid takes.
func _face_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = [FACE_RECT]
	return rects


## How far a man running at RUN_SPEED covers while shedding it at BODY_ACCEL, plus one tick.
func _reach() -> float:
	return RUN_SPEED * RUN_SPEED / (2.0 * BODY_ACCEL) + RUN_SPEED * TICK


func test_a_deep_router_rounds_a_hill_at_flight_pace_with_its_block_together() -> void:
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 cavalry deployed")
	if router == null:
		return
	assert_eq(router.tier, FormationTier.CLOSE, "the router is simulated in the close tier")
	var half: Vector2 = router._formation_local_half_extents()
	assert_gt(half.y, half.x, "setup: a deep block (half-extents %s wu)" % half)
	assert_true(HILL.position.x < ROUTER_START.x and ROUTER_START.x < HILL.end.x,
			"setup: the hill stands across the router's line of flight")
	assert_almost_eq(router._rout_step_clearance(), half.x + router.soldier_body_radius(), 0.001,
			"the flight step rounds terrain with the block's half-width plus a body radius")
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router._rout()
	var flee_per_tick: float = router.flee_speed() / float(Engine.physics_ticks_per_second)
	# A man held at the hill: within one tick of flight travel of the backstop's edge (the
	# drawn hill grown by his body radius) and moving at under half the flight pace.
	var margin: Rect2 = HILL.grow(router.soldier_body_radius() + flee_per_tick)
	var held_speed: float = 0.5 * router.flee_speed()
	var worst_gap: float = 0.0
	var held_body_ticks: int = 0
	var cleared_tick: int = -1
	var start := Vector2.ZERO
	var pace: float = -1.0
	for k in range(WATCH_TICKS):
		await _advance_ticks(1)
		if not is_instance_valid(router) or router.state != Unit.State.ROUTING:
			break
		var slots: PackedVector2Array = router.soldier_world_slots(router.soldiers)
		for i in range(mini(slots.size(), router._sim_soldier_pos.size())):
			var p: Vector2 = router._sim_soldier_pos[i]
			worst_gap = maxf(worst_gap, p.distance_to(slots[i]))
			if margin.has_point(p) and router._sim_body_vel[i].length() < held_speed:
				held_body_ticks += 1
		# The whole block has passed the hill once its rear (half its depth behind the
		# anchor, along its northward flight) is beyond the hill's far face.
		if cleared_tick < 0 and router.position.y + half.y < HILL.position.y:
			cleared_tick = k
			start = router.position
		elif cleared_tick >= 0 and pace < 0.0 and k - cleared_tick == MEASURE_TICKS:
			pace = router.position.distance_to(start) / float(MEASURE_TICKS)
	assert_true(cleared_tick >= 0, "the whole block passed the hill within %d ticks" % WATCH_TICKS)
	assert_almost_eq(pace, flee_per_tick, flee_per_tick * SPEED_TOLERANCE_FRAC,
			"past the hill the router flees at flee_speed() (got %.3f wu/tick, flee %.3f)"
			% [pace, flee_per_tick])
	assert_eq(held_body_ticks, 0,
			"no man is held at the hill's face (man-ticks held: %d)" % held_body_ticks)
	# A man farther from his slot than the block's own corner radius has been left outside the
	# block's footprint altogether. The detour's own turns swing the corner slots off their men
	# by up to a chord of that radius, which stays inside it.
	assert_lt(worst_gap, half.length(),
			"no man falls farther from his slot than the block's corner radius %.1f (worst %.1f wu)"
			% [half.length(), worst_gap])


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


func test_a_man_already_running_away_from_the_face_is_left_alone() -> void:
	# His run still carries him at the face, but he already wants to run away from it.
	var pos := Vector2(0.0, FACE_RECT.end.y + 50.0)
	var vel := Vector2(0.0, -RUN_SPEED)
	var desired := Vector2(0.0, 80.0)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, vel, Vector2(0.0, 600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_eq(out, desired, "a man wanting to run away from the face keeps his desired velocity")
