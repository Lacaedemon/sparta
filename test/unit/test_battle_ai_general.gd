extends GutTest
## Battle AI phase 3 (docs/battle-ai-design.md), live-battle integration: the general's plan/
## group/reserve decisions must reach team-1 units as real queue orders through the same
## single apply site phases 1-2 already use -- and the same seed must replay to the same
## decisions (the design's determinism contract, extended one level up the chain from
## test_battle_ai_subcommanders.gd's own phase-2 check). Also the design doc's own headline
## phase-3 acceptance criterion: two different doctrine profiles produce visibly different
## army behavior from the same battle seed. Instantiates the real Battle scene and steps it
## tick by tick, matching that file's pattern rather than asserting against an isolated unit.

const AI_PERIOD: int = 60   # Battle.AI_PERIOD -- the first _run_enemy_ai() decision is at tick 0.

## Empirically verified (tools/demo/dump-state.sh against the showcase seed's default 5v5
## battle, no scenario override): the default 5v5 matchup is a 1:1 unit-count ratio on both
## sides, which is BELOW both shipped doctrines' envelop_ratio_threshold (aggressive 1.2,
## cautious 1.6) -- deliberately, so a symmetric default battle reproduces phase 2's own single-
## group behavior under EITHER doctrine (no regression for the phase-2 tests that predate
## doctrines and never set ai_doctrine). The doctrines still diverge visibly on a symmetric
## matchup via their reserve_fraction (aggressive holds back int(5*0.1) = 0; cautious holds back
## int(5*0.4) = 2) -- see test_two_doctrines_produce_visibly_different_army_behavior below.
## Envelop itself is demonstrated separately, in a scenario where team 1 genuinely outnumbers
## team 0 (see _outnumbering_scenario), which is what actually earns an envelop plan under
## either doctrine's threshold.


func after_each() -> void:
	Replay.forced_seed = -1


func _team1_units(battle: Node) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u != null and u.team == 1:
			out.append(u)
	return out


func _spawn_battle(doctrine_id: String) -> Node:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.ai_doctrine = doctrine_id   # set BEFORE add_child so Battle._ready/tick 0 reads it
	add_child_autofree(battle)
	return battle


## Team 1 (4 units) genuinely outnumbers team 0 (2 units) 2:1 -- enough to clear BOTH shipped
## doctrines' envelop_ratio_threshold once reserves are excluded from the count (aggressive:
## 4 active / 2 enemy = 2.0 >= 1.2; cautious: int(4*0.4)=1 held back, 3 active / 2 enemy = 1.5,
## still >= 1.6? No -- 1.5 < 1.6, so cautious stays on advance_line even here, which is itself
## part of the point: the same numeric edge reads as "envelop" under one doctrine and
## "advance_line, reserve one unit" under the other. Symmetric team-1 spread (x centred on 600)
## so the axis to the enemy centroid (also centred on x=600) is a clean vertical line and the
## envelop split bisects left/right without a degenerate empty wing.
func _outnumbering_scenario() -> Array:
	return [
		{"team": 0, "type": "Infantry", "x": 500, "y": 300},
		{"team": 0, "type": "Infantry", "x": 700, "y": 300},
		{"team": 1, "type": "Infantry", "x": 450, "y": 700},
		{"team": 1, "type": "Infantry", "x": 550, "y": 700},
		{"team": 1, "type": "Infantry", "x": 650, "y": 700},
		{"team": 1, "type": "Infantry", "x": 750, "y": 700},
	]


func _spawn_scenario_battle(doctrine_id: String, scenario: Array) -> Node:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.ai_doctrine = doctrine_id
	battle.scenario = scenario
	add_child_autofree(battle)
	return battle


func test_aggressive_doctrine_picks_envelop_when_outnumbering_at_the_first_ai_tick() -> void:
	var battle: Node = _spawn_scenario_battle("aggressive", _outnumbering_scenario())
	await get_tree().physics_frame   # tick 0's _run_enemy_ai already ran before this frame yields

	var team1: Array = _team1_units(battle)
	var doctrine: Dictionary = DoctrineRegistry.doctrine("aggressive")
	var decision: Dictionary = General.decide_army(
		team1, get_tree().get_nodes_in_group("units"), doctrine)
	assert_eq(decision["plan"], General.PLAN_ENVELOP,
		"4 active vs 2 enemy (ratio 2.0) clears aggressive's 1.2 envelop threshold")
	assert_eq(decision["groups"].size(), 2, "the aggressive general splits into two wings")
	assert_eq(decision["reserve_units"], [], "aggressive holds nothing back (0.1 * 4 rounds to 0)")


func test_cautious_doctrine_stays_on_advance_line_at_the_same_numeric_edge() -> void:
	# Same outnumbering scenario as the aggressive test above, same seed -- only the doctrine
	# differs. Cautious's own reserve_fraction trims the active count before the ratio is even
	# computed (3 active vs 2 enemy = 1.5), which still misses its own higher 1.6 threshold --
	# a direct illustration of "two doctrines read the identical battle differently."
	var battle: Node = _spawn_scenario_battle("cautious", _outnumbering_scenario())
	await get_tree().physics_frame

	var team1: Array = _team1_units(battle)
	var doctrine: Dictionary = DoctrineRegistry.doctrine("cautious")
	var decision: Dictionary = General.decide_army(
		team1, get_tree().get_nodes_in_group("units"), doctrine)
	assert_eq(decision["plan"], General.PLAN_ADVANCE_LINE,
		"3 active vs 2 enemy (ratio 1.5) misses cautious's 1.6 envelop threshold")
	assert_eq(decision["groups"].size(), 1)
	assert_eq(decision["reserve_units"].size(), 1, "cautious holds 1 of 4 units back (0.4 * 4)")


func test_cautious_doctrine_picks_advance_line_and_holds_reserves_at_the_first_ai_tick() -> void:
	var battle: Node = _spawn_battle("cautious")
	await get_tree().physics_frame

	var team1: Array = _team1_units(battle)
	var doctrine: Dictionary = DoctrineRegistry.doctrine("cautious")
	var decision: Dictionary = General.decide_army(
		team1, get_tree().get_nodes_in_group("units"), doctrine)
	assert_eq(decision["plan"], General.PLAN_ADVANCE_LINE,
		"3 active vs 5 enemy (ratio 0.6) misses cautious's 1.6 envelop threshold")
	assert_eq(decision["groups"].size(), 1, "the cautious general keeps a single line")
	assert_eq(decision["reserve_units"].size(), 2, "cautious holds 2 of 5 units back (0.4 * 5)")


func test_two_doctrines_produce_visibly_different_army_behavior_from_the_same_seed() -> void:
	# The design doc's own headline phase-3 acceptance criterion, checked directly against
	# live-battle transcript state rather than just the pure General.decide_army() output
	# the two tests above already cover: an aggressive general's team-1 units carry MOVE
	# orders toward two different (wing) destinations at the first AI tick, while a cautious
	# general's team-1 units include some that get NO order at all (held in reserve).
	var aggressive: Node = _spawn_battle("aggressive")
	await get_tree().physics_frame
	var aggressive_orders: Dictionary = {}
	for u in _team1_units(aggressive):
		aggressive_orders[u.uid] = _order_signature(u)
	aggressive.free()
	await get_tree().physics_frame

	var cautious: Node = _spawn_battle("cautious")
	await get_tree().physics_frame
	var cautious_orders: Dictionary = {}
	for u in _team1_units(cautious):
		cautious_orders[u.uid] = _order_signature(u)

	assert_ne(aggressive_orders, cautious_orders,
		"the same seed produces different per-unit AI orders under the two doctrines")
	# Concretely: the cautious general leaves some team-1 units with no order at all this
	# tick (held in reserve at their own spawn point), which the aggressive general -- with
	# no reserve to hold back -- never does.
	var cautious_has_idle_unit := false
	for uid in cautious_orders:
		if cautious_orders[uid] == "NONE":
			cautious_has_idle_unit = true
	var aggressive_has_idle_unit := false
	for uid in aggressive_orders:
		if aggressive_orders[uid] == "NONE":
			aggressive_has_idle_unit = true
	assert_true(cautious_has_idle_unit, "cautious holds at least one unit back with no order")
	assert_false(aggressive_has_idle_unit, "aggressive commits every unit from tick 0")


func test_ai_decisions_replay_identically_on_the_same_seed() -> void:
	# Two independent live runs of the same seed (and the same doctrine) must reach the same
	# AI order on the same unit at the same tick -- including any order shaped by the
	# general's plan/group/reserve decisions, not just phases 1-2's own repertoire.
	var first: Node = _spawn_battle("aggressive")
	while first.current_tick() <= AI_PERIOD:
		await get_tree().physics_frame
	var snapshot_a: Dictionary = {}
	for u in _team1_units(first):
		snapshot_a[u.uid] = _order_signature(u)
	first.free()
	await get_tree().physics_frame

	var second: Node = _spawn_battle("aggressive")
	while second.current_tick() <= AI_PERIOD:
		await get_tree().physics_frame
	var snapshot_b: Dictionary = {}
	for u in _team1_units(second):
		snapshot_b[u.uid] = _order_signature(u)

	assert_eq(snapshot_a, snapshot_b,
		"same seed + same doctrine -> identical AI order per unit at the same tick")


func _order_signature(u: Unit) -> String:
	if u.current_order == null:
		return "NONE"
	var target: int = u.current_order.target_uid
	return "%s:%d" % [u.current_order.describe(), target]
