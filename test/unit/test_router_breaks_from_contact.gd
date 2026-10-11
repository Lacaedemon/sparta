extends GutTest
## A router breaking from a melee runs from it at least as fast as it did when its slot grid
## snapped onto the flight, though its heading now turns onto the flight at a bounded rate.
## SoldierBodies.step and couple() treat a router's men alike: none is held back from the
## flight's feed-forward as an engaged front, and the block does not anchor on its front ranks,
## which the melee holds.
##
## The regression this pins: with the bounded turn, a router breaking from a melee kept its
## front toward the enemy, and couple() anchored the block on those front men, who stood in the
## melee. The anchor followed them, so the router hung in the fight, its men gaining 41 wu in
## their first 150 ticks against 61 when its grid snapped.

# demos/inputs/contact-rout-keeps-ranks-1785.json's staging: a brittle 48-mount squadron
# facing north-west, charged by an enemy squadron from that side, routs while in contact and
# flees north, 45 degrees off its heading.
const SEED := 17851
const ROUTER := {"team": 0, "type": "Cavalry", "x": 900, "y": 900, "count": 48, "morale": 0.5,
		"facing": [-0.7071, -0.7071]}
const ENEMY := {"team": 1, "type": "Cavalry", "x": 740, "y": 740}
# Latest tick by which the router must have routed (it routs at tick 309).
const ROUT_BY_TICK := 400
# How far the router's men's centroid travels after the rout, measured in this staging on main
# bb2a9e4f, where the in-contact flight snapped the grid onto the flight at once: 60.6 wu
# after 150 ticks and 299.3 wu after 300 (41.0 and 259.7 with the bounded turn alone). The bounds are main's own figures rounded down to the
# whole world unit: no slower than main.
const AFTER_SHORT := 150
const MAIN_TRAVEL_SHORT := 60.0
const AFTER_LONG := 300
const MAIN_TRAVEL_LONG := 299.0
# demos/inputs/routing-terrain-pathfinding.json's staging (catalog clip trapped_routing): the
# router routs at tick 344 and rallies at tick 704.
const PRESS_SEED := 12345
const PRESS_ROUTER := {"team": 0, "type": "Cavalry", "x": 960, "y": 620, "count": 60, "morale": 0.5}
const PRESS_ENEMY := {"team": 1, "type": "Cavalry", "x": 790, "y": 620}
const PRESS_HILL := Rect2(1150.0, 380.0, 250.0, 200.0)   # Battle.TERRAIN's block rect
const PRESS_WATCH_TICKS := 720

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


func test_a_router_breaking_from_contact_gains_ground_no_slower_than_a_snapped_grid() -> void:
	Replay.forced_seed = SEED
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = [ROUTER, ENEMY]
	add_child(_battle)
	await get_tree().physics_frame
	var router: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		if (u as Unit).uid == 0:
			router = u
	assert_not_null(router, "setup: the player squadron deployed")
	if router == null:
		return
	var safety: int = ROUT_BY_TICK * 4
	while router.state != Unit.State.ROUTING and _battle.current_tick() < ROUT_BY_TICK and safety > 0:
		safety -= 1
		await get_tree().physics_frame
	assert_eq(router.state, Unit.State.ROUTING, "setup: the squadron routs by tick %d" % ROUT_BY_TICK)
	if router.state != Unit.State.ROUTING:
		return
	assert_true(router._in_enemy_contact, "setup: it routs while still in contact")
	var rout_tick: int = _battle.current_tick()
	var start: Vector2 = _centroid(router)
	var travel := {}
	while _battle.current_tick() < rout_tick + AFTER_LONG and safety > 0:
		safety -= 1
		await get_tree().physics_frame
		var since: int = _battle.current_tick() - rout_tick
		if since == AFTER_SHORT or since == AFTER_LONG:
			travel[since] = _centroid(router).distance_to(start)
	assert_eq(router.state, Unit.State.ROUTING, "setup: still routing at the end of the watch")
	assert_gte(float(travel.get(AFTER_SHORT, 0.0)), MAIN_TRAVEL_SHORT,
			"its men gain ground no slower than main's in the first %d ticks (got %.1f wu)"
			% [AFTER_SHORT, float(travel.get(AFTER_SHORT, 0.0))])
	assert_gte(float(travel.get(AFTER_LONG, 0.0)), MAIN_TRAVEL_LONG,
			"and over %d ticks (got %.1f wu)" % [AFTER_LONG, float(travel.get(AFTER_LONG, 0.0))])


func test_a_router_pressed_beside_a_hill_is_not_carried_into_it() -> void:
	# The catalog clip trapped_routing's staging: a brittle squadron just west of the default
	# map's hill, charged from the west, routs in contact and turns its flight at the bounded
	# rate while the pursuer still presses it. An earlier bounded turn in contact let the
	# press carry the anchor east into the hill, where the router counted as trapped and turned
	# to fight (TODO(#1788): that mechanism is undiagnosed). Its anchor and every man must stay
	# out of the hill, and it must flee on to its rally rather than stand and fight.
	Replay.forced_seed = PRESS_SEED
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = [PRESS_ROUTER, PRESS_ENEMY]
	add_child(_battle)
	await get_tree().physics_frame
	var router: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		if (u as Unit).uid == 0:
			router = u
	assert_not_null(router, "setup: the player squadron deployed")
	if router == null:
		return
	var routed: bool = false
	var anchor_in_hill: int = 0
	var men_in_hill: int = 0
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
		if PRESS_HILL.has_point(router.position):
			anchor_in_hill += 1
		for p in router._sim_soldier_pos:
			if PRESS_HILL.has_point(p):
				men_in_hill += 1
	assert_true(routed, "setup: the squadron routs inside the watch")
	assert_true(is_instance_valid(router), "setup: the squadron is still on the field")
	if not is_instance_valid(router):
		return
	assert_eq(anchor_in_hill, 0, "the press never carries the router's anchor into the hill")
	assert_eq(men_in_hill, 0, "nor any of its men")
	assert_false(router._shattered, "it is never trapped into fighting to the death")
	assert_eq(router.state, Unit.State.IDLE, "it flees on and rallies inside the watch")
