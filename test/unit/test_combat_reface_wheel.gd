extends GutTest
## A fighting block in enemy contact that re-faces by a small correction (up to
## ENGAGE_TURN_THRESHOLD) wheels its heading onto the enemy at a bounded rate instead of
## snapping it there in one tick. The slot grid is laid out from the heading, so a snap turned
## the whole grid about the anchor at once: a deep block's corner slot moved its radius times the
## turn in a single tick while the men, held in the press, stayed where they stood. A correction
## within combat_reface_snap_turn (a few degrees) still snaps, and so does every correction out
## of contact, on a far-tier block, and on riders inside a foot block (which folds the turn into
## the grid instead: test_melee_reface_inside_block.gd).

const DT := 1.0 / 60.0
const FACING_TOL := 1e-5
# Float slack on a slot's sweep against the bound it must stay under.
const SWEEP_TOL := 1e-3


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


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


## A point `deg` degrees off the block's DOWN heading, far outside its footprint.
func _bearing_point(deg: float) -> Vector2:
	return Vector2.DOWN.rotated(deg_to_rad(deg)) * 2000.0


func _max_slot_shift(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(a.size()):
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


func test_a_small_reface_in_contact_wheels_the_heading_at_the_bounded_rate() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(30.0))
	var rate: float = u.bounded_turn_rate()
	assert_lt(rate * DT, deg_to_rad(30.0), "sanity: one tick of the bound is far short of the turn")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_true(u._face_for_action(e.position, DT, e), "the block reports itself faced and fights on")
	assert_almost_eq(absf(Vector2.DOWN.angle_to(u.facing)), rate * DT, FACING_TOL,
		"the heading turns one tick of the bounded rate toward the enemy")
	assert_gt(Vector2.DOWN.angle_to(u.facing) * deg_to_rad(30.0), 0.0, "and it turns toward him")
	assert_lt(_max_slot_shift(before, u.soldier_world_slots(u.soldiers)), u.jog_speed * DT + SWEEP_TOL,
		"no slot sweeps faster than the men can jog")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no turn-in-place is armed")
	assert_eq(u._formation_angle, 0.0, "nothing is folded into the grid")


func test_the_wheel_reaches_the_enemy_and_then_holds_on_him() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(30.0))
	var ticks: int = int(ceil(deg_to_rad(30.0) / (u.bounded_turn_rate() * DT))) + 2
	for i in range(ticks):
		u._is_facing_turning = false   # cleared at the top of every tick
		u._facing_turn_step = 0.0
		u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"the heading comes onto the enemy")


func test_a_correction_within_the_snap_turn_still_snaps() -> void:
	var u := _make_block()
	var turn: float = 0.9 * u.combat_reface_snap_turn
	assert_gt(turn, u.bounded_turn_rate() * DT,
		"sanity: the correction is past one tick of the bounded rate")
	var e := _make_enemy(_bearing_point(rad_to_deg(turn)))
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"a correction within combat_reface_snap_turn snaps at once")


func test_the_snap_turn_is_configurable() -> void:
	var u := _make_block()
	u.combat_reface_snap_turn = deg_to_rad(40.0)
	var e := _make_enemy(_bearing_point(30.0))
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"a correction within a raised snap turn snaps at once")


func test_a_small_reface_out_of_contact_still_snaps() -> void:
	var u := _make_block()
	u._in_enemy_contact = false
	var e := _make_enemy(_bearing_point(30.0))
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"out of contact the re-face snaps as before")


func test_a_far_tier_block_still_snaps() -> void:
	var u := _make_block()
	u.tier = FormationTier.FAR
	var e := _make_enemy(_bearing_point(30.0))
	u._face_for_action(e.position, DT, e)
	assert_almost_eq(u.facing.angle(), (e.position - u.position).angle(), FACING_TOL,
		"a far-tier block has no bodies on its slots, so it snaps")


func test_a_large_offset_still_turns_in_place() -> void:
	var u := _make_block()
	var e := _make_enemy(_bearing_point(120.0))
	assert_false(u._face_for_action(e.position, DT, e), "the strike waits while the block turns")
	assert_ne(u._engage_turn_target, Vector2.ZERO, "a turn-in-place is armed, as before")
