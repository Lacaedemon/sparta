extends GutTest
## MeleeRunStore (tools/demo/MeleeRunStore.gd): a run's metrics.json is reused only when it
## matches the travel offsets, step and end asked for, and a re-extraction keeps the run's
## own end, so a cut-off run never reads as complete.

var _dir: String = ""


func before_each() -> void:
	_dir = OS.get_user_data_dir().path_join("test_melee_run_store")
	_clear()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	_clear()


func _clear() -> void:
	if not DirAccess.dir_exists_absolute(_dir):
		return
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _write(fname: String, data: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(_dir.path_join(fname), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## Snapshots every 10 ticks to tick 100: uid 0 holds, never routing.
func _snapshots() -> void:
	for t in range(0, 101, 10):
		_write("state_%05d.json" % t, {"tick": t, "units": [{"uid": 0, "team": 0,
				"state": "FIGHTING", "soldiers": 10, "in_enemy_contact": true,
				"soldier_summary_m": {"centroid_m": [0.0, 0.0]}}]})


func test_reextraction_keeps_the_runs_own_end() -> void:
	_snapshots()
	_write("run.json", {"end": 400, "step": 10})
	_write("metrics.json", {"travel": [999], "end": 400, "step": 10, "metrics": {}})
	var got: Dictionary = MeleeRunStore.run_metrics(_dir, [60], 10)
	assert_eq(got["metrics"]["uid0_break"], null,
			"cut off at tick 100 of 400: whether uid 0 breaks is unobserved, not never")
	_write("run.json", {"end": 100, "step": 10})
	got = MeleeRunStore.run_metrics(_dir, [60], 10)
	assert_eq(got["metrics"]["uid0_break"], MeleeOutcomes.NEVER, "reaching its end, the run is complete")


func test_a_metrics_file_for_another_end_is_not_reused() -> void:
	_snapshots()
	_write("run.json", {"end": 400, "step": 10})
	_write("metrics.json", {"travel": [60], "end": 100, "step": 10,
			"metrics": {"uid0_break": "never"}})
	var got: Dictionary = MeleeRunStore.run_metrics(_dir, [60], 10)
	assert_eq(got["metrics"]["uid0_break"], null, "re-extracted at the run's own end")


func test_a_matching_metrics_file_is_reused() -> void:
	_write("run.json", {"end": 400, "step": 10})
	_write("metrics.json", {"travel": [60], "end": 400, "step": 10, "metrics": {"x": 1}})
	assert_eq(MeleeRunStore.run_metrics(_dir, [60], 10)["metrics"], {"x": 1.0})


func test_another_step_is_refused() -> void:
	_write("run.json", {"end": 400, "step": 5})
	_write("metrics.json", {"travel": [60], "end": 400, "step": 5, "metrics": {}})
	assert_true(MeleeRunStore.run_metrics(_dir, [60], 10).has("error"))


func test_snapshots_without_an_end_are_refused() -> void:
	_snapshots()
	assert_true(MeleeRunStore.run_metrics(_dir, [60], 10).has("error"),
			"without run.json the run's completeness is unknown")


func test_extract_records_travel_end_and_step() -> void:
	_snapshots()
	assert_eq(MeleeRunStore.extract(_dir, [60], 100, 10), "")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join("metrics.json")))
	assert_eq([saved["travel"], int(saved["end"]), int(saved["step"])], [[60.0], 100, 10])
	assert_eq(MeleeRunStore.extract(_dir.path_join("missing"), [60], 100, 10).is_empty(), false)


func test_reextraction_refuses_a_run_dumped_at_another_step() -> void:
	_snapshots()
	_write("run.json", {"end": 100, "step": 5})
	assert_true(MeleeRunStore.run_metrics(_dir, [60], 10).has("error"),
			"no metrics.json, and the snapshots were taken at step 5, not 10")
	assert_false(MeleeRunStore.run_metrics(_dir, [60], 5).has("error"))
