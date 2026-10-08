extends GutTest
## A routing unit in the CLOSE sim tier must cover ground at its own flee_speed(), the same
## pace the far tier moves it at, with its soldier bodies running alongside the anchor.
##
## The regression this pins: _process_rout moves the anchor at flee pace, but nothing fed
## that flight to the bodies (their feed-forward was _approach_velocity, which _process_rout
## never sets -- zero for a router that broke standing still), so they chased their
## slots on the jog-capped arrival term alone. They fell tens of world units behind, and
## SoldierBodies.couple() -- reading that lag as the men standing off formation -- pulled the
## anchor most of the way back every tick. A no-contact cavalry rout crawled at about a sixth
## of its flee pace. The superphysical body-speed ceiling, measured from move_speed, also sat
## below the flee pace, so the bodies could never have kept up even with the feed-forward.
##
## The scenario is staged on an empty map (no terrain) with the only enemy far off and idle
## (all_teams_control skips team 1's AI), so nothing but the rout itself moves the router.

const ROUTER_START := Vector2(700.0, 1300.0)
const ENEMY_START := Vector2(1030.0, 1300.0)   # 330 wu off: close tier, never in contact
# The flight ramps up from a standstill at the unit's own accel; this many ticks covers
# the build-up for a Cavalry router (flee_speed / accel is about 5.5 s) with margin.
const RAMP_TICKS := 420
# The steady-state window the anchor speed is averaged over.
const MEASURE_TICKS := 60
# How far the steady-state anchor pace may sit from flee_speed(). The bodies see their slot
# one flee step ahead each tick (the anchor moves before they integrate), which adds a
# small arrival term on top of the feed-forward and lets the coupling nudge the anchor a
# few percent past the flee pace; a few percent either way is the same flight.
const SPEED_TOLERANCE_FRAC := 0.1
# How far the bodies may stand off their slots while fleeing at full pace (world units):
# the men run WITH the anchor, not strung out behind it.
const MAX_BODY_SLOT_WU := 10.0
# Covers the brake from full flight before the rally (flee_speed / arrival_brake_rate is
# about 5.5 s for this Cavalry) plus a few seconds of the reform after it.
const RALLY_WINDOW_TICKS := 600
# A deeper squadron than the speed test's, so men running on past a dead-stopped anchor
# would have somewhere to overrun to.
const RALLY_ROUTER_COUNT := 40
# The most the men's mean speed may fall in a single tick, as a fraction of the flee pace.
# Stopping dead from full flight dropped it by 69.3 wu/s in one tick on this staging (flee
# pace 221 wu/s); braking first leaves only the last few wu/s of the men settling onto
# their slots (measured 5.3 wu/s), well under this.
const MAX_ONE_TICK_DROP_FRAC := 0.1

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


## Stage the router (and, unless `with_enemy` is false, the idle enemy squadron). Without
## the enemy the battle runs in drill mode, so nothing demotes the rallied router to the far
## tier -- which would drop its bodies and leave nothing to measure.
func _spawn(with_enemy: bool = true, router_count: int = 12) -> Unit:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.drill_mode = not with_enemy
	_battle.terrain = []
	_battle.scenario = [
		{"team": 0, "type": "Cavalry", "count": router_count, "x": ROUTER_START.x,
				"y": ROUTER_START.y, "facing": [0, -1]},
	]
	if with_enemy:
		_battle.scenario.append({"team": 1, "type": "Cavalry", "count": 12,
				"x": ENEMY_START.x, "y": ENEMY_START.y, "facing": [-1, 0]})
	add_child(_battle)
	await get_tree().physics_frame
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0:
			return unit
	return null


## Await physics frames until the battle's own tick counter advances by `n` (an awaited
## physics_frame does not map one-to-one onto a sim tick under coverage instrumentation).
func _advance_ticks(n: int) -> void:
	var target: int = _battle.current_tick() + n
	var safety: int = n * 20 + 200
	while _battle.current_tick() < target and safety > 0:
		safety -= 1
		await get_tree().physics_frame


## The farthest any of `unit`'s bodies stands from its own formation slot (world units).
func _worst_body_slot_gap(unit: Unit) -> float:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	var worst: float = 0.0
	for i in range(mini(slots.size(), unit._sim_soldier_pos.size())):
		worst = maxf(worst, unit._sim_soldier_pos[i].distance_to(slots[i]))
	return worst


func test_close_tier_router_flees_at_flee_speed_with_its_bodies() -> void:
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 cavalry deployed")
	if router == null:
		return
	assert_eq(router.tier, FormationTier.CLOSE, "the router is simulated in the close tier")
	# Hold the rout open for the whole window: no rally, no timeout.
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router._rout()
	# Through the build-up too, the men keep pace with the anchor rather than the anchor
	# leaping to full flight and the block trailing it until the coupling drags it back.
	var worst_ramp: float = 0.0
	var ramp_end: int = _battle.current_tick() + RAMP_TICKS
	while _battle.current_tick() < ramp_end and router.state == Unit.State.ROUTING:
		await _advance_ticks(1)
		worst_ramp = maxf(worst_ramp, _worst_body_slot_gap(router))
	assert_eq(router.state, Unit.State.ROUTING, "still routing after the build-up")
	assert_lt(worst_ramp, MAX_BODY_SLOT_WU,
			"no body trails its slot by more than %.1f wu while the flight builds up (worst %.2f)"
			% [MAX_BODY_SLOT_WU, worst_ramp])

	var start: Vector2 = router.position
	var start_tick: int = _battle.current_tick()
	await _advance_ticks(MEASURE_TICKS)
	var ticks: int = _battle.current_tick() - start_tick
	assert_eq(router.state, Unit.State.ROUTING, "still routing at the end of the window")
	var per_tick: float = router.position.distance_to(start) / float(maxi(1, ticks))
	var flee_per_tick: float = router.flee_speed() / float(Engine.physics_ticks_per_second)
	assert_almost_eq(per_tick, flee_per_tick, flee_per_tick * SPEED_TOLERANCE_FRAC,
			"the close-tier router covers ground at flee_speed() (got %.3f wu/tick, flee %.3f)"
			% [per_tick, flee_per_tick])

	# The bodies keep up: every man is near his slot and the block's centroid sits on the
	# slot centroid, rather than trailing the anchor.
	var slots: PackedVector2Array = router.soldier_world_slots(router.soldiers)
	assert_eq(slots.size(), router._sim_soldier_pos.size(), "one body per slot")
	var body_centroid := Vector2.ZERO
	var slot_centroid := Vector2.ZERO
	for i in range(slots.size()):
		body_centroid += router._sim_soldier_pos[i]
		slot_centroid += slots[i]
	var worst: float = _worst_body_slot_gap(router)
	var inv: float = 1.0 / float(maxi(1, slots.size()))
	var centroid_gap: float = (body_centroid * inv).distance_to(slot_centroid * inv)
	assert_lt(worst, MAX_BODY_SLOT_WU,
			"no body trails its slot by more than %.1f wu (worst %.2f)" % [MAX_BODY_SLOT_WU, worst])
	assert_lt(centroid_gap, MAX_BODY_SLOT_WU,
			"the body centroid keeps up with the slot centroid (gap %.2f wu)" % centroid_gap)


func test_a_router_rallying_from_full_flight_comes_to_rest_with_its_bodies() -> void:
	# A router that earns its rally at full flight reins the flight in before it reforms, so
	# its riders come to rest with the anchor. Reforming straight out of full flight stopped
	# the anchor dead while the men, still running, overran their slots and had to walk back.
	var router: Unit = await _spawn(false, RALLY_ROUTER_COUNT)
	assert_not_null(router, "the team-0 cavalry deployed")
	if router == null:
		return
	router.rally_morale_threshold = 1000.0   # no rally until it is at full flight
	router.rout_time = 1000.0
	router.morale = 0.0
	router._rout()
	await _advance_ticks(RAMP_TICKS)
	assert_almost_eq(router._flee_pace, router.flee_speed(), 0.001, "at full flight before the rally")
	router.rally_morale_threshold = 0.0   # the rally is earned on the next tick
	var worst: float = 0.0
	var rallied_tick: int = -1
	# The men's own deceleration, tick to tick. Reforming straight out of full flight stopped
	# them from flee pace in a single tick; braking first brings them down gradually.
	var worst_drop: float = 0.0
	var last_pos: PackedVector2Array = router._sim_soldier_pos.duplicate()
	var last_speed: float = -1.0
	var budget: int = _battle.current_tick() + RALLY_WINDOW_TICKS
	while _battle.current_tick() < budget:
		await _advance_ticks(1)
		assert_eq(router.tier, FormationTier.CLOSE, "the router keeps its bodies (close tier) throughout")
		assert_eq(router._sim_soldier_pos.size(), router.soldiers, "one body per man to measure")
		worst = maxf(worst, _worst_body_slot_gap(router))
		var speed: float = _mean_body_speed(last_pos, router._sim_soldier_pos)
		if last_speed >= 0.0:
			worst_drop = maxf(worst_drop, last_speed - speed)
		last_speed = speed
		last_pos = router._sim_soldier_pos.duplicate()
		if rallied_tick < 0 and router.state == Unit.State.IDLE:
			rallied_tick = _battle.current_tick()
	assert_true(rallied_tick >= 0, "it rallied within the window")
	assert_lt(worst, MAX_BODY_SLOT_WU,
			"no body stood more than %.1f wu off its slot through the brake and the rally (worst %.2f)"
			% [MAX_BODY_SLOT_WU, worst])
	var max_drop: float = MAX_ONE_TICK_DROP_FRAC * router.flee_speed()
	assert_lt(worst_drop, max_drop,
			"the men never stop dead from their flight (worst drop %.2f wu/s in one tick, cap %.2f)"
			% [worst_drop, max_drop])


## Mean speed of a block's bodies over one tick (world units/s), from how far each moved
## between two consecutive position snapshots -- the ground they actually covered, not the
## stored velocity the arrival bookkeeping trims.
func _mean_body_speed(before: PackedVector2Array, after: PackedVector2Array) -> float:
	var n: int = mini(before.size(), after.size())
	if n == 0:
		return 0.0
	var total: float = 0.0
	for i in range(n):
		total += before[i].distance_to(after[i])
	return total / float(n) * float(Engine.physics_ticks_per_second)
