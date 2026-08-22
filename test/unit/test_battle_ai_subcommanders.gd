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
## battle, no scenario override -- see .claude/skills/sparta-demos/SKILL.md's "verify before
## claiming" convention): the *replay-determinism* check below covers this many ticks of the
## default battle. Left wide so the determinism comparison is meaningful, independent of
## whether any SUPPORT directive happens to fire along the way.
const SUPPORT_BY_TICK: int = 600

## The scenario below runs on this fixed seed rather than a random one, so a failure is
## reproducible instead of being a fresh draw every run. Battle picks a random seed unless
## `Replay.forced_seed` is set before it enters the tree, and this scenario used to leave it
## random.
const SUPPORT_SCENARIO_SEED: int = 12345

## How long to give the dedicated SUPPORT-order scenario below to reach a real SUPPORT order.
## The directive fires at tick 61 -- the first AI tick after the ally's throwaway foe dies,
## with the ward already FIGHTING from its spawn contact -- so 180 leaves two whole AI periods
## of margin. It is deliberately tight: a wide window is what let the old scenario's race pass
## most of the time instead of failing loudly, so a regression back to that shape should turn
## this red rather than merely slow it down. Measured at tick 61 on every one of 16 runs
## (eleven fixed seeds plus five random draws, including the first-battle-in-process case).
## Narrow this if the fire tick moves; do not widen it to chase a failure, which is what the
## previous 120 -> 360 -> 600 sequence did without ever converging.
const SUPPORT_SCENARIO_TICK_WINDOW: int = 180


func after_each() -> void:
	Replay.forced_seed = -1


## Scoped to the battle passed in, not to the whole "units" group. The parameter was already
## in the signature and simply unused, so the function's name and arguments claimed a scoping
## it did not do -- this makes them true. No caller currently keeps two battles alive at once
## (the determinism test below runs two, but frees the first before instantiating the second),
## so this is hardening rather than a bug fix; a group-wide query would report a foreign
## unit's order as this battle's the moment one did.
func _team1_units(battle: Node) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u != null and u.team == 1 and battle.is_ancestor_of(u):
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
## directive can claim it.
##
## `ward` and its foe spawn IN CONTACT, which is the whole of what makes the timing
## deterministic, and it is worth spelling out because the obvious-looking wider gap does not
## work. Both halves of _mutual_support_directives' precondition have to hold on the SAME AI
## tick: the ward must already be FIGHTING, and the ally must not be chasing a live target.
## The ally is free for exactly one tick -- tick 60, the first AI tick after its throwaway foe
## dies -- because UnitLeader's own fallback hands it an ATTACK on the nearest living enemy at
## INF range the moment no directive claims it, and it stays unavailable from then on. So if
## the ward has not closed the distance and engaged by tick 60, that one opening is missed,
## and the directive can only fire much later, once combat morale happens to push the ward's
## foe into ROUTING and frees the ally again. That last step is a combat race, and it was the
## entire source of this test's flakiness: with the foe spawned a march away (y=480) the fire
## tick ranged over 301, 361, 481, 541, 601, 661 and 781 across seeds 1..30. The loop below
## polls one tick past its bound (it tests current_tick() BEFORE the await), so a 600-tick
## window really admits a fire at 601, and 4 of those 30 draws -- the three at 661 and the one
## at 781 -- still missed it. Spawning the ward in contact removes the race outright: measured
## at tick 61 on every one of 16 runs. y=515 sits mid-band; the behaviour is identical from
## about y=495 to y=535 and reverts to the old race by y=480.
##
## See also demos/inputs/subcommander-mutual-support.json, the website demo built on this same
## scenario shape.
func _spawn_support_scenario() -> Node:
	# Fixed seed: see SUPPORT_SCENARIO_SEED. Must be set before the battle enters the tree,
	# since Battle._ready is what consumes it.
	Replay.forced_seed = SUPPORT_SCENARIO_SEED
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 750, "y": 515},               # ward's foe: in contact
		{"team": 0, "type": "Infantry", "x": 900, "y": 480, "count": 1},   # ally's foe: dies fast
		{"team": 1, "type": "Infantry", "x": 750, "y": 550},   # `ward`: fighting from tick 0
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
