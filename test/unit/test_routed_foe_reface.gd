extends GutTest
## A unit fighting a ROUTING enemy turns its front onto it only while it follows the rout: horse
## riding it down (SoldierPursuitStep.is_pursuing) or a block whose target it is. Any other unit
## keeps its heading and fights on: a router's position is the centre of men running each his
## own way, which can stand among the block's ranks, where a bearing to it names no front.

const DT := 1.0 / 60.0
# Two slot sets computed from the same unit state agree to float rounding; the snap this file
# guards against moves the farthest slot by tens of world units.
const SLOT_HOLD_TOL := 0.01
# A facing that has not been written reads back bit for bit, up to the normalisation of DOWN.
const FACING_TOL := 1e-6
# The router's centre: inside the block, 39.8 degrees off its facing (under the 75-degree
# turn-in-place threshold, so the ordinary path would snap onto it).
const ROUTER_OFFSET := Vector2(-20.0, 24.0)


func _make_unit(max_soldiers: int, uid: int, team: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.uid = uid
	u.team = team
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _router(pos: Vector2) -> Unit:
	var r := _make_unit(20, 2, 1)
	r.position = pos
	r.state = Unit.State.ROUTING
	return r


func _max_slot_shift(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(a.size()):
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


func test_a_block_not_following_the_rout_keeps_its_heading() -> void:
	var u := _make_unit(60, 1, 0)
	var r := _router(ROUTER_OFFSET)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(30):
		r.position = ROUTER_OFFSET.rotated(deg_to_rad(float(i)))
		assert_true(u._face_for_action(r.position, DT, r), "the block reports itself faced")
	assert_almost_eq(u.facing.x, 0.0, FACING_TOL, "the facing holds (x)")
	assert_almost_eq(u.facing.y, 1.0, FACING_TOL, "the facing holds (y)")
	assert_eq(u._formation_angle, 0.0, "nothing is folded into the grid")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no turn-in-place is armed")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
			"no slot moves in the world")


func test_a_block_whose_target_is_the_router_turns_onto_it() -> void:
	var u := _make_unit(60, 1, 0)
	var r := _router(ROUTER_OFFSET)
	u.target_enemy = r
	u._face_for_action(r.position, DT, r)
	assert_almost_eq(u.facing.angle_to(ROUTER_OFFSET), 0.0, 0.001,
			"a block following the rout turns its front onto the router")


func test_horse_riding_the_rout_down_turns_onto_it() -> void:
	var u := _make_unit(20, 1, 0)
	u.is_cavalry = true
	u.state = Unit.State.FIGHTING
	var r := _router(ROUTER_OFFSET)
	u._sim_chase_dir.resize(u.soldiers)
	u._sim_chase_dir[0] = Vector2.RIGHT   # one rider rides at a routed man he sees
	assert_true(SoldierPursuitStep.is_pursuing(u), "sanity: the troop rides the rout down")
	u._face_for_action(r.position, DT, r)
	assert_almost_eq(u.facing.angle_to(ROUTER_OFFSET), 0.0, 0.001,
			"horse riding the rout down turns its front onto the router")


func test_a_rider_with_no_routed_man_in_sight_keeps_the_heading() -> void:
	var u := _make_unit(20, 1, 0)
	u.is_cavalry = true
	u.state = Unit.State.FIGHTING
	var r := _router(ROUTER_OFFSET)
	u._sim_chase_dir.resize(u.soldiers)   # every rider's way ZERO: none rides at a routed man
	u._face_for_action(r.position, DT, r)
	assert_almost_eq(u.facing.y, 1.0, FACING_TOL, "a troop not riding the rout down holds")
