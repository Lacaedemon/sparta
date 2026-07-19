extends GutTest
## walk_advance/reform_before_move are persistent per-unit fields, changed only by
## an explicit player toggle or a replayed toggle event. A mid-battle toggle
## (SelectionManager.set_selected_walk_advance/set_selected_reform_before_move ->
## Battle.enqueue_unit_settings) must ride the recorded order stream -- not just take effect
## live -- or a saved-and-replayed recording would silently diverge from what the live
## session actually did. Live-record a toggle mid-battle, save, then replay the saved file
## from a fresh Battle instance and confirm the unit ends up with the same setting.

const BattleScript = preload("res://scripts/Battle.gd")

const SPAWN := Vector2(500, 430)


func after_each() -> void:
	Replay.reset()
	Replay.forced_seed = -1


func _spawn(team_scenario: Array) -> Node:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true   # set before add_child so Battle._ready reads it
	battle.scenario = team_scenario
	add_child_autofree(battle)
	return battle


func _lone_unit() -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		if node is Unit:
			return node
	return null


func test_a_mid_battle_walk_advance_toggle_replays_identically() -> void:
	# Infantry defaults walk_advance off (the per-type spawn default), so toggling it ON
	# mid-battle is a real, provable state change -- not just the spawn default holding.
	var scenario := [
		{"team": 0, "type": "Infantry", "x": SPAWN.x, "y": SPAWN.y, "count": 20, "facing": [0, 1]},
	]

	# --- Live recording ------------------------------------------------
	Replay.forced_seed = 98765
	var live: Node = _spawn(scenario)
	var u: Unit = _lone_unit()
	assert_not_null(u, "the scenario spawned the lone unit")
	if u == null:
		return
	assert_false(u.walk_advance, "sanity: Infantry defaults walk_advance off")

	for _k in range(10):
		await get_tree().physics_frame
	live.enqueue_unit_settings([u.uid], BattleScript.UnitSettingToggle.ON,
			BattleScript.UnitSettingToggle.LEAVE)
	assert_true(u.walk_advance, "the toggle applies live immediately")
	await get_tree().physics_frame   # the tick drain records the order (applied_live skips a re-apply)

	for _k in range(10):
		await get_tree().physics_frame
	var live_final_tick: int = live.current_tick()
	var live_walk_advance: bool = u.walk_advance

	var path: String = Replay.save("Test", live_final_tick)
	assert_ne(path, "", "the recording saves")
	live.free()
	await get_tree().physics_frame

	# --- Playback --------------------------------------------------------
	assert_true(Replay.start_playback(path), "the saved replay loads")
	var replayed: Node = _spawn(scenario)
	var ru: Unit = _lone_unit()
	assert_not_null(ru, "the replayed scenario spawns the same lone unit")
	if ru == null:
		return
	assert_false(ru.walk_advance, "sanity: the replayed unit starts at the same spawn default")

	while replayed.current_tick() < live_final_tick:
		await get_tree().physics_frame

	assert_eq(ru.walk_advance, live_walk_advance,
		"the mid-battle toggle reproduces identically on replay, not just the spawn default")


func test_a_mid_battle_reform_before_move_toggle_replays_identically() -> void:
	# Spearmen default reform_before_move ON, so toggling it OFF mid-battle is the provable
	# state change here.
	var scenario := [
		{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y, "count": 20, "facing": [0, 1]},
	]

	Replay.forced_seed = 24681
	var live: Node = _spawn(scenario)
	var u: Unit = _lone_unit()
	assert_not_null(u, "the scenario spawned the lone unit")
	if u == null:
		return
	assert_true(u.reform_before_move, "sanity: Spearmen default reform_before_move on")

	for _k in range(10):
		await get_tree().physics_frame
	live.enqueue_unit_settings([u.uid], BattleScript.UnitSettingToggle.LEAVE,
			BattleScript.UnitSettingToggle.OFF)
	assert_false(u.reform_before_move, "the toggle applies live immediately")
	await get_tree().physics_frame

	for _k in range(10):
		await get_tree().physics_frame
	var live_final_tick: int = live.current_tick()
	var live_reform: bool = u.reform_before_move

	var path: String = Replay.save("Test", live_final_tick)
	assert_ne(path, "", "the recording saves")
	live.free()
	await get_tree().physics_frame

	assert_true(Replay.start_playback(path), "the saved replay loads")
	var replayed: Node = _spawn(scenario)
	var ru: Unit = _lone_unit()
	assert_not_null(ru, "the replayed scenario spawns the same lone unit")
	if ru == null:
		return
	assert_true(ru.reform_before_move, "sanity: the replayed unit starts at the same spawn default")

	while replayed.current_tick() < live_final_tick:
		await get_tree().physics_frame

	assert_eq(ru.reform_before_move, live_reform,
		"the mid-battle toggle reproduces identically on replay, not just the spawn default")
