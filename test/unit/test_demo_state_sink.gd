extends GutTest
## DemoStateSink: the replay path's env-gated state dumping (DemoRunner is freed when the
## battle scene replaces it, so a root-surviving sink carries the dump instead). Covers the
## env arming contract and a real dump against a live Battle, through the same shared
## DemoState.build_snapshot the scripted-input recorder uses.

const SinkScript = preload("res://tools/demo/DemoStateSink.gd")

var _battle: Node = null
var _saved_env: Dictionary = {}


func before_each() -> void:
	# Snapshot/restore the env vars the sink reads, so a developer's shell (or another
	# test) can't leak arming state in either direction.
	_saved_env = {}
	for key in ["SPARTA_DEMO_STATE", "SPARTA_DEMO_STATE_DIR", "SPARTA_DEMO_STATE_FULL"]:
		_saved_env[key] = OS.get_environment(key) if OS.has_environment(key) else null
		OS.unset_environment(key)


func after_each() -> void:
	for key in _saved_env:
		if _saved_env[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, _saved_env[key])
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func test_arm_from_env_is_null_when_unarmed() -> void:
	assert_null(SinkScript.arm_from_env("test"),
			"no SPARTA_DEMO_STATE -> no sink at all (a movie recording never creates one)")
	OS.set_environment("SPARTA_DEMO_STATE", "")
	assert_null(SinkScript.arm_from_env("test"), "an empty tick list arms nothing either")


func test_arm_from_env_reads_ticks_dir_and_full() -> void:
	OS.set_environment("SPARTA_DEMO_STATE", "8,60,120")
	OS.set_environment("SPARTA_DEMO_STATE_DIR", "user://sink_test_out")
	OS.set_environment("SPARTA_DEMO_STATE_FULL", "1")
	var sink = SinkScript.arm_from_env("test")
	assert_not_null(sink, "a tick list arms the sink")
	autofree(sink)
	assert_eq(sink._ticks, [8, 60, 120], "the env tick list parses in order")
	assert_eq(sink._dir, "user://sink_test_out", "the output dir reads through")
	assert_true(sink._full, "FULL=1 requests the raw per-soldier arrays")


func test_dump_writes_a_parseable_snapshot_of_a_live_battle() -> void:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.scenario = [{"team": 0, "type": "Infantry", "x": 400.0, "y": 300.0}]
	add_child(_battle)

	OS.set_environment("SPARTA_DEMO_STATE", "0")
	OS.set_environment("SPARTA_DEMO_STATE_DIR", "user://sink_test_dump")
	var sink = SinkScript.arm_from_env("test")
	assert_not_null(sink, "sanity: armed")
	autofree(sink)
	# Drive _dump directly rather than adding the sink to the tree: in the tree it would
	# quit the whole test run once its ticks were satisfied (that behavior is the tool
	# contract, deliberately not exercised inside a GUT run).
	DirAccess.make_dir_recursive_absolute(sink._dir)
	sink._dump(_battle, _battle.current_tick())

	var path: String = "user://sink_test_dump/state_%05d.json" % _battle.current_tick()
	assert_true(FileAccess.file_exists(path), "the snapshot file lands at the armed dir")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_not_null(parsed, "the snapshot is valid JSON")
	assert_eq(int(parsed["tick"]), _battle.current_tick(), "the tick field matches")
	assert_eq(parsed["units"].size(), 1, "the staged unit is in the snapshot")
	assert_eq(parsed["units"][0]["name"], "Infantry 1",
			"the record carries the shared unit_record fields")
	# remove_absolute needs a real OS path -- a raw user:// silently fails to delete,
	# leaving a stray file in the app-data dir after every run.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
