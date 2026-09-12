extends GutTest
## Tests for ReplayFogTrack: dedup on record, playback cursor stepping,
## cursor rewind, and reset.

const HelperScript = preload("res://scripts/ReplayFogTrack.gd")


func _fresh() -> HelperScript:
	var h := HelperScript.new()
	return h


func test_record_fog_change_dedups_against_default_initial_state() -> void:
	var track_inst := _fresh()
	track_inst.record_fog_change(0, false)
	assert_eq(track_inst.track.size(), 0, "default false value without prior entry is dropped")
	track_inst.record_fog_change(10, true)
	assert_eq(track_inst.track.size(), 1, "first transition to true is recorded")
	track_inst.record_fog_change(20, true)
	assert_eq(track_inst.track.size(), 1, "repeated true value is deduped and dropped")
	track_inst.record_fog_change(30, false)
	assert_eq(track_inst.track.size(), 2, "transition back to false is recorded")


func test_record_fog_change_with_true_initial_state() -> void:
	var track_inst := _fresh()
	track_inst.init_state(true)
	track_inst.record_fog_change(5, true)
	assert_eq(track_inst.track.size(), 0, "initial true state drops redundant true transition")
	track_inst.record_fog_change(10, false)
	assert_eq(track_inst.track.size(), 1, "transition to false from initial true is recorded")
	track_inst.record_fog_change(20, false)
	assert_eq(track_inst.track.size(), 1, "duplicate false transition is dropped")


func test_for_tick_stepping_and_rewind() -> void:
	var track_inst := _fresh()
	track_inst.record_fog_change(10, true)
	track_inst.record_fog_change(20, false)
	track_inst.record_fog_change(30, true)
	assert_eq(track_inst.for_tick(5), -1, "tick before first transition returns sentinel -1")
	assert_eq(track_inst.for_tick(10), 1, "tick matching first transition returns 1")
	assert_eq(track_inst.for_tick(10), -1, "cursor advanced so same tick returns -1")
	assert_eq(track_inst.for_tick(20), 0, "tick matching second transition returns 0")
	assert_eq(track_inst.for_tick(30), 1, "third transition returns 1")
	track_inst.rewind_cursor_to_tick(15)
	assert_eq(track_inst.for_tick(15), -1, "rewind to tick 15 has nothing at 15")
	assert_eq(track_inst.for_tick(20), 0, "resuming forward returns transition at 20")
	track_inst.rewind_cursor_to_tick(0)
	assert_eq(track_inst.for_tick(10), 1, "rewind to 0 repositions to first transition")


func test_reset_clears_track_and_index() -> void:
	var track_inst := _fresh()
	track_inst.init_state(true)
	track_inst.record_fog_change(10, false)
	assert_false(track_inst.track.is_empty(), "track has entries")
	track_inst.reset()
	assert_true(track_inst.track.is_empty(), "track is empty after reset")
	assert_eq(track_inst.index, 0, "index is reset to 0")
	assert_false(track_inst.initial_value, "initial_value is reset to false")
