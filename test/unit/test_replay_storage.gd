extends GutTest
## Tests for ReplayStorage: directory ensuring, timestamped filename formatting,
## and round-trip file read and write.

const ReplayStorageScript = preload("res://scripts/ReplayStorage.gd")
const TEST_FILE := "user://replays/test_1512b_storage.json"


func after_each() -> void:
	if FileAccess.file_exists(TEST_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))


func test_replays_dir() -> void:
	var d := ReplayStorageScript.replays_dir()
	assert_eq(d, "user://replays", "replays directory matches DIR constant")


func test_timestamped_path_shape() -> void:
	var path := ReplayStorageScript.timestamped_path(7)
	assert_true(path.begins_with("user://replays/battle_"), "path starts with replays directory and prefix")
	assert_true(path.ends_with("_07.json"), "path ends with zero-padded counter and json extension")


func test_read_file_missing_path_returns_empty_dict() -> void:
	var missing_data := ReplayStorageScript.read_file("user://replays/nonexistent_file_xyz.json")
	assert_true(missing_data.is_empty(), "missing path yields empty dictionary")


func test_storage_round_trip() -> void:
	assert_true(ReplayStorageScript.ensure_dir(), "directory is ensured")
	var written := ReplayStorageScript.write_text(TEST_FILE, "{\"score\": 42, \"tag\": \"alpha\"}")
	assert_true(written, "write succeeds")
	var loaded_data := ReplayStorageScript.read_file(TEST_FILE)
	assert_eq(int(loaded_data.get("score", 0)), 42, "numeric payload round-trips")
	assert_eq(str(loaded_data.get("tag", "")), "alpha", "string payload round-trips")


func test_write_text_fails_on_invalid_path() -> void:
	var invalid_path := "user://nonexistent_nested_dir_xyz/sub/bad.json"
	var failed := ReplayStorageScript.write_text(invalid_path, "test")
	assert_false(failed, "writing to unwritable directory returns false")
