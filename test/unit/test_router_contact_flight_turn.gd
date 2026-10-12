extends GutTest
## A router still in enemy contact turns its heading onto its flight direction at the same
## bounded rate as any other flight turn (Unit._turn_flight_toward), so its slot grid never
## swings round under the men in one tick.
##
## The regression this pins: in contact, a flight turn under FACING_SNAP_ABSORB_THRESHOLD
## snapped without being folded into _formation_angle, so the whole grid turned about the
## anchor in one tick and a deep block's corner slots jumped by a chord of its corner radius.
## In the catalog clip trapped_routing the router's mean body-to-slot gap went from 19.8 wu on
## the rout tick to 288.9 wu on the next.

# An 80-mount Cavalry block (a deep block, so a turned grid moves its corners far) with an
# enemy squadron close enough for contact, on the default map clear of its hill.
const ROUTER_START := Vector2(700.0, 1300.0)
const MOUNTS := 80
# The router's heading before the flight turn: 30 degrees off its flight line (team 0 flees
# north), well under the snap-absorb threshold.
const TILT_DEG := 30.0
# Where the enemy stands, relative to the router's anchor: along the tilted heading, inside
# melee contact range of the two anchors.
const ENEMY_OFFSET := 40.0
# Float slack on a slot's position (wu): the grid is rebuilt through float32 facings.
const SLOT_EPS := 0.01   # tuned in wu, solver epsilon

var _battle: Node = null


func after_each() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


## Spawn the router (uid 0) tilted TILT_DEG off north with an enemy squadron in contact ahead
## of it along that heading, and return the router.
func _spawn_in_contact() -> Unit:
	Replay.forced_seed = 12345
	var tilted: Vector2 = Vector2.UP.rotated(deg_to_rad(TILT_DEG))
	var enemy_at: Vector2 = ROUTER_START + tilted * ENEMY_OFFSET
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.scenario = [
		{"team": 0, "type": "Cavalry", "count": MOUNTS, "x": ROUTER_START.x, "y": ROUTER_START.y,
				"facing": [tilted.x, tilted.y]},
		{"team": 1, "type": "Cavalry", "count": MOUNTS, "x": enemy_at.x, "y": enemy_at.y,
				"facing": [-tilted.x, -tilted.y]},
	]
	add_child(_battle)
	await get_tree().physics_frame
	for u in get_tree().get_nodes_in_group("units") + get_tree().get_nodes_in_group("routers"):
		var unit: Unit = u as Unit
		if unit != null and unit.uid == 0:
			return unit
	return null


## The farthest any slot of `after` lies from its slot in `before` carried by `shift` (wu):
## how far the grid turned its slots about the anchor, beyond translating with it.
func _worst_slot_turn(before: PackedVector2Array, after: PackedVector2Array, shift: Vector2) -> float:
	var worst: float = 0.0
	for i in range(mini(before.size(), after.size())):
		worst = maxf(worst, after[i].distance_to(before[i] + shift))
	return worst


func test_a_flight_turn_in_contact_is_bounded() -> void:
	var router: Unit = await _spawn_in_contact()
	assert_not_null(router, "the team-0 cavalry deployed")
	if router == null:
		return
	var flee := Vector2.UP
	var tick: float = 1.0 / float(Engine.physics_ticks_per_second)
	assert_lt(absf(angle_difference(router.facing.angle(), flee.angle())),
			Unit.FACING_SNAP_ABSORB_THRESHOLD,
			"setup: the turn onto the flight line is under the snap-absorb threshold")
	router._in_enemy_contact = true
	var before: PackedVector2Array = router.soldier_world_slots(router.soldiers)
	router._turn_flight_toward(flee, tick)
	assert_gt(absf(angle_difference(router.facing.angle(), flee.angle())), 0.001,
			"in contact the heading turns only part of the way in one tick")
	assert_lte(absf(router._flight_turn_rate), router.bounded_turn_rate(),
			"and no faster than bounded_turn_rate()")
	var after: PackedVector2Array = router.soldier_world_slots(router.soldiers)
	assert_eq(after.size(), before.size(), "setup: the same men before and after")
	# The farthest slot sits at most the block's corner radius from the anchor, so a turn of
	# bounded_turn_rate() for one tick moves it at most jog_speed for one tick.
	assert_lte(_worst_slot_turn(before, after, Vector2.ZERO), router.jog_speed * tick + SLOT_EPS,
			"no slot moves sideways faster than jog_speed")


func test_a_router_breaking_from_contact_keeps_its_slot_grid_on_the_rout_tick() -> void:
	# Through the live rout tick: the flight's first heading, taken while still in contact,
	# turns at a bounded rate, so the grid only carries along with the anchor and turns by no
	# more than the farthest man can follow.
	var router: Unit = await _spawn_in_contact()
	assert_not_null(router, "the team-0 cavalry deployed")
	if router == null:
		return
	var tick: float = 1.0 / float(Engine.physics_ticks_per_second)
	router.rally_morale_threshold = 1000.0
	router.morale = 0.0
	router._rout()
	var heading_before: float = router.facing.angle()
	var anchor_before: Vector2 = router.position
	var men_before: int = router.soldiers
	var before: PackedVector2Array = router.soldier_world_slots(router.soldiers)
	var tick_before: int = _battle.current_tick()
	await get_tree().physics_frame
	assert_eq(_battle.current_tick(), tick_before + 1, "setup: exactly one tick ran")
	assert_eq(router.state, Unit.State.ROUTING, "setup: still routing after the tick")
	assert_true(router._in_enemy_contact, "setup: still in enemy contact on the flight's first tick")
	assert_eq(router.soldiers, men_before, "setup: no casualty reflowed the grid this tick")
	assert_lt(absf(angle_difference(heading_before, Vector2.UP.angle())),
			Unit.FACING_SNAP_ABSORB_THRESHOLD,
			"setup: the flight line is under the snap-absorb threshold off the heading")
	var turned: float = absf(angle_difference(heading_before, router.facing.angle()))
	assert_lte(turned, router.bounded_turn_rate() * tick + 0.000001,
			"the heading turns by at most bounded_turn_rate() for one tick")
	var after: PackedVector2Array = router.soldier_world_slots(router.soldiers)
	assert_lte(_worst_slot_turn(before, after, router.position - anchor_before),
			router.jog_speed * tick + SLOT_EPS,
			"every slot moves with the anchor, turning no faster than jog_speed")
