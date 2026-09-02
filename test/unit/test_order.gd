extends GutTest
## Order value type (docs/orders-queue-design.md phases 1-3): pure, node-free tests
## for the enum-name tables, the readable describe() string, and the constructor helpers used
## to build each order kind.


func test_type_name_maps_every_known_type() -> void:
	assert_eq(Order.type_name(Order.Type.MOVE), "MOVE")
	assert_eq(Order.type_name(Order.Type.ATTACK), "ATTACK")
	assert_eq(Order.type_name(Order.Type.RELIEF), "RELIEF")
	assert_eq(Order.type_name(Order.Type.SUPPORT), "SUPPORT")
	assert_eq(Order.type_name(Order.Type.WHEEL), "WHEEL")
	assert_eq(Order.type_name(Order.Type.NUDGE), "NUDGE")
	assert_eq(Order.type_name(Order.Type.FORMATION), "FORMATION")
	assert_eq(Order.type_name(Order.Type.FRONTAGE), "FRONTAGE")
	assert_eq(Order.type_name(Order.Type.ABOUT_FACE), "ABOUT_FACE")
	assert_eq(Order.type_name(Order.Type.QUARTER_TURN), "QUARTER_TURN")
	assert_eq(Order.type_name(Order.Type.STANCE), "STANCE")
	assert_eq(Order.type_name(Order.Type.FORM_UP), "FORM_UP")
	assert_eq(Order.type_name(Order.Type.SWITCH_WEAPON), "SWITCH_WEAPON")
	assert_eq(Order.type_name(Order.Type.COMBO), "COMBO")


func test_phase_name_maps_every_known_phase() -> void:
	assert_eq(Order.phase_name(Order.Phase.NONE), "NONE")
	assert_eq(Order.phase_name(Order.Phase.TURN), "TURN")
	assert_eq(Order.phase_name(Order.Phase.MARCH), "MARCH")
	assert_eq(Order.phase_name(Order.Phase.REFORM), "REFORM")


func test_type_name_falls_back_for_an_unmapped_value() -> void:
	assert_eq(Order.type_name(99), "TYPE(99)")


func test_phase_name_falls_back_for_an_unmapped_value() -> void:
	assert_eq(Order.phase_name(99), "PHASE(99)")


func test_describe_omits_the_phase_when_unphased() -> void:
	var o := Order.new_wheel(1)
	assert_eq(o.describe(), "WHEEL")


func test_describe_includes_the_phase_when_phased() -> void:
	var o := Order.new_move(Vector2(1, 2))
	o.phase = Order.Phase.TURN
	assert_eq(o.describe(), "MOVE:TURN")


func test_new_move_defaults_to_unphased() -> void:
	var o := Order.new_move(Vector2(5, 5))
	assert_eq(o.type, Order.Type.MOVE)
	assert_eq(o.phase, Order.Phase.NONE)
	assert_eq(o.target_pos, Vector2(5, 5))


func test_new_move_defaults_haste_to_false_even_at_run_gait() -> void:
	# haste is a plain passthrough, not derived from gait -- SelectionManager's waypoint-
	# append path relies on this: it forces gait == RUN for travel-speed continuity, not
	# urgency, so a caller that omits haste (the default) must NOT get it for free from gait.
	var o := Order.new_move(Vector2(5, 5), 0, Unit.GAIT_RUN)
	assert_eq(o.gait, Unit.GAIT_RUN, "sanity: gait is set as requested")
	assert_false(o.haste, "haste does not default true just because gait is RUN")


func test_new_move_sets_haste_when_explicitly_requested() -> void:
	var o := Order.new_move(Vector2(5, 5), 0, Unit.GAIT_RUN, true)
	assert_true(o.haste, "an explicit haste=true is honored")


func test_new_move_starts_with_idle_maneuver_state() -> void:
	# The maneuver execution state (phase 2) is armed by Unit.begin_about_face / the drill
	# methods, never by the constructor.
	var o := Order.new_move(Vector2(5, 5))
	assert_eq(o.turn_target, Vector2.ZERO)
	assert_eq(o.pivot, Vector2.ZERO)
	assert_false(o.reform)


func test_new_about_face_and_new_quarter_turn_carry_their_kind() -> void:
	assert_eq(Order.new_about_face().type, Order.Type.ABOUT_FACE)
	var q := Order.new_quarter_turn(-1)
	assert_eq(q.type, Order.Type.QUARTER_TURN)
	assert_eq(q.dir, -1)


func test_new_attack_carries_target_uid_and_mode() -> void:
	var o := Order.new_attack(7, 2)
	assert_eq(o.type, Order.Type.ATTACK)
	assert_eq(o.target_uid, 7)
	assert_eq(o.order_mode, 2)


func test_new_relief_and_new_support_carry_target_uid() -> void:
	assert_eq(Order.new_relief(3).target_uid, 3)
	assert_eq(Order.new_support(4).target_uid, 4)


func test_new_wheel_and_new_nudge_carry_direction() -> void:
	assert_eq(Order.new_wheel(-1).dir, -1)
	assert_eq(Order.new_nudge(2).dir, 2)


func test_new_formation_and_new_frontage_carry_their_value() -> void:
	assert_eq(Order.new_formation(3).formation, 3)
	assert_eq(Order.new_frontage(6).frontage, 6)


func test_new_stance_carries_stance_and_rank_relief_toggle() -> void:
	var o := Order.new_stance(1, 2)
	assert_eq(o.type, Order.Type.STANCE)
	assert_eq(o.stance, 1)
	assert_eq(o.rank_relief, 2)


func test_new_relief_starts_with_no_pass_through_link() -> void:
	# The swap link (friendly_target) is armed by UnitRelief.begin at the apply site,
	# never by the constructor.
	assert_null(Order.new_relief(3).friendly_target)


func test_new_form_up_starts_with_no_children_and_no_parent() -> void:
	# Battle._apply_order_cmd appends children as each per-unit order joins the group;
	# a freshly-built group tag starts empty.
	var o := Order.new_form_up()
	assert_eq(o.type, Order.Type.FORM_UP)
	assert_true(o.children.is_empty())
	assert_null(o.parent)


# --- Phase 4: guard vocabulary -----------------------------------------------

func test_guard_name_maps_every_known_guard() -> void:
	assert_eq(Order.guard_name(Order.Guard.NONE), "NONE")
	assert_eq(Order.guard_name(Order.Guard.ENEMY_IN_RANGE), "ENEMY_IN_RANGE")
	assert_eq(Order.guard_name(Order.Guard.CONTACT_MADE), "CONTACT_MADE")
	assert_eq(Order.guard_name(Order.Guard.MORALE_BELOW), "MORALE_BELOW")
	assert_eq(Order.guard_name(Order.Guard.ALLY_EXHAUSTED), "ALLY_EXHAUSTED")
	assert_eq(Order.guard_name(Order.Guard.TICKS_ELAPSED), "TICKS_ELAPSED")
	assert_eq(Order.guard_name(Order.Guard.FLANKED), "FLANKED")
	assert_eq(Order.guard_name(Order.Guard.ENGAGED_FRACTION_ABOVE), "ENGAGED_FRACTION_ABOVE")


func test_guard_name_falls_back_for_an_unmapped_value() -> void:
	assert_eq(Order.guard_name(99), "GUARD(99)")


func test_a_fresh_order_carries_no_guard() -> void:
	var o := Order.new_move(Vector2(1, 1))
	assert_eq(o.guard, Order.Guard.NONE)
	assert_eq(o.guard_param, 0.0)
	assert_eq(o.guard_uid, -1)
	assert_eq(o._guard_ticks, 0)


func test_with_guard_sets_the_guard_and_returns_the_order() -> void:
	var o := Order.new_move(Vector2(1, 1))
	var same := o.with_guard(Order.Guard.CONTACT_MADE)
	assert_eq(same, o, "fluent -- returns self for chaining at the constructor site")
	assert_eq(o.guard, Order.Guard.CONTACT_MADE)


func test_with_guard_carries_its_param_and_uid() -> void:
	var o := Order.new_move(Vector2(1, 1)).with_guard(Order.Guard.MORALE_BELOW, 25.0)
	assert_eq(o.guard, Order.Guard.MORALE_BELOW)
	assert_eq(o.guard_param, 25.0)
	var ally_o := Order.new_move(Vector2(1, 1)).with_guard(Order.Guard.ALLY_EXHAUSTED, 80.0, 7)
	assert_eq(ally_o.guard_uid, 7)


func test_describe_appends_the_pending_guard() -> void:
	var o := Order.new_move(Vector2(1, 1)).with_guard(Order.Guard.CONTACT_MADE)
	assert_eq(o.describe(), "MOVE until CONTACT_MADE")


func test_describe_orders_phase_before_guard() -> void:
	var o := Order.new_move(Vector2(1, 1)).with_guard(Order.Guard.ENEMY_IN_RANGE)
	o.phase = Order.Phase.MARCH
	assert_eq(o.describe(), "MOVE:MARCH until ENEMY_IN_RANGE")


# --- COMBO composite and the relative file-double step -----------------------------------

func test_new_file_double_is_a_relative_unresolved_frontage_step() -> void:
	var widen := Order.new_file_double(1)
	assert_eq(widen.type, Order.Type.FRONTAGE)
	assert_eq(widen.dir, 1, "explicatio marks the step +1")
	assert_eq(widen.frontage, -1, "the absolute count stays unresolved until the step arms")
	var narrow := Order.new_file_double(-3)
	assert_eq(narrow.dir, -1, "any negative direction normalizes to a duplicatio (-1)")


func test_new_file_double_rejects_zero_direction_and_defaults_to_explicatio() -> void:
	# direction == 0 has no widen/narrow meaning for this RELATIVE-only factory. Left
	# unguarded, dir would stay 0 and Unit._apply_file_double_step would read the step as
	# ABSOLUTE, applying `frontage`'s still-unresolved -1 default (clamped to a single file
	# by set_frontage) instead of resolving a live width. The fix must both warn AND still
	# produce a well-formed step, so assert both halves rather than only the push_error.
	var step := Order.new_file_double(0)
	assert_push_error("direction must be nonzero")
	assert_eq(step.type, Order.Type.FRONTAGE)
	assert_eq(step.dir, 1,
			"coerced to an explicatio rather than left at 0 -- that is the ABSOLUTE branch's marker")
	assert_eq(step.frontage, -1, "still unresolved -- arming still resolves it, same as any relative step")


func test_new_combo_links_every_step_back_to_the_composite() -> void:
	var turn := Order.new_quarter_turn(1)
	var widen := Order.new_file_double(1)
	var steps: Array[Order] = [turn, widen]
	var combo := Order.new_combo(steps)
	assert_eq(combo.type, Order.Type.COMBO)
	assert_eq(combo.children.size(), 2)
	assert_eq(combo.children[0], turn, "steps keep their issue order")
	assert_eq(combo.children[1], widen)
	assert_eq(turn.parent, combo, "each step points back at the composite")
	assert_eq(widen.parent, combo)
	assert_eq(combo.active_leaf(), turn, "the cursor starts on the first step")


func test_combo_effective_phase_reports_the_active_step_itself() -> void:
	# A combo's steps carry no positional meaning, so the transcript's order_phase names the
	# step (its type) rather than the rear-move composites' by-position TURN/RETURN_TURN.
	var steps: Array[Order] = [Order.new_about_face(), Order.new_quarter_turn(-1)]
	var combo := Order.new_combo(steps)
	assert_eq(combo.effective_phase_name(), "ABOUT_FACE")
	combo._active_child = 1
	assert_eq(combo.effective_phase_name(), "QUARTER_TURN",
		"the second step is NOT reported as a RETURN_TURN, unlike a lateral pivot's last child")


func test_combo_round_trips_through_the_snapshot_dict() -> void:
	var steps: Array[Order] = [Order.new_quarter_turn(-1), Order.new_file_double(1)]
	var combo := Order.new_combo(steps)
	combo._active_child = 1
	var rebuilt := Order.from_dict(combo.to_dict())
	assert_eq(rebuilt.type, Order.Type.COMBO)
	assert_eq(rebuilt.children.size(), 2)
	assert_eq(rebuilt._active_child, 1, "the cursor survives the round trip")
	assert_eq(rebuilt.children[0].type, Order.Type.QUARTER_TURN)
	assert_eq(rebuilt.children[0].dir, -1)
	assert_eq(rebuilt.children[1].type, Order.Type.FRONTAGE)
	assert_eq(rebuilt.children[1].dir, 1, "the relative file-double marker survives too")
	assert_eq(rebuilt.children[1].parent, rebuilt, "children re-link to the rebuilt composite")
