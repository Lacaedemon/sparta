extends GutTest
## The screen-margins HUD layout: distance legend top-left, unit info panel
## center-left, unit settings bottom-left, unit card tray bottom-right, menu button +
## tray toggle top-right (unaffected here -- their own anchor logic is covered by
## test_hud_fps.gd and test_hud_unit_card_tray.gd already).

const HUDScript = preload("res://scripts/HUD.gd")
const UnitScript = preload("res://scripts/Unit.gd")


func _hud() -> CanvasLayer:
	var hud = HUDScript.new()
	add_child_autofree(hud)
	return hud


func _unit() -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	return u


func test_distance_legend_anchors_top_left() -> void:
	var hud := _hud()
	assert_eq(hud._legend_panel.anchor_left, 0.0, "left edge anchors to the left margin")
	assert_eq(hud._legend_panel.anchor_top, 0.0, "top edge anchors to the top margin")
	assert_eq(hud._legend_panel.grow_horizontal, Control.GROW_DIRECTION_END,
			"grows rightward, away from the corner")
	assert_eq(hud._legend_panel.grow_vertical, Control.GROW_DIRECTION_END,
			"grows downward, away from the corner")


func test_unit_card_tray_anchors_bottom_right() -> void:
	var hud := _hud()
	assert_eq(hud._unit_card_tray.anchor_left, 1.0, "left edge anchors to the right margin")
	assert_eq(hud._unit_card_tray.anchor_top, 1.0, "top edge anchors to the bottom margin")
	assert_eq(hud._unit_card_tray.grow_horizontal, Control.GROW_DIRECTION_BEGIN,
			"grows leftward, away from the corner")
	assert_eq(hud._unit_card_tray.grow_vertical, Control.GROW_DIRECTION_BEGIN,
			"grows upward, away from the corner")


func test_info_panel_anchors_center_left() -> void:
	var hud := _hud()
	assert_eq(hud._info_panel.anchor_left, 0.0, "left edge anchors to the left margin")
	assert_eq(hud._info_panel.anchor_top, 0.5, "top edge anchors to the vertical center")
	assert_eq(hud._info_panel.anchor_bottom, 0.5, "bottom edge anchors to the vertical center")
	assert_eq(hud._info_panel.grow_vertical, Control.GROW_DIRECTION_BOTH,
			"grows symmetrically up and down as content grows, staying centered")


func test_settings_panel_anchors_bottom_left() -> void:
	var hud := _hud()
	assert_eq(hud._settings_panel.anchor_left, 0.0, "left edge anchors to the left margin")
	assert_eq(hud._settings_panel.anchor_top, 1.0, "top edge anchors to the bottom margin")
	assert_eq(hud._settings_panel.grow_vertical, Control.GROW_DIRECTION_BEGIN,
			"grows upward, clearing the control bar beneath it")


func test_settings_panel_holds_the_walk_advance_and_reform_controls() -> void:
	# The three per-unit controls moved out of the info panel into their own bottom-left
	# panel -- confirm they actually live there now, not orphaned or left behind.
	var hud := _hud()
	assert_true(hud._settings_panel.is_ancestor_of(hud._walk_advance_check),
			"walk_advance checkbox is inside the settings panel")
	assert_true(hud._settings_panel.is_ancestor_of(hud._reform_before_move_check),
			"reform_before_move checkbox is inside the settings panel")
	assert_true(hud._settings_panel.is_ancestor_of(hud._file_major_reform_btn),
			"file_major_reform_mode button is inside the settings panel")
	assert_false(hud._info_panel.is_ancestor_of(hud._walk_advance_check),
			"...and NOT inside the (now center-left) info panel")


func test_info_panel_available_height_is_no_longer_shrunk_by_the_control_bar() -> void:
	# The info panel used to share the bottom-left corner with the control bar's raise
	# clearance; now it's centered on the left margin, well clear of the control bar,
	# so showing a unit (and its control bar) must not shrink its height budget.
	var hud := _hud()
	var viewport_h: float = hud._info_panel.get_viewport_rect().size.y
	var edge_gap: float = maxf(hud.PANEL_TOP_GAP, hud.PANEL_BOTTOM_GAP)
	var expected: float = viewport_h - 2.0 * edge_gap
	assert_almost_eq(hud._info_panel_available_height(), expected, 0.01,
			"the budget spans the viewport minus the larger edge gap, doubled")
	hud.show_unit(_unit(), 1)
	assert_almost_eq(hud._info_panel_available_height(), expected, 0.01,
			"showing a unit (and its control bar) leaves the budget unchanged")


func test_info_panel_recenter_keeps_the_panel_centered_as_it_grows() -> void:
	# offset_top/offset_bottom are set via set_deferred; flush it before reading each time.
	var hud := _hud()
	hud._info_panel_recenter(200.0)
	await get_tree().process_frame
	assert_almost_eq(hud._info_panel.offset_top, -100.0, 0.01,
			"offset_top is half the height above the center anchor line")
	assert_almost_eq(hud._info_panel.offset_bottom, 100.0, 0.01,
			"offset_bottom is half the height below the center anchor line")
	hud._info_panel_recenter(60.0)
	await get_tree().process_frame
	assert_almost_eq(hud._info_panel.offset_top, -hud.PANEL_MIN.y * 0.5, 0.01,
			"a height below PANEL_MIN floors to PANEL_MIN, still centered")
	assert_almost_eq(hud._info_panel.offset_bottom, hud.PANEL_MIN.y * 0.5, 0.01,
			"...symmetrically on both edges")


func test_settings_panel_raises_above_the_control_bar_while_a_unit_is_shown() -> void:
	var hud := _hud()
	hud.show_unit(_unit(), 1)
	# offset_top/offset_bottom are set via set_deferred; flush it before reading.
	await get_tree().process_frame
	var raise_amount: float = hud._ctrl_bar.get_combined_minimum_size().y + 8.0
	assert_almost_eq(hud._settings_panel.offset_top,
			-(hud.PANEL_MIN.y + hud.PANEL_BOTTOM_GAP + raise_amount), 0.01,
			"the panel's top offset raises by the control bar's height + gap")
	assert_almost_eq(hud._settings_panel.offset_bottom,
			-(hud.PANEL_BOTTOM_GAP + raise_amount), 0.01,
			"...and its bottom offset raises by the same amount, translating as a rigid rect")

	hud.clear_unit()
	await get_tree().process_frame
	assert_almost_eq(hud._settings_panel.offset_top,
			-(hud.PANEL_MIN.y + hud.PANEL_BOTTOM_GAP), 0.01,
			"clearing the unit lowers the panel back to its at-rest offset")
	assert_almost_eq(hud._settings_panel.offset_bottom, -hud.PANEL_BOTTOM_GAP, 0.01,
			"...on both edges")
