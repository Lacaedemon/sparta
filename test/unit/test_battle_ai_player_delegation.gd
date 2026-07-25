extends GutTest
## Battle AI phase 4 (docs/battle-ai-design.md), live-battle integration: delegating a team-0
## unit group must produce real queue orders through the SAME single apply site
## (Battle._apply_order_cmd) team 1's own AI already uses -- structurally indistinguishable
## from a hand-issued order in the transcript -- a manual player order must always override a
## delegated unit's subcommander directive, period rank names must render from the doctrine
## profile, and the same seed must replay to the same delegated-group decisions. Instantiates
## the real Battle scene and steps it tick by tick, matching test_battle_ai_general.gd's own
## pattern rather than asserting against an isolated unit.

const AI_PERIOD: int = 60   # Battle.AI_PERIOD -- the first AI decision (either team) is at tick 0.
const DELEGATE_GROUP: int = 5


func after_each() -> void:
	Replay.forced_seed = -1


func _team0_units(battle: Node) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u != null and u.team == 0:
			out.append(u)
	return out


## Two team-0 units close together (so Subcommander sees a real 2-unit group) and one team-1
## enemy far off to the north -- close enough that UnitLeader's advance/attack fallback picks
## it as the nearest enemy (so a delegated unit visibly gets a MOVE/ATTACK order), far enough
## that the two sides aren't already in contact at tick 0 (so the very first AI tick's
## decision is legible as "just started advancing", not "already fighting").
func _delegation_scenario() -> Array:
	return [
		{"team": 0, "type": "Infantry", "x": 500, "y": 700},
		{"team": 0, "type": "Infantry", "x": 600, "y": 700},
		{"team": 1, "type": "Infantry", "x": 550, "y": 300},
	]


func _spawn_battle() -> Node:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.all_teams_control = true   # team 1 needs a real body on the field, undirected by its
	                                  # own AI is irrelevant here -- this just keeps _run_enemy_ai
	                                  # from also moving it, so only the delegated team-0 group's
	                                  # own decisions are under test.
	battle.scenario = _delegation_scenario()
	add_child_autofree(battle)
	return battle


func _order_signature(u: Unit) -> String:
	if u.current_order == null:
		return "NONE"
	return "%s:%d" % [u.current_order.describe(), u.current_order.target_uid]


# --- delegation actuates through the same apply site as a hand-issued order -----------------

func test_a_delegated_unit_gets_a_real_queue_order_from_the_ai_pipeline() -> void:
	var battle: Node = _spawn_battle()
	var team0: Array = _team0_units(battle)
	var uids: Array = []
	for u in team0:
		uids.append(u.uid)
	battle.enqueue_delegation(uids, DELEGATE_GROUP)
	for u in team0:
		assert_true(u.is_delegated())
		assert_eq(u.player_group_id, DELEGATE_GROUP)

	while battle.current_tick() < 1:
		await get_tree().physics_frame

	for u in team0:
		assert_ne(_order_signature(u), "NONE",
			"a delegated unit gets a real order from the AI pipeline at the first AI tick, " +
			"the exact same shape (Order via _apply_order_cmd) a hand-issued order would produce")


func test_a_non_delegated_unit_never_receives_an_ai_order() -> void:
	var battle: Node = _spawn_battle()
	var team0: Array = _team0_units(battle)
	# Deliberately never delegate anything.
	while battle.current_tick() < 1:
		await get_tree().physics_frame

	for u in team0:
		assert_eq(_order_signature(u), "NONE",
			"an ordinary, non-delegated player unit is untouched by any AI decision")


# --- take manual control back at any time ----------------------------------------------------

func test_a_manual_order_to_a_delegated_unit_immediately_revokes_delegation() -> void:
	var battle: Node = _spawn_battle()
	var team0: Array = _team0_units(battle)
	var u: Unit = team0[0]
	battle.enqueue_delegation([u.uid], DELEGATE_GROUP)
	assert_true(u.is_delegated())

	# A plain move order -- applied live/synchronously (Battle.enqueue_order), no tick needed.
	battle.enqueue_order([u.uid], Vector2(500, 650), -1)
	assert_false(u.is_delegated(),
		"the design doc's own phase-4 contract: a manual player order to a delegated unit " +
		"always overrides the subcommander's directive")
	assert_eq(u.subcommander_rank_title, "", "the resolved rank title is cleared alongside it")


func test_ctrl_shift_digit_toggles_delegation_off_when_already_delegated_to_that_group() -> void:
	# Mirrors SelectionManager._toggle_delegation's own toggle-back semantics directly through
	# Battle.enqueue_delegation (the actuation it calls), since a live keypress needs a real
	# input event and selection state this file doesn't otherwise exercise.
	var battle: Node = _spawn_battle()
	var team0: Array = _team0_units(battle)
	var u: Unit = team0[0]
	battle.enqueue_delegation([u.uid], DELEGATE_GROUP)
	assert_true(u.is_delegated())
	battle.enqueue_delegation([u.uid], Unit.UNDELEGATED)
	assert_false(u.is_delegated())


# --- period rank names render from the doctrine profile --------------------------------------

func test_delegating_a_unit_resolves_its_subcommander_rank_from_the_player_doctrine() -> void:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.all_teams_control = true
	battle.scenario = _delegation_scenario()
	battle.player_doctrine = "aggressive"
	add_child_autofree(battle)

	var team0: Array = _team0_units(battle)
	var u: Unit = team0[0]
	battle.enqueue_delegation([u.uid], DELEGATE_GROUP)
	var expected: String = DoctrineRegistry.doctrine("aggressive")["subcommander_rank"]
	assert_eq(u.subcommander_rank_title, expected)
	assert_eq(u.subcommander_rank_title, "Tribune")


# --- replay determinism -----------------------------------------------------------------------

func test_delegated_group_orders_replay_identically_on_the_same_seed() -> void:
	# Two independent live runs, same seed, same scenario, same delegation toggle applied at
	# tick 0 -- must reach the same AI order on the same delegated unit at the same tick,
	# mirroring test_battle_ai_general.gd's own test_ai_decisions_replay_identically_on_the_
	# same_seed. The delegation toggle itself is recorded (Battle.enqueue_delegation) and
	# replayed like any other player order; the AI's resulting orders are re-derived, not
	# recorded, exactly like team 1's own AI.
	var first: Node = _spawn_battle()
	var first_team0: Array = _team0_units(first)
	var first_uids: Array = []
	for u in first_team0:
		first_uids.append(u.uid)
	first.enqueue_delegation(first_uids, DELEGATE_GROUP)
	while first.current_tick() <= AI_PERIOD:
		await get_tree().physics_frame
	var snapshot_a: Dictionary = {}
	for u in first_team0:
		snapshot_a[u.uid] = _order_signature(u)
	first.free()
	await get_tree().physics_frame

	var second: Node = _spawn_battle()
	var second_team0: Array = _team0_units(second)
	var second_uids: Array = []
	for u in second_team0:
		second_uids.append(u.uid)
	second.enqueue_delegation(second_uids, DELEGATE_GROUP)
	while second.current_tick() <= AI_PERIOD:
		await get_tree().physics_frame
	var snapshot_b: Dictionary = {}
	for u in second_team0:
		snapshot_b[u.uid] = _order_signature(u)

	assert_eq(snapshot_a, snapshot_b,
		"same seed + same delegation toggle -> identical AI order per delegated unit at the " +
		"same tick")
