extends GutTest
## All-out attack (Battle.OrderMode.ALL_OUT_ATTACK): a stance that trades defense for
## offense. UnitCombat.order_mode_modifiers gives the striking side +20% effective
## attack when the STRIKER is in this stance, and -20% effective defense when the
## TARGET is -- so a unit fighting all-out both hits harder and gets hit harder.
## Covers the acceptance criteria directly (own hit chance up, own defense down) and
## guards two review-caught bugs: (1) the defense penalty must be keyed on the
## TARGET's own order_mode, never the attacker's; (2) order_mode_modifiers() must
## actually apply in the per-soldier melee path (SoldierMelee.resolve()'s wound_scale),
## not just the regiment-formula/ranged fallback -- the melee end-to-end tests below
## stage genuinely ENGAGED units (see _make_engaged_unit) so they exercise the same
## dispatch branch real, in-contact combat takes, rather than the rarely-hit fallback.

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


## A bare _make_unit() never engages: UnitCombat.strike()'s per-soldier melee branch
## (Unit.INDIVIDUAL_COLLISION and both units engaged/seeded) requires is_engaged() true
## and a populated _sim_soldier_pos, so a test built only on _make_unit() exercises just
## the regiment-formula fallback -- the path real, engaged melee never actually takes.
## This mirrors test_soldier_melee.gd's _unit() pattern (tick_engaged + seed_sim_soldiers)
## so strike() dispatches into the SAME branch live combat does.
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
#
# These stage ENGAGED units (tick_engaged + seed_sim_soldiers, matching
# test_soldier_melee.gd's pattern), not bare Unit.new() instances, so UnitCombat.strike()
# dispatches into the per-soldier SoldierMelee.resolve() path -- the branch every real,
# in-contact melee fight actually takes (Unit.INDIVIDUAL_COLLISION is a hardcoded true
# const) -- rather than the regiment-formula fallback that only runs for a non-engaged or
# unseeded edge case. A first version of this test file used bare units here and passed
# even though order_mode_modifiers() was never wired into SoldierMelee.resolve() at all,
# because bare units always fall through to the (irrelevant, in real combat) formula path.

func test_all_out_attack_striker_deals_more_melee_damage_when_engaged() -> void:
	# Same attacker/defender stat line and the same RNG draws; only the attacker's
	# stance differs, so any damage delta is attributable to ALL_OUT_ATTACK alone.
	var attacker_all_out := _make_engaged_unit(100, Vector2(0, 0), Vector2.DOWN)
	attacker_all_out.team = 0
	attacker_all_out.order_mode = Unit.ORDER_ALL_OUT_ATTACK
	var defender_a := _make_engaged_unit(100, Vector2(0, 10), Vector2.UP)
	defender_a.team = 1
	var before_a: int = defender_a.soldiers

	var attacker_normal := _make_engaged_unit(100, Vector2(0, 0), Vector2.DOWN)
	attacker_normal.team = 0
	var defender_b := _make_engaged_unit(100, Vector2(0, 10), Vector2.UP)
	defender_b.team = 1
	var before_b: int = defender_b.soldiers

	# 16 cadences (empirically checked against 8/12/16/20/25/30/40): enough to open a
	# clear, consistent gap between the two RNG-identical fights while both regiments
	# stay well short of full wipeout -- at 8 cadences the gap hadn't opened yet (both
	# sides landed exactly 8 casualties by coincidence at that low a sample), and past
	# ~30 both regiments start converging back together as they approach annihilation.
	Replay.rng.seed = 12345
	for _k in range(16):
		UnitCombat.strike(attacker_all_out, defender_a)
	var casualties_all_out: int = before_a - defender_a.soldiers

	Replay.rng.seed = 12345   # replay the identical RNG draws against the normal attacker
	for _k in range(16):
		UnitCombat.strike(attacker_normal, defender_b)
	var casualties_normal: int = before_b - defender_b.soldiers

	assert_gt(casualties_all_out, casualties_normal,
		"an engaged all-out-attack striker inflicts more melee casualties than a normal one")


func test_all_out_attack_defender_takes_more_melee_damage_when_engaged() -> void:
	# Same attacker, same RNG draws; only the DEFENDER's stance differs, isolating the
	# defense-penalty half of the tradeoff (the half the bug hid for three rounds).
	var attacker_a := _make_engaged_unit(100, Vector2(0, 0), Vector2.DOWN)
	attacker_a.team = 0
	var defender_all_out := _make_engaged_unit(100, Vector2(0, 10), Vector2.UP)
	defender_all_out.team = 1
	defender_all_out.order_mode = Unit.ORDER_ALL_OUT_ATTACK
	var before_a: int = defender_all_out.soldiers

	var attacker_b := _make_engaged_unit(100, Vector2(0, 0), Vector2.DOWN)
	attacker_b.team = 0
	var defender_normal := _make_engaged_unit(100, Vector2(0, 10), Vector2.UP)
	defender_normal.team = 1
	var before_b: int = defender_normal.soldiers

	# 16 cadences -- see the matching comment on the striker-side test above.
	Replay.rng.seed = 12345
	for _k in range(16):
		UnitCombat.strike(attacker_a, defender_all_out)
	var casualties_exposed: int = before_a - defender_all_out.soldiers

	Replay.rng.seed = 12345
	for _k in range(16):
		UnitCombat.strike(attacker_b, defender_normal)
	var casualties_safe: int = before_b - defender_normal.soldiers

	assert_gt(casualties_exposed, casualties_safe,
		"an engaged defender fighting all-out takes more melee casualties than one that isn't")


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
