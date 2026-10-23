extends GutTest
## Which pairings the in-footprint re-face hold covers (Unit._cavalry_inside_foot_footprint):
## only a foot block, archers included, hosting enemy cavalry. Two archer blocks in melee,
## cavalry hosting foot, cavalry hosting cavalry and foot hosting foot all re-face as before,
## turning the slot grid with the heading. The hold itself is covered in
## test_melee_reface_inside_block.gd.

const DT := 1.0 / 60.0
# 39.8 degrees off the block's DOWN heading; each test checks it lies inside the footprint.
const INSIDE_OFFSET := Vector2(-20.0, 24.0)
# As in test_melee_reface_inside_block.gd: float rounding against a turn of tens of degrees.
const SLOT_HOLD_TOL := 0.01


func _make_unit(max_soldiers: int, cavalry: bool, ranged: bool) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.is_cavalry = cavalry
	u.is_ranged = ranged
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


## Re-face a block of the given kind once onto an enemy of the given kind whose centre stands
## at INSIDE_OFFSET, in melee contact, and return how far the farthest slot moved.
func _slot_shift(host_cav: bool, host_ranged: bool, enemy_cav: bool, enemy_ranged: bool) -> float:
	var u := _make_unit(60, host_cav, host_ranged)
	u.uid = 1
	u._in_enemy_contact = true
	var e := _make_unit(20, enemy_cav, enemy_ranged)
	e.uid = 2
	e.team = 1
	e.position = INSIDE_OFFSET
	e.state = Unit.State.FIGHTING
	var local: Vector2 = INSIDE_OFFSET.rotated(-u.soldier_block_world_angle())
	var half: Vector2 = u.soldier_block_half_extents()
	assert_true(absf(local.x) <= half.x and absf(local.y) <= half.y,
		"sanity: the enemy's centre is inside the host's footprint")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._face_for_action(e.position, DT, e)
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var worst := 0.0
	for i in range(before.size()):
		worst = maxf(worst, before[i].distance_to(after[i]))
	return worst


func test_infantry_hosting_cavalry_holds_the_grid() -> void:
	assert_lt(_slot_shift(false, false, true, false), SLOT_HOLD_TOL, "riders inside a foot block hold its grid")


func test_archers_hosting_cavalry_hold_the_grid() -> void:
	assert_lt(_slot_shift(false, true, true, false), SLOT_HOLD_TOL, "archers are a foot block too")


func test_archers_against_archers_turn_the_grid() -> void:
	assert_gt(_slot_shift(false, true, false, true), 100.0 * SLOT_HOLD_TOL,
		"two archer blocks in melee re-face as before")


func test_cavalry_hosting_infantry_turns_the_grid() -> void:
	assert_gt(_slot_shift(true, false, false, false), 100.0 * SLOT_HOLD_TOL,
		"a troop riding through foot keeps its own front to follow")


func test_cavalry_hosting_cavalry_turns_the_grid() -> void:
	assert_gt(_slot_shift(true, false, true, false), 100.0 * SLOT_HOLD_TOL,
		"horse against horse re-faces as before")


func test_infantry_hosting_infantry_turns_the_grid() -> void:
	assert_gt(_slot_shift(false, false, false, false), 100.0 * SLOT_HOLD_TOL,
		"foot against foot re-faces as before")
