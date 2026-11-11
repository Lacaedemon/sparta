extends GutTest
## A router's flight velocity (Unit._flee_velocity) changes no faster than the flight share
## can hand on to its men (Unit.flight_velocity_accel): the share's cap,
## flight_share_max_accel_mult times the bodies' own acceleration
## (SoldierBodies.flight_accel_share). A flight that changes no faster than that is one the
## share alone keeps a man level with, so his own acceleration stays free to close on his slot.
## - The side-step along a face (Unit._flight_front_veer) turns the flight over several ticks
##   as it starts and ends, and the flight step leaving its turn-back hold
##   (Unit._flight_step) does too, instead of the velocity swinging in one tick.
## - Since the flight turns at that rate, the leading rank looks along the flight it carries as
##   far as it runs while turning off at that rate, so the side-step starts in time.
## - A rout carries the pace the unit was already making away from the enemy on as its
##   first flight velocity, so the anchor's speed runs on unbroken through the rout.
## - The rate never drops below the unit's own acceleration, so a share multiplier of 0
##   cannot freeze a router, and the stamina bill and a rally's coast read the speed the
##   flight runs.
## - The flight step's turn-back reads the leg the flight was steered on last tick, not the
##   lagging flight velocity, so it holds only after a detour leg.
##
## The regression this pins: on demos/inputs/deep-router-close-start-hill.json (clip seed,
## Windows, main aef5b476, 2026-11-10, by a temporary per-tick log) the flight velocity
## swung in one tick as the side-step started (tick 73: 1.02 rad at 48.7 wu/s, 2826 wu/s^2)
## and ended (tick 154: 1.11 rad at 102.7 wu/s, 6477 wu/s^2), and as the flight step held its
## heading for one tick and left it (ticks 338 and 339: 0.36 and 0.39 rad at 221 wu/s, 4756
## and 5160 wu/s^2), against a share cap of 80 wu/s^2.

# The close-start staging (demos/inputs/deep-router-close-start-hill.json): an 80-mount
# Cavalry block already routing south, its front rank 40 wu short of a hill across its
# eastern half, with an idle squadron keeping it in the close tier. Watched to tick 352, the
# clip's end, just before the 6 s rout timer runs out.
const MOUNTS := 80
const CLOSE_FIELD := Rect2(0.0, 0.0, 1800.0, 2400.0)
const CLOSE_HILL := Rect2(780.0, 1220.0, 260.0, 200.0)
const CLOSE_START := Vector2(820.0, 700.0)
const CLOSE_ENEMY := Vector2(1420.0, 760.0)
const CLOSE_END_TICK := 352
# A step point well west and south of the hill sends the flight round its west end.
const WEST_STEP := Vector2(300.0, 1700.0)
# A spot well clear of the hill and the field's edges.
const OPEN_GROUND := Vector2(300.0, 300.0)
# How far either side of a look's exact reach the boundary fixtures place the face (wu): well
# above float32 rounding at these coordinates, well below one tick of travel.
const LOOK_MARGIN_WU := 0.5
const TICK := 1.0 / 60.0
# The relative rounding of one float32 component (2^-23): Vector2 stores float32, so a
# velocity change read back from two stored velocities carries up to that much of each
# component's size as rounding.
const FLOAT32_EPS := 1.0 / 8388608.0
# The longest a turn-back hold can last after a detour leg: the held tick clears
# Unit._flight_leg_was_detour, which the hold needs, so the tick after it cannot hold.
const HOLD_TICKS_MAX := 1
# Ticks watched after the detour leg for the hold to release: enough that a self-sustaining
# hold would show.
const HOLD_WATCH_TICKS := 30

var _battle: Node = null


func after_each() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


func _spawn_close() -> Unit:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.field = CLOSE_FIELD
	_battle.terrain = [{"rect": CLOSE_HILL, "type": "hill", "kind": "block"}]
	_battle.scenario = [
		{"team": 1, "type": "Cavalry", "count": MOUNTS, "x": CLOSE_START.x, "y": CLOSE_START.y,
				"morale": 1.0, "starting_state": 3, "facing": [0, 1]},
		{"team": 0, "type": "Cavalry", "count": 24, "x": CLOSE_ENEMY.x, "y": CLOSE_ENEMY.y,
				"facing": [-1, 0]},
	]
	add_child(_battle)
	await get_tree().physics_frame
	for u in get_tree().get_nodes_in_group("units") + get_tree().get_nodes_in_group("routers"):
		var unit: Unit = u as Unit
		if unit != null and unit.uid == 0:
			return unit
	return null


## The most extra acceleration the flight share hands a routing man (wu/s^2), read off the
## same fields SoldierBodies.step reads: the bound the flight velocity is held to.
func _share_cap(unit: Unit) -> float:
	return maxf(unit.accel, SoldierBodies.BODY_ACCEL_FLOOR) * unit.flight_share_max_accel_mult


## How far a flight at `speed` runs while shedding it at the share cap, plus one tick.
func _look(unit: Unit, speed: float) -> float:
	return speed * speed / (2.0 * _share_cap(unit)) + speed * TICK


## Move the router so the centre of its leading rank line stands `short` wu north of the
## hill's north face grown by a body radius, at the hill's own x, fleeing south at full pace.
func _place_front(router: Unit, short: float) -> void:
	var offset: Vector2 = router._flight_front_line()[0] - router.position
	var face_y: float = CLOSE_HILL.position.y - router.soldier_body_radius()
	router.position = Vector2(CLOSE_START.x, face_y - short) - offset
	router._flee_pace = router.flee_speed()
	router._flee_velocity = Vector2.DOWN * router._flee_pace


func test_the_close_start_flight_changes_no_faster_than_the_share_cap() -> void:
	var router: Unit = await _spawn_close()
	assert_not_null(router, "the team-1 cavalry deployed")
	if router == null:
		return
	var cap: float = _share_cap(router)
	var tol: float = 4.0 * router.flee_speed() * FLOAT32_EPS / TICK
	var worst: float = 0.0
	var worst_tick: int = -1
	var veered: int = 0
	var prev: Vector2 = router._flee_velocity
	while _battle.current_tick() < CLOSE_END_TICK:
		var tick: int = _battle.current_tick()
		await get_tree().physics_frame
		if _battle.current_tick() == tick:
			continue
		assert_eq(router.state, Unit.State.ROUTING, "setup: still routing at tick %d" % tick)
		if router.state != Unit.State.ROUTING:
			return
		var now: Vector2 = router._flee_velocity
		var rate: float = (now - prev).length() / TICK
		if rate > worst:
			worst = rate
			worst_tick = _battle.current_tick()
		# The side-step runs the flight west, against a step that rounds the hill to the
		# south-west.
		if now.x < 0.0 and absf(now.y) < 0.5 * now.length():
			veered += 1
		prev = now
	assert_gt(veered, 0, "setup: the flight side-stepped west along the hill")
	assert_lte(worst, cap + tol,
			"the flight velocity changed by at most %.1f wu/s^2 (worst %.1f at tick %d)"
			% [cap, worst, worst_tick])


func test_the_flight_turns_from_a_side_step_at_the_share_cap() -> void:
	var router: Unit = await _spawn_close()
	assert_not_null(router, "the team-1 cavalry deployed")
	if router == null:
		return
	router.position = OPEN_GROUND
	router._flee_pace = router.flee_speed()
	router._flee_velocity = Vector2.LEFT * router._flee_pace
	router._flight_leg_was_detour = true
	router.facing = Vector2.DOWN
	router._flight_turn_rate = 0.0
	var before: Vector2 = router._flee_velocity
	router._process_rout(TICK)
	var change: float = (router._flee_velocity - before).length()
	var tol: float = 4.0 * router.flee_speed() * FLOAT32_EPS
	assert_almost_eq(change, _share_cap(router) * TICK, tol,
			"one tick turns the flight by the share cap's worth (got %.4f wu/s)" % change)
	assert_gt(router._flee_velocity.dot(Vector2.DOWN), 0.0, "toward the flight line")
	assert_lt(router._flee_velocity.dot(Vector2.LEFT), router._flee_pace,
			"away from the side-step")


func test_a_flight_inside_its_turning_look_of_a_face_side_steps() -> void:
	var router: Unit = await _spawn_close()
	assert_not_null(router, "the team-1 cavalry deployed")
	if router == null:
		return
	var look: float = _look(router, router.flee_speed())
	assert_gt(look, router.flee_speed() * TICK + LOOK_MARGIN_WU,
			"setup: the turning look reaches beyond one tick's travel")
	_place_front(router, look - LOOK_MARGIN_WU)
	var west: Vector2 = router._flight_front_veer(Vector2.DOWN, WEST_STEP, TICK)
	assert_almost_eq(west.x, -1.0, 0.0001,
			"a face inside the flight's turning look sends it west (got %s)" % west)
	assert_almost_eq(west.y, 0.0, 0.0001, "with nothing left heading into the face")


func test_a_flight_beyond_its_turning_look_of_a_face_keeps_its_direction() -> void:
	var router: Unit = await _spawn_close()
	assert_not_null(router, "the team-1 cavalry deployed")
	if router == null:
		return
	_place_front(router, _look(router, router.flee_speed()) + LOOK_MARGIN_WU)
	assert_eq(router._flight_front_veer(Vector2.DOWN, WEST_STEP, TICK), Vector2.DOWN,
			"a face beyond the flight's turning look leaves its direction alone")


## The team-0 squadron of the close-start staging (uid 1), spawned after `_spawn_close`.
func _squadron() -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		if (u as Unit) != null and (u as Unit).uid == 1:
			return u
	return null


func test_a_rout_carries_the_pace_it_was_making_away_on_into_the_flight() -> void:
	var router: Unit = await _spawn_close()
	assert_not_null(router, "the team-1 cavalry deployed")
	var squadron: Unit = _squadron()
	assert_not_null(squadron, "the team-0 squadron deployed")
	if router == null or squadron == null:
		return
	# Falling back toward its own (northern) edge at half its flee speed, drifting east too.
	var pace: float = 0.5 * squadron.flee_speed()
	squadron._approach_velocity = Vector2.UP * pace + Vector2.RIGHT * pace
	squadron.morale = 0.0
	squadron._rout()
	assert_almost_eq(squadron._flee_pace, pace, 0.0001, "setup: the rout carries that pace")
	assert_almost_eq(squadron._flee_velocity.y, -pace, 0.0001,
			"the flight starts at the pace it was making away (got %s)" % squadron._flee_velocity)
	assert_almost_eq(squadron._flee_velocity.x, 0.0, 0.0001, "along the flee heading")
	squadron._process_rout(TICK)
	var tol: float = 4.0 * squadron.flee_speed() * FLOAT32_EPS
	assert_gte(squadron._flee_velocity.length(), pace - tol,
			"the first flight tick keeps that speed rather than dropping it (got %s)"
			% squadron._flee_velocity)
	assert_almost_eq(squadron._moved_while_routing_pace, squadron._flee_velocity.length(), tol,
			"the stamina bill reads the speed the flight ran")


func test_no_share_still_lets_a_router_build_its_flight_at_its_own_accel() -> void:
	var router: Unit = await _spawn_close()
	assert_not_null(router, "the team-1 cavalry deployed")
	var squadron: Unit = _squadron()
	assert_not_null(squadron, "the team-0 squadron deployed")
	if router == null or squadron == null:
		return
	squadron.flight_share_max_accel_mult = 0.0
	assert_almost_eq(squadron.flight_velocity_accel(), squadron.accel, 0.0001,
			"no share leaves the flight its own accel")
	squadron.morale = 0.0
	squadron._rout()
	squadron._flee_pace = squadron.flee_speed()
	assert_eq(squadron._flee_velocity, Vector2.ZERO, "setup: broke from a standstill")
	var start: Vector2 = squadron.position
	squadron._process_rout(TICK)
	var tol: float = 4.0 * squadron.flee_speed() * FLOAT32_EPS
	assert_almost_eq(squadron._flee_velocity.length(), squadron.accel * TICK, tol,
			"the flight builds at accel (got %s)" % squadron._flee_velocity)
	assert_gt(start.distance_to(squadron.position), 0.0, "the router moves")
	assert_lt(squadron._moved_while_routing_pace, squadron._flee_pace,
			"the stamina bill reads the speed run, not the pace still ahead of it")


## Place `router` west of the hill, heading turned `turn` rad west of its southward flight,
## where the plain step runs straight down the flight line beside the hill but the turned
## block's swept width across that line would clip it: the turn-back's hold applies there
## when the flight last ran a detour leg. Returns the plain step direction.
func _place_for_turn_back(router: Unit, turn: float) -> Vector2:
	router.facing = Vector2.DOWN.rotated(turn)
	router._formation_angle = 0.0
	router._grid_lag = 0.0
	var wide: float = router._rout_step_clearance()
	var turned: float = maxf(wide, router.terrain_clearance(Vector2.DOWN))
	router.position = Vector2(CLOSE_HILL.position.x - 0.5 * (wide + turned),
			CLOSE_HILL.position.y - 200.0)
	router._flee_pace = router.flee_speed()
	return (PathField.active.next_step_fleeing(router.position, Vector2.DOWN, wide)
			- router.position).normalized()


func test_the_turn_back_holds_only_after_a_detour_leg() -> void:
	var router: Unit = await _spawn_close()
	assert_not_null(router, "the team-1 cavalry deployed")
	if router == null:
		return
	var plain: Vector2 = _place_for_turn_back(router, deg_to_rad(30.0))
	assert_gte(plain.dot(Vector2.DOWN), Unit.STRAIGHT_FLIGHT_DOT,
			"setup: the plain step runs straight down the flight line (got %s)" % plain)
	var detour := Vector2.DOWN.rotated(deg_to_rad(30.0))
	# Steered on a detour leg last tick: the block runs on along its heading.
	router._flight_leg_was_detour = true
	router._flee_velocity = detour * router._flee_pace
	var held: Vector2 = (router._flight_step(Vector2.DOWN) - router.position).normalized()
	assert_almost_eq(held.dot(router.facing), 1.0, 0.0001,
			"setup: after a detour leg the turn-back holds the heading (got %s)" % held)
	assert_true(router._flight_step_held, "and says it held")
	# Steered straight down the flight line last tick, with the flight velocity still lagging
	# on the detour: no hold, the flight takes its plain step.
	router._flight_leg_was_detour = false
	var step: Vector2 = (router._flight_step(Vector2.DOWN) - router.position).normalized()
	assert_gte(step.dot(Vector2.DOWN), Unit.STRAIGHT_FLIGHT_DOT,
			"a straight last leg takes the plain step, whatever the lagging velocity (got %s)"
			% step)


func test_a_turn_back_hold_cannot_sustain_itself() -> void:
	# A held tick steers along the heading, which is off the flight line, but it is not a
	# detour leg (_flight_leg_was_detour), so it cannot re-arm the hold: after a detour leg
	# the hold lasts at most HOLD_TICKS_MAX = 1 tick, however long the turned block's swept
	# width keeps the flight line blocked.
	var router: Unit = await _spawn_close()
	assert_not_null(router, "the team-1 cavalry deployed")
	if router == null:
		return
	_place_for_turn_back(router, deg_to_rad(30.0))
	router._flight_leg_was_detour = true
	router._flee_velocity = Vector2.DOWN.rotated(deg_to_rad(30.0)) * router._flee_pace
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	var held: int = 0
	var first_free: int = -1
	for k in range(HOLD_WATCH_TICKS):
		router._process_rout(TICK)
		if router._flight_step_held:
			held += 1
		elif first_free < 0:
			first_free = k
	assert_gt(held, 0, "setup: the hold engaged after the detour leg")
	assert_lte(held, HOLD_TICKS_MAX,
			"the hold lasted %d ticks of %d, no more than %d" % [held, HOLD_WATCH_TICKS, HOLD_TICKS_MAX])
	assert_eq(first_free, HOLD_TICKS_MAX, "and released on the tick after it")


## The squadron moved well clear of the router, so a rally's coast meets no enemy.
func _clear_squadron() -> Unit:
	var squadron: Unit = _squadron()
	squadron.position = Vector2(1600.0, 2200.0)
	return squadron


func test_a_rally_coasts_from_the_speed_the_flight_runs() -> void:
	var router: Unit = await _spawn_close()
	assert_not_null(router, "the team-1 cavalry deployed")
	var squadron: Unit = _squadron()
	assert_not_null(squadron, "the team-0 squadron deployed")
	if router == null or squadron == null:
		return
	squadron = _clear_squadron()
	squadron.morale = 0.0
	squadron._rout()
	squadron._flee_pace = squadron.flee_speed()
	var speed: float = 0.5 * squadron.flee_speed()
	squadron._flee_velocity = Vector2.UP * speed   # the flight still building toward its pace
	var brake: float = squadron.rally_halt_brake_rate()
	assert_gt(brake, 0.0, "setup: the coast brakes")
	var by_speed: float = speed * speed / (2.0 * brake)
	var by_pace: float = squadron._flee_pace * squadron._flee_pace / (2.0 * brake)
	# The field's top edge between the two stopping points: a coast from the speed run stops
	# inside it, one from the pace would leave it and be refused.
	var top: float = squadron.position.y - 0.5 * (by_speed + by_pace)
	squadron.retreat_bounds = Rect2(0.0, top, 1800.0, 2400.0 - top)
	squadron._begin_rally_halt()
	assert_true(squadron._rally_halt, "the coast from the speed run stops on the field")
	assert_almost_eq(squadron._current_speed, speed, 0.0001, "and runs at that speed")
	assert_eq(squadron._approach_velocity, squadron._flee_velocity, "along the flight")


func test_a_flight_carrying_no_speed_hands_over_no_coast() -> void:
	var router: Unit = await _spawn_close()
	assert_not_null(router, "the team-1 cavalry deployed")
	var squadron: Unit = _squadron()
	assert_not_null(squadron, "the team-0 squadron deployed")
	if router == null or squadron == null:
		return
	squadron = _clear_squadron()
	squadron.morale = 0.0
	squadron._rout()
	squadron._flee_pace = squadron.flee_speed()   # a pace ahead of a flight not yet moving
	squadron._flee_velocity = Vector2.ZERO
	squadron._begin_rally_halt()
	assert_false(squadron._rally_halt, "no coast from a flight that carries no speed")
	assert_eq(squadron._current_speed, 0.0, "and no speed handed over")
