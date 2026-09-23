extends GutTest
## Battle AI phase 5 (docs/battle-ai-design.md): perception honors fog of war. The
## AI's four command scripts (UnitLeader, Subcommander, General, PlayerDelegation) read
## only Battle._ai_perceptible_units' fogged-or-omniscient view -- never the live "units"/
## "routers" groups directly -- so with fog of war on, a team's AI decisions can only ever
## react to what that team currently perceives (Perception.gd, the SAME visibility rules the
## player's own fog rendering uses). With fog off, the view is exactly today's omniscient
## one and AI behaviour is unchanged.

const UNIT_LEADER_PATH := "res://scripts/UnitLeader.gd"
const SUBCOMMANDER_PATH := "res://scripts/Subcommander.gd"
const GENERAL_PATH := "res://scripts/General.gd"
const PLAYER_DELEGATION_PATH := "res://scripts/PlayerDelegation.gd"

const WorldScale = preload("res://scripts/WorldScale.gd")

const AI_PERIOD: int = 60   # Battle.AI_PERIOD -- the first _run_enemy_ai() decision is at tick 0.

## Foot sight radius on the default battle: Unit.SIGHT_FOOT (1.0) x Battle's own default
## sight_scale (0.25 * min(field.size.x, field.size.y) = 0.25 * 1200 = 300 wu on the default
## 1600x1200 field). Same derivation as test_fog_of_war.gd's own FOOT_SIGHT constant, so a
## change to the sight scale or field size invalidates this file's "beyond"/"inside" sight
## claims LOUDLY (the derived positions below move with it) rather than silently leaving a
## bare literal that quietly stops meaning what its comment says.
const FOOT_SIGHT: float = 15.0 * WorldScale.WU_PER_M

# Well clear of the default TERRAIN patches (forest x:200-450, hill x:1150-1400, both
# y:380-580), so line-of-sight between these points is never occluded by accident.
const WATCHER_POS := Vector2(600.0, 1100.0)
const FAR_FLANKER_POS := WATCHER_POS - Vector2(0.0, FOOT_SIGHT + 750.0)   # well beyond sight
const NEAR_FLANKER_POS := WATCHER_POS - Vector2(0.0, FOOT_SIGHT - 50.0)   # well inside sight

## A sight range forced well below Unit.DETECTION_RANGE (190 wu on the default WorldScale),
## used only by the auto-advance-on-detect tests below: small enough that a target inside
## detection range can still sit outside it.
const SHRUNK_SIGHT: float = 50.0
## Midpoint between SHRUNK_SIGHT and Unit.DETECTION_RANGE -- inside detection range (so
## UnitTargeting.nearest_enemy_to still finds it) but outside SHRUNK_SIGHT (so a team whose
## sight is forced down to SHRUNK_SIGHT does not perceive it): the "detected, not perceived"
## gap Unit._think()'s auto-advance-on-detect fallback used to skip entirely, marching on
## anything within detection_range regardless of whether it was actually perceived.
const DETECTED_NOT_PERCEIVED_POS := WATCHER_POS \
		- Vector2(0.0, (SHRUNK_SIGHT + Unit.DETECTION_RANGE) * 0.5)


func after_each() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = -1
	Replay.reset()
	await get_tree().physics_frame


# --- the four AI scripts never bypass the caller's perception source -----------------
#
# docs/fog-of-war-design.md's own phase-3 invariant (its "How the AI consumes perception
# without cheating" section): "No AI code path reads get_tree().get_nodes_in_group("units"),
# or any other unfiltered world state, directly ... a grep over [the four AI scripts] for
# group lookups and for direct Battle field access is a cheap regression test." Two shapes,
# both checked by _perception_invariant_violation below -- and ONLY these two: this is a
# grep-based check, not real type tracking, so its own claim is scoped to exactly what it
# mechanically recognizes, not to the invariant's full intent.
#   1. A direct get_nodes_in_group(...) call -- the live, unfiltered sim state, bypassing
#      whatever fogged-or-omniscient array Battle handed the caller.
#   2. The literal token `BattleRef` used for anything other than a static constant/enum
#      read (`BattleRef.OrderMode.SKIRMISH`, `BattleRef.ORDER_FORMATION_ONLY` -- the
#      established, legitimate way UnitLeader.gd reaches Battle's own constants today,
#      since Battle.gd has no class_name and BattleRef -- a preloaded script reference --
#      is the only handle to it at all). Anything else attached to that SPECIFIC token
#      (`as BattleRef`, `BattleRef.new(`, a `: BattleRef` type annotation) would mean an
#      actual Battle INSTANCE in scope under that name.
#
# KNOWN GAP, not extended here: this only recognizes the literal identifier `BattleRef`.
# A script that reached a live Battle instance through some OTHER untyped variable --
# `var b = get_parent()` then `b.terrain`, or any other name/path -- would read straight
# past this check with neither shape triggering, since nothing here tracks what a variable
# actually HOLDS, only whether the specific token `BattleRef` appears misused. Catching
# that reliably needs real static type analysis, not a grep; a keyword list of Battle's own
# field names would be both fragile (breaks the moment a new forbidden field is added and
# nobody updates the list) and false-positive-prone (any of those names could legitimately
# appear in an unrelated string, comment, or local variable elsewhere). This check's own
# claim is scoped to the two shapes it mechanically recognizes, not to "no untyped Battle
# access exists anywhere in these four files" -- see the test's own assertion message below.


## Returns a short, non-empty description of the first violation _perception_invariant_
## violation finds in `src`, or "" when `src` is clean. Pure string/regex logic with no file
## I/O, so it can be exercised directly against a synthetic snippet (see the "proven to bite"
## test below) as well as against the four real AI scripts.
static func _perception_invariant_violation(src: String) -> String:
	if src.contains("get_nodes_in_group"):
		return "calls get_nodes_in_group(...) directly"
	# Strip the one legitimate declaration line before scanning, so `const BattleRef =
	# preload(...)` itself -- BattleRef followed by " = ", not ".<Uppercase>" -- doesn't
	# trip the same regex that must catch `BattleRef.new(...)` or an `as BattleRef` cast.
	var scan: String = src.replace(
			"const BattleRef = preload(\"res://scripts/Battle.gd\")", "")
	var rx := RegEx.new()
	rx.compile("BattleRef(?!\\.[A-Z])")
	if rx.search(scan) != null:
		return "uses BattleRef for something other than a static constant/enum read"
	return ""


## Narrowly scoped to what _perception_invariant_violation mechanically recognizes (its own
## "KNOWN GAP" note above): a direct get_nodes_in_group(...) call, or the literal token
## `BattleRef` used for anything but a static constant/enum read. Does NOT prove the four
## scripts hold no live Battle instance at all -- one reached through a different variable
## name would not trip either shape. See that note for why extending this to catch that
## reliably would need real type analysis rather than a grep.
func test_no_ai_command_script_never_calls_get_nodes_in_group_or_misuses_battleref() -> void:
	for path in [UNIT_LEADER_PATH, SUBCOMMANDER_PATH, GENERAL_PATH, PLAYER_DELEGATION_PATH]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_true(src.length() > 0, "%s should be readable" % path)
		var violation: String = _perception_invariant_violation(src)
		assert_eq(violation, "",
			"%s must never call get_nodes_in_group(...) directly, nor use a `BattleRef` " %
			path + "token for anything but a static constant/enum read")


## Proves the guard above actually bites, per CLAUDE.md's "Guard tests must be proven to
## bite": a check that only ever reports the real files clean is indistinguishable from one
## that never runs. Each snippet below is a minimal, realistic stand-in for the two violation
## shapes the invariant forbids, plus the two legitimate shapes (the real declaration line,
## and a static constant/enum read) that must NOT trip it.
func test_perception_invariant_violation_detects_both_forbidden_shapes() -> void:
	assert_eq(_perception_invariant_violation(
			"static func decide(u, all_units):\n\treturn all_units"), "",
		"clean source: no violation")
	assert_eq(_perception_invariant_violation(
			"const BattleRef = preload(\"res://scripts/Battle.gd\")\n" +
			"static func f(): return BattleRef.OrderMode.NORMAL"), "",
		"the real declaration line, plus a static enum read, must not trip the guard")
	assert_ne(_perception_invariant_violation(
			"static func decide(u, all_units):\n" +
			"\tfor e in get_tree().get_nodes_in_group(\"units\"):\n\t\tpass"), "",
		"a direct get_nodes_in_group call must trip the guard")
	assert_ne(_perception_invariant_violation(
			"const BattleRef = preload(\"res://scripts/Battle.gd\")\n" +
			"static func decide(u, battle):\n" +
			"\tvar b := battle as BattleRef\n\treturn b.terrain"), "",
		"an `as BattleRef` cast onto a live instance, then a direct field read, must trip the guard")
	assert_ne(_perception_invariant_violation("static func decide(): return BattleRef.new()"), "",
		"instantiating Battle directly must trip the guard too")


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


# --- a delegated team-0 group reads the SAME fogged command-level view -----------------
#
# _run_player_delegated_ai (Battle.gd) reads _ai_perceptible_units(0), the identical
# fogged-or-omniscient source _run_enemy_ai reads for team 1 above -- but every existing
# delegation test (test_battle_ai_player_delegation.gd) sets all_teams_control = true to
# keep team 1's own AI from also moving, and Battle.is_fog_active() returns false
# unconditionally whenever all_teams_control is on. So the delegated-group path has never
# actually been exercised under real fog before this test: a real battle, all_teams_control
# left at its default (false), fog on.


const DELEGATE_GROUP: int = 5


func test_delegated_team0_group_ignores_an_unperceived_enemy_until_it_is_sighted() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	# Two team-0 units close together (so Subcommander sees a real 2-unit group, matching
	# test_battle_ai_player_delegation.gd's own staging convention) and one team-1 enemy
	# far off, beyond sight -- symmetric fog, so team 1's own (undelegated) AI has nothing
	# to react to either and stays passive.
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x + 40.0, "y": WATCHER_POS.y},
		{"team": 1, "type": "Infantry", "x": FAR_FLANKER_POS.x, "y": FAR_FLANKER_POS.y},
	]
	add_child_autofree(battle)
	var group: Array = _team_units(0)
	var uids: Array = []
	for u in group:
		uids.append(u.uid)
	battle.enqueue_delegation(uids, DELEGATE_GROUP)
	for u in group:
		assert_true(u.is_delegated(), "sanity check: delegation actually took")

	while battle.current_tick() < 1:
		await get_tree().physics_frame

	var enemy: Unit = _team_units(1)[0]
	for u in group:
		assert_null(u.current_order,
			"the enemy is ~1050 wu away, well beyond sight: the delegated group's own " +
			"AI decides nothing, exactly like an undelegated team's would")
	assert_false(battle._ai_perceptible_units(0).has(enemy),
		"the fogged view the delegated group's AI reads does not name the unperceived enemy")

	# Teleport the enemy into a delegated unit's sight disc -- same technique as the
	# team-1 flanker test above. NEAR_FLANKER_POS is already staged relative to WATCHER_POS,
	# which the first delegated unit spawns at.
	enemy.position = NEAR_FLANKER_POS
	while battle.current_tick() <= AI_PERIOD:
		await get_tree().physics_frame

	assert_true(battle._ai_perceptible_units(0).has(enemy),
		"now inside a delegated unit's sight disc: the fogged view includes it")
	var reacted: bool = false
	for u in group:
		if u.current_order != null and u.current_order.type == Order.Type.ATTACK \
				and u.current_order.target_uid == enemy.uid:
			reacted = true
	assert_true(reacted,
		"the delegated group reacts on the first decision tick after the enemy enters " +
		"perception, exactly like team 1's own AI does")


# --- a SEPARATE per-tick path: Unit._think()'s auto-advance-on-detect fallback ---------
#
# The command-level AI above (_run_enemy_ai, decided once per AI_PERIOD ticks) is not the
# only thing that can move an idle AI-driven unit toward an enemy.
# Unit._think()'s auto-advance-on-detect fallback runs every physics
# tick, independent of _run_enemy_ai, and its own candidate (UnitTargeting.nearest_enemy_to)
# is a bare-radius scan of the live "units"/"routers" groups within Unit.DETECTION_RANGE (190
# wu default) with NO line-of-sight or fog test at all. Before the fix, an idle team-1 unit
# would auto-march every tick toward any enemy within detection range, even one its own side
# does not currently perceive (forced sight below detection range, below) -- an omniscient
# backdoor the command-level fog swap never touched, since it is a wholly separate mechanism.


## Ticks to hold after staging before checking for movement: comfortably past BOTH
## Unit.order_response_delay (0.5s = 30 ticks -- an issued order sits idle that long before
## the unit actually marches) and Battle.AI_PERIOD (60 ticks, the command layer's own next
## decision), so a negative result (no movement) can't be misread as "hasn't had time yet"
## from either mechanism.
const SETTLE_TICKS: int = 90


func test_idle_ai_unit_does_not_auto_advance_on_a_detected_but_unperceived_enemy() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	# Force the watcher's sight well below the enemy's distance (still comfortably inside
	# Unit.DETECTION_RANGE, per DETECTED_NOT_PERCEIVED_POS's own derivation above) so the
	# enemy is a valid nearest_enemy_to candidate but not a perceived one. Set BEFORE the
	# first physics tick runs (not after) -- otherwise tick 0's own command-level AI decision
	# would still see the enemy at the unit's DEFAULT sight range and issue a real ATTACK
	# order right then, which arms Unit.order_response_delay and freezes _think() entirely
	# for the next 30 ticks regardless of what this test is actually trying to isolate.
	watcher.sight_range = SHRUNK_SIGHT
	assert_false(battle.ai_team_perceives(1, enemy),
		"sanity check on the staged distances: team 1 does not perceive this enemy")
	assert_lt(watcher.position.distance_to(enemy.position), Unit.DETECTION_RANGE,
		"sanity check: the enemy is still a valid nearest_enemy_to candidate")
	var start_pos: Vector2 = watcher.position

	for _i in range(SETTLE_TICKS):
		await get_tree().physics_frame

	assert_almost_eq(watcher.position.distance_to(start_pos), 0.0, 0.5,
		"fog on, enemy detected (within DETECTION_RANGE) but unperceived (outside the forced " +
		"sight range): the watcher holds position instead of auto-advancing")
	assert_null(watcher.current_order,
		"no order was ever issued for this either -- neither the command layer's own AI_PERIOD " +
		"decision nor the per-tick fallback above ever perceived the enemy")


func test_idle_ai_unit_still_auto_advances_on_a_detected_enemy_when_fog_is_off() -> void:
	# The mirror check for fog OFF: the identical staging (same forced-small sight range, same
	# "detected but would-be-unperceived-under-fog" distance) still auto-advances, because
	# ai_team_perceives (and therefore _enemy_is_perceived) is unconditionally true with fog
	# off -- this branch is byte-for-byte the pre-phase-5 behaviour. Fog off also means the
	# command-level AI (omniscient regardless of sight_range) issues a real ATTACK order at
	# tick 0 -- SETTLE_TICKS' own margin past order_response_delay covers that path too, so
	# this test doesn't need to (and, given the command layer's own unconditional omniscience,
	# largely can't) isolate the per-tick fallback from the command-level order the way the
	# fog-on test above does; either mechanism producing movement proves the fog-off claim.
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	watcher.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity with the fog-on test
	assert_true(battle.ai_team_perceives(1, enemy),
		"sanity check: fog off means ai_team_perceives is unconditionally true regardless of sight")
	var start_pos: Vector2 = watcher.position

	for _i in range(SETTLE_TICKS):
		await get_tree().physics_frame

	assert_gt(watcher.position.distance_to(start_pos), 0.5,
		"fog off: the watcher still auto-advances on the detected enemy, exactly as before phase 5")


# --- the same gate also covers RANGED FIRE, not just chase/movement --------------------
#
# Coordinator review: Unit._think()'s own ranged-fire-at-standoff branch, and
# Unit._support_tick's ranged branch, each pick a missile target from the same unfogged,
# bare-radius scan (detection_range / SUPPORT_GUARD_RADIUS respectively) the chase branches
# above use -- and firing is a STARKER tell than marching, since missile_range can reach
# well past what the team's fog-restricted sight covers: a visible volley at a unit the
# player's own screen still hides. Both are now gated by _enemy_is_perceived exactly like
# the chase branches.


func test_idle_ranged_ai_unit_does_not_fire_on_a_detected_but_unperceived_enemy() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	# Set BEFORE the first physics tick, same reasoning as the auto-advance test above.
	watcher.sight_range = SHRUNK_SIGHT
	assert_false(battle.ai_team_perceives(1, enemy),
		"sanity check on the staged distances: team 1 does not perceive this enemy")
	assert_lt(watcher.position.distance_to(enemy.position), watcher.missile_range,
		"sanity check: the enemy is still within the archer's own missile_range")
	var start_pos: Vector2 = watcher.position

	for _i in range(SETTLE_TICKS):
		await get_tree().physics_frame

	assert_almost_eq(watcher.position.distance_to(start_pos), 0.0, 0.5,
		"fog on: the archer holds position instead of chasing (the chase branch's own gate)")
	assert_ne(watcher.state, Unit.State.FIGHTING,
		"fog on, enemy within missile_range but unperceived: the archer never enters FIGHTING, " +
		"so it never fires (UnitCombat.shoot is only reached from inside the FIGHTING branch)")
	assert_null(watcher.current_order,
		"no command-level order was issued for this either -- team 1's own fog-restricted " +
		"sight never covered this enemy at any AI decision tick")


func test_idle_ranged_ai_unit_still_fires_on_a_detected_enemy_when_fog_is_off() -> void:
	# The mirror check for fog OFF: the identical staging still fires, because
	# ai_team_perceives is unconditionally true with fog off -- this branch is byte-for-byte
	# the pre-phase-5 behaviour.
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	watcher.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	assert_true(battle.ai_team_perceives(1, enemy),
		"sanity check: fog off means ai_team_perceives is unconditionally true regardless of sight")

	for _i in range(SETTLE_TICKS):
		await get_tree().physics_frame

	assert_eq(watcher.state, Unit.State.FIGHTING,
		"fog off: the archer still fires on the detected enemy, exactly as before phase 5")


## _support_tick is called directly here (bypassing the live command-level AI loop
## entirely) so the test isolates the SUPPORT-stance ranged branch itself: a real command-
## level AI tick for this unit would freely reissue an ordinary attack/chase order over top
## of a directly-set order_mode/support_target, which the queue-driven SUPPORT order path
## (Battle._apply_order_cmd's SUPPORT branch, exercised elsewhere) does not have to contend
## with in the same way. Matches this file's own convention of calling a private tick
## function directly (see test_fog_of_war.gd's battle._tick_fog() calls).
func test_support_stance_ranged_unit_does_not_fire_on_a_detected_but_unperceived_threat() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},   # ward
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x + 30.0, "y": WATCHER_POS.y, "ammo": 5},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var team1: Array = _team_units(1)
	var ward: Unit = team1[0]
	var supporter: Unit = team1[1]
	var threat: Unit = _team_units(0)[0]
	for u in team1:
		u.sight_range = SHRUNK_SIGHT
	assert_false(battle.ai_team_perceives(1, threat),
		"sanity check on the staged distances: team 1 does not perceive this threat")
	assert_lt(ward.position.distance_to(threat.position), Unit.SUPPORT_GUARD_RADIUS,
		"sanity check: the threat is still within SUPPORT_GUARD_RADIUS of the ward")
	assert_lt(supporter.position.distance_to(threat.position), supporter.missile_range,
		"sanity check: the threat is still within the supporter's own missile_range")
	supporter.order_mode = Unit.ORDER_SUPPORT
	supporter.support_target = ward
	var start_ammo: int = supporter.missile_ammo
	var start_pos: Vector2 = supporter.position

	for _i in range(30):
		supporter._support_tick(1.0 / 60.0)

	assert_eq(supporter.missile_ammo, start_ammo,
		"fog on, threat within SUPPORT_GUARD_RADIUS but unperceived: the supporter never fires")
	assert_ne(supporter.state, Unit.State.FIGHTING,
		"fog on: the supporter never enters FIGHTING against the unperceived threat")
	assert_lt(supporter.position.distance_to(start_pos), Unit.SUPPORT_FOLLOW_DISTANCE,
		"fog on: the supporter shadows its ward (already within follow distance) rather than " +
		"chasing the threat -- it does not close on the threat's own position")


func test_support_stance_ranged_unit_still_fires_on_a_detected_threat_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},   # ward
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x + 30.0, "y": WATCHER_POS.y, "ammo": 5},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var team1: Array = _team_units(1)
	var ward: Unit = team1[0]
	var supporter: Unit = team1[1]
	var threat: Unit = _team_units(0)[0]
	for u in team1:
		u.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	assert_true(battle.ai_team_perceives(1, threat),
		"sanity check: fog off means ai_team_perceives is unconditionally true regardless of sight")
	supporter.order_mode = Unit.ORDER_SUPPORT
	supporter.support_target = ward
	var start_ammo: int = supporter.missile_ammo

	for _i in range(30):
		supporter._support_tick(1.0 / 60.0)

	assert_lt(supporter.missile_ammo, start_ammo,
		"fog off: the supporter still fires on the detected threat, exactly as before phase 5")


# --- the ranged-fire and SUPPORT gates are symmetric: PLAYER (team 0) units too ---------
#
# Coordinator decision (under the user's daytb grant): keep these two branches symmetric
# across both teams, deliberately, rather than carving out an AI-only exception -- a player
# unit that could snipe or chase past its OWN player's fogged screen would itself be a
# fog-breaking exploit, and one shared rule is simpler than special-casing which side asked.
# This is a player-visible gameplay change (disclosed in website/how-to-play.qmd and
# website/tactics.qmd), so it gets the same fog-on/fog-off coverage the team-1 versions of
# these two tests already have, just with the team assignments swapped: team 0 is now the
# watcher/ward/supporter, team 1 is the detected-but-unperceived enemy/threat.


func test_idle_player_ranged_unit_does_not_fire_on_a_detected_but_unperceived_enemy() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 1, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(0)[0]
	var enemy: Unit = _team_units(1)[0]
	watcher.sight_range = SHRUNK_SIGHT   # before the first physics tick -- see the team-1 test above
	assert_false(battle.ai_team_perceives(0, enemy),
		"sanity check on the staged distances: team 0 does not perceive this enemy")
	assert_lt(watcher.position.distance_to(enemy.position), watcher.missile_range,
		"sanity check: the enemy is still within the archer's own missile_range")
	var start_pos: Vector2 = watcher.position

	for _i in range(SETTLE_TICKS):
		await get_tree().physics_frame

	assert_almost_eq(watcher.position.distance_to(start_pos), 0.0, 0.5,
		"fog on: the player's own idle archer holds position instead of chasing")
	assert_ne(watcher.state, Unit.State.FIGHTING,
		"fog on, enemy within missile_range but unperceived: the player's own archer never " +
		"fires -- the gate applies to team 0 exactly like team 1")
	# No command-level order either: team 0 has no AI general of its own (a non-delegated
	# player unit is untouched by _run_enemy_ai/_run_player_delegated_ai), so this is really
	# just confirming nothing ELSE moved the archer either.
	assert_null(watcher.current_order, "no order of any kind was issued for this unit")


func test_idle_player_ranged_unit_still_fires_on_a_detected_enemy_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 1, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(0)[0]
	var enemy: Unit = _team_units(1)[0]
	watcher.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	assert_true(battle.ai_team_perceives(0, enemy),
		"sanity check: fog off means ai_team_perceives is unconditionally true regardless of sight")

	for _i in range(SETTLE_TICKS):
		await get_tree().physics_frame

	assert_eq(watcher.state, Unit.State.FIGHTING,
		"fog off: the player's own archer still fires on the detected enemy, exactly as before phase 5")


func test_player_support_stance_ranged_unit_does_not_fire_on_a_detected_but_unperceived_threat() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},   # ward
		{"team": 0, "type": "Archers", "x": WATCHER_POS.x + 30.0, "y": WATCHER_POS.y, "ammo": 5},
		{"team": 1, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var team0: Array = _team_units(0)
	var ward: Unit = team0[0]
	var supporter: Unit = team0[1]
	var threat: Unit = _team_units(1)[0]
	for u in team0:
		u.sight_range = SHRUNK_SIGHT
	assert_false(battle.ai_team_perceives(0, threat),
		"sanity check on the staged distances: team 0 does not perceive this threat")
	assert_lt(ward.position.distance_to(threat.position), Unit.SUPPORT_GUARD_RADIUS,
		"sanity check: the threat is still within SUPPORT_GUARD_RADIUS of the ward")
	assert_lt(supporter.position.distance_to(threat.position), supporter.missile_range,
		"sanity check: the threat is still within the supporter's own missile_range")
	supporter.order_mode = Unit.ORDER_SUPPORT
	supporter.support_target = ward
	var start_ammo: int = supporter.missile_ammo
	var start_pos: Vector2 = supporter.position

	for _i in range(30):
		supporter._support_tick(1.0 / 60.0)

	assert_eq(supporter.missile_ammo, start_ammo,
		"fog on, threat within SUPPORT_GUARD_RADIUS but unperceived: the player's own " +
		"supporter never fires -- the gate applies to team 0 exactly like team 1")
	assert_ne(supporter.state, Unit.State.FIGHTING,
		"fog on: the player's own supporter never enters FIGHTING against the unperceived threat")
	assert_lt(supporter.position.distance_to(start_pos), Unit.SUPPORT_FOLLOW_DISTANCE,
		"fog on: the supporter shadows its ward rather than closing on the threat's own position")


func test_player_support_stance_ranged_unit_still_fires_on_a_detected_threat_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},   # ward
		{"team": 0, "type": "Archers", "x": WATCHER_POS.x + 30.0, "y": WATCHER_POS.y, "ammo": 5},
		{"team": 1, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var team0: Array = _team_units(0)
	var ward: Unit = team0[0]
	var supporter: Unit = team0[1]
	var threat: Unit = _team_units(1)[0]
	for u in team0:
		u.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	assert_true(battle.ai_team_perceives(0, threat),
		"sanity check: fog off means ai_team_perceives is unconditionally true regardless of sight")
	supporter.order_mode = Unit.ORDER_SUPPORT
	supporter.support_target = ward
	var start_ammo: int = supporter.missile_ammo

	for _i in range(30):
		supporter._support_tick(1.0 / 60.0)

	assert_lt(supporter.missile_ammo, start_ammo,
		"fog off: the player's own supporter still fires on the detected threat, exactly as before phase 5")


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


# --- far-tier attrition: FarTierCombat.engaged_target matches the near tier's melee/ranged
# --- split, not a blanket "committed is always exempt" rule -----------------------------
#
# UnitTargeting.current_target(u) falls through to a bare, unfogged nearest_enemy() scan
# whenever u.target_enemy has died or gone invalid, and never persists that pick back to
# target_enemy -- so a FIGHTING far-tier unit whose committed target just died could
# otherwise keep attriting a fresh, never-perceived target every tick with no gate at all.
# That much is true for both melee and ranged.
# But the exemption for an ALREADY-committed target_enemy is melee-only, matching the near
# tier exactly: Unit._think's melee-in-contact branch has no perception check at all
# (committed or fresh), while its ranged-fire-at-standoff branch re-checks
# _enemy_is_perceived every tick with no "already committed" carve-out -- only the
# melee/chase branch's `target_enemy != null` half is the disclosed exception. So a ranged
# far-tier exchange must keep re-checking too, even for a target it was already fighting.
# FarTierCombat.engaged_target is called DIRECTLY here (no physics ticks): the fields under
# test (tier, state, target_enemy) are set immediately after the battle spawns, so nothing
# AI-driven runs in between to disturb them, matching this file's own convention of calling
# a private/static function directly to isolate one branch (see the SUPPORT-stance tests
# above).


func test_far_tier_engaged_target_does_not_pick_a_fresh_unperceived_target() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(1)[0]
	var fresh_enemy: Unit = _team_units(0)[0]
	watcher.sight_range = SHRUNK_SIGHT
	assert_false(battle.ai_team_perceives(1, fresh_enemy),
		"sanity check on the staged distances: team 1 does not perceive this enemy")
	assert_true(FarTierRates.in_striking_range(watcher, fresh_enemy),
		"sanity check: the enemy is still within the archer's own missile_range")
	watcher.tier = FormationTier.FAR
	watcher.state = Unit.State.FIGHTING
	watcher.target_enemy = null   # simulates the committed target having just died mid-fight

	var engaged: Unit = FarTierCombat.engaged_target(watcher)

	assert_null(engaged,
		"a FRESH re-acquisition (target_enemy was null, so current_target() fell through to " +
		"the unfogged nearest_enemy() scan) must not attrit an enemy this team hasn't sighted")


func test_far_tier_engaged_target_still_picks_a_fresh_enemy_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(1)[0]
	var fresh_enemy: Unit = _team_units(0)[0]
	watcher.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	assert_true(battle.ai_team_perceives(1, fresh_enemy),
		"sanity check: fog off means ai_team_perceives is unconditionally true regardless of sight")
	watcher.tier = FormationTier.FAR
	watcher.state = Unit.State.FIGHTING
	watcher.target_enemy = null

	var engaged: Unit = FarTierCombat.engaged_target(watcher)

	assert_eq(engaged, fresh_enemy,
		"fog off: the fresh re-acquisition is unconditionally allowed, exactly as before " +
		"this gate existed")


func test_far_tier_engaged_target_keeps_an_already_committed_melee_target_even_if_unperceived() -> void:
	# The MELEE half of the invariant: combat already in contact is unconditionally exempt,
	# matching every other melee branch in this codebase (soldier-level combat stays unfogged
	# once bodies are touching) -- the near tier's own melee-in-contact branch has no
	# perception check at all, fresh pick or already committed. See the sibling test below
	# for the RANGED half, which re-checks every tick even for an already-committed target.
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y - 400.0},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(1)[0]
	var committed_enemy: Unit = _team_units(0)[0]
	# Melee contact distance is itself small, so SHRUNK_SIGHT (50 wu, tuned for the standoff
	# tests elsewhere in this file) would still trivially cover it -- shrink sight_range well
	# below contact distance specifically, so "in melee contact" and "unperceived" can both
	# be staged at once.
	var contact: float = UnitTargeting.melee_contact_distance(watcher.attack_range, Unit.RADIUS, committed_enemy)
	watcher.sight_range = contact * 0.25
	# Teleport into melee contact -- a scripted position write, the same technique this file
	# already uses elsewhere to control exactly which staging applies.
	committed_enemy.position = watcher.position + Vector2(0.0, contact - 1.0)
	assert_false(battle.ai_team_perceives(1, committed_enemy),
		"sanity check on the staged distance: team 1 does not perceive this enemy")
	assert_false(FarTierRates.resolves_as_ranged(watcher, committed_enemy),
		"sanity check: in melee contact, this resolves as melee, not a volley")
	watcher.tier = FormationTier.FAR
	watcher.state = Unit.State.FIGHTING
	watcher.target_enemy = committed_enemy

	var engaged: Unit = FarTierCombat.engaged_target(watcher)

	assert_eq(engaged, committed_enemy,
		"melee combat already in contact is unconditionally exempt, even though this team's " +
		"current perception no longer covers it")


func test_far_tier_engaged_target_drops_an_already_committed_ranged_target_once_unperceived() -> void:
	# The RANGED/standoff half of the same invariant: unlike melee, a standoff exchange
	# re-checks perception every tick regardless of commitment, matching the near tier's own
	# ranged-fire-at-standoff branch (Unit._think, ~line 2832), whose _enemy_is_perceived
	# check carries no "already committed" carve-out at all -- only the melee/chase branch's
	# `target_enemy != null` half is the disclosed exception.
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(1)[0]
	var committed_enemy: Unit = _team_units(0)[0]
	watcher.sight_range = SHRUNK_SIGHT
	assert_false(battle.ai_team_perceives(1, committed_enemy),
		"sanity check on the staged distance: team 1 does not perceive this enemy")
	assert_true(FarTierRates.resolves_as_ranged(watcher, committed_enemy),
		"sanity check: not in melee contact, so this resolves as a volley")
	watcher.tier = FormationTier.FAR
	watcher.state = Unit.State.FIGHTING
	watcher.target_enemy = committed_enemy   # already committed, unlike a fresh pick

	var engaged: Unit = FarTierCombat.engaged_target(watcher)

	assert_null(engaged,
		"a ranged/standoff exchange re-checks perception every tick, so an already-committed " +
		"target this team no longer perceives is dropped, not kept -- unlike the melee case " +
		"above")


func test_far_tier_engaged_target_keeps_a_ranged_target_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var watcher: Unit = _team_units(1)[0]
	var committed_enemy: Unit = _team_units(0)[0]
	watcher.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	watcher.tier = FormationTier.FAR
	watcher.state = Unit.State.FIGHTING
	watcher.target_enemy = committed_enemy

	var engaged: Unit = FarTierCombat.engaged_target(watcher)

	assert_eq(engaged, committed_enemy,
		"fog off: the ranged re-check is unconditionally true, so the committed target is " +
		"kept, exactly as before this gate existed")


# --- four more fresh-acquisition gaps: SKIRMISH kite, SWEEP_ROUTERS, ROLL_THE_LINE, CHASE -
#
# Each of these calls Unit._think() directly (matching test_unit.gd's own convention for
# isolating one order-mode branch) rather than running physics ticks, since the battle only
# needs to exist to wire a real, fogged _owning_battle -- a bare unit's _owning_battle is
# null, which makes _enemy_is_perceived unconditionally true regardless of fog.


func test_skirmish_kite_does_not_react_to_an_unperceived_close_enemy() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		# Inside skirmish_kite_distance (missile_range * 0.625 -- 100 wu for the default
		# Archers missile_range of 160 wu) but outside SHRUNK_SIGHT (50 wu): a close-in
		# threat the skirmisher's own side has not sighted.
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y - 80.0},
	]
	add_child_autofree(battle)
	var skirmisher: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	skirmisher.sight_range = SHRUNK_SIGHT
	skirmisher.order_mode = Unit.ORDER_SKIRMISH
	assert_false(battle.ai_team_perceives(1, enemy),
		"sanity check on the staged distance: team 1 does not perceive this enemy")
	assert_lt(skirmisher.position.distance_to(enemy.position), skirmisher.skirmish_kite_distance,
		"sanity check: the enemy is still inside the skirmisher's own kite distance")
	var start_pos: Vector2 = skirmisher.position

	skirmisher._think(0.1)

	assert_almost_eq(skirmisher.position.distance_to(start_pos), 0.0, 0.5,
		"fog on: a skirmisher does not kite away from a close threat its own side hasn't " +
		"sighted -- reacting to it would itself be the tell")


func test_skirmish_kite_still_reacts_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Archers", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y - 80.0},
	]
	add_child_autofree(battle)
	var skirmisher: Unit = _team_units(1)[0]
	skirmisher.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	skirmisher.order_mode = Unit.ORDER_SKIRMISH
	var start_pos: Vector2 = skirmisher.position

	skirmisher._think(0.1)

	assert_gt(skirmisher.position.distance_to(start_pos), 0.05,
		"fog off: the skirmisher still kites away, exactly as before this gate existed")


func test_sweep_routers_fallback_does_not_commit_to_a_fresh_unperceived_enemy() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var sweeper: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	sweeper.sight_range = SHRUNK_SIGHT
	sweeper.order_mode = Unit.ORDER_SWEEP_ROUTERS
	assert_false(battle.ai_team_perceives(1, enemy),
		"sanity check on the staged distance: team 1 does not perceive this enemy")
	assert_null(sweeper.target_enemy, "no target committed before thinking")

	sweeper._think(0.1)

	assert_null(sweeper.target_enemy,
		"fog on: SWEEP_ROUTERS's own current_target() fallback does not commit a fresh, " +
		"unperceived enemy to target_enemy (no live router in range, so this exercises the " +
		"elif fallback, not the routing-specific scan)")


func test_sweep_routers_fallback_still_commits_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var sweeper: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	sweeper.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	sweeper.order_mode = Unit.ORDER_SWEEP_ROUTERS

	sweeper._think(0.1)

	assert_eq(sweeper.target_enemy, enemy,
		"fog off: the fresh pick is committed, exactly as before this gate existed")


func test_roll_the_line_does_not_commit_to_a_fresh_unperceived_enemy() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var u: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	u.sight_range = SHRUNK_SIGHT
	u.order_mode = Unit.ORDER_ROLL_THE_LINE
	assert_false(battle.ai_team_perceives(1, enemy),
		"sanity check on the staged distance: team 1 does not perceive this enemy")

	u._think(0.1)

	assert_null(u.target_enemy,
		"fog on: ROLL_THE_LINE does not commit a fresh, unperceived enemy to target_enemy")


func test_roll_the_line_still_commits_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var u: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	u.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	u.order_mode = Unit.ORDER_ROLL_THE_LINE

	u._think(0.1)

	assert_eq(u.target_enemy, enemy,
		"fog off: the fresh pick is committed, exactly as before this gate existed")


func test_chase_does_not_close_on_a_fresh_unperceived_enemy_with_no_committed_target() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var u: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	u.sight_range = SHRUNK_SIGHT
	u.order_mode = Unit.ORDER_CHASE
	assert_null(u.target_enemy,
		"no committed target before thinking -- a bare ORDER_CHASE stance alone must not " +
		"gain the disclosed already-committed exception")
	assert_false(battle.ai_team_perceives(1, enemy),
		"sanity check on the staged distance: team 1 does not perceive this enemy")
	var start_pos: Vector2 = u.position

	u._think(0.1)

	assert_almost_eq(u.position.distance_to(start_pos), 0.0, 0.5,
		"fog on: a CHASE unit with no prior committed target_enemy does not close on a " +
		"fresh, unperceived enemy")


func test_chase_still_closes_on_a_fresh_enemy_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var u: Unit = _team_units(1)[0]
	u.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	u.order_mode = Unit.ORDER_CHASE
	var start_pos: Vector2 = u.position

	u._think(0.1)

	assert_gt(u.position.distance_to(start_pos), 0.05,
		"fog off: the CHASE unit still closes on the fresh enemy, exactly as before this " +
		"gate existed")


# --- _start_promoted_attack: a just-promoted, unresolved ATTACK order (target_uid < 0) -----
#
# Reachable from _think() via retire_current_order() -- the "advance UNTIL contact THEN
# attack" macro's own promotion path (phase 4): the guard retires a MOVE order the instant
# contact is made, and the queued ATTACK order it appended names no specific enemy
# (target_uid stays -1), so _start_promoted_attack must resolve target_enemy itself, from
# UnitTargeting.current_target -- whose own fresh-pick fallback is a bare, unfogged
# detection_range scan, same shape as every other fresh acquisition this file already
# covers. Called directly here (matching this file's own convention), with current_order
# set directly rather than routed through the real order queue.


func test_start_promoted_attack_does_not_resolve_to_a_fresh_unperceived_standoff_enemy() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var u: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	u.sight_range = SHRUNK_SIGHT
	u.current_order = Order.new_attack(-1)   # unresolved: target_uid stays -1
	assert_false(battle.ai_team_perceives(1, enemy),
		"sanity check on the staged distance: team 1 does not perceive this enemy")
	var contact: float = UnitTargeting.melee_contact_distance(u.attack_range, Unit.RADIUS, enemy)
	assert_gt(u.position.distance_to(enemy.position), contact,
		"sanity check: the enemy is not in melee contact, so this is the standoff case")

	u._start_promoted_attack()

	assert_null(u.target_enemy,
		"a fresh, unperceived, not-yet-in-contact enemy must not resolve an unrestricted " +
		"ATTACK order's target_enemy")


func test_start_promoted_attack_still_resolves_a_fresh_enemy_when_fog_is_off() -> void:
	Settings.set_fog_of_war_session(false)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": DETECTED_NOT_PERCEIVED_POS.x, "y": DETECTED_NOT_PERCEIVED_POS.y},
	]
	add_child_autofree(battle)
	var u: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	u.sight_range = SHRUNK_SIGHT   # irrelevant with fog off; set for parity
	u.current_order = Order.new_attack(-1)

	u._start_promoted_attack()

	assert_eq(u.target_enemy, enemy,
		"fog off: the fresh pick resolves target_enemy, exactly as before this gate existed")


func test_start_promoted_attack_resolves_to_an_unperceived_enemy_already_in_melee_contact() -> void:
	# The "keep the contacting-enemy case working" half: the guard that promotes this order
	# only fires the instant contact is made, so the intended candidate is normally already
	# in melee contact when this runs -- unconditionally exempt, same as every other melee
	# branch in this codebase, regardless of whether this team currently perceives it.
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y - 400.0},
	]
	add_child_autofree(battle)
	var u: Unit = _team_units(1)[0]
	var enemy: Unit = _team_units(0)[0]
	u.sight_range = SHRUNK_SIGHT
	var contact: float = UnitTargeting.melee_contact_distance(u.attack_range, Unit.RADIUS, enemy)
	enemy.position = u.position + Vector2(0.0, contact - 1.0)
	u.current_order = Order.new_attack(-1)
	assert_false(battle.ai_team_perceives(1, enemy),
		"sanity check on the staged distance: team 1 does not perceive this enemy")

	u._start_promoted_attack()

	assert_eq(u.target_enemy, enemy,
		"an enemy already in melee contact resolves the order even when this team's own " +
		"perception does not currently cover it")


func _order_signature(u: Unit) -> String:
	if u.current_order == null:
		return "NONE"
	return "%s:%d" % [u.current_order.describe(), u.current_order.target_uid]


# --- performance: fog_team's rendering-pass scan is reused by a same-frame gate -----------
#
# _tick_fog's own rendering-pass scan and _ai_perceptible_units(fog_team)'s own scan read
# the identical observer set and candidate set, so without the reuse in
# _ai_perceptible_units, a battle where both the rendering pass and a per-unit gate ask
# about fog_team in one tick would pay for that scan twice. The reused value is a
# start-of-frame SNAPSHOT, not a live re-derivation -- see Battle._ai_perceptible_units'
# own doc comment for the one-frame staleness window a mid-frame death/rout can open, and
# why that is a deliberate, order-independent design choice rather than an approximation.
# Called directly (no `await` between the two calls, matching this file's own convention of
# isolating one mechanism at a time): the whole point under test is whether two calls in
# the SAME physics frame collapse into one scan, and inserting an
# `await get_tree().physics_frame` between them would move to a LATER frame instead of
# proving anything about the same one.


func test_fog_team_scan_is_reused_by_a_gate_asking_the_same_team_in_the_same_frame() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 1, "type": "Infantry", "x": FAR_FLANKER_POS.x, "y": FAR_FLANKER_POS.y},
	]
	add_child_autofree(battle)
	assert_eq(battle.fog_team, 0, "sanity check: the default scenario renders team 0's view")
	var enemy: Unit = _team_units(1)[0]
	assert_eq(battle._fog_scan_calls, 0, "no scan has run yet -- no tick has been processed")

	battle._tick_fog()   # the rendering pass' own scan for fog_team

	assert_eq(battle._fog_scan_calls, 1, "the rendering pass scanned once, as always")

	var perceives_own_team: bool = battle.ai_team_perceives(0, enemy)   # asks about fog_team

	assert_eq(battle._fog_scan_calls, 1,
		"a gate asking about fog_team in the same frame _tick_fog already scanned for " +
		"reuses that result rather than paying for a second identical scan")
	assert_false(perceives_own_team,
		"sanity check: the enemy is ~1050 wu away, well beyond default sight, so the " +
		"reused result correctly reports it as unperceived")

	battle.ai_team_perceives(1, enemy)   # asks about a DIFFERENT team

	assert_eq(battle._fog_scan_calls, 2,
		"a different team's own ask still pays for its own scan -- only the fog_team " +
		"duplicate is eliminated, not every scan")


# --- BUG: restore_snapshot must also clear ai_team_perceives' own cache -------------------
#
# ai_team_perceives caches its answer keyed by _tick alone (_ai_perceives_cache /
# _ai_perceives_cache_tick, above _ai_perceptible_units in this file). restore_snapshot
# already resets _fog_seen_frame (this file's own reuse tests above), but a rewind that
# lands on the SAME _tick value an earlier ask already cached a result for would otherwise
# skip _ai_perceptible_units entirely and return the PRE-restore answer against the
# freshly-restored (potentially very different) positions -- UIDs themselves survive a
# restore, so a stale cache entry does not even fail an existence check, it just answers
# wrong. No `await` anywhere below: the whole point is landing the restore on the EXACT
# same _tick the earlier ask cached, which physics-frame-based waiting cannot reliably
# guarantee (natural per-tick AI activity would keep re-populating
# _ai_perceives_cache_tick to whatever tick is currently live).


func test_restore_snapshot_clears_the_stale_ai_perceives_cache() -> void:
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 588
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y},
		{"team": 1, "type": "Infantry", "x": WATCHER_POS.x, "y": WATCHER_POS.y - 50.0},
	]
	add_child_autofree(battle)
	var enemy: Unit = _team_units(1)[0]
	battle._tick_fog()

	assert_true(battle.ai_team_perceives(0, enemy),
		"sanity check: the enemy starts close enough to be perceived")
	var captured_tick: int = battle.current_tick()

	# Teleport the enemy well beyond sight -- a scripted position write, the same
	# technique this file already uses elsewhere -- simulating the world having moved on
	# by the time a later restore lands back on this same tick.
	enemy.position = FAR_FLANKER_POS
	battle._tick_fog()
	var snap: Dictionary = battle.capture_snapshot()
	assert_eq(battle.current_tick(), captured_tick,
		"sanity check: capturing a snapshot does not itself advance the tick")

	battle.restore_snapshot(snap)

	assert_eq(battle.current_tick(), captured_tick,
		"sanity check: the restore lands on the SAME tick the earlier ask cached a " +
		"result for -- the exact condition the bug needs")
	assert_false(battle.ai_team_perceives(0, enemy),
		"the restored world has the enemy far away: the cache must not leak the earlier, " +
		"now-stale 'perceived' answer just because the tick number matches")
