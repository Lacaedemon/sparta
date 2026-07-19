extends GutTest
## The selected-unit info panel's walk_advance / reform_before_move / file_major_reform
## checkboxes: hidden with no unit shown, reflecting the FIRST selected unit's own values
## when one is, and routing a click through SelectionManager to the whole current selection.

const HUDScript = preload("res://scripts/HUD.gd")
const UnitScript = preload("res://scripts/Unit.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const SelectionManagerScript = preload("res://scripts/SelectionManager.gd")


func _hud() -> CanvasLayer:
	var hud = HUDScript.new()
	add_child_autofree(hud)   # runs _ready(): builds the menu, info panel, checkboxes
	return hud


func _unit() -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	return u


func test_checkboxes_hidden_with_no_unit_selected() -> void:
	var hud := _hud()
	assert_false(hud._walk_advance_check.visible, "walk_advance checkbox starts hidden")
	assert_false(hud._reform_before_move_check.visible, "reform_before_move checkbox starts hidden")
	assert_false(hud._file_major_reform_check.visible, "file_major_reform checkbox starts hidden")


func test_show_unit_reveals_and_syncs_the_checkboxes() -> void:
	var hud := _hud()
	var u := _unit()
	u.walk_advance = true
	u.reform_before_move = false
	u.file_major_reform = false
	hud.show_unit(u, 1)
	assert_true(hud._walk_advance_check.visible, "showing a unit reveals the checkbox")
	assert_true(hud._reform_before_move_check.visible, "and the other one")
	assert_true(hud._file_major_reform_check.visible, "and the file_major_reform one")
	assert_true(hud._walk_advance_check.button_pressed, "the checkbox reflects the unit's own value")
	assert_false(hud._reform_before_move_check.button_pressed, "for both settings")
	assert_false(hud._file_major_reform_check.button_pressed, "and file_major_reform too")


func test_show_unit_reflects_the_first_selected_units_value() -> void:
	# group_count > 1 shows "(+N more)" in the label but still reflects the FIRST unit
	# passed -- the same convention _refresh_hud/show_unit already use for every other
	# per-unit stat in the panel.
	var hud := _hud()
	var lead := _unit()
	lead.walk_advance = true
	hud.show_unit(lead, 3)
	assert_true(hud._walk_advance_check.button_pressed, "the checkbox shows the lead unit's value")


func test_clear_unit_hides_the_checkboxes() -> void:
	var hud := _hud()
	var u := _unit()
	hud.show_unit(u, 1)
	hud.clear_unit()
	assert_false(hud._walk_advance_check.visible, "clearing the selection hides the checkbox")
	assert_false(hud._reform_before_move_check.visible, "and the other one")
	assert_false(hud._file_major_reform_check.visible, "and the file_major_reform one")


func test_walk_advance_checkbox_toggle_writes_the_whole_selection() -> void:
	var hud := _hud()
	var sm := SelectionManagerScript.new()
	autofree(sm)
	var b := BattleScript.new()
	autofree(b)
	sm._battle = b
	var u1 := UnitScript.new()
	add_child_autofree(u1)
	u1.uid = 1
	u1.walk_advance = false
	var u2 := UnitScript.new()
	add_child_autofree(u2)
	u2.uid = 2
	u2.walk_advance = false
	b._by_uid[1] = u1
	b._by_uid[2] = u2
	sm._select(u1)
	sm._select(u2)
	hud._sel_mgr = sm

	hud._on_walk_advance_toggled(true)
	assert_true(u1.walk_advance, "the checkbox toggle applies to every selected unit")
	assert_true(u2.walk_advance, "not just the lead one")


func test_reform_before_move_checkbox_toggle_writes_the_whole_selection() -> void:
	var hud := _hud()
	var sm := SelectionManagerScript.new()
	autofree(sm)
	var b := BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := UnitScript.new()
	add_child_autofree(u)
	u.uid = 1
	u.reform_before_move = true
	b._by_uid[1] = u
	sm._select(u)
	hud._sel_mgr = sm

	hud._on_reform_before_move_toggled(false)
	assert_false(u.reform_before_move, "the checkbox toggle writes reform_before_move")


func test_file_major_reform_checkbox_toggle_writes_the_whole_selection() -> void:
	var hud := _hud()
	var sm := SelectionManagerScript.new()
	autofree(sm)
	var b := BattleScript.new()
	autofree(b)
	sm._battle = b
	var u1 := UnitScript.new()
	add_child_autofree(u1)
	u1.uid = 1
	u1.file_major_reform = true
	var u2 := UnitScript.new()
	add_child_autofree(u2)
	u2.uid = 2
	u2.file_major_reform = true
	b._by_uid[1] = u1
	b._by_uid[2] = u2
	sm._select(u1)
	sm._select(u2)
	hud._sel_mgr = sm

	hud._on_file_major_reform_toggled(false)
	assert_false(u1.file_major_reform, "the checkbox toggle applies to every selected unit")
	assert_false(u2.file_major_reform, "not just the lead one")


func test_walk_advance_checkbox_toggle_is_a_noop_with_no_selection_manager() -> void:
	# A HUD instantiated standalone (as in these tests, or before Battle assigns a
	# SelectionManager sibling) must not error if the checkbox fires before _sel_mgr
	# resolves.
	var hud := _hud()
	hud._sel_mgr = null
	hud._on_walk_advance_toggled(true)   # must not error
	hud._on_reform_before_move_toggled(true)   # must not error
	hud._on_file_major_reform_toggled(true)   # must not error
	assert_null(hud._sel_mgr, "sanity: still no SelectionManager after the no-op toggles")


func test_ctrl_bar_update_reform_is_a_noop_with_no_unit() -> void:
	# Mirrors _ctrl_bar_update_formation's own null-unit guard: called with no unit shown
	# (e.g. right after _build_ctrl_bar, before any selection), it must leave the button's
	# state untouched rather than erroring on a null unit.reform_before_move read.
	var hud := _hud()
	var before: bool = hud._ctrl_reform_btn.button_pressed
	hud._ctrl_bar_update_reform(null)
	assert_eq(hud._ctrl_reform_btn.button_pressed, before,
		"the quick-toggle button is untouched when no unit is passed")
