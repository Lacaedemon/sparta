extends GutTest
## Wedge charge (Battle.OrderMode.WEDGE_CHARGE): an attack-order subtype that maximizes
## charge speed at the expense of defense and fatigue, aiming to punch a hole in the enemy
## line. Unlike all-out-attack (which trades defense for MORE attack), wedge charge trades
## defense for FASTER MOVEMENT -- own attack is untouched. Covers all three tradeoffs from
## the acceptance criteria (charge speed up, own defense down, own fatigue cost up) plus the
## OrderMode plumbing (mirror constant, name, hotkey), mirroring test_all_out_attack.gd's
## structure and _make_engaged_unit() end-to-end melee pattern.
##
## Scope note: this covers only the attack-order subtype (speed/defense/fatigue). The
## issue's own companion "wedge formation" idea is explicitly out of scope here -- see the
## PR description.

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


## Mirrors test_all_out_attack.gd's _make_engaged_unit(): a bare _make_unit() never
## engages, so UnitCombat.strike()'s per-soldier melee branch needs is_engaged() true and
## seeded soldier bodies to dispatch into the same path real, in-contact combat takes.
func _make_engaged_unit(max_soldiers: int, pos: Vector2, face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)
	u.position = pos
	u.facing = face
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	u.seed_sim_soldiers()
	return u


func before_each() -> void:
	Replay.rng.seed = 12345   # deterministic draws for UnitCombat.strike/shoot


# --- order_mode_modifiers: wedge charge costs defense only, no attack bonus ---------

func test_neither_unit_wedge_charge_gives_no_defense_modifier() -> void:
	var u := _make_unit()
	var enemy := _make_unit()
	var mods: Vector2 = UnitCombat.order_mode_modifiers(u, enemy)
	assert_almost_eq(mods.y, 1.0, TOL, "no defense penalty without WEDGE_CHARGE")


func test_attacker_wedge_charge_does_not_boost_attack_mult() -> void:
	# Unlike ALL_OUT_ATTACK, wedge charge's own attack is untouched -- its speed/defense/
	# fatigue tradeoff is applied elsewhere (Unit.gd's pace_speed, UnitMorale.tick_fatigue).
	var u := _make_unit()
	u.order_mode = Unit.ORDER_WEDGE_CHARGE
	var enemy := _make_unit()
	var mods: Vector2 = UnitCombat.order_mode_modifiers(u, enemy)
	assert_almost_eq(mods.x, 1.0, TOL,
		"wedge charge does not boost the striker's own effective attack")
	assert_almost_eq(mods.y, 1.0, TOL,
		"the striker's own stance alone must not discount the TARGET's defense")


func test_target_wedge_charge_penalizes_only_defense_mult() -> void:
	# The defense penalty must be keyed on the TARGET's own order_mode, not the
	# attacker's -- the exact bug class test_all_out_attack.gd guards for ALL_OUT_ATTACK.
	var u := _make_unit()
	var enemy := _make_unit()
	enemy.order_mode = Unit.ORDER_WEDGE_CHARGE
	var mods: Vector2 = UnitCombat.order_mode_modifiers(u, enemy)
	assert_almost_eq(mods.x, 1.0, TOL,
		"a non-attacking unit's stance must not boost someone else's attack")
	assert_almost_eq(mods.y, UnitCombat.WEDGE_CHARGE_DEFENSE_PENALTY, TOL,
		"a unit wedge-charging is itself easier to hit, even as the target")


# --- end-to-end: strike() actually moves casualty counts for the exposed defense -----

func test_wedge_charge_defender_takes_more_melee_damage_when_engaged() -> void:
	var attacker_a := _make_engaged_unit(100, Vector2(0, 0), Vector2.DOWN)
	attacker_a.team = 0
	var defender_wedge := _make_engaged_unit(100, Vector2(0, 10), Vector2.UP)
	defender_wedge.team = 1
	defender_wedge.order_mode = Unit.ORDER_WEDGE_CHARGE
	var before_a: int = defender_wedge.soldiers

	var attacker_b := _make_engaged_unit(100, Vector2(0, 0), Vector2.DOWN)
	attacker_b.team = 0
	var defender_normal := _make_engaged_unit(100, Vector2(0, 10), Vector2.UP)
	defender_normal.team = 1
	var before_b: int = defender_normal.soldiers

	# 16 cadences -- same sample size test_all_out_attack.gd's matching test uses, for the
	# same reason (enough to open a consistent gap without either regiment wiping out).
	Replay.rng.seed = 12345
	for _k in range(16):
		UnitCombat.strike(attacker_a, defender_wedge)
	var casualties_exposed: int = before_a - defender_wedge.soldiers

	Replay.rng.seed = 12345
	for _k in range(16):
		UnitCombat.strike(attacker_b, defender_normal)
	var casualties_safe: int = before_b - defender_normal.soldiers

	assert_gt(casualties_exposed, casualties_safe,
		"an engaged defender wedge-charging takes more melee casualties than one that isn't")


# --- charge speed: wedge charge reaches a higher pace than NORMAL --------------------

func test_wedge_charge_unit_reaches_a_higher_pace_than_normal() -> void:
	# A destination well past SPRINT_START_DISTANCE and no missile fire selects walk pace
	# (Unit._move_to's AUTO branch) for both units -- isolating the wedge-charge bonus from
	# gait selection. 120 ticks at accel=30/s comfortably clears the ~1.5s ramp to plateau.
	var target := Vector2(0, 1000)
	var wedge := _make_unit()
	wedge.order_mode = Unit.ORDER_WEDGE_CHARGE
	var normal := _make_unit()

	for _i in range(120):
		wedge._move_to(target, 1.0 / 60.0)
		normal._move_to(target, 1.0 / 60.0)

	assert_almost_eq(normal._current_speed, normal.walk_speed, 0.5,
		"sanity: the normal unit plateaus at its own walk pace")
	assert_almost_eq(wedge._current_speed, normal.walk_speed * Unit.WEDGE_CHARGE_SPEED_BONUS, 0.5,
		"the wedge-charging unit plateaus at WEDGE_CHARGE_SPEED_BONUS times walk pace")
	assert_gt(wedge._current_speed, normal._current_speed,
		"wedge charge reaches a higher pace than NORMAL under the same conditions")


# --- fatigue: wedge charge builds fatigue faster while fighting ---------------------

func test_wedge_charge_unit_builds_fatigue_faster_while_fighting() -> void:
	var wedge := _make_unit()
	wedge.order_mode = Unit.ORDER_WEDGE_CHARGE
	wedge.state = Unit.State.FIGHTING
	wedge.rank_relief = false   # isolate the wedge multiplier from the rank-cycle reduction
	var normal := _make_unit()
	normal.state = Unit.State.FIGHTING
	normal.rank_relief = false

	for _i in range(60):
		UnitMorale.tick_fatigue(wedge, 1.0 / 60.0)
		UnitMorale.tick_fatigue(normal, 1.0 / 60.0)

	assert_almost_eq(wedge.fatigue, normal.fatigue * Unit.WEDGE_CHARGE_FATIGUE_MULT, 0.01,
		"wedge charge builds fatigue at WEDGE_CHARGE_FATIGUE_MULT times the normal rate")
	assert_gt(wedge.fatigue, normal.fatigue,
		"a wedge-charging unit tires faster than a normal one while fighting")


# --- OrderMode plumbing: mirror constants, names, hotkeys stay in sync --------------

func test_order_wedge_charge_mirrors_battle_order_mode() -> void:
	assert_eq(Unit.ORDER_WEDGE_CHARGE, BattleScript.OrderMode.WEDGE_CHARGE,
		"Unit's mirrored int constant matches Battle.OrderMode.WEDGE_CHARGE")


func test_wedge_charge_has_a_name_and_a_hotkey_slug() -> void:
	assert_true(BattleScript.ORDER_MODE_NAMES.has(BattleScript.OrderMode.WEDGE_CHARGE),
		"WEDGE_CHARGE has a human-readable HUD name")
	var slugs: Array = []
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		slugs.append(entry["slug"])
	assert_true(slugs.has("wedge_charge"), "WEDGE_CHARGE has a rebindable hotkey slug")


func test_wedge_charge_hotkey_default_is_not_reused() -> void:
	var seen: Dictionary = {}
	for slug in SettingsScript.DEFAULT_ORDER_BINDINGS:
		var key: int = SettingsScript.DEFAULT_ORDER_BINDINGS[slug]
		assert_false(seen.has(key),
			"default hotkey %s is already bound to %s" % [key, seen.get(key)])
		seen[key] = slug
