extends GutTest
## Unit tests for the graded soldier_brace() formula and its BRACE_SETTLE_TIME timing
## gate (docs/combat-model.md "Bracing" -- the graded br formula, replacing the old
## binary switch). See test_soldier_melee.gd for the downstream knockback/displacement
## consumers, and test_soldier_combat.gd for the weapon-differentiated brace_capacity.


func _make_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 20
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


## Engage the unit the same way _unit() helpers elsewhere latch is_engaged() true --
## without this, soldier_brace() is unconditionally 0 regardless of order/motion.
func _engage(u: Unit) -> void:
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)


func test_not_engaged_is_unbraced() -> void:
	var u := _make_unit()
	assert_almost_eq(u.soldier_brace(), 0.0, 0.001, "never engaged, no brace at all")


func test_engaged_baseline_is_at_attention_not_fully_set() -> void:
	var u := _make_unit()
	_engage(u)
	assert_almost_eq(u.soldier_brace(), Unit.BRACE_BASELINE_ENGAGED, 0.001,
		"merely engaged (no explicit brace order) is the 'at attention' baseline, not fully set")


func test_skirmish_forces_zero_even_while_engaged() -> void:
	var u := _make_unit()
	_engage(u)
	u.order_mode = Unit.ORDER_SKIRMISH
	assert_almost_eq(u.soldier_brace(), 0.0, 0.001, "a skirmish line never braces")


func test_motion_reduces_brace_below_the_stationary_baseline() -> void:
	var u := _make_unit()
	_engage(u)
	u._current_speed = Unit.BRACE_MOTION_REF_SPEED   # full-speed march
	assert_lt(u.soldier_brace(), Unit.BRACE_BASELINE_ENGAGED,
		"a unit still under way is less set than one standing still")


func test_brace_order_alone_grants_no_bonus_before_settling() -> void:
	var u := _make_unit()
	_engage(u)
	u.order_mode = Unit.ORDER_BRACE
	# No tick_brace_settle() call yet -- _brace_settled_time stays at its initial 0.
	assert_almost_eq(u.soldier_brace(), Unit.BRACE_BASELINE_ENGAGED, 0.001,
		"ordering Brace does not grant the set bonus instantly -- must settle first (T_post)")


func test_brace_order_reaches_the_ceiling_once_settled() -> void:
	var u := _make_unit()
	_engage(u)
	u.order_mode = Unit.ORDER_BRACE
	# current_speed defaults to 0, so every settle tick counts toward BRACE_SETTLE_TIME.
	u.tick_brace_settle(Unit.BRACE_SETTLE_TIME + 0.01)
	var expected: float = clampf(
			Unit.BRACE_BASELINE_ENGAGED + Unit.BRACE_SET_BONUS, 0.0, 1.0)
	assert_almost_eq(u.soldier_brace(), expected, 0.001,
		"held still and ordered to brace for the full settle window reaches the ceiling")


func test_settle_timer_resets_the_instant_the_unit_moves() -> void:
	var u := _make_unit()
	_engage(u)
	u.order_mode = Unit.ORDER_BRACE
	u.tick_brace_settle(Unit.BRACE_SETTLE_TIME + 0.01)
	assert_gte(u._brace_settled_time, Unit.BRACE_SETTLE_TIME, "sanity: settled first")
	u._current_speed = Unit.BRACE_STILL_SPEED + 1.0   # now moving, not stationary
	u.tick_brace_settle(0.01)
	assert_almost_eq(u._brace_settled_time, 0.0, 0.001,
		"breaking stillness resets the settle timer -- a charge that catches a still-moving line unset")


func test_settle_timer_resets_when_the_order_changes() -> void:
	var u := _make_unit()
	_engage(u)
	u.order_mode = Unit.ORDER_BRACE
	u.tick_brace_settle(Unit.BRACE_SETTLE_TIME + 0.01)
	u.order_mode = Unit.ORDER_HOLD
	u.tick_brace_settle(0.01)
	assert_almost_eq(u._brace_settled_time, 0.0, 0.001,
		"leaving the brace order resets the settle timer even while still stationary")


func test_tight_formation_adds_a_margin() -> void:
	var loose := _make_unit()
	_engage(loose)
	loose.formation_mode = Unit.FORMATION_NORMAL
	var tight := _make_unit()
	_engage(tight)
	tight.formation_mode = Unit.FORMATION_TIGHT
	assert_gt(tight.soldier_brace(), loose.soldier_brace(),
		"a tight formation braces harder than the same posture in a looser one")


func test_brace_never_exceeds_one_even_at_the_ceiling_in_tight_formation() -> void:
	var u := _make_unit()
	_engage(u)
	u.formation_mode = Unit.FORMATION_TIGHT
	u.order_mode = Unit.ORDER_BRACE
	u.tick_brace_settle(Unit.BRACE_SETTLE_TIME + 0.01)
	assert_lte(u.soldier_brace(), 1.0, "clipped to [0, 1] even when every bonus stacks")


func test_brace_order_still_zero_while_skirmishing() -> void:
	var u := _make_unit()
	_engage(u)
	u.order_mode = Unit.ORDER_SKIRMISH
	u.tick_brace_settle(Unit.BRACE_SETTLE_TIME + 0.01)
	assert_almost_eq(u.soldier_brace(), 0.0, 0.001,
		"ORDER_SKIRMISH forces zero regardless of any settled brace state")
