extends GutTest
## All-teams control: with Battle.all_teams_control set before the node enters the
## tree, both armies still spawn as normal but team 1's AI (_run_enemy_ai) never runs, so a
## tester can drive both sides of a real clash by hand. The main menu's "All-Teams Control"
## button reaches the same flag through AllTeamsControl.pending, since it can't set the
## property directly across a change_scene_to_file scene swap.

const AllTeamsControl = preload("res://scripts/AllTeamsControl.gd")
const ReplayScript = preload("res://scripts/Replay.gd")

# Battle.AI_PERIOD (60): how often _run_enemy_ai would fire, including at tick 0. A handful
# of ticks past that is enough to observe whether it acted.
const AI_PERIOD := 60


func after_each() -> void:
	AllTeamsControl.clear()   # don't leak a pending request into a later test
	Replay.reset()   # don't leak PLAYBACK mode into a later test


func test_all_teams_control_spawns_both_armies_and_skips_enemy_ai() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.all_teams_control = true            # must be set before _ready
	add_child_autofree(battle)
	await _assert_all_teams_control_battle(battle)


func test_all_teams_control_pending_puts_the_battle_in_all_teams_control() -> void:
	AllTeamsControl.pending = true             # set by MainMenu's "All-Teams Control" button
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)                 # _ready reads AllTeamsControl.pending
	assert_true(battle.all_teams_control,
		"AllTeamsControl.pending puts the battle in all-teams control")
	await _assert_all_teams_control_battle(battle)


func test_all_teams_control_pending_does_not_leak_into_replay_playback() -> void:
	# Reproduces the ParadeGround.pending bug class (see test_battle_drill.gd's own regression
	# test): All-Teams Control -> battle starts (AllTeamsControl.pending left set, by design)
	# -> from that battle's menu, Load Replay / Watch Replay / Restart Replay picks a normal
	# replay -> reload_current_scene(). Without the Replay.mode guard, the reloaded
	# Battle._ready() would re-force all-teams control from the stale pending flag and skip
	# team 1's AI, desyncing the replay's recorded (AI-driven) team-1 orders.
	AllTeamsControl.pending = true
	Replay.mode = ReplayScript.Mode.PLAYBACK   # set by Replay.start_playback() before reload
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)                 # _ready reads AllTeamsControl.pending + Replay.mode
	assert_false(battle.all_teams_control,
		"a pending all-teams-control request must not apply during replay playback")
	for _k in range(AI_PERIOD + 5):
		await get_tree().physics_frame
	assert_true(_any_team1_has_an_order(),
		"team 1's AI still runs during replay playback, unaffected by the stale pending flag")


func _assert_all_teams_control_battle(battle: Node) -> void:
	for _k in range(AI_PERIOD + 5):            # spawn + past the first AI_PERIOD boundary
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
	assert_gt(team0, 0, "the player's own army still deploys under all-teams control")
	assert_gt(team1, 0, "the second army still deploys too -- unlike drill mode, this is a real clash")
	assert_false(_any_team1_has_an_order(),
		"no AI directive ever reaches team 1 -- the player commands it directly instead")


## Whether any team-1 unit has been dispatched an order (current_order set, or a live
## target_enemy) -- the immediate, synchronous signal that _run_enemy_ai's UnitLeader.decide
## acted on it (Battle._apply_order_cmd sets both the instant an order is applied). Unlike
## has_move_target, which an ATTACK order deliberately clears until the unit's own pursuit
## logic later starts it closing the distance, these two fire the same tick AI issues the
## order, so a handful of ticks past an AI_PERIOD boundary is enough to observe them.
func _any_team1_has_an_order() -> bool:
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 1 \
				and (unit.current_order != null or unit.target_enemy != null):
			return true
	return false
