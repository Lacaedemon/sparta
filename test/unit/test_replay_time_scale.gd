extends GutTest
## Tests for the Replay time-scale track: recording a slow-motion change with dedup,
## playback dispatch (and its rewind-cursor repositioning), save/load round-trip, and
## back-compat with replays that have no time-scale track. Unlike the pointer/keys tracks
## this one feeds the simulation on playback rather than being purely cosmetic -- see
## Replay._time_scale_track's own doc for why.

const ReplayScript = preload("res://scripts/Replay.gd")


func _fresh() -> Node:
	var r: Node = ReplayScript.new()
	add_child_autofree(r)
	return r


func after_each() -> void:
	Replay.reset()
	Replay.forced_seed = -1
	Engine.time_scale = 1.0   # in case a live-battle test below is interrupted mid-slowdown


func test_record_time_scale_change_is_noop_outside_record() -> void:
	var r := _fresh()   # IDLE
	r.record_time_scale_change(0, 0.5)
	assert_eq(r._time_scale_track.size(), 0, "no time_scale captured outside RECORD")


func test_record_time_scale_change_dedups_a_repeated_value() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_time_scale_change(10, 0.5)
	r.record_time_scale_change(20, 0.5)   # unchanged -> dropped
	r.record_time_scale_change(30, 0.25)  # a real change -> kept
	assert_eq(r._time_scale_track.size(), 2,
			"a repeated value dedups against the track's own last entry; a real change is kept")


func test_record_time_scale_change_dedups_against_the_implicit_default() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_time_scale_change(5, 1.0)   # 1.0 is already the implicit starting value
	assert_eq(r._time_scale_track.size(), 0,
			"recording the default value with no prior entry is a no-op, not a stored keyframe")


func test_time_scale_for_tick_is_the_sentinel_outside_playback() -> void:
	var r := _fresh()   # IDLE, not PLAYBACK
	r._time_scale_track = [{"tick": 5, "value": 0.5}]
	assert_eq(r.time_scale_for_tick(5), -1.0, "no dispatch outside playback")


func test_time_scale_for_tick_dispatches_once_and_advances_the_cursor() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._time_scale_track = [{"tick": 200, "value": 0.5}]
	assert_eq(r.time_scale_for_tick(199), -1.0, "nothing due yet")
	assert_eq(r.time_scale_for_tick(200), 0.5, "the recorded value dispatches at its own tick")
	assert_eq(r.time_scale_for_tick(200), -1.0,
			"the cursor advanced past it -- a second call at the same tick dispatches nothing")
	assert_eq(r.time_scale_for_tick(201), -1.0, "and nothing is due on a later tick either")


func test_time_scale_for_tick_walks_multiple_entries_in_order() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._time_scale_track = [
		{"tick": 10, "value": 0.5},
		{"tick": 20, "value": 0.25},
		{"tick": 30, "value": 1.0},
	]
	assert_eq(r.time_scale_for_tick(10), 0.5)
	assert_eq(r.time_scale_for_tick(20), 0.25)
	assert_eq(r.time_scale_for_tick(30), 1.0)


func test_rewind_cursor_to_tick_repositions_the_time_scale_cursor() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._time_scale_track = [
		{"tick": 10, "value": 0.5},
		{"tick": 20, "value": 0.25},
		{"tick": 30, "value": 1.0},
	]
	# Advance past every entry, as ordinary forward playback would.
	r.time_scale_for_tick(10)
	r.time_scale_for_tick(20)
	r.time_scale_for_tick(30)
	assert_eq(r.time_scale_for_tick(31), -1.0, "the cursor has consumed every entry")

	r.rewind_cursor_to_tick(15)   # a rewind lands between the 10 and 20 entries
	assert_eq(r.time_scale_for_tick(15), -1.0, "nothing is due exactly at the landing tick")
	assert_eq(r.time_scale_for_tick(20), 0.25,
			"resuming forward from the rewind still dispatches the entry it hadn't reached yet")
	assert_eq(r.time_scale_for_tick(30), 1.0, "and the one after that")


func test_save_load_round_trips_the_time_scale_track() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_time_scale_change(50, 0.5)
	r.record_time_scale_change(120, 0.1)
	var path: String = r.save("Test", 120)
	assert_ne(path, "", "the recording saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	assert_eq(loaded._time_scale_track.size(), 2, "the time-scale track survives save/load")
	assert_eq(loaded.time_scale_for_tick(50), 0.5, "the first change round-trips")
	assert_eq(loaded.time_scale_for_tick(120), 0.1, "and the second")


func test_replay_without_time_scale_changes_has_an_empty_track() -> void:
	var r := _fresh()
	r.start_recording()
	var path: String = r.save("Test", 0)
	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "it loads")
	assert_eq(loaded._time_scale_track.size(), 0,
			"no slow-motion change made -> no time-scale track, exactly the pre-existing shape")
	assert_eq(loaded.time_scale_for_tick(0), -1.0, "playback never touches Engine.time_scale")


func test_start_recording_clears_a_stale_time_scale_track() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_time_scale_change(5, 0.5)
	r.start_recording()   # a fresh battle
	assert_eq(r._time_scale_track.size(), 0, "the previous battle's track doesn't leak into the next")


# --- live-battle integration: proves the actual reported bug is fixed ---------------

func _lone_unit() -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		if node is Unit:
			return node
	return null


## The decisive end-to-end proof: a mid-battle slow-motion change must reproduce the same
## per-tick delta trajectory on replay, not silently be ignored -- see
## Replay._time_scale_track's own doc for why an un-recorded change would desync a
## "deterministic" replay. Mirrors test_replay_unit_settings_battle.gd's live-record ->
## save -> fresh-battle-playback shape; drives Replay.record_time_scale_change directly
## (like that file drives Battle.enqueue_unit_settings directly) rather than through HUD's
## F5 handler, which is covered separately in test_hud_slowmo.gd.
func test_a_mid_battle_time_scale_change_replays_identically() -> void:
	var scenario := [
		{"team": 0, "type": "Infantry", "x": 500, "y": 250, "count": 20, "facing": [0, 1]},
	]

	# --- Live recording ------------------------------------------------
	Replay.forced_seed = 55221
	var live: Node = load("res://scenes/Battle.tscn").instantiate()
	live.drill_mode = true
	live.scenario = scenario
	add_child_autofree(live)
	var u := _lone_unit()
	assert_not_null(u, "the scenario spawned the lone unit")
	if u == null:
		return

	for _k in range(10):
		await get_tree().physics_frame
	live.enqueue_order([u.uid], Vector2(500, 950), -1)

	for _k in range(20):
		await get_tree().physics_frame
	# Halfway through the march, slow to a quarter speed -- exactly what HUD._cycle_slowmo does
	# (set Engine.time_scale live, and record the change so it survives on replay).
	Engine.time_scale = 0.25
	Replay.record_time_scale_change(live.current_tick(), 0.25)

	for _k in range(60):
		await get_tree().physics_frame
	Engine.time_scale = 1.0   # back to normal speed, also recorded
	Replay.record_time_scale_change(live.current_tick(), 1.0)

	for _k in range(20):
		await get_tree().physics_frame
	var live_final_tick: int = live.current_tick()
	var live_final_pos: Vector2 = u.position

	var path: String = Replay.save("Test", live_final_tick)
	assert_ne(path, "", "the recording saves")
	live.free()
	await get_tree().physics_frame

	# --- Playback --------------------------------------------------------
	assert_true(Replay.start_playback(path), "the saved replay loads")
	var replayed: Node = load("res://scenes/Battle.tscn").instantiate()
	replayed.drill_mode = true
	replayed.scenario = scenario
	add_child_autofree(replayed)
	var ru := _lone_unit()
	assert_not_null(ru, "the replayed scenario spawns the same lone unit")
	if ru == null:
		return

	while replayed.current_tick() < live_final_tick:
		await get_tree().physics_frame

	assert_almost_eq(ru.position.x, live_final_pos.x, 1.0,
			"the recorded slow-motion segment reproduces the same march distance on replay,")
	assert_almost_eq(ru.position.y, live_final_pos.y, 1.0,
			"not the distance a constant-speed march (ignoring the recorded slowdown) would cover")
