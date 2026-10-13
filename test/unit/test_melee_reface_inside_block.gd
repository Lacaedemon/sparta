extends GutTest
## A fighting block whose target's centre lies inside its own slot footprint still turns its
## heading onto each small re-face in _face_for_action, but folds the turn into
## _formation_angle, so the slot grid stays where the men stand. Before, a correction up to
## ENGAGE_TURN_THRESHOLD (75 degrees) turned the whole grid about the anchor unabsorbed, so
## an enemy among the ranks wound the grid round after its bearing tick by tick.

const DT := 1.0 / 60.0
# Inside a 60-man block's footprint (sanity-checked in each test that uses it): 39.8 degrees
# off the block's DOWN heading.
const INSIDE_OFFSET := Vector2(-20.0, 24.0)
# Two slot sets computed from the same unit state agree to float rounding, so any slot moving
# more than this has been moved by a facing or fold change. An unabsorbed snap of theta moves
# the farthest slot by 2 * R * sin(theta / 2); for the 39.8-degree INSIDE_OFFSET bearing that
# is about 0.68 * R, tens of world units for a 60-man block (R is checked below), so 0.01 wu
# separates the two by three orders of magnitude. A fold reproduces each slot to float
# rounding.
const SLOT_HOLD_TOL := 0.01
# The heading is written from a normalised direction, so it matches that direction to float
# rounding.
const FACING_TOL := 1e-5


func _make_unit(max_soldiers: int = 60) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
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


## The shift an unabsorbed turn of `theta` gives the farthest slot of `u`, less a margin for
## the slot closest to the anchor being nearer than the extent: half of it.
func _unabsorbed_shift_floor(u: Unit, theta: float) -> float:
	return 0.5 * 2.0 * u.soldier_block_extent() * sin(absf(theta) * 0.5)


func test_an_enemy_inside_the_footprint_turns_the_heading_but_not_the_grid() -> void:
	var u := _make_unit()
	u.uid = 1
	var e := _make_enemy(u.position + INSIDE_OFFSET)
	assert_true(u._enemy_centre_inside_footprint(e), "sanity: the enemy's centre is inside the footprint")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var theta: float = Vector2.DOWN.angle_to(INSIDE_OFFSET)
	assert_gt(_unabsorbed_shift_floor(u, theta), 100.0 * SLOT_HOLD_TOL,
		"sanity: an unabsorbed turn would move a slot far past the hold tolerance")
	assert_true(u._face_for_action(e.position, DT, e), "the block reports itself faced and fights on")
	var want: Vector2 = INSIDE_OFFSET.normalized()
	assert_almost_eq(u.facing.x, want.x, FACING_TOL, "the heading turns onto the enemy (x)")
	assert_almost_eq(u.facing.y, want.y, FACING_TOL, "the heading turns onto the enemy (y)")
	assert_almost_eq(u._formation_angle, -theta, FACING_TOL, "the turn is folded into the grid")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
		"no slot moves in the world")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no turn-in-place is armed")


func test_the_grid_holds_through_an_orbit_of_an_enemy_inside_the_block() -> void:
	# The feedback loop the issue measured: the bearing to an enemy among the ranks walks
	# round the anchor in steps far under the snap threshold.
	var u := _make_unit()
	u.uid = 1
	var e := _make_enemy(u.position + Vector2(0.0, 30.0))
	assert_true(u._enemy_centre_inside_footprint(e), "sanity: the enemy's centre is inside the footprint")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for step in range(1, 91):
		e.position = u.position + Vector2(0.0, 30.0).rotated(deg_to_rad(float(step)))
		u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle_to(Vector2.LEFT), 0.0, FACING_TOL,
		"after a quarter-turn orbit the heading has followed the enemy round")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
		"after a quarter-turn orbit in one-degree steps every slot is where it started")


func test_an_enemy_just_outside_the_footprint_turns_the_grid_as_before() -> void:
	var u := _make_unit()
	u.uid = 1
	var half: Vector2 = u.soldier_block_half_extents()
	# Along the heading, 5% past the footprint's half-depth, 30 degrees off the heading: the
	# point's local depth is the projection on the heading.
	var dist: float = half.y * 1.05 / cos(deg_to_rad(30.0))
	var e := _make_enemy(u.position + Vector2.DOWN.rotated(deg_to_rad(30.0)) * dist)
	assert_false(u._enemy_centre_inside_footprint(e), "sanity: the enemy's centre is outside the footprint")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(e.position, DT, e)
	assert_eq(u._formation_angle, 0.0, "nothing is folded into the grid")
	assert_gt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)),
		_unabsorbed_shift_floor(u, deg_to_rad(30.0)), "the grid turns with the heading")


func test_the_footprint_scale_widens_the_hold() -> void:
	# The same enemy just outside the footprint is held once the scale takes it in.
	var u := _make_unit()
	u.uid = 1
	var half: Vector2 = u.soldier_block_half_extents()
	var dist: float = half.y * 1.05 / cos(deg_to_rad(30.0))
	var e := _make_enemy(u.position + Vector2.DOWN.rotated(deg_to_rad(30.0)) * dist)
	u.melee_reface_hold_footprint_scale = 1.1
	assert_true(u._enemy_centre_inside_footprint(e), "sanity: the scaled footprint takes the enemy in")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(e.position, DT, e)
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), SLOT_HOLD_TOL,
		"a scale of 1.1 holds the grid against an enemy 5% past the footprint's edge")


func test_a_zero_scale_turns_the_hold_off() -> void:
	var u := _make_unit()
	u.uid = 1
	u.melee_reface_hold_footprint_scale = 0.0
	var e := _make_enemy(u.position)
	assert_false(u._enemy_centre_inside_footprint(e), "an enemy on the anchor itself is not held at scale 0")
	e.position = u.position + INSIDE_OFFSET
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(e.position, DT, e)
	assert_gt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)),
		_unabsorbed_shift_floor(u, Vector2.DOWN.angle_to(INSIDE_OFFSET)),
		"with the hold off the grid turns with the heading, as before")


func test_a_far_tier_block_is_not_held() -> void:
	var u := _make_unit()
	u.uid = 1
	var e := _make_enemy(u.position + INSIDE_OFFSET)
	u.tier = FormationTier.FAR
	assert_false(u._enemy_centre_inside_footprint(e), "a far-tier block has no bodies on its slots to hold")


func test_no_target_is_not_inside() -> void:
	var u := _make_unit()
	assert_false(u._enemy_centre_inside_footprint(null), "a re-face with no enemy unit holds nothing")


func test_the_footprint_scale_round_trips_through_a_snapshot() -> void:
	var u := _make_unit()
	u.melee_reface_hold_footprint_scale = 0.5
	var d: Dictionary = u.to_snapshot_dict()
	var restored := Unit.new()
	restored.apply_snapshot_dict(d)
	assert_eq(restored.melee_reface_hold_footprint_scale, 0.5, "the scale survives a replay-seek restore")
	d.erase("melee_reface_hold_footprint_scale")
	var older := Unit.new()
	older.apply_snapshot_dict(d)
	assert_eq(older.melee_reface_hold_footprint_scale, Unit.MELEE_REFACE_HOLD_FOOTPRINT_SCALE,
		"a snapshot from before the field existed restores the default")
	restored.free()
	older.free()
