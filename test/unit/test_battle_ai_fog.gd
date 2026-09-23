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
# both checked by _perception_invariant_violation below:
#   1. A direct get_nodes_in_group(...) call -- the live, unfiltered sim state, bypassing
#      whatever fogged-or-omniscient array Battle handed the caller.
#   2. A `BattleRef` token used for anything other than a static constant/enum read
#      (`BattleRef.OrderMode.SKIRMISH`, `BattleRef.ORDER_FORMATION_ONLY` -- the established,
#      legitimate way UnitLeader.gd reaches Battle's own constants today, since Battle.gd has
#      no class_name and BattleRef -- a preloaded script reference -- is the only handle to
#      it at all). Anything else attached to that token (`as BattleRef`, `BattleRef.new(`, a
#      `: BattleRef` type annotation) would mean an actual Battle INSTANCE in scope -- the
#      direct-field-access door this check exists to keep shut.


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


func test_no_ai_command_script_reads_unfiltered_world_state_directly() -> void:
	for path in [UnitLeaderSrc, SubcommanderSrc, GeneralSrc, PlayerDelegationSrc]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_true(src.length() > 0, "%s should be readable" % path)
		var violation: String = _perception_invariant_violation(src)
		assert_eq(violation, "",
			"%s must read only its caller-supplied perception array, never the live scene " %
			path + "groups or a Battle instance's own fields directly")


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
