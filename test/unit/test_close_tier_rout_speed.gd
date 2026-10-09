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
# The in-contact router staging: ticks for the two blocks to close and engage before the
# rout, and ticks watched after it.
const CONTACT_SETTLE_TICKS := 240
const CONTACT_WATCH_TICKS := 240
# How far, on average, a router broken from melee may stand ahead of its slots toward its line
# of flight while its front is still in the engaged tier (world units). With the engaged latch
# frozen for the whole rout, the front stayed paired on the melee line while the flight drove
# the bulk on: about 33 wu ahead of its slots, into the enemy block in its way. With the latch
# decaying as for any unit that stops fighting, about 7 wu.
const MAX_ENGAGED_FLIGHT_LEAD_WU := 15.0
# Ticks after the break by which the router must have left the engaged tier: ENGAGED_LINGER
# (0.5 s, 30 ticks at 60 tps) plus a margin.
const ENGAGED_RELEASE_TICKS := 45

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
	_battle.terrain = []
	_battle.scenario = [
		{"team": 0, "type": "Cavalry", "count": 12, "x": ROUTER_START.x, "y": ROUTER_START.y,
				"facing": [0, -1]},
		{"team": 1, "type": "Cavalry", "count": 12, "x": ENEMY_START.x, "y": ENEMY_START.y,
				"facing": [-1, 0]},
	]
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


## How far, on average, `unit`'s bodies stand ahead of their own formation slots along `dir`
## (world units; negative means behind).
func _mean_body_lead(unit: Unit, dir: Vector2) -> float:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	var n: int = mini(slots.size(), unit._sim_soldier_pos.size())
	if n == 0:
		return 0.0
	var lead: float = 0.0
	for i in range(n):
		lead += (unit._sim_soldier_pos[i] - slots[i]).dot(dir)
	return lead / float(n)


func test_a_router_broken_from_melee_leaves_the_engaged_tier() -> void:
	# A router is not FIGHTING, so its engaged latch must decay like any other unit's that stops
	# fighting. Left armed for the whole rout, it kept the router's front paired on the melee
	# line while the flight drove the bulk on ahead of its slots, into the enemy block in its
	# way. Team 0 flees north, and the enemy attacks it from the north: across its line of flight.
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.terrain = []
	_battle.scenario = [
		{"team": 0, "type": "Cavalry", "count": 24, "x": 700.0, "y": 1300.0, "facing": [0, -1]},
		{"team": 1, "type": "Infantry", "count": 120, "x": 700.0, "y": 1160.0, "facing": [0, 1]},
	]
	add_child(_battle)
	await get_tree().physics_frame
	var router: Unit = null
	var enemy: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit == null:
			continue
		if unit.team == 0:
			router = unit
		else:
			enemy = unit
	assert_not_null(router, "the router deployed")
	assert_not_null(enemy, "the enemy deployed")
	if router == null or enemy == null:
		return
	_battle._apply_order_cmd({"units": [enemy.uid], "x": router.position.x,
			"y": router.position.y, "target": router.uid})
	for i in range(CONTACT_SETTLE_TICKS):
		if router.state == Unit.State.FIGHTING:
			break
		await _advance_ticks(1)
	assert_eq(router.state, Unit.State.FIGHTING, "setup: the enemy closed and the two blocks fought")
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router._rout()
	await _advance_ticks(1)
	assert_true(router._in_enemy_contact,
			"a router still pressed against the enemy it broke from stays in enemy contact")
	var flee: Vector2 = router._flee_heading()
	var worst_lead: float = -INF
	var engaged_ticks: int = 0
	var engaged_at_release: bool = true
	for i in range(CONTACT_WATCH_TICKS):
		await _advance_ticks(1)
		if router.state != Unit.State.ROUTING:
			break
		if i + 1 == ENGAGED_RELEASE_TICKS:
			engaged_at_release = router.is_engaged()
		if router.body_tier_soldier_indices(router._sim_soldier_pos.size()).is_empty():
			continue
		engaged_ticks += 1
		worst_lead = maxf(worst_lead, _mean_body_lead(router, flee))
	assert_gt(engaged_ticks, 0, "setup: the router still had bodies in the engaged tier after it broke")
	assert_false(engaged_at_release,
			"the router left the engaged tier within %d ticks of breaking" % ENGAGED_RELEASE_TICKS)
	assert_lt(worst_lead, MAX_ENGAGED_FLIGHT_LEAD_WU,
			"an engaged router's bulk stays on its slots rather than running on with the flight"
			+ " (worst mean lead %.2f wu)" % worst_lead)


func test_a_router_clear_of_every_enemy_is_not_in_enemy_contact() -> void:
	# A router never runs _think(), where _in_enemy_contact is recomputed, so the rout path
	# must refresh it: left as it was when the unit broke, a router that has got clear would
	# keep its bodies colliding as if still pressed against the enemy it fled. Here the only
	# enemy stands far beyond contact range, and the flag starts stale-true as at a break.
	var router: Unit = await _spawn()
	assert_not_null(router, "the team-0 cavalry deployed")
	if router == null:
		return
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router._in_enemy_contact = true
	router._rout()
	await _advance_ticks(1)
	assert_eq(router.state, Unit.State.ROUTING, "setup: the unit is routing")
	assert_false(router._in_enemy_contact,
			"a router with no enemy within contact range is not in enemy contact")
