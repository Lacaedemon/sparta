extends GutTest
## A close-tier router that rallies from full flight pulls up as one block: the rally hands the
## flight over to the idle coast-to-stop, the anchor brakes at the unit's own decel, and its
## soldier bodies brake with it and settle onto their slots.
##
## The regression this pins: _rally() flipped the unit to IDLE and the anchor stopped dead on
## that tick, while its bodies still carried the flight velocity. They overran their slots and
## walked back, scrambling the block while it settled.
##
## The staging is an empty map with the only enemy far off and idle (all_teams_control skips
## team 1's AI), so nothing but the rout and the rally moves the router.

const ROUTER_START := Vector2(700.0, 1300.0)
const ENEMY_START := Vector2(1030.0, 1300.0)   # 330 wu off: close tier, never in contact
# Ticks for an Infantry router's flight to build up to its flee pace (flee_speed / accel is
# about 3.5 s) with margin.
const RAMP_TICKS := 300
# How far, on average, the rallied block's bodies may stand ahead of their slots along the
# line of flight while it pulls up (world units).
const MAX_MEAN_OVERRUN_WU := 5.0
# How far any one body may stand off its slot while the block pulls up (world units).
const MAX_BODY_SLOT_WU := 10.0
# How far any body may stand off its slot once the block has settled (world units).
const SETTLED_BODY_SLOT_WU := 1.0
# Ticks after the rally by which every body must have settled.
const SETTLE_TICKS := 240

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


func _spawn(terrain: Array = []) -> Unit:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.terrain = terrain
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "count": 48, "x": ROUTER_START.x, "y": ROUTER_START.y,
				"facing": [0, -1]},
		{"team": 1, "type": "Infantry", "count": 24, "x": ENEMY_START.x, "y": ENEMY_START.y,
				"facing": [-1, 0]},
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


## Rout `router` and run it up to its full flee pace, held routing (no rally, no timeout).
func _rout_to_full_flight(router: Unit) -> void:
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router._rout()
	await _advance_ticks(RAMP_TICKS)


## Let the router rally on its next rout tick: its morale is already past a zero threshold,
## and nothing is inside the rally-contact radius.
func _rally_next_tick(router: Unit) -> void:
	router.rally_morale_threshold = 0.0
	await _advance_ticks(1)


## The farthest any of `unit`'s bodies stands from its own formation slot (world units).
func _worst_body_slot_gap(unit: Unit) -> float:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	var worst: float = 0.0
	for i in range(mini(slots.size(), unit._sim_soldier_pos.size())):
		worst = maxf(worst, unit._sim_soldier_pos[i].distance_to(slots[i]))
	return worst


## How far, on average, `unit`'s bodies stand ahead of their own slots along `dir`.
func _mean_body_lead(unit: Unit, dir: Vector2) -> float:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	var n: int = mini(slots.size(), unit._sim_soldier_pos.size())
	if n == 0:
		return 0.0
	var lead: float = 0.0
	for i in range(n):
		lead += (unit._sim_soldier_pos[i] - slots[i]).dot(dir)
	return lead / float(n)


func test_a_router_rallying_from_full_flight_pulls_up_with_its_bodies() -> void:
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 infantry deployed")
	if router == null:
		return
	await _rout_to_full_flight(router)
	assert_eq(router.state, Unit.State.ROUTING, "setup: still routing after the build-up")
	assert_almost_eq(router._flee_pace, router.flee_speed(), 0.01, "setup: running at full flee pace")
	var flee_dir: Vector2 = router._flee_velocity.normalized()
	var rally_at: Vector2 = router.position
	await _rally_next_tick(router)
	assert_eq(router.state, Unit.State.IDLE, "the router rallied")
	var worst_overrun: float = -INF
	var worst_gap: float = 0.0
	for i in range(SETTLE_TICKS):
		await _advance_ticks(1)
		worst_overrun = maxf(worst_overrun, _mean_body_lead(router, flee_dir))
		worst_gap = maxf(worst_gap, _worst_body_slot_gap(router))
	var settled_gap: float = _worst_body_slot_gap(router)
	gut.p("worst mean overrun %.2f wu, worst body gap %.2f wu, gap after %d ticks %.2f wu, coast %.1f wu"
			% [worst_overrun, worst_gap, SETTLE_TICKS, settled_gap, router.position.distance_to(rally_at)])
	assert_lt(worst_overrun, MAX_MEAN_OVERRUN_WU,
			"the rallied block's bodies do not run on past their slots (worst mean lead %.2f wu)"
			% worst_overrun)
	assert_lt(worst_gap, MAX_BODY_SLOT_WU,
			"no body strays more than %.1f wu off its slot while the block pulls up (worst %.2f)"
			% [MAX_BODY_SLOT_WU, worst_gap])
	assert_lt(settled_gap, SETTLED_BODY_SLOT_WU,
			"every body has settled onto its slot %d ticks after the rally (worst %.2f wu)"
			% [SETTLE_TICKS, settled_gap])
	assert_eq(router._current_speed, 0.0, "the anchor has come to a stop")
	assert_false(router.is_rally_halting(), "the halt ended once the block came to rest")
	assert_eq(SoldierBodies.body_accel_for(router), maxf(router.accel, SoldierBodies.BODY_ACCEL_FLOOR),
			"the bodies are back on their ordinary acceleration once the halt ends")


func test_the_rally_hands_the_flight_to_a_coast_braking_at_the_units_decel() -> void:
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 infantry deployed")
	if router == null:
		return
	await _rout_to_full_flight(router)
	var pace: float = router._flee_pace
	await _rally_next_tick(router)
	assert_eq(router.state, Unit.State.IDLE, "the router rallied")
	assert_true(router.is_rally_halting(), "the rallied unit is pulling up from its flight")
	assert_almost_eq(router._current_speed, pace, 0.001, "the coast starts at the flight's pace")
	assert_eq(router.idle_brake_rate(), router.decel, "the coast brakes at the unit's own decel")
	assert_eq(SoldierBodies.body_accel_for(router), router.decel,
			"the bodies brake at the same rate as the anchor")
	var ticks := 10
	await _advance_ticks(ticks)
	var expected: float = pace - router.decel * float(ticks) / float(Engine.physics_ticks_per_second)
	assert_almost_eq(router._current_speed, expected, 0.01,
			"the anchor sheds speed at decel (%.2f after %d ticks)" % [router._current_speed, ticks])


func test_routing_again_mid_halt_ends_the_halt() -> void:
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 infantry deployed")
	if router == null:
		return
	await _rout_to_full_flight(router)
	await _rally_next_tick(router)
	await _advance_ticks(5)
	assert_true(router.is_rally_halting(), "setup: still pulling up")
	router.rally_morale_threshold = 1000.0
	router._rout()
	assert_false(router._rally_halt, "a fresh rout drops the halt")
	assert_eq(router._current_speed, 0.0, "and the coast it carried")


func test_an_order_mid_halt_ends_the_halt() -> void:
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 infantry deployed")
	if router == null:
		return
	await _rout_to_full_flight(router)
	await _rally_next_tick(router)
	await _advance_ticks(5)
	assert_true(router.is_rally_halting(), "setup: still pulling up")
	_battle._apply_order_cmd({"units": [router.uid], "x": router.position.x + 200.0,
			"y": router.position.y, "target": -1})
	var ended_after: int = -1
	for i in range(120):
		await _advance_ticks(1)
		if not router._rally_halt:
			ended_after = i + 1
			break
	assert_between(ended_after, 1, 120, "an order ends the halt (after %d ticks)" % ended_after)
	assert_ne(router.state, Unit.State.IDLE, "the halt ended because the unit took up its order")


func _bare_flight_unit() -> Unit:
	var u := Unit.new()
	u.state = Unit.State.IDLE
	u.position = Vector2(500.0, 500.0)
	u.accel = 30.0
	u.decel = 60.0
	u._flee_pace = 100.0
	u._flee_velocity = Vector2(0.0, -100.0)
	return u


func test_begin_rally_halt_hands_the_flight_over() -> void:
	var old_field: PathField = PathField.active
	PathField.active = null
	var u := _bare_flight_unit()
	u._begin_rally_halt()
	assert_true(u.is_rally_halting(), "a rally from flight starts the halt")
	assert_eq(u._current_speed, 100.0, "the coast takes over the flight's pace")
	assert_eq(u._approach_velocity, Vector2(0.0, -100.0), "and its velocity")
	u.state = Unit.State.FIGHTING
	assert_false(u.is_rally_halting(), "only an IDLE unit is pulling up from a rally")
	u.free()
	PathField.active = old_field


func test_a_rally_from_a_standstill_has_nothing_to_hand_over() -> void:
	var old_field: PathField = PathField.active
	PathField.active = null
	var u := _bare_flight_unit()
	u._flee_pace = 0.0
	u._flee_velocity = Vector2.ZERO
	u._begin_rally_halt()
	assert_false(u._rally_halt, "no flight, no halt")
	assert_eq(u._current_speed, 0.0, "and no coast")
	u.free()
	PathField.active = old_field


func test_a_coast_that_would_leave_retreat_bounds_stops_where_it_rallied() -> void:
	var old_field: PathField = PathField.active
	PathField.active = null
	var u := _bare_flight_unit()
	# 100^2 / (2 * 60) = 83.3 wu to stop, heading up; the edge is 50 wu ahead.
	u.retreat_bounds = Rect2(0.0, 450.0, 1000.0, 1000.0)
	u._begin_rally_halt()
	assert_false(u._rally_halt, "a coast past the retreat edge is not handed over")
	assert_eq(u._current_speed, 0.0, "the anchor stops where it rallied")
	assert_eq(u._approach_velocity, Vector2.ZERO, "with no travel left on it")
	u.free()
	PathField.active = old_field


func test_a_coast_into_impassable_terrain_stops_where_it_rallied() -> void:
	var old_field: PathField = PathField.active
	var field := PathField.new(Rect2(0.0, 0.0, 2000.0, 2000.0))
	field.block_rect(Rect2(400.0, 440.0, 200.0, 20.0))   # across the coast, 40 wu ahead
	PathField.active = field
	var u := _bare_flight_unit()
	u._begin_rally_halt()
	assert_false(u._rally_halt, "a coast into a block is not handed over")
	assert_eq(u._current_speed, 0.0, "the anchor stops where it rallied")
	u.free()
	PathField.active = old_field
