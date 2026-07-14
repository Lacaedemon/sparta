extends GutTest
## Drill / solo mode (#390): with Battle.drill_mode set before the node enters the tree, only
## the player army (team 0) deploys and the battle never auto-ends on "no enemies" — so a unit
## can rehearse a maneuver in isolation (what the maneuver demos record). The main menu's
## "Parade Ground" button reaches the same drill_mode through ParadeGround.pending, since
## it can't set the property directly across a change_scene_to_file scene swap.

const ParadeGround = preload("res://scripts/ParadeGround.gd")
const ReplayScript = preload("res://scripts/Replay.gd")


func after_each() -> void:
	ParadeGround.clear()   # don't leak a pending request into a later test
	Replay.reset()   # don't leak PLAYBACK mode into a later test


func test_drill_mode_spawns_only_team0_and_never_auto_ends() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true                   # must be set before _ready
	add_child_autofree(battle)
	await _assert_drill_battle(battle)


func test_parade_ground_pending_puts_the_battle_in_drill_mode() -> void:
	ParadeGround.pending = true                 # set by MainMenu's "Parade Ground" button
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)                  # _ready reads ParadeGround.pending
	assert_true(battle.drill_mode, "ParadeGround.pending puts the battle in drill mode")
	await _assert_drill_battle(battle)


func test_parade_ground_pending_does_not_leak_into_replay_playback() -> void:
	# Reproduces: Parade Ground -> drill battle starts (ParadeGround.pending left set, by
	# design) -> from that battle's menu, Load Replay / Watch Replay / Restart Replay picks
	# a normal two-army replay -> reload_current_scene(). Without the Replay.mode guard, the
	# reloaded Battle._ready() would re-force drill_mode from the stale pending flag and skip
	# spawning team 1, even though the replay's recorded orders reference team-1 unit uids.
	ParadeGround.pending = true
	Replay.mode = ReplayScript.Mode.PLAYBACK   # set by Replay.start_playback() before reload
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)                  # _ready reads ParadeGround.pending + Replay.mode
	assert_false(battle.drill_mode,
			"a pending parade-ground request must not force drill mode during replay playback")
	for _k in range(5):
		await get_tree().physics_frame
	var team1 := 0
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 1:
			team1 += 1
	assert_gt(team1, 0, "team 1 still spawns so the replay's recorded orders resolve")


func _assert_drill_battle(battle: Node) -> void:
	for _k in range(40):                       # spawn + a stretch of ticks with no opponent
		await get_tree().physics_frame
	var team0 := 0
	var team1 := 0
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit == null:
			continue
		if unit.team == 0:
			team0 += 1
		elif unit.team == 1:
			team1 += 1
	assert_gt(team0, 0, "the player army still deploys in drill mode")
	assert_eq(team1, 0, "no enemy army deploys in drill mode")
	assert_false(battle._ended,
		"drill mode does not auto-win when there are no enemies — the rehearsal runs on")
