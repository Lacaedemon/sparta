extends GutTest
## Battle AI phase 5 (docs/battle-ai-design.md): perception honors fog of war. The
## AI's four command scripts (UnitLeader, Subcommander, General, PlayerDelegation) read
## only Battle._ai_perceptible_units' fogged-or-omniscient view -- never the live "units"/
## "routers" groups directly -- so with fog of war on, a team's AI decisions can only ever
## react to what that team currently perceives (Perception.gd, the SAME visibility rules the
## player's own fog rendering uses). With fog off, the view is exactly today's omniscient
## one and AI behaviour is unchanged.

const UnitLeaderSrc := "res://scripts/UnitLeader.gd"
const SubcommanderSrc := "res://scripts/Subcommander.gd"
const GeneralSrc := "res://scripts/General.gd"
const PlayerDelegationSrc := "res://scripts/PlayerDelegation.gd"

const AI_PERIOD: int = 60   # Battle.AI_PERIOD -- the first _run_enemy_ai() decision is at tick 0.

# Well clear of the default TERRAIN patches (forest x:200-450, hill x:1150-1400, both
# y:380-580), so line-of-sight between these points is never occluded by accident.
const WATCHER_POS := Vector2(600.0, 1100.0)
const FAR_FLANKER_POS := Vector2(600.0, 50.0)     # ~1050 wu away: well beyond foot sight
const NEAR_FLANKER_POS := Vector2(600.0, 850.0)   # 250 wu away: well inside foot sight


func after_each() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = -1
	Replay.reset()
	await get_tree().physics_frame


# --- the four AI scripts never bypass the caller's perception source -----------------
#
# docs/fog-of-war-design.md's own phase-3 regression test: "a grep-based regression test
# that the four AI scripts contain no direct group lookups." A direct
# get_tree().get_nodes_in_group(...) call in any of these four files would read the live,
# unfiltered sim state, bypassing whatever fogged-or-omniscient array Battle handed them.


func test_no_ai_command_script_queries_scene_groups_directly() -> void:
	for path in [UnitLeaderSrc, SubcommanderSrc, GeneralSrc, PlayerDelegationSrc]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_true(src.length() > 0, "%s should be readable" % path)
		assert_false(src.contains("get_nodes_in_group"),
			"%s must read only its caller-supplied perception array, never the live scene groups" % path)


# --- fog off reproduces today's omniscient set exactly --------------------------------


func test_ai_perceptible_units_matches_the_live_groups_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 414
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 1, "type": "Infantry", "x": FAR_FLANKER_POS.x, "y": FAR_FLANKER_POS.y},
	]
	add_child_autofree(battle)
	# See the wait in test_team1_ai_ignores_an_unperceived_flanker_until_it_is_sighted below
	# for why this isn't a bare single `await physics_frame`.
	while battle.current_tick() < 1:
		await get_tree().physics_frame

	var expected: Dictionary = {}
	for group in ["units", "routers"]:
		for node in get_tree().get_nodes_in_group(group):
			var u := node as Unit
			if u != null:
				expected[u.uid] = true

	for team in [0, 1]:
		var got: Dictionary = {}
		for node in battle._ai_perceptible_units(team):
			var u := node as Unit
			if u != null:
				got[u.uid] = true
		assert_eq(got, expected,
			"with fog off, team %d's AI perception source is every live unit, unfiltered" % team)


# --- fog on: the design's own phase-5 acceptance test ----------------------------------


func _team_units(team: int) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u != null and u.team == team:
			out.append(u)
	return out


func test_team1_ai_ignores_an_unperceived_flanker_until_it_is_sighted() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	# A single unit per side keeps the scenario legible: team 1's lone "watcher" is the
	# only observer whose perception decides team 1's AI view, and team 0's lone
	# "flanker" is the only thing there is to (not) see.
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": FAR_FLANKER_POS.x, "y": FAR_FLANKER_POS.y},
	]
	add_child_autofree(battle)
	# A single bare `await physics_frame` races the newly-added Battle node's own first
	# _physics_process under full-suite load (see test_battle_ai_general.gd's
	# test_two_doctrines_produce_visibly_different_army_behavior_from_the_same_seed for the
	# same fix) -- wait until tick 0's _run_enemy_ai has actually run instead.
	while battle.current_tick() < 1:
		await get_tree().physics_frame

	var watcher: Unit = _team_units(1)[0]
	var flanker: Unit = _team_units(0)[0]
	assert_null(watcher.current_order,
		"the flanker is ~1050 wu away, well beyond sight: team 1's AI decides nothing")
	assert_false(battle._ai_perceptible_units(1).has(flanker),
		"the fogged view team 1's AI reads does not name the unperceived flanker at all")

	# Teleport the flanker into the watcher's sight disc -- a scripted position write is
	# the simplest way to control exactly which AI tick first perceives it; the AI reads
	# positions, not how a unit got there.
	flanker.position = NEAR_FLANKER_POS
	while battle.current_tick() <= AI_PERIOD:
		await get_tree().physics_frame

	assert_true(battle._ai_perceptible_units(1).has(flanker),
		"now inside the watcher's sight disc: the fogged view includes it")
	assert_not_null(watcher.current_order,
		"team 1's AI reacts on the first decision tick after the flanker enters perception")
	assert_eq(watcher.current_order.type, Order.Type.ATTACK,
		"the advance/attack fallback picks up the newly-perceived flanker")
	assert_eq(watcher.current_order.target_uid, flanker.uid)


func test_team1_ai_ignores_the_same_flanker_when_fog_is_off_too_far_to_reach() -> void:
	# The mirror check for fog OFF: an enemy this far away is still beyond
	# UnitLeader's own advance/attack fallback only if nothing else picks it up --
	# with fog off the AI is omniscient, so (unlike the fog-on case above) it DOES
	# react to the far flanker immediately. This is the "fog off: nothing changes"
	# invariant -- the pre-phase-5 (and still current, fog-off) omniscient behaviour.
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": FAR_FLANKER_POS.x, "y": FAR_FLANKER_POS.y},
	]
	add_child_autofree(battle)
	# See the same-named wait in test_team1_ai_ignores_an_unperceived_flanker_until_it_is_sighted
	# above for why this isn't a bare single `await physics_frame`.
	while battle.current_tick() < 1:
		await get_tree().physics_frame

	var watcher: Unit = _team_units(1)[0]
	var flanker: Unit = _team_units(0)[0]
	assert_not_null(watcher.current_order,
		"fog off: the omniscient view names every living enemy regardless of distance")
	assert_eq(watcher.current_order.target_uid, flanker.uid,
		"the only enemy on the field is targeted immediately, exactly as before phase 5")


# --- determinism: the fogged view is a pure function of serialized sim state ----------


func test_ai_decisions_replay_identically_with_fog_active() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 12345
	var first: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(first)
	while first.current_tick() <= AI_PERIOD:
		await get_tree().physics_frame
	var snapshot_a: Dictionary = {}
	for node in _team_units(1):
		var u: Unit = node
		snapshot_a[u.uid] = _order_signature(u)
	first.free()
	await get_tree().physics_frame

	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 12345
	var second: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(second)
	while second.current_tick() <= AI_PERIOD:
		await get_tree().physics_frame
	var snapshot_b: Dictionary = {}
	for node in _team_units(1):
		var u: Unit = node
		snapshot_b[u.uid] = _order_signature(u)

	assert_eq(snapshot_a, snapshot_b,
		"same seed + fog active -> identical per-unit AI order, exactly like the pre-phase-5 " +
		"omniscient determinism test in test_battle_ai_leaders.gd")


func _order_signature(u: Unit) -> String:
	if u.current_order == null:
		return "NONE"
	return "%s:%d" % [u.current_order.describe(), u.current_order.target_uid]
