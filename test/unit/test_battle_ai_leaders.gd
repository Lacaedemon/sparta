extends GutTest
## Battle AI phase 1 (docs/battle-ai-design.md), live-battle integration: the enemy
## AI's decisions must arrive as real queue orders on a live-battle unit, not the old
## direct target_enemy write with no order behind it -- and the same seed must replay to
## the same AI orders (the design's determinism contract). Instantiates the real Battle
## scene and steps it tick by tick, matching the pattern in test_quarter_turn_battle.gd /
## test_collision_knockback_battle.gd rather than asserting against an isolated unit.

const FIRST_AI_TICK: int = 60   # Battle.AI_PERIOD -- the first _run_enemy_ai() decision tick


func after_each() -> void:
	Replay.forced_seed = -1


func _team1_units(battle: Node) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u != null and u.team == 1:
			out.append(u)
	return out


func test_enemy_units_carry_a_real_order_after_the_first_ai_tick() -> void:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)

	while battle.current_tick() <= FIRST_AI_TICK:
		await get_tree().physics_frame

	var team1: Array = _team1_units(battle)
	assert_false(team1.is_empty(), "the showcase seed spawns an enemy line")
	for node in team1:
		var u: Unit = node
		if u.state == Unit.State.DEAD or u.state == Unit.State.ROUTING:
			continue
		assert_not_null(u.current_order,
			"enemy unit %d has a queue-visible order after the AI's first decision tick" % u.uid)
		if u.current_order != null:
			assert_true(
				u.current_order.type == Order.Type.ATTACK or u.current_order.type == Order.Type.MOVE
				or u.current_order.type == Order.Type.FORMATION or u.current_order.type == Order.Type.RELIEF,
				"AI order is one of the tactical repertoire's types, got %s" % u.current_order.describe())


func test_ai_decisions_replay_identically_on_the_same_seed() -> void:
	# Two independent live runs of the same seed must reach the same AI order on the
	# same unit at the same tick -- the design's "replays re-derive AI decisions"
	# invariant. Compares current_order.describe() + target_uid per team-1 uid.
	Replay.forced_seed = 12345
	var first: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(first)
	while first.current_tick() <= FIRST_AI_TICK:
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
	while second.current_tick() <= FIRST_AI_TICK:
		await get_tree().physics_frame
	var snapshot_b: Dictionary = {}
	for node in _team1_units(second):
		var u: Unit = node
		snapshot_b[u.uid] = _order_signature(u)

	assert_eq(snapshot_a, snapshot_b,
		"same seed -> identical AI order per unit at the same tick (determinism contract)")


func _order_signature(u: Unit) -> String:
	if u.current_order == null:
		return "NONE"
	var target: int = u.current_order.target_uid
	return "%s:%d" % [u.current_order.describe(), target]
