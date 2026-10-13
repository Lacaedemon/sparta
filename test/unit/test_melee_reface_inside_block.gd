extends GutTest
## A fighting block in enemy contact whose target's centre lies inside its own slot footprint
## holds its facing on a small re-face in _face_for_action: neither the heading nor
## _formation_angle changes, so the slot grid stays where the men stand and nothing is left
## for a later reform to undo. Before, a correction up to ENGAGE_TURN_THRESHOLD (75 degrees)
## turned the whole grid about the anchor unabsorbed, so an enemy among the ranks wound the
## grid round after its bearing tick by tick.
## The footprint's own tunables are covered in test_melee_reface_footprint_config.gd.

const DT := 1.0 / 60.0
# Inside a 60-man block's footprint (sanity-checked in each test that uses it): 39.8 degrees
# off the block's DOWN heading.
const INSIDE_OFFSET := Vector2(-20.0, 24.0)
# Two slot sets computed from the same unit state agree to float rounding, so any slot moving
# more than this has been moved by a facing or fold change. An unabsorbed turn of theta moves
# the farthest slot by 2 * R * sin(theta / 2); _unabsorbed_shift_floor takes half of that, and
# each test checks the floor is at least 100 times this tolerance.
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


## The block under test, in melee contact as the hold requires.
func _make_block() -> Unit:
	var u := _make_unit()
	u.uid = 1
	u._in_enemy_contact = true
	return u


func _make_enemy(pos: Vector2) -> Unit:
	var e := _make_unit(20)
	e.uid = 2
	e.team = 1
	e.position = pos
	e.state = Unit.State.FIGHTING
	return e


func _max_slot_shift(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(a.size()):
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


## Whether `p` lies inside `u`'s slot footprint: the half extents in the grid's own frame.
## Computed here from accessors that predate the change, so the file runs on either side of it.
func _inside_footprint(u: Unit, p: Vector2) -> bool:
	var local: Vector2 = (p - u.position).rotated(-u.soldier_block_world_angle())
	var half: Vector2 = u.soldier_block_half_extents()
	return absf(local.x) <= half.x and absf(local.y) <= half.y


## A lower bound on how far an unabsorbed turn of `theta` moves the farthest slot of `u`:
## half the chord 2 * R * sin(theta / 2) at the block's circumradius R, so the bound holds for
## a block whose farthest slot is anywhere past half that radius.
func _unabsorbed_shift_floor(u: Unit, theta: float) -> float:
	return 0.5 * 2.0 * u.soldier_block_extent() * sin(absf(theta) * 0.5)


func _assert_facing_down(u: Unit, msg: String) -> void:
	assert_almost_eq(u.facing.x, 0.0, FACING_TOL, msg + " (x)")
	assert_almost_eq(u.facing.y, 1.0, FACING_TOL, msg + " (y)")


func test_an_enemy_inside_the_footprint_holds_the_facing_and_the_grid() -> void:
	var u := _make_block()
	var e := _make_enemy(u.position + INSIDE_OFFSET)
	assert_true(_inside_footprint(u, e.position), "sanity: the enemy's centre is inside the footprint")
	assert_gt(_unabsorbed_shift_floor(u, Vector2.DOWN.angle_to(INSIDE_OFFSET)), 100.0 * SLOT_HOLD_TOL,
		"sanity: an unabsorbed turn would move a slot far past the hold tolerance")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_true(u._face_for_action(e.position, DT, e), "the block reports itself faced and fights on")
	_assert_facing_down(u, "the facing holds")
	assert_eq(u._formation_angle, 0.0, "nothing is folded into the grid")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
		"no slot moves in the world")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no turn-in-place is armed")


func test_the_grid_holds_while_an_enemy_works_round_inside_the_block() -> void:
	# The feedback loop the issue measured: the bearing to an enemy among the ranks walks
	# round the anchor in steps far under the snap threshold. 60 one-degree steps stay under
	# ENGAGE_TURN_THRESHOLD off the held facing.
	var u := _make_block()
	var e := _make_enemy(u.position + Vector2(0.0, 30.0))
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for step in range(1, 61):
		e.position = u.position + Vector2(0.0, 30.0).rotated(deg_to_rad(float(step)))
		assert_true(_inside_footprint(u, e.position), "sanity: the walk stays inside the footprint")
		u._face_for_action(e.position, DT, e)
	_assert_facing_down(u, "after 60 one-degree steps the facing is where it started")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
		"after 60 one-degree steps every slot is where it started")


func test_a_bearing_past_the_threshold_still_turns_the_men_in_place() -> void:
	# The hold covers the small snap only: a bearing 120 degrees off the facing arms the
	# turn-in-place, as before.
	var u := _make_block()
	var e := _make_enemy(u.position + Vector2(0.0, 30.0).rotated(deg_to_rad(120.0)))
	assert_true(_inside_footprint(u, e.position), "sanity: the enemy's centre is inside the footprint")
	u._face_for_action(e.position, DT, e)
	assert_ne(u._engage_turn_target, Vector2.ZERO, "a turn-in-place is armed")


func test_an_enemy_just_outside_the_footprint_turns_the_grid_as_before() -> void:
	var u := _make_block()
	var half: Vector2 = u.soldier_block_half_extents()
	# 30 degrees off the heading, at a local depth 5% past the footprint's half-depth; its
	# lateral offset (depth * tan 30) stays inside the half-width, so depth alone puts it out.
	var dist: float = half.y * 1.05 / cos(deg_to_rad(30.0))
	var e := _make_enemy(u.position + Vector2.DOWN.rotated(deg_to_rad(30.0)) * dist)
	assert_false(_inside_footprint(u, e.position), "sanity: the enemy's centre is outside the footprint")
	assert_lt(dist * sin(deg_to_rad(30.0)), half.x, "sanity: only its depth puts it outside")
	assert_lt(dist, u.soldier_block_extent(), "sanity: it is inside the block's circumradius")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(e.position, DT, e)
	assert_eq(u._formation_angle, 0.0, "nothing is folded into the grid")
	assert_gt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)),
		_unabsorbed_shift_floor(u, deg_to_rad(30.0)), "the grid turns with the heading")


func test_out_of_contact_the_grid_turns_as_before() -> void:
	# A large block closing on a target its own footprint already takes in still has a front
	# to bring round: out of enemy contact the snap turns the grid with the heading.
	var u := _make_block()
	u._in_enemy_contact = false
	var e := _make_enemy(u.position + INSIDE_OFFSET)
	assert_true(_inside_footprint(u, e.position), "sanity: the enemy's centre is inside the footprint")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(e.position, DT, e)
	assert_gt(absf(u.facing.angle_to(Vector2.DOWN)), 0.1, "the facing turns onto the enemy")
	assert_gt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)),
		_unabsorbed_shift_floor(u, Vector2.DOWN.angle_to(INSIDE_OFFSET)), "the grid turns with the heading")
