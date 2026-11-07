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
# The same squadron and block as router-contact-edge-1801's clip, on that clip's seed 18011
# perturbed by run 1 (DemoSeed.seed_for_run): the squadron routs at tick 326 with most of its
# riders off their slots, so its front-rank and whole-block anchors settle it 54 to 86 wu apart.
# On main a37af5c0 (measured 2026-11-06) it switched anchors 21 times in the 300 ticks after
# its rout, re-entering its anchor contact every 6 to 8 ticks.
const OFF_SLOT_SEED := 1051351146
const OFF_SLOT_SCENARIO := [
	{"team": 0, "type": "Cavalry", "x": 520, "y": 980, "count": 16, "morale": 0.5},
	{"team": 1, "type": "Infantry", "x": 730, "y": 980, "count": 40, "frontage": 10, "facing": [-1, 0]},
]
const EDGE_ROUT_BY_TICK := 400
# Ticks after the rout that the edge staging is watched for: well past the last tick of
# physical contact on either tree.
const EDGE_WATCH_TICKS := 300
# A 16-mount squadron routing north with an enemy squadron behind it.
const GAP_START := Vector2(700.0, 1300.0)
# The front-rank anchor offset (SoldierBodies.anchor_drift) is a float32 sum of up to 16 bodies
# less a sum of as many slots, divided by the count. The staging's positions lie within 2048 wu
# of the origin, so each sum stays under 16 * 2048 = 32768 wu, where one add rounds by at most
# half an ulp, 2^-10 wu: at most 15 * 2^-10 wu per sum. Each body, set to its slot plus the
# shift, rounds by at most 2^-13 wu more (half an ulp under 2048). Divided by the count of 16
# that is (2 * 15 * 2^-10 + 16 * 2^-13) / 16, about 0.00195 wu, under 0.002 wu.
const OFFSET_TOL := 0.002
# Where the anchor would settle the block, `position` plus the offset, read before and after
# `position` moves: two offsets of OFFSET_TOL each, plus five more roundings under 2048 wu of
# at most 2^-13 wu (the slots' centroid on each side, the moved `position`, and the two sums of
# `position` and offset).
const SETTLE_TOL := 2.0 * OFFSET_TOL + 5.0 / 8192.0

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
	await _assert_switches_anchor_once([EDGE_ROUTER, EDGE_PURSUER], EDGE_SEED)


func test_a_router_whose_men_stand_off_their_slots_switches_anchor_once() -> void:
	await _assert_switches_anchor_once(OFF_SLOT_SCENARIO, OFF_SLOT_SEED)


## Play `scenario` on `seed_value` until uid 0 routs, then watch it for EDGE_WATCH_TICKS: it
## must anchor on its front ranks on every tick in contact until it first leaves contact, and
## then switch to its whole-block anchor exactly once.
func _assert_switches_anchor_once(scenario: Array, seed_value: int) -> void:
	var units: Dictionary = await _start(scenario, seed_value)
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


## Stand every body of `router` on its slot moved by `offset`, so anchoring on any of them
## would settle the block `offset` from its position.
func _stand_bodies_off(router: Unit, offset: Vector2) -> void:
	var slots: PackedVector2Array = router.soldier_world_slots(router.soldiers)
	for i in range(mini(slots.size(), router._sim_soldier_pos.size())):
		router._sim_soldier_pos[i] = slots[i] + offset


func test_a_router_that_has_left_contact_measures_re_entry_from_its_front_rank_anchor() -> void:
	# Whichever anchor couple() reads moves `position`, and the whole-block anchor a router
	# takes on leaving contact can carry it back within the re-entry share of the enemy it
	# left. Re-entry is measured from where the front-rank anchor it would switch to would
	# settle it as well, so the switch cannot undo itself, and from `position` still, so a
	# router back on its front ranks keeps the share's depth inside the full range it leaves at.
	var pair: Array = await _router_and_enemy()
	if pair.is_empty():
		return
	var router: Unit = pair[0]
	var enemy: Unit = pair[1]
	var reach: float = maxf(router.attack_range, enemy.attack_range) + router.RADIUS + enemy.RADIUS
	# Half the range from `position`: inside the re-entry share, so on `position` alone it
	# would anchor in contact again.
	var near: float = 0.5
	assert_lt(near, _frac(router), "setup: the enemy stands inside the re-entry share")
	_place(router, enemy, near)
	assert_false(_place(router, enemy, 1.01), "setup: it leaves contact")
	# Bodies a full range away from the enemy put the front-rank anchor 1 + near ranges from it,
	# past even the full range an enemy fighting the router is measured at.
	_stand_bodies_off(router, Vector2.UP * reach)
	assert_false(_place(router, enemy, near),
			"an enemy near its position but past the range of its front-rank anchor is not anchor contact")
	assert_true(router._in_enemy_contact, "though it is in physical contact")
	assert_false(_anchored(router), "so it stays on its whole-block anchor")
	enemy.state = Unit.State.FIGHTING
	enemy.target_enemy = router
	assert_false(_place(router, enemy, near), "nor is one fighting it")
	enemy.state = Unit.State.MOVING
	enemy.target_enemy = null
	# An enemy inside the full range but outside the share of `position`, with the bodies
	# standing so that the front-rank anchor would settle the router right on it.
	var between: float = (1.0 + _frac(router)) * 0.5
	_stand_bodies_off(router, Vector2.DOWN * reach * between)
	assert_false(_place(router, enemy, between),
			"an enemy on its front-rank anchor but outside the share of its position is not anchor contact")
	assert_true(router._in_enemy_contact, "setup: though it is in physical contact")
	# Bodies `near` ranges toward the enemy put the front-rank anchor on it, where the reverse
	# offset would put it 2 * near ranges off, past the re-entry share.
	assert_gt(2.0 * near, _frac(router), "setup: the reverse offset would leave it outside the share")
	_stand_bodies_off(router, Vector2.DOWN * reach * near)
	assert_true(_place(router, enemy, near), "one at its front-rank anchor brings it back into anchor contact")
	assert_true(_anchored(router), "on its front ranks")


## Unit.contact_anchor_offset, called by name so this file still loads on a tree without it.
func _offset(router: Unit) -> Vector2:
	if not router.has_method("contact_anchor_offset"):
		return Vector2(INF, INF)
	return router.call("contact_anchor_offset")


func test_the_front_rank_anchor_offset_is_measured_from_the_bodies() -> void:
	var pair: Array = await _router_and_enemy()
	if pair.is_empty():
		return
	var router: Unit = pair[0]
	var enemy: Unit = pair[1]
	assert_true(router.has_method("contact_anchor_offset"), "the router measures its front-rank anchor")
	_place(router, enemy, 0.5)
	assert_true(router._in_enemy_contact, "setup: in contact, so it has a front-rank anchor")
	var shift := Vector2(3.0, -7.0)
	_stand_bodies_off(router, shift)
	var offset: Vector2 = _offset(router)
	assert_almost_eq(offset.x, shift.x, OFFSET_TOL, "bodies standing off their slots give the offset (x)")
	assert_almost_eq(offset.y, shift.y, OFFSET_TOL, "and (y)")
	# Moving `position` moves the slots and leaves the bodies, so where the front-rank anchor
	# would settle the block stays put.
	var settled: Vector2 = router.position + offset
	router.position += Vector2(11.0, 5.0)
	var moved: Vector2 = router.position + _offset(router)
	assert_almost_eq(moved.x, settled.x, SETTLE_TOL, "its settling point does not follow position (x)")
	assert_almost_eq(moved.y, settled.y, SETTLE_TOL, "and (y)")
	router._router_front_in_melee = true
	assert_eq(_offset(router), Vector2.ZERO, "none for a router anchored on its whole block either way")
	router._router_front_in_melee = false
	router._sim_soldier_pos.resize(router._sim_soldier_pos.size() - 1)
	assert_eq(_offset(router), Vector2.ZERO, "and none while the grid and the bodies differ in size")


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
	# A router caught again by an enemy fighting it re-enters anchor contact anywhere inside the
	# full range rather than the share, provided its front-rank anchor would settle it inside that
	# range too (the test below covers that half). The share is only for an enemy hovering at the
	# edge without fighting it. Here the bodies stand on their slots, so both points coincide.
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


func test_a_fought_router_off_its_slots_re_enters_only_where_its_front_ranks_stay_in_range() -> void:
	# A router caught from behind whose leading ranks have run ahead of their slots: its
	# front-rank anchor would settle it farther from the pursuer than `position`. An enemy
	# fighting it is measured at the full range from both points, so the router takes its front
	# ranks only where anchoring on them keeps it in range; otherwise it stays on its whole
	# block, while its physical contact still holds.
	var pair: Array = await _router_and_enemy()
	if pair.is_empty():
		return
	var router: Unit = pair[0]
	var enemy: Unit = pair[1]
	var reach: float = maxf(router.attack_range, enemy.attack_range) + router.RADIUS + enemy.RADIUS
	var between: float = (1.0 + _frac(router)) * 0.5
	_place(router, enemy, 0.5)
	assert_false(_place(router, enemy, 1.01), "setup: it leaves contact")
	enemy.state = Unit.State.FIGHTING
	enemy.target_enemy = router
	# Bodies run ahead (away from the enemy) by more than the gap from `between` to the full
	# range put the front-rank anchor past that range.
	var ahead: float = 1.0 - between + 0.05
	_stand_bodies_off(router, Vector2.UP * reach * ahead)
	assert_false(_place(router, enemy, between),
			"an enemy fighting it, whom its front-rank anchor would leave out of range, is not anchor contact")
	assert_true(router._in_enemy_contact, "though it is in physical contact")
	assert_false(_anchored(router), "so it stays on its whole-block anchor")
	# Run ahead by less than that gap, its front-rank anchor stays inside the full range.
	_stand_bodies_off(router, Vector2.UP * reach * (1.0 - between - 0.025))
	assert_true(_place(router, enemy, between),
			"while one its front-rank anchor would keep inside the full range is")
	assert_true(_anchored(router), "on its front ranks")


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
