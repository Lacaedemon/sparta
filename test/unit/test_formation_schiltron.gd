extends GutTest
## Schiltron: the cavalry-specialist hollow-square variant (#488), distinct from the
## orbis (plain FORMATION_SQUARE). Both share the same hollow-square geometry (a real
## square grid with the perimeter facing outward -- test_formation_square.gd covers that
## shared machinery), so this file focuses on what makes them DISTINCT stances rather than
## one generic square: schiltron braces a cavalry charge harder and hits softer in return;
## orbis is the last-stand ring, with a morale-erosion-resistance bonus schiltron lacks.

const FRONT := Vector2(0, 100)    # ahead of a unit facing DOWN
const SIDE := Vector2(100, 0)     # to its flank
const REAR := Vector2(0, -100)    # behind it


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _attacker_at(p: Vector2) -> Unit:
	var a: Unit = Unit.new()
	add_child_autofree(a)
	a.position = p
	return a


func _cavalry_charging_from(target: Unit, from: Vector2) -> Unit:
	var cav := _attacker_at(from)
	cav.is_cavalry = true
	var dir: Vector2 = (target.position - cav.position).normalized()
	cav._approach_velocity = dir * Unit.CHARGE_REFERENCE_SPEED
	return cav


# --- mode wiring ----------------------------------------------------------------

func test_set_formation_records_schiltron_and_close_order_footprint() -> void:
	var u := _make_unit()
	var base := u._base_separation_radius
	u.set_formation(Unit.FORMATION_SCHILTRON)
	assert_eq(u.formation_mode, Unit.FORMATION_SCHILTRON, "the mode is set")
	assert_almost_eq(u.separation_radius, base * Unit.TIGHT_SEPARATION_SCALE, 0.001,
		"schiltron closes ranks to the tight footprint, same as orbis")
	assert_almost_eq(u.spacing_scale, 1.0, 0.001, "and holds the close-order grid spacing")


func test_formation_summary_labels_schiltron() -> void:
	var u := _make_unit()
	u.set_formation(Unit.FORMATION_SCHILTRON)
	assert_eq(u.formation_summary(), "Schiltron", "the HUD label reads Schiltron")


# --- shared hollow-square geometry (both variants alike) ------------------------

func test_in_square_is_true_for_both_variants() -> void:
	var orbis := _make_unit()
	orbis.set_formation(Unit.FORMATION_SQUARE)
	var schiltron := _make_unit()
	schiltron.set_formation(Unit.FORMATION_SCHILTRON)
	assert_true(orbis.in_square(), "orbis counts as a square")
	assert_true(schiltron.in_square(), "schiltron counts as a square too")


func test_in_schiltron_distinguishes_the_variant() -> void:
	var orbis := _make_unit()
	orbis.set_formation(Unit.FORMATION_SQUARE)
	var schiltron := _make_unit()
	schiltron.set_formation(Unit.FORMATION_SCHILTRON)
	assert_false(orbis.in_schiltron(), "orbis is not the schiltron variant")
	assert_true(schiltron.in_schiltron(), "schiltron reports itself")


func test_schiltron_lays_out_the_same_square_grid_as_orbis() -> void:
	var orbis := _make_unit()
	orbis.set_formation(Unit.FORMATION_SQUARE)
	var schiltron := _make_unit()
	schiltron.set_formation(Unit.FORMATION_SCHILTRON)
	var n: int = orbis.soldiers
	assert_eq(schiltron.formation_files(n), orbis.formation_files(n),
		"schiltron uses the same square file count as orbis")
	var orbis_slots := orbis.soldier_world_slots(n)
	var schiltron_slots := schiltron.soldier_world_slots(n)
	for i in range(n):
		assert_true(orbis_slots[i].is_equal_approx(schiltron_slots[i]),
			"slot %d matches between orbis and schiltron (shared geometry)" % i)


func test_schiltron_perimeter_soldiers_face_outward_too() -> void:
	var u := _make_unit()
	u.set_formation(Unit.FORMATION_SCHILTRON)
	var n: int = u.soldiers
	var positions := u.soldier_world_slots(n)
	var facings := u.soldier_world_facings(n)
	var files: int = UnitFormation.square_files(n)
	var centroid := Vector2.ZERO
	for p in positions:
		centroid += p
	centroid /= float(n)
	var checked := 0
	for i in range(n):
		if not UnitFormation.square_is_perimeter(i, n, files):
			continue
		var outward: Vector2 = (positions[i] - centroid)
		if outward.length() < 0.5:
			continue
		checked += 1
		assert_gt(facings[i].dot(outward.normalized()), 0.5,
			"schiltron's perimeter soldier %d faces away from the block centre" % i)
	assert_gt(checked, 20, "spot-checked a meaningful number of perimeter soldiers")


func test_schiltron_takes_no_flank_or_rear_multiplier() -> void:
	# Schiltron shares orbis's defining trait: all-around defence, no weak side.
	var u := _make_unit()
	u.set_formation(Unit.FORMATION_SCHILTRON)
	var front := UnitCombat.flank_multiplier(u, _attacker_at(FRONT))
	var flank := UnitCombat.flank_multiplier(u, _attacker_at(SIDE))
	var rear := UnitCombat.flank_multiplier(u, _attacker_at(REAR))
	assert_almost_eq(front, 1.0, 0.001, "frontal is x1.0")
	assert_almost_eq(flank, front, 0.001, "schiltron's flank equals its front (no bonus)")
	assert_almost_eq(rear, front, 0.001, "schiltron's rear equals its front (no bonus)")


func test_schiltron_crawls_like_orbis() -> void:
	assert_almost_eq(Unit.SQUARE_MOVE_FACTOR, Unit.SQUARE_MOVE_FACTOR, 0.001,
		"both variants share the same mobility penalty (formation_speed_factor)")
	var u := _make_unit()
	u.set_formation(Unit.FORMATION_SCHILTRON)
	assert_almost_eq(u.formation_speed_factor(), Unit.SQUARE_MOVE_FACTOR, 0.001,
		"schiltron's pace cap matches orbis's -- mobility isn't what distinguishes them")


# --- the distinguishing trade-off: schiltron braces harder, hits softer ---------

func test_schiltron_braces_a_charge_harder_than_orbis() -> void:
	var orbis := _make_unit()
	orbis.set_formation(Unit.FORMATION_SQUARE)
	var schiltron := _make_unit()
	schiltron.set_formation(Unit.FORMATION_SCHILTRON)
	for from: Vector2 in [FRONT, SIDE, REAR]:
		var orbis_mult := UnitCombat.charge_multiplier(_cavalry_charging_from(orbis, from), orbis)
		var schiltron_mult := UnitCombat.charge_multiplier(
			_cavalry_charging_from(schiltron, from), schiltron)
		assert_lt(schiltron_mult, 1.0, "a charge into the schiltron backfires from %s" % from)
		assert_lt(schiltron_mult, orbis_mult,
			"schiltron's backfire from %s is harsher than orbis's -- the cavalry specialist" % from)
		assert_gte(schiltron_mult, Unit.SCHILTRON_CHARGE_FLOOR - 0.001,
			"schiltron's backfire is floored at SCHILTRON_CHARGE_FLOOR")


func test_schiltron_charge_backfire_is_direction_independent() -> void:
	var u := _make_unit()
	u.set_formation(Unit.FORMATION_SCHILTRON)
	var from_front := UnitCombat.charge_multiplier(_cavalry_charging_from(u, FRONT), u)
	var from_rear := UnitCombat.charge_multiplier(_cavalry_charging_from(u, REAR), u)
	assert_almost_eq(from_rear, from_front, 0.001,
		"schiltron braces a rear charge exactly like a front charge -- no open side")


func test_schiltron_hits_softer_than_orbis() -> void:
	var orbis := _make_unit()
	orbis.set_formation(Unit.FORMATION_SQUARE)
	var schiltron := _make_unit()
	schiltron.set_formation(Unit.FORMATION_SCHILTRON)
	assert_almost_eq(orbis.formation_attack_factor(), Unit.SQUARE_ATTACK_FACTOR, 0.001)
	assert_almost_eq(schiltron.formation_attack_factor(), Unit.SCHILTRON_ATTACK_FACTOR, 0.001)
	assert_lt(schiltron.formation_attack_factor(), orbis.formation_attack_factor(),
		"schiltron pays a deeper offence penalty than orbis for its harder brace")


func test_schiltron_charge_brace_is_the_stronger_specialist_trade() -> void:
	assert_lt(Unit.SCHILTRON_CHARGE_FLOOR, Unit.SQUARE_CHARGE_FLOOR,
		"schiltron's floor sits below orbis's -- a harder-braced backfire")
	assert_gt(Unit.SCHILTRON_CHARGE_BACKFIRE, Unit.SQUARE_CHARGE_BACKFIRE,
		"schiltron's backfire scale exceeds orbis's")


# --- the distinguishing trade-off: orbis holds its nerve, schiltron does not ----

func test_orbis_erodes_morale_slower_than_normal() -> void:
	var normal := _make_unit()
	var orbis := _make_unit()
	orbis.set_formation(Unit.FORMATION_SQUARE)
	assert_almost_eq(normal.formation_morale_erosion_factor(), 1.0, 0.001,
		"a normal-stance unit takes full morale erosion")
	assert_almost_eq(orbis.formation_morale_erosion_factor(), Unit.ORBIS_MORALE_EROSION_RESIST,
		0.001, "orbis resists erosion")
	assert_lt(Unit.ORBIS_MORALE_EROSION_RESIST, 1.0, "the resistance is a real reduction")


func test_schiltron_has_no_morale_bonus() -> void:
	# The distinguishing trait split: schiltron is the cavalry specialist, not a
	# last-stand stance, so it takes morale erosion like any other formation.
	var schiltron := _make_unit()
	schiltron.set_formation(Unit.FORMATION_SCHILTRON)
	assert_almost_eq(schiltron.formation_morale_erosion_factor(), 1.0, 0.001,
		"schiltron has no morale-erosion resistance -- that's orbis's distinguishing trait")


func test_register_casualties_erodes_orbis_morale_slower_than_schiltron() -> void:
	# End-to-end through the real casualty-registration path (not just the pure factor).
	var orbis := _make_unit()
	orbis.set_formation(Unit.FORMATION_SQUARE)
	orbis.soldiers = orbis.max_soldiers
	orbis.morale = 100.0
	var schiltron := _make_unit()
	schiltron.set_formation(Unit.FORMATION_SCHILTRON)
	schiltron.soldiers = schiltron.max_soldiers
	schiltron.morale = 100.0

	UnitCombat.register_casualties(orbis, 10, null, 1.0)
	UnitCombat.register_casualties(schiltron, 10, null, 1.0)

	var orbis_loss: float = 100.0 - orbis.morale
	var schiltron_loss: float = 100.0 - schiltron.morale
	assert_gt(orbis_loss, 0.0, "orbis still loses some morale from casualties")
	assert_lt(orbis_loss, schiltron_loss,
		"the same casualties erode orbis's morale less than schiltron's")


# --- hotkey / control-bar wiring -------------------------------------------------

func _key_event(keycode: int, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.shift_pressed = shift
	return ev


class _StubBattle:
	extends Node
	var last_formation: int = -999
	func enqueue_formation(_uids: Array, formation: int) -> void:
		last_formation = formation


func _sm_with_unit(u: Unit):
	const SM = preload("res://scripts/SelectionManager.gd")
	var battle := _StubBattle.new()
	add_child_autofree(battle)
	var sm = SM.new()
	battle.add_child(sm)
	sm._select(u)
	return [sm, battle]


func test_shift_o_key_dispatches_to_the_schiltron_toggle() -> void:
	# Every plain letter is claimed (I went to rank-relief toggle, #612), so schiltron
	# shares O's key with Shift -- plain O still reaches orbis (see the next test).
	var u := _make_unit()   # Normal
	var pair = _sm_with_unit(u)
	var handled: bool = pair[0]._dispatch_key(_key_event(KEY_O, true))
	assert_true(handled, "Shift+O is a known hotkey")
	assert_eq(pair[1].last_formation, Unit.FORMATION_SCHILTRON,
		"pressing Shift+O forms the schiltron directly")


func test_plain_o_key_still_dispatches_to_orbis_not_schiltron() -> void:
	# Regression guard: adding Shift+O for schiltron must not disturb plain O's
	# existing orbis behaviour.
	var u := _make_unit()   # Normal
	var pair = _sm_with_unit(u)
	var handled: bool = pair[0]._dispatch_key(_key_event(KEY_O, false))
	assert_true(handled, "plain O is still a known hotkey")
	assert_eq(pair[1].last_formation, Unit.FORMATION_SQUARE,
		"pressing plain O still forms orbis, not schiltron")


func test_toggle_schiltron_jumps_straight_to_schiltron_from_any_mode() -> void:
	var u := _make_unit()   # starts Normal
	var pair = _sm_with_unit(u)
	pair[0]._toggle_schiltron()
	assert_eq(pair[1].last_formation, Unit.FORMATION_SCHILTRON,
		"I jumps to Schiltron from Normal in one press")


func test_toggle_schiltron_drops_back_to_normal_when_already_in_schiltron() -> void:
	var u := _make_unit()
	u.set_formation(Unit.FORMATION_SCHILTRON)
	var pair = _sm_with_unit(u)
	pair[0]._toggle_schiltron()
	assert_eq(pair[1].last_formation, Unit.FORMATION_NORMAL,
		"I on an already-schiltroned unit toggles back to Normal")


func test_schiltron_is_not_in_the_t_cycle() -> void:
	# Schiltron is a direct-select stance (like Shield Wall / Testudo), not part of the
	# short T-cycle -- matches the existing SHIELD_WALL/TESTUDO exclusion.
	const SM = preload("res://scripts/SelectionManager.gd")
	assert_false(SM.FORMATION_CYCLE.has(Unit.FORMATION_SCHILTRON),
		"the T-cycle does not include Schiltron")


func test_control_bar_menu_lists_schiltron() -> void:
	const HUDScript = preload("res://scripts/HUD.gd")
	var hud = HUDScript.new()
	add_child_autofree(hud)
	assert_true(hud._FORMATION_MENU_ORDER.has(Unit.FORMATION_SCHILTRON),
		"the control-bar formation menu includes Schiltron")
	assert_eq(hud._FORMATION_NAMES.get(Unit.FORMATION_SCHILTRON, ""), "Schiltron",
		"the control-bar label reads Schiltron")
