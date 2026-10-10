extends GutTest
## A close-tier router that rallies from full flight pulls up as one block: the rally hands the
## flight over to the idle coast-to-stop, the anchor brakes at the unit's own decel, and its
## soldier bodies brake with it and settle onto their slots.
##
## The regression this pins: _rally() flipped the unit to IDLE and the anchor stopped dead on
## that tick, while its bodies still carried the flight velocity. A body already on its slot was
## brought to a dead stop in that one tick; one the rally re-paired onto another slot carried
## the flight on past it and walked back, scrambling the block while it settled.
##
## The staging is an empty map with the only enemy far off and idle (all_teams_control skips
## team 1's AI), so nothing but the rout and the rally moves the router.

const ROUTER_START := Vector2(700.0, 1300.0)
const ENEMY_START := Vector2(1030.0, 1300.0)   # 330 wu off: close tier, never in contact
# Ticks for an Infantry router's flight to build up to its flee pace (flee_speed / accel is
# about 3.5 s) with margin.
const RAMP_TICKS := 300
# The most the men's mean speed may drop by in one tick after the rally, as a fraction of the
# flee pace. Braking at decel sheds 1 wu/s a tick; the arrival's final landing onto the slot
# sheds a body's last few wu/s in one tick, as every arrival does (measured: 4.2 wu/s worst).
# Stopping dead sheds the whole flight, about 110 wu/s, on the rally tick.
const MAX_DROP_FRAC := 0.1
# How far, on average, the rallied block's bodies may stand ahead of their slots along the
# line of flight while it pulls up (world units).
const MAX_MEAN_OVERRUN_WU := 5.0
# How far any one body may stand off its slot while the block pulls up (world units).
# Measured: 1.15 wu; with the bodies held to their idle jog cap through the halt they trail
# their coasting slots by 5.3 wu.
const MAX_BODY_SLOT_WU := 3.0
# How far any body may stand off its slot once the block has settled (world units).
const SETTLED_BODY_SLOT_WU := 1.0
# Ticks after the rally by which every body must have settled.
const SETTLE_TICKS := 240
# The about-face square: ticks allowed for its rout to end in a rally, how long after the
# rally its men are measured, and the bound on their mean distance from their slots then
# (world units). Measured on the website clip's transcript 60 ticks after the rally: 4.4 wu
# with the halt, 14.8 wu with the anchor stopped dead.
const SQUARE_RALLY_TIMEOUT_TICKS := 400
const SQUARE_SETTLE_PROBE_TICKS := 60
const SQUARE_MAX_MEAN_GAP_WU := 8.0
# Ticks watched after the square's anchor stops, covering its men's re-form walk.
const POST_STOP_WATCH_TICKS := 120
# How far one man is set ahead of his slot after the anchor stops (world units): far enough
# that his arrival speed, sqrt(2 * accel * d), clears the 22.5 wu/s Infantry back-speed cap
# at the ordinary body acceleration (42 wu/s at 30 wu/s^2).
const SHOVE_WU := 30.0

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


func _spawn(terrain: Array = [], extra: Array = [], count: int = 48,
		facing: Array = [0, -1]) -> Unit:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.terrain = terrain
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "count": count, "x": ROUTER_START.x, "y": ROUTER_START.y,
				"facing": facing},
		{"team": 1, "type": "Infantry", "count": 24, "x": ENEMY_START.x, "y": ENEMY_START.y,
				"facing": [-1, 0]},
	] + extra
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


## The mean distance of `unit`'s bodies from their own formation slots (world units).
func _mean_body_slot_gap(unit: Unit) -> float:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	var n: int = mini(slots.size(), unit._sim_soldier_pos.size())
	if n == 0:
		return 0.0
	var total: float = 0.0
	for i in range(n):
		total += unit._sim_soldier_pos[i].distance_to(slots[i])
	return total / float(n)


## The mean speed of `unit`'s bodies (world units/s).
func _mean_body_speed(unit: Unit) -> float:
	var n: int = unit._sim_body_vel.size()
	if n == 0:
		return 0.0
	var total: float = 0.0
	for v in unit._sim_body_vel:
		total += v.length()
	return total / float(n)


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
	var prev_speed: float = _mean_body_speed(router)
	assert_gt(prev_speed, router.flee_speed() * 0.9, "setup: the men are running with the flight")
	await _rally_next_tick(router)
	assert_eq(router.state, Unit.State.IDLE, "the router rallied")
	# The rally tick's own drop counts: that is where the bodies used to stop dead.
	var worst_drop: float = prev_speed - _mean_body_speed(router)
	prev_speed = _mean_body_speed(router)
	var worst_overrun: float = _mean_body_lead(router, flee_dir)
	var worst_gap: float = _worst_body_slot_gap(router)
	for i in range(SETTLE_TICKS):
		await _advance_ticks(1)
		var speed: float = _mean_body_speed(router)
		worst_drop = maxf(worst_drop, prev_speed - speed)
		prev_speed = speed
		worst_overrun = maxf(worst_overrun, _mean_body_lead(router, flee_dir))
		worst_gap = maxf(worst_gap, _worst_body_slot_gap(router))
	var settled_gap: float = _worst_body_slot_gap(router)
	var max_drop: float = router.flee_speed() * MAX_DROP_FRAC
	gut.p("worst one-tick body speed drop %.2f wu/s (bound %.2f), worst mean overrun %.2f wu, worst body gap %.2f wu, gap after %d ticks %.2f wu, coast %.1f wu"
			% [worst_drop, max_drop, worst_overrun, worst_gap, SETTLE_TICKS, settled_gap,
			router.position.distance_to(rally_at)])
	assert_lt(worst_drop, max_drop,
			"the men pull up rather than stopping dead on the rally (worst one-tick drop %.2f wu/s)"
			% worst_drop)
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
	assert_eq(SoldierBodies.body_brake_accel_for(router), maxf(router.accel, SoldierBodies.BODY_ACCEL_FLOOR),
			"the bodies are back on their ordinary acceleration once the halt ends")


func test_a_square_rallying_with_an_about_face_settles_without_walking_back() -> void:
	# The website clip's staging: a SQUARE spawned routing away from its facing, so the rally's
	# hold-ground reform re-pairs men across the block's depth while they still carry the flight.
	# A second, safe team-0 unit keeps the battle from ending while the square routs.
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.terrain = []
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 700, "count": 60, "morale": 22.0,
				"formation": Unit.FORMATION_SQUARE, "starting_state": Unit.State.ROUTING},
		{"team": 0, "type": "Spearmen", "x": 260, "y": 260, "count": 60, "morale": 100.0},
		{"team": 1, "type": "Spearmen", "x": 800, "y": 1150, "count": 80},
	]
	add_child(_battle)
	await get_tree().physics_frame
	var square: Unit = null
	for u in get_tree().get_nodes_in_group("routers"):
		square = u as Unit
	assert_not_null(square, "setup: the square spawned routing")
	if square == null:
		return
	var waited: int = 0
	while square.state == Unit.State.ROUTING and waited < SQUARE_RALLY_TIMEOUT_TICKS:
		await _advance_ticks(1)
		waited += 1
	assert_eq(square.state, Unit.State.IDLE, "setup: the square rallied (after %d ticks)" % waited)
	await _advance_ticks(SQUARE_SETTLE_PROBE_TICKS)
	# A far-tier block carries no bodies, and a mean over none reads zero: the coast must not
	# have carried the square out of the close tier, which is how this staging once failed.
	assert_ne(square.tier, FormationTier.FAR, "the square is still simulated in the close tier")
	assert_eq(square._sim_soldier_pos.size(), square.soldiers, "with one body per man")
	var gap: float = _mean_body_slot_gap(square)
	gut.p("square: rallied after %d ticks; mean body-slot gap %.2f wu %d ticks later"
			% [waited, gap, SQUARE_SETTLE_PROBE_TICKS])
	assert_lt(gap, SQUARE_MAX_MEAN_GAP_WU,
			"%d ticks after the rally the men stand near their slots (mean %.2f wu)"
			% [SQUARE_SETTLE_PROBE_TICKS, gap])


func test_once_the_anchor_stops_the_mens_re_form_is_held_to_the_idle_caps() -> void:
	# The halt lifts the idle jog and back-speed caps only while the anchor still carries the
	# flight. The square's men are still walking onto their re-paired slots after the anchor
	# stops, some of them backward against their facing: from then on every body's velocity
	# must sit inside the ordinary idle caps (jog, and jog * back_speed_fraction backward).
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.terrain = []
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 700, "count": 60, "morale": 22.0,
				"formation": Unit.FORMATION_SQUARE, "starting_state": Unit.State.ROUTING},
		{"team": 0, "type": "Spearmen", "x": 260, "y": 260, "count": 60, "morale": 100.0},
		{"team": 1, "type": "Spearmen", "x": 800, "y": 1150, "count": 80},
	]
	add_child(_battle)
	await get_tree().physics_frame
	var square: Unit = null
	for u in get_tree().get_nodes_in_group("routers"):
		square = u as Unit
	assert_not_null(square, "setup: the square spawned routing")
	if square == null:
		return
	var waited: int = 0
	while (square.state == Unit.State.ROUTING or square._current_speed > 0.0) \
			and waited < SQUARE_RALLY_TIMEOUT_TICKS:
		await _advance_ticks(1)
		waited += 1
	assert_eq(square.state, Unit.State.IDLE, "setup: the square rallied")
	assert_eq(square._current_speed, 0.0, "setup: its anchor has pulled up")
	assert_false(square._rally_halt, "the halt ended when the anchor stopped")
	# The square's own re-form walks men back only slowly, so also set one man well ahead of
	# his slot along his facing, as a shove would: he has to walk back against his facing,
	# fast enough to meet the back-speed cap if nothing holds him to it.
	var slots: PackedVector2Array = square.soldier_world_slots(square.soldiers)
	square._sim_soldier_pos[0] = slots[0] + square._sim_soldier_facing[0] * SHOVE_WU
	square._sim_body_vel[0] = Vector2.ZERO
	var worst_excess: float = 0.0
	var worst_back: float = 0.0
	for t in range(POST_STOP_WATCH_TICKS):
		await _advance_ticks(1)
		for i in range(square._sim_body_vel.size()):
			var v: Vector2 = square._sim_body_vel[i]
			var f: Vector2 = square._sim_soldier_facing[i]
			var capped: Vector2 = SoldierBodies._cap_body_speed_vec(v, f, square.jog_speed,
					square.back_speed_fraction)
			worst_excess = maxf(worst_excess, (v - capped).length())
			worst_back = maxf(worst_back, -v.dot(f))
	gut.p("after the anchor stopped: worst backward body speed %.2f wu/s (back cap %.2f), worst excess over the idle caps %.4f"
			% [worst_back, square.jog_speed * square.back_speed_fraction, worst_excess])
	assert_gt(worst_back, square.jog_speed * square.back_speed_fraction * 0.9,
			"setup: the shoved man walks back against his facing up against the back-speed cap")
	assert_lt(worst_excess, 0.001,
			"no body exceeds the idle jog and back-speed caps once the anchor has stopped (worst excess %.4f wu/s)"
			% worst_excess)


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
	assert_eq(SoldierBodies.body_brake_accel_for(router), router.decel,
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


## How many of `before`'s off-centre points (more than half a file pitch off the centreline,
## measured from `centre_before`) sit on the other side of it in `after` (measured from
## `centre_after`), on the fixed lateral axis `lateral`.
func _flank_crossings(before: PackedVector2Array, centre_before: Vector2,
		after: PackedVector2Array, centre_after: Vector2, lateral: Vector2, half: float) -> int:
	var crossed: int = 0
	for i in range(mini(before.size(), after.size())):
		var a: float = (before[i] - centre_before).dot(lateral)
		var b: float = (after[i] - centre_after).dot(lateral)
		if a * b < 0.0 and absf(a) > half and absf(b) > half:
			crossed += 1
	return crossed


## The rally's hold-ground re-square of an about-face fold arms the depth mirror, and an order
## issued while the rallied block is still coasting to a stop is the fresh order that bakes it.
## A router spawned facing south and fleeing north snap-absorbs a half-turn into its grid; with
## 46 men on 9 files the rear rank is short, so the rally's re-square reflects rather than
## leaving the fold. The order must end the halt without sending any man across the block.
func test_an_order_mid_halt_after_an_about_face_rally_keeps_every_man_on_his_flank() -> void:
	var router: Unit = await _spawn([], [], 46, [0, 1])
	assert_not_null(router, "the team-0 infantry deployed")
	if router == null:
		return
	assert_ne(router.soldiers % router.formation_files(router.soldiers), 0,
			"setup: the block has a short rear rank")
	await _rout_to_full_flight(router)
	assert_almost_eq(absf(router._formation_angle), PI, 0.01,
			"setup: the flight snap-absorbed a half-turn into the grid")
	await _rally_next_tick(router)
	await _advance_ticks(5)
	assert_true(router.is_rally_halting(), "setup: still pulling up")
	assert_true(router._formation_mirror_x, "setup: the rally's re-square armed the mirror")
	var lateral: Vector2 = router.facing.orthogonal()
	var half: float = router.file_pitch_wu() * 0.5
	var slots_before: PackedVector2Array = router.soldier_world_slots(router.soldiers)
	var bodies_before: PackedVector2Array = router._sim_soldier_pos.duplicate()
	var centre_before: Vector2 = router.position
	var dest: Vector2 = router.position + router.facing * 200.0
	_battle._apply_order_cmd({"units": [router.uid], "x": dest.x, "y": dest.y, "target": -1})
	assert_false(router._formation_mirror_x, "the order baked the mirror")
	var slot_crossed: int = _flank_crossings(slots_before, centre_before,
			router.soldier_world_slots(router.soldiers), router.position, lateral, half)
	assert_eq(slot_crossed, 0,
			"no man's slot is moved to the other flank by the order (%d were)" % slot_crossed)
	var ended_after: int = -1
	var worst_body_crossed: int = 0
	for i in range(480):
		await _advance_ticks(1)
		worst_body_crossed = maxi(worst_body_crossed, _flank_crossings(bodies_before, centre_before,
				router._sim_soldier_pos, router.position, lateral, half))
		if ended_after < 0 and not router._rally_halt:
			ended_after = i + 1
	gut.p("order mid halt: %d slots crossed, worst %d bodies crossed, halt ended after %d ticks, worst body-slot gap now %.1f wu"
			% [slot_crossed, worst_body_crossed, ended_after, _worst_body_slot_gap(router)])
	assert_between(ended_after, 1, 120, "the order ends the halt (after %d ticks)" % ended_after)
	assert_eq(worst_body_crossed, 0,
			"no man walks across to the other flank after the order (%d did)" % worst_body_crossed)


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


func test_a_flight_pace_with_no_direction_has_nothing_to_hand_over() -> void:
	# A zero flight velocity gives no leg to check: stop_at would sit on the unit itself, every
	# check would pass, and the coast would then run along `facing`, which nothing vetted.
	var old_field: PathField = PathField.active
	PathField.active = null
	var u := _bare_flight_unit()
	u._flee_velocity = Vector2.ZERO
	u._begin_rally_halt()
	assert_false(u._rally_halt, "a flight with no direction is not handed over")
	assert_eq(u._current_speed, 0.0, "and no coast starts")
	u.free()
	PathField.active = old_field


func test_brake_biased_step_raises_only_the_braking_part() -> void:
	var dt: float = 1.0 / 60.0
	var braked: Vector2 = SoldierBodies.brake_biased_step(Vector2(0.0, -100.0), Vector2.ZERO,
			30.0, 60.0, dt)
	assert_almost_eq(braked.y, -99.0, 0.0001, "slowing down uses the raised braking rate")
	assert_almost_eq(braked.x, 0.0, 0.0001, "and nothing sideways")
	var sped: Vector2 = SoldierBodies.brake_biased_step(Vector2(0.0, -50.0), Vector2(0.0, -100.0),
			30.0, 60.0, dt)
	assert_almost_eq(sped.y, -50.5, 0.0001, "speeding up keeps the ordinary rate")
	var turned: Vector2 = SoldierBodies.brake_biased_step(Vector2(0.0, -100.0),
			Vector2(100.0, -100.0), 30.0, 60.0, dt)
	assert_almost_eq(turned.x, 0.5, 0.0001, "a sideways change keeps the ordinary rate")
	assert_almost_eq(turned.y, -100.0, 0.0001, "with nothing braked")
	# Braking and turning at once: each part keeps its own bound.
	var mixed: Vector2 = SoldierBodies.brake_biased_step(Vector2(0.0, -100.0), Vector2(100.0, 0.0),
			30.0, 60.0, dt)
	assert_almost_eq(mixed.y, -99.0, 0.0001, "the braking part sheds speed at the raised rate")
	assert_almost_eq(mixed.x, 0.5, 0.0001, "while the sideways part turns at the ordinary rate")


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


func test_a_wide_block_coasting_past_a_terrain_face_is_checked_by_its_swept_width() -> void:
	# The coast is checked with the block's own swept width, not a lone body's clearance: a
	# rect beside the line the anchor travels, inside the block's half-width but beyond the
	# anchor's own clearance, still blocks it.
	var old_field: PathField = PathField.active
	var u := _bare_flight_unit()
	u.max_soldiers = 120
	u.soldiers = 120
	u.facing = Vector2(0.0, -1.0)
	var half: Vector2 = u._formation_local_half_extents()
	var lateral: float = half.x * 0.6
	assert_gt(lateral, u._rout_clearance() + 5.0,
			"setup: the face stands beyond a lone anchor's clearance (half-width %.1f)" % half.x)
	var field := PathField.new(Rect2(0.0, 0.0, 2000.0, 2000.0))
	# A full-gallop flight: 200^2 / (2 * 60) = 333.3 wu to stop.
	u._flee_pace = 200.0
	u._flee_velocity = Vector2(0.0, -200.0)
	var half_leg: float = 200.0 * 200.0 / (2.0 * u.decel) * 0.5
	# A thin face `lateral` wu to the right of the middle of the coast. PathField never grows
	# a rect by more than the room the leg's two ends leave it, so the face stands farther
	# than `lateral` from both ends and only the coast's middle passes that close.
	assert_lt(lateral, half_leg - 5.0, "setup: the face is nearer the middle of the coast than its ends")
	field.block_rect(Rect2(500.0 + lateral, 500.0 - half_leg - 1.0, 60.0, 2.0))
	PathField.active = field
	u._begin_rally_halt()
	assert_false(u._rally_halt, "a coast whose block would sweep into the face is not handed over")
	assert_eq(u._current_speed, 0.0, "the anchor stops where it rallied")
	u.free()
	PathField.active = old_field


func test_a_coast_toward_an_enemy_is_not_handed_over() -> void:
	# The flee pace must not carry a rallied unit into contact, where its travel velocity
	# would read as a charge: with a living enemy within the contact radius of the coast's
	# path (though beyond it from where the unit rallies), the anchor stops where it rallied.
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 infantry deployed")
	if router == null:
		return
	var enemy: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		if (u as Unit).team == 1:
			enemy = u as Unit
	assert_not_null(enemy, "the enemy deployed")
	if enemy == null:
		return
	await _rout_to_full_flight(router)
	var dir: Vector2 = router._flee_velocity.normalized()
	var stop_dist: float = router._flee_pace * router._flee_pace / (2.0 * router.rally_halt_brake_rate())
	# Just past the contact radius from the router, and well within it of the coast's end.
	enemy.position = router.position + dir * (Unit.RALLY_CONTACT_RADIUS + 20.0)
	assert_lt(Unit.RALLY_CONTACT_RADIUS + 20.0 - stop_dist, Unit.RALLY_CONTACT_RADIUS,
			"setup: the coast would end inside the enemy's contact radius")
	await _rally_next_tick(router)
	assert_eq(router.state, Unit.State.IDLE, "setup: the router rallied (the enemy is out of contact)")
	assert_false(router._rally_halt, "no coast is handed over toward the enemy")
	assert_eq(router._current_speed, 0.0, "the anchor stops where it rallied")
	assert_eq(router._approach_velocity, Vector2.ZERO, "and carries no velocity into the enemy")


## The team-1 unit _spawn deploys.
func _enemy_unit() -> Unit:
	for group in ["units", "routers"]:
		for u in get_tree().get_nodes_in_group(group):
			if (u as Unit).team == 1:
				return u as Unit
	return null


func test_a_coast_toward_a_routing_enemy_is_not_handed_over() -> void:
	var router: Unit = await _spawn()
	var enemy: Unit = _enemy_unit()
	assert_not_null(enemy, "the enemy deployed")
	if router == null or enemy == null:
		return
	await _rout_to_full_flight(router)
	var dir: Vector2 = router._flee_velocity.normalized()
	enemy.position = router.position + dir * (router.rally_coast_enemy_radius() + 20.0)
	enemy.rally_morale_threshold = 1000.0
	enemy.rout_time = 1000.0
	enemy._rout()
	assert_eq(enemy.state, Unit.State.ROUTING, "setup: the enemy ahead is routing")
	await _rally_next_tick(router)
	assert_eq(router.state, Unit.State.IDLE, "setup: the router rallied")
	assert_false(router._rally_halt, "no coast is handed over toward a routing enemy either")
	assert_eq(router._current_speed, 0.0, "the anchor stops where it rallied")


func test_a_teammate_ahead_does_not_cancel_the_coast() -> void:
	var router: Unit = await _spawn([], [{"team": 0, "type": "Infantry", "count": 24,
			"x": 1500.0, "y": 1300.0, "facing": [0, -1]}])
	var friend: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		if (u as Unit).team == 0 and u != router:
			friend = u as Unit
	assert_not_null(friend, "the teammate deployed")
	if router == null or friend == null:
		return
	await _rout_to_full_flight(router)
	var dir: Vector2 = router._flee_velocity.normalized()
	friend.position = router.position + dir * (router.rally_coast_enemy_radius() + 20.0)
	await _rally_next_tick(router)
	assert_eq(router.state, Unit.State.IDLE, "setup: the router rallied")
	assert_true(router.is_rally_halting(), "a friend in the coast's path does not cancel it")


func test_an_enemy_that_comes_near_mid_coast_cuts_the_halt_short() -> void:
	# The coast was clear when it was handed over; an enemy that then moves into its path must
	# not meet the flee-pace velocity (a charge for cavalry): the halt ends and the anchor
	# stops where it stands, as a rally did before the halt existed.
	var router: Unit = await _spawn()
	var enemy: Unit = _enemy_unit()
	assert_not_null(enemy, "the enemy deployed")
	if router == null or enemy == null:
		return
	await _rout_to_full_flight(router)
	await _rally_next_tick(router)
	await _advance_ticks(5)
	assert_true(router.is_rally_halting(), "setup: the coast was handed over and is running")
	var dir: Vector2 = router._approach_velocity.normalized()
	enemy.position = router.position + dir * 100.0
	await _advance_ticks(1)
	assert_false(router._rally_halt, "an enemy near the remaining coast ends the halt")
	assert_lt(router._approach_velocity.length(), router.flee_speed() * 0.1,
			"and the unit carries none of the flight toward it (%.2f wu/s)"
			% router._approach_velocity.length())


func test_a_halt_that_starts_in_the_retreat_margin_is_not_snapped_onto_the_field() -> void:
	# A router may flee past the field edge into the retreat margin before it rallies. The halt
	# is held to retreat_bounds there: clamping it to field_bounds would yank the anchor back
	# onto the field the moment the coast starts.
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 infantry deployed")
	if router == null:
		return
	await _rout_to_full_flight(router)
	# Pretend the field's top edge lies just behind the router: it is fleeing up, out of it.
	router.field_bounds = Rect2(0.0, router.position.y + 20.0, 2000.0, 2000.0)
	var field_top: float = router.field_bounds.position.y
	await _rally_next_tick(router)
	assert_true(router.is_rally_halting(), "setup: the halt was handed over")
	var prev_y: float = router.position.y
	for i in range(5):
		await _advance_ticks(1)
		assert_lt(router.position.y, prev_y, "the coast keeps carrying the anchor on (tick %d)" % i)
		prev_y = router.position.y
	assert_lt(router.position.y, field_top - 20.0, "the anchor is still out in the margin")


## A bare unit coasting on a rally's halt, with no bodies (as a far-tier unit carries none).
func _bare_coasting_unit() -> Unit:
	var u := Unit.new()
	u.state = Unit.State.IDLE
	u.tier = FormationTier.FAR
	u.position = Vector2(500.0, 500.0)
	u.accel = 30.0
	u.decel = 60.0
	u._current_speed = 30.0
	u._approach_velocity = Vector2(0.0, -30.0)
	u._rally_halt = true
	return u


func test_a_halting_unit_with_no_bodies_ends_the_halt_when_its_anchor_stops() -> void:
	var old_field: PathField = PathField.active
	PathField.active = null
	var u := _bare_coasting_unit()
	var ticks: int = 0
	while u._current_speed > 0.0 and ticks < 120:
		u._tick_idle_coast(1.0 / 60.0)
		ticks += 1
	assert_eq(u._current_speed, 0.0, "setup: the anchor pulled up (after %d ticks)" % ticks)
	assert_false(u._rally_halt, "the halt ends with the anchor's stop")
	u.free()
	PathField.active = old_field


func test_fighting_mid_halt_ends_the_halt() -> void:
	var old_field: PathField = PathField.active
	PathField.active = null
	var u := _bare_coasting_unit()
	u.state = Unit.State.FIGHTING
	u._tick_idle_coast(1.0 / 60.0)
	assert_false(u._rally_halt, "a unit that is fighting is no longer pulling up from a rally")
	u.free()
	PathField.active = old_field


func test_locomoting_mid_halt_ends_the_halt() -> void:
	var old_field: PathField = PathField.active
	PathField.active = null
	var u := _bare_coasting_unit()
	u._moved_last_frame = true
	u._tick_idle_coast(1.0 / 60.0)
	assert_false(u._rally_halt, "a unit that moved under its own drive is no longer pulling up")
	u.free()
	PathField.active = old_field


func test_a_held_march_mid_halt_ends_the_halt() -> void:
	var old_field: PathField = PathField.active
	PathField.active = null
	var u := _bare_coasting_unit()
	# Frozen by a fresh order's response delay, with the order going the way it coasts.
	u._order_response_timer = 0.5
	u.move_target = u.position + Vector2(0.0, -200.0)
	u.has_move_target = true
	assert_true(u._held_march_continues_travel(), "setup: the held march continues the coast")
	u._tick_idle_coast(1.0 / 60.0)
	assert_false(u._rally_halt, "a held march carries the momentum on, so the halt is over")
	assert_eq(u._current_speed, 30.0, "and the held momentum is not braked")
	u.free()
	PathField.active = old_field
