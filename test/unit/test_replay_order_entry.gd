extends GutTest
## Tests for ReplayOrderEntry: build() emits base fields and precisely
## the optional keys implied by arguments, omitting default sentinels.

const HelperScript = preload("res://scripts/ReplayOrderEntry.gd")


func test_build_defaults_omit_optional_keys() -> void:
	var uids: Array = [42]
	var pos := Vector2(100.0, 200.0)
	var entry: Dictionary = HelperScript.build(10, uids, pos, -1)
	assert_eq(entry["tick"], 10, "tick recorded")
	assert_eq(entry["units"], [42], "units recorded")
	assert_eq(entry["x"], 100.0, "x pos recorded")
	assert_eq(entry["y"], 200.0, "y pos recorded")
	assert_eq(entry["target"], -1, "target recorded")
	assert_eq(entry["mode"], 0, "order_mode defaults to 0")
	# Verify optional keys are absent when at default sentinels
	assert_false(entry.has("formation"), "formation omitted when 0")
	assert_false(entry.has("frontage"), "frontage omitted when 0")
	assert_false(entry.has("anchor_offset"), "anchor_offset omitted when 0.0")
	assert_false(entry.has("face"), "face omitted when INF")
	assert_false(entry.has("group_attack"), "group_attack omitted when 0")
	assert_false(entry.has("form_up_group"), "form_up_group omitted when -1")
	assert_false(entry.has("walk_advance_toggle"), "walk_advance_toggle omitted when 0")
	assert_false(entry.has("reform_toggle"), "reform_toggle omitted when 0")
	assert_false(entry.has("file_major_reform_mode_toggle"), "file_major_reform_mode_toggle omitted when -1")
	assert_false(entry.has("line"), "line omitted when -1")
	# Verify uids array was duplicated, not referenced
	uids.append(99)
	assert_eq(entry["units"].size(), 1, "units array duplicated on build")


func test_build_includes_optional_keys_when_set() -> void:
	var pos := Vector2(150.0, 250.0)
	var entry: Dictionary = HelperScript.build(
			12, [42], pos, 99,
			1, 2, 16, 0.75,
			2, -32.5,
			3, 1, 2,
			0,
			4
	)
	assert_eq(entry["tick"], 12, "tick")
	assert_eq(entry["mode"], 1, "order_mode")
	assert_eq(entry["target"], 99, "target_uid")
	assert_eq(entry["formation"], 2, "formation included when non-zero")
	assert_eq(entry["frontage"], 16, "frontage included when non-zero")
	assert_eq(entry["face"], 0.75, "face included when non-INF")
	assert_eq(entry["group_attack"], 2, "group_attack included when non-zero")
	assert_eq(entry["anchor_offset"], -32.5, "anchor_offset included when non-zero")
	assert_eq(entry["form_up_group"], 3, "form_up_group included when non-negative")
	assert_eq(entry["walk_advance_toggle"], 1, "walk_advance_toggle included when non-zero")
	assert_eq(entry["reform_toggle"], 2, "reform_toggle included when non-zero")
	assert_eq(entry["file_major_reform_mode_toggle"], 0, "file_major_reform_mode_toggle 0 included since sentinel is -1")
	assert_eq(entry["line"], 4, "line included under 'line' key when sentinel is -1")


func test_build_zero_sentinels_for_reform_and_line_and_face() -> void:
	# 0.0 is a valid facing (not INF); 0 is a valid ReformMode (not -1); 0 is a valid line index (not -1)
	var entry: Dictionary = HelperScript.build(
			5, [42], Vector2.ZERO, -1,
			0, 0, 0, 0.0,
			0, 0.0,
			-1, 0, 0,
			0,
			0
	)
	assert_true(entry.has("face"), "face 0.0 is recorded because INF is the sentinel")
	assert_eq(entry["face"], 0.0, "face value is 0.0")
	assert_true(entry.has("file_major_reform_mode_toggle"), "reform mode 0 is recorded because -1 is the sentinel")
	assert_eq(entry["file_major_reform_mode_toggle"], 0, "reform mode value is 0")
	assert_true(entry.has("line"), "line 0 is recorded because -1 is the sentinel")
	assert_eq(entry["line"], 0, "line value is 0")
