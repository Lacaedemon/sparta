extends GutTest
## Choosing the explicatio from the keyboard: Alt+B steps the drill, Alt+Shift+B the side and
## Alt+Ctrl+B the ground (ExplicatioChoice), the B family that deals the explicatio reads the
## choice into the order, and the HUD shows it. The defaults stay what B dealt before.

const SelectionManagerScript = preload("res://scripts/SelectionManager.gd")
const HUDScript = preload("res://scripts/HUD.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")

const HALF_FILE := UnitFormation.ExplicatioDrill.HALF_FILE
const ALTERNATE_RANK := UnitFormation.ExplicatioDrill.ALTERNATE_RANK


## Records what the selection manager tells the HUD.
class StubHud:
	extends RefCounted
	var flashes: Array = []
	var summaries: Array = []

	func flash_message(text: String) -> void:
		flashes.append(text)

	func update_explicatio(summary: String) -> void:
		summaries.append(summary)


func _sm() -> Node2D:
	var sm = SelectionManagerScript.new()
	add_child_autofree(sm)
	return sm


func _key(keycode: int, alt: bool = true, ctrl: bool = false, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.alt_pressed = alt
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	return ev


func test_defaults_are_half_file_outward_lengthen() -> void:
	var sm := _sm()
	assert_eq(sm.explicatio_drill, HALF_FILE, "B deals the half-file drill by default")
	assert_eq(sm.explicatio_side, UnitFormation.ExplicatioSide.OUTWARD, "outward by default")
	assert_eq(sm.explicatio_ground, UnitFormation.ExplicatioGround.LENGTHEN, "lengthening by default")
	assert_eq(sm.get_explicatio_summary(), "half-file, outward, lengthen", "and the HUD words them so")


func test_alt_b_steps_the_drill_and_wraps() -> void:
	var sm := _sm()
	assert_true(sm._dispatch_key(_key(KEY_B)), "Alt+B is a handled hotkey")
	assert_eq(sm.explicatio_drill, ALTERNATE_RANK, "the first press chooses the alternate rank")
	assert_true(sm._dispatch_key(_key(KEY_B)), "a second press is handled")
	assert_eq(sm.explicatio_drill, HALF_FILE, "and wraps back to the half-file drill")


func test_alt_shift_b_steps_through_every_side() -> void:
	var sm := _sm()
	var seen: Array = []
	for _i in 4:
		assert_true(sm._dispatch_key(_key(KEY_B, true, false, true)), "Alt+Shift+B is handled")
		seen.append(sm.explicatio_side)
	assert_eq(seen, [UnitFormation.ExplicatioSide.INWARD, UnitFormation.ExplicatioSide.SPEAR_SIDE,
			UnitFormation.ExplicatioSide.SHIELD_SIDE, UnitFormation.ExplicatioSide.OUTWARD],
			"inward, spear side, shield side, then back to outward")
	assert_eq(sm.explicatio_drill, HALF_FILE, "the drill is untouched")


func test_alt_ctrl_b_steps_the_ground() -> void:
	var sm := _sm()
	assert_true(sm._dispatch_key(_key(KEY_B, true, true)), "Alt+Ctrl+B is handled")
	assert_eq(sm.explicatio_ground, UnitFormation.ExplicatioGround.SAME_GROUND, "same ground first")
	assert_true(sm._dispatch_key(_key(KEY_B, true, true)), "again")
	assert_eq(sm.explicatio_ground, UnitFormation.ExplicatioGround.LENGTHEN, "and back to lengthen")


func test_alt_with_another_key_is_not_claimed() -> void:
	var sm := _sm()
	assert_false(sm._dispatch_explicatio_choice(_key(KEY_N)), "Alt+N is not an explicatio choice")
	assert_false(sm._dispatch_explicatio_choice(_key(KEY_B, false)), "plain B is not one either")


func test_alt_b_orders_nothing() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = 7
	u.soldiers = 120
	u.max_soldiers = 120
	b._by_uid[7] = u
	sm._select(u)
	var start: int = UnitFormation.frontage(u)
	sm._dispatch_key(_key(KEY_B))
	assert_eq(UnitFormation.frontage(u), start, "Alt+B only chooses; the frontage stays")
	assert_true(b._pending_orders.is_empty(), "and nothing is enqueued")


func test_the_choice_reaches_the_order_b_deals() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = 7
	u.soldiers = 120
	u.max_soldiers = 120
	b._by_uid[7] = u
	sm._select(u)
	sm._dispatch_key(_key(KEY_B))
	sm._dispatch_key(_key(KEY_B, true, false, true))
	sm._dispatch_key(_key(KEY_B, true, true))
	sm._dispatch_key(_key(KEY_B, false))
	var cmd: Dictionary = b._pending_orders.back()
	assert_eq(int(cmd["explicatio"]), ALTERNATE_RANK, "the order names the chosen drill")
	assert_eq(int(cmd["explicatio_side"]), UnitFormation.ExplicatioSide.INWARD, "and side")
	assert_eq(int(cmd["explicatio_ground"]), UnitFormation.ExplicatioGround.SAME_GROUND, "and ground")


func test_default_b_order_carries_no_variant_fields() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = 7
	u.soldiers = 120
	u.max_soldiers = 120
	b._by_uid[7] = u
	sm._select(u)
	sm._dispatch_key(_key(KEY_B, false))
	var cmd: Dictionary = b._pending_orders.back()
	assert_eq(int(cmd["explicatio"]), HALF_FILE, "the half-file drill")
	assert_false(cmd.has("explicatio_side"), "no side field, so the replay is as before")
	assert_false(cmd.has("explicatio_ground"), "no ground field either")


func test_each_choice_flashes_and_updates_the_hud() -> void:
	var sm := _sm()
	var hud := StubHud.new()
	sm._hud = hud
	sm._dispatch_key(_key(KEY_B))
	assert_eq(hud.flashes, ["Explicatio: alternate rank, outward, lengthen"], "the toast names it")
	assert_eq(hud.summaries, ["alternate rank, outward, lengthen"], "the control bar is told")


func test_key_label_names_alt() -> void:
	var sm := _sm()
	assert_eq(sm._key_label(_key(KEY_B, true, false, true)), "Alt+Shift+B", "the demo overlay says Alt")


func test_hud_button_shows_the_choice() -> void:
	var h := HUDScript.new()
	autofree(h)
	h._ctrl_explicatio_btn = Button.new()
	autofree(h._ctrl_explicatio_btn)
	h.update_explicatio("")
	assert_eq(h._ctrl_explicatio_btn.text, "Explicatio: half-file, outward, lengthen",
			"an empty summary shows the defaults")
	h.update_explicatio("alternate rank, inward, same ground")
	assert_eq(h._ctrl_explicatio_btn.text, "Explicatio: alternate rank, inward, same ground",
			"a chosen reading shows as given")


func test_hud_button_press_steps_the_drill() -> void:
	var sm := _sm()
	sm.toggle_explicatio_drill()
	assert_eq(sm.explicatio_drill, ALTERNATE_RANK, "the button steps the drill like Alt+B")


func test_built_control_bar_shows_the_default_and_follows_the_selection_manager() -> void:
	var h = HUDScript.new()
	add_child_autofree(h)
	var button: Button = h._ctrl_explicatio_btn
	assert_eq(button.text, "Explicatio: half-file, outward, lengthen", "the bar starts on the defaults")
	var sm := _sm()
	sm.explicatio_side = UnitFormation.ExplicatioSide.SHIELD_SIDE
	h._sel_mgr = sm
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	h.show_unit(u, 1)
	assert_eq(button.text, "Explicatio: half-file, shield side, lengthen",
			"showing a unit reads the selection manager's choice")
	button.pressed.emit()
	assert_eq(sm.explicatio_drill, ALTERNATE_RANK, "pressing the button steps the drill")
