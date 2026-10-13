extends GutTest
## The footprint a combat re-face holds the slot grid inside (Unit._enemy_centre_inside_footprint):
## its caller-configurable scale, the cases it leaves out, and its snapshot round trip. The hold
## itself is covered in test_melee_reface_inside_block.gd.

const DT := 1.0 / 60.0
# Inside a 60-man block's footprint at the default scale.
const INSIDE_OFFSET := Vector2(-20.0, 24.0)
# As in test_melee_reface_inside_block.gd: float rounding against a turn of tens of degrees.
const SLOT_HOLD_TOL := 0.01


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


## Half the chord an unabsorbed turn of `theta` moves a slot at the block's circumradius.
func _unabsorbed_shift_floor(u: Unit, theta: float) -> float:
	return 0.5 * 2.0 * u.soldier_block_extent() * sin(absf(theta) * 0.5)


func test_the_default_scale_is_the_footprint_itself() -> void:
	assert_eq(Unit.MELEE_REFACE_HOLD_FOOTPRINT_SCALE, 1.0, "the default holds against the footprint itself")
	var u := _make_unit()
	assert_eq(u.melee_reface_hold_footprint_scale, Unit.MELEE_REFACE_HOLD_FOOTPRINT_SCALE,
		"a new unit runs on the default")


func test_the_footprint_scale_widens_the_hold() -> void:
	# An enemy 30 degrees off the heading at 5% past the footprint's half-depth is outside at
	# the default scale and inside at 1.1, so the grid holds only once the scale takes it in.
	var u := _make_unit()
	u.uid = 1
	var half: Vector2 = u.soldier_block_half_extents()
	var dist: float = half.y * 1.05 / cos(deg_to_rad(30.0))
	var e := _make_enemy(u.position + Vector2.DOWN.rotated(deg_to_rad(30.0)) * dist)
	assert_false(u._enemy_centre_inside_footprint(e), "sanity: outside at the default scale")
	u.melee_reface_hold_footprint_scale = 1.1
	assert_true(u._enemy_centre_inside_footprint(e), "the scaled footprint takes the enemy in")
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


func test_a_routing_enemy_is_left_to_the_router_rules() -> void:
	var u := _make_unit()
	u.uid = 1
	var e := _make_enemy(u.position + INSIDE_OFFSET)
	assert_true(u._enemy_centre_inside_footprint(e), "sanity: a standing enemy there is held")
	e.state = Unit.State.ROUTING
	assert_false(u._enemy_centre_inside_footprint(e), "a router there is not")


func test_a_far_tier_block_is_not_held() -> void:
	var u := _make_unit()
	u.uid = 1
	var e := _make_enemy(u.position + INSIDE_OFFSET)
	assert_true(u._enemy_centre_inside_footprint(e), "sanity: a close-tier block is held")
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
