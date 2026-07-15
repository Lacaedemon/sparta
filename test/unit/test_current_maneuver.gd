extends GutTest
## Unit.current_maneuver(): a single readable label for the in-progress drill/maneuver,
## distinguishing cases state/formation/order_mode alone can't -- a conversio and a
## centre-pivot both otherwise read as `state: MOVING`. Each case here arms the maneuver via
## its own real entry point (conversio()/quarter_turn()/wheel()/set_frontage(), or the same
## fields Battle._apply_order_cmd's NUDGE branch sets) rather than poking the label logic
## directly, so a future change to how a maneuver is armed is still exercised.


func _make_unit(uid: int = 1, max_soldiers: int = 40) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.uid = uid
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	u.seed_sim_soldiers()   # required by _can_drill() for conversio/quarter_turn/wheel
	return u


func test_defaults_to_idle() -> void:
	var u := _make_unit()
	assert_eq(u.current_maneuver(), Unit.Maneuver.IDLE, "a fresh, unordered unit is idle")


func test_reports_marching_while_moving_with_no_active_drill() -> void:
	var u := _make_unit()
	u.state = Unit.State.MOVING
	assert_eq(u.current_maneuver(), Unit.Maneuver.MARCHING)


func test_reports_fighting_while_fighting_with_no_active_drill() -> void:
	var u := _make_unit()
	u.state = Unit.State.FIGHTING
	assert_eq(u.current_maneuver(), Unit.Maneuver.FIGHTING)


func test_reports_conversio_during_a_standalone_about_face() -> void:
	var u := _make_unit()
	u.conversio()
	assert_true(u.is_order_turning(), "sanity: the drill actually armed")
	assert_eq(u.current_maneuver(), Unit.Maneuver.CONVERSIO)


func test_reports_quarter_turn_during_a_quarter_turn() -> void:
	var u := _make_unit()
	u.quarter_turn(1)
	assert_true(u.is_order_turning(), "sanity: the drill actually armed")
	assert_eq(u.current_maneuver(), Unit.Maneuver.QUARTER_TURN)


func test_distinguishes_conversio_from_quarter_turn() -> void:
	# The concrete case this closes: both look identical as state: MOVING, and both set
	# is_order_turning() true -- only about_face_goal() (checked inside current_maneuver())
	# actually tells them apart.
	var reversing := _make_unit(1)
	reversing.conversio()
	var turning := _make_unit(2)
	turning.quarter_turn(1)
	assert_ne(reversing.current_maneuver(), turning.current_maneuver(),
		"a conversio and a quarter-turn must report distinct maneuver labels")
	assert_eq(reversing.current_maneuver(), Unit.Maneuver.CONVERSIO)
	assert_eq(turning.current_maneuver(), Unit.Maneuver.QUARTER_TURN)


func test_reports_wheeling_during_a_wheel() -> void:
	var u := _make_unit()
	u.wheel(1)
	assert_true(u.is_wheeling(), "sanity: the wheel actually armed")
	assert_eq(u.current_maneuver(), Unit.Maneuver.WHEELING)


func test_reports_nudge_sidestep_for_left_and_right() -> void:
	for dir in [Unit.NUDGE_LEFT, Unit.NUDGE_RIGHT]:
		var u := _make_unit()
		u.set_current_order(Order.new_nudge(dir))
		u.has_move_target = true
		assert_eq(u.current_maneuver(), Unit.Maneuver.NUDGE_SIDESTEP,
			"nudge dir %d should read as a sidestep" % dir)


func test_reports_nudge_backstep() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_nudge(Unit.NUDGE_BACK))
	u.has_move_target = true
	assert_eq(u.current_maneuver(), Unit.Maneuver.NUDGE_BACKSTEP)


func test_reports_nudge_forward_step() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_nudge(Unit.NUDGE_FORWARD))
	u.has_move_target = true
	assert_eq(u.current_maneuver(), Unit.Maneuver.NUDGE_FORWARD_STEP)


func test_nudge_order_alone_is_not_enough_without_has_move_target() -> void:
	# A nudge order that already arrived (has_move_target cleared) is done -- it must not
	# keep reporting a nudge maneuver just because current_order is still the stale NUDGE.
	var u := _make_unit()
	u.set_current_order(Order.new_nudge(Unit.NUDGE_LEFT))
	u.has_move_target = false
	assert_ne(u.current_maneuver(), Unit.Maneuver.NUDGE_SIDESTEP)


func test_reports_cycle_charge_stance() -> void:
	var u := _make_unit()
	u.order_mode = Unit.ORDER_CYCLE_CHARGE
	assert_eq(u.current_maneuver(), Unit.Maneuver.CYCLE_CHARGE)


func test_cycle_charge_does_not_mask_a_more_specific_active_drill() -> void:
	# The stance can coexist with MOVING/FIGHTING, but a real turn/wheel in progress is more
	# specific and must still win -- matches the exploration's precedence note that cycle-charge
	# is an independent axis, not a top-priority label.
	var u := _make_unit()
	u.order_mode = Unit.ORDER_CYCLE_CHARGE
	u.wheel(1)
	assert_eq(u.current_maneuver(), Unit.Maneuver.WHEELING,
		"an active wheel outranks the cycle-charge stance label")


func test_reports_file_double_widen_on_the_exact_tick_only() -> void:
	var u := _make_unit(1, 80)
	u.set_frontage(4)   # establish a known baseline file count first
	u.set_frontage(8)   # widen: 8 > 4
	assert_eq(u.current_maneuver(), Unit.Maneuver.FILE_DOUBLE_WIDEN)
	await get_tree().physics_frame
	assert_ne(u.current_maneuver(), Unit.Maneuver.FILE_DOUBLE_WIDEN,
		"the reshape label is scoped to the tick it applied, not held indefinitely")


func test_reports_file_double_deepen_on_the_exact_tick_only() -> void:
	var u := _make_unit(1, 80)
	u.set_frontage(8)
	u.set_frontage(4)   # deepen: 4 < 8
	assert_eq(u.current_maneuver(), Unit.Maneuver.FILE_DOUBLE_DEEPEN)
	await get_tree().physics_frame
	assert_ne(u.current_maneuver(), Unit.Maneuver.FILE_DOUBLE_DEEPEN,
		"the reshape label is scoped to the tick it applied, not held indefinitely")


func test_reports_countermarch_during_the_whole_composite() -> void:
	var u := _make_unit()
	u.countermarch(Unit.CountermarchVariant.CHORAL)
	assert_true(u.is_order_turning(), "sanity: the drill actually armed its about-face phase")
	assert_eq(u.current_maneuver(), Unit.Maneuver.COUNTERMARCH,
		"a countermarch's opening about-face must not read as a bare CONVERSIO")


func test_countermarch_outranks_the_bare_about_face_label() -> void:
	# Both build an identical Order.Type.ABOUT_FACE turn leaf under the hood
	# (about_face_goal() can't tell them apart) -- only current_order.countermarch_variant does.
	var reversing := _make_unit(1)
	reversing.conversio()
	var countermarching := _make_unit(2)
	countermarching.countermarch(Unit.CountermarchVariant.MACEDONIAN)
	assert_eq(reversing.current_maneuver(), Unit.Maneuver.CONVERSIO)
	assert_eq(countermarching.current_maneuver(), Unit.Maneuver.COUNTERMARCH,
		"a countermarch's own about-face phase must not collapse to the bare conversio label")


func test_countermarch_variant_accessor_reads_the_armed_variant() -> void:
	var u := _make_unit()
	assert_eq(u.countermarch_variant(), -1, "no current order: not a countermarch")
	u.countermarch(Unit.CountermarchVariant.LACONIAN)
	assert_eq(u.countermarch_variant(), Unit.CountermarchVariant.LACONIAN)


func test_set_frontage_to_the_same_effective_count_is_not_a_reshape() -> void:
	# Re-applying the pending FRONTAGE order on the same tick is idempotent by design
	# (frontage_anchor_offset's own docstring) -- a no-op re-application must not spuriously
	# report a NEW reshape maneuver. Establish the baseline and let its own reshape stamp
	# age out (a physics tick) before the idempotent re-application under test, so this
	# isn't just re-observing the baseline-establishing call's own genuine reshape.
	var u := _make_unit(1, 80)
	u.set_frontage(6)
	await get_tree().physics_frame
	u.set_frontage(6)   # idempotent re-application: same effective count as already-set
	assert_ne(u.current_maneuver(), Unit.Maneuver.FILE_DOUBLE_WIDEN)
	assert_ne(u.current_maneuver(), Unit.Maneuver.FILE_DOUBLE_DEEPEN)
