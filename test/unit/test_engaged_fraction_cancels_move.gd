extends GutTest
## Auto-cancel a unit's pending MOVE order once ~10% of its soldiers engage in
## melee, instead of the old pause-then-resume-on-disengage behavior around
## Unit.is_engaged()'s binary FIGHTING latch. Covers the issue-site wiring in
## Battle._apply_order_cmd's two Order.new_move call sites (a fresh plain move, and an
## appended waypoint leg): a NORMAL-stance plain move gets Order.Guard.ENGAGED_FRACTION_ABOVE
## attached automatically; HOLD/CHASE/MARCH_TO_CONTACT and an explicit ATTACK order (already a
## committed decision to fight -- see Battle.ENGAGED_FRACTION_CANCELS_MOVE's own doc comment)
## do not. The guard's own value semantics (the fraction math, and _update_current_order's
## early-retirement mechanics) are covered separately by test_order_guards.gd and
## test_orders_queue.gd; this file only covers whether the guard gets attached at all.
## Mirrors test_give_ground_order.gd's own "Battle._apply_order_cmd" section: a Battle
## exercised directly via the script, units registered by uid, no live scene needed.

const BattleScript = preload("res://scripts/Battle.gd")


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


# --- A plain NORMAL move gets the guard --------------------------------------------------

func test_a_plain_normal_move_is_issued_with_the_engaged_fraction_guard() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.current_order.type, Order.Type.MOVE)
	assert_eq(u.current_order.guard, Order.Guard.ENGAGED_FRACTION_ABOVE)
	assert_eq(u.current_order.guard_param, BattleScript.ENGAGED_FRACTION_CANCELS_MOVE)


func test_an_appended_waypoint_leg_also_carries_the_engaged_fraction_guard() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0,
		"target": BattleScript.ORDER_APPEND_WAYPOINT, "mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.current_order.type, Order.Type.MOVE)
	assert_eq(u.current_order.guard, Order.Guard.ENGAGED_FRACTION_ABOVE)
	assert_eq(u.current_order.guard_param, BattleScript.ENGAGED_FRACTION_CANCELS_MOVE)


# --- Already-committed stances keep their own behavior, no auto-cancel guard -------------

func test_a_hold_stance_move_does_not_get_the_engaged_fraction_guard() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.HOLD})
	assert_eq(u.current_order.type, Order.Type.MOVE)
	assert_eq(u.current_order.guard, Order.Guard.NONE,
		"HOLD is an already-committed stance -- it keeps its own behavior, not the auto-cancel")


func test_a_chase_stance_move_does_not_get_the_engaged_fraction_guard() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.CHASE})
	assert_eq(u.current_order.guard, Order.Guard.NONE,
		"CHASE never lets go of its quarry -- the auto-cancel default would fight that")


func test_a_march_to_contact_move_does_not_get_the_engaged_fraction_guard() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.MARCH_TO_CONTACT})
	assert_eq(u.current_order.guard, Order.Guard.NONE,
		"MARCH_TO_CONTACT already has its own stop/resume contract around a plain move")


# --- An explicit attack target is never a guarded plain move -----------------------------

func test_an_explicit_attack_order_is_unaffected() -> void:
	var u := _make_unit()
	u.uid = 1
	var enemy := _make_unit()
	enemy.uid = 2
	enemy.team = 1
	var b := _battle([u, enemy])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0, "target": 2,
		"mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.current_order.type, Order.Type.ATTACK,
		"an explicit attack target makes this an ATTACK order, never a guarded plain move")
	assert_eq(u.current_order.guard, Order.Guard.NONE)
