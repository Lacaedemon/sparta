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

## Team 0's own line in the recall scenario. Deliberately NOT inside the withdraw trigger at
## tick 0: the archers spawn 316 wu from the nearest enemy (100 wu across, 300 wu up), well
## outside the 120-wu trigger, so the first AI tick issues a SCREEN and the recall has a
## SKIRMISH stance to reset later. Near enough that the two lines close inside the trigger
## once the screen has marched out to the contest line.
const RECALL_ENEMY_Y: float = 480.0

## Tick cap for the recall run rather than a fixed length: the screen has to march the 240 wu
## out to the contest line, and the enemy has to close on it, before there is anything to
## recall. The loop stops the tick the recall is observed, so a healthy run ends well short
## of this.
const RECALL_TICK_CAP: int = 600

## Ticks to keep stepping after the recall is issued, so the fall-back shows up as ground
## actually given up rather than as a fresh order sitting in the response delay.
const FALLBACK_TICKS: int = 90


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
	# Staged as the whole sequence, not as a recall in isolation: the archers spawn behind
	# their own line, march out under a SKIRMISH-stance SCREEN order, and only then does the
	# advancing enemy come inside the withdraw trigger. Asserting the recall against a unit
	# that never received a screen order would assert nothing -- Unit.order_mode already
	# spawns NORMAL, so "the recall resets the stance" is only a claim once the stance was
	# something else first.
	var battle: Node = _spawn_screen_battle(REAR_Y, RECALL_ENEMY_Y)
	var archers: Unit = _archers_of(battle)
	assert_not_null(archers, "the staged matchup deployed a team-1 archer unit")
	if archers == null:
		return

	var saw_screen_order: bool = false
	var saw_recall: bool = false
	var recall_y: float = 0.0
	while battle.current_tick() <= RECALL_TICK_CAP:
		await get_tree().physics_frame
		if archers.order_mode == BattleScript.OrderMode.SKIRMISH:
			saw_screen_order = true
			continue
		# The recall, and the only thing that looks like it: the default stance again, and a
		# march on a point BEHIND the unit's own heavy line (the rally, one rally depth past
		# it) rather than on the contest line ahead of it.
		if saw_screen_order and archers.has_move_target and archers.move_target.y > LINE_Y:
			saw_recall = true
			recall_y = archers.position.y
			break

	assert_true(saw_screen_order,
		"the screen went out under a SKIRMISH-stance order before anything recalled it")
	assert_true(saw_recall,
		"and the closing enemy recalled it to the rally, in the default stance not SKIRMISH")
	var until: int = battle.current_tick() + FALLBACK_TICKS
	while battle.current_tick() <= until:
		await get_tree().physics_frame
	assert_gt(archers.position.y, recall_y + 5.0,
		"falling back toward its own line rather than standing to be caught")


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
