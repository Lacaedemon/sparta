extends GutTest
## Pin down / stall (Battle.OrderMode.PIN_DOWN): a defensive attack stance that trades
## attack tempo for a brief self-inflicted exposure window. Covers the two acceptance
## criteria directly: attack frequency drops below the baseline cadence, and the
## unit's own defense is measurably lower than baseline for a short window after each
## swing (see the PIN_DOWN_* constants and pin_down_defense_factor() in scripts/Unit.gd).

const BattleScript = preload("res://scripts/Battle.gd")
const SettingsScript = preload("res://scripts/Settings.gd")
const SEED: int = 12345


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func before_each() -> void:
	Replay.rng.seed = SEED   # deterministic draws for UnitCombat.strike/shoot


# --- attack frequency: PIN_DOWN swings slower than baseline -------------------

func test_pin_down_attack_interval_is_slower_than_baseline() -> void:
	# The stance's own cooldown must genuinely exceed the normal melee/ranged cadence --
	# otherwise it isn't "fewer/slower attacks" at all.
	assert_gt(Unit.PIN_DOWN_ATTACK_INTERVAL, Unit.ATTACK_INTERVAL,
		"pin down swings less often than a normal melee stance")
	assert_gt(Unit.PIN_DOWN_ATTACK_INTERVAL, Unit.RANGED_INTERVAL,
		"pin down swings less often than a normal ranged stance")


func test_pin_down_strike_arms_the_slower_cooldown() -> void:
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_PIN_DOWN
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	# Straight ahead of the unit's DOWN facing (no re-face turn needed), in contact.
	enemy.position = Vector2(0, u.attack_range + Unit.RADIUS + enemy.RADIUS - 2.0)
	u.target_enemy = enemy
	u._think(0.1)
	assert_almost_eq(u._attack_cd, Unit.PIN_DOWN_ATTACK_INTERVAL, 0.001,
		"a PIN_DOWN strike arms PIN_DOWN_ATTACK_INTERVAL, not the normal ATTACK_INTERVAL")


func test_normal_strike_still_arms_the_baseline_cooldown() -> void:
	# Contrast: the same contact without PIN_DOWN arms the normal (faster) cooldown --
	# confirming the slower interval is specific to the stance, not the test geometry.
	var u := _make_unit()
	u.team = 0
	u.position = Vector2.ZERO   # order_mode defaults to NORMAL
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(0, u.attack_range + Unit.RADIUS + enemy.RADIUS - 2.0)
	u.target_enemy = enemy
	u._think(0.1)
	assert_almost_eq(u._attack_cd, Unit.ATTACK_INTERVAL, 0.001,
		"a normal-stance strike arms the baseline ATTACK_INTERVAL")


func test_pin_down_ranged_shot_arms_the_slower_cooldown() -> void:
	var u := _make_unit()
	u.team = 0
	u.is_ranged = true
	u.order_mode = Unit.ORDER_PIN_DOWN
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	# Straight ahead of the unit's DOWN facing (no re-face turn needed), in ranged range.
	enemy.position = Vector2(0, Unit.RANGED_RANGE - 20.0)
	u.target_enemy = enemy
	u._think(0.1)
	assert_almost_eq(u._attack_cd, Unit.PIN_DOWN_ATTACK_INTERVAL, 0.001,
		"a PIN_DOWN ranged shot also arms the slower interval, not RANGED_INTERVAL")


# --- defense exposure: lower defense for a short window after each swing ------

func test_pin_down_strike_opens_an_exposure_window() -> void:
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_PIN_DOWN
	assert_eq(u._pin_down_exposure_cd, 0.0, "no exposure before any swing")
	u._start_attack_cd(Unit.ATTACK_INTERVAL)
	assert_almost_eq(u._pin_down_exposure_cd, Unit.PIN_DOWN_EXPOSURE_DURATION, 0.001,
		"a PIN_DOWN swing opens the exposure window for its full duration")


func test_normal_stance_strike_never_opens_an_exposure_window() -> void:
	var u := _make_unit()
	u.team = 0   # order_mode defaults to NORMAL
	u._start_attack_cd(Unit.ATTACK_INTERVAL)
	assert_eq(u._pin_down_exposure_cd, 0.0,
		"a non-PIN_DOWN stance never opens the exposure window")


func test_pin_down_defense_factor_is_reduced_during_exposure() -> void:
	var u := _make_unit()
	u.order_mode = Unit.ORDER_PIN_DOWN
	u._pin_down_exposure_cd = Unit.PIN_DOWN_EXPOSURE_DURATION
	assert_lt(u.pin_down_defense_factor(), 1.0,
		"defense is measurably lower than baseline while the exposure window is open")
	assert_almost_eq(u.pin_down_defense_factor(), Unit.PIN_DOWN_DEFENSE_FACTOR, 0.001)


func test_pin_down_defense_factor_is_full_once_the_window_closes() -> void:
	var u := _make_unit()
	u.order_mode = Unit.ORDER_PIN_DOWN
	u._pin_down_exposure_cd = 0.0   # window elapsed
	assert_eq(u.pin_down_defense_factor(), 1.0,
		"defense is back to baseline once the exposure window has closed")


func test_pin_down_exposure_window_counts_down_and_closes() -> void:
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_PIN_DOWN
	u._pin_down_exposure_cd = Unit.PIN_DOWN_EXPOSURE_DURATION
	u._physics_process(Unit.PIN_DOWN_EXPOSURE_DURATION + 0.01)
	assert_eq(u._pin_down_exposure_cd, 0.0, "the exposure window ticks down to zero and stays there")
	assert_eq(u.pin_down_defense_factor(), 1.0, "...so defense returns to baseline")


func test_non_pin_down_stance_defends_at_full_value_even_with_a_stale_timer() -> void:
	# A defensive belt-and-braces check: even if the exposure timer were somehow still
	# running, the factor is gated on the stance too -- only a PIN_DOWN unit is ever exposed.
	var u := _make_unit()
	u.order_mode = Unit.ORDER_HOLD
	u._pin_down_exposure_cd = Unit.PIN_DOWN_EXPOSURE_DURATION
	assert_eq(u.pin_down_defense_factor(), 1.0,
		"only the PIN_DOWN stance itself is ever exposed, regardless of the timer")


# --- end-to-end: exposure measurably raises incoming melee/ranged damage ------

func test_pin_down_exposure_increases_incoming_melee_damage() -> void:
	# Same attacker and defender stat line, only the defender's exposure differs: the
	# exposed roll must deal strictly more damage than the same roll against a
	# non-exposed PIN_DOWN defender.
	var attacker := _make_unit()
	attacker.team = 0
	attacker.position = Vector2.ZERO

	var defender_exposed := _make_unit()
	defender_exposed.team = 1
	defender_exposed.order_mode = Unit.ORDER_PIN_DOWN
	defender_exposed._pin_down_exposure_cd = Unit.PIN_DOWN_EXPOSURE_DURATION
	var soldiers_before_exposed: int = defender_exposed.soldiers

	var defender_safe := _make_unit()
	defender_safe.team = 1
	defender_safe.order_mode = Unit.ORDER_PIN_DOWN
	defender_safe._pin_down_exposure_cd = 0.0
	var soldiers_before_safe: int = defender_safe.soldiers

	Replay.rng.seed = SEED
	UnitCombat.strike(attacker, defender_exposed)
	var casualties_exposed: int = soldiers_before_exposed - defender_exposed.soldiers

	Replay.rng.seed = SEED   # replay the identical RNG draw against the non-exposed defender
	UnitCombat.strike(attacker, defender_safe)
	var casualties_safe: int = soldiers_before_safe - defender_safe.soldiers

	assert_gt(casualties_exposed, casualties_safe,
		"the same strike deals more casualties to a defender caught mid-exposure")


func test_pin_down_exposure_increases_incoming_ranged_damage() -> void:
	var attacker := _make_unit()
	attacker.team = 0
	attacker.is_ranged = true
	attacker.position = Vector2.ZERO

	var defender_exposed := _make_unit()
	defender_exposed.team = 1
	defender_exposed.order_mode = Unit.ORDER_PIN_DOWN
	defender_exposed._pin_down_exposure_cd = Unit.PIN_DOWN_EXPOSURE_DURATION
	defender_exposed.position = Vector2(200, 0)
	var soldiers_before_exposed: int = defender_exposed.soldiers

	var defender_safe := _make_unit()
	defender_safe.team = 1
	defender_safe.order_mode = Unit.ORDER_PIN_DOWN
	defender_safe._pin_down_exposure_cd = 0.0
	defender_safe.position = Vector2(200, 0)
	var soldiers_before_safe: int = defender_safe.soldiers

	Replay.rng.seed = SEED
	UnitCombat.shoot(attacker, defender_exposed)
	var casualties_exposed: int = soldiers_before_exposed - defender_exposed.soldiers

	Replay.rng.seed = SEED
	UnitCombat.shoot(attacker, defender_safe)
	var casualties_safe: int = soldiers_before_safe - defender_safe.soldiers

	assert_gt(casualties_exposed, casualties_safe,
		"the same volley deals more casualties to a defender caught mid-exposure")


# --- OrderMode plumbing: mirror constants, names, hotkeys stay in sync --------

func test_order_pin_down_mirrors_battle_order_mode() -> void:
	assert_eq(Unit.ORDER_PIN_DOWN, BattleScript.OrderMode.PIN_DOWN,
		"Unit's mirrored int constant matches Battle.OrderMode.PIN_DOWN")


func test_pin_down_has_a_name_and_a_hotkey_slug() -> void:
	assert_true(BattleScript.ORDER_MODE_NAMES.has(BattleScript.OrderMode.PIN_DOWN),
		"PIN_DOWN has a human-readable HUD name")
	var slugs: Array = []
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		slugs.append(entry["slug"])
	assert_true(slugs.has("pin_down"), "PIN_DOWN has a rebindable hotkey slug")


func test_pin_down_hotkey_default_is_not_reused() -> void:
	var seen: Dictionary = {}
	for slug in SettingsScript.DEFAULT_ORDER_BINDINGS:
		var key: int = SettingsScript.DEFAULT_ORDER_BINDINGS[slug]
		assert_false(seen.has(key),
			"default hotkey %s is already bound to %s" % [key, seen.get(key)])
		seen[key] = slug

