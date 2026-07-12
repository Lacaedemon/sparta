extends GutTest
## Battle AI phase 2 (docs/battle-ai-design.md), live-battle integration: a subcommander's
## directives (mutual support, line integrity, flank coverage) must reach team-1 units as
## real queue orders through the same single apply site phase 1 already uses -- and the
## same seed must replay to the same directives (the design's determinism contract,
## extended one level up the chain from test_battle_ai_leaders.gd's own phase-1 check).
## Instantiates the real Battle scene and steps it tick by tick, matching that file's
## pattern rather than asserting against an isolated unit.

## Battle.AI_PERIOD -- _run_enemy_ai() fires on every tick where `tick % AI_PERIOD == 0`,
## which includes tick 0 itself: the very FIRST AI decision happens at tick 0, before any
## unit's own _physics_process has run even once (Battle._physics_process runs _run_enemy_ai()
## ahead of the Units' own _physics_process -- see _spawn_support_scenario's comment below for
## why that matters). AI_PERIOD is the spacing between decisions, not an offset to the first one.
const AI_PERIOD: int = 60

## Empirically verified (tools/demo/dump-state.sh against the showcase seed's default 5v5
## battle, no scenario override -- see .claude/memories/sparta-demos.md's "verify before
## claiming" convention): the *replay-determinism* check below covers this many ticks of the
## default battle. Left wide so the determinism comparison is meaningful, independent of
## whether any SUPPORT directive happens to fire along the way.
const SUPPORT_BY_TICK: int = 600

## How long to give the dedicated SUPPORT-order scenario below: empirically verified (see
## _spawn_support_scenario's comment) to reach a real SUPPORT order by tick 120 -- two AI_PERIOD
## decisions in, with margin.
const SUPPORT_SCENARIO_TICK_WINDOW: int = 120


func after_each() -> void:
	Replay.forced_seed = -1


func _team1_units(battle: Node) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u != null and u.team == 1:
			out.append(u)
	return out


## Staged, not the default 5v5 line spawn: UnitLeader.decide's own "a subcommander directive
## must never interrupt a unit already chasing a live target" guard (docs/battle-ai-design.md
## phase 2's own priority rule) means the default matchup can no longer demonstrate a
## mutual-support directive reaching a real order -- every team-1 unit picks up a live ATTACK
## order against a real enemy on the very first AI tick, so none of them is ever "available"
## for Subcommander to redirect. That first AI tick is tick 0 itself, not FIRST_AI_TICK's
## naming suggests: Battle._physics_process runs _run_enemy_ai() (tick % AI_PERIOD == 0, true
## at tick 0) BEFORE the Units' own _physics_process, so no unit can already be FIGHTING via
## reactive contact by the time the very first AI decision is made -- a unit spawned already
## overlapping its enemy still gets an explicit ATTACK order at tick 0, same as any other
## idle unit. The only way a team-1 unit stops being "chasing a live target" after that is
## for its OWN target to die. So this scenario pairs `ward` against a full-strength enemy it
## fights for a long time, and `ally` against a token 1-soldier enemy that dies almost
## immediately -- freeing `ally` (UnitLeader.is_chasing_live_target reads false once its
## target is dead) while `ward` is still fighting, so the next AI tick's mutual-support
## directive can claim it. Empirically verified via tools/demo/dump-state.sh: `ally`'s
## current_order reads SUPPORT by tick 120 (see demos/inputs/subcommander-mutual-support.json,
## the website demo built on this same scenario shape).
func _spawn_support_scenario() -> Node:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 750, "y": 480},               # ward's foe
		{"team": 0, "type": "Infantry", "x": 900, "y": 480, "count": 1},   # ally's foe: dies fast
		{"team": 1, "type": "Infantry", "x": 750, "y": 550},   # `ward`: stays locked in a fight
		{"team": 1, "type": "Cavalry", "x": 900, "y": 550},    # `ally`: freed once its foe dies
	]
	add_child_autofree(battle)
	return battle


func test_a_subcommander_directive_reaches_a_team1_unit_as_a_support_order() -> void:
	var battle: Node = _spawn_support_scenario()

	var saw_support := false
	while battle.current_tick() <= SUPPORT_SCENARIO_TICK_WINDOW and not saw_support:
		await get_tree().physics_frame
		for node in _team1_units(battle):
			var u: Unit = node
			if u.current_order != null and u.current_order.type == Order.Type.SUPPORT:
				saw_support = true
				break

	assert_true(saw_support,
		("by tick %d a subcommander's mutual-support directive has reached some team-1 "
			+ "unit as a real SUPPORT order (docs/battle-ai-design.md phase 2)")
			% SUPPORT_SCENARIO_TICK_WINDOW)


func test_subcommander_directives_replay_identically_on_the_same_seed() -> void:
	# Two independent live runs of the same seed must reach the same AI order on the same
	# unit at the same tick -- including any order shaped by a subcommander directive, not
	# just phase 1's own repertoire. Compares current_order.describe() + target_uid per
	# team-1 uid, mirroring test_battle_ai_leaders.gd's own determinism check.
	Replay.forced_seed = 12345
	var first: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(first)
	while first.current_tick() <= SUPPORT_BY_TICK:
		await get_tree().physics_frame
	var snapshot_a: Dictionary = {}
	for node in _team1_units(first):
		var u: Unit = node
		snapshot_a[u.uid] = _order_signature(u)
	first.free()
	await get_tree().physics_frame

	Replay.forced_seed = 12345
	var second: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(second)
	while second.current_tick() <= SUPPORT_BY_TICK:
		await get_tree().physics_frame
	var snapshot_b: Dictionary = {}
	for node in _team1_units(second):
		var u: Unit = node
		snapshot_b[u.uid] = _order_signature(u)

	assert_eq(snapshot_a, snapshot_b,
		("same seed -> identical AI order (subcommander-directed or not) per unit at the "
			+ "same tick (determinism contract)"))


func _order_signature(u: Unit) -> String:
	if u.current_order == null:
		return "NONE"
	var target: int = u.current_order.target_uid
	return "%s:%d" % [u.current_order.describe(), target]
