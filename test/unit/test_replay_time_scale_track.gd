extends GutTest
## Tests for ReplayTimeScaleTrack: dedup on record, playback cursor stepping,
## cursor rewind, and reset.

const HelperScript = preload("res://scripts/ReplayTimeScaleTrack.gd")


func _fresh() -> HelperScript:
	var h := HelperScript.new()
	return h


func test_record_time_scale_change_dedups_repeated_and_default() -> void:
	var track_inst := _fresh()
	track_inst.record_time_scale_change(0, 1.0)
	assert_eq(track_inst.track.size(), 0, "default 1.0 value without prior entry is dropped")
	track_inst.record_time_scale_change(10, 0.5)
	assert_eq(track_inst.track.size(), 1, "first non-default value is recorded")
	track_inst.record_time_scale_change(20, 0.5)
	assert_eq(track_inst.track.size(), 1, "repeated value is deduped and dropped")
	track_inst.record_time_scale_change(30, 0.25)
	assert_eq(track_inst.track.size(), 2, "new scale value is recorded")


func test_for_tick_stepping_and_rewind() -> void:
	var track_inst := _fresh()
	track_inst.record_time_scale_change(10, 0.5)
	track_inst.record_time_scale_change(20, 0.25)
	track_inst.record_time_scale_change(30, 1.0)
	assert_eq(track_inst.for_tick(5), -1.0, "tick before first keyframe returns sentinel")
	assert_eq(track_inst.for_tick(10), 0.5, "tick matching keyframe returns value")
	assert_eq(track_inst.for_tick(10), -1.0, "cursor advanced so same tick returns sentinel")
	assert_eq(track_inst.for_tick(20), 0.25, "for_tick returns value")
	assert_eq(track_inst.for_tick(30), 1.0, "third keyframe returns value")
	track_inst.rewind_cursor_to_tick(15)
	assert_eq(track_inst.for_tick(15), -1.0, "rewind to tick 15 has nothing at 15")
	assert_eq(track_inst.for_tick(20), 0.25, "resuming forward returns keyframe at 20")
	track_inst.rewind_cursor_to_tick(0)
	assert_eq(track_inst.for_tick(10), 0.5, "rewind_cursor_to_tick 0 repositions to first keyframe")


func test_reset_clears_track_and_index() -> void:
	var track_inst := _fresh()
	track_inst.record_time_scale_change(10, 0.5)
	assert_false(track_inst.track.is_empty(), "track is not empty when entries exist")
	var out_val := track_inst.for_tick(10)
	assert_eq(out_val, 0.5, "value was dispatched")
	assert_eq(track_inst.index, 1, "index advanced")
	track_inst.reset()
	assert_true(track_inst.track.is_empty(), "track is empty after reset")
	assert_eq(track_inst.track.size(), 0, "track array is cleared")
	assert_eq(track_inst.index, 0, "index is reset to 0")
