extends GutTest
## All-out attack (Battle.OrderMode.ALL_OUT_ATTACK): a stance that trades defense for
## offense. UnitCombat.order_mode_modifiers gives the striking side +20% effective
## attack when the STRIKER is in this stance, and -20% effective defense when the
## TARGET is -- so a unit fighting all-out both hits harder and gets hit harder.
## Covers the acceptance criteria directly (own hit chance up, own defense down) and
## guards the exact bug three review rounds caught and fixed: the defense penalty
## must be keyed on the TARGET's own order_mode, never the attacker's.

const BattleScript = preload("res://scripts/Battle.gd")
const SettingsScript = preload("res://scripts/Settings.gd")
const TOL: float = 1e-4


func _make_unit(max_soldiers: int = 100) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers, joins "units"
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func before_each() -> void:
	Replay.rng.seed = 12345   # deterministic draws for UnitCombat.strike/shoot


# --- order_mode_modifiers: the pure multiplier lookup -------------------------

func test_neither_unit_all_out_attack_gives_no_modifiers() -> void:
	var u := _make_unit()
	var enemy := _make_unit()
	var mods: Vector2 = UnitCombat.order_mode_modifiers(u, enemy)
	assert_almost_eq(mods.x, 1.0, TOL, "no attack bonus without ALL_OUT_ATTACK")
	assert_almost_eq(mods.y, 1.0, TOL, "no defense penalty without ALL_OUT_ATTACK")


func test_attacker_all_out_attack_boosts_only_attack_mult() -> void:
	var u := _make_unit()
	u.order_mode = Unit.ORDER_ALL_OUT_ATTACK
	var enemy := _make_unit()
	var mods: Vector2 = UnitCombat.order_mode_modifiers(u, enemy)
	assert_almost_eq(mods.x, UnitCombat.ALL_OUT_ATTACK_HIT_BONUS, TOL,
		"the striker's own ALL_OUT_ATTACK boosts its effective attack")
	assert_almost_eq(mods.y, 1.0, TOL,
		"the striker's stance alone must not discount the TARGET's defense")


func test_target_all_out_attack_penalizes_only_defense_mult() -> void:
	# This is the exact bug three review rounds caught: the defense penalty must be
	# keyed on the TARGET's own order_mode, not the attacker's.
	var u := _make_unit()
	var enemy := _make_unit()
	enemy.order_mode = Unit.ORDER_ALL_OUT_ATTACK
	var mods: Vector2 = UnitCombat.order_mode_modifiers(u, enemy)
	assert_almost_eq(mods.x, 1.0, TOL,
		"a non-attacking unit's stance must not boost someone else's attack")
	assert_almost_eq(mods.y, UnitCombat.ALL_OUT_ATTACK_DEFENSE_PENALTY, TOL,
		"a unit fighting all-out is itself easier to hit, even as the target")


func test_both_units_all_out_attack_apply_independently() -> void:
	var u := _make_unit()
	u.order_mode = Unit.ORDER_ALL_OUT_ATTACK
	var enemy := _make_unit()
	enemy.order_mode = Unit.ORDER_ALL_OUT_ATTACK
	var mods: Vector2 = UnitCombat.order_mode_modifiers(u, enemy)
	assert_almost_eq(mods.x, UnitCombat.ALL_OUT_ATTACK_HIT_BONUS, TOL)
	assert_almost_eq(mods.y, UnitCombat.ALL_OUT_ATTACK_DEFENSE_PENALTY, TOL)


# --- end-to-end: strike()/shoot() actually move casualty counts --------------

func test_all_out_attack_striker_deals_more_melee_damage() -> void:
	# Same attacker/defender stat line and the same RNG draw; only the attacker's
	# stance differs, so any damage delta is attributable to ALL_OUT_ATTACK alone.
	var attacker_all_out := _make_unit()
	attacker_all_out.team = 0
	attacker_all_out.order_mode = Unit.ORDER_ALL_OUT_ATTACK
	var defender_a := _make_unit()
	defender_a.team = 1
	var before_a: int = defender_a.soldiers

	var attacker_normal := _make_unit()
	attacker_normal.team = 0
	var defender_b := _make_unit()
	defender_b.team = 1
	var before_b: int = defender_b.soldiers

	Replay.rng.seed = 12345
	UnitCombat.strike(attacker_all_out, defender_a)
	var casualties_all_out: int = before_a - defender_a.soldiers

	Replay.rng.seed = 12345   # replay the identical RNG draw against the normal attacker
	UnitCombat.strike(attacker_normal, defender_b)
	var casualties_normal: int = before_b - defender_b.soldiers

	assert_gt(casualties_all_out, casualties_normal,
		"an all-out-attack striker inflicts more melee casualties than a normal one")


func test_all_out_attack_defender_takes_more_melee_damage() -> void:
	# Same attacker, same RNG draw; only the DEFENDER's stance differs, isolating the
	# defense-penalty half of the tradeoff (the half the bug hid for three rounds).
	var attacker_a := _make_unit()
	attacker_a.team = 0
	var defender_all_out := _make_unit()
	defender_all_out.team = 1
	defender_all_out.order_mode = Unit.ORDER_ALL_OUT_ATTACK
	var before_a: int = defender_all_out.soldiers

	var attacker_b := _make_unit()
	attacker_b.team = 0
	var defender_normal := _make_unit()
	defender_normal.team = 1
	var before_b: int = defender_normal.soldiers

	Replay.rng.seed = 12345
	UnitCombat.strike(attacker_a, defender_all_out)
	var casualties_exposed: int = before_a - defender_all_out.soldiers

	Replay.rng.seed = 12345
	UnitCombat.strike(attacker_b, defender_normal)
	var casualties_safe: int = before_b - defender_normal.soldiers

	assert_gt(casualties_exposed, casualties_safe,
		"a defender fighting all-out takes more melee casualties than one that isn't")


func test_all_out_attack_striker_deals_more_ranged_damage() -> void:
	var attacker_all_out := _make_unit()
	attacker_all_out.team = 0
	attacker_all_out.is_ranged = true
	attacker_all_out.order_mode = Unit.ORDER_ALL_OUT_ATTACK
	var defender_a := _make_unit()
	defender_a.team = 1
	var before_a: int = defender_a.soldiers

	var attacker_normal := _make_unit()
	attacker_normal.team = 0
	attacker_normal.is_ranged = true
	var defender_b := _make_unit()
	defender_b.team = 1
	var before_b: int = defender_b.soldiers

	Replay.rng.seed = 12345
	UnitCombat.shoot(attacker_all_out, defender_a)
	var casualties_all_out: int = before_a - defender_a.soldiers

	Replay.rng.seed = 12345
	UnitCombat.shoot(attacker_normal, defender_b)
	var casualties_normal: int = before_b - defender_b.soldiers

	assert_gt(casualties_all_out, casualties_normal,
		"an all-out-attack shooter inflicts more ranged casualties than a normal one")


# --- OrderMode plumbing: mirror constants, names, hotkeys stay in sync --------

func test_order_all_out_attack_mirrors_battle_order_mode() -> void:
	assert_eq(Unit.ORDER_ALL_OUT_ATTACK, BattleScript.OrderMode.ALL_OUT_ATTACK,
		"Unit's mirrored int constant matches Battle.OrderMode.ALL_OUT_ATTACK")


func test_all_out_attack_has_a_name_and_a_hotkey_slug() -> void:
	assert_true(BattleScript.ORDER_MODE_NAMES.has(BattleScript.OrderMode.ALL_OUT_ATTACK),
		"ALL_OUT_ATTACK has a human-readable HUD name")
	var slugs: Array = []
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		slugs.append(entry["slug"])
	assert_true(slugs.has("all_out_attack"), "ALL_OUT_ATTACK has a rebindable hotkey slug")


func test_all_out_attack_hotkey_default_is_not_reused() -> void:
	var seen: Dictionary = {}
	for slug in SettingsScript.DEFAULT_ORDER_BINDINGS:
		var key: int = SettingsScript.DEFAULT_ORDER_BINDINGS[slug]
		assert_false(seen.has(key),
			"default hotkey %s is already bound to %s" % [key, seen.get(key)])
		seen[key] = slug
