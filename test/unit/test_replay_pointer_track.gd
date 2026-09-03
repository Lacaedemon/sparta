extends GutTest
## Unit tests for ReplayPointerTrack: recording with cursor dedup (POINTER_EPS),
## selection/drag/stance changes, for_tick keyframe hold and rewind,
## cursor_for_tick continuous interpolation, and reset.

const ReplayPointerTrackScript = preload("res://scripts/ReplayPointerTrack.gd")


func _fresh() -> ReplayPointerTrackScript:
	return ReplayPointerTrackScript.new()


func test_has_track_false_when_empty() -> void:
	var ptr := _fresh()
	assert_false(ptr.has_track(), "fresh pointer track is empty")
	assert_eq(ptr.track.size(), 0)


func test_record_pointer_dedups_within_eps() -> void:
	var ptr := _fresh()
	ptr.record_pointer(0, Vector2(100.0, 100.0), false, Vector2.ZERO, [], 0)
	ptr.record_pointer(1, Vector2(100.0, 100.0), false, Vector2.ZERO, [], 0)
	ptr.record_pointer(2, Vector2(101.0, 100.0), false, Vector2.ZERO, [], 0)
	ptr.record_pointer(3, Vector2(140.0, 100.0), false, Vector2.ZERO, [], 0)

	assert_eq(ptr.track.size(), 2, "sub-eps move dropped; larger move kept")
	assert_true(ptr.has_track())


func test_record_pointer_drag_start_and_stance_and_selection() -> void:
	var ptr := _fresh()
	ptr.record_pointer(0, Vector2(50.0, 50.0), false, Vector2.ZERO, [], 0)
	ptr.record_pointer(1, Vector2(50.0, 50.0), false, Vector2.ZERO, [1], 0)
	ptr.record_pointer(2, Vector2(50.0, 50.0), false, Vector2.ZERO, [1], 2)
	ptr.record_pointer(3, Vector2(50.0, 50.0), true, Vector2(10.0, 10.0), [1], 2)
	ptr.record_pointer(4, Vector2(50.0, 50.0), true, Vector2(10.5, 10.0), [1], 2)
	ptr.record_pointer(5, Vector2(50.0, 50.0), true, Vector2(30.0, 10.0), [1], 2)

	assert_eq(ptr.track.size(), 5, "selection, stance, drag-open, and drag-corner changes recorded")
	var d0: Dictionary = ptr.track[0]
	assert_false(d0.has("sx"), "non-dragging entry has no sx")
	var d3: Dictionary = ptr.track[3]
	assert_true(bool(d3["drag"]))
	assert_almost_eq(float(d3["sx"]), 10.0, 0.0001)
	assert_almost_eq(float(d3["sy"]), 10.0, 0.0001)


func test_for_tick_empty_when_no_track() -> void:
	var ptr := _fresh()
	assert_eq(ptr.for_tick(0), {})
	assert_eq(ptr.for_tick(42), {})


func test_for_tick_holds_and_rewinds() -> void:
	var ptr := _fresh()
	ptr.track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "drag": false, "sel": [], "mode": 0},
		{"tick": 10, "x": 100.0, "y": 50.0, "drag": false, "sel": [3], "mode": 2},
	]
	var at_0: Dictionary = ptr.for_tick(0)
	assert_almost_eq(float(at_0["x"]), 0.0, 0.0001)
	assert_eq(at_0["mode"], 0)

	var at_5: Dictionary = ptr.for_tick(5)
	assert_almost_eq(float(at_5["x"]), 0.0, 0.0001, "holds earlier keyframe before tick 10")

	var at_10: Dictionary = ptr.for_tick(10)
	assert_almost_eq(float(at_10["x"]), 100.0, 0.0001)
	assert_almost_eq(float(at_10["y"]), 50.0, 0.0001)
	assert_eq(at_10["mode"], 2)

	var at_99: Dictionary = ptr.for_tick(99)
	assert_almost_eq(float(at_99["x"]), 100.0, 0.0001, "past last keyframe holds last")

	var rewound: Dictionary = ptr.for_tick(0)
	assert_almost_eq(float(rewound["x"]), 0.0, 0.0001, "step back rewinds to tick 0")


func test_cursor_for_tick_empty_returns_zero() -> void:
	var ptr := _fresh()
	var pos: Vector2 = ptr.cursor_for_tick(0)
	assert_almost_eq(pos.x, 0.0, 0.0001)
	assert_almost_eq(pos.y, 0.0, 0.0001)


func test_cursor_for_tick_interpolates_between_keyframes() -> void:
	var ptr := _fresh()
	ptr.track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "drag": false, "sel": [], "mode": 0},
		{"tick": 10, "x": 100.0, "y": 200.0, "drag": false, "sel": [], "mode": 0},
	]
	var p0: Vector2 = ptr.cursor_for_tick(0)
	assert_almost_eq(p0.x, 0.0, 0.0001)
	assert_almost_eq(p0.y, 0.0, 0.0001)

	var p5: Vector2 = ptr.cursor_for_tick(5)
	assert_almost_eq(p5.x, 50.0, 0.001, "halfway glides to midpoint x")
	assert_almost_eq(p5.y, 100.0, 0.001, "halfway glides to midpoint y")

	var p8: Vector2 = ptr.cursor_for_tick(8)
	assert_almost_eq(p8.x, 80.0, 0.001)
	assert_almost_eq(p8.y, 160.0, 0.001)

	var p10: Vector2 = ptr.cursor_for_tick(10)
	assert_almost_eq(p10.x, 100.0, 0.0001)
	assert_almost_eq(p10.y, 200.0, 0.0001)

	var p20: Vector2 = ptr.cursor_for_tick(20)
	assert_almost_eq(p20.x, 100.0, 0.0001, "past last keyframe holds last pos x")
	assert_almost_eq(p20.y, 200.0, 0.0001, "past last keyframe holds last pos y")


func test_cursor_for_tick_rewinds_on_step_back() -> void:
	var ptr := _fresh()
	ptr.track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "drag": false, "sel": [], "mode": 0},
		{"tick": 10, "x": 100.0, "y": 200.0, "drag": false, "sel": [], "mode": 0},
	]
	var _adv: Vector2 = ptr.cursor_for_tick(10)
	var rew: Vector2 = ptr.cursor_for_tick(5)
	assert_almost_eq(rew.x, 50.0, 0.001)
	assert_almost_eq(rew.y, 100.0, 0.001)


# The span-guard in cursor_for_tick is unreachable for a sorted track and exists only as a defensive check, so the observable contract is "the later of two same-tick keyframes wins".
func test_cursor_for_tick_duplicate_tick_resolves_to_the_later_keyframe() -> void:
	var ptr := _fresh()
	ptr.track = [
		{"tick": 5, "x": 40.0, "y": 60.0, "drag": false, "sel": [], "mode": 0},
		{"tick": 5, "x": 80.0, "y": 120.0, "drag": false, "sel": [], "mode": 1},
	]
	var pos: Vector2 = ptr.cursor_for_tick(5)
	assert_almost_eq(pos.x, 80.0, 0.0001)
	assert_almost_eq(pos.y, 120.0, 0.0001)


func test_reset_clears_track_and_index() -> void:
	var ptr := _fresh()
	ptr.record_pointer(0, Vector2(10.0, 20.0), false, Vector2.ZERO, [], 0)
	ptr.record_pointer(10, Vector2(40.0, 50.0), false, Vector2.ZERO, [], 0)
	var _cur: Vector2 = ptr.cursor_for_tick(10)
	assert_gt(ptr.index, 0)

	ptr.reset()
	assert_eq(ptr.track.size(), 0)
	assert_eq(ptr.index, 0)
	assert_false(ptr.has_track())
