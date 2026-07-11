extends GutTest
## Knockback focus (Battle.OrderMode.KNOCKBACK_FOCUS): an attack-order subtype that trades
## damage for a much bigger, more probable push-back. UnitCombat.order_mode_modifiers
## discounts the STRIKER's own effective attack (KNOCKBACK_FOCUS_DAMAGE_MULT) when it's the
## one fighting this way -- no defense-side effect, unlike ALL_OUT_ATTACK/WEDGE_CHARGE, since
## this stance costs offense only. SoldierMelee.resolve() separately boosts the knockback
## impulse (SoldierCombat.KNOCKBACK_FOCUS_IMPULSE_MULT) whenever the ATTACKER is in this
## stance, which also raises the prone-chance draw (one multiplier drives both "harder" and
## "more likely"). Unit.knockback_push_indefinite is a genuine PER-ORDER parameter (armed via
## Shift+hotkey, not a global Settings toggle -- see SelectionManager._armed_knockback_indefinite
## and Battle._apply_order_cmd) picking between the default "just clear the line" push-distance
## speed cap (SoldierCombat.clear_line_speed_cap) and a much higher "indefinite" one
## (SoldierCombat.KNOCKBACK_FOCUS_INDEFINITE_SPEED_CAP).
##
## Mirrors test_all_out_attack.gd's helpers/structure for the damage-tradeoff half, and
## test_soldier_melee.gd's single/small-regiment knockback pattern (unbraced SKIRMISH
## defender, health pinned high so a strike can't kill and reap the body before it's read)
## for the push-distance half.

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


## Matches test_all_out_attack.gd's _make_engaged_unit: stages a genuinely ENGAGED unit so
## UnitCombat.strike()/SoldierMelee.resolve() dispatch into the per-soldier melee path real,
## in-contact combat actually takes, not the regiment-formula fallback.
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


## The maximum body speed among `u`'s engaged soldiers -- the knockback metric the
## push-distance tests read, robust to which specific soldier index the strike happened
## to land on.
func _max_body_speed(u: Unit) -> float:
	var top: float = 0.0
	for v in u._sim_body_vel:
		top = maxf(top, v.length())
	return top


func before_each() -> void:
	Replay.rng.seed = 12345   # deterministic draws for UnitCombat.strike/SoldierMelee.resolve


# --- order_mode_modifiers: attack_mult only, never defense_mult --------------------------

func test_neither_unit_knockback_focus_gives_no_modifiers() -> void:
	var u := _make_unit()
	var enemy := _make_unit()
	var mods: Vector2 = UnitCombat.order_mode_modifiers(u, enemy)
	assert_almost_eq(mods.x, 1.0, TOL, "no attack discount without KNOCKBACK_FOCUS")
	assert_almost_eq(mods.y, 1.0, TOL, "no defense change without KNOCKBACK_FOCUS")


func test_attacker_knockback_focus_reduces_only_attack_mult() -> void:
	var u := _make_unit()
	u.order_mode = Unit.ORDER_KNOCKBACK_FOCUS
	var enemy := _make_unit()
	var mods: Vector2 = UnitCombat.order_mode_modifiers(u, enemy)
	assert_almost_eq(mods.x, UnitCombat.KNOCKBACK_FOCUS_DAMAGE_MULT, TOL,
		"the striker's own KNOCKBACK_FOCUS discounts its effective attack")
	assert_almost_eq(mods.y, 1.0, TOL,
		"knockback focus is an offense-only tradeoff -- it must not discount the TARGET's defense")


func test_target_knockback_focus_does_not_change_defense_mult() -> void:
	# Unlike ALL_OUT_ATTACK/WEDGE_CHARGE (which key a defense penalty off the TARGET's own
	# stance), knockback focus costs only the wielder's own offense -- a unit fighting a
	# knockback-focus attacker gets no defense discount for it.
	var u := _make_unit()
	var enemy := _make_unit()
	enemy.order_mode = Unit.ORDER_KNOCKBACK_FOCUS
	var mods: Vector2 = UnitCombat.order_mode_modifiers(u, enemy)
	assert_almost_eq(mods.x, 1.0, TOL, "a defender's own stance must not change the attacker's attack")
	assert_almost_eq(mods.y, 1.0, TOL, "knockback focus never discounts the TARGET's defense")


# --- end-to-end: an engaged knockback-focus striker deals less melee damage --------------
#
# Mirrors test_all_out_attack.gd's engaged end-to-end pattern: bare units always fall
# through to the (irrelevant, in real combat) regiment-formula path, so this stages
# genuinely engaged units to exercise the same per-soldier dispatch real combat takes.

func test_knockback_focus_striker_deals_less_melee_damage_when_engaged() -> void:
	var attacker_kb := _make_engaged_unit(100, Vector2(0, 0), Vector2.DOWN)
	attacker_kb.team = 0
	attacker_kb.order_mode = Unit.ORDER_KNOCKBACK_FOCUS
	var defender_a := _make_engaged_unit(100, Vector2(0, 10), Vector2.UP)
	defender_a.team = 1
	var before_a: int = defender_a.soldiers

	var attacker_normal := _make_engaged_unit(100, Vector2(0, 0), Vector2.DOWN)
	attacker_normal.team = 0
	var defender_b := _make_engaged_unit(100, Vector2(0, 10), Vector2.UP)
	defender_b.team = 1
	var before_b: int = defender_b.soldiers

	# 16 cadences: same sample size test_all_out_attack.gd found opens a consistent gap
	# without either regiment nearing full wipeout.
	Replay.rng.seed = 12345
	for _k in range(16):
		UnitCombat.strike(attacker_kb, defender_a)
	var casualties_kb: int = before_a - defender_a.soldiers

	Replay.rng.seed = 12345   # replay the identical RNG draws against the normal attacker
	for _k in range(16):
		UnitCombat.strike(attacker_normal, defender_b)
	var casualties_normal: int = before_b - defender_b.soldiers

	assert_lt(casualties_kb, casualties_normal,
		"an engaged knockback-focus striker inflicts fewer melee casualties than a normal one")


# --- knockback intensity/probability: the impulse multiplier, in isolation ---------------

func test_knockback_focus_impulse_mult_boosts_the_raw_impulse() -> void:
	var base: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0)
	var boosted: float = SoldierCombat.knockback_impulse(
			1.0, 0.0, 1.0, 1.0, SoldierCombat.KNOCKBACK_FOCUS_IMPULSE_MULT)
	assert_gt(boosted, base, "KNOCKBACK_FOCUS_IMPULSE_MULT raises the raw impulse magnitude")


func test_knockback_focus_impulse_mult_boosts_prone_chance() -> void:
	# Feeding the boosted impulse into the SAME prone_chance check the melee resolver
	# already calls is what makes "higher intensity" also mean "higher probability" --
	# one multiplier drives both, with no separate knob needed.
	var mass: float = 1.0
	var brace: float = 0.0
	var base_impulse: float = SoldierCombat.knockback_impulse(1.0, 0.0, mass, 1.0)
	var boosted_impulse: float = SoldierCombat.knockback_impulse(
			1.0, 0.0, mass, 1.0, SoldierCombat.KNOCKBACK_FOCUS_IMPULSE_MULT)
	var base_chance: float = SoldierCombat.prone_chance(base_impulse, mass, brace)
	var boosted_chance: float = SoldierCombat.prone_chance(boosted_impulse, mass, brace)
	assert_gt(boosted_chance, base_chance,
		"a knockback-focus attacker's bigger impulse makes felling the defender more likely")


# --- the push-distance order parameter: pure cap math -------------------------------------

func test_indefinite_speed_cap_exceeds_the_clear_line_cap_for_realistic_distances() -> void:
	# Realistic engaged-unit front depths (a few dozen world units at most -- see
	# Unit._front_depth's own attack_range*0.5 cap) keep clear_line_speed_cap well under
	# KNOCKBACK_FOCUS_INDEFINITE_SPEED_CAP, so "indefinite" always reaches further than
	# "just clear the line" once the raw impulse is big enough to matter.
	var a := _make_engaged_unit(12, Vector2(0, 0), Vector2.DOWN)
	var b := _make_engaged_unit(12, Vector2(0, 10), Vector2.UP)
	var clear_distance: float = a._front_depth() + b._front_depth()
	var clear_cap: float = SoldierCombat.clear_line_speed_cap(clear_distance, SoldierBodies.BODY_ACCEL_FLOOR)
	assert_gt(SoldierCombat.KNOCKBACK_FOCUS_INDEFINITE_SPEED_CAP, clear_cap,
		"the indefinite push-distance variant's cap clears the 'just clear the line' cap for a realistic engaged distance")


func test_clear_line_speed_cap_grows_with_distance() -> void:
	var near: float = SoldierCombat.clear_line_speed_cap(5.0, SoldierBodies.BODY_ACCEL_FLOOR)
	var far: float = SoldierCombat.clear_line_speed_cap(40.0, SoldierBodies.BODY_ACCEL_FLOOR)
	assert_gt(far, near, "a bigger combined front depth raises the 'just clear the line' cap")


func test_capped_knockback_velocity_travels_further_under_the_indefinite_cap() -> void:
	# A single, deterministic proof that the two push-distance variants actually diverge:
	# an impulse big enough to exceed the modest "clear the line" cap but still well under
	# the "indefinite" one ends up capped at two different, measurably different speeds.
	var clear_cap: float = 30.0
	var indefinite_cap: float = SoldierCombat.KNOCKBACK_FOCUS_INDEFINITE_SPEED_CAP
	var big_impulse := Vector2(0.0, 90.0)   # exceeds clear_cap, well under indefinite_cap
	var v_clear: Vector2 = SoldierCombat.capped_knockback_velocity(Vector2.ZERO, big_impulse, clear_cap)
	var v_indefinite: Vector2 = SoldierCombat.capped_knockback_velocity(
			Vector2.ZERO, big_impulse, indefinite_cap)
	assert_almost_eq(v_clear.length(), clear_cap, TOL, "clearing the line caps the shove at the modest distance")
	assert_gt(v_indefinite.length(), v_clear.length(),
		"the indefinite variant lets the same strike shove the defender measurably further")


# --- the push-distance order parameter: end-to-end through SoldierMelee.resolve() --------

func test_knockback_focus_pushes_the_defender_back_harder_than_a_normal_attacker() -> void:
	# Same attacker/defender geometry and RNG draws in every run -- an unbraced (SKIRMISH)
	# defender with health pinned high so a strike can't kill and reap the body before its
	# velocity is read, matching test_soldier_melee.gd's own knockback pattern. Only the
	# attacker's stance (and, for the two knockback-focus runs, knockback_push_indefinite)
	# differs, so any speed delta is attributable to those alone.
	Replay.rng.seed = 12345
	var attacker_normal := _make_engaged_unit(12, Vector2(0, 0), Vector2.DOWN)
	var defender_normal := _make_engaged_unit(12, Vector2(0, 10), Vector2.UP)
	defender_normal.order_mode = Unit.ORDER_SKIRMISH
	for i in range(defender_normal._sim_soldier_hp.size()):
		defender_normal._sim_soldier_hp[i] = 9999.0
	SoldierMelee.resolve(attacker_normal, defender_normal)
	var speed_normal: float = _max_body_speed(defender_normal)

	Replay.rng.seed = 12345
	var attacker_clear := _make_engaged_unit(12, Vector2(0, 0), Vector2.DOWN)
	attacker_clear.order_mode = Unit.ORDER_KNOCKBACK_FOCUS
	attacker_clear.knockback_push_indefinite = false
	var defender_clear := _make_engaged_unit(12, Vector2(0, 10), Vector2.UP)
	defender_clear.order_mode = Unit.ORDER_SKIRMISH
	for i in range(defender_clear._sim_soldier_hp.size()):
		defender_clear._sim_soldier_hp[i] = 9999.0
	SoldierMelee.resolve(attacker_clear, defender_clear)
	var speed_clear: float = _max_body_speed(defender_clear)

	Replay.rng.seed = 12345
	var attacker_indefinite := _make_engaged_unit(12, Vector2(0, 0), Vector2.DOWN)
	attacker_indefinite.order_mode = Unit.ORDER_KNOCKBACK_FOCUS
	attacker_indefinite.knockback_push_indefinite = true
	var defender_indefinite := _make_engaged_unit(12, Vector2(0, 10), Vector2.UP)
	defender_indefinite.order_mode = Unit.ORDER_SKIRMISH
	for i in range(defender_indefinite._sim_soldier_hp.size()):
		defender_indefinite._sim_soldier_hp[i] = 9999.0
	SoldierMelee.resolve(attacker_indefinite, defender_indefinite)
	var speed_indefinite: float = _max_body_speed(defender_indefinite)

	assert_gt(speed_clear, speed_normal,
		"a knockback-focus attacker pushes the defender back harder than a normal one, even at the default 'clear the line' setting")
	assert_gt(speed_indefinite, speed_normal,
		"the 'indefinite' push-distance variant also pushes harder than a normal attacker")
	# Not strictly greater than speed_clear: whether "indefinite" measurably outpushes
	# "clear the line" depends on whether this cadence's land roll cleared the (lower)
	# clear-line cap in the first place -- see the deterministic cap-math tests above for
	# an unconditional proof the two variants diverge once the raw impulse is big enough.
	assert_gte(speed_indefinite, speed_clear,
		"the indefinite variant never pushes less far than the default clear-the-line one")


# --- Unit.knockback_push_indefinite defaults -----------------------------------------------

func test_knockback_push_indefinite_defaults_to_false() -> void:
	var u := _make_unit()
	assert_false(u.knockback_push_indefinite,
		"a fresh unit defaults to the common 'just clear the line' push variant")


# --- OrderMode plumbing: mirror constants, names, hotkeys stay in sync --------------------

func test_order_knockback_focus_mirrors_battle_order_mode() -> void:
	assert_eq(Unit.ORDER_KNOCKBACK_FOCUS, BattleScript.OrderMode.KNOCKBACK_FOCUS,
		"Unit's mirrored int constant matches Battle.OrderMode.KNOCKBACK_FOCUS")


func test_knockback_focus_has_a_name_and_a_hotkey_slug() -> void:
	assert_true(BattleScript.ORDER_MODE_NAMES.has(BattleScript.OrderMode.KNOCKBACK_FOCUS),
		"KNOCKBACK_FOCUS has a human-readable HUD name")
	var slugs: Array = []
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		slugs.append(entry["slug"])
	assert_true(slugs.has("knockback_focus"), "KNOCKBACK_FOCUS has a rebindable hotkey slug")


func test_knockback_focus_hotkey_default_is_not_reused() -> void:
	var seen: Dictionary = {}
	for slug in SettingsScript.DEFAULT_ORDER_BINDINGS:
		var key: int = SettingsScript.DEFAULT_ORDER_BINDINGS[slug]
		assert_false(seen.has(key),
			"default hotkey %s is already bound to %s" % [key, seen.get(key)])
		seen[key] = slug
