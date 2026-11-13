extends GutTest
## A routing unit in the CLOSE sim tier flees as individual men (SoldierFlightStep): each man
## builds his run at his own acceleration up to his flee pace, faces the way he runs, and runs
## from the foes he perceives toward his refuge. The unit's `position` is a readout of its men
## (their centroid, SoldierBodies.couple), never a point they are steered toward.
##
## The stagings run on an empty map (no terrain) unless a test says otherwise, with team 1's AI
## off (all_teams_control), so nothing but the rout moves the router.

const ROUTER_START := Vector2(700.0, 1300.0)
const ENEMY_START := Vector2(1030.0, 1300.0)   # 330 wu off: close tier, never in contact
# The flight builds up from a standstill at each man's own accel; this many ticks covers the
# build-up for a Cavalry router (flee_speed / accel is about 5.5 s) with margin.
const RAMP_TICKS := 420
# The steady-state window the men's centroid speed is averaged over.
const MEASURE_TICKS := 60
# How far the steady-state centroid pace may sit from flee_speed(): the men run at their flee
# pace, and a man's line bends a little off his refuge while he perceives the idle enemy.
const SPEED_TOLERANCE_FRAC := 0.1
# How far `position` may stand from the men's centroid (world units): float rounding only.
const READOUT_EPS := 0.01
# The most a man's velocity may change in one tick beyond his own acceleration, in world units
# per second: float rounding and the friendly-contact steering of the men around him.
const ACCEL_SLACK := 1.0
# The router attacked across its line of flight: the enemy stands on its refuge side.
const ACROSS_WATCH_TICKS := 120
# The refuge-beyond-the-enemy staging: ticks for the run to build up, then ticks watched.
# A man who first ran for his refuge, toward the enemy, has to stop and turn, which at a
# Cavalry rider's acceleration takes a few seconds; the watch's last STALL_END_TICKS judge him.
const STALL_WATCH_TICKS := 600
const STALL_END_TICKS := 60
# The caught-router staging: a slow router (move_speed set low, so its flee pace is under a
# walking pursuer's) routed out of contact with a pursuer 130 wu behind it.
const CAUGHT_ROUTER_MOVE_SPEED := 15.0
const CAUGHT_PURSUER_GAP := 130.0
const CATCH_TICKS := 300
const CAUGHT_WATCH_TICKS := 120
# The rally staging: ticks the men run before the unit rallies (RAMP_TICKS, so they are at full
# flight), and ticks watched after.
const RALLY_AFTER_TICKS := RAMP_TICKS
const RALLY_WATCH_TICKS := 120
# The default map's block rect (Battle.TERRAIN), and a deep Cavalry block routing north from
# directly south of it with an idle enemy off to one side.
const HILL := Rect2(1150.0, 380.0, 250.0, 200.0)
const DEEP_START := Vector2(1230.0, 1300.0)
const DEEP_ENEMY := Vector2(900.0, 1300.0)
const HILL_WATCH_TICKS := 900

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	SoldierFlight.perceive_threats = true
	await _free_battle()
	Replay.forced_seed = -1


func _free_battle() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


## Spawn `scenario` on `terrain` (null: the default map's) and return [team 0's unit, team 1's].
func _spawn_pair(scenario: Array, terrain: Variant = []) -> Array:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	if terrain != null:
		_battle.terrain = terrain
	_battle.scenario = scenario
	add_child(_battle)
	await get_tree().physics_frame
	var out: Array = [null, null]
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null:
			out[unit.team] = unit
	return out


func _spawn() -> Unit:
	var pair: Array = await _spawn_pair([
		{"team": 0, "type": "Cavalry", "count": 12, "x": ROUTER_START.x, "y": ROUTER_START.y,
				"facing": [0, -1]},
		{"team": 1, "type": "Cavalry", "count": 12, "x": ENEMY_START.x, "y": ENEMY_START.y,
				"facing": [-1, 0]},
	])
	return pair[0]


## Await physics frames until the battle's own tick counter advances by `n` (an awaited
## physics_frame does not map one-to-one onto a sim tick under coverage instrumentation).
func _advance_ticks(n: int) -> void:
	var target: int = _battle.current_tick() + n
	var safety: int = n * 20 + 200
	while _battle.current_tick() < target and safety > 0:
		safety -= 1
		await get_tree().physics_frame


func _centroid(unit: Unit) -> Vector2:
	var c := Vector2.ZERO
	for p in unit._sim_soldier_pos:
		c += p
	return c / maxf(1.0, float(unit._sim_soldier_pos.size()))


func _speeds(unit: Unit) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in unit._sim_body_vel:
		out.push_back(v.length())
	return out


## Break `router` and hold it routing: no rally, no timeout.
func _rout_and_hold(router: Unit) -> void:
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router._rout()


func test_close_tier_router_flees_at_flee_speed_as_its_own_men() -> void:
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 cavalry deployed")
	if router == null:
		return
	assert_eq(router.tier, FormationTier.CLOSE, "the router is simulated in the close tier")
	_rout_and_hold(router)
	var body_accel: float = maxf(router.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var worst_readout: float = 0.0
	var worst_kick: float = 0.0
	var worst_facing: float = 0.0
	var ramp_end: int = _battle.current_tick() + RAMP_TICKS
	while _battle.current_tick() < ramp_end and router.state == Unit.State.ROUTING:
		var prev: PackedVector2Array = router._sim_body_vel.duplicate()
		await _advance_ticks(1)
		worst_readout = maxf(worst_readout, router.position.distance_to(_centroid(router)))
		for i in range(mini(prev.size(), router._sim_body_vel.size())):
			var v: Vector2 = router._sim_body_vel[i]
			worst_kick = maxf(worst_kick, (v - prev[i]).length() * 60.0 - body_accel)
			if v.length() > 1.0:
				worst_facing = maxf(worst_facing,
						absf(v.normalized().angle_to(router.soldier_facing(i))))
	assert_eq(router.state, Unit.State.ROUTING, "still routing after the build-up")
	assert_lt(worst_readout, READOUT_EPS,
			"position is the men's centroid every tick (worst %.4f wu)" % worst_readout)
	assert_lt(worst_kick, ACCEL_SLACK, "no man changes his velocity faster than his own"
			+ " acceleration (worst %.3f wu/s^2 over it)" % worst_kick)
	assert_lt(worst_facing, 0.001, "each running man faces the way he runs")

	var start: Vector2 = router.position
	var start_tick: int = _battle.current_tick()
	await _advance_ticks(MEASURE_TICKS)
	var ticks: int = _battle.current_tick() - start_tick
	var per_tick: float = router.position.distance_to(start) / float(maxi(1, ticks))
	var flee_per_tick: float = router.flee_speed() / float(Engine.physics_ticks_per_second)
	assert_almost_eq(per_tick, flee_per_tick, flee_per_tick * SPEED_TOLERANCE_FRAC,
			"the men run at flee_speed() (got %.3f wu/tick, flee %.3f)" % [per_tick, flee_per_tick])
	assert_lt(router.position.y, start.y, "toward their own rear edge (team 0 flees north)")


## A router attacked across its line of flight, the enemy standing north of it, between it and
## its refuge. Returns how far south its men's centroid moved in ACROSS_WATCH_TICKS.
func _across_flight_drift(perceive: bool) -> float:
	SoldierFlight.perceive_threats = perceive
	var pair: Array = await _spawn_pair([
		{"team": 0, "type": "Cavalry", "count": 24, "x": 700.0, "y": 1300.0, "facing": [0, -1]},
		{"team": 1, "type": "Infantry", "count": 120, "x": 700.0, "y": 1180.0, "facing": [0, 1]},
	])
	var router: Unit = pair[0]
	assert_not_null(router, "the router deployed")
	if router == null:
		return 0.0
	_rout_and_hold(router)
	var start: Vector2 = _centroid(router)
	await _advance_ticks(ACROSS_WATCH_TICKS)
	var drift: float = (_centroid(router) - start).y
	await _free_battle()
	return drift


func test_a_router_runs_from_the_foes_it_perceives_not_into_them() -> void:
	var seeing: float = await _across_flight_drift(true)
	var blind: float = await _across_flight_drift(false)
	assert_gt(seeing, 0.0, "seeing the enemy on its refuge side, the men run south, away from it"
			+ " (moved %.1f wu)" % seeing)
	assert_lt(blind, 0.0, "blind to it, they would run north for their refuge (moved %.1f wu)"
			% blind)


## A router whose refuge lies beyond an enemy line: no man ends up standing still in front of
## the enemy (where his refuge's pull and the enemy's push would balance), and no man runs into
## the enemy line on the way round it.
func test_a_router_with_the_enemy_on_its_refuge_side_never_stalls_and_goes_round() -> void:
	var pair: Array = await _spawn_pair([
		{"team": 0, "type": "Cavalry", "count": 24, "x": 700.0, "y": 1650.0, "facing": [0, -1]},
		{"team": 1, "type": "Infantry", "count": 160, "x": 700.0, "y": 1150.0, "facing": [0, 1]},
	])
	var router: Unit = pair[0]
	var line: Unit = pair[1]
	assert_not_null(router, "the router deployed")
	if router == null or line == null:
		return
	_rout_and_hold(router)
	var slowest: float = INF
	var closest: float = INF
	for t in range(STALL_WATCH_TICKS):
		await _advance_ticks(1)
		assert_eq(router.state, Unit.State.ROUTING, "setup: still routing on the field")
		if router.state != Unit.State.ROUTING:
			return
		for i in range(router._sim_soldier_pos.size()):
			if i < router._sim_flight_dir.size() and router._sim_flight_dir[i] == Vector2.ZERO:
				continue   # a man standing cornered to fight is not stalled
			if t >= STALL_WATCH_TICKS - STALL_END_TICKS:
				slowest = minf(slowest, router._sim_body_vel[i].length())
			for p in line._sim_soldier_pos:
				closest = minf(closest, router._sim_soldier_pos[i].distance_to(p))
	assert_gt(slowest, router.jog_speed, "no man ends up below a jog in front of the enemy"
			+ " (slowest %.1f wu/s)" % slowest)
	assert_gt(closest, router.soldier_body_radius() + line.soldier_body_radius(),
			"and none runs into the enemy line (closest %.1f wu)" % closest)


func test_a_unit_riding_a_router_down_keeps_its_men() -> void:
	# The routed unit is the pursuer's only near enemy; its other enemy stands far off. The tier
	# pass counts the quarry, so the pursuer stays in the close tier and its riders keep chasing.
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.terrain = []
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "count": 12, "x": 700.0, "y": 1250.0, "facing": [0, -1]},
		{"team": 0, "type": "Spearmen", "count": 40, "x": 700.0, "y": 100.0, "facing": [0, 1]},
		{"team": 1, "type": "Cavalry", "count": 12, "x": 700.0, "y": 1400.0, "facing": [0, -1]},
	]
	add_child(_battle)
	await get_tree().physics_frame
	var router: Unit = null
	var pursuer: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit.team == 1:
			pursuer = unit
		elif str(unit.unit_name).begins_with("Infantry"):
			router = unit
	_rout_and_hold(router)
	_battle._apply_order_cmd({"units": [pursuer.uid], "x": router.position.x,
			"y": router.position.y, "target": router.uid})
	var far: bool = false
	for t in range(120):
		await _advance_ticks(1)
		far = far or pursuer.tier == FormationTier.FAR
	assert_true(SoldierPursuitStep.is_pursuing(pursuer), "setup: the cavalry ride the router down")
	assert_false(far, "the pursuer kept its men for the whole chase")


func test_a_router_clear_of_every_enemy_is_not_in_enemy_contact() -> void:
	# A router never runs _think(), where _in_enemy_contact is recomputed, so the rout path
	# must refresh it: left as it was when the unit broke, a router that has got clear would
	# keep its bodies colliding as if still pressed against the enemy it fled. Here the only
	# enemy stands far beyond contact range, and the flag starts stale-true as at a break.
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 cavalry deployed")
	if router == null:
		return
	router._in_enemy_contact = true
	_rout_and_hold(router)
	await _advance_ticks(1)
	assert_eq(router.state, Unit.State.ROUTING, "setup: the unit is routing")
	assert_false(router._in_enemy_contact,
			"a router with no enemy within contact range is not in enemy contact")


func test_a_router_caught_by_a_pursuer_comes_into_enemy_contact() -> void:
	# The rising edge of the router's contact flag: routed out of contact, it must come into
	# contact when a pursuer catches it, since a router never runs _think() where the flag is
	# otherwise refreshed. Caught, its `position` still reads its men.
	var pair: Array = await _spawn_pair([
		{"team": 0, "type": "Infantry", "count": 48, "x": ROUTER_START.x, "y": ROUTER_START.y,
				"facing": [0, -1]},
		{"team": 1, "type": "Cavalry", "count": 24, "x": ROUTER_START.x,
				"y": ROUTER_START.y + CAUGHT_PURSUER_GAP, "facing": [0, -1]},
	])
	var router: Unit = pair[0]
	var pursuer: Unit = pair[1]
	assert_not_null(router, "the router deployed")
	assert_not_null(pursuer, "the pursuer deployed")
	if router == null or pursuer == null:
		return
	router.move_speed = CAUGHT_ROUTER_MOVE_SPEED
	router.jog_speed = CAUGHT_ROUTER_MOVE_SPEED * 0.6   # gaits stay ordered under the sprint
	router.walk_speed = CAUGHT_ROUTER_MOVE_SPEED * 0.3
	_rout_and_hold(router)
	_battle._apply_order_cmd({"units": [pursuer.uid], "x": router.position.x,
			"y": router.position.y, "target": router.uid})
	assert_false(router._in_enemy_contact, "setup: the router routs out of contact")
	var caught: bool = false
	for i in range(CATCH_TICKS):
		await _advance_ticks(1)
		if router._in_enemy_contact:
			caught = true
			break
	assert_true(caught, "the router comes into enemy contact when the pursuer catches it")
	if not caught:
		return
	var worst: float = 0.0
	for i in range(CAUGHT_WATCH_TICKS):
		await _advance_ticks(1)
		if router.state != Unit.State.ROUTING:
			break
		worst = maxf(worst, router.position.distance_to(_centroid(router)))
	assert_lt(worst, READOUT_EPS,
			"a caught router's position still reads its men (worst %.4f wu)" % worst)


## Run the open-ground router RALLY_AFTER_TICKS, scramble its men the way a crowd running
## from a fight scrambles them (each man stands where the man at the other end of the array
## stood), then let it rally under `deal`. Returns the total distance from its men to their
## places on the tick its grid is laid out, once they have pulled up.
func _rally_walk(deal: int) -> float:
	var router: Unit = await _spawn()
	router.rally_deal = deal
	_rout_and_hold(router)
	await _advance_ticks(RALLY_AFTER_TICKS)
	router._sim_soldier_pos.reverse()
	router._sim_body_vel.reverse()
	router.rally_morale_threshold = 0.0
	router.morale = 50.0
	await _advance_ticks(1)
	assert_eq(router.state, Unit.State.IDLE, "setup: the unit rallied")
	for t in range(RALLY_WATCH_TICKS * 4):
		if not router._rally_pending:
			break
		await _advance_ticks(1)
	assert_false(router._rally_pending, "setup: the men pulled up and the grid was laid out")
	var slots: PackedVector2Array = router.soldier_world_slots(router.soldiers)
	var walk: float = 0.0
	for i in range(mini(slots.size(), router._sim_soldier_pos.size())):
		walk += router._sim_soldier_pos[i].distance_to(slots[i])
	await _free_battle()
	return walk


func test_a_rally_deals_the_men_places_from_where_they_stand() -> void:
	var stand: float = await _rally_walk(Unit.RallyDeal.STAND)
	var own: float = await _rally_walk(Unit.RallyDeal.OWN)
	assert_lt(stand, own, "dealt from where they stand, the men walk less in all (%.0f wu) than"
			% stand + " each going back to his own place in his file (%.0f wu)" % own)


func test_a_rallied_unit_s_men_pull_up_then_it_re_forms_where_they_stand() -> void:
	var router: Unit = await _spawn()
	_rout_and_hold(router)
	await _advance_ticks(RALLY_AFTER_TICKS)
	var running: float = 0.0
	for s in _speeds(router):
		running = maxf(running, s)
	assert_gt(running, router.jog_speed * 1.2, "setup: the men are running well above a jog")
	router.rally_morale_threshold = 0.0
	router.morale = 50.0
	await _advance_ticks(1)
	assert_eq(router.state, Unit.State.IDLE, "the unit rallied")
	assert_true(router.shedding_flight(), "its men are still pulling up")
	var brake: float = maxf(maxf(router.accel, SoldierBodies.BODY_ACCEL_FLOOR), router.decel)
	var worst_drop: float = 0.0
	var worst_readout: float = 0.0
	for t in range(RALLY_WATCH_TICKS * 4):
		if not router._rally_pending:
			break
		var prev: PackedFloat32Array = _speeds(router)
		await _advance_ticks(1)
		if not router._rally_pending:
			break
		worst_readout = maxf(worst_readout, router.position.distance_to(_centroid(router)))
		var now: PackedFloat32Array = _speeds(router)
		for i in range(mini(prev.size(), now.size())):
			worst_drop = maxf(worst_drop, prev[i] - now[i])
	assert_false(router._rally_pending, "the men pulled up and the unit re-formed")
	assert_lt(worst_drop * 60.0, brake + ACCEL_SLACK, "no man sheds his run faster than he can"
			+ " brake (worst %.1f wu/s^2, brake %.1f)" % [worst_drop * 60.0, brake])
	assert_lt(worst_readout, READOUT_EPS, "while they pull up, position reads the men")
	assert_almost_eq(router._formation_angle, 0.0, 0.0001, "its grid is square to its heading")
	assert_lt(router.position.distance_to(_centroid(router)), router.rank_pitch_wu(),
			"laid out where its men came to rest")
	for s in _speeds(router):
		assert_lt(s, router.jog_speed + 0.001, "no man is faster than a jog once it has re-formed")


func test_a_router_rounds_a_hill_in_its_way() -> void:
	# A deep block routing north from directly south of the default map's hill: each man veers
	# along the face he runs at (router_terrain_avoid) and goes round, so every man gets past it.
	var pair: Array = await _spawn_pair([
		{"team": 0, "type": "Cavalry", "count": 80, "x": DEEP_START.x, "y": DEEP_START.y,
				"facing": [0, -1]},
		{"team": 1, "type": "Cavalry", "count": 12, "x": DEEP_ENEMY.x, "y": DEEP_ENEMY.y,
				"facing": [1, 0]},
	], null)
	var router: Unit = pair[0]
	assert_not_null(router, "the router deployed")
	if router == null:
		return
	_rout_and_hold(router)
	var inside: int = 0
	var all_past: bool = false
	for t in range(HILL_WATCH_TICKS):
		await _advance_ticks(1)
		if router.state != Unit.State.ROUTING:
			break
		var past: bool = true
		for p in router._sim_soldier_pos:
			if HILL.has_point(p):
				inside += 1
			if p.y >= HILL.position.y:
				past = false
		if past:
			all_past = true
			break
	assert_eq(inside, 0, "no man ever stood inside the hill")
	assert_true(all_past, "every man got round the hill within %d ticks" % HILL_WATCH_TICKS)
