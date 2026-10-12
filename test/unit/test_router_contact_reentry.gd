extends GutTest
## A router's couple() anchor reads its anchor contact (Unit._router_anchor_contact), not its
## physical contact flag. The two agree until the router first leaves contact in its rout;
## after that it anchors as one in contact again only within router_contact_reentry_frac of the
## melee contact range, or to an enemy fighting it. Without that gap a router at the edge of
## the range switched anchors every tick or two between its front ranks and its whole block.
## Its physical contact (_in_enemy_contact, which gates body contact and separation) keeps the
## full range throughout.

# A 16-mount Cavalry squadron at morale 0.5, charged from the east by a 40-man Infantry block,
# routs at tick 293 and outruns the block at the edge of contact range, its front not in the
# melee. Without the gap it first leaves contact 141 ticks after the rout and switches anchors
# 7 times by 148 ticks after it.
const EDGE_SEED := 12345
const EDGE_ROUTER := {"team": 0, "type": "Cavalry", "x": 1260, "y": 870, "count": 16, "morale": 0.5}
const EDGE_PURSUER := {"team": 1, "type": "Infantry", "x": 1460, "y": 870, "count": 40, "frontage": 10,
		"facing": [-1, 0]}
const EDGE_ROUT_BY_TICK := 400
# Ticks after the rout that the edge staging is watched for: well past the last tick of
# physical contact on either tree.
const EDGE_WATCH_TICKS := 300
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


func _anchored(router: Unit) -> bool:
	return not router.position_anchor_indices(router._sim_soldier_pos.size()).is_empty()


func test_a_router_at_the_edge_of_contact_switches_anchor_once() -> void:
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
	var last_contact: int = -1
	var left_contact: bool = false
	var front_in_melee: bool = false
	var unanchored_before_leaving: int = 0
	while _battle.current_tick() < rout_tick + EDGE_WATCH_TICKS and safety > 0:
		safety -= 1
		await get_tree().physics_frame
		if not is_instance_valid(router) or router.state != Unit.State.ROUTING:
			break
		var anchored: bool = _anchored(router)
		if anchored != anchored_was:
			anchor_switches += 1
		anchored_was = anchored
		front_in_melee = front_in_melee or router.router_front_in_melee()
		if router._in_enemy_contact:
			last_contact = _battle.current_tick() - rout_tick
			if not left_contact and not anchored:
				unanchored_before_leaving += 1
		else:
			left_contact = true
	assert_true(is_instance_valid(router) and router.state == Unit.State.ROUTING,
			"setup: still routing at the end of the watch")
	assert_false(front_in_melee, "setup: its front is not in the melee")
	assert_gt(last_contact, 0, "setup: the router is in contact after the rout")
	assert_lt(last_contact, EDGE_WATCH_TICKS - 60, "setup: and leaves it well inside the watch")
	assert_eq(unanchored_before_leaving, 0,
			"it anchors on its front ranks on every tick in contact until it first leaves")
	assert_eq(anchor_switches, 1,
			"then switches to its whole-block anchor once (got %d switches)" % anchor_switches)


## The router's re-entry share, its anchor contact and its left-contact mark, read and written
## by name so this file still loads on a tree without them (where the edge test above fails
## for its stated reason).
func _frac(router: Unit) -> float:
	return float(router.get("router_contact_reentry_frac"))


func _anchor_contact(router: Unit) -> bool:
	return bool(router.get("_router_anchor_contact"))


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


## Place `enemy` `share` of the melee contact range behind `router`, refresh the router's
## contact, and return its anchor contact.
func _place(router: Unit, enemy: Unit, share: float) -> bool:
	var reach: float = maxf(router.attack_range, enemy.attack_range) + router.RADIUS + enemy.RADIUS
	enemy.position = router.position + Vector2.DOWN * reach * share
	router._refresh_enemy_contact()
	return _anchor_contact(router)


func test_a_router_anchors_in_contact_again_only_nearer_once_it_has_left() -> void:
	var pair: Array = await _router_and_enemy()
	if pair.is_empty():
		return
	var router: Unit = pair[0]
	var enemy: Unit = pair[1]
	var between: float = (1.0 + _frac(router)) * 0.5
	assert_true(_place(router, enemy, between), "a fresh router anchors in contact at the full range")
	assert_true(_anchored(router), "on its front ranks")
	assert_false(_place(router, enemy, 1.01), "and leaves anchor contact just past it")
	assert_true(_left(router), "which marks it as having left")
	assert_false(_place(router, enemy, between),
			"then an enemy back inside the range but outside the re-entry share is not anchor contact")
	assert_false(_anchored(router), "so it stays on its whole-block anchor")
	assert_true(_place(router, enemy, _frac(router) * 0.99), "while one inside the re-entry share is")
	assert_true(_place(router, enemy, between), "and it leaves again only at the full range")
	assert_false(_place(router, enemy, 1.01), "as before")


func test_a_router_outside_its_anchor_contact_is_still_in_physical_contact() -> void:
	# The gap is the anchor's alone: inside the full range the router's bodies still meet the
	# enemy's, whichever anchor couple() reads.
	var pair: Array = await _router_and_enemy()
	if pair.is_empty():
		return
	var router: Unit = pair[0]
	var enemy: Unit = pair[1]
	var between: float = (1.0 + _frac(router)) * 0.5
	_place(router, enemy, 0.5)
	_place(router, enemy, 1.01)
	assert_false(_place(router, enemy, between), "setup: outside its anchor contact")
	assert_true(router._in_enemy_contact, "it is in physical contact at the full range")
	var n: int = router._sim_soldier_pos.size()
	assert_false(router.contact_soldier_indices(n).is_empty(), "so its bodies are in the contact tier")
	assert_false(_anchored(router), "while couple() anchors its whole block")


func test_a_router_held_by_an_enemy_fighting_it_anchors_in_contact_at_the_full_range() -> void:
	# A router caught again and held in a melee near the edge of the range anchors as one in
	# contact: the re-entry share is only for an enemy hovering at the edge without fighting it.
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
			"an enemy fighting it inside the full range puts it in anchor contact")
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


func test_only_a_router_uses_its_anchor_contact_and_a_fresh_rout_resets_it() -> void:
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
	_place(router, enemy, between)
	assert_true(router._in_enemy_contact, "setup: an idle unit in contact")
	assert_true(_anchored(router), "out of the rout, the anchor reads physical contact again")
	_place(router, enemy, 1.01)
	assert_true(_left(router), "and an idle unit leaving contact leaves the mark alone")
	router.set("_router_left_contact", false)
	_place(router, enemy, 0.5)
	_place(router, enemy, 1.01)
	assert_false(_left(router), "nor does an idle unit leaving contact set it")
	router.set("_router_left_contact", true)
	_place(router, enemy, between)
	router._rout()
	assert_eq(router.state, Unit.State.ROUTING, "setup: it routs again")
	assert_false(_left(router), "a fresh rout clears the mark")
	assert_true(_anchor_contact(router), "and starts its anchor contact from its physical contact")
	assert_true(_place(router, enemy, between), "so it anchors in contact at the full range again")


func test_a_router_with_its_front_in_the_melee_releases_it_at_the_full_range() -> void:
	# The latch that anchors such a router on its whole block reads physical contact, so it
	# clears where it always did and stays clear when the router comes back into contact.
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
	_place(router, enemy, between)
	router._update_router_front_in_melee()
	assert_true(router._in_enemy_contact, "setup: back in physical contact")
	assert_false(router.router_front_in_melee(), "and not re-armed by contact coming back")
