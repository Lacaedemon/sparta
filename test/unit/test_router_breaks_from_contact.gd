extends GutTest
## A router breaking from a melee runs from it, though its heading turns onto the flight at a
## bounded rate (Unit._turn_flight_toward) and so keeps its front toward the enemy for a while.
## While its front ranks are the ones in the melee (Unit.router_front_in_melee: armed once at
## the break from any contact enemy in its front arc, held until its heading lands on the
## flight or contact ends), none of its men is held back as an engaged front and couple()
## anchors the block on all of them. A router caught from behind keeps its anchor on its
## front, flight-side ranks.
##
## The regression the first test pins: with the bounded turn, couple() anchored a router
## breaking from a melee on its front ranks, the men the melee held, so the anchor followed
## them and the router hung in the fight.

# demos/inputs/contact-rout-keeps-ranks-1785.json's staging: a brittle 48-mount squadron
# facing north-west, charged by an enemy squadron from that side, routs while in contact and
# flees north, 45 degrees off its heading.
const SEED := 17851
const ROUTER := {"team": 0, "type": "Cavalry", "x": 900, "y": 900, "count": 48, "morale": 0.5,
		"facing": [-0.7071, -0.7071]}
const ENEMY := {"team": 1, "type": "Cavalry", "x": 740, "y": 740}
# Latest tick by which the router must have routed (it routs at tick 309).
const ROUT_BY_TICK := 400
# Ticks after the rout at which its men's progress is judged.
const WATCH_TICKS := 300
# The share of an unhindered flight's distance its men must cover by then. An unhindered
# anchor fleeing from a standstill covers the integral of min(accel x t, flee_speed()), and
# its men run on its slots, so they cover the same distance less the growth in their lag
# (501.7 wu here over 300 ticks). They start in the melee, with the enemy's files among them
# and riding north beside them for about 3 s, which costs any flight here 35 to 40 percent of
# that distance: 0.60 on main bb2a9e4f, where the grid snapped onto the flight and the anchor
# was thrown clear of its men, and 0.63 now. Anchored on the front ranks the melee holds, the
# block lost about half (0.52), the hold this pins. The bound sits between those: the melee may
# cost the flight at most 45 percent of an unhindered run.
const MIN_FLIGHT_SHARE := 0.55
# demos/inputs/routing-terrain-pathfinding.json's staging (catalog clip trapped_routing): the
# router routs at tick 344 next to the default map's hill and rallies at tick 704.
const PRESS_SEED := 12345
const PRESS_ROUTER := {"team": 0, "type": "Cavalry", "x": 960, "y": 620, "count": 60, "morale": 0.5}
const PRESS_ENEMY := {"team": 1, "type": "Cavalry", "x": 790, "y": 620}
const PRESS_WATCH_TICKS := 720
# test_close_tier_rout_speed.gd's caught staging: a 48-man Infantry block routs north and a
# 24-mount Cavalry pursuer 130 wu behind it is ordered onto it.
const CAUGHT_START := Vector2(700.0, 1300.0)
const CAUGHT_PURSUER_GAP := 130.0
const CAUGHT_ROUTER_MOVE_SPEED := 20.0   # tuned in wu/s, slow enough to be caught
const CATCH_TICKS := 600
# The arming stagings: a router facing east (off its northward flight) with enemy squadrons
# ARM_OFFSET from its anchor, inside melee contact range, ahead (east), behind (west) or on
# its flank (north, 90 degrees off its heading, outside the 60 degree front arc).
const ARM_START := Vector2(700.0, 1300.0)
const ARM_OFFSET := 40.0

var _battle: Node = null


func after_each() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


func _centroid(unit: Unit) -> Vector2:
	var sum := Vector2.ZERO
	for p in unit._sim_soldier_pos:
		sum += p
	return sum / float(maxi(1, unit._sim_soldier_pos.size()))


## Start `scenario` on the default map with `seed_value` and return the unit with uid 0.
func _start(scenario: Array, seed_value: int, all_control: bool = false) -> Unit:
	Replay.forced_seed = seed_value
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = all_control
	_battle.scenario = scenario
	add_child(_battle)
	await get_tree().physics_frame
	for u in get_tree().get_nodes_in_group("units"):
		if (u as Unit).uid == 0:
			return u
	return null


func test_a_router_breaking_from_contact_runs_from_the_melee() -> void:
	var router: Unit = await _start([ROUTER, ENEMY], SEED)
	assert_not_null(router, "setup: the player squadron deployed")
	if router == null:
		return
	var safety: int = (ROUT_BY_TICK + WATCH_TICKS) * 4
	while router.state != Unit.State.ROUTING and _battle.current_tick() < ROUT_BY_TICK and safety > 0:
		safety -= 1
		await get_tree().physics_frame
	assert_eq(router.state, Unit.State.ROUTING, "setup: the squadron routs by tick %d" % ROUT_BY_TICK)
	if router.state != Unit.State.ROUTING:
		return
	var tick: float = 1.0 / float(Engine.physics_ticks_per_second)
	var rout_tick: int = _battle.current_tick()
	var start: Vector2 = _centroid(router)
	var pace: float = 0.0
	var unhindered: float = 0.0
	var front_in_melee: bool = false
	while _battle.current_tick() < rout_tick + WATCH_TICKS and safety > 0:
		safety -= 1
		var before: int = _battle.current_tick()
		await get_tree().physics_frame
		front_in_melee = front_in_melee or router.router_front_in_melee()
		for k in range(_battle.current_tick() - before):
			pace = minf(pace + router.accel * tick, router.flee_speed())
			unhindered += pace * tick
	assert_true(front_in_melee, "setup: it breaks with its front in the melee")
	assert_eq(router.state, Unit.State.ROUTING, "setup: still routing at the end of the watch")
	var travelled: float = _centroid(router).distance_to(start)
	assert_gte(travelled, MIN_FLIGHT_SHARE * unhindered,
			"its men cover at least %.2f of an unhindered flight's %.1f wu in %d ticks (got %.1f wu, %.2f)"
			% [MIN_FLIGHT_SHARE, unhindered, WATCH_TICKS, travelled, travelled / maxf(unhindered, 0.001)])


func test_a_router_pressed_beside_a_hill_is_not_carried_into_it() -> void:
	# The catalog clip trapped_routing's staging: a brittle squadron just west of the default
	# map's hill, charged from the west, routs in contact and turns its flight at the bounded
	# rate while the pursuer still presses it. An earlier bounded turn in contact let the
	# press carry the anchor east into the hill, where the router counted as trapped and turned
	# to fight (TODO(#1788): that mechanism is undiagnosed). Its anchor and every man must stay
	# out of the hill, and it must flee on to its rally rather than stand and fight.
	var router: Unit = await _start([PRESS_ROUTER, PRESS_ENEMY], PRESS_SEED)
	assert_not_null(router, "setup: the player squadron deployed")
	if router == null:
		return
	var hills: Array = []
	for patch in _battle.terrain:
		if str(patch.get("kind", "")) == "block":
			hills.append(patch["rect"])
	assert_eq(hills.size(), 1, "setup: the default map has its one block-terrain hill")
	if hills.size() != 1:
		return
	var hill: Rect2 = hills[0]
	var routed: bool = false
	var anchor_in_hill: int = 0
	var men_in_hill: int = 0
	# router_front_in_melee() over the rout: armed at the break, it may clear once (its heading
	# lands on the flight, or contact ends) and never comes back, though the pursuer passes
	# alongside the router while still in contact.
	var front_was: bool = false
	var front_ever: bool = false
	var transitions: int = 0
	var safety: int = PRESS_WATCH_TICKS * 4
	while _battle.current_tick() < PRESS_WATCH_TICKS and safety > 0:
		safety -= 1
		await get_tree().physics_frame
		if not is_instance_valid(router):
			break
		if router.state == Unit.State.ROUTING:
			routed = true
		if not routed:
			continue
		var front: bool = router.router_front_in_melee()
		if router.state == Unit.State.ROUTING:
			if front_ever and front != front_was:
				transitions += 1
			front_ever = front_ever or front
			front_was = front
		if hill.has_point(router.position):
			anchor_in_hill += 1
		for p in router._sim_soldier_pos:
			if hill.has_point(p):
				men_in_hill += 1
	assert_true(routed, "setup: the squadron routs inside the watch")
	assert_true(is_instance_valid(router), "setup: the squadron is still on the field")
	if not is_instance_valid(router):
		return
	assert_true(front_ever, "setup: it breaks with its front in the melee")
	assert_lte(transitions, 1,
			"its front stops counting as in the melee at most once in the rout (got %d switches)"
			% transitions)
	assert_eq(anchor_in_hill, 0, "the press never carries the router's anchor into the hill")
	assert_eq(men_in_hill, 0, "nor any of its men")
	assert_false(router._shattered, "it is never trapped into fighting to the death")
	assert_eq(router.state, Unit.State.IDLE, "it flees on and rallies inside the watch")


func test_a_router_caught_from_behind_anchors_on_its_flight_side_ranks() -> void:
	# A router caught by a pursuer from behind is in contact with its front, flight-side ranks
	# farthest from the pursuer: couple() keeps anchoring on them rather than on the whole
	# block, so the pursuer's press on its rear does not drag the anchor back.
	var scenario: Array = [
		{"team": 0, "type": "Infantry", "count": 48, "x": CAUGHT_START.x, "y": CAUGHT_START.y,
				"facing": [0, -1]},
		{"team": 1, "type": "Cavalry", "count": 24, "x": CAUGHT_START.x,
				"y": CAUGHT_START.y + CAUGHT_PURSUER_GAP, "facing": [0, -1]},
	]
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.terrain = []
	_battle.scenario = scenario
	add_child(_battle)
	await get_tree().physics_frame
	var router: Unit = null
	var pursuer: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null:
			if unit.team == 0:
				router = unit
			else:
				pursuer = unit
	assert_not_null(router, "setup: the router deployed")
	assert_not_null(pursuer, "setup: the pursuer deployed")
	if router == null or pursuer == null:
		return
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router.move_speed = CAUGHT_ROUTER_MOVE_SPEED
	router._rout()
	_battle._apply_order_cmd({"units": [pursuer.uid], "x": router.position.x,
			"y": router.position.y, "target": router.uid})
	var caught: bool = false
	for i in range(CATCH_TICKS):
		await get_tree().physics_frame
		if router._in_enemy_contact:
			caught = true
			break
	assert_true(caught, "setup: the pursuer catches the router")
	if not caught:
		return
	assert_eq(router.state, Unit.State.ROUTING, "setup: still routing when caught")
	assert_lt((pursuer.position - router.position).dot(router.facing), 0.0,
			"setup: the pursuer stands behind the router's heading")
	assert_false(router.router_front_in_melee(), "a router caught from behind does not have its front in the melee")
	var n: int = router._sim_soldier_pos.size()
	var anchor: PackedInt32Array = router.position_anchor_indices(n)
	assert_gt(anchor.size(), 0, "couple() anchors it on a front selection, not the whole block")
	assert_lt(anchor.size(), n, "and on part of the block only")


## Deploy a 48-mount squadron at ARM_START facing east, with an enemy squadron at each
## `offsets` entry (relative to ARM_START, in that spawn order, all idle), rout it, and return
## whether it broke with its front in the melee.
func _armed_with_enemies_at(offsets: Array) -> bool:
	var scenario: Array = [{"team": 0, "type": "Cavalry", "count": 48, "x": ARM_START.x,
			"y": ARM_START.y, "facing": [1, 0]}]
	for off in offsets:
		var at: Vector2 = ARM_START + (off as Vector2)
		scenario.append({"team": 1, "type": "Cavalry", "count": 24, "x": at.x, "y": at.y,
				"facing": [-1, 0]})
	var router: Unit = await _start(scenario, 12345, true)
	assert_not_null(router, "setup: the squadron deployed")
	if router == null:
		return false
	var in_contact: int = 0
	for u in get_tree().get_nodes_in_group("units"):
		var enemy: Unit = u as Unit
		if enemy != null and enemy.team != router.team:
			var reach: float = maxf(router.attack_range, enemy.attack_range) + router.RADIUS + enemy.RADIUS
			if router.position.distance_to(enemy.position) <= reach:
				in_contact += 1
	assert_eq(in_contact, offsets.size(), "setup: every enemy squadron is in melee contact range")
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router._rout()
	var armed: bool = router.router_front_in_melee()
	_battle.free()
	_battle = null
	return armed


func test_a_router_arms_its_front_in_the_melee_from_any_enemy_in_its_front_arc() -> void:
	var ahead := Vector2(ARM_OFFSET, 0.0)
	var behind := Vector2(-ARM_OFFSET, 0.0)
	assert_true(await _armed_with_enemies_at([ahead, behind]),
			"an enemy ahead arms it with another behind, the one ahead spawned first")
	assert_true(await _armed_with_enemies_at([behind, ahead]),
			"and with the one behind spawned first")
	assert_true(await _armed_with_enemies_at([ahead]), "an enemy ahead alone arms it")


func test_a_router_with_no_enemy_in_its_front_arc_is_not_armed() -> void:
	assert_false(await _armed_with_enemies_at([Vector2(-ARM_OFFSET, 0.0)]),
			"an enemy only behind does not arm it")
	assert_false(await _armed_with_enemies_at([Vector2(0.0, -ARM_OFFSET)]),
			"nor does an enemy only on its flank, 90 degrees off its heading")
