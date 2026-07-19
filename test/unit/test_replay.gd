extends GutTest
## Tests for the Replay presentation (camera) track: recording with dedup, playback
## stepping, save/load round-trip, and back-compat with replays that have no track.

const ReplayScript = preload("res://scripts/Replay.gd")


## A fresh, isolated Replay instance so tests never touch the live autoload's state.
func _fresh() -> Node:
	var r: Node = ReplayScript.new()
	add_child_autofree(r)
	return r


func test_record_camera_dedups_static_frames() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_camera(0, Vector2(100, 100), 1.0)
	r.record_camera(1, Vector2(100, 100), 1.0)   # unchanged -> dropped
	r.record_camera(2, Vector2(150, 100), 1.5)   # moved -> kept
	assert_eq(r._camera_track.size(), 2,
			"a still camera dedups to one keyframe; a move adds another")
	assert_true(r.has_camera_track(), "a recorded track reports present")


func test_record_camera_is_noop_outside_record() -> void:
	var r := _fresh()   # mode IDLE
	r.record_camera(0, Vector2(10, 10), 1.0)
	assert_eq(r._camera_track.size(), 0, "no camera is captured outside RECORD")
	assert_false(r.has_camera_track(), "no track without recording")


func test_camera_for_tick_holds_last_keyframe() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._camera_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "zoom": 1.0},
		{"tick": 10, "x": 100.0, "y": 0.0, "zoom": 2.0},
	]
	assert_eq(r.camera_for_tick(0)["zoom"], 1.0, "tick 0 uses the first keyframe")
	assert_eq(r.camera_for_tick(5)["zoom"], 1.0, "between keyframes it holds the earlier one")
	assert_eq(r.camera_for_tick(10)["x"], 100.0, "at the next keyframe's tick it switches")
	assert_eq(r.camera_for_tick(99)["x"], 100.0, "past the last keyframe it holds the last")


func test_camera_for_tick_before_first_keyframe_holds_first() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._camera_track = [{"tick": 5, "x": 7.0, "y": 8.0, "zoom": 1.5}]
	assert_eq(r.camera_for_tick(0)["x"], 7.0,
			"a tick before the first keyframe holds the first framing")


func test_camera_for_tick_rewinds_on_step_back() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._camera_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "zoom": 1.0},
		{"tick": 10, "x": 100.0, "y": 0.0, "zoom": 2.0},
	]
	assert_eq(r.camera_for_tick(10)["x"], 100.0, "advance the cursor to the later keyframe")
	assert_eq(r.camera_for_tick(0)["x"], 0.0, "a step back to tick 0 rewinds to the first keyframe")


func test_camera_for_tick_empty_without_track_or_playback() -> void:
	var r := _fresh()   # IDLE, no track
	assert_eq(r.camera_for_tick(0), {}, "no track / not playing back -> empty")


func test_save_load_round_trips_the_camera_track() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_camera(0, Vector2(10.0, 20.0), 0.8)
	r.record_camera(3, Vector2(40.0, 20.0), 1.2)
	var path: String = r.save("Test", 3)
	assert_ne(path, "", "the recording saves to a path")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	assert_true(loaded.has_camera_track(), "the camera track survives save/load")
	assert_almost_eq(loaded.camera_for_tick(0)["zoom"], 0.8, 0.0001, "zoom round-trips")
	assert_almost_eq(loaded.camera_for_tick(3)["x"], 40.0, 0.0001, "position round-trips")


func test_replay_without_camera_moves_has_no_track() -> void:
	# A recording that never moves (records) the camera omits the track entirely, so it
	# loads exactly like a pre-camera replay: no track, default static camera on playback.
	var r := _fresh()
	r.start_recording()
	var path: String = r.save("Test", 0)
	assert_ne(path, "", "the recording saves even with no camera track")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "it loads")
	assert_false(loaded.has_camera_track(), "no camera keyframes -> no presentation track")
	assert_eq(loaded.camera_for_tick(0), {}, "playback drives nothing -> static camera")


func test_save_load_round_trips_an_anchored_frontage_orders_anchor_offset() -> void:
	# Regression test: an asymmetric (anchored) explicatio/duplicatio's anchor_offset must
	# survive a save/load round trip like every other order field, or a saved-and-replayed
	# anchored widen silently re-centres instead of holding the flank (live-vs-replay desync
	# -- the anchor read correctly in a live session, since Battle.enqueue_file_double applies
	# it immediately, but a *replayed* recording of the same session would drop it, since
	# record_order never carried it to the saved file).
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -4, 0, 0, 32, INF, 0, -72.0)   # -4 = ORDER_FRONTAGE_ONLY
	var path: String = r.save("Test", 5)
	assert_ne(path, "", "the recording saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1, "the frontage order round-trips")
	assert_almost_eq(float(due[0].get("anchor_offset", 0.0)), -72.0, 0.0001,
			"the anchor offset round-trips through save/load, not just live recording")


func test_a_centred_frontage_order_omits_anchor_offset_on_round_trip() -> void:
	# The plain (centred) case -- anchor_offset 0.0 -- stays omitted on save (matching the
	# in-memory record_order behaviour for every other optional field) and reads back as the
	# same 0.0 default, so an old replay recorded before this field existed still loads and
	# plays exactly like a fresh centred resize.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -4, 0, 0, 16)   # -4 = ORDER_FRONTAGE_ONLY, no anchor
	var path: String = r.save("Test", 5)

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1, "the frontage order round-trips")
	assert_false(due[0].has("anchor_offset"),
			"a centred resize's order carries no anchor_offset key at all, like a pre-anchor replay")


func test_save_load_round_trips_a_multi_unit_form_up_group_id() -> void:
	# docs/atomic-order-decomposition-design.md: a multi-unit drag-line form-up's shared
	# group id must survive save/load like any other order field, or a replayed recording
	# would rebuild every per-unit order as ungrouped (losing the FORM_UP tree structure)
	# even though the live session grouped them.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [11], Vector2(10, 20), -1, 0, 0, 4, 0.5, 0, 0.0, 2)
	r.record_order(5, [12], Vector2(30, 20), -1, 0, 0, 4, 0.5, 0, 0.0, 2)
	var path: String = r.save("Test", 5)
	assert_ne(path, "", "the recording saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 2, "both grouped orders round-trip")
	assert_eq(int(due[0].get("form_up_group", -1)), 2, "the group id round-trips, not just live")
	assert_eq(int(due[1].get("form_up_group", -1)), 2,
			"both units' orders read back tagged with the SAME group id")


func test_an_ungrouped_form_up_omits_form_up_group_on_round_trip() -> void:
	# A single-unit form-up (or any other order) carries no group id at all, matching the
	# in-memory record_order behaviour for every other optional field -- an old replay
	# recorded before this field existed still loads with no group id, same as a fresh
	# single-unit deploy.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -1, 0, 0, 4, 0.5)   # a plain (ungrouped) form-up
	var path: String = r.save("Test", 5)

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1)
	assert_false(due[0].has("form_up_group"),
			"an ungrouped order carries no form_up_group key at all, like a pre-grouping replay")


func test_save_load_round_trips_a_unit_settings_orders_toggles() -> void:
	# A mid-battle walk_advance/reform_before_move toggle is its own recordable order
	# (Battle.enqueue_unit_settings, target ORDER_UNIT_SETTINGS_ONLY = -9) -- the toggle
	# itself, not just its downstream effect, must survive save/load like every other order
	# field, or a replayed recording would silently drop the toggle and desync from the
	# unit state the live session actually reached.
	var r := _fresh()
	r.start_recording()
	# -9 = Battle.ORDER_UNIT_SETTINGS_ONLY; 1 = UnitSettingToggle.ON, 2 = UnitSettingToggle.OFF.
	r.record_order(5, [0], Vector2.ZERO, -9, 0, 0, 0, INF, 0, 0.0, -1, 1, 2)
	var path: String = r.save("Test", 5)
	assert_ne(path, "", "the recording saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1, "the unit-settings order round-trips")
	assert_eq(int(due[0].get("walk_advance_toggle", 0)), 1,
			"the walk_advance toggle (ON) round-trips through save/load")
	assert_eq(int(due[0].get("reform_toggle", 0)), 2,
			"the reform_before_move toggle (OFF) round-trips through save/load")


func test_a_leave_toggle_omits_the_unit_settings_keys_on_round_trip() -> void:
	# The all-LEAVE case (0) stays omitted on save, matching the in-memory record_order
	# behaviour for every other optional field -- an old replay recorded before this
	# migration still loads and plays exactly like a fresh order that never touches
	# either setting.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -1, 0, 0, 4, 0.5)   # a plain move, no toggles at all
	var path: String = r.save("Test", 5)

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1)
	assert_false(due[0].has("walk_advance_toggle"),
			"a LEAVE toggle carries no walk_advance_toggle key at all, like an old-format replay")
	assert_false(due[0].has("reform_toggle"),
			"a LEAVE toggle carries no reform_toggle key at all, like an old-format replay")
