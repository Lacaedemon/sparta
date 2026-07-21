extends GutTest
## PUSH stance (melee maneuver): an engaged unit presses forward to drive the opponent
## backward through sustained physical pressure (the offensive counterpart to GIVE_GROUND).

const BattleScript = preload("res://scripts/Battle.gd")
const SoldierMeleeStandoffScript = preload("res://scripts/SoldierMeleeStandoff.gd")


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func test_push_bias_points_toward_enemy() -> void:
	var pos := Vector2(10.0, 20.0)
	var enemy_pos := Vector2(50.0, 20.0)
	var bias: Vector2 = SoldierMeleeStandoffScript.push_bias(pos, enemy_pos)
	assert_almost_eq(bias.y, 0.0, 0.001, "no vertical drift when enemy is straight right")
	assert_gt(bias.x, 0.0, "bias points toward the enemy (+x)")
	assert_almost_eq(bias.length(), SoldierMeleeStandoffScript.PUSH_STRENGTH, 0.001,
		"push bias magnitude matches PUSH_STRENGTH")


func test_order_push_mirrors_battle_order_mode() -> void:
	assert_eq(Unit.ORDER_PUSH, BattleScript.OrderMode.PUSH,
		"Unit.ORDER_PUSH mirror constant matches Battle.OrderMode.PUSH")


func test_push_stance_has_a_name_and_a_hotkey_slug() -> void:
	assert_eq(BattleScript.ORDER_MODE_NAMES.get(BattleScript.OrderMode.PUSH), "Push",
		"PUSH stance has a human-readable name")
	var found_slug := false
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		if entry["mode"] == BattleScript.OrderMode.PUSH and entry["slug"] == "push":
			found_slug = true
			break
	assert_true(found_slug, "PUSH stance is registered in ORDER_MODE_HOTKEYS with slug 'push'")
