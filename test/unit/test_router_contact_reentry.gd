extends GutTest
## A router leaves enemy contact at the full melee contact range, as any unit does, but once it
## has left contact in its current rout it comes back into it only within
## router_contact_reentry_frac of that range (Unit._refresh_enemy_contact). Without that gap a
## router at the edge of the range flipped in and out of contact every tick or two, and its
## couple() anchor flipped with it between its front ranks and its whole block.

# A 16-mount Cavalry squadron at morale 0.5, charged from the east by a 40-man Infantry block,
# routs at tick 293 and outruns the block at the edge of contact range, its front not in the
# melee.
const EDGE_SEED := 12345
const EDGE_ROUTER := {"team": 0, "type": "Cavalry", "x": 1260, "y": 870, "count": 16, "morale": 0.5}
const EDGE_PURSUER := {"team": 1, "type": "Infantry", "x": 1460, "y": 870, "count": 40, "frontage": 10,
		"facing": [-1, 0]}
const EDGE_ROUT_BY_TICK := 400
# Ticks after the rout that the edge staging is watched for: contact ends 148 ticks after the
# rout without the re-entry gap and 140 with it, so the watch runs well past both.
const EDGE_WATCH_TICKS := 300
# The last tick, counted from the rout, on which the router may still be in contact. Without
# the re-entry gap it first leaves contact 141 ticks after the rout and is last in contact
# 148 ticks after it, after switching anchors 7 times. The gap must not keep it in contact any
# longer than that.
const EDGE_CONTACT_ENDS_BY := 148
# A 16-mount squadron routing north with an enemy squadron behind it.
const GAP_START := Vector2(700.0, 1300.0)

var _battle: Node = null


func after_each() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


## Start `scenario` on the default map with `seed_value`; return its units by uid.
func _start(scenario: Array, seed_value: int, all_control: bool = false) -> Dictionary:
	Replay.forced_seed = seed_value
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = all_control
	_battle.scenario = scenario
	add_child(_battle)
	await get_tree().physics_frame
	var by_uid := {}
	for u in get_tree().get_nodes_in_group("units"):
		by_uid[(u as Unit).uid] = u
	return by_uid


func test_a_router_at_the_edge_of_contact_leaves_it_once() -> void:
	var units: Dictionary = await _start([EDGE_ROUTER, EDGE_PURSUER], EDGE_SEED)
	var router: Unit = units.get(0)
	assert_not_null(router, "setup: the squadron deployed")
	if router == null:
		return
	var safety: int = (EDGE_ROUT_BY_TICK + EDGE_WATCH_TICKS) * 4
	while router.state != Unit.State.ROUTING and _battle.current_tick() < EDGE_ROUT_BY_TICK and safety > 0:
		safety -= 1
		await get_tree().physics_frame
	assert_eq(router.state, Unit.State.ROUTING, "setup: the squadron routs by tick %d" % EDGE_ROUT_BY_TICK)
	if router.state != Unit.State.ROUTING:
		return
	var rout_tick: int = _battle.current_tick()
	var anchored_was: bool = true
	var anchor_switches: int = 0
	var contact_was: bool = router._in_enemy_contact
	var contact_switches: int = 0
	var last_contact: int = -1
	var front_in_melee: bool = false
	var unanchored_in_contact: int = 0
	while _battle.current_tick() < rout_tick + EDGE_WATCH_TICKS and safety > 0:
		safety -= 1
		await get_tree().physics_frame
		if not is_instance_valid(router) or router.state != Unit.State.ROUTING:
			break
		var anchored: bool = not router.position_anchor_indices(router._sim_soldier_pos.size()).is_empty()
		if anchored != anchored_was:
			anchor_switches += 1
		anchored_was = anchored
		if router._in_enemy_contact != contact_was:
			contact_switches += 1
		contact_was = router._in_enemy_contact
		front_in_melee = front_in_melee or router.router_front_in_melee()
		if router._in_enemy_contact:
			last_contact = _battle.current_tick() - rout_tick
			if not anchored:
				unanchored_in_contact += 1
	assert_true(is_instance_valid(router) and router.state == Unit.State.ROUTING,
			"setup: still routing at the end of the watch")
	assert_false(front_in_melee, "setup: its front is not in the melee")
	assert_gt(last_contact, 0, "setup: the router is in contact after the rout")
	assert_lt(last_contact, EDGE_WATCH_TICKS - 60, "setup: and leaves it well inside the watch")
	assert_eq(contact_switches, 1, "it leaves contact once (got %d switches)" % contact_switches)
	assert_eq(anchor_switches, 1,
			"so it switches to its whole-block anchor once (got %d switches)" % anchor_switches)
	assert_eq(unanchored_in_contact, 0, "it anchors on its front ranks on every tick in contact")
	assert_lte(last_contact, EDGE_CONTACT_ENDS_BY,
			"and leaves contact no later than without the gap (got %d ticks after the rout)" % last_contact)


## The router's re-entry share and its left-contact mark, read and written by name so this file
## still loads on a tree without them (where the edge test above fails for its stated reason).
func _frac(router: Unit) -> float:
	return float(router.get("router_contact_reentry_frac"))


func _left(router: Unit) -> bool:
	return bool(router.get("_router_left_contact"))


## Rout a squadron with an enemy squadron behind it and clear its engaged latch. Returns
## [router, enemy], or an empty array when the staging failed.
func _router_and_enemy() -> Array:
	var units: Dictionary = await _start([
		{"team": 0, "type": "Cavalry", "count": 16, "x": GAP_START.x, "y": GAP_START.y, "facing": [0, -1]},
		{"team": 1, "type": "Cavalry", "count": 16, "x": GAP_START.x, "y": GAP_START.y + 400.0,
				"facing": [0, -1]},
	], 12345, true)
	var router: Unit = units.get(0)
	var enemy: Unit = units.get(1)
	assert_not_null(router, "setup: the squadron deployed")
	assert_not_null(enemy, "setup: the enemy deployed")
	if router == null or enemy == null:
		return []
	assert_not_null(router.get("router_contact_reentry_frac"), "the router has a re-entry share")
	if router.get("router_contact_reentry_frac") == null:
		return []
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router._rout()
	router._engaged_linger = 0.0
	assert_eq(router.state, Unit.State.ROUTING, "setup: the squadron routs")
	return [router, enemy]


## Place `enemy` `share` of the melee contact range behind `router` and refresh the router's
## contact flag.
func _place(router: Unit, enemy: Unit, share: float) -> bool:
	var reach: float = maxf(router.attack_range, enemy.attack_range) + router.RADIUS + enemy.RADIUS
	enemy.position = router.position + Vector2.DOWN * reach * share
	router._refresh_enemy_contact()
	return router._in_enemy_contact


func test_a_router_comes_back_into_contact_only_nearer_once_it_has_left() -> void:
	var pair: Array = await _router_and_enemy()
	if pair.is_empty():
		return
	var router: Unit = pair[0]
	var enemy: Unit = pair[1]
	var between: float = (1.0 + _frac(router)) * 0.5
	assert_true(_place(router, enemy, between), "a fresh router meets the enemy at the full range")
	assert_false(_place(router, enemy, 1.01), "and leaves contact just past it")
	assert_true(_left(router), "which marks it as having left contact")
	assert_false(_place(router, enemy, between),
			"then the enemy back inside the range but outside the re-entry share is not contact")
	assert_true(_place(router, enemy, _frac(router) * 0.99), "while one inside the re-entry share is")
	assert_true(_place(router, enemy, between), "and it leaves again only at the full range")
	assert_false(_place(router, enemy, 1.01), "as before")


func test_a_router_held_by_an_enemy_fighting_it_stays_in_contact_at_the_full_range() -> void:
	# A router caught again and held in a melee near the edge of the range is in contact: the
	# re-entry share is only for an enemy hovering at the edge without fighting it.
	var pair: Array = await _router_and_enemy()
	if pair.is_empty():
		return
	var router: Unit = pair[0]
	var enemy: Unit = pair[1]
	var between: float = (1.0 + _frac(router)) * 0.5
	_place(router, enemy, 0.5)
	assert_false(_place(router, enemy, 1.01), "setup: it leaves contact")
	enemy.state = Unit.State.FIGHTING
	enemy.target_enemy = router
	assert_true(_place(router, enemy, between),
			"an enemy fighting it inside the full range puts it in contact")
	assert_false(_place(router, enemy, 1.01), "setup: it leaves contact again")
	enemy.state = Unit.State.MOVING
	assert_false(_place(router, enemy, between),
			"one chasing it without fighting it still has to come inside the re-entry share")
	enemy.state = Unit.State.FIGHTING
	enemy.target_enemy = null
	assert_false(_place(router, enemy, between), "as does one fighting someone else")


func test_the_reentry_share_is_caller_configurable() -> void:
	var pair: Array = await _router_and_enemy()
	if pair.is_empty():
		return
	var router: Unit = pair[0]
	var enemy: Unit = pair[1]
	var consts: Dictionary = (Unit as Script).get_script_constant_map()
	assert_almost_eq(_frac(router), float(consts.get("ROUTER_CONTACT_REENTRY_FRAC", -1.0)), 1e-6,
			"setup: the default")
	router.set("router_contact_reentry_frac", 1.0)
	_place(router, enemy, 0.5)
	assert_false(_place(router, enemy, 1.01), "setup: it leaves contact")
	assert_true(_place(router, enemy, 0.99), "a share of 1 lets it straight back in at the full range")


func test_only_a_router_uses_the_reentry_share_and_a_fresh_rout_clears_it() -> void:
	var pair: Array = await _router_and_enemy()
	if pair.is_empty():
		return
	var router: Unit = pair[0]
	var enemy: Unit = pair[1]
	var between: float = (1.0 + _frac(router)) * 0.5
	_place(router, enemy, 0.5)
	_place(router, enemy, 1.01)
	assert_true(_left(router), "setup: it has left contact")
	router.state = Unit.State.IDLE
	assert_true(_place(router, enemy, between), "out of the rout, contact is the full range again")
	assert_false(_place(router, enemy, 1.01), "setup: out of contact")
	assert_true(_left(router), "and an idle unit leaving contact leaves the mark alone")
	router.set("_router_left_contact", false)
	assert_true(_place(router, enemy, 0.5), "setup: an idle unit back in contact")
	_place(router, enemy, 1.01)
	assert_false(_left(router), "nor does an idle unit leaving contact set it")
	router.set("_router_left_contact", true)
	router._rout()
	assert_eq(router.state, Unit.State.ROUTING, "setup: it routs again")
	assert_false(_left(router), "a fresh rout clears the mark")
	assert_true(_place(router, enemy, between), "so it meets the enemy at the full range again")


func test_a_router_with_its_front_in_the_melee_releases_it_at_the_full_range() -> void:
	# The latch that anchors such a router on its whole block clears when it leaves contact,
	# which is still at the full range, and stays clear when it comes back into contact.
	var pair: Array = await _router_and_enemy()
	if pair.is_empty():
		return
	var router: Unit = pair[0]
	var enemy: Unit = pair[1]
	var between: float = (1.0 + _frac(router)) * 0.5
	router._router_front_in_melee = true
	router._flee_velocity = Vector2.UP * router.flee_speed()
	router.facing = Vector2.UP.rotated(0.5)
	_place(router, enemy, between)
	router._update_router_front_in_melee()
	assert_true(router.router_front_in_melee(), "held in contact inside the full range")
	_place(router, enemy, 1.01)
	router._update_router_front_in_melee()
	assert_false(router.router_front_in_melee(), "cleared once it leaves the full range")
	_place(router, enemy, _frac(router) * 0.5)
	router._update_router_front_in_melee()
	assert_true(router._in_enemy_contact, "setup: back in contact")
	assert_false(router.router_front_in_melee(), "and not re-armed by contact coming back")
