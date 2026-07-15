extends GutTest
## SelectionManager order-overlay helpers: the SUPPORT-ward resolution that
## decides whether the hold-Space overlay draws a supporter→ward link. The drawing
## itself is visual, but the ward-validity guard is pure logic and worth pinning.
## (The freed-instance `is_instance_valid(ward) == false` path isn't exercised — it
## needs a queue_free() plus a frame await, awkward in GUT; the alive/none/dead/
## routing/self cases below cover the rest of the guard.)

const SelectionManagerScript = preload("res://scripts/SelectionManager.gd")
const UnitScript = preload("res://scripts/Unit.gd")
const BattleScript = preload("res://scripts/Battle.gd")

# Snapshot/restore the global Settings hotkeys around tests that rebind them,
# so a rebinding test can't leak into others or the real user://settings.cfg.
var _orig_bindings: Dictionary
var _orig_form_up_default: int
var _orig_form_up_cycle: Array
var _orig_reform_before_move: bool
var _orig_show_unit_speed: bool


func before_each() -> void:
	_orig_bindings = Settings.order_bindings.duplicate()
	_orig_form_up_default = Settings.form_up_dist_default
	_orig_form_up_cycle = Settings.form_up_dist_cycle.duplicate()
	_orig_reform_before_move = Settings.reform_before_move
	_orig_show_unit_speed = Settings.show_unit_speed
	# Pin the default cycle; a developer's persisted cfg can deviate and break these tests locally.
	Settings.form_up_dist_cycle = [EQUAL_DEPTH, EQUAL_WIDTH]


func after_each() -> void:
	Settings.order_bindings = _orig_bindings.duplicate()
	Settings.form_up_dist_default = _orig_form_up_default
	Settings.form_up_dist_cycle = _orig_form_up_cycle.duplicate()
	Settings.reform_before_move = _orig_reform_before_move
	Settings.show_unit_speed = _orig_show_unit_speed


func _sm() -> Node2D:
	var sm = SelectionManagerScript.new()
	add_child_autofree(sm)   # runs _ready(): only sets z_index / process_mode
	return sm


func _unit() -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	return u


func test_support_ward_resolves_a_valid_ward() -> void:
	var sm := _sm()
	var u := _unit()
	var ward := _unit()
	u.support_target = ward
	assert_eq(sm._support_ward_of(u), ward, "a live ward is returned for the overlay link")


# --- order-overlay unit-speed label (#444) -----------------------------------

func test_unit_speed_label_is_empty_when_toggle_off() -> void:
	var sm := _sm()
	var u := _unit()
	Settings.show_unit_speed = false
	u._current_speed = 52.0
	assert_eq(sm._unit_speed_label(u), "", "no label when the toggle is off, whatever the speed")


func test_unit_speed_label_reports_metres_per_second_when_on() -> void:
	var sm := _sm()
	var u := _unit()
	Settings.show_unit_speed = true
	# 52 world units/s at 20 u/m, speed_scale 1.0 -> 2.6 m/s.
	u._current_speed = 52.0
	assert_eq(sm._unit_speed_label(u), "2.6 m/s", "the live speed converts back to the loadout's m/s")


func test_unit_speed_label_reads_zero_for_a_halted_unit() -> void:
	var sm := _sm()
	var u := _unit()
	Settings.show_unit_speed = true
	u._current_speed = 0.0
	assert_eq(sm._unit_speed_label(u), "0.0 m/s", "a stationary unit reads 0.0 m/s")


func test_unit_speed_label_reads_wheeling_mid_swing_instead_of_zero() -> void:
	# _advance_wheel rotates the block about a hinge without ever calling _move_to,
	# so current_speed never leaves 0 during a wheel -- the label must not claim the
	# unit is stationary while it's visibly swinging.
	var sm := _sm()
	var u := _unit()
	Settings.show_unit_speed = true
	u._current_speed = 0.0
	var w := Order.new_wheel(1)
	w.turn_start_facing = u.facing
	w.turn_target = u.facing.rotated(PI * 0.5)
	u.set_current_order(w)
	assert_true(u.is_wheeling(), "setup: the order is a mid-swing wheel")
	assert_eq(sm._unit_speed_label(u), "wheeling", "a mid-wheel unit reads 'wheeling', not '0.0 m/s'")


# --- order-overlay distance label: route length (#413) -----------------------

func test_route_length_single_leg_is_the_straight_distance() -> void:
	var sm := _sm()
	var route: Array[Vector2] = [Vector2(300, 0)]
	assert_almost_eq(sm._route_length(Vector2.ZERO, route), 300.0, 0.0001,
		"a single-destination move is the straight origin->target distance")


func test_route_length_sums_each_leg_of_a_waypoint_route() -> void:
	var sm := _sm()
	# Origin (0,0) -> (300,0) -> (300,400): legs of 300 and 400 -> 700, not the 500
	# straight-line origin->destination. The label must report the real march.
	var route: Array[Vector2] = [Vector2(300, 0), Vector2(300, 400)]
	assert_almost_eq(sm._route_length(Vector2.ZERO, route), 700.0, 0.0001,
		"a multi-waypoint route sums its legs, exceeding the straight-line distance")


func test_route_length_of_an_empty_route_is_zero() -> void:
	var sm := _sm()
	var route: Array[Vector2] = []
	assert_eq(sm._route_length(Vector2.ZERO, route), 0.0, "no points -> no distance")


func test_support_ward_is_null_without_a_ward() -> void:
	var sm := _sm()
	var u := _unit()
	assert_null(sm._support_ward_of(u), "no ward -> nothing to draw")


func test_support_ward_skips_a_dead_ward() -> void:
	var sm := _sm()
	var u := _unit()
	var ward := _unit()
	u.support_target = ward
	ward.state = UnitScript.State.DEAD
	assert_null(sm._support_ward_of(u), "a dead ward is not drawn")


func test_support_ward_skips_a_routing_ward() -> void:
	var sm := _sm()
	var u := _unit()
	var ward := _unit()
	u.support_target = ward
	ward.state = UnitScript.State.ROUTING
	assert_null(sm._support_ward_of(u), "a routing ward is not drawn")


func test_support_ward_skips_self() -> void:
	# Parity with UnitTargeting.support_valid's self-guard check. Battle never issues a
	# self-guard order, but the helper rejects it so the two stay in lockstep.
	var sm := _sm()
	var u := _unit()
	u.support_target = u
	assert_null(sm._support_ward_of(u), "a unit can't guard itself")


# --- order-mode hotkeys read from Settings ---------------------------

func test_selector_reads_rebound_key_from_settings() -> void:
	var sm := _sm()
	assert_eq(sm._order_mode_for_keycode(KEY_H), BattleScript.OrderMode.HOLD,
		"the default H arms Hold")
	assert_eq(sm._order_mode_for_keycode(KEY_Z), -1, "Z is unbound by default")
	# Rebind Hold to Z in-memory (after_each restores the global bindings).
	Settings.order_bindings["hold"] = KEY_Z
	assert_eq(sm._order_mode_for_keycode(KEY_Z), BattleScript.OrderMode.HOLD,
		"after rebinding, Z arms Hold")
	assert_eq(sm._order_mode_for_keycode(KEY_H), -1,
		"and the old default H no longer arms anything")


func test_escape_clears_stance_regardless_of_bindings() -> void:
	var sm := _sm()
	assert_eq(sm._order_mode_for_keycode(KEY_ESCAPE), BattleScript.OrderMode.NORMAL,
		"Esc always clears the stance — it's fixed, not rebindable")


# --- demo order overlay gating ---------------------------------------

func test_demo_orders_active_only_during_playback_with_the_flag() -> void:
	# The order overlay shows without a held key only when the demo recorder is
	# replaying with show_demo_orders set; in-app Watch Replay (flag off) and live
	# play keep it on the Space-held survey.
	var sm := _sm()
	var prev_mode = Replay.mode
	var prev_flag := Replay.show_demo_orders
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.show_demo_orders = true
	assert_true(sm._demo_orders_active(), "active during demo playback with the flag set")
	Replay.show_demo_orders = false
	assert_false(sm._demo_orders_active(), "off in Watch Replay (playback, flag clear)")
	Replay.mode = Replay.Mode.RECORD
	Replay.show_demo_orders = true
	assert_false(sm._demo_orders_active(), "off when not in playback")
	Replay.mode = prev_mode
	Replay.show_demo_orders = prev_flag


# --- demo pointer capture --------------------------------------------

func test_pointer_state_reports_live_selection_drag_and_stance() -> void:
	# The recorder samples this each tick; it must report the armed stance, the drag-box
	# state, and the selected units' uids (alive only).
	var sm := _sm()
	var u := _unit()
	u.uid = 7
	var dead := _unit()
	dead.uid = 9
	dead.state = UnitScript.State.DEAD
	sm._selected = [u, dead]
	sm._dragging = true
	sm._drag_start = Vector2(12, 34)
	sm._armed_mode = BattleScript.OrderMode.SKIRMISH

	sm.set_cursor_override(Vector2(640, 480))
	var ps: Dictionary = sm.pointer_state()
	assert_eq(ps["cursor"], Vector2(640, 480), "an injected cursor is reported as the cursor")
	assert_eq(ps["selection"], [7], "only living selected units' uids are reported")
	# Clearing the override returns to the live mouse, so the injected value no longer shows.
	sm.set_cursor_override(null)
	assert_ne(sm.pointer_state()["cursor"], Vector2(640, 480),
			"clearing the override falls back to the live OS mouse")
	assert_true(ps["dragging"], "the open drag-box is reported")
	assert_eq(ps["drag_start"], Vector2(12, 34), "the drag start corner is reported")
	assert_eq(ps["mode"], BattleScript.OrderMode.SKIRMISH, "the armed stance is reported")


# --- frontage resize handles ----------------------------

func test_file_axis_is_perpendicular_to_facing() -> void:
	var sm := _sm()
	var u := _unit()
	u.facing = Vector2.DOWN   # forward is +Y, so the width axis is horizontal
	var axis: Vector2 = sm._file_axis(u)
	assert_almost_eq(axis.y, 0.0, 0.001, "a down-facing unit's file axis is horizontal")
	assert_almost_eq(absf(axis.x), 1.0, 0.001, "and is a unit vector")


func test_resize_handles_straddle_the_unit_along_the_file_axis() -> void:
	var sm := _sm()
	var u := _unit()
	u.facing = Vector2.DOWN
	u.position = Vector2(100, 100)
	var hs: Array = sm._resize_handle_positions(u)
	assert_eq(hs.size(), 2, "two grips, one per flank")
	# Symmetric about the unit centre.
	var mid: Vector2 = (hs[0] + hs[1]) * 0.5
	assert_almost_eq(mid.distance_to(u.global_position), 0.0, 0.001,
			"the grips are centred on the unit")
	assert_gt(hs[0].distance_to(hs[1]), 0.0, "the grips are separated across the line")


func test_single_selected_unit_requires_exactly_one() -> void:
	var sm := _sm()
	var a := _unit()
	var c := _unit()
	assert_null(sm._single_selected_unit(), "nothing selected -> no resize target")
	sm._select(a)
	assert_eq(sm._single_selected_unit(), a, "one selected unit is the resize target")
	sm._select(c)
	assert_null(sm._single_selected_unit(), "a multi-selection shows no single-unit grips")


func test_resize_handle_at_grabs_a_grip_and_ignores_empty_space() -> void:
	var sm := _sm()
	var u := _unit()
	u.facing = Vector2.DOWN
	u.position = Vector2(50, 50)
	sm._select(u)
	var grip: Vector2 = sm._resize_handle_positions(u)[0]
	assert_eq(sm._resize_handle_at(grip), u, "a cursor on a grip grabs that unit for resizing")
	assert_null(sm._resize_handle_at(u.global_position + Vector2(9999, 0)),
			"a cursor far from any grip grabs nothing")


func test_resize_frontage_routes_an_absolute_command_to_battle() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 5
	u.max_soldiers = 80
	b._by_uid[5] = u
	var start: int = UnitFormation.frontage(u)
	sm._select(u)
	sm._resize_frontage(1)
	assert_eq(UnitFormation.frontage(u), start + 1, "the keyboard widen steps the line out one file")
	assert_eq(int(b._pending_orders[-1]["target"]), BattleScript.ORDER_FRONTAGE_ONLY,
			"routed as a recorded frontage command")


# --- keystroke overlay capture --------------------------

func _key_event(keycode: int, ctrl: bool = false, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	return ev


func test_key_label_uses_glyphs_for_brackets_and_escape() -> void:
	var sm := _sm()
	assert_eq(sm._key_label(_key_event(KEY_BRACKETLEFT)), "[", "left bracket shows as [")
	assert_eq(sm._key_label(_key_event(KEY_BRACKETRIGHT)), "]", "right bracket shows as ]")
	assert_eq(sm._key_label(_key_event(KEY_ESCAPE)), "Esc", "escape shows as Esc")
	assert_eq(sm._key_label(_key_event(KEY_T)), "T", "a letter shows as itself")
	assert_eq(sm._key_label(_key_event(KEY_1, true)), "Ctrl+1", "a chorded digit shows the modifier")


func test_take_keys_this_tick_drains_the_buffer() -> void:
	var sm := _sm()
	sm._note_key("]")
	sm._note_key("[")
	assert_eq(sm.take_keys_this_tick(), ["]", "["], "buffered keys are returned in order")
	assert_eq(sm.take_keys_this_tick(), [], "the buffer is cleared after draining")


func test_dispatch_key_routes_resize_and_reports_handled() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 9
	u.max_soldiers = 80
	b._by_uid[9] = u
	var start: int = UnitFormation.frontage(u)
	sm._select(u)
	assert_true(sm._dispatch_key(_key_event(KEY_BRACKETRIGHT)), "] is a handled hotkey")
	assert_eq(UnitFormation.frontage(u), start + 1, "and widens the selected unit")
	assert_false(sm._dispatch_key(_key_event(KEY_P)), "an unbound key is not handled")


func test_dispatch_key_shift_b_issues_right_anchored_explicatio() -> void:
	# Shift+B (asymmetric explicatio): widens like plain B, but with a non-zero
	# anchor offset that holds the right flank fixed instead of the plain centred
	# widen's zero offset.
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 11
	u.soldiers = 120
	u.max_soldiers = 120
	b._by_uid[11] = u
	var start: int = UnitFormation.frontage(u)
	sm._select(u)
	assert_true(sm._dispatch_key(_key_event(KEY_B, false, true)), "Shift+B is a handled hotkey")
	assert_eq(UnitFormation.frontage(u), start * 2, "still doubles the frontage like plain B")
	assert_ne(u.frontage_anchor_offset, 0.0, "right-anchored explicatio carries a non-zero anchor shift")


func test_dispatch_key_shift_b_pressed_twice_keeps_the_right_flank_fixed() -> void:
	# Regression for the bug the review caught: a SECOND Shift+B on the same unit
	# must compose its anchor shift onto the existing offset, not overwrite it, or
	# the "held" right flank silently jumps between presses.
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 14
	u.soldiers = 240
	u.max_soldiers = 240
	b._by_uid[14] = u
	sm._select(u)

	var slots_before := u.soldier_world_slots(u.soldiers)
	var frontage_before: int = UnitFormation.frontage(u)
	var right_edge_before: float = slots_before[frontage_before - 1].x

	assert_true(sm._dispatch_key(_key_event(KEY_B, false, true)), "first Shift+B is handled")
	var slots_after_1 := u.soldier_world_slots(u.soldiers)
	var frontage_after_1: int = UnitFormation.frontage(u)
	var right_edge_after_1: float = slots_after_1[frontage_after_1 - 1].x
	assert_almost_eq(right_edge_after_1, right_edge_before, 0.5,
		"the right flank stays fixed after the first anchored widen")

	assert_true(sm._dispatch_key(_key_event(KEY_B, false, true)), "second Shift+B is handled")
	var slots_after_2 := u.soldier_world_slots(u.soldiers)
	var frontage_after_2: int = UnitFormation.frontage(u)
	var right_edge_after_2: float = slots_after_2[frontage_after_2 - 1].x
	assert_almost_eq(right_edge_after_2, right_edge_before, 0.5,
		"the right flank STILL stays fixed after a SECOND anchored widen (composed offset)")


func test_dispatch_key_ctrl_b_issues_left_anchored_explicatio() -> void:
	# Ctrl+B is the mirror: same widen, opposite (left) anchor -- so the shift sign
	# is the opposite of Shift+B's for the same starting layout.
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 12
	u.soldiers = 120
	u.max_soldiers = 120
	b._by_uid[12] = u
	sm._select(u)
	assert_true(sm._dispatch_key(_key_event(KEY_B, true)), "Ctrl+B is a handled hotkey")
	assert_ne(u.frontage_anchor_offset, 0.0, "left-anchored explicatio carries a non-zero anchor shift")


func test_dispatch_key_plain_b_stays_centred() -> void:
	# Plain B (no modifier) is unchanged: the centred explicatio carries a zero
	# anchor offset, exactly like before this asymmetric variant existed.
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 13
	u.soldiers = 120
	u.max_soldiers = 120
	b._by_uid[13] = u
	sm._select(u)
	assert_true(sm._dispatch_key(_key_event(KEY_B)), "plain B is a handled hotkey")
	assert_eq(u.frontage_anchor_offset, 0.0, "the plain centred explicatio has no anchor shift")


func test_dispatch_key_routes_up_arrow_to_forward_nudge() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 11
	b._by_uid[11] = u
	sm._select(u)
	assert_true(sm._dispatch_key(_key_event(KEY_UP)), "Up is a handled hotkey while a unit is selected")
	var cmd: Dictionary = b._pending_orders[-1]
	assert_eq(int(cmd["target"]), BattleScript.ORDER_NUDGE,
			"routed as a recorded nudge command")
	assert_eq(int(cmd["frontage"]), BattleScript.NudgeDir.FORWARD,
			"the direction rides the frontage field, per enqueue_nudge's doc comment")


# --- standalone stance gesture -----------------------------------------

func test_ctrl_stance_key_writes_the_stance_in_place() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 3
	b._by_uid[3] = u
	sm._select(u)
	# Plain H arms Hold for the NEXT order; it does not touch order_mode yet.
	assert_true(sm._dispatch_key(_key_event(KEY_H)), "H is a handled hotkey")
	assert_eq(sm.get_armed_mode(), BattleScript.OrderMode.HOLD, "H arms Hold")
	assert_eq(u.order_mode, BattleScript.OrderMode.NORMAL,
			"arming alone doesn't write the unit's stance")
	# Ctrl+H writes Hold on the unit immediately, no move/attack needed.
	assert_true(sm._dispatch_key(_key_event(KEY_H, true)), "Ctrl+H is a handled hotkey")
	assert_eq(u.order_mode, BattleScript.OrderMode.HOLD,
			"Ctrl+<stance key> writes the stance in place")
	assert_eq(int(b._pending_orders[-1]["target"]), BattleScript.ORDER_STANCE_ONLY,
			"routed as a recorded stance-only command")
	assert_eq(int(b._pending_orders[-1]["frontage"]), BattleScript.RankRelief.LEAVE,
			"the direct-stance gesture never touches rank relief")


func test_ctrl_stance_key_does_nothing_with_no_selection() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	assert_true(sm._dispatch_key(_key_event(KEY_H, true)), "still a handled/known hotkey")
	assert_true(b._pending_orders.is_empty(), "no selection -> no command queued")


func test_toggle_rank_relief_flips_from_the_lead_units_setting() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 4
	b._by_uid[4] = u
	sm._select(u)
	assert_true(u.rank_relief, "rank relief defaults on")

	assert_true(sm._dispatch_key(_key_event(KEY_I)), "I is a handled hotkey")
	assert_false(u.rank_relief, "I toggles rank relief off from the default")
	assert_eq(int(b._pending_orders[-1]["target"]), BattleScript.ORDER_STANCE_ONLY,
			"routed as a recorded stance-only command")
	assert_eq(int(b._pending_orders[-1]["mode"]), -1,
			"the rank-relief toggle never touches the order_mode stance")

	sm._dispatch_key(_key_event(KEY_I))
	assert_true(u.rank_relief, "a second press toggles it back on")


func test_toggle_rank_relief_does_nothing_with_no_selection() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	assert_true(sm._dispatch_key(_key_event(KEY_I)), "still a handled/known hotkey")
	assert_true(b._pending_orders.is_empty(), "no selection -> no command queued")


func test_ctrl_stance_key_and_rank_relief_toggle_are_disabled_during_playback() -> void:
	# Both gestures are live-play-only, like every other order-issuing hotkey: a replay's
	# recorded commands drive playback, so a synthesized keypress during Watch Replay must
	# not queue a second, unrecorded command.
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 6
	b._by_uid[6] = u
	sm._select(u)
	var prev_mode = Replay.mode
	Replay.mode = Replay.Mode.PLAYBACK
	sm._issue_stance(BattleScript.OrderMode.HOLD)
	sm._toggle_rank_relief()
	Replay.mode = prev_mode
	assert_eq(u.order_mode, BattleScript.OrderMode.NORMAL, "no stance written during playback")
	assert_true(u.rank_relief, "no rank-relief toggle during playback")
	assert_true(b._pending_orders.is_empty(), "no command queued during playback")


# --- drag-to-form-up ------------------------------------

func test_form_up_facing_is_perpendicular_to_the_flank_line() -> void:
	var sm := _sm()
	# A left->right horizontal flank line: the unit faces up (perpendicular).
	var facing := Vector2.from_angle(sm._form_up_facing(Vector2(0, 0), Vector2(100, 0)))
	assert_almost_eq(facing.x, 0.0, 0.001, "a horizontal flank line gives a vertical facing")
	assert_almost_eq(facing.y, -1.0, 0.001, "and faces up for a left-to-right drag")


func test_can_form_up_requires_a_selection_and_width() -> void:
	var sm := _sm()
	var a := _unit()
	var c := _unit()
	assert_false(sm._can_form_up(Vector2.ZERO, Vector2(100, 0)), "no selection -> plain move")
	sm._select(a)
	assert_true(sm._can_form_up(Vector2.ZERO, Vector2(100, 0)), "one unit + wide drag -> form-up")
	assert_false(sm._can_form_up(Vector2.ZERO, Vector2(5, 0)), "too-short drag -> plain move")
	sm._select(c)
	assert_true(sm._can_form_up(Vector2.ZERO, Vector2(100, 0)),
			"a multi-selection + wide drag also forms up (distributed along the line)")


func test_can_form_up_needs_extra_width_for_each_inter_unit_gap() -> void:
	# Two units need FORM_UP_MIN_WIDTH plus one gap's worth of drag; a drag only wide enough
	# for a single unit falls back to a plain move (so the gaps can't eat all the usable width).
	var sm := _sm()
	var a := _unit()
	var c := _unit()
	sm._select(a)
	var one_unit_min: float = SelectionManagerScript.FORM_UP_MIN_WIDTH
	assert_true(sm._can_form_up(Vector2.ZERO, Vector2(one_unit_min, 0)), "one unit forms up at the base minimum")
	sm._select(c)
	assert_false(sm._can_form_up(Vector2.ZERO, Vector2(one_unit_min, 0)),
			"two units need more than the single-unit minimum (room for the gap)")
	var two_unit_min: float = one_unit_min + SelectionManagerScript.MULTI_FORM_UP_GAP
	assert_true(sm._can_form_up(Vector2.ZERO, Vector2(two_unit_min, 0)),
			"a drag wide enough for the gap forms up")


# --- clickable flags ------------------------------------

func test_flag_pick_distance_hits_the_standard_and_misses_the_body_and_empty_space() -> void:
	var sm := _sm()
	var u := _unit()
	u.position = Vector2(500, 500)
	# The standard's local centre, from the same geometry UnitSprites draws.
	var center: Vector2 = UnitSprites.standard_bounds(u.render_block_extent()).get_center()
	var flag_world: Vector2 = u.global_position + center
	assert_almost_eq(sm._flag_pick_distance(u, flag_world), 0.0, 0.001,
			"a cursor on the standard's centre is zero distance from it")
	assert_eq(sm._flag_pick_distance(u, u.global_position), -1.0,
			"the body centre is well below the raised standard, so not a flag hit")
	assert_eq(sm._flag_pick_distance(u, u.global_position + Vector2(9999, 0)), -1.0,
			"empty space far from the standard is not a flag hit")


func test_unit_at_selects_a_unit_by_its_flag() -> void:
	var sm := _sm()
	var u := _unit()
	u.team = 0
	u.position = Vector2(500, 500)
	var flag_world: Vector2 = u.global_position \
			+ UnitSprites.standard_bounds(u.render_block_extent()).get_center()
	# The flag floats above the block, out of body-click range, yet resolves to the unit.
	# Read the body-pick pad from SelectionManager so this stays true if the threshold moves.
	var body_pick: float = UnitScript.RADIUS + SelectionManagerScript.BODY_PICK_PAD
	assert_gt(flag_world.distance_to(u.global_position), body_pick,
			"the flag sits beyond the body-click radius")
	assert_eq(sm._unit_at(flag_world, 0), u, "clicking the raised flag selects the unit")


func test_unit_at_prefers_a_body_hit_over_an_overlapping_flag() -> void:
	# A body click always wins: place unit B's flag exactly over unit A's body, then click
	# there — A (the body) is selected, not B (the flag floating onto the same spot).
	var sm := _sm()
	var a := _unit()
	a.team = 0
	a.position = Vector2(300, 300)
	var b := _unit()
	b.team = 0
	# Put B's standard centre on A's body centre.
	var center: Vector2 = UnitSprites.standard_bounds(b.render_block_extent()).get_center()
	b.position = a.global_position - center
	assert_eq(sm._unit_at(a.global_position, 0), a,
			"the body under the cursor wins over another unit's overlapping flag")


func test_unit_at_flag_click_respects_team() -> void:
	var sm := _sm()
	var enemy := _unit()
	enemy.team = 1
	enemy.position = Vector2(700, 200)
	var flag_world: Vector2 = enemy.global_position \
			+ UnitSprites.standard_bounds(enemy.render_block_extent()).get_center()
	assert_null(sm._unit_at(flag_world, 0),
			"a team-0 query ignores an enemy's flag (team filter still applies)")
	assert_eq(sm._unit_at(flag_world, 1), enemy,
			"a team-1 query resolves the same flag to the enemy")


# --- all-teams control --------------------------------------------------------

func test_is_own_team_defaults_to_team_zero_only() -> void:
	var sm := _sm()
	assert_true(sm._is_own_team(0), "team 0 is always the player's own")
	assert_false(sm._is_own_team(1), "team 1 isn't controllable outside all-teams control")


func test_is_own_team_relaxes_under_all_teams_control() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	b.all_teams_control = true
	sm._battle = b
	assert_true(sm._is_own_team(1), "every team is controllable once all-teams control is active")


func test_unit_at_team_any_own_ignores_team1_outside_all_teams_control() -> void:
	var sm := _sm()
	var enemy := _unit()
	enemy.team = 1
	enemy.position = Vector2(700, 200)
	assert_null(sm._unit_at(enemy.global_position, SelectionManagerScript.TEAM_ANY_OWN),
			"TEAM_ANY_OWN stays team-0-only outside all-teams control")


func test_unit_at_team_any_own_selects_across_teams_under_all_teams_control() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	b.all_teams_control = true
	sm._battle = b
	var enemy := _unit()
	enemy.team = 1
	enemy.position = Vector2(700, 200)
	assert_eq(sm._unit_at(enemy.global_position, SelectionManagerScript.TEAM_ANY_OWN), enemy,
			"a non-zero-team unit becomes selectable once all-teams control is active")


func test_enemy_team_defaults_to_team1() -> void:
	var sm := _sm()
	assert_eq(sm._enemy_team(), 1, "outside all-teams control the enemy is always team 1")
	assert_eq(sm._friend_team(), 0, "and the friend team is always team 0")


func test_enemy_team_flips_relative_to_the_selection_under_all_teams_control() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	b.all_teams_control = true
	sm._battle = b
	var t1_unit := _unit()
	t1_unit.team = 1
	sm._select(t1_unit)
	assert_eq(sm._enemy_team(), 0,
			"a selected team-1 unit's 'enemy' is team 0, so right-click can order it to attack team 0")
	assert_eq(sm._friend_team(), 1, "and its own team is the 'friend' team for relief/move resolution")


func test_enemy_team_falls_back_to_team1_under_all_teams_control_with_no_selection() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	b.all_teams_control = true
	sm._battle = b
	assert_eq(sm._enemy_team(), 1,
			"with nothing selected there's no team to flip relative to, so it falls back to team 1")


func test_finish_selection_box_select_only_includes_own_team_units() -> void:
	var sm := _sm()
	var friend := _unit()
	friend.team = 0
	friend.position = Vector2(100, 100)
	var enemy := _unit()
	enemy.team = 1
	enemy.position = Vector2(150, 100)
	sm._drag_start = Vector2.ZERO
	sm._drag_cur = Vector2(300, 300)   # box covers both units; well over CLICK_THRESHOLD
	sm._finish_selection()
	assert_true(sm._selected.has(friend), "an own-team unit inside the drag box is selected")
	assert_false(sm._selected.has(enemy),
			"an enemy unit inside the same drag box is skipped outside all-teams control")


func test_select_same_type_only_includes_own_team_units() -> void:
	var sm := _sm()
	var proto := _unit()
	proto.team = 0
	var same_type_enemy := _unit()
	same_type_enemy.team = 1
	sm._select_same_type(proto)
	assert_true(sm._selected.has(proto), "the prototype's own unit is selected")
	assert_false(sm._selected.has(same_type_enemy),
			"a same-type enemy unit is skipped outside all-teams control")


func _seeded_unit(team: int) -> Unit:
	var u := _unit()
	u.team = team
	u.max_soldiers = 60
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()   # required by _can_drill() for conversio/quarter_turn
	return u


func test_issue_conversio_only_turns_own_team_units() -> void:
	var sm := _sm()
	var friend := _seeded_unit(0)
	var enemy := _seeded_unit(1)
	sm._selected = [friend, enemy]
	sm._issue_conversio()
	assert_eq(friend.current_order.type, Order.Type.ABOUT_FACE,
			"the own-team unit received the about-face drill")
	assert_null(enemy.current_order,
			"an enemy unit in the selection is skipped outside all-teams control")


## Unlike conversio/quarter-turn (visual-only, unrecorded), a countermarch goes through the
## recorded Battle.enqueue_countermarch path -- see _issue_countermarch's own doc -- so this
## needs a real Battle double registering both units by uid, the same setup the dispatch_key
## resize/explicatio tests above use.
func test_issue_countermarch_only_turns_own_team_units() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var friend := _seeded_unit(0)
	friend.uid = 30
	b._by_uid[30] = friend
	var enemy := _seeded_unit(1)
	enemy.uid = 31
	b._by_uid[31] = enemy
	sm._selected = [friend, enemy]
	sm._issue_countermarch(Unit.CountermarchVariant.MACEDONIAN)
	assert_eq(friend.countermarch_variant(), Unit.CountermarchVariant.MACEDONIAN,
			"the own-team unit received the countermarch")
	assert_eq(enemy.countermarch_variant(), -1,
			"an enemy unit in the selection is skipped outside all-teams control")


func test_dispatch_key_shift_v_issues_choral_countermarch() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _seeded_unit(0)
	u.uid = 32
	b._by_uid[32] = u
	sm._select(u)
	assert_true(sm._dispatch_key(_key_event(KEY_V, false, true)), "Shift+V is a handled hotkey")
	assert_eq(u.countermarch_variant(), Unit.CountermarchVariant.CHORAL)


func test_dispatch_key_ctrl_v_issues_macedonian_countermarch() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _seeded_unit(0)
	u.uid = 33
	b._by_uid[33] = u
	sm._select(u)
	assert_true(sm._dispatch_key(_key_event(KEY_V, true)), "Ctrl+V is a handled hotkey")
	assert_eq(u.countermarch_variant(), Unit.CountermarchVariant.MACEDONIAN)


func test_dispatch_key_ctrl_shift_v_issues_laconian_countermarch() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _seeded_unit(0)
	u.uid = 34
	b._by_uid[34] = u
	sm._select(u)
	assert_true(sm._dispatch_key(_key_event(KEY_V, true, true)), "Ctrl+Shift+V is a handled hotkey")
	assert_eq(u.countermarch_variant(), Unit.CountermarchVariant.LACONIAN)


func test_issue_quarter_turn_only_turns_own_team_units() -> void:
	var sm := _sm()
	var friend := _seeded_unit(0)
	var enemy := _seeded_unit(1)
	sm._selected = [friend, enemy]
	sm._issue_quarter_turn(1)
	assert_eq(friend.current_order.type, Order.Type.QUARTER_TURN,
			"the own-team unit received the quarter-turn drill")
	assert_null(enemy.current_order,
			"an enemy unit in the selection is skipped outside all-teams control")


func test_issue_form_up_routes_a_recorded_order() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 11
	u.max_soldiers = 120
	u.position = Vector2(0, 100)
	b._by_uid[11] = u
	sm._select(u)
	sm._issue_form_up(Vector2(400, 500), Vector2(540, 500))   # 140 px wide line
	assert_eq(u.active_leaf().target_pos, Vector2(470, 500), "deploys at the flank-line midpoint")
	assert_true(b._pending_orders[-1].has("face"), "routed as a recorded form-up order")


# --- multi-click move gait (walk/jog/run/sprint) -------------------------

func test_gait_from_click_count_maps_counts_to_gaits() -> void:
	var sm := _sm()
	assert_eq(sm._gait_from_click_count(1), BattleScript.Gait.WALK, "a single click walks")
	assert_eq(sm._gait_from_click_count(2), BattleScript.Gait.JOG, "a double click jogs")
	assert_eq(sm._gait_from_click_count(3), BattleScript.Gait.RUN, "a triple click runs")
	assert_eq(sm._gait_from_click_count(4), BattleScript.Gait.SPRINT, "a quadruple click sprints")
	assert_eq(sm._gait_from_click_count(9), BattleScript.Gait.SPRINT, "any further click stays at sprint")


func test_gait_from_click_count_append_always_runs() -> void:
	var sm := _sm()
	assert_eq(sm._gait_from_click_count(1, true), BattleScript.Gait.RUN,
			"an appended waypoint runs even on the first click")
	assert_eq(sm._gait_from_click_count(4, true), BattleScript.Gait.RUN,
			"an appended waypoint stays at run regardless of click count")


func test_finish_right_button_first_click_orders_a_walk() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 21
	sm._select(u)
	sm._finish_right_button(Vector2(300, 300), false)
	assert_eq(int(b._pending_orders[-1]["gait"]), BattleScript.Gait.WALK,
			"a single right-click orders a walk")


func test_finish_right_button_click_combo_escalates_the_gait() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 22
	sm._select(u)
	var dest := Vector2(300, 300)
	sm._finish_right_button(dest, false)
	assert_eq(int(b._pending_orders[-1]["gait"]), BattleScript.Gait.WALK, "1st click walks")
	sm._finish_right_button(dest, false)
	assert_eq(int(b._pending_orders[-1]["gait"]), BattleScript.Gait.JOG,
			"a 2nd click on the same spot jogs")
	sm._finish_right_button(dest, false)
	assert_eq(int(b._pending_orders[-1]["gait"]), BattleScript.Gait.RUN, "a 3rd click runs")
	sm._finish_right_button(dest, false)
	assert_eq(int(b._pending_orders[-1]["gait"]), BattleScript.Gait.SPRINT, "a 4th click sprints")
	sm._finish_right_button(dest, false)
	assert_eq(int(b._pending_orders[-1]["gait"]), BattleScript.Gait.SPRINT,
			"a 5th click stays at sprint")


func test_finish_right_button_combo_resets_once_the_window_expires() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 23
	sm._select(u)
	var dest := Vector2(300, 300)
	sm._finish_right_button(dest, false)
	sm._finish_right_button(dest, false)
	assert_eq(int(b._pending_orders[-1]["gait"]), BattleScript.Gait.JOG, "2 clicks in a row jog")
	sm._last_right_click_ms -= (sm._click_combo_window_ms + 1)
	sm._finish_right_button(dest, false)
	assert_eq(int(b._pending_orders[-1]["gait"]), BattleScript.Gait.WALK,
			"a click after the combo window expires restarts the count at walk")


func test_finish_right_button_combo_resets_on_a_different_destination() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 24
	sm._select(u)
	sm._finish_right_button(Vector2(300, 300), false)
	sm._finish_right_button(Vector2(300, 300), false)
	assert_eq(int(b._pending_orders[-1]["gait"]), BattleScript.Gait.JOG,
			"2 clicks on the same spot jog")
	sm._finish_right_button(Vector2(900, 900), false)
	assert_eq(int(b._pending_orders[-1]["gait"]), BattleScript.Gait.WALK,
			"a click on a different destination restarts the count at walk")


func test_finish_right_button_resets_the_click_count_after_a_drag() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 25
	sm._select(u)
	sm._click_count = 3
	sm._rmb_dragging = true
	sm._rmb_start = Vector2(300, 300)
	sm._finish_right_button(Vector2(500, 300), false)   # wide enough to form up
	assert_eq(sm._click_count, 0, "a form-up drag resets the click count")


# --- multi-unit drag-to-form-up -------------------------

const EQUAL_DEPTH := SelectionManagerScript.FormUpDist.EQUAL_DEPTH
const EQUAL_WIDTH := SelectionManagerScript.FormUpDist.EQUAL_WIDTH
const EQUAL_DEPTH_SPACE := SelectionManagerScript.FormUpDist.EQUAL_DEPTH_SPACE
const EQUAL_WIDTH_COUNT := SelectionManagerScript.FormUpDist.EQUAL_WIDTH_COUNT
const CHECKERBOARD := SelectionManagerScript.FormUpDist.CHECKERBOARD
const ECHELON_RIGHT := SelectionManagerScript.FormUpDist.ECHELON_RIGHT
const ECHELON_LEFT := SelectionManagerScript.FormUpDist.ECHELON_LEFT


func test_form_up_equal_depth_gives_units_the_same_rank_depth() -> void:
	# Equal-depth (count basis): a bigger unit gets MORE files than a smaller one, but both
	# deploy at (about) the same number of ranks — the uniform battle-line look.
	var sm := _sm()
	var big := _unit()
	big.max_soldiers = 200
	var small := _unit()
	small.max_soldiers = 100
	var slices: Array = sm._form_up_slices([big, small], Vector2(0, 0), Vector2(400, 0), EQUAL_DEPTH)
	assert_eq(slices.size(), 2, "one slice per unit")
	assert_lt(slices[0]["center"].x, slices[1]["center"].x, "slice centres run left to right")
	assert_gt(slices[0]["files"], slices[1]["files"], "the bigger unit deploys more files (wider)")
	var depth_big: int = int(ceil(200.0 / float(slices[0]["files"])))
	var depth_small: int = int(ceil(100.0 / float(slices[1]["files"])))
	assert_almost_eq(float(depth_big), float(depth_small), 1.0,
			"both units form up to within one rank of the same depth")


func test_form_up_equal_depth_uses_average_spacing_for_a_mixed_formation_group() -> void:
	# A mixed-density group (one TIGHT, one LOOSE) shares a pitch based on the AVERAGE
	# spacing_scale across both units, not just the first-selected unit's. Regression
	# test: previously `_files_for_mode` always borrowed units[0]'s spacing_scale, so
	# swapping selection order changed the resulting file counts even though the units
	# and the drag span didn't change.
	var sm := _sm()
	var tight := _unit()
	tight.max_soldiers = 100
	tight.set_formation(UnitScript.FORMATION_TIGHT)
	var loose := _unit()
	loose.max_soldiers = 100
	loose.set_formation(UnitScript.FORMATION_LOOSE)
	assert_ne(tight.spacing_scale, loose.spacing_scale,
			"the two units must actually differ in density for this test to mean anything")

	var slices_tight_first: Array = sm._form_up_slices(
			[tight, loose], Vector2(0, 0), Vector2(400, 0), EQUAL_DEPTH)
	var slices_loose_first: Array = sm._form_up_slices(
			[loose, tight], Vector2(0, 0), Vector2(400, 0), EQUAL_DEPTH)

	# Selection order must not change the file counts -- both orderings solve from the
	# same (order-independent) average spacing.
	assert_eq(int(slices_tight_first[0]["files"]), int(slices_loose_first[1]["files"]),
			"the tight unit's file count is the same regardless of selection order")
	assert_eq(int(slices_tight_first[1]["files"]), int(slices_loose_first[0]["files"]),
			"the loose unit's file count is the same regardless of selection order")


func test_form_up_equal_width_gives_units_the_same_frontage() -> void:
	# Equal-width (space basis): same files for equal-line-share regardless of size, so a big
	# and a small unit get the same frontage (the small one just ends up deeper).
	var sm := _sm()
	var big := _unit()
	big.max_soldiers = 200
	var small := _unit()
	small.max_soldiers = 100
	var slices: Array = sm._form_up_slices([big, small], Vector2(0, 0), Vector2(400, 0), EQUAL_WIDTH)
	assert_eq(slices[0]["files"], slices[1]["files"],
			"equal width gives both units the same frontage")


func test_form_up_equal_width_count_gives_units_the_same_file_count() -> void:
	# Equal-width, count basis: every unit gets the same FILE count directly (the mode
	# EQUAL_WIDTH's space basis is measured against) -- for a same-density group the two
	# coincide (see test_form_up_equal_width_count_matches_equal_width_for_a_same_density_group).
	var sm := _sm()
	var big := _unit()
	big.max_soldiers = 200
	var small := _unit()
	small.max_soldiers = 100
	var slices: Array = sm._form_up_slices(
			[big, small], Vector2(0, 0), Vector2(400, 0), EQUAL_WIDTH_COUNT)
	assert_eq(slices[0]["files"], slices[1]["files"],
			"equal-width-count gives both units the same file count")


func test_form_up_equal_width_count_matches_equal_width_for_a_same_density_group() -> void:
	# The space and count bases of a dimension coincide whenever every unit in the drag
	# shares one spacing_scale -- both derive the same shared file count from the same
	# usable span, just via different search shapes.
	var sm := _sm()
	var big := _unit()
	big.max_soldiers = 200
	var small := _unit()
	small.max_soldiers = 100
	var space_slices: Array = sm._form_up_slices(
			[big, small], Vector2(0, 0), Vector2(400, 0), EQUAL_WIDTH)
	var count_slices: Array = sm._form_up_slices(
			[big, small], Vector2(0, 0), Vector2(400, 0), EQUAL_WIDTH_COUNT)
	assert_eq(int(space_slices[0]["files"]), int(count_slices[0]["files"]),
			"same-density group: equal-width and equal-width-count agree (big unit)")
	assert_eq(int(space_slices[1]["files"]), int(count_slices[1]["files"]),
			"same-density group: equal-width and equal-width-count agree (small unit)")


func test_form_up_equal_width_count_differs_for_a_mixed_density_group() -> void:
	# The count basis holds file count equal (so a TIGHT unit's slice is physically narrower
	# than a LOOSE unit's at the same count); the space basis (EQUAL_WIDTH) instead holds
	# frontage equal, giving them DIFFERENT file counts. Confirms the two bases are genuinely
	# distinct for a mixed group, not just differently-named aliases of the same math.
	var sm := _sm()
	var tight := _unit()
	tight.max_soldiers = 100
	tight.set_formation(UnitScript.FORMATION_TIGHT)
	var loose := _unit()
	loose.max_soldiers = 100
	loose.set_formation(UnitScript.FORMATION_LOOSE)
	assert_ne(tight.spacing_scale, loose.spacing_scale,
			"the two units must actually differ in density for this test to mean anything")
	var slices: Array = sm._form_up_slices(
			[tight, loose], Vector2(0, 0), Vector2(400, 0), EQUAL_WIDTH_COUNT)
	assert_eq(int(slices[0]["files"]), int(slices[1]["files"]),
			"equal-width-count holds file count equal even across densities")


func test_form_up_equal_depth_space_gives_units_the_same_physical_depth() -> void:
	# Equal-depth (space basis, the default): a TIGHT unit packs more ranks into the same
	# physical depth than a LOOSE one, so their RANK COUNTS differ even though their physical
	# depths agree -- the opposite of EQUAL_DEPTH's own count-basis test above.
	var sm := _sm()
	var tight := _unit()
	tight.max_soldiers = 100
	tight.set_formation(UnitScript.FORMATION_TIGHT)
	var loose := _unit()
	loose.max_soldiers = 100
	loose.set_formation(UnitScript.FORMATION_LOOSE)
	assert_ne(tight.spacing_scale, loose.spacing_scale,
			"the two units must actually differ in density for this test to mean anything")
	var slices: Array = sm._form_up_slices(
			[tight, loose], Vector2(0, 0), Vector2(400, 0), EQUAL_DEPTH_SPACE)
	var ranks_tight: int = int(ceil(100.0 / float(slices[0]["files"])))
	var ranks_loose: int = int(ceil(100.0 / float(slices[1]["files"])))
	var depth_tight: float = float(ranks_tight - 1) * UnitScript.FORMATION_SPACING * tight.spacing_scale
	var depth_loose: float = float(ranks_loose - 1) * UnitScript.FORMATION_SPACING * loose.spacing_scale
	assert_ne(ranks_tight, ranks_loose,
			"physically-equal depth gives the tighter unit MORE ranks than the looser one")
	assert_almost_eq(depth_tight, depth_loose, UnitScript.FORMATION_SPACING * tight.spacing_scale,
			"both units form up to within one rank's worth of the same physical depth")


func test_form_up_equal_depth_space_matches_equal_depth_for_a_same_density_group() -> void:
	# For a same-density group the reference-depth conversion is the identity, so the space
	# and count bases of "equal depth" must produce IDENTICAL results.
	var sm := _sm()
	var big := _unit()
	big.max_soldiers = 200
	var small := _unit()
	small.max_soldiers = 100
	var count_slices: Array = sm._form_up_slices(
			[big, small], Vector2(0, 0), Vector2(400, 0), EQUAL_DEPTH)
	var space_slices: Array = sm._form_up_slices(
			[big, small], Vector2(0, 0), Vector2(400, 0), EQUAL_DEPTH_SPACE)
	assert_eq(int(count_slices[0]["files"]), int(space_slices[0]["files"]),
			"same-density group: equal-depth and equal-depth-space agree (big unit)")
	assert_eq(int(count_slices[1]["files"]), int(space_slices[1]["files"]),
			"same-density group: equal-depth and equal-depth-space agree (small unit)")


func test_form_up_single_unit_slice_fills_the_whole_line() -> void:
	# One unit collapses to the old behaviour: no gap, slice centre at the line midpoint,
	# regardless of mode.
	var sm := _sm()
	var u := _unit()
	u.max_soldiers = 120
	# A lone unit fills the 140 px drag with the same frontage the original single-unit deploy
	# used (files_for_halfwidth of the half-width) — in EVERY mode, since holding anything
	# "equal" is vacuous with only one unit to compare.
	var want_files: int = UnitFormation.files_for_halfwidth(70.0, 120)
	for mode in [EQUAL_DEPTH, EQUAL_WIDTH, EQUAL_DEPTH_SPACE, EQUAL_WIDTH_COUNT, CHECKERBOARD,
			ECHELON_RIGHT, ECHELON_LEFT]:
		var slices: Array = sm._form_up_slices([u], Vector2(400, 500), Vector2(540, 500), mode)
		assert_eq(slices.size(), 1, "a lone unit is one slice")
		assert_almost_eq(slices[0]["center"].x, 470.0, 0.001, "centred on the line midpoint")
		assert_eq(slices[0]["center"].y, 500.0, "on the line")
		assert_eq(slices[0]["files"], want_files, "fills the line at the original single-unit frontage")


# --- checkerboard (quincunx) form-up, docs/acies-triplex-design.md ----------

func test_checkerboard_alternates_units_into_front_and_rear_rows() -> void:
	# Three units on a straight west-east drag: 1st and 3rd (by ordinal position) form the
	# front row, 2nd forms the rear row -- one slice per unit either way.
	var sm := _sm()
	var u1 := _unit()
	var u2 := _unit()
	var u3 := _unit()
	var slices: Array = sm._form_up_slices([u1, u2, u3], Vector2(0, 0), Vector2(600, 0), CHECKERBOARD)
	assert_eq(slices.size(), 3, "one slice per unit, front and rear together")
	var by_unit := {}
	for s in slices:
		by_unit[s["unit"]] = s
	assert_almost_eq(by_unit[u1]["center"].y, 0.0, 0.001, "1st unit (front row) stays on the drag line")
	assert_almost_eq(by_unit[u3]["center"].y, 0.0, 0.001, "3rd unit (front row) stays on the drag line")
	assert_gt(by_unit[u2]["center"].y, 1.0, "2nd unit (rear row) sits behind the drag line")


func test_checkerboard_rear_unit_sits_at_the_lateral_midpoint_of_the_front_gap() -> void:
	var sm := _sm()
	var u1 := _unit()
	var u2 := _unit()
	var u3 := _unit()
	var slices: Array = sm._form_up_slices([u1, u2, u3], Vector2(0, 0), Vector2(600, 0), CHECKERBOARD)
	var by_unit := {}
	for s in slices:
		by_unit[s["unit"]] = s
	var midpoint_x: float = (by_unit[u1]["center"].x + by_unit[u3]["center"].x) * 0.5
	assert_almost_eq(by_unit[u2]["center"].x, midpoint_x, 0.5,
			"the rear unit centres on the lateral midpoint between its two front neighbours")


func test_checkerboard_rear_offset_matches_the_line_gap_constant() -> void:
	# The drag runs due east (facing perpendicular, i.e. due south in world Y), so the rear
	# row's offset from the front row is exactly CHECKERBOARD_LINE_GAP along -facing.
	var sm := _sm()
	var u1 := _unit()
	var u2 := _unit()
	var slices: Array = sm._form_up_slices([u1, u2], Vector2(0, 0), Vector2(400, 0), CHECKERBOARD)
	var by_unit := {}
	for s in slices:
		by_unit[s["unit"]] = s
	assert_almost_eq(by_unit[u2]["center"].y, by_unit[u1]["center"].y
			+ SelectionManagerScript.CHECKERBOARD_LINE_GAP, 0.5,
			"rear row sits exactly CHECKERBOARD_LINE_GAP behind the front row")


func test_checkerboard_front_row_gap_is_wider_than_the_flat_multi_unit_gap() -> void:
	# The quincunx "gap ≈ own frontage" rule: two front-row neighbours end up farther apart
	# than the flat MULTI_FORM_UP_GAP two adjacent same-row units get in every other mode.
	var sm := _sm()
	var u1 := _unit()
	u1.max_soldiers = 120
	var u2 := _unit()
	u2.max_soldiers = 120
	var u3 := _unit()
	u3.max_soldiers = 120
	var checkerboard: Array = sm._form_up_slices(
			[u1, u2, u3], Vector2(0, 0), Vector2(900, 0), CHECKERBOARD)
	var equal_depth_space: Array = sm._form_up_slices(
			[u1, u3], Vector2(0, 0), Vector2(900, 0), EQUAL_DEPTH_SPACE)
	var by_unit := {}
	for s in checkerboard:
		by_unit[s["unit"]] = s
	var checkerboard_gap: float = by_unit[u3]["center"].x - by_unit[u1]["center"].x
	var flat_gap: float = equal_depth_space[1]["center"].x - equal_depth_space[0]["center"].x
	assert_gt(checkerboard_gap, flat_gap,
			"checkerboard's front-row spacing is wider than the same two units get under a flat gap")


func test_checkerboard_extra_rear_unit_extends_past_the_last_front_slot() -> void:
	# Four units: front = [u1, u3] (2 units, 1 internal gap), rear = [u2, u4] (2 units) --
	# one more rear unit than front has gaps. u4 must land somewhere distinct from u2's
	# gap-midpoint slot, past the front row's own flank, not stacked on u2.
	var sm := _sm()
	var u1 := _unit()
	var u2 := _unit()
	var u3 := _unit()
	var u4 := _unit()
	var slices: Array = sm._form_up_slices(
			[u1, u2, u3, u4], Vector2(0, 0), Vector2(800, 0), CHECKERBOARD)
	assert_eq(slices.size(), 4, "one slice per unit")
	var by_unit := {}
	for s in slices:
		by_unit[s["unit"]] = s
	assert_gt(by_unit[u4]["center"].x, by_unit[u3]["center"].x,
			"the extra rear unit extends past the last front unit, not back onto an existing slot")
	assert_almost_eq(by_unit[u4]["center"].y, by_unit[u2]["center"].y, 0.001,
			"the extra rear unit stays on the same rear-row depth as the other rear unit")


# --- echelon / oblique order form-up ----------------------------------------
# Drag runs due east (0,0)->(600,0), same convention the checkerboard tests above use: facing
# perpendicular to the drag comes out pointing due "north" (negative world Y), so a unit that
# advances toward the facing direction ends up with a SMALLER (more negative) center.y than
# one that trails behind.

func test_echelon_right_leads_advances_the_right_flank() -> void:
	var sm := _sm()
	var u1 := _unit()
	var u2 := _unit()
	var u3 := _unit()
	var slices: Array = sm._form_up_slices([u1, u2, u3], Vector2(0, 0), Vector2(600, 0), ECHELON_RIGHT)
	assert_eq(slices.size(), 3, "one slice per unit")
	var by_unit := {}
	for s in slices:
		by_unit[s["unit"]] = s
	assert_lt(by_unit[u1]["center"].x, by_unit[u2]["center"].x, "slice centres run left to right")
	assert_lt(by_unit[u2]["center"].x, by_unit[u3]["center"].x, "slice centres run left to right")
	assert_gt(by_unit[u1]["center"].y, by_unit[u2]["center"].y,
			"the left (trailing) unit sits further back than the middle unit")
	assert_gt(by_unit[u2]["center"].y, by_unit[u3]["center"].y,
			"the middle unit sits further back than the right (leading) unit")


func test_echelon_left_mirrors_echelon_right() -> void:
	# ECHELON_LEFT is the same staggered diagonal with the leading flank flipped: whichever
	# depth offset the right flank got under ECHELON_RIGHT, the left flank gets under
	# ECHELON_LEFT, and vice versa.
	var sm := _sm()
	var u1 := _unit()
	var u2 := _unit()
	var u3 := _unit()
	var right: Array = sm._form_up_slices([u1, u2, u3], Vector2(0, 0), Vector2(600, 0), ECHELON_RIGHT)
	var left: Array = sm._form_up_slices([u1, u2, u3], Vector2(0, 0), Vector2(600, 0), ECHELON_LEFT)
	var by_unit_right := {}
	for s in right:
		by_unit_right[s["unit"]] = s
	var by_unit_left := {}
	for s in left:
		by_unit_left[s["unit"]] = s
	assert_almost_eq(by_unit_left[u1]["center"].y, by_unit_right[u3]["center"].y, 0.001,
			"the left flank's depth under ECHELON_LEFT matches the right flank's under ECHELON_RIGHT")
	assert_almost_eq(by_unit_left[u3]["center"].y, by_unit_right[u1]["center"].y, 0.001,
			"the right flank's depth under ECHELON_LEFT matches the left flank's under ECHELON_RIGHT")
	assert_almost_eq(by_unit_left[u2]["center"].y, by_unit_right[u2]["center"].y, 0.001,
			"the middle unit's depth is unchanged by which flank leads")


func test_echelon_step_matches_the_constant() -> void:
	# Exactly two units: the whole stagger reduces to a single ECHELON_STEP depth gap between
	# them, the same "pin the constant directly" pattern as
	# test_checkerboard_rear_offset_matches_the_line_gap_constant above.
	var sm := _sm()
	var u1 := _unit()
	var u2 := _unit()
	var slices: Array = sm._form_up_slices([u1, u2], Vector2(0, 0), Vector2(400, 0), ECHELON_RIGHT)
	var by_unit := {}
	for s in slices:
		by_unit[s["unit"]] = s
	assert_almost_eq(by_unit[u1]["center"].y, by_unit[u2]["center"].y
			+ SelectionManagerScript.ECHELON_STEP, 0.5,
			"the trailing unit sits exactly ECHELON_STEP behind the leading one")


func test_echelon_keeps_the_lateral_layout_and_file_counts_of_a_plain_line() -> void:
	# Echelon only changes DEPTH: the lateral (along-the-drag) position and file count of each
	# slice must match the plain EQUAL_DEPTH_SPACE line exactly -- it's the same layout, just
	# staggered forward/back.
	var sm := _sm()
	var big := _unit()
	big.max_soldiers = 200
	var small := _unit()
	small.max_soldiers = 100
	var plain: Array = sm._form_up_slices(
			[big, small], Vector2(0, 0), Vector2(400, 0), EQUAL_DEPTH_SPACE)
	var echelon: Array = sm._form_up_slices(
			[big, small], Vector2(0, 0), Vector2(400, 0), ECHELON_RIGHT)
	for i in range(2):
		assert_almost_eq(echelon[i]["center"].x, plain[i]["center"].x, 0.001,
				"echelon keeps the plain line's lateral (x) position")
		assert_eq(echelon[i]["files"], plain[i]["files"],
				"echelon keeps the plain line's per-unit file count")


func test_echelon_offsets_average_to_zero() -> void:
	# The stagger is centred on the drag line: it doesn't net advance or withdraw the whole
	# assembly, only spread it into a diagonal -- so the depth offsets relative to the plain
	# line must sum to (about) zero.
	var sm := _sm()
	var u1 := _unit()
	var u2 := _unit()
	var u3 := _unit()
	var u4 := _unit()
	var plain: Array = sm._form_up_slices(
			[u1, u2, u3, u4], Vector2(0, 0), Vector2(800, 0), EQUAL_DEPTH_SPACE)
	var echelon: Array = sm._form_up_slices(
			[u1, u2, u3, u4], Vector2(0, 0), Vector2(800, 0), ECHELON_RIGHT)
	var offset_sum: float = 0.0
	for i in range(4):
		offset_sum += echelon[i]["center"].y - plain[i]["center"].y
	assert_almost_eq(offset_sum, 0.0, 0.01, "the per-unit depth offsets sum to zero")


func test_order_units_for_line_sorts_by_field_position_by_default() -> void:
	# Two units selected right-to-left of where they sit; the default field-position ordering
	# puts the physically-left unit on the left flank regardless of selection order.
	var sm := _sm()
	var left_on_field := _unit()
	left_on_field.position = Vector2(50, 0)
	var right_on_field := _unit()
	right_on_field.position = Vector2(900, 0)
	# Selected right-first, so selection order is [right, left].
	var sel: Array = [right_on_field, left_on_field]
	var by_field: Array = sm._order_units_for_line(sel, Vector2(0, 0), Vector2(1000, 0), false)
	assert_eq(by_field[0], left_on_field, "field order puts the left-positioned unit on the left flank")
	var by_sel: Array = sm._order_units_for_line(sel, Vector2(0, 0), Vector2(1000, 0), true)
	assert_eq(by_sel[0], right_on_field, "selection order keeps the first-selected unit on the left")


func test_issue_form_up_routes_one_order_per_selected_unit() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u1 := _unit()
	u1.uid = 21
	u1.max_soldiers = 100
	u1.position = Vector2(100, 500)
	var u2 := _unit()
	u2.uid = 22
	u2.max_soldiers = 100
	u2.position = Vector2(900, 500)
	b._by_uid[21] = u1
	b._by_uid[22] = u2
	sm._select(u1)
	sm._select(u2)
	var before: int = b._pending_orders.size()
	sm._issue_form_up(Vector2(0, 500), Vector2(1000, 500))
	assert_eq(b._pending_orders.size() - before, 2, "one recorded form-up order per unit")
	# Each order carries exactly one unit and a deploy facing, and their slice centres differ.
	var last_two: Array = b._pending_orders.slice(b._pending_orders.size() - 2)
	assert_eq(last_two[0]["units"].size(), 1, "each form-up order targets a single unit")
	assert_true(last_two[0].has("face") and last_two[1].has("face"), "both routed as form-up orders")
	assert_ne(last_two[0]["x"], last_two[1]["x"], "the two units deploy at distinct slice centres")


func test_multi_unit_form_up_hangs_every_unit_off_one_shared_form_up_order() -> void:
	# docs/atomic-order-decomposition-design.md: the group-level decomposition gets a real
	# home in the order tree -- a FORM_UP order at the top whose children are each unit's
	# own order -- instead of N unrelated standalone orders.
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u1 := _unit()
	u1.uid = 31
	u1.max_soldiers = 100
	u1.position = Vector2(100, 500)
	var u2 := _unit()
	u2.uid = 32
	u2.max_soldiers = 100
	u2.position = Vector2(900, 500)
	b._by_uid[31] = u1
	b._by_uid[32] = u2
	sm._select(u1)
	sm._select(u2)
	sm._issue_form_up(Vector2(0, 500), Vector2(1000, 500))
	assert_not_null(u1.current_order, "each unit still gets its own installed order")
	assert_not_null(u2.current_order)
	assert_not_null(u1.current_order.parent, "a multi-unit deploy tags its order with a group parent")
	assert_eq(u1.current_order.parent, u2.current_order.parent,
			"both units' orders point at the SAME shared group order")
	var group_order: Order = u1.current_order.parent
	assert_eq(group_order.type, Order.Type.FORM_UP, "the shared parent is FORM_UP-flavored")
	assert_eq(group_order.children, [u1.current_order, u2.current_order],
			"the group's children are exactly the two per-unit orders, in slice order")
	assert_null(group_order.parent, "the group order itself is never installed as any unit's own current_order")


func test_single_unit_form_up_is_not_tagged_with_a_group_parent() -> void:
	# A lone-unit drag-line deploy has nothing to group -- its order stays exactly the
	# standalone order it always was, unaffected by the multi-unit grouping above.
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 33
	u.max_soldiers = 100
	u.position = Vector2(0, 500)
	b._by_uid[33] = u
	sm._select(u)
	sm._issue_form_up(Vector2(400, 500), Vector2(540, 500))
	assert_not_null(u.current_order)
	assert_null(u.current_order.parent, "a single-unit form-up is never grouped")


# --- form-up distribution mode (cycle + settings) -------

func test_form_up_dist_starts_at_the_persisted_default() -> void:
	Settings.form_up_dist_default = EQUAL_WIDTH
	var sm := _sm()   # _ready reads the default
	assert_eq(sm._form_up_dist, EQUAL_WIDTH, "the live mode starts at the persisted default")


func test_cycle_form_up_dist_hotkey_flips_the_live_mode() -> void:
	var sm := _sm()
	sm._form_up_dist = EQUAL_DEPTH
	assert_true(sm._dispatch_key(_key_event(SelectionManagerScript.FORM_UP_DIST_CYCLE_KEY)),
			"the cycle key is a handled hotkey")
	assert_eq(sm._form_up_dist, EQUAL_WIDTH, "one press advances to the next mode in the cycle")
	sm._dispatch_key(_key_event(SelectionManagerScript.FORM_UP_DIST_CYCLE_KEY))
	assert_eq(sm._form_up_dist, EQUAL_DEPTH, "a second press wraps back to the first mode")


func test_shift_y_reverses_the_form_up_dist_cycle() -> void:
	# Shift+Y is the reverse of Y, parallel to Shift+Tab reversing Tab: a forward
	# press then a Shift+ press should return to the mode Y started at.
	var sm := _sm()
	sm._form_up_dist = EQUAL_DEPTH
	sm._dispatch_key(_key_event(SelectionManagerScript.FORM_UP_DIST_CYCLE_KEY))
	assert_eq(sm._form_up_dist, EQUAL_WIDTH, "Y advances to the next mode")
	assert_true(
		sm._dispatch_key(_key_event(SelectionManagerScript.FORM_UP_DIST_CYCLE_KEY, false, true)),
		"Shift+Y is a handled hotkey")
	assert_eq(sm._form_up_dist, EQUAL_DEPTH, "Shift+Y steps back to the mode Y started at")


func test_changing_the_default_snaps_the_live_mode_over() -> void:
	# A ☰-menu change to the default (Settings.form_up_dist_default) snaps the live mode to it.
	var sm := _sm()
	sm._form_up_dist = EQUAL_DEPTH
	Settings.form_up_dist_default = EQUAL_WIDTH   # fires Settings.changed -> _on_settings_changed
	assert_eq(sm._form_up_dist, EQUAL_WIDTH, "changing the default in settings updates the live mode")


func test_unrelated_setting_change_keeps_an_on_the_fly_cycle() -> void:
	# Cycling the live mode then toggling an unrelated setting must NOT reset the cycled mode.
	Settings.form_up_dist_default = EQUAL_DEPTH
	var sm := _sm()
	sm._form_up_dist = EQUAL_WIDTH   # cycled away from the default on the fly
	Settings.edge_scroll = not Settings.edge_scroll   # unrelated Settings.changed
	assert_eq(sm._form_up_dist, EQUAL_WIDTH, "an unrelated setting change leaves the cycled mode intact")
	Settings.edge_scroll = not Settings.edge_scroll   # restore


func test_form_up_dist_default_clamps_out_of_range() -> void:
	# A corrupt/hand-edited cfg can't propagate an out-of-range mode: the setter clamps it.
	Settings.form_up_dist_default = 99
	assert_eq(Settings.form_up_dist_default, Settings.FORM_UP_DIST_MAX,
			"an over-range default clamps to the last mode")
	Settings.form_up_dist_default = -5
	assert_eq(Settings.form_up_dist_default, 0, "a negative default clamps to the first mode")


# --- group-attack-mode cycle (X, Shift+X reverses) -------

func test_x_cycles_group_attack_mode_and_shift_x_reverses() -> void:
	# Shift+X reverses X, the same parallelism as Shift+Y reversing Y and
	# Shift+Tab reversing Tab.
	var sm := _sm()
	var start: int = sm._group_attack_mode
	assert_true(sm._dispatch_key(_key_event(SelectionManagerScript.GROUP_ATTACK_CYCLE_KEY)),
			"X is a handled hotkey")
	var advanced: int = sm._group_attack_mode
	assert_ne(advanced, start, "X advances to the other group-attack mode")
	assert_true(
		sm._dispatch_key(_key_event(SelectionManagerScript.GROUP_ATTACK_CYCLE_KEY, false, true)),
		"Shift+X is a handled hotkey")
	assert_eq(sm._group_attack_mode, start, "Shift+X steps back to the mode X started at")


# --- move-order ghost preview reads per-formation geometry --------------------
# _draw_formation_preview used to call UnitFormation.slots(u, u.soldiers) directly,
# bypassing Unit.formation_slots() -- the per-formation layout dispatch. So the
# destination ghost still showed the wide-line grid for a squared unit (a real square
# footprint) instead of the live shape the unit actually stands on. Fixed
# to call u.formation_slots(u.soldiers) instead.

func test_formation_preview_slots_match_the_units_live_square_shape() -> void:
	# The preview must read the SAME slot layout the unit's own soldier_world_slots
	# uses -- not the generic wide-line grid every non-square formation shares.
	var u := _unit()
	u.max_soldiers = 120
	u.facing = Vector2.DOWN
	u.set_formation(Unit.FORMATION_SQUARE)
	var preview_slots := u.formation_slots(u.soldiers)
	# soldier_world_slots is formation_slots rotated+offset to the unit's world
	# position/facing; at position ZERO with the same rotation convention the
	# preview's local slots must equal the live grid's local slots one-for-one.
	var ang: float = u.facing.angle() + PI * 0.5
	var live_local := PackedVector2Array()
	for p in u.soldier_world_slots(u.soldiers):
		live_local.push_back(p.rotated(-ang))
	assert_eq(preview_slots.size(), live_local.size(),
		"the preview has one dot per soldier, matching the live grid")
	for i in range(preview_slots.size()):
		assert_true(preview_slots[i].is_equal_approx(live_local[i]),
			"preview slot %d matches the unit's live square slot" % i)


func test_formation_preview_bbox_is_square_not_the_wide_line_for_a_squared_unit() -> void:
	# The bug this fixes, in shape terms: the old UnitFormation.slots() call always
	# produced the wide 2:1 line, even for a squared unit. The preview's bbox must now
	# be roughly square (matching test_square_slot_bbox_is_roughly_square_not_two_to_one
	# in test_formation_square.gd), not the wide line's aspect.
	var u := _unit()
	u.max_soldiers = 120
	u.facing = Vector2.DOWN
	u.set_formation(Unit.FORMATION_SQUARE)
	var slots := u.formation_slots(u.soldiers)
	var min_p: Vector2 = slots[0]
	var max_p: Vector2 = slots[0]
	for p in slots:
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	var bbox: Vector2 = max_p - min_p
	assert_almost_eq(bbox.x / bbox.y, 1.0, 0.15,
		"the preview's own footprint reads square, not the wide line's ~2:1 aspect")


func test_formation_preview_matches_schiltron_shape_too() -> void:
	# Schiltron shares the same hollow-square geometry as orbis via in_square(),
	# so the preview fix covers it automatically -- confirm it does.
	var u := _unit()
	u.max_soldiers = 120
	u.facing = Vector2.DOWN
	u.set_formation(Unit.FORMATION_SCHILTRON)
	var preview_slots := u.formation_slots(u.soldiers)
	var files: int = UnitFormation.square_files(u.soldiers)
	var expected := UnitFormation.block_slots(u.soldiers, files, Unit.FORMATION_SPACING * u.spacing_scale)
	assert_eq(preview_slots.size(), expected.size())
	for i in range(preview_slots.size()):
		assert_true(preview_slots[i].is_equal_approx(expected[i]),
			"preview slot %d matches the schiltron's square grid" % i)


class _StubBattleWithRoute:
	extends Node
	var pending_points: Array[Vector2] = []
	func pending_append_points_for(_u: Unit) -> Array[Vector2]:
		return pending_points
	# _draw_demo_pointer (reached because the test arms the demo-orders overlay via
	# Replay.mode/show_demo_orders) reads _battle.current_tick() to look up the
	# recorded pointer track; return a plain 0 -- no pointer track is being tested here.
	func current_tick() -> int:
		return 0


func test_draw_formation_preview_renders_for_a_squared_unit_with_a_move_order() -> void:
	# Render smoke: drive the REAL _draw() path (hold-Space-equivalent via the demo
	# overlay flag) with a squared, moving unit parented under a stub Battle, and
	# confirm it completes without error. Proves _draw_formation_preview is actually
	# reachable and wired to a live unit's move order, not just exercised in isolation.
	var battle := _StubBattleWithRoute.new()
	add_child_autofree(battle)
	var sm = SelectionManagerScript.new()
	battle.add_child(sm)   # so _battle = get_parent() resolves to the stub

	var u := UnitScript.new()
	battle.add_child(u)
	u.add_to_group("units")
	u.team = 0
	u.facing = Vector2.DOWN
	u.max_soldiers = 120
	u.set_formation(Unit.FORMATION_SQUARE)
	u.has_move_target = true
	u.move_target = Vector2(400, 400)

	var prev_mode = Replay.mode
	var prev_flag := Replay.show_demo_orders
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.show_demo_orders = true

	sm.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame

	Replay.mode = prev_mode
	Replay.show_demo_orders = prev_flag
	assert_true(u.has_move_target, "the move order is still live after the draw pass")
