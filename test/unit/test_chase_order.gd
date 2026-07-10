extends GutTest
## CHASE attack order mode: relentless pursuit. A CHASE unit does not take the
## normal "plain move order with no explicit target = disengage" exit that lets a
## unit break contact/pursuit — it keeps re-closing on and re-engaging the SAME
## fleeing/repositioning enemy across ticks instead.

const BattleScript = preload("res://scripts/Battle.gd")


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	# _ready() (runs on add_child) sets soldiers = max_soldiers and joins groups.
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func test_chase_unit_in_contact_ignores_a_plain_move_order() -> void:
	# Contrast with test_unit.gd's test_fighting_unit_executes_disengage_order_...:
	# a plain move order (target_enemy cleared) normally lets a FIGHTING unit break
	# contact and march off. A CHASE unit must not take that exit.
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_CHASE
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(30, 0)   # within melee contact range
	u.state = Unit.State.FIGHTING
	u.has_move_target = true
	u.move_target = Vector2(-200, 0)   # a move order pointing away from the enemy
	u.target_enemy = null              # no explicit attack order: this is a plain move
	var before := u.position
	u._think(0.1)
	assert_eq(u.position, before,
		"a chasing unit holds and fights instead of marching off on a plain move order")
	assert_eq(u.state, Unit.State.FIGHTING, "still fighting the same foe")


func test_normal_unit_in_contact_disengages_on_a_plain_move_order() -> void:
	# Regression guard: proves the CHASE override above is actually doing something —
	# the same setup under NORMAL order_mode disengages, matching existing behaviour.
	var u := _make_unit()
	u.team = 0
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.state = Unit.State.FIGHTING
	u.has_move_target = true
	u.move_target = Vector2(-200, 0)
	u.target_enemy = null
	var before := u.position
	u._think(0.1)
	assert_ne(u.position, before, "a normal unit obeys the disengage move order")


func test_chase_unit_pursues_past_a_move_order_when_not_yet_in_contact() -> void:
	# Not yet in contact, no explicit target_enemy (auto-acquired only), and a move
	# order pointing elsewhere: a chasing unit still closes on the enemy rather than
	# marching to the ordered destination.
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_CHASE
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(100, 0)   # inside DETECTION_RANGE, out of melee contact
	u.has_move_target = true
	u.move_target = Vector2(-200, 0)
	u.target_enemy = null
	u._think(0.1)
	assert_gt(u.position.x, 0.0, "the chaser closes toward the enemy (+x), not the move order (-x)")


func test_normal_unit_obeys_move_order_over_an_auto_acquired_enemy() -> void:
	# Regression guard for the case above: NORMAL obeys the move order instead.
	var u := _make_unit()
	u.team = 0
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(100, 0)
	u.has_move_target = true
	u.move_target = Vector2(-200, 0)
	u.target_enemy = null
	u._think(0.1)
	assert_lt(u.position.x, 0.0, "a normal unit marches to its ordered destination instead")


func test_chase_unit_keeps_retargeting_a_fleeing_enemy_across_ticks() -> void:
	# Acceptance criterion from the issue: a chasing unit keeps re-targeting/re-closing
	# on the same fleeing/repositioning enemy across several physics ticks, rather than
	# breaking off. The enemy steps away each tick (simulating a routing/repositioning
	# foe); the chaser must keep shrinking the gap the whole time.
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_CHASE
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(150, 0)
	u.target_enemy = enemy   # an explicit chase order names its quarry

	var prev_dist: float = u.position.distance_to(enemy.position)
	for i in range(10):
		# The quarry keeps repositioning away, as a fleeing/routing enemy would.
		enemy.position += Vector2(40, 0)
		u._think(1.0 / 60.0)
		var dist: float = u.position.distance_to(enemy.position)
		assert_eq(u.target_enemy, enemy,
			"tick %d: the chaser never lets go of its quarry" % i)
		assert_true(dist <= prev_dist + 40.0 + 0.01,
			"tick %d: the chaser keeps closing rather than falling further behind" % i)
		prev_dist = dist


func test_chase_is_registered_in_order_mode_tables() -> void:
	# Guard the wiring across the enum/name/hotkey tables the way other stances are.
	assert_true(BattleScript.ORDER_MODE_NAMES.has(BattleScript.OrderMode.CHASE),
		"CHASE has a display name")
	var hotkey_modes: Array = []
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		hotkey_modes.append(entry["mode"])
	assert_true(hotkey_modes.has(BattleScript.OrderMode.CHASE),
		"CHASE is a rebindable hotkey entry")
	assert_eq(Unit.ORDER_CHASE, BattleScript.OrderMode.CHASE,
		"Unit's mirror constant matches Battle.OrderMode.CHASE")
