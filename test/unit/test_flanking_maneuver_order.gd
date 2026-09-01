extends GutTest
## FLANKING_MANEUVER stance (melee maneuver): an engaged unit expands its frontage beyond
## the opposing enemy's frontage to wrap around the enemy flanks, holding its line facing
## while the outer wings envelop the foe.

const BattleScript = preload("res://scripts/Battle.gd")
const SEED: int = 12345


func before_each() -> void:
	Replay.rng.seed = SEED


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _make_engaged_unit(max_soldiers: int, pos: Vector2, face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)
	u.position = pos
	u.facing = face
	u.set_formation(Unit.FORMATION_TIGHT)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	u.seed_sim_soldiers()
	return u


# --- Registration: enum mirror, name, hotkey slug ---------------------------

func test_order_flanking_maneuver_mirrors_battle_order_mode() -> void:
	assert_eq(Unit.ORDER_FLANKING_MANEUVER, BattleScript.OrderMode.FLANKING_MANEUVER,
		"Unit.ORDER_FLANKING_MANEUVER mirror constant matches Battle.OrderMode.FLANKING_MANEUVER")


func test_flanking_maneuver_stance_has_a_name_and_a_hotkey_slug() -> void:
	assert_eq(BattleScript.ORDER_MODE_NAMES.get(BattleScript.OrderMode.FLANKING_MANEUVER), "Flanking maneuver",
		"FLANKING_MANEUVER stance has a human-readable name")
	var found_slug := false
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		if entry["mode"] == BattleScript.OrderMode.FLANKING_MANEUVER and entry["slug"] == "flanking_maneuver":
			found_slug = true
			break
	assert_true(found_slug,
		"FLANKING_MANEUVER stance is registered in ORDER_MODE_HOTKEYS with slug 'flanking_maneuver'")


# --- Arm-then-issue plumbing (Battle._apply_order_cmd) -----------------------

func test_stance_only_order_carries_flanking_maneuver_onto_the_unit() -> void:
	var u := _make_unit()
	u.uid = 1
	var b = BattleScript.new()
	autofree(b)
	b._by_uid[1] = u
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": BattleScript.OrderMode.FLANKING_MANEUVER})
	assert_eq(u.order_mode, Unit.ORDER_FLANKING_MANEUVER, "a stance-only order sets order_mode")


func test_move_order_carries_flanking_maneuver_onto_the_unit() -> void:
	var u := _make_unit()
	u.uid = 1
	var b = BattleScript.new()
	autofree(b)
	b._by_uid[1] = u
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.FLANKING_MANEUVER})
	assert_eq(u.order_mode, Unit.ORDER_FLANKING_MANEUVER, "a move/attack order carrying the stance sets order_mode")


func test_fresh_order_clears_prior_flanking_maneuver_stance() -> void:
	var u := _make_unit()
	u.uid = 1
	u.order_mode = Unit.ORDER_FLANKING_MANEUVER
	var b = BattleScript.new()
	autofree(b)
	b._by_uid[1] = u
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.order_mode, BattleScript.OrderMode.NORMAL, "NORMAL order clears the prior stance")


# --- Facing hold in _face_for_action -----------------------------------------

func test_face_for_action_holds_facing_under_flanking_maneuver_while_engaged() -> void:
	var u := _make_unit()
	u.uid = 1
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	u.order_mode = Unit.ORDER_FLANKING_MANEUVER
	var enemy := _make_unit()
	enemy.uid = 2
	enemy.team = 1
	var far_point := Vector2(500.0, 0.0)
	var faced: bool = u._face_for_action(far_point, 0.1, enemy)
	assert_true(faced, "FLANKING_MANEUVER reports itself as faced while engaged")
	assert_eq(u.facing, Vector2.DOWN, "and its facing holds instead of turning off-axis")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no engage turn is armed by the held-facing path")


func test_face_for_action_settles_an_in_progress_turn_when_flanking_maneuver_takes_over_mid_turn() -> void:
	var u := _make_unit()
	u.uid = 1
	u._engage_turn_target = Vector2.RIGHT
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	u.order_mode = Unit.ORDER_FLANKING_MANEUVER
	var faced: bool = u._face_for_action(Vector2(500.0, 0.0), 0.1)
	assert_true(faced, "FLANKING_MANEUVER reports itself as faced")
	assert_eq(u._engage_turn_target, Vector2.ZERO,
		"picking up FLANKING_MANEUVER mid-turn settles the in-progress engage turn")


func test_face_for_action_does_not_hold_facing_outside_fighting_state_even_if_linger_active() -> void:
	var u := _make_unit()
	u.uid = 1
	u.state = Unit.State.MOVING
	u.tick_engaged(0.1) # linger timer is active
	u.order_mode = Unit.ORDER_FLANKING_MANEUVER
	var far_point := Vector2(500.0, 0.0)
	var faced: bool = u._face_for_action(far_point, 0.1)
	assert_false(faced, "not fighting: facing is not held and turn is armed")
	assert_ne(u._engage_turn_target, Vector2.ZERO, "engage turn target is armed for movement")


# --- Frontage reflow in _flanking_maneuver_reflow ----------------------------

func test_flanking_maneuver_reflow_widens_frontage_beyond_enemy_frontage() -> void:
	var u := _make_unit(100)
	u.set_frontage(8)
	u._last_reshape_tick = -1
	var enemy := _make_unit(60)
	enemy.set_frontage(10)
	assert_eq(enemy.formation_files(enemy.soldiers), 10)

	u._flanking_maneuver_reflow(enemy)
	assert_eq(UnitFormation.frontage(u), 14,
		"FLANKING_MANEUVER expands frontage beyond enemy frontage to wrap wings")


func test_flanking_maneuver_reflow_clamps_to_unit_soldier_count() -> void:
	var u := _make_unit(12)
	u.set_frontage(4)
	u._last_reshape_tick = -1
	var enemy := _make_unit(60)
	enemy.set_frontage(10)

	u._flanking_maneuver_reflow(enemy)
	assert_eq(UnitFormation.frontage(u), 12,
		"FLANKING_MANEUVER target files clamps to available soldiers")


func test_flanking_maneuver_reflow_respects_hysteresis() -> void:
	var u := _make_unit(100)
	u.set_frontage(14)
	u._last_reshape_tick = -1
	var enemy := _make_unit(60)
	enemy.set_frontage(10)

	u._flanking_maneuver_reflow(enemy)
	assert_eq(UnitFormation.frontage(u), 14, "frontage unchanged when within hysteresis")


func test_flanking_maneuver_reflow_respects_cooldown() -> void:
	var u := _make_unit(100)
	u.set_frontage(8)
	u._last_reshape_tick = Engine.get_physics_frames() # just reshaped
	var enemy := _make_unit(60)
	enemy.set_frontage(10)

	u._flanking_maneuver_reflow(enemy)
	assert_eq(UnitFormation.frontage(u), 8, "on cooldown: no reshape")


func test_flanking_maneuver_reflow_null_enemy_safe() -> void:
	var u := _make_unit(100)
	u.set_frontage(8)
	u._last_reshape_tick = -1
	u._flanking_maneuver_reflow(null)
	assert_eq(UnitFormation.frontage(u), 8, "null enemy is a safe no-op")


# --- End-to-end _think() integration ----------------------------------------

func test_flanking_maneuver_driven_by_unit_think_in_melee() -> void:
	var u := _make_engaged_unit(100, Vector2(500, 300), Vector2.DOWN)
	u.uid = 1
	u.team = 0
	u.order_mode = Unit.ORDER_FLANKING_MANEUVER
	u.set_frontage(8)
	u._last_reshape_tick = -1

	var enemy := _make_engaged_unit(50, Vector2(500, 310), Vector2.UP)
	enemy.uid = 2
	enemy.team = 1
	enemy.set_frontage(10)
	u.target_enemy = enemy

	u._think(0.016)
	assert_eq(UnitFormation.frontage(u), 14,
		"Unit._think in melee contact triggers _flanking_maneuver_reflow to wrap opposing line")
