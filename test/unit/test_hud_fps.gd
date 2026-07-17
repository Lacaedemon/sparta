extends GutTest
## The ☰-menu frame-rate counter toggle and its four-corner radio picker.
## Instantiating the HUD also smoke-tests that its menu builds (the new check item /
## labelled separator / radio items) without a runtime error.

const HUDScript = preload("res://scripts/HUD.gd")
const SettingsScript = preload("res://scripts/Settings.gd")

var _orig_show_fps: bool
var _orig_corner: int


func before_each() -> void:
	_orig_show_fps = Settings.show_fps
	_orig_corner = Settings.fps_corner


func after_each() -> void:
	Settings.show_fps = _orig_show_fps
	Settings.fps_corner = _orig_corner


func _hud() -> CanvasLayer:
	var hud = HUDScript.new()
	add_child_autofree(hud)   # runs _ready(): builds the menu, info panel, overlay, fps label
	return hud


func _popup(hud) -> PopupMenu:
	return hud._menu_button.get_popup()


func test_menu_builds_with_the_fps_toggle_and_corner_radios() -> void:
	var hud := _hud()
	var popup := _popup(hud)
	assert_gte(popup.get_item_index(HUDScript.MENU_SHOW_FPS), 0,
			"the show-frame-rate check item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FPS_CORNER_TOP_LEFT), 0,
			"the top-left corner radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FPS_CORNER_TOP_RIGHT), 0,
			"the top-right corner radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FPS_CORNER_BOTTOM_LEFT), 0,
			"the bottom-left corner radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FPS_CORNER_BOTTOM_RIGHT), 0,
			"the bottom-right corner radio item is present")


func test_toggle_menu_check_reflects_setting() -> void:
	Settings.show_fps = false
	var hud := _hud()
	var popup := _popup(hud)
	assert_false(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_SHOW_FPS)),
			"item is unchecked when the setting is off")
	assert_false(hud._fps_label.visible, "the label starts hidden")


func test_toggling_via_menu_dispatch_flips_setting_and_label_visibility() -> void:
	Settings.show_fps = false
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_SHOW_FPS)
	assert_true(Settings.show_fps, "toggling the menu item turns the counter on")
	assert_true(hud._fps_label.visible, "...and shows the label")
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_SHOW_FPS)),
			"the checkbox re-syncs to checked")
	hud._on_menu_id(HUDScript.MENU_SHOW_FPS)
	assert_false(Settings.show_fps, "toggling again turns it back off")
	assert_false(hud._fps_label.visible, "...and hides the label")


func test_radios_reflect_the_persisted_corner() -> void:
	Settings.fps_corner = SettingsScript.FPS_CORNER_BOTTOM_LEFT
	var hud := _hud()   # _ready -> _sync_setting_toggles reads the corner
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FPS_CORNER_BOTTOM_LEFT)),
			"bottom-left is checked as the current corner")
	assert_false(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FPS_CORNER_TOP_RIGHT)),
			"a different corner's radio is unchecked")


func test_picking_a_corner_radio_sets_and_persists_it() -> void:
	Settings.fps_corner = SettingsScript.FPS_CORNER_TOP_LEFT
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_FPS_CORNER_BOTTOM_RIGHT)
	assert_eq(Settings.fps_corner, SettingsScript.FPS_CORNER_BOTTOM_RIGHT,
			"choosing the bottom-right item sets the persisted corner")
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FPS_CORNER_BOTTOM_RIGHT)),
			"and the radio re-syncs to the new corner")


func test_label_anchors_to_the_chosen_corner() -> void:
	Settings.show_fps = true
	Settings.fps_corner = SettingsScript.FPS_CORNER_BOTTOM_RIGHT
	var hud := _hud()
	assert_eq(hud._fps_label.anchor_left, 1.0, "bottom-right anchors its left edge to the far side")
	assert_eq(hud._fps_label.anchor_top, 1.0, "bottom-right anchors its top edge to the bottom")


func test_update_writes_the_live_frame_rate_only_while_visible() -> void:
	Settings.show_fps = false
	var hud := _hud()
	hud._fps_label.text = "stale"
	hud._update_fps_label()
	assert_eq(hud._fps_label.text, "stale", "hidden label text is left untouched")

	Settings.show_fps = true
	hud._sync_fps_label()
	hud._update_fps_label()
	assert_true(hud._fps_label.text.contains("FPS"), "visible label shows the live frame rate")
	assert_true(hud._fps_label.text.contains("ticks/s"), "...and the live physics tick rate")


# --- live tick-rate sampling -------------------------------------------------
# _on_physics_tick counts physics_frame emissions; _process closes a 1s window and turns
# the count into a rate, the same shape Engine.get_frames_per_second() gives for render FPS
# but computed by hand since Godot has no built-in equivalent for physics ticks.

func test_tick_rate_holds_its_prior_value_mid_window() -> void:
	var hud := _hud()
	var initial: float = hud._live_tick_rate
	for i in range(30):
		hud._on_physics_tick()
	hud._process(0.5)   # half a second: window not yet closed
	assert_eq(hud._live_tick_rate, initial,
			"the rate doesn't update until a full sample window elapses")


func test_tick_rate_reflects_ticks_counted_over_a_full_window() -> void:
	var hud := _hud()
	for i in range(42):
		hud._on_physics_tick()
	hud._process(1.0)   # closes the window
	assert_almost_eq(hud._live_tick_rate, 42.0, 0.01,
			"42 ticks over a 1s window measures as ~42 ticks/s")
	assert_eq(hud._tick_count, 0, "the counter resets for the next window")


func test_tick_rate_below_target_shows_the_sim_falling_behind() -> void:
	# The scenario the readout exists for: a large battle can't keep up with the configured
	# 60 Hz physics target, so the live rate should read visibly below it.
	var hud := _hud()
	for i in range(20):
		hud._on_physics_tick()
	hud._process(1.0)
	assert_almost_eq(hud._live_tick_rate, 20.0, 0.01,
			"a sim that only completes 20 ticks in a real second measures ~20 ticks/s")
	assert_lt(hud._live_tick_rate, Engine.physics_ticks_per_second,
			"...visibly below the configured target")


func test_top_right_fps_label_sits_below_the_menu_button() -> void:
	# The top-right corner is shared with the always-on Menu button: the label
	# must clear the button's whole rect, not sit inside it. (The removed hint
	# bar's fixed top clearance covered this incidentally; the clearance is now
	# derived from the button's own rect.)
	Settings.show_fps = true
	Settings.fps_corner = Settings.FPS_CORNER_TOP_RIGHT
	var hud := _hud()
	var menu_bottom: float = hud._menu_button.position.y \
			+ hud._menu_button.get_combined_minimum_size().y
	assert_gte(hud._fps_label.position.y, menu_bottom,
			"the top-right label starts below the menu button's bottom edge")


func test_top_left_fps_label_uses_the_standard_margin() -> void:
	# With the hint bar gone, nothing occupies the top-left corner, so the label
	# uses the same margin as the bottom corners.
	Settings.show_fps = true
	Settings.fps_corner = Settings.FPS_CORNER_TOP_LEFT
	var hud := _hud()
	assert_eq(hud._fps_label.position.y, HUDScript._FPS_MARGIN.y,
			"the top-left corner needs no extra clearance")
