extends GutTest
## A fighting block whose target is a ROUTING regiment streaming out through its own ranks
## (the router's centre inside the block's reach, not yet ahead of the block's anchor along
## the router's own line of flight) keeps its slot grid where it stands while its facing
## follows the router: _face_for_action folds the whole turn into _formation_angle, as a
## large snap already does. Before, each tick's small correction (anything up to
## ENGAGE_TURN_THRESHOLD, 75 degrees) rotated the grid unabsorbed, so a router circling
## the anchor dragged every slot of a deep block around with it while the men, held in
## contact, stayed where they were.

const ROUTER_INSIDE_OFFSET := Vector2(-20.0, 24.0)
# Two slot sets computed from the same unit state agree to float rounding, so any slot
# moving more than this has been moved by the facing change. The unabsorbed snap this file
# guards against moves the farthest slot by 2 * R * sin(theta / 2): about 0.68 * R for the
# 39.8-degree bearing ROUTER_INSIDE_OFFSET makes with DOWN, i.e. tens of world units for
# any real block, so 0.01 wu separates the two by three orders of magnitude.
const SLOT_HOLD_TOL := 0.01


func _make_unit(max_soldiers: int = 60) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _make_router(pos: Vector2, flee: Vector2) -> Unit:
	var r := _make_unit(20)
	r.uid = 2
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


func test_slots_hold_in_place_while_facing_follows_a_router_streaming_through() -> void:
	var u := _make_unit()
	u.uid = 1
	# Fleeing straight up (-y) while sitting below-left of the anchor (+y): its centre does
	# not lead the anchor along its flight, so it is still passing through the block.
	var r := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, -80.0))
	assert_true(ROUTER_INSIDE_OFFSET.length() < u.soldier_block_extent(),
		"sanity: the router's centre lies inside the block's reach")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var faced: bool = u._face_for_action(r.position, 1.0 / 60.0, r)
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_true(faced, "the block reports itself faced and fights on")
	var want: Vector2 = ROUTER_INSIDE_OFFSET.normalized()
	assert_almost_eq(u.facing.x, want.x, 1e-5, "facing follows the router's bearing (x)")
	assert_almost_eq(u.facing.y, want.y, 1e-5, "facing follows the router's bearing (y)")
	assert_lt(_max_slot_shift(before, after), SLOT_HOLD_TOL,
		"no slot moves in the world: the turn is folded into _formation_angle")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no turn-in-place is armed")


func test_slots_hold_through_a_full_orbit_of_a_router_inside_the_block() -> void:
	# The measured catalog case: a router pinned among the ranks orbits the anchor, and
	# each tick's bearing step is far under the 75-degree snap threshold.
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + Vector2(0.0, 30.0), Vector2.ZERO)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for step in range(1, 181):
		var ang: float = deg_to_rad(float(step))
		r.position = u.position + Vector2(0.0, 30.0).rotated(ang)
		u._face_for_action(r.position, 1.0 / 60.0, r)
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_lt(_max_slot_shift(before, after), SLOT_HOLD_TOL,
		"after a half-turn orbit in one-degree steps every slot is where it started")


func test_a_router_that_works_past_the_anchor_keeps_the_grid_held() -> void:
	# It entered the block behind the anchor along its flight, then got a few world units
	# past it while still among the ranks: the turn stays folded until it leaves the reach.
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, -80.0))
	u._face_for_action(r.position, 1.0 / 60.0, r)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	r.position = u.position + Vector2(20.0, -12.0)   # now leads the anchor along -y
	u._face_for_action(r.position, 1.0 / 60.0, r)
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
		"a router already streaming through is not faced the ordinary way once it is past the anchor")
	r.position = u.position + Vector2(0.0, -(u.soldier_block_extent() + 50.0))
	u._face_for_action(r.position, 1.0 / 60.0, r)
	assert_eq(u._streaming_router_uid, -1, "out of the block's reach, the router is let go")


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


func test_router_ahead_along_its_flight_still_turns_the_grid() -> void:
	# Riding a router down from behind: it leads the anchor along its own flight, so the
	# ordinary small-offset snap applies and the grid turns with the facing.
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, 80.0))
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(r.position, 1.0 / 60.0, r)
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_gt(_max_slot_shift(before, after), 1.0, "the grid turns with the facing")


func test_router_outside_the_block_reach_still_turns_the_grid() -> void:
	var u := _make_unit()
	u.uid = 1
	var far: Vector2 = ROUTER_INSIDE_OFFSET.normalized() * (u.soldier_block_extent() + 50.0)
	var r := _make_router(u.position + far, Vector2(0.0, -80.0))
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(r.position, 1.0 / 60.0, r)
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_gt(_max_slot_shift(before, after), 1.0, "a router beyond the block's reach is faced as before")


func test_a_standing_enemy_inside_the_block_still_turns_the_grid() -> void:
	var u := _make_unit()
	u.uid = 1
	var r := _make_router(u.position + ROUTER_INSIDE_OFFSET, Vector2(0.0, -80.0))
	r.state = Unit.State.FIGHTING
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(r.position, 1.0 / 60.0, r)
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_gt(_max_slot_shift(before, after), 1.0, "only a ROUTING target takes the folded turn")
