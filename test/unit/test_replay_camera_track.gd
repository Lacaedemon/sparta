extends GutTest
## Unit tests for ReplayCameraTrack: recording with dedup, keyframe stepping,
## for_tick lookup before/between/past keyframes, rewind on step back, and reset.

const ReplayCameraTrackScript = preload("res://scripts/ReplayCameraTrack.gd")


func _fresh() -> ReplayCameraTrackScript:
	return ReplayCameraTrackScript.new()


func test_has_track_false_when_empty() -> void:
	var cam := _fresh()
	assert_false(cam.has_track(), "a fresh track reports empty")
	assert_eq(cam.track.size(), 0, "track array is empty")


func test_record_camera_dedups_consecutive_identical_frames() -> void:
	var cam := _fresh()
	cam.record_camera(0, Vector2(100.0, 200.0), 1.0)
	cam.record_camera(1, Vector2(100.0, 200.0), 1.0)
	cam.record_camera(2, Vector2(100.0, 200.0), 1.5)
	cam.record_camera(3, Vector2(150.0, 200.0), 1.5)

	assert_eq(cam.track.size(), 3, "identical frame dropped; zoom and pos changes kept")
	assert_true(cam.has_track(), "track with frames reports present")
	var f0: Dictionary = cam.track[0]
	assert_eq(f0["tick"], 0)
	assert_almost_eq(float(f0["x"]), 100.0, 0.0001)
	assert_almost_eq(float(f0["y"]), 200.0, 0.0001)
	assert_almost_eq(float(f0["zoom"]), 1.0, 0.0001)


func test_for_tick_empty_when_no_track() -> void:
	var cam := _fresh()
	assert_eq(cam.for_tick(0), {}, "empty track returns empty dict")
	assert_eq(cam.for_tick(42), {}, "empty track returns empty dict for any tick")


func test_for_tick_holds_last_keyframe() -> void:
	var cam := _fresh()
	cam.record_camera(10, Vector2(10.0, 20.0), 1.0)
	cam.record_camera(20, Vector2(50.0, 60.0), 2.0)

	var before: Dictionary = cam.for_tick(0)
	assert_almost_eq(float(before["x"]), 10.0, 0.0001, "tick before first holds first framing x")
	assert_almost_eq(float(before["y"]), 20.0, 0.0001, "tick before first holds first framing y")
	assert_almost_eq(float(before["zoom"]), 1.0, 0.0001, "tick before first holds first zoom")

	var mid: Dictionary = cam.for_tick(15)
	assert_almost_eq(float(mid["x"]), 10.0, 0.0001, "tick between holds earlier frame x")
	assert_almost_eq(float(mid["y"]), 20.0, 0.0001, "tick between holds earlier frame y")

	var exact: Dictionary = cam.for_tick(20)
	assert_almost_eq(float(exact["x"]), 50.0, 0.0001, "exact tick switches to new keyframe x")
	assert_almost_eq(float(exact["y"]), 60.0, 0.0001, "exact tick switches to new keyframe y")
	assert_almost_eq(float(exact["zoom"]), 2.0, 0.0001, "exact tick switches to new zoom")

	var past: Dictionary = cam.for_tick(99)
	assert_almost_eq(float(past["x"]), 50.0, 0.0001, "tick past last keyframe holds last x")
	assert_almost_eq(float(past["y"]), 60.0, 0.0001, "tick past last keyframe holds last y")


func test_for_tick_rewinds_on_step_back() -> void:
	var cam := _fresh()
	cam.record_camera(10, Vector2(10.0, 20.0), 1.0)
	cam.record_camera(20, Vector2(50.0, 60.0), 2.0)

	var advanced: Dictionary = cam.for_tick(20)
	assert_almost_eq(float(advanced["x"]), 50.0, 0.0001)

	var rewound: Dictionary = cam.for_tick(5)
	assert_almost_eq(float(rewound["x"]), 10.0, 0.0001, "stepping back rewinds to first keyframe x")
	assert_almost_eq(float(rewound["y"]), 20.0, 0.0001, "stepping back rewinds to first keyframe y")


func test_reset_clears_track_and_index() -> void:
	var cam := _fresh()
	cam.record_camera(5, Vector2(10.0, 20.0), 1.0)
	cam.record_camera(15, Vector2(30.0, 40.0), 2.0)
	var _active: Dictionary = cam.for_tick(15)
	assert_gt(cam.index, 0, "index advanced past zero")

	cam.reset()
	assert_eq(cam.track.size(), 0, "track array is cleared")
	assert_eq(cam.index, 0, "index is reset to zero")
	assert_false(cam.has_track(), "has_track reports false after reset")
