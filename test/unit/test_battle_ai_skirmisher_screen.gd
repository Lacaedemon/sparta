extends GutTest
## The skirmisher-screen directive (docs/deployment-distance-design.md, "Skirmisher
## screening"), live-battle integration: a doctrine that asks for a screen must push its
## light troops out ahead of the heavy line as real queue orders through the same single
## apply site every other AI decision goes through, recall them through the intervals as the
## enemy closes, and reach the same decisions twice on the same forced seed. Instantiates
## the real Battle scene and steps it tick by tick, matching test_battle_ai_subcommanders.gd
## rather than asserting against an isolated unit; the pure-function contract is
## test_skirmisher_screen.gd.

const BattleScript = preload("res://scripts/Battle.gd")

## The doctrine profile that opts into the screen (data/doctrines/screening.json). Every
## shipped doctrine without the flag keeps its prior behaviour, which is why the default
## 5v5 battle cannot demonstrate this and a staged matchup is needed.
const SCREENING_DOCTRINE := "screening"

## Fixed seed rather than a random draw, so a failure here is reproducible instead of a
## fresh battle every run. Consumed by Battle._ready, so it is set before add_child.
const SCENARIO_SEED: int = 24680

## Long enough for the tick-0 AI decision to become a real order and for the unit to have
## visibly moved on it (the order-response delay is 0.2 s, and archers walk at 1.5 m/s, so
## 120 ticks is two seconds of march against a twelve-wu assertion margin).
const MARCH_TICKS: int = 120

## The heavy line's own y in both scenarios below, and the archers' spawn y behind it.
const LINE_Y: float = 700.0
const REAR_Y: float = 780.0


func after_each() -> void:
	Replay.forced_seed = -1


func _team1_units(battle: Node) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u != null and u.team == 1 and battle.is_ancestor_of(u):
			out.append(u)
	return out


func _archers_of(battle: Node) -> Unit:
	for node in _team1_units(battle):
		var u := node as Unit
		if u.is_ranged and not u.is_cavalry:
			return u
	return null


## Two heavy blocks and one archer unit per side, the armies far enough apart that the
## screen's whole opening move is the advance to the contest line. `archer_y` places team
## 1's archers: behind its own line for the advance case, already out in front for the
## recall case.
func _spawn_screen_battle(archer_y: float, enemy_y: float) -> Node:
	Replay.forced_seed = SCENARIO_SEED
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.ai_doctrine = SCREENING_DOCTRINE   # set BEFORE add_child: Battle._ready reads it
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 500, "y": enemy_y},
		{"team": 0, "type": "Infantry", "x": 700, "y": enemy_y},
		{"team": 1, "type": "Infantry", "x": 500, "y": LINE_Y},
		{"team": 1, "type": "Infantry", "x": 700, "y": LINE_Y},
		{"team": 1, "type": "Archers", "x": 600, "y": archer_y},
	]
	add_child_autofree(battle)
	return battle


func test_the_screen_advances_ahead_of_the_heavy_line_as_a_skirmish_stance_order() -> void:
	var battle: Node = _spawn_screen_battle(REAR_Y, 200.0)
	while battle.current_tick() <= MARCH_TICKS:
		await get_tree().physics_frame

	var archers: Unit = _archers_of(battle)
	assert_not_null(archers, "the staged matchup deployed a team-1 archer unit")
	assert_eq(archers.order_mode, BattleScript.OrderMode.SKIRMISH,
		"the SCREEN directive reached the unit as a SKIRMISH-stance order")
	assert_lt(archers.position.y, REAR_Y - 10.0,
		"and it is marching out past its own spawn toward the contest line")


func test_the_screen_is_recalled_behind_the_line_once_the_enemy_closes() -> void:
	# The archers open already out in front, with the enemy inside the withdraw trigger, so
	# the very first AI tick recalls them instead of pushing them further forward.
	var start_y: float = LINE_Y - SkirmisherScreen.SCREEN_LEAD_DISTANCE
	var battle: Node = _spawn_screen_battle(
		start_y, start_y - (SkirmisherScreen.WITHDRAW_TRIGGER_RANGE - 20.0))
	while battle.current_tick() <= MARCH_TICKS:
		await get_tree().physics_frame

	var archers: Unit = _archers_of(battle)
	assert_not_null(archers)
	assert_gt(archers.position.y, start_y + 5.0,
		"falling back toward its own line rather than standing to be caught")
	assert_eq(archers.order_mode, BattleScript.OrderMode.NORMAL,
		"the recall marches in the default stance, so kiting cannot hold the withdrawal up")


func test_the_screen_replays_identically_on_the_same_seed() -> void:
	# Two independent live runs of the same seed must reach the same AI order on the same
	# unit at the same tick -- including the screen's own directive-driven orders. Mirrors
	# test_battle_ai_subcommanders.gd's determinism check, on the screening doctrine.
	var first: Node = _spawn_screen_battle(REAR_Y, 200.0)
	while first.current_tick() <= MARCH_TICKS:
		await get_tree().physics_frame
	var snapshot_a: Dictionary = {}
	for node in _team1_units(first):
		snapshot_a[(node as Unit).uid] = _order_signature(node as Unit)
	first.free()
	await get_tree().physics_frame

	var second: Node = _spawn_screen_battle(REAR_Y, 200.0)
	while second.current_tick() <= MARCH_TICKS:
		await get_tree().physics_frame
	var snapshot_b: Dictionary = {}
	for node in _team1_units(second):
		snapshot_b[(node as Unit).uid] = _order_signature(node as Unit)

	assert_eq(snapshot_a, snapshot_b,
		"same forced seed -> identical screen orders per unit at the same tick")


func _order_signature(u: Unit) -> String:
	if u.current_order == null:
		return "NONE:%d" % u.order_mode
	return "%s:%d:%d" % [u.current_order.describe(), u.current_order.target_uid, u.order_mode]
