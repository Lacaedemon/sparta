extends GutTest
## Tests for the Replay fog-of-war track: recording a fog toggle with dedup,
## playback dispatch (and its rewind-cursor repositioning), save/load round-trip,
## and mid-battle replay reproduction.

const ReplayScript = preload("res://scripts/Replay.gd")


func _fresh() -> Node:
	var r: Node = ReplayScript.new()
	add_child_autofree(r)
	return r


func after_each() -> void:
	Replay.reset()
	Replay.forced_seed = -1
	Settings.set_fog_of_war_session(false)


func test_record_fog_change_is_noop_outside_record() -> void:
	var r := _fresh()   # IDLE
	r.record_fog_change(0, true)
	assert_eq(r._fog_track.size(), 0, "no fog change captured outside RECORD")


func test_record_fog_change_dedups_a_repeated_value() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_fog_change(10, true)
	r.record_fog_change(20, true)   # unchanged -> dropped
	r.record_fog_change(30, false)  # real change -> kept
	assert_eq(r._fog_track.size(), 2,
			"repeated value dedups against the track's last entry; real change is kept")


func test_record_fog_change_dedups_against_the_initial_state() -> void:
	var r := _fresh()
	r.start_recording()
	r.init_fog(false)
	r.record_fog_change(5, false)   # false is already initial state
	assert_eq(r._fog_track.size(), 0,
			"recording initial value with no prior entry is a no-op")
	r.record_fog_change(10, true)
	assert_eq(r._fog_track.size(), 1, "transitioning to true is recorded")


func test_fog_for_tick_is_the_sentinel_outside_playback() -> void:
	var r := _fresh()   # IDLE, not PLAYBACK
	r._fog_track = [{"tick": 5, "value": true}]
	assert_eq(r.fog_for_tick(5), -1, "no dispatch outside playback")


func test_fog_for_tick_dispatches_once_and_advances_the_cursor() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._fog_track = [{"tick": 200, "value": true}]
	assert_eq(r.fog_for_tick(199), -1, "nothing due yet")
	assert_eq(r.fog_for_tick(200), 1, "the recorded value dispatches at its own tick")
	assert_eq(r.fog_for_tick(200), -1,
			"cursor advanced -- second call at same tick returns sentinel")
	assert_eq(r.fog_for_tick(201), -1, "nothing due on later tick")


func test_fog_for_tick_walks_multiple_entries_in_order() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._fog_track = [
		{"tick": 10, "value": true},
		{"tick": 20, "value": false},
		{"tick": 30, "value": true},
	]
	assert_eq(r.fog_for_tick(10), 1, "tick 10 enables fog")
	assert_eq(r.fog_for_tick(15), -1, "no change at tick 15")
	assert_eq(r.fog_for_tick(20), 0, "tick 20 disables fog")
	assert_eq(r.fog_for_tick(30), 1, "tick 30 re-enables fog")


func test_save_load_round_trips_the_fog_track() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_fog_change(15, true)
	r.record_fog_change(45, false)

	var path: String = r.save("FogRoundTrip", 60)
	assert_ne(path, "", "replay with fog track saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "saved replay loads")
	assert_eq(loaded.mode, ReplayScript.Mode.PLAYBACK, "replay is armed for playback")
	assert_eq(loaded._fog_track.size(), 2, "both fog track entries survived the round-trip")
	assert_eq(int(loaded._fog_track[0]["tick"]), 15)
	assert_true(bool(loaded._fog_track[0]["value"]))
	assert_eq(int(loaded._fog_track[1]["tick"]), 45)
	assert_false(bool(loaded._fog_track[1]["value"]))


func test_replay_without_fog_track_has_an_empty_track() -> void:
	var r := _fresh()
	r.start_recording()
	var path: String = r.save("NoFogTrack", 30)
	assert_ne(path, "", "baseline replay saves")
	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "saved replay loads")
	assert_eq(loaded._fog_track.size(), 0, "missing fog track defaults to empty")
	assert_eq(loaded.fog_for_tick(0), -1, "playback never dispatches fog change")


func test_start_recording_clears_a_stale_fog_track() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_fog_change(10, true)
	r.start_recording()
	assert_eq(r._fog_track.size(), 0,
			"start_recording cleared the loaded playback fog track")
	assert_eq(r._fog_index, 0, "and reset the read cursor")


func test_a_mid_battle_fog_toggle_replays_identically() -> void:
	var scenario := [
		{"team": 0, "type": "Infantry", "x": 500, "y": 250, "count": 20, "facing": [0, 1]},
		{"team": 1, "type": "Infantry", "x": 500, "y": 1500, "count": 20, "facing": [0, -1]},
	]

	# --- Live recording ------------------------------------------------
	Replay.forced_seed = 55222
	var live: Node = load("res://scenes/Battle.tscn").instantiate()
	live.drill_mode = true
	live.scenario = scenario
	add_child_autofree(live)

	for _k in range(5):
		await get_tree().physics_frame

	assert_false(live.is_fog_active(), "fog begins off")

	# Toggle fog on mid-battle at tick ~5
	Settings.fog_of_war = true
	live._on_settings_changed()
	assert_true(live.is_fog_active(), "fog is active after toggle")

	for _k in range(10):
		await get_tree().physics_frame

	# Toggle fog back off
	Settings.fog_of_war = false
	live._on_settings_changed()
	assert_false(live.is_fog_active(), "fog is disabled after second toggle")

	for _k in range(5):
		await get_tree().physics_frame

	var live_final_tick: int = live.current_tick()
	var path: String = Replay.save("TestFogReplay", live_final_tick)
	assert_ne(path, "", "the recording saves")
	live.free()
	await get_tree().physics_frame

	# --- Playback ------------------------------------------------------
	assert_true(Replay.start_playback(path), "the saved replay loads")
	assert_eq(Replay._fog_track.size(), 2, "both transitions recorded")

	var replayed: Node = load("res://scenes/Battle.tscn").instantiate()
	replayed.drill_mode = true
	replayed.scenario = scenario
	add_child_autofree(replayed)

	assert_false(replayed.is_fog_active(), "playback starts with fog off")

	while replayed.current_tick() < 8:
		await get_tree().physics_frame

	assert_true(replayed.is_fog_active(), "playback toggles fog on at recorded tick")

	while replayed.current_tick() < live_final_tick:
		await get_tree().physics_frame

	assert_false(replayed.is_fog_active(), "playback toggles fog off at second recorded tick")
