extends GutTest
## Battle.capture_snapshot()/restore_snapshot()/seek_to_tick() in a LIVE battle:
## the derived state-snapshot cache that lets a PLAYBACK rewind resume from a cached
## mid-battle moment instead of resimulating from tick 0. Battle._physics_process's own
## automatic per-tick capture, ReplaySnapshotCache's density/eviction contract, and
## Unit.to_snapshot_dict/apply_snapshot_dict's per-field round-trip are covered separately
## (test_replay_snapshot_cache.gd, test_unit_snapshot.gd, test_order_snapshot.gd); this file
## is the end-to-end wiring through a real Battle scene.


## Puts Replay into a fresh, seeded PLAYBACK session (no recorded orders -- these tests drive
## the battle purely through spawned units and time, not a loaded replay file) and returns
## the previous mode so the caller can restore it in an autofree cleanup.
func _enter_playback() -> int:
	var prev_mode: int = Replay.mode
	Replay.forced_seed = 424242
	Replay.start_recording()   # resets _orders/tracks and seeds rng from forced_seed
	Replay.mode = Replay.Mode.PLAYBACK
	return prev_mode


func _leave_playback(prev_mode: int) -> void:
	Replay.mode = prev_mode


func _clash_scenario() -> Array:
	# Two small units placed close enough to clash almost immediately, so a snapshot taken
	# after a couple dozen ticks reflects real combat state (target_enemy set, soldiers
	# engaged) rather than an idle spawn.
	return [
		{"team": 0, "type": "Infantry", "x": 500, "y": 470, "count": 20},
		{"team": 1, "type": "Infantry", "x": 500, "y": 530, "count": 20, "facing": [0, -1]},
	]


func _spawn_battle(scenario: Array, interval: int = 40, max_snapshots: int = 20) -> Node:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = scenario
	battle.replay_snapshot_interval_ticks = interval
	battle.replay_snapshot_max = max_snapshots
	add_child_autofree(battle)
	return battle


func _units_by_uid(battle: Node) -> Dictionary:
	var out: Dictionary = {}
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null:
			out[unit.uid] = unit
	for u in get_tree().get_nodes_in_group("routers"):
		var unit: Unit = u as Unit
		if unit != null:
			out[unit.uid] = unit
	return out


func test_capture_and_restore_round_trips_a_live_battles_state() -> void:
	var prev_mode := _enter_playback()
	var battle := _spawn_battle(_clash_scenario())
	while battle.current_tick() < 60:
		await get_tree().physics_frame

	var before := _units_by_uid(battle)
	assert_eq(before.size(), 2, "both units are still on the field")
	var captured := {}
	for uid in before:
		var u: Unit = before[uid]
		captured[uid] = {
			"position": u.position, "morale": u.morale, "state": u.state,
			"soldiers": u.soldiers, "target_enemy_uid": u.target_enemy.uid if u.target_enemy != null else -1,
		}
	var snap: Dictionary = battle.capture_snapshot()
	var tick_at_capture: int = battle.current_tick()

	# Keep ticking so the live battle's state diverges from what was captured.
	while battle.current_tick() < tick_at_capture + 60:
		await get_tree().physics_frame

	battle.restore_snapshot(snap)

	assert_eq(battle.current_tick(), tick_at_capture, "the tick counter rewinds to the snapshot")
	var after := _units_by_uid(battle)
	assert_eq(after.size(), before.size(), "the same units exist after restore")
	for uid in captured:
		assert_true(after.has(uid), "unit %d survives the restore" % uid)
		if not after.has(uid):
			continue
		var u: Unit = after[uid]
		var c: Dictionary = captured[uid]
		assert_almost_eq(u.position.x, (c["position"] as Vector2).x, 0.01)
		assert_almost_eq(u.position.y, (c["position"] as Vector2).y, 0.01)
		assert_almost_eq(u.morale, c["morale"], 0.01)
		assert_eq(u.state, c["state"])
		assert_eq(u.soldiers, c["soldiers"])
		var restored_target_uid: int = u.target_enemy.uid if u.target_enemy != null else -1
		assert_eq(restored_target_uid, c["target_enemy_uid"],
				"target_enemy is resolved back to the same partner by uid")

	_leave_playback(prev_mode)


func test_capture_and_restore_round_trips_player_delegation() -> void:
	# Battle AI phase 4 (docs/battle-ai-design.md): Unit.player_group_id/subcommander_rank_title
	# must survive a snapshot round-trip like every other mutable runtime field (Unit.
	# to_snapshot_dict/apply_snapshot_dict's own field-level contract is covered in
	# test_unit_snapshot.gd; this is the Battle-level proof that a REAL restore -- which
	# respawns a fresh Unit node rather than mutating the live one -- actually carries
	# delegation through, not just an isolated in-memory dict round-trip). Written directly
	# on the unit rather than through Battle.enqueue_delegation: this whole suite runs the
	# battle in PLAYBACK mode (_enter_playback), where enqueue_delegation -- like every other
	# enqueue_* function -- is a deliberate no-op, and the live-play delegation gesture itself
	# is already covered elsewhere (test_battle.gd, test_battle_ai_player_delegation.gd). This
	# test is only about whether the snapshot machinery carries the fields, not about how they
	# got set in the first place.
	var prev_mode := _enter_playback()
	var battle := _spawn_battle(_clash_scenario())
	while battle.current_tick() < 20:
		await get_tree().physics_frame

	var units: Dictionary = _units_by_uid(battle)
	var team0_uid: int = -1
	for uid in units:
		if (units[uid] as Unit).team == 0:
			team0_uid = uid
			break
	assert_ne(team0_uid, -1, "a team-0 unit exists to delegate")

	var delegated_unit: Unit = units[team0_uid]
	delegated_unit.player_group_id = 5
	delegated_unit.subcommander_rank_title = "Tribune"

	var snap: Dictionary = battle.capture_snapshot()
	while battle.current_tick() < 80:
		await get_tree().physics_frame
	# Clear on the LIVE (post-capture) unit -- proves the restore brings back the CAPTURED
	# delegated state, not just whatever the live unit still happens to carry by coincidence.
	delegated_unit.player_group_id = Unit.UNDELEGATED
	delegated_unit.subcommander_rank_title = ""

	battle.restore_snapshot(snap)
	var restored: Unit = _units_by_uid(battle)[team0_uid]
	assert_true(restored.is_delegated(),
		"delegation survives a snapshot round-trip, like every other mutable runtime field")
	assert_eq(restored.player_group_id, 5)
	assert_eq(restored.subcommander_rank_title, "Tribune",
		"the resolved rank title survives the round-trip too")

	_leave_playback(prev_mode)


func test_restore_snapshot_lets_the_battle_keep_ticking_forward_afterward() -> void:
	var prev_mode := _enter_playback()
	var battle := _spawn_battle(_clash_scenario())
	while battle.current_tick() < 40:
		await get_tree().physics_frame
	var snap: Dictionary = battle.capture_snapshot()
	while battle.current_tick() < 80:
		await get_tree().physics_frame

	battle.restore_snapshot(snap)
	var resumed_from: int = battle.current_tick()
	for _i in range(20):
		await get_tree().physics_frame
	assert_gt(battle.current_tick(), resumed_from,
			"the tick counter keeps advancing normally after a restore")

	_leave_playback(prev_mode)


func test_restore_snapshot_revives_a_battle_that_already_concluded() -> void:
	# _check_victory runs during PLAYBACK too, so a replay watched to its end has
	# _ended set and the tree paused behind the end overlay -- both of which gate
	# every per-tick entry point. Rewinding to a mid-battle snapshot must clear that
	# terminal state or the restored battle sits frozen forever.
	var prev_mode := _enter_playback()
	var battle := _spawn_battle(_clash_scenario())
	while battle.current_tick() < 40:
		await get_tree().physics_frame
	var snap: Dictionary = battle.capture_snapshot()

	battle._end("Victory!")
	assert_true(get_tree().paused, "the end overlay pauses the tree")

	battle.restore_snapshot(snap)
	assert_false(battle._ended, "the terminal flag clears on rewind")
	assert_false(get_tree().paused, "the tree resumes ticking on rewind")
	var resumed_from: int = battle.current_tick()
	for _i in range(20):
		await get_tree().physics_frame
	assert_gt(battle.current_tick(), resumed_from,
			"the revived battle actually simulates forward again")

	_leave_playback(prev_mode)


func test_automatic_snapshot_capture_happens_at_the_configured_interval() -> void:
	var prev_mode := _enter_playback()
	var battle := _spawn_battle([{"team": 0, "type": "Infantry", "x": 500, "y": 500}], 25, 20)
	battle.drill_mode = true   # no opponent -- a stable scenario, purely testing the cadence
	while battle.current_tick() < 90:
		await get_tree().physics_frame

	var ticks: Array = battle._snapshot_cache.ticks()
	assert_true(ticks.size() >= 2, "several snapshots were captured over 90 ticks at interval 25")
	for t in ticks:
		assert_eq(int(t) % 25, 0, "every cached tick falls on the configured interval boundary")

	_leave_playback(prev_mode)


func test_seek_to_tick_restores_from_the_nearest_snapshot_without_overshooting() -> void:
	var prev_mode := _enter_playback()
	var battle := _spawn_battle([{"team": 0, "type": "Infantry", "x": 500, "y": 500}], 25, 20)
	battle.drill_mode = true
	while battle.current_tick() < 110:
		await get_tree().physics_frame

	battle.seek_to_tick(83)   # between the 75 and 100 snapshot boundaries
	assert_lte(battle.current_tick(), 83, "seek_to_tick never lands past the requested tick")
	assert_eq(battle.current_tick(), 75, "it lands exactly on the nearest snapshot at or before it")

	_leave_playback(prev_mode)


func test_seek_to_tick_is_a_noop_for_a_forward_target() -> void:
	var prev_mode := _enter_playback()
	var battle := _spawn_battle([{"team": 0, "type": "Infantry", "x": 500, "y": 500}], 25, 20)
	battle.drill_mode = true
	while battle.current_tick() < 40:
		await get_tree().physics_frame

	var before: int = battle.current_tick()
	battle.seek_to_tick(before + 500)   # a forward jump: nothing to derive it from
	assert_eq(battle.current_tick(), before, "a forward target is left untouched")

	_leave_playback(prev_mode)


func test_seek_to_tick_is_a_noop_outside_playback() -> void:
	var prev_mode := _enter_playback()
	var battle := _spawn_battle([{"team": 0, "type": "Infantry", "x": 500, "y": 500}], 25, 20)
	battle.drill_mode = true
	while battle.current_tick() < 60:
		await get_tree().physics_frame

	Replay.mode = Replay.Mode.RECORD
	var before: int = battle.current_tick()
	battle.seek_to_tick(0)
	assert_eq(battle.current_tick(), before, "outside PLAYBACK, seek_to_tick does nothing")

	_leave_playback(prev_mode)


## Engine.time_scale has no per-unit trace, so it has to ride in the snapshot dict itself
## (unlike everything else this suite round-trips, which lives on a Unit) -- see
## Battle.capture_snapshot's own doc.
func test_capture_and_restore_round_trips_time_scale() -> void:
	var prev_mode := _enter_playback()
	var battle := _spawn_battle([{"team": 0, "type": "Infantry", "x": 500, "y": 500}], 25, 20)
	battle.drill_mode = true
	while battle.current_tick() < 40:
		await get_tree().physics_frame

	Engine.time_scale = 0.25
	var snap: Dictionary = battle.capture_snapshot()
	assert_almost_eq(float(snap["time_scale"]), 0.25, 0.0001,
			"the active time_scale rides in the snapshot")

	Engine.time_scale = 1.0   # diverge before restoring, like this suite's other round-trips
	while battle.current_tick() < 80:
		await get_tree().physics_frame

	battle.restore_snapshot(snap)
	assert_almost_eq(Engine.time_scale, 0.25, 0.0001,
			"restoring a snapshot re-applies the time_scale that was active when it was captured")

	Engine.time_scale = 1.0   # don't leak into a later test
	_leave_playback(prev_mode)


func test_restore_snapshot_defaults_time_scale_to_normal_for_a_pre_field_snapshot() -> void:
	var prev_mode := _enter_playback()
	var battle := _spawn_battle([{"team": 0, "type": "Infantry", "x": 500, "y": 500}], 25, 20)
	battle.drill_mode = true
	while battle.current_tick() < 30:
		await get_tree().physics_frame

	var snap: Dictionary = battle.capture_snapshot()
	snap.erase("time_scale")   # simulate a snapshot captured before this field existed

	Engine.time_scale = 0.5
	battle.restore_snapshot(snap)
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001,
			"a snapshot with no time_scale field restores to the normal default")

	Engine.time_scale = 1.0   # don't leak into a later test
	_leave_playback(prev_mode)
