extends GutTest
## The ☰-menu picker for the default multi-unit form-up distribution. Instantiating the HUD
## also smoke-tests that its menu builds (the radio items / labelled separator added for this
## picker) without a runtime error — nothing else instantiates the HUD headlessly.

const HUDScript = preload("res://scripts/HUD.gd")
const SelectionManagerScript = preload("res://scripts/SelectionManager.gd")
const SettingsScript = preload("res://scripts/Settings.gd")

var _orig_default: int
var _orig_cycle: Array
var _orig_reform: bool


func before_each() -> void:
	_orig_default = Settings.form_up_dist_default
	_orig_cycle = Settings.form_up_dist_cycle.duplicate()
	_orig_reform = Settings.reform_before_move
	# Pin the default cycle; a developer's persisted cfg can deviate and break these tests locally.
	Settings.form_up_dist_cycle = [SelectionManagerScript.FormUpDist.EQUAL_DEPTH,
			SelectionManagerScript.FormUpDist.EQUAL_WIDTH]


func after_each() -> void:
	Settings.form_up_dist_default = _orig_default
	Settings.form_up_dist_cycle = _orig_cycle.duplicate()
	Settings.reform_before_move = _orig_reform


func _hud() -> CanvasLayer:
	var hud = HUDScript.new()
	add_child_autofree(hud)   # runs _ready(): builds the menu, info panel, overlay
	return hud


func _popup(hud) -> PopupMenu:
	return hud._menu_button.get_popup()


func test_menu_builds_with_the_form_up_radio_items() -> void:
	var hud := _hud()
	var popup := _popup(hud)
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_DEPTH), 0,
			"the equal-depth (count) radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_WIDTH), 0,
			"the equal-width (space) radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_DEPTH_SPACE), 0,
			"the equal-depth (space) radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_WIDTH_COUNT), 0,
			"the equal-width (count) radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_DEPTH_SPACE), 0,
			"the equal-depth (space) cycle checkbox is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_WIDTH_COUNT), 0,
			"the equal-width (count) cycle checkbox is present")


func test_menu_builds_with_the_checkerboard_radio_and_cycle_items() -> void:
	var hud := _hud()
	var popup := _popup(hud)
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_CHECKERBOARD), 0,
			"the checkerboard radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_CHECKERBOARD), 0,
			"the checkerboard cycle checkbox is present")


func test_checkerboard_cycle_checkbox_starts_unchecked_by_default() -> void:
	# Checkerboard is deliberately excluded from Settings.form_up_dist_cycle's own DEFAULT
	# VALUE (docs/acies-triplex-design.md) -- distinct from SelectionManager.FORM_UP_DIST_CYCLE,
	# the canonical "every mode that exists" list, which DOES include it (see that constant's
	# own doc comment). A fresh player's menu shouldn't show checkerboard already enrolled in
	# the Y-key cycle.
	var s := SettingsScript.new()
	autofree(s)
	Settings.form_up_dist_cycle = s.form_up_dist_cycle.duplicate()
	var hud := _hud()
	var popup := _popup(hud)
	assert_false(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_CHECKERBOARD)),
			"checkerboard's cycle checkbox is unchecked under the fresh-install default cycle")


func test_menu_builds_with_the_echelon_radio_and_cycle_items() -> void:
	var hud := _hud()
	var popup := _popup(hud)
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_ECHELON_RIGHT), 0,
			"the echelon-right radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_ECHELON_LEFT), 0,
			"the echelon-left radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_ECHELON_RIGHT), 0,
			"the echelon-right cycle checkbox is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_ECHELON_LEFT), 0,
			"the echelon-left cycle checkbox is present")


func test_echelon_cycle_checkboxes_start_unchecked_by_default() -> void:
	# Same reasoning as checkerboard above: echelon is excluded from Settings.form_up_dist_cycle's
	# own default value, even though it's a real mode in the canonical FORM_UP_DIST_CYCLE list.
	var s := SettingsScript.new()
	autofree(s)
	Settings.form_up_dist_cycle = s.form_up_dist_cycle.duplicate()
	var hud := _hud()
	var popup := _popup(hud)
	assert_false(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_ECHELON_RIGHT)),
			"echelon-right's cycle checkbox is unchecked under the fresh-install default cycle")
	assert_false(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_ECHELON_LEFT)),
			"echelon-left's cycle checkbox is unchecked under the fresh-install default cycle")


func test_picking_the_echelon_right_radio_sets_and_persists_the_default() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_FORMUP_ECHELON_RIGHT)
	assert_eq(Settings.form_up_dist_default, SelectionManagerScript.FormUpDist.ECHELON_RIGHT,
			"choosing the echelon-right item sets the persisted default")
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_ECHELON_RIGHT)),
			"and the radio re-syncs to the new default")
	assert_true(Settings.form_up_dist_cycle.has(SelectionManagerScript.FormUpDist.ECHELON_RIGHT),
			"picking echelon-right as the default also enrolls it in the cycle (default must stay reachable)")


func test_picking_the_checkerboard_radio_sets_and_persists_the_default() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_FORMUP_CHECKERBOARD)
	assert_eq(Settings.form_up_dist_default, SelectionManagerScript.FormUpDist.CHECKERBOARD,
			"choosing the checkerboard item sets the persisted default")
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_CHECKERBOARD)),
			"and the radio re-syncs to the new default")
	assert_true(Settings.form_up_dist_cycle.has(SelectionManagerScript.FormUpDist.CHECKERBOARD),
			"picking checkerboard as the default also enrolls it in the cycle (default must stay reachable)")


func test_radio_reflects_equal_depth_space_as_the_persisted_default() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH_SPACE
	Settings.form_up_dist_cycle = [SelectionManagerScript.FormUpDist.EQUAL_DEPTH_SPACE,
			SelectionManagerScript.FormUpDist.EQUAL_WIDTH]
	var hud := _hud()   # _ready -> _sync_setting_toggles reads the default
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_DEPTH_SPACE)),
			"equal-depth (space) is checked as the current default")
	assert_false(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_WIDTH)),
			"a different mode's radio is unchecked")


func test_picking_the_equal_depth_space_radio_sets_and_persists_the_default() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	Settings.form_up_dist_cycle = [SelectionManagerScript.FormUpDist.EQUAL_DEPTH,
			SelectionManagerScript.FormUpDist.EQUAL_DEPTH_SPACE]
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_FORMUP_EQUAL_DEPTH_SPACE)
	assert_eq(Settings.form_up_dist_default, SelectionManagerScript.FormUpDist.EQUAL_DEPTH_SPACE,
			"choosing the equal-depth (space) item sets the persisted default")
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(
			popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_DEPTH_SPACE)),
			"and the radio re-syncs to the new default")


func test_radios_reflect_the_persisted_default() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_WIDTH
	var hud := _hud()   # _ready -> _sync_setting_toggles reads the default
	var popup := _popup(hud)
	assert_false(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_DEPTH)),
			"equal-depth is unchecked when the default is equal-width")
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_WIDTH)),
			"equal-width is checked as the current default")


func test_picking_a_radio_sets_and_persists_the_default() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	var hud := _hud()
	# Drive the menu handler as the popup's id_pressed signal would.
	hud._on_menu_id(HUDScript.MENU_FORMUP_EQUAL_WIDTH)
	assert_eq(Settings.form_up_dist_default, SelectionManagerScript.FormUpDist.EQUAL_WIDTH,
			"choosing the equal-width item sets the persisted default")
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_WIDTH)),
			"and the radio re-syncs to the new default")


# --- reform-before-move menu item ---

func test_reform_menu_item_present() -> void:
	var hud := _hud()
	var popup := _popup(hud)
	assert_gte(popup.get_item_index(HUDScript.MENU_REFORM_BEFORE_MOVE), 0,
			"the reform-before-move check item is present in the menu")


func test_reform_menu_check_reflects_setting() -> void:
	Settings.reform_before_move = false
	var hud := _hud()
	var popup := _popup(hud)
	assert_false(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_REFORM_BEFORE_MOVE)),
			"item is unchecked when setting is false")


func test_reform_menu_toggle_flips_setting() -> void:
	Settings.reform_before_move = true
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_REFORM_BEFORE_MOVE)
	assert_false(Settings.reform_before_move,
			"toggling the menu item turns reform off when it was on")
	hud._on_menu_id(HUDScript.MENU_REFORM_BEFORE_MOVE)
	assert_true(Settings.reform_before_move,
			"toggling again turns it back on")


# --- form-up cycle checkboxes: the default mode can't be excluded -----------
# A player could uncheck the cycle entry for the battle DEFAULT, leaving it unreachable by
# the Y-key cycle with no feedback. Disable that one checkbox instead of allowing the
# inconsistency and warning after the fact.

func test_cycle_checkbox_for_the_default_mode_is_disabled() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	var hud := _hud()
	var popup := _popup(hud)
	assert_true(popup.is_item_disabled(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_DEPTH)),
			"the cycle checkbox for the current default is disabled")
	assert_false(popup.is_item_disabled(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_WIDTH)),
			"the non-default cycle checkbox stays enabled")


func test_cycle_checkbox_disable_follows_the_default_when_it_changes() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_FORMUP_EQUAL_WIDTH)   # change the default
	var popup := _popup(hud)
	assert_false(popup.is_item_disabled(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_DEPTH)),
			"the old default's cycle checkbox re-enables")
	assert_true(popup.is_item_disabled(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_WIDTH)),
			"the new default's cycle checkbox becomes disabled")


func test_changing_default_to_a_mode_excluded_from_the_cycle_adds_it() -> void:
	# The symmetric path to the bug: narrow the cycle to DEPTH only (allowed -- DEPTH is still
	# the default), then flip the default to the excluded mode (WIDTH). The default must stay
	# Y-key reachable, so WIDTH gets added back to the cycle automatically.
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	Settings.form_up_dist_cycle = [SelectionManagerScript.FormUpDist.EQUAL_DEPTH]
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_FORMUP_EQUAL_WIDTH)
	assert_true(Settings.form_up_dist_cycle.has(SelectionManagerScript.FormUpDist.EQUAL_WIDTH),
			"changing the default to an excluded mode adds it back to the cycle")
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_WIDTH)),
			"the newly-defaulted mode's cycle checkbox shows checked, not stuck unchecked")


func test_picking_a_cycle_checkbox_item_toggles_it_via_the_menu_dispatch() -> void:
	# Drives the MENU_FORMUP_CYCLE_* branch of _on_menu_id (as the popup's id_pressed signal
	# would), not _toggle_form_up_cycle directly -- proves the menu dispatch itself reaches it.
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	Settings.form_up_dist_cycle = [SelectionManagerScript.FormUpDist.EQUAL_DEPTH]
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_FORMUP_CYCLE_WIDTH)
	assert_true(Settings.form_up_dist_cycle.has(SelectionManagerScript.FormUpDist.EQUAL_WIDTH),
			"picking the equal-width cycle checkbox adds it to the cycle")
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_WIDTH)),
			"and the checkbox re-syncs to checked")
	hud._on_menu_id(HUDScript.MENU_FORMUP_CYCLE_WIDTH)
	assert_false(Settings.form_up_dist_cycle.has(SelectionManagerScript.FormUpDist.EQUAL_WIDTH),
			"picking it again removes it from the cycle")


func test_toggling_the_default_out_of_the_cycle_is_a_no_op() -> void:
	# Defense-in-depth: even if _toggle_form_up_cycle is reached for the disabled item, the
	# default stays in the cycle (the invariant the disabled checkbox is meant to guarantee).
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	var hud := _hud()
	hud._toggle_form_up_cycle(SelectionManagerScript.FormUpDist.EQUAL_DEPTH)
	assert_true(Settings.form_up_dist_cycle.has(SelectionManagerScript.FormUpDist.EQUAL_DEPTH),
			"the current default cannot be removed from the cycle")
