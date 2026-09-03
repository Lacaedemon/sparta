extends GutTest
## Unit tests for SettingsStorage helper: ConfigFile round trip, missing path fallback, and sanitisation.

const SettingsScript = preload("res://scripts/Settings.gd")
const SettingsStorage = preload("res://scripts/SettingsStorage.gd")
const SettingsKeybindings = preload("res://scripts/SettingsKeybindings.gd")
const TEST_PATH := "user://test_settings_1511.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _sample_defaults() -> Dictionary:
	return {
		"edge_scroll": false,
		"sfx_enabled": false,
		"form_up_dist_default": 2,
		"form_up_dist_cycle": [2, 0, 1, 3],
		"show_distance_legend": true,
		"show_order_distance": true,
		"show_unit_speed": false,
		"show_soldier_ids": false,
		"show_engaged_highlight": false,
		"show_position_anchor": false,
		"show_fps": false,
		"show_performance_graph": false,
		"show_unit_card_tray": false,
		"tray_row_order_placement": false,
		"fps_corner": 0,
		"order_bindings": SettingsKeybindings.DEFAULT_ORDER_BINDINGS.duplicate(),
	}


func test_load_from_missing_path_returns_empty() -> void:
	var defaults: Dictionary = _sample_defaults()
	var loaded: Dictionary = SettingsStorage.load_from_path(TEST_PATH, defaults, SettingsScript.FORM_UP_DIST_MAX)
	assert_true(loaded.is_empty(), "missing path returns an empty dictionary")


func test_save_and_load_round_trip() -> void:
	var values: Dictionary = _sample_defaults()
	values["edge_scroll"] = true
	values["sfx_enabled"] = true
	values["form_up_dist_default"] = 1
	values["form_up_dist_cycle"] = [1, 2]
	values["show_distance_legend"] = false
	values["show_order_distance"] = false
	values["show_unit_speed"] = true
	values["show_soldier_ids"] = true
	values["show_engaged_highlight"] = true
	values["show_position_anchor"] = true
	values["show_fps"] = true
	values["show_performance_graph"] = true
	values["show_unit_card_tray"] = true
	values["tray_row_order_placement"] = true
	values["fps_corner"] = 3
	values["order_bindings"]["hold"] = KEY_Z

	var err: Error = SettingsStorage.save_to_path(TEST_PATH, values)
	assert_eq(err, OK, "saving configuration returns OK")

	var loaded: Dictionary = SettingsStorage.load_from_path(TEST_PATH, _sample_defaults(), SettingsScript.FORM_UP_DIST_MAX)
	assert_eq(loaded, values, "all saved settings match after reload")


func test_push_key_migrates_from_key_p_to_slash() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("keybindings", "push", KEY_P)
	cfg.save(TEST_PATH)

	var loaded: Dictionary = SettingsStorage.load_from_path(TEST_PATH, _sample_defaults(), SettingsScript.FORM_UP_DIST_MAX)
	assert_eq(loaded["order_bindings"]["push"], KEY_SLASH, "legacy KEY_P binding on push migrates to KEY_SLASH")


func test_form_up_dist_cycle_sanitises_invalid_entries() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("gameplay", "form_up_dist_cycle", [0, 99, -1, 1, "corrupt"])
	cfg.save(TEST_PATH)

	var loaded: Dictionary = SettingsStorage.load_from_path(TEST_PATH, _sample_defaults(), SettingsScript.FORM_UP_DIST_MAX)
	assert_eq(loaded["form_up_dist_cycle"], [0, 1], "invalid distribution modes are filtered on load")


func test_out_of_range_form_up_dist_default_returned_unclamped() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("gameplay", "form_up_dist_default", 99)
	cfg.save(TEST_PATH)

	var loaded: Dictionary = SettingsStorage.load_from_path(TEST_PATH, _sample_defaults(), SettingsScript.FORM_UP_DIST_MAX)
	assert_eq(loaded["form_up_dist_default"], 99, "out-of-range form_up_dist_default is returned unclamped; setter clamps")
