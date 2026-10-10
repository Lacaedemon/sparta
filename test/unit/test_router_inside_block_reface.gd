extends GutTest
## A fighting block whose target is a ROUTING regiment streaming out through its own ranks
## (the router's centre inside the block's reach, not ahead of the block's anchor along the
## router's own line of flight) holds its facing: _face_for_action neither re-faces nor
## folds anything into _formation_angle, so the slot grid stays where the men stand and a
## later reform has nothing to undo. Before, each tick's small correction (anything up to
## ENGAGE_TURN_THRESHOLD, 75 degrees) rotated the grid unabsorbed, so a router moving among
## the ranks dragged every slot of the block round after its bearing.

const ROUTER_INSIDE_OFFSET := Vector2(-20.0, 24.0)
const DT := 1.0 / 60.0
# Two slot sets computed from the same unit state agree to float rounding, so any slot
# moving more than this has been moved by a facing or fold change. The unabsorbed snap this
# file guards against moves the farthest slot by 2 * R * sin(theta / 2): about 0.68 * R for
# the 39.8-degree bearing ROUTER_INSIDE_OFFSET makes with DOWN, i.e. tens of world units
# for any real block, so 0.01 wu separates the two by three orders of magnitude.
const SLOT_HOLD_TOL := 0.01
# A facing that has not been written reads back bit for bit; this only absorbs the
# normalisation rounding of Vector2.DOWN.
const FACING_TOL := 1e-6


func _make_unit(max_soldiers: int = 60) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _make_router(pos: Vector2, flee: Vector2, router_uid: int = 2) -> Unit:
	var r := _make_unit(20)
	r.uid = router_uid
	r.team = 1
	r.position = pos
	r.state = Unit.State.ROUTING
	r._flee_velocity = flee
	return r


func _max_slot_shift(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(a.size()):
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


func _assert_facing_down(u: Unit, msg: String) -> void:
	assert_almost_eq(u.facing.x, 0.0, FACING_TOL, msg + " (x)")
	assert_almost_eq(u.facing.y, 1.0, FACING_TOL, msg + " (y)")


func test_facing_and_slots_hold_while_a_router_streams_through() -> void:
	var u := _make_unit()
	u.uid = 1
	# Fleeing straight up (-y) while sitting below-left of the anchor (+y): its centre does
	# not lead the anchor along its flight, so it is still passing through the block.
	var r := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, -80.0))
	assert_true(ROUTER_INSIDE_OFFSET.length() < u.soldier_block_extent(),
		"sanity: the router's centre lies inside the block's reach")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var faced: bool = u._face_for_action(r.position, DT, r)
	assert_true(faced, "the block reports itself faced and fights on")
	_assert_facing_down(u, "the facing holds")
	assert_eq(u._formation_angle, 0.0, "nothing is folded into the grid")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
		"no slot moves in the world")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no turn-in-place is armed")


func test_a_router_entering_behind_the_block_arms_no_turn() -> void:
	# A large first offset: the router comes in through the block's rear, 150 degrees off
	# its facing, which the ordinary path answers with a turn-in-place.
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + Vector2(10.0, -18.0), Vector2(0.0, 80.0))
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(30):
		u._face_for_action(r.position, DT, r)
	_assert_facing_down(u, "the facing holds over half a second of the pass")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no turn-in-place is armed")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
		"no slot moves in the world")


func test_slots_hold_through_a_full_orbit_of_a_router_inside_the_block() -> void:
	# The measured catalog case: a router pinned among the ranks orbits the anchor, and
	# each tick's bearing step is far under the 75-degree snap threshold.
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + Vector2(0.0, 30.0), Vector2.ZERO)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for step in range(1, 181):
		r.position = u.position + Vector2(0.0, 30.0).rotated(deg_to_rad(float(step)))
		u._face_for_action(r.position, DT, r)
	_assert_facing_down(u, "after a half-turn orbit the facing is where it started")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
		"after a half-turn orbit in one-degree steps every slot is where it started")


func test_a_reform_after_the_pass_moves_no_slot() -> void:
	# The pass leaves nothing for the next order's reform to undo: reform_ranks drops a
	# folded grid back square, so a fold left by the pass would turn the grid under the men.
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + Vector2(0.0, 30.0), Vector2.ZERO)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for step in range(1, 121):
		r.position = u.position + Vector2(0.0, 30.0).rotated(deg_to_rad(float(step)))
		u._face_for_action(r.position, DT, r)
	r.position = u.position + Vector2(0.0, u.soldier_block_extent() + 50.0)
	u._face_for_action(r.position, DT, r)
	u.reform_ranks()
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
		"after the router has gone and the block reforms, every slot is where it started")


func test_a_router_that_works_past_the_anchor_keeps_the_facing_held() -> void:
	# It entered the block behind the anchor along its flight, then got a few world units
	# past it while still among the ranks: the facing stays held until it leaves the reach.
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, -80.0))
	u._face_for_action(r.position, DT, r)
	r.position = u.position + Vector2(20.0, -12.0)   # now leads the anchor along -y
	u._face_for_action(r.position, DT, r)
	_assert_facing_down(u, "a router already streaming through is not faced once it is past the anchor")
	r.position = u.position + Vector2(0.0, -(u.soldier_block_extent() + 50.0))
	u._face_for_action(r.position, DT, r)
	assert_eq(u._streaming_router_uid, -1, "out of the block's reach, the router is let go")


func test_the_latch_is_let_go_when_the_block_stops_fighting() -> void:
	var u := _make_unit()
	u.uid = 1
	u.state = Unit.State.FIGHTING
	var r := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, -80.0))
	u._face_for_action(r.position, DT, r)
	assert_eq(u._streaming_router_uid, r.uid, "sanity: the pass latched the router")
	u.tick_engaged(DT)
	assert_eq(u._streaming_router_uid, r.uid, "a block still fighting keeps the latch")
	u.state = Unit.State.MOVING   # an order, a march, or the fight simply ending
	u.tick_engaged(DT)
	assert_eq(u._streaming_router_uid, -1, "a block that stops fighting lets the latch go")
	# The same router, met again later ahead of the anchor as a pursuit, is faced as before.
	r._flee_velocity = Vector2(0.0, 80.0)
	u._face_for_action(r.position, DT, r)
	assert_gt(absf(u.facing.angle_to(Vector2.DOWN)), 0.1, "a stale latch does not hold the facing")


func test_a_stance_hold_lets_the_latch_go() -> void:
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, -80.0))
	u._face_for_action(r.position, DT, r)
	assert_eq(u._streaming_router_uid, r.uid, "sanity: the pass latched the router")
	u.order_mode = Unit.ORDER_FLANKING_MANEUVER
	u.state = Unit.State.FIGHTING
	u._face_for_action(r.position, DT, r)
	assert_eq(u._streaming_router_uid, -1, "a stance's own facing hold lets the latch go")


func test_a_second_router_ahead_is_faced_while_the_first_is_latched() -> void:
	var u := _make_unit()
	u.uid = 1
	var a := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, -80.0), 2)
	u._face_for_action(a.position, DT, a)
	assert_eq(u._streaming_router_uid, a.uid, "sanity: router A is latched")
	var b := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, 80.0), 3)
	u._face_for_action(b.position, DT, b)
	assert_gt(absf(u.facing.angle_to(Vector2.DOWN)), 0.1,
		"router B, ridden down from behind, is faced: A's latch does not cover it")


func test_the_streaming_router_round_trips_through_a_snapshot() -> void:
	var u := _make_unit()
	u._streaming_router_uid = 7
	var d: Dictionary = u.to_snapshot_dict()
	var restored := Unit.new()
	restored.apply_snapshot_dict(d)
	assert_eq(restored._streaming_router_uid, 7, "the latch survives a replay-seek restore")
	d.erase("streaming_router_uid")
	var older := Unit.new()
	older.apply_snapshot_dict(d)
	assert_eq(older._streaming_router_uid, -1, "a snapshot from before the field existed holds no router")
	restored.free()
	older.free()


func test_a_router_ridden_down_from_behind_is_faced_as_before() -> void:
	# Pursuit from behind: the router leads the anchor along its own flight. Measured on the
	# rout_rally clip, whose cavalry troop rides inside its quarry's reach (the router's
	# centre 26-64 wu ahead of the anchor, block reach 134 wu) on a steady bearing: holding
	# the facing there too left the router alive past tick 700 instead of dying at 650 and
	# failed the clip's annihilation pin. The ordinary small-offset snap therefore applies.
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, 80.0))
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(r.position, DT, r)
	assert_gt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), 1.0, "the grid turns with the facing")


func test_router_outside_the_block_reach_is_faced_as_before() -> void:
	var u := _make_unit()
	u.uid = 1
	var far: Vector2 = ROUTER_INSIDE_OFFSET.normalized() * (u.soldier_block_extent() + 50.0)
	var r := _make_router(u.position + far, Vector2(0.0, -80.0))
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(r.position, DT, r)
	assert_gt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), 1.0,
		"a router beyond the block's reach is faced as before")


func test_a_standing_enemy_inside_the_block_is_faced_as_before() -> void:
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, -80.0))
	r.state = Unit.State.FIGHTING
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(r.position, DT, r)
	assert_gt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), 1.0,
		"only a ROUTING target holds the facing")
