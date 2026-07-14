extends GutTest
## Replay.save() records which commit produced a replay (BuildInfo.COMMIT_SHA) so a mismatch
## can be surfaced as a warning on load, rather than the player just guessing why an old
## replay desynced. Unlike FORMAT_VERSION/PHYSICS_TPS, a commit mismatch doesn't block
## playback -- most commits touch nothing replay-affecting.

const ReplayScript = preload("res://scripts/Replay.gd")
const BuildInfoScript = preload("res://scripts/BuildInfo.gd")
const TEST_DIR := "user://replays"


func _recording_replay() -> Node:
	var r = ReplayScript.new()
	autofree(r)
	r.start_recording()
	return r


func _cleanup(path: String) -> void:
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_save_records_this_builds_commit_sha() -> void:
	var r := _recording_replay()
	var path: String = r.save("Test", 10)
	assert_ne(path, "", "a live recording saves successfully")

	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	assert_eq(data.get("commit_sha", ""), BuildInfoScript.COMMIT_SHA,
			"the saved file records this build's commit SHA")
	_cleanup(path)


func test_playback_reports_no_mismatch_for_a_replay_from_this_build() -> void:
	var writer := _recording_replay()
	var path: String = writer.save("Test", 10)

	var reader = ReplayScript.new()
	autofree(reader)
	var ok: bool = reader.start_playback(path)

	assert_true(ok, "a same-build replay loads fine")
	assert_eq(reader.last_load_sha_mismatch, "",
			"no mismatch is reported when the recorded SHA matches this build's")
	_cleanup(path)


func test_playback_reports_a_mismatch_without_rejecting_the_replay() -> void:
	var writer := _recording_replay()
	var path: String = writer.save("Test", 10)
	# Simulate a replay saved by a different build: rewrite the just-saved file's
	# commit_sha to something this build's COMMIT_SHA can't equal.
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	data["commit_sha"] = "deadbeef0000000000000000000000000000000"
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

	var reader = ReplayScript.new()
	autofree(reader)
	var ok: bool = reader.start_playback(path)

	assert_true(ok, "a commit mismatch is a warning, not a hard reject -- playback proceeds")
	assert_eq(reader.last_load_sha_mismatch, "deadbeef0000000000000000000000000000000",
			"the mismatched SHA is recorded for the caller to surface")
	_cleanup(path)


func test_playback_reports_no_mismatch_for_a_replay_that_predates_this_field() -> void:
	var writer := _recording_replay()
	var path: String = writer.save("Test", 10)
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	data.erase("commit_sha")   # simulate an older replay file saved before this field existed
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

	var reader = ReplayScript.new()
	autofree(reader)
	var ok: bool = reader.start_playback(path)

	assert_true(ok, "a replay missing commit_sha entirely still loads")
	assert_eq(reader.last_load_sha_mismatch, "",
			"a missing field isn't treated as a mismatch -- nothing to compare")
	_cleanup(path)


func test_git_dirty_status_returns_a_string_without_erroring() -> void:
	# Best-effort: whatever the live checkout's git state actually is, this must return a
	# String (possibly empty) rather than crash, since Replay.save() calls it unconditionally
	# on every save -- including from an exported build with no git binary at all.
	var status := BuildInfoScript.git_dirty_status()
	assert_true(status is String, "always returns a String, clean tree or dirty")
