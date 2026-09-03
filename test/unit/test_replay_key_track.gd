extends GutTest
## Unit tests for ReplayKeyTrack: recording with empty-label drop,
## for_tick windowing at boundary (includes age <= window, excludes age > window),
## breaks at future ticks, and reset.

const ReplayKeyTrackScript = preload("res://scripts/ReplayKeyTrack.gd")


func _fresh() -> ReplayKeyTrackScript:
	return ReplayKeyTrackScript.new()


func test_record_keys_drops_empty_labels() -> void:
	var kt := _fresh()
	kt.record_keys(0, ["]"])
	kt.record_keys(1, [])
	kt.record_keys(2, ["[", "T"])

	assert_eq(kt.track.size(), 2, "empty label array is not recorded")
	var k0: Dictionary = kt.track[0]
	assert_eq(k0["tick"], 0)
	assert_eq(k0["labels"], ["]"])
	var k1: Dictionary = kt.track[1]
	assert_eq(k1["tick"], 2)
	assert_eq(k1["labels"], ["[", "T"])


func test_for_tick_empty_track() -> void:
	var kt := _fresh()
	assert_eq(kt.for_tick(10, 5), [], "empty track returns empty array")


func test_for_tick_window_boundaries() -> void:
	var kt := _fresh()
	kt.record_keys(10, ["A"])
	kt.record_keys(20, ["B"])
	kt.record_keys(30, ["C"])

	var res1: Array = kt.for_tick(25, 10)
	assert_eq(res1.size(), 1, "only tick 20 is inside the window")
	var r0: Dictionary = res1[0]
	assert_eq(r0["label"], "B")
	assert_eq(r0["age"], 5)

	var res2: Array = kt.for_tick(20, 10)
	assert_eq(res2.size(), 2, "boundary age 10 and age 0 are both included")
	var b0: Dictionary = res2[0]
	assert_eq(b0["label"], "A")
	assert_eq(b0["age"], 10)
	var b1: Dictionary = res2[1]
	assert_eq(b1["label"], "B")
	assert_eq(b1["age"], 0)

	var res3: Array = kt.for_tick(20, 9)
	assert_eq(res3.size(), 1, "age 10 is excluded when window is 9")
	var c0: Dictionary = res3[0]
	assert_eq(c0["label"], "B")
	assert_eq(c0["age"], 0)


func test_reset_clears_track() -> void:
	var kt := _fresh()
	kt.record_keys(10, ["A"])
	assert_eq(kt.track.size(), 1)
	kt.reset()
	assert_eq(kt.track.size(), 0)
