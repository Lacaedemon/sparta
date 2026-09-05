extends GutTest
## MARCH_TO_CONTACT stance: an advance-to-contact order for a plain move order.
## NORMAL's push-through default (a plain move order with no explicit attack target lets a
## unit auto-acquire and then march straight past a hostile it crosses -- the deliberate
## baseline behavior) stays untouched. MARCH_TO_CONTACT widens the ranged/melee engage
## gates so the SAME plain move order stops the unit to fight anything it meets along the
## way instead, then -- since has_move_target is never cleared -- resumes the queued move
## on its own once the fight ends, exactly the way ORDER_CHASE's held move_target already
## resumes a march once its quarry is gone. Unlike CHASE, MARCH_TO_CONTACT never actively
## pursues a target that breaks contact -- it lets it go and continues toward the original
## destination.

const BattleScript = preload("res://scripts/Battle.gd")
const HUDScript = preload("res://scripts/HUD.gd")


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	# _ready() (runs on add_child) sets soldiers = max_soldiers and joins groups.
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	# Pin Tight: the 30 wu foe offset was authored against close-order contact.
	# The post-fight resume tick budget derives from the formed pivot rate.
	u.set_formation(Unit.FORMATION_TIGHT)
	return u


## Ticks to wait for a resumed march's own formed centre-pivot (Unit._move_to's
## pivot_as_formation) to turn `u` fully onto `u.move_target`'s bearing, plus 0.5 s slack for
## the accel ramp and displacement along the resumed heading. Derived from the same
## formed_turn_tracking_frac-derated rate the production code actually uses, rather than a
## fixed tick count, so the budget tracks that derate instead of guessing a literal.
func _resume_turn_ticks(u: Unit) -> int:
	var turn_rate: float = (u.jog_speed * u.formed_turn_tracking_frac) / u._pivot_radius()
	var dest_heading: float = (u.move_target - u.position).angle()
	var turn_angle: float = absf(angle_difference(u.facing.angle(), dest_heading))
	return ceili((turn_angle / turn_rate + 0.5) * 60.0)


# --- Registration: enum mirror, name, hotkey slug, HUD stance entry ---------

func test_march_to_contact_is_registered_in_order_mode_tables() -> void:
	assert_eq(Unit.ORDER_MARCH_TO_CONTACT, BattleScript.OrderMode.MARCH_TO_CONTACT,
		"Unit's mirror constant matches Battle.OrderMode.MARCH_TO_CONTACT")
	assert_eq(BattleScript.ORDER_MODE_NAMES.get(BattleScript.OrderMode.MARCH_TO_CONTACT), "March to contact",
		"MARCH_TO_CONTACT has a human-readable name")
	var found_slug := false
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		if entry["mode"] == BattleScript.OrderMode.MARCH_TO_CONTACT and entry["slug"] == "march_to_contact":
			found_slug = true
			break
	assert_true(found_slug,
		"MARCH_TO_CONTACT is registered in ORDER_MODE_HOTKEYS with slug 'march_to_contact'")


func test_march_to_contact_has_a_hud_stance_entry() -> void:
	var h := HUDScript.new()
	autofree(h)
	var found := false
	for entry: Dictionary in h._STANCE_ENTRIES:
		if entry["mode"] == BattleScript.OrderMode.MARCH_TO_CONTACT:
			found = true
			assert_eq(entry["slug"], "march_to_contact", "HUD stance entry slug matches the hotkey slug")
			break
	assert_true(found, "MARCH_TO_CONTACT has a row in HUD._STANCE_ENTRIES")


# --- Stop-and-fight: a plain move order stops the unit instead of marching through -----

func test_march_to_contact_unit_in_melee_contact_stops_and_fights_instead_of_marching_through() -> void:
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_MARCH_TO_CONTACT
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(30, 0)   # within melee contact range
	u.has_move_target = true
	u.move_target = Vector2(-200, 0)   # a move order pointing away from the enemy
	u.target_enemy = null              # no explicit attack order: this is a plain move
	var before := u.position
	u._think(0.1)
	assert_eq(u.position, before,
		"a march-to-contact unit stops and fights instead of marching off on a plain move order")
	assert_eq(u.state, Unit.State.FIGHTING, "fighting the auto-acquired foe")
	assert_true(u.has_move_target, "the queued move order is NOT cleared -- it survives the fight")


func test_normal_unit_in_melee_contact_marches_through_the_same_hostile_control() -> void:
	# Contrast for the test above, proving MARCH_TO_CONTACT is actually doing something:
	# the identical setup under NORMAL marches straight past the hostile (the existing
	# push-through default -- see test_chase_order.gd's own equivalent regression guard).
	var u := _make_unit()
	u.team = 0
	# order_mode defaults to NORMAL.
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.has_move_target = true
	u.move_target = Vector2(-200, 0)
	u.target_enemy = null
	var before := u.position
	u._think(0.1)
	assert_ne(u.position, before, "a normal unit pushes through and marches on")


func test_march_to_contact_ranged_unit_stops_to_fire_instead_of_marching_through() -> void:
	var u := _make_unit()
	u.team = 0
	u.is_ranged = true
	u.order_mode = Unit.ORDER_MARCH_TO_CONTACT
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(120, 0)   # inside RANGED_RANGE, outside melee contact
	u.has_move_target = true
	u.move_target = Vector2(-500, 0)
	u.target_enemy = null
	var before := u.position
	u._think(0.1)
	assert_eq(u.position, before,
		"a march-to-contact ranged unit stops to fire instead of marching off")
	assert_eq(u.state, Unit.State.FIGHTING, "fighting (firing on) the auto-acquired foe")
	assert_true(u.has_move_target, "the queued move order is NOT cleared -- it survives the engagement")


func test_normal_ranged_unit_marches_through_the_same_hostile_control() -> void:
	var u := _make_unit()
	u.team = 0
	u.is_ranged = true
	# order_mode defaults to NORMAL.
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(120, 0)
	u.has_move_target = true
	u.move_target = Vector2(-500, 0)
	u.target_enemy = null
	var before := u.position
	u._think(0.1)
	assert_ne(u.position, before, "a normal ranged unit pushes through and marches on")


# --- Resume: the march continues once the fight ends -----------------------

func test_march_to_contact_resumes_the_queued_move_once_the_enemy_is_defeated() -> void:
	# PathField.active is a global static that persists across GUT tests within the same
	# run -- save/restore around any isolated-unit test that reaches _move_to() (per
	# .claude/memories/sparta.md), so this test's result doesn't depend on whichever
	# PathField an earlier test in the same suite run happened to leave active.
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_MARCH_TO_CONTACT
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.has_move_target = true
	u.move_target = Vector2(-500, 0)
	u.target_enemy = null

	# Tick 1: stops and fights, exactly as the test above proves.
	var before := u.position
	u._think(0.1)
	assert_eq(u.position, before, "sanity: still holding and fighting on tick 1")
	assert_eq(u.state, Unit.State.FIGHTING)

	# The enemy is defeated (annihilated in melee).
	enemy.state = Unit.State.DEAD

	# No living enemy is left to fight, so the queued move resumes on its own -- no
	# separate "resume" mechanism is needed, since has_move_target was never cleared.
	# The resume budget derives from the formed pivot rate (governed by
	# formed_turn_tracking_frac) plus time to accelerate and displace along the resumed heading.
	for i in range(_resume_turn_ticks(u)):
		u._think(1.0 / 60.0)
	assert_true(u.has_move_target, "the move order is still live")
	assert_lt(u.position.x, before.x,
		"the unit resumes marching toward its original destination (-x) once the foe is gone")
	PathField.active = old_pf


func test_march_to_contact_lets_a_disengaging_foe_go_rather_than_chasing_it() -> void:
	# Distinguishes MARCH_TO_CONTACT from CHASE: once a foe it stopped to fight breaks
	# contact (retreats out of range) WITHOUT dying, the unit must not give chase -- it
	# should resume its own queued move instead of following the foe's new position.
	# PathField.active save/restore: see the identical note in the resume-on-defeat test above.
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_MARCH_TO_CONTACT
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(30, 0)   # in melee contact
	u.has_move_target = true
	u.move_target = Vector2(-500, 0)
	u.target_enemy = null

	var before := u.position
	u._think(0.1)
	assert_eq(u.position, before, "sanity: holding and fighting on tick 1")

	# The foe disengages: still alive, still detected, but no longer in contact/range.
	enemy.position = Vector2(100, 0)

	for i in range(_resume_turn_ticks(u)):
		u._think(1.0 / 60.0)
	assert_true(u.has_move_target, "the move order is still live")
	assert_lt(u.position.x, before.x,
		"the unit resumes toward its own destination (-x) rather than following the foe (+x)")
	assert_null(u.target_enemy,
		"the auto-acquired foe was never committed, so nothing pulls the unit toward it")
	assert_eq(u._engage_turn_target, Vector2.ZERO,
		"an engage turn armed by the off-axis contact above (facing DOWN, foe at (30,0) is a "
		+ "90-degree bearing) does not stay stranded once the march resumes")
	assert_false(u.is_maneuver_turning(),
		"SoldierBodies.step's slot-approach term is not left frozen behind")
	PathField.active = old_pf


func test_march_to_contact_settles_a_stranded_engage_turn_when_the_foe_disengages_mid_turn() -> void:
	# Regression guard for a bug found by review: the resume path (`if has_move_target:
	# _move_to(...)`) never used to settle an in-progress engage turn -- the ONE branch that
	# does (`elif target_enemy != null or (chasing and not in_contact):`) is unreachable under
	# this stance, since target_enemy deliberately stays null and chasing is false. Left
	# stranded, a nonzero _engage_turn_target permanently freezes SoldierBodies.step's
	# slot-approach term (see the "early return...must settle" lesson in
	# .claude/memories/sparta.md), producing a blob/smear instead of a clean march.
	# PathField.active save/restore: see the identical note on the sibling tests above.
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_MARCH_TO_CONTACT
	var enemy := _make_unit()
	enemy.team = 1
	# A bearing 90 degrees off the unit's DOWN facing -- comfortably past
	# ENGAGE_TURN_THRESHOLD (75 degrees), so this arms a genuine in-place turn rather than
	# the small-offset instant snap.
	enemy.position = Vector2(30, 0)
	u.has_move_target = true
	u.move_target = Vector2(-500, 0)
	u.target_enemy = null

	# One tick engages and begins the turn -- not enough time (at CONVERSIO_TURN_RATE) for a
	# 90-degree swing to finish in a single 0.1s call.
	u._think(0.1)
	assert_eq(u.state, Unit.State.FIGHTING, "sanity: the off-axis contact engaged")
	assert_ne(u._engage_turn_target, Vector2.ZERO, "sanity: an off-axis engage turn armed")
	assert_true(u.is_maneuver_turning(), "sanity: the turn is genuinely still in progress")

	# The foe disengages before the turn completes: still alive, still detected, but no
	# longer in contact/range. MARCH_TO_CONTACT never commits target_enemy, so the only path
	# back to marching is the has_move_target resume branch under test.
	enemy.position = Vector2(100, 0)
	for i in range(60):
		u._think(1.0 / 60.0)

	assert_eq(u._engage_turn_target, Vector2.ZERO,
		"the stranded engage turn is settled once the march resumes, not left stuck forever")
	assert_false(u.is_maneuver_turning(),
		"SoldierBodies.step's slot-approach term is free to run again")
	PathField.active = old_pf
