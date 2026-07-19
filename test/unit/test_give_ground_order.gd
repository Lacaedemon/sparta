extends GutTest
## Give ground (Battle.OrderMode.GIVE_GROUND): an explicit player-facing withdrawal
## order. Unlike the passive reach-asymmetric standoff (SoldierMeleeStandoff.
## standoff_bias -- see test_soldier_melee_standoff.gd for the physics-level coverage of
## give_ground_bias and accumulate()'s override/perf-gate behavior), this order carries no
## per-order parameter of its own (unlike KNOCKBACK_FOCUS's knockback_indefinite) -- it's a
## plain stance, so this file covers just the OrderMode plumbing (enum/name/hotkey wiring)
## and Battle._apply_order_cmd's dispatch, mirroring test_knockback_focus_attack.gd's own
## "OrderMode plumbing" section and test_chase_order.gd's registration test.

const BattleScript = preload("res://scripts/Battle.gd")
const SettingsScript = preload("res://scripts/Settings.gd")


func _make_unit(max_soldiers: int = 100) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers, joins "units"
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _battle(units: Array) -> Node:
	var b = BattleScript.new()
	autofree(b)
	for u in units:
		b._by_uid[u.uid] = u
	return b


# --- OrderMode plumbing: mirror constant, name, hotkey slug stay in sync -----------------

func test_order_give_ground_mirrors_battle_order_mode() -> void:
	assert_eq(Unit.ORDER_GIVE_GROUND, BattleScript.OrderMode.GIVE_GROUND,
		"Unit's mirrored int constant matches Battle.OrderMode.GIVE_GROUND")


func test_give_ground_has_a_name_and_a_hotkey_slug() -> void:
	assert_true(BattleScript.ORDER_MODE_NAMES.has(BattleScript.OrderMode.GIVE_GROUND),
		"GIVE_GROUND has a human-readable HUD name")
	var slugs: Array = []
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		slugs.append(entry["slug"])
	assert_true(slugs.has("give_ground"), "GIVE_GROUND has a rebindable hotkey slug")


func test_give_ground_hotkey_default_is_not_reused() -> void:
	var seen: Dictionary = {}
	for slug in SettingsScript.DEFAULT_ORDER_BINDINGS:
		var key: int = SettingsScript.DEFAULT_ORDER_BINDINGS[slug]
		assert_false(seen.has(key),
			"default hotkey %s is already bound to %s" % [key, seen.get(key)])
		seen[key] = slug


func test_give_ground_default_binding_is_backtick() -> void:
	assert_eq(SettingsScript.DEFAULT_ORDER_BINDINGS.get("give_ground"), KEY_QUOTELEFT,
		"give_ground's default hotkey is the backtick key")


# --- Battle._apply_order_cmd: order_mode lands on the unit, plain stance ------------------
# (Mirrors test_knockback_focus_attack.gd's own _battle helper pattern: a Battle exercised
# directly via the script, with units registered by uid, so dispatch is covered without a
# live scene.)

func test_stance_only_order_carries_give_ground_onto_the_unit() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": BattleScript.OrderMode.GIVE_GROUND})
	assert_eq(u.order_mode, Unit.ORDER_GIVE_GROUND,
		"a stance-only GIVE_GROUND order sets the unit's order_mode")


func test_move_order_carries_give_ground_onto_the_unit() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.GIVE_GROUND})
	assert_eq(u.order_mode, Unit.ORDER_GIVE_GROUND,
		"a move/attack order carrying GIVE_GROUND sets order_mode too")


func test_a_fresh_order_without_give_ground_clears_a_prior_give_ground_stance() -> void:
	var u := _make_unit()
	u.uid = 1
	u.order_mode = Unit.ORDER_GIVE_GROUND   # a prior order armed the withdrawal stance
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.order_mode, BattleScript.OrderMode.NORMAL,
		"a fresh NORMAL order replaces the prior GIVE_GROUND stance, same as any other order")
