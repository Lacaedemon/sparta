extends GutTest
## Battle AI phase 2 (docs/battle-ai-design.md), live-battle integration: a subcommander's
## directives (mutual support, line integrity, flank coverage) must reach team-1 units as
## real queue orders through the same single apply site phase 1 already uses -- and the
## same seed must replay to the same directives (the design's determinism contract,
## extended one level up the chain from test_battle_ai_leaders.gd's own phase-1 check).
## Instantiates the real Battle scene and steps it tick by tick, matching that file's
## pattern rather than asserting against an isolated unit.

const FIRST_AI_TICK: int = 60   # Battle.AI_PERIOD -- the first _run_enemy_ai() decision tick

## Empirically verified (tools/demo/dump-state.sh against the showcase seed's default 5v5
## battle, no scenario override -- see .claude/memories/sparta-demos.md's "verify before
## claiming" convention): by this tick, at least one team-1 unit carries a SUPPORT order.
## SUPPORT is an unambiguous phase-2 signature -- phase 1's own repertoire (UnitLeader.gd's
## class doc: face-flank-threat / form-square / call-for-relief / advance-attack) never
## issues one, so seeing it here is direct evidence a Subcommander mutual-support directive
## reached UnitLeader.decide and was actuated as a real order, not just computed and dropped.
const SUPPORT_BY_TICK: int = 600


func after_each() -> void:
	Replay.forced_seed = -1


func _team1_units(battle: Node) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u != null and u.team == 1:
			out.append(u)
	return out


func test_a_subcommander_directive_reaches_a_team1_unit_as_a_support_order() -> void:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)

	var saw_support := false
	while battle.current_tick() <= SUPPORT_BY_TICK and not saw_support:
		await get_tree().physics_frame
		for node in _team1_units(battle):
			var u: Unit = node
			if u.current_order != null and u.current_order.type == Order.Type.SUPPORT:
				saw_support = true
				break

	assert_true(saw_support,
		("by tick %d a subcommander's mutual-support directive has reached some team-1 "
			+ "unit as a real SUPPORT order (docs/battle-ai-design.md phase 2)") % SUPPORT_BY_TICK)


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
