extends GutTest
## Replay.save()/start_playback() round-trip the spawn-layout fingerprint (SpawnFingerprint):
## a recording stamps the layout it ran on, and a load reads it back so Battle._ready can flag a
## drift. Like commit_sha (test_replay_build_stamp), it's an additive, opt-in field -- a replay
## that never carried one loads with an empty stamp and is not gated. Battle publishes the value
## after spawning; here it's set directly so save/load are exercised without a full battle.

const ReplayScript = preload("res://scripts/Replay.gd")


func _recording_replay() -> Node:
	var r = ReplayScript.new()
	autofree(r)
	r.start_recording()
	return r


func _cleanup(path: String) -> void:
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_start_recording_clears_a_stale_stamp() -> void:
	var r := _recording_replay()
	r.spawn_fingerprint = "left-over-from-a-previous-battle"
	r.start_recording()   # a fresh battle re-publishes it; the old value must not leak through
	assert_eq(r.spawn_fingerprint, "", "start_recording clears the spawn fingerprint")


func test_save_records_the_spawn_fingerprint_when_set() -> void:
	var r := _recording_replay()
	r.spawn_fingerprint = "abc123def456"
	var path: String = r.save("Test", 10)
	assert_ne(path, "", "a live recording saves successfully")
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	assert_eq(data.get("spawn_fingerprint", ""), "abc123def456",
			"the saved file records the layout's fingerprint")
	_cleanup(path)


func test_save_omits_the_spawn_fingerprint_when_unset() -> void:
	var r := _recording_replay()   # start_recording left spawn_fingerprint == ""
	var path: String = r.save("Test", 10)
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	assert_false(data.has("spawn_fingerprint"),
			"an unstamped recording writes no spawn_fingerprint key, staying byte-simple")
	_cleanup(path)


func test_playback_loads_the_stamp() -> void:
	var writer := _recording_replay()
	writer.spawn_fingerprint = "abc123def456"
	var path: String = writer.save("Test", 10)

	var reader = ReplayScript.new()
	autofree(reader)
	assert_true(reader.start_playback(path), "the stamped replay loads")
	assert_eq(reader.loaded_spawn_fingerprint, "abc123def456",
			"start_playback reads the stamp back for Battle._ready to check")
	assert_eq(reader.last_load_spawn_mismatch, "",
			"the mismatch flag starts clear -- Battle sets it later, after re-spawning")
	_cleanup(path)


func test_playback_of_a_replay_without_the_field_loads_an_empty_stamp() -> void:
	var writer := _recording_replay()   # unstamped
	var path: String = writer.save("Test", 10)

	var reader = ReplayScript.new()
	autofree(reader)
	assert_true(reader.start_playback(path), "an unstamped replay still loads")
	assert_eq(reader.loaded_spawn_fingerprint, "",
			"a missing stamp loads as empty, so Battle skips the check (back-compat)")
	_cleanup(path)
