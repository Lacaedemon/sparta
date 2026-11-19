extends GutTest
## A rout and its pursuit replay the same after a seek: each routed man and each rider looks round
## on battle ticks (SoldierFlight.tick), which a restore rewinds, not on the physics frame counter,
## which it does not. Snapshot mid-rout, play on, restore, play on again, and every man stands
## where he stood the first time.

const PLAY_ON: int = 37   # not a multiple of the look-round period, so a shifted phase would show


func _men(battle: Node) -> Dictionary:
	var out: Dictionary = {}
	for group in ["units", "routers"]:
		for o in battle.get_tree().get_nodes_in_group(group):
			var u: Unit = o as Unit
			if u != null:
				out[u.uid] = u._sim_soldier_pos.duplicate()
	return out


func _play_to(battle: Node, tick: int) -> void:
	while battle.current_tick() < tick:
		await get_tree().physics_frame


func test_a_rout_replays_the_same_after_a_restore() -> void:
	var prev_mode: int = Replay.mode
	Replay.forced_seed = 424242
	Replay.start_recording()
	Replay.mode = Replay.Mode.PLAYBACK
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 500, "y": 470, "count": 20},
		{"team": 1, "type": "Cavalry", "x": 500, "y": 600, "count": 12, "facing": [0, -1]},
	]
	battle.replay_snapshot_interval_ticks = 1000
	add_child_autofree(battle)
	await _play_to(battle, 10)
	var router: Unit = null
	var rider: Unit = null
	for o in battle.get_tree().get_nodes_in_group("units"):
		var u: Unit = o as Unit
		if u.team == 0:
			router = u
		else:
			rider = u
	router._rout()
	rider.target_enemy = router
	rider.state = Unit.State.MOVING
	await _play_to(battle, 40)
	assert_eq(router.state, Unit.State.ROUTING, "setup: the infantry is routing")
	var snap: Dictionary = battle.capture_snapshot()
	var at: int = battle.current_tick()
	await _play_to(battle, at + PLAY_ON)
	var first: Dictionary = _men(battle)
	assert_true(SoldierPursuitStep.is_pursuing(rider) or not rider._sim_chase_dir.is_empty() \
			or rider.state != Unit.State.MOVING, "setup: the horse rode the rout down")
	battle.restore_snapshot(snap)
	await get_tree().physics_frame   # the engine frame now runs PLAY_ON + 1 ahead of the first pass
	await _play_to(battle, at + PLAY_ON)
	var second: Dictionary = _men(battle)
	assert_eq(second.keys(), first.keys(), "the same units are in play")
	for uid in first:
		assert_eq(second[uid], first[uid], "unit %d's men stand where they stood" % uid)
	Replay.mode = prev_mode
