extends GutTest
## MULTIPLE_ENGAGE stance (melee maneuver): an engaged unit fighting 2+ distinct enemy
## units at once holds its current facing (instead of turning to bear on whichever single
## foe target_enemy resolves to) and widens its own frontage toward the combined width of
## every adjacent enemy, so its line can actually reach all of them. Distributing damage
## across those adjacent enemies is no longer this stance's own job -- SoldierMelee.resolve
## (via Unit.resolve_soldier_melee) now fights every adjacent engaged enemy simultaneously,
## per soldier, regardless of order_mode (see test_soldier_melee.gd's own multi-defender
## coverage) -- so this file only covers the facing-hold and frontage-widening behavior that
## remains specific to this stance.

const BattleScript = preload("res://scripts/Battle.gd")
const SEED: int = 12345


func before_each() -> void:
	Replay.rng.seed = SEED   # deterministic draws for UnitCombat.strike, as test_pin_down_attack.gd does


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


## An engaged, soldier-seeded variant of _make_unit() -- mirrors test_all_out_attack.gd's
## _make_engaged_unit(): UnitCombat.strike()'s per-soldier melee branch (and, through it,
## Unit.resolve_soldier_melee's adjacent-enemy fan-out) requires is_engaged() true and a
## populated _sim_soldier_pos on both sides, which a bare _make_unit() never reaches.
func _make_engaged_unit(max_soldiers: int, pos: Vector2, face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)
	u.position = pos
	u.facing = face
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)     # latch is_engaged() true
	u.seed_sim_soldiers()   # seed bodies + full health
	return u


# --- Registration: enum mirror, name, hotkey slug ---------------------------

func test_order_multiple_engage_mirrors_battle_order_mode() -> void:
	assert_eq(Unit.ORDER_MULTIPLE_ENGAGE, BattleScript.OrderMode.MULTIPLE_ENGAGE,
		"Unit.ORDER_MULTIPLE_ENGAGE mirror constant matches Battle.OrderMode.MULTIPLE_ENGAGE")


func test_multiple_engage_stance_has_a_name_and_a_hotkey_slug() -> void:
	assert_eq(BattleScript.ORDER_MODE_NAMES.get(BattleScript.OrderMode.MULTIPLE_ENGAGE), "Multiple engage",
		"MULTIPLE_ENGAGE stance has a human-readable name")
	var found_slug := false
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		if entry["mode"] == BattleScript.OrderMode.MULTIPLE_ENGAGE and entry["slug"] == "multiple_engage":
			found_slug = true
			break
	assert_true(found_slug,
		"MULTIPLE_ENGAGE stance is registered in ORDER_MODE_HOTKEYS with slug 'multiple_engage'")


# --- Arm-then-issue plumbing (Battle._apply_order_cmd) -----------------------

func test_stance_only_order_carries_multiple_engage_onto_the_unit() -> void:
	var u := _make_unit()
	u.uid = 1
	var b = BattleScript.new()
	autofree(b)
	b._by_uid[1] = u
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": BattleScript.OrderMode.MULTIPLE_ENGAGE})
	assert_eq(u.order_mode, Unit.ORDER_MULTIPLE_ENGAGE, "a stance-only order sets order_mode")


func test_move_order_carries_multiple_engage_onto_the_unit() -> void:
	var u := _make_unit()
	u.uid = 1
	var b = BattleScript.new()
	autofree(b)
	b._by_uid[1] = u
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.MULTIPLE_ENGAGE})
	assert_eq(u.order_mode, Unit.ORDER_MULTIPLE_ENGAGE, "a move/attack order carrying the stance sets order_mode")


func test_fresh_order_clears_prior_multiple_engage_stance() -> void:
	var u := _make_unit()
	u.uid = 1
	u.order_mode = Unit.ORDER_MULTIPLE_ENGAGE
	var b = BattleScript.new()
	autofree(b)
	b._by_uid[1] = u
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.order_mode, BattleScript.OrderMode.NORMAL, "NORMAL order clears the prior stance")


# --- _adjacent_engaged_enemy_units() detection -------------------------------

func test_adjacent_engaged_enemy_units_excludes_a_distant_enemy() -> void:
	var u := _make_unit()
	u.uid = 1
	var near := _make_unit()
	near.uid = 2
	near.team = 1
	var contact: float = u._front_depth() + near._front_depth()
	near.position = Vector2(0.0, contact - 5.0)   # within contact range
	var far := _make_unit()
	far.uid = 3
	far.team = 1
	far.position = Vector2(0.0, 5000.0)   # detected at long range, but not adjacent
	var adjacent: Array[Unit] = u._adjacent_engaged_enemy_units()
	assert_eq(adjacent.size(), 1, "only the enemy within contact range counts as adjacent")
	assert_eq(adjacent[0], near, "the near enemy is the one returned")


func test_adjacent_engaged_enemy_units_excludes_friendlies_and_dead() -> void:
	var u := _make_unit()
	u.uid = 1
	var friend := _make_unit()
	friend.uid = 2
	friend.team = 0
	friend.position = Vector2(0.0, 5.0)   # right next to u, but same team
	var dead_enemy := _make_unit()
	dead_enemy.uid = 3
	dead_enemy.team = 1
	dead_enemy.position = Vector2(0.0, 5.0)
	dead_enemy.state = Unit.State.DEAD
	assert_true(u._adjacent_engaged_enemy_units().is_empty(),
		"a co-located friendly and a co-located dead enemy are both excluded")


func test_adjacent_engaged_enemy_units_finds_two_distinct_enemies_in_contact() -> void:
	var u := _make_unit()
	u.uid = 1
	var e1 := _make_unit()
	e1.uid = 2
	e1.team = 1
	e1.position = Vector2(0.0, u._front_depth() + e1._front_depth() - 5.0)
	var e2 := _make_unit()
	e2.uid = 3
	e2.team = 1
	e2.position = Vector2(0.0, u._front_depth() + e2._front_depth() - 10.0)
	assert_eq(u._adjacent_engaged_enemy_units().size(), 2,
		"both distinct enemy units within contact range are counted")


# --- Facing hold in _face_for_action -----------------------------------------

func test_face_for_action_holds_facing_under_multiple_engage_with_two_adjacent_enemies() -> void:
	var u := _make_unit()
	u.uid = 1
	u.order_mode = Unit.ORDER_MULTIPLE_ENGAGE
	var e1 := _make_unit()
	e1.uid = 2
	e1.team = 1
	e1.position = Vector2(0.0, u._front_depth() + e1._front_depth() - 5.0)
	var e2 := _make_unit()
	e2.uid = 3
	e2.team = 1
	e2.position = Vector2(0.0, u._front_depth() + e2._front_depth() - 10.0)
	assert_eq(u._adjacent_engaged_enemy_units().size(), 2, "sanity: both enemies read as adjacent")
	var far_point := Vector2(500.0, 0.0)   # well off DOWN -- would normally force a big turn
	var faced: bool = u._face_for_action(far_point, 0.1, e1)
	assert_true(faced, "MULTIPLE_ENGAGE reports itself as faced while fighting 2+ adjacent enemies")
	assert_eq(u.facing, Vector2.DOWN, "and its facing holds instead of turning toward the point")
	assert_eq(u._engage_turn_target, Vector2.ZERO, "no engage turn is armed by the held-facing path")


func test_face_for_action_settles_an_in_progress_turn_when_multiple_engage_takes_over_mid_turn() -> void:
	# Mirrors test_face_for_action_settles_an_in_progress_turn_when_squared_mid_turn: a unit
	# can pick up a second adjacent enemy (or have MULTIPLE_ENGAGE armed) while an engage turn
	# from before is still in progress. Left unsettled, the held-facing early return would
	# leave _engage_turn_target stuck non-zero forever.
	var u := _make_unit()
	u.uid = 1
	var e1 := _make_unit()
	e1.uid = 2
	e1.team = 1
	e1.position = Vector2(500.0, 0.0)   # a large swing off DOWN -- arms an engage turn
	u._face_for_action(e1.position, 0.1, e1)
	assert_ne(u._engage_turn_target, Vector2.ZERO, "a large heading swing arms an engage turn")
	# A second enemy closes to contact range and the stance takes over this same tick.
	e1.position = Vector2(0.0, u._front_depth() + e1._front_depth() - 5.0)
	var e2 := _make_unit()
	e2.uid = 3
	e2.team = 1
	e2.position = Vector2(0.0, u._front_depth() + e2._front_depth() - 10.0)
	u.order_mode = Unit.ORDER_MULTIPLE_ENGAGE
	assert_eq(u._adjacent_engaged_enemy_units().size(), 2, "sanity: both enemies now read as adjacent")
	var faced: bool = u._face_for_action(e1.position, 0.1, e1)
	assert_true(faced, "MULTIPLE_ENGAGE reports itself as faced")
	assert_eq(u._engage_turn_target, Vector2.ZERO,
		"picking up MULTIPLE_ENGAGE mid-turn settles the in-progress engage turn instead of leaving it stuck")


func test_face_for_action_turns_normally_under_multiple_engage_with_only_one_adjacent_enemy() -> void:
	var u := _make_unit()
	u.uid = 1
	u.order_mode = Unit.ORDER_MULTIPLE_ENGAGE
	var e1 := _make_unit()
	e1.uid = 2
	e1.team = 1
	e1.position = Vector2(0.0, u._front_depth() + e1._front_depth() - 5.0)
	var e2 := _make_unit()
	e2.uid = 3
	e2.team = 1
	e2.position = Vector2(0.0, 5000.0)   # far outside contact range -- not adjacent
	assert_eq(u._adjacent_engaged_enemy_units().size(), 1, "sanity: only one enemy reads as adjacent")
	u._face_for_action(Vector2(500.0, 0.0), 0.1, e1)
	assert_ne(u._engage_turn_target, Vector2.ZERO,
		"with fewer than 2 adjacent enemies, MULTIPLE_ENGAGE behaves like any other stance and begins turning")


# --- Frontage widening (_multiple_engage_reflow) -----------------------------

func test_multiple_engage_frontage_reflow_is_a_no_op_below_two_adjacent_enemies() -> void:
	var u := _make_unit(120)
	u.set_frontage(10)
	u._last_reshape_tick = -1   # not on cooldown
	var e1 := _make_unit(120)
	e1.set_frontage(8)
	u._multiple_engage_reflow([e1])
	assert_eq(UnitFormation.frontage(u), 10, "fewer than 2 adjacent enemies: frontage untouched")


func test_multiple_engage_frontage_reflow_widens_to_combined_adjacent_width() -> void:
	var u := _make_unit(120)
	u.set_frontage(10)
	u._last_reshape_tick = -1   # not on cooldown
	var e1 := _make_unit(120)
	e1.set_frontage(8)
	var e2 := _make_unit(120)
	e2.set_frontage(6)
	u._multiple_engage_reflow([e1, e2])
	assert_eq(UnitFormation.frontage(u), 14, "widened to the combined width of both adjacent enemies (8 + 6)")


func test_multiple_engage_frontage_reflow_clamps_to_max_soldiers() -> void:
	var u := _make_unit(10)   # max_soldiers caps the widened frontage well below the raw sum
	u.set_frontage(5)
	u._last_reshape_tick = -1
	var e1 := _make_unit(120)
	e1.set_frontage(8)
	var e2 := _make_unit(120)
	e2.set_frontage(6)
	u._multiple_engage_reflow([e1, e2])
	assert_eq(UnitFormation.frontage(u), 10, "clamped to this unit's own max_soldiers")


func test_multiple_engage_frontage_reflow_respects_hysteresis() -> void:
	var u := _make_unit(120)
	u.set_frontage(13)   # already within 1 file of the 14-file target below
	u._last_reshape_tick = -1
	var e1 := _make_unit(120)
	e1.set_frontage(8)
	var e2 := _make_unit(120)
	e2.set_frontage(6)
	u._multiple_engage_reflow([e1, e2])
	assert_eq(UnitFormation.frontage(u), 13, "within the hysteresis band: no reshape")


func test_multiple_engage_frontage_reflow_respects_cooldown() -> void:
	var u := _make_unit(120)
	u.set_frontage(10)
	u._last_reshape_tick = Engine.get_physics_frames()   # a reshape "just happened" this tick
	var e1 := _make_unit(120)
	e1.set_frontage(8)
	var e2 := _make_unit(120)
	e2.set_frontage(6)
	u._multiple_engage_reflow([e1, e2])
	assert_eq(UnitFormation.frontage(u), 10, "still on cooldown: no reshape even though the target differs a lot")


# --- End-to-end: a live _think() tick actually drives the reflow ------------

func test_multiple_engage_reflow_fires_from_a_live_think_tick_in_melee_contact() -> void:
	# Unlike the _multiple_engage_reflow()-called-directly tests above, this drives the whole
	# call site inside _think()'s "Fight when in contact" branch -- the same pattern
	# test_pin_down_attack.gd's own _think()-driven tests use (target_enemy set, both units
	# positioned in contact, then a single u._think(delta) call).
	var u := _make_unit(60)
	u.uid = 1
	u.team = 0
	u.order_mode = Unit.ORDER_MULTIPLE_ENGAGE
	u.set_frontage(8)
	u._last_reshape_tick = -1   # not on cooldown
	var e1 := _make_unit(120)
	e1.uid = 2
	e1.team = 1
	e1.set_frontage(9)
	e1.position = Vector2(0.0, u._front_depth() + e1._front_depth() - 2.0)
	var e2 := _make_unit(120)
	e2.uid = 3
	e2.team = 1
	e2.set_frontage(9)
	e2.position = Vector2(0.0, u._front_depth() + e2._front_depth() - 4.0)
	u.target_enemy = e1
	u._think(0.1)
	assert_eq(u.state, Unit.State.FIGHTING, "sanity: the live tick actually entered melee")
	assert_eq(UnitFormation.frontage(u), 18,
		"a live _think() tick reflows frontage toward the combined width of both adjacent enemies (9 + 9)")


# --- End-to-end: resolve_soldier_melee damages every adjacent engaged enemy at once ------
# (SoldierMelee.resolve's own multi-defender search, reach-gating, and determinism coverage
# lives in test_soldier_melee.gd -- this file only checks that Unit.resolve_soldier_melee's
# own adjacent-enemy gather, called the way UnitCombat.strike actually calls it, reaches both
# enemies regardless of order_mode, mirroring the frontage-reflow end-to-end test above.)

func test_resolve_soldier_melee_damages_both_adjacent_engaged_enemies_regardless_of_order_mode() -> void:
	# u is genuinely adjacent to (and engaged with) TWO distinct enemy units at once, stacked
	# behind it at slightly different distances (mirroring _adjacent_engaged_enemy_units()'s
	# own contact-range test above -- unit-CENTER distance, not per-soldier position, is what
	# "adjacent" means). Calling resolve_soldier_melee(e_left) -- exactly how UnitCombat.strike's
	# engaged branch invokes it -- must ALSO damage e_right, since the wrapper unions in every
	# adjacent engaged enemy, not just the one it's handed. Plain NORMAL order_mode (u.order_mode
	# is never set here) -- proving this is no longer MULTIPLE_ENGAGE-specific, per this file's
	# own top-of-file doc comment.
	var u := _make_engaged_unit(60, Vector2(0, 0), Vector2.DOWN)
	u.uid = 1
	u.team = 0

	var e_left := Unit.new()
	e_left.max_soldiers = 120
	add_child_autofree(e_left)   # _ready() sets soldiers = max_soldiers, so _front_depth() below is valid
	e_left.uid = 2
	e_left.team = 1
	e_left.facing = Vector2.UP
	e_left.position = Vector2(0.0, u._front_depth() + e_left._front_depth() - 2.0)
	e_left.state = Unit.State.FIGHTING
	e_left.tick_engaged(0.1)
	e_left.seed_sim_soldiers()   # seeded AFTER position is set, so bodies land at the right spot

	var e_right := Unit.new()
	e_right.max_soldiers = 120
	add_child_autofree(e_right)
	e_right.uid = 3
	e_right.team = 1
	e_right.facing = Vector2.UP
	e_right.position = Vector2(0.0, u._front_depth() + e_right._front_depth() - 4.0)
	e_right.state = Unit.State.FIGHTING
	e_right.tick_engaged(0.1)
	e_right.seed_sim_soldiers()

	assert_eq(u._adjacent_engaged_enemy_units().size(), 2,
		"sanity: both enemies read as adjacent and engaged")
	var e_left_before: int = e_left.soldiers
	var e_right_before: int = e_right.soldiers
	# resolve_soldier_melee bypasses attack-cadence gating entirely (that's _think()'s own
	# _attack_cd, not this function's concern), so a plain loop suffices -- no need to drive
	# _think() or replicate its cooldown decrement.
	for _k in range(100):
		u.resolve_soldier_melee(e_left)
	assert_lt(e_left.soldiers, e_left_before, "the primary (passed) enemy takes casualties")
	assert_lt(e_right.soldiers, e_right_before,
		"the other adjacent enemy ALSO takes casualties in the same run -- each soldier finds its own nearest enemy, no rotation needed")
