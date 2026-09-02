extends GutTest
## FarTierCombat (docs/far-tier-pursuit-contagion-design.md, phase 0): the LIVE far-tier
## attrition step, which is what lets a demoted formation take casualties, lose morale, and
## break at all. Three layers are covered, deliberately:
##
## 1. The rate math, pinned against FarTierRules' own record-shaped formulas so the live
##    path and the isolated reference model cannot drift apart silently.
## 2. The resolution step on bare Units -- casualties accrue over ticks, morale falls, and
##    the rout fires through Unit._rout() (the ordinary path, with its group move and its
##    contagion shockwave), not through a second far-tier state machine.
## 3. The Battle wiring itself, on a real seeded battle whose tier band is tightened so
##    far-tier formations can actually stay far-tier while in reach. Without the wiring
##    these fail: nothing else in the tree calls FarTierCombat.
##
## The battle cases seed via Replay.forced_seed, not Replay.rng.seed -- Battle._ready()
## calls Replay.start_recording(), which reseeds the stream out from under any earlier pin.

const TOL: float = 1e-5
const BATTLE_SEED := 4242
# Staging band for the battle cases: both formations spawn beyond DEMOTE_STAGE (so the
# first tier pass collapses them to the far tier) and never close inside PROMOTE_STAGE (so
# they stay there while they fight). Deliberately far tighter than FormationTier's tuned
# defaults, which sit outside every combat reach -- see Battle.promote_range's own comment.
const PROMOTE_STAGE: float = 40.0
const DEMOTE_STAGE: float = 100.0
# Archer duel geometry: inside Unit.RANGED_RANGE (160) so both sides loose, outside melee
# contact so neither presses in, and wider than DEMOTE_STAGE so both demote on tick 1.
const DUEL_GAP: float = 150.0
const DUEL_X: float = 600.0
const DUEL_Y: float = 300.0


func before_each() -> void:
	Replay.rng.seed = 12345   # for the close-tier control cases, which do roll


func after_each() -> void:
	Replay.forced_seed = -1


# --- helpers ----------------------------------------------------------------------------

## A bare far-tier regiment in the tree: joined to "units" by _ready(), with no per-soldier
## layer, exactly as TierTransition.demote leaves one.
func _far_unit(team: int, pos: Vector2, facing: Vector2, count: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins "units"
	u.team = team
	u.position = pos
	u.facing = facing
	u.tier = FormationTier.FAR
	return u


## A frontal far-tier pair in melee reach: the defender at the origin facing DOWN, the
## attacker below it facing UP, one melee contact distance apart.
func _frontal_pair(count: int = 120) -> Array:
	var defender: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN, count)
	var gap: float = defender.attack_range + Unit.RADIUS * 2.0 - 1.0
	var attacker: Unit = _far_unit(1, Vector2(0.0, gap), Vector2.UP, count)
	return [attacker, defender]


## Every live formation, defenders included once they break out of "units" into "routers" --
## the same array Battle._tick_far_tier_combat hands FarTierCombat.tick_all.
func _combatants() -> Array:
	var all: Array = get_tree().get_nodes_in_group("units")
	all.append_array(get_tree().get_nodes_in_group("routers"))
	return all


func _tick_seconds() -> float:
	return 1.0 / float(Replay.PHYSICS_TPS)


## One strike's worth of expectation, interval-independent: the live path reads the
## attacker's OWN weapon cadence while FarTierRules reads the melee const, so comparing the
## per-second rates directly would fail on cadence rather than on the formula under test.
func _per_strike(attacker: Unit, defender: Unit) -> float:
	return FarTierRates.casualty_rate(attacker, defender) \
			* FarTierRates.attack_interval(attacker)


func _rules_per_strike(attacker: Unit, defender: Unit) -> float:
	var ra: FarTierFormation = FarTierFormation.from_unit(attacker)
	var rb: FarTierFormation = FarTierFormation.from_unit(defender)
	var interval: float = Unit.RANGED_INTERVAL if attacker.is_ranged else Unit.ATTACK_INTERVAL
	return FarTierRules.casualty_rate(ra, rb) * interval


# --- the live rate math mirrors FarTierRules' record-shaped model ------------------------

func test_strike_expectation_matches_the_record_model_frontally() -> void:
	var pair := _frontal_pair()
	assert_almost_eq(FarTierRates.strike_expectation(pair[0], pair[1]),
		FarTierRules.strike_expectation(FarTierFormation.from_unit(pair[0]),
			FarTierFormation.from_unit(pair[1])), TOL,
		"the live path evaluates the same mean-roll formula as the reference model")


func test_rate_matches_the_record_model_across_stances_and_angles() -> void:
	# Each case perturbs one input the formula reads: the defender's stance (missile and
	# melee blunting, the all-around square), the attack angle (flank multiplier), the
	# attacker's remaining strength (the thinning term), and the ranged/melee split.
	var cases: Array = [
		{"name": "frontal melee", "facing": Vector2.DOWN, "mode": Unit.FORMATION_NORMAL},
		{"name": "flanked melee", "facing": Vector2.RIGHT, "mode": Unit.FORMATION_NORMAL},
		{"name": "rear melee", "facing": Vector2.UP, "mode": Unit.FORMATION_NORMAL},
		{"name": "shield wall", "facing": Vector2.DOWN, "mode": Unit.FORMATION_SHIELD_WALL},
		{"name": "orbis", "facing": Vector2.RIGHT, "mode": Unit.FORMATION_SQUARE},
		{"name": "testudo", "facing": Vector2.DOWN, "mode": Unit.FORMATION_TESTUDO},
	]
	for case in cases:
		var pair := _frontal_pair()
		var attacker: Unit = pair[0]
		var defender: Unit = pair[1]
		defender.facing = case["facing"]
		defender.formation_mode = case["mode"]
		attacker.soldiers = 70   # thinned: exercises the Lanchester term
		assert_almost_eq(_per_strike(attacker, defender),
			_rules_per_strike(attacker, defender), TOL,
			"live and reference rates agree: %s" % case["name"])


func test_ranged_rate_matches_the_record_model_and_skips_the_thinning_term() -> void:
	var pair := _frontal_pair()
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	attacker.is_ranged = true
	attacker.soldiers = 12   # a gutted archer regiment still volleys at full weight
	assert_almost_eq(_per_strike(attacker, defender),
		_rules_per_strike(attacker, defender), TOL,
		"a ranged attacker's live rate matches the reference model")
	var full: Unit = _far_unit(1, attacker.position, attacker.facing)
	full.is_ranged = true
	assert_almost_eq(FarTierRates.casualty_rate(attacker, defender),
		FarTierRates.casualty_rate(full, defender), TOL,
		"ranged output does not scale with the shooter's remaining strength")


func test_ranged_reach_is_ranged_range_and_melee_reach_is_contact() -> void:
	var pair := _frontal_pair()
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	assert_almost_eq(FarTierRates.striking_reach(attacker, defender),
		attacker.attack_range + Unit.RADIUS * 2.0, TOL,
		"melee reach is the regiment contact distance")
	attacker.is_ranged = true
	assert_almost_eq(FarTierRates.striking_reach(attacker, defender), Unit.RANGED_RANGE, TOL,
		"a ranged formation reaches RANGED_RANGE")


# --- the resolution step on bare units ---------------------------------------------------

func test_a_far_tier_pair_in_contact_accrues_casualties_over_ticks() -> void:
	var pair := _frontal_pair()
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	var delta: float = _tick_seconds()
	var expected_rate: float = FarTierRates.casualty_rate(attacker, defender)
	assert_gt(expected_rate, 0.0, "a formation in reach has a positive attrition rate")
	var ticks: int = 120
	for _i in range(ticks):
		FarTierCombat.tick_all(_combatants(), delta)
	assert_lt(defender.soldiers, defender.max_soldiers,
		"the defender lost men to far-tier attrition")
	assert_lt(attacker.soldiers, attacker.max_soldiers,
		"the exchange is mutual -- the attacker takes return attrition too")
	# The continuous rate is exact over the span up to the sub-soldier carry, which is what
	# the carry field exists to guarantee: no casualty is rounded away tick by tick.
	var lost: int = defender.max_soldiers - defender.soldiers
	var booked: float = float(lost) + defender._far_tier_casualty_carry
	assert_between(booked, expected_rate * delta * float(ticks) * 0.85,
		expected_rate * delta * float(ticks) * 1.15,
		"casualties booked track rate * elapsed time")


func test_a_pair_out_of_striking_range_does_nothing() -> void:
	var defender: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN)
	var attacker: Unit = _far_unit(1, Vector2(0.0, 5000.0), Vector2.UP)
	for _i in range(120):
		FarTierCombat.tick_all(_combatants(), _tick_seconds())
	assert_eq(defender.soldiers, defender.max_soldiers, "no casualties out of reach")
	assert_eq(attacker.soldiers, attacker.max_soldiers, "no casualties out of reach")
	assert_almost_eq(defender._far_tier_casualty_carry, 0.0, TOL,
		"an out-of-reach formation accumulates no fractional carry either")
	assert_null(FarTierCombat.engaged_target(attacker),
		"an out-of-reach formation has no engaged target")


func test_morale_falls_and_the_rout_fires_through_the_ordinary_unit_path() -> void:
	var pair := _frontal_pair(40)
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	defender.morale = 4.0   # one casualty's erosion away from breaking
	var friend: Unit = _far_unit(0, defender.position + Vector2(10.0, 0.0), Vector2.DOWN)
	var friend_morale_before: float = friend.morale
	var start_morale: float = defender.morale
	var delta: float = _tick_seconds()
	for _i in range(240):
		FarTierCombat.tick_all(_combatants(), delta)
		if defender.state == Unit.State.ROUTING:
			break
	assert_lt(defender.morale, start_morale, "casualties eroded the defender's morale")
	assert_eq(defender.state, Unit.State.ROUTING,
		"morale reaching zero broke the formation through Unit._rout()")
	assert_true(defender.is_in_group("routers"),
		"the break went through the ordinary rout path, which moves the unit to routers")
	assert_false(defender.is_in_group("units"), "and out of the fighting units group")
	assert_lt(friend.morale, friend_morale_before,
		"Unit._rout()'s existing contagion shockwave shook the nearby friendly, for free")
	assert_gt(attacker.soldiers, 0, "the attacker survived the exchange")


func test_a_routing_formation_deals_no_attrition_but_can_still_be_run_down() -> void:
	var pair := _frontal_pair(40)
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	defender.state = Unit.State.ROUTING
	defender.remove_from_group("units")
	defender.add_to_group("routers")
	var attacker_before: int = attacker.soldiers
	for _i in range(120):
		FarTierCombat.tick_all(_combatants(), _tick_seconds())
	assert_eq(attacker.soldiers, attacker_before,
		"a routing formation deals no far-tier attrition")
	assert_lt(defender.soldiers, defender.max_soldiers,
		"but it is still run down -- fleeing grants no immunity, as at close tier")


func test_a_close_tier_formation_is_not_touched_by_the_far_tier_pass() -> void:
	var pair := _frontal_pair()
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	attacker.tier = FormationTier.CLOSE
	defender.tier = FormationTier.CLOSE
	for _i in range(120):
		FarTierCombat.tick_all(_combatants(), _tick_seconds())
	assert_eq(defender.soldiers, defender.max_soldiers,
		"the far-tier pass skips close-tier formations, which fight in Unit._think")
	assert_eq(attacker.soldiers, attacker.max_soldiers, "on both sides")


# --- the double-billing guard ------------------------------------------------------------

func test_unit_combat_strike_declines_for_a_far_tier_attacker() -> void:
	var pair := _frontal_pair()
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	UnitCombat.strike(attacker, defender)
	assert_eq(defender.soldiers, defender.max_soldiers,
		"a far-tier attacker's strike lands no casualties -- FarTierCombat books them")
	attacker.tier = FormationTier.CLOSE
	UnitCombat.strike(attacker, defender)
	assert_lt(defender.soldiers, defender.max_soldiers,
		"a close-tier attacker's strike still resolves normally")


func test_unit_combat_shoot_declines_for_a_far_tier_attacker() -> void:
	var pair := _frontal_pair()
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	attacker.is_ranged = true
	UnitCombat.shoot(attacker, defender)
	assert_eq(defender.soldiers, defender.max_soldiers,
		"a far-tier volley lands no rolled casualties -- FarTierCombat books the expectation")
	attacker.tier = FormationTier.CLOSE
	UnitCombat.shoot(attacker, defender)
	assert_lt(defender.soldiers, defender.max_soldiers,
		"a close-tier volley still resolves normally")


# --- the Battle wiring, on a real seeded battle -------------------------------------------

func _spawn_duel() -> Node2D:
	Replay.forced_seed = BATTLE_SEED
	var battle: Node2D = load("res://scenes/Battle.tscn").instantiate()
	battle.all_teams_control = true   # no team-1 AI: neither side is ordered to close
	battle.promote_range = PROMOTE_STAGE
	battle.demote_range = DEMOTE_STAGE
	battle.scenario = [
		{"team": 0, "type": "Archers", "x": DUEL_X, "y": DUEL_Y,
			"count": 60, "facing": [0.0, 1.0]},
		{"team": 1, "type": "Archers", "x": DUEL_X, "y": DUEL_Y + DUEL_GAP,
			"count": 30, "morale": 6.0, "facing": [0.0, -1.0]},
	]
	add_child(battle)
	return battle


func _duel_unit(team: int) -> Unit:
	for node in _combatants():
		var u: Unit = node as Unit
		if u != null and u.team == team and u.state != Unit.State.DEAD:
			return u
	return null


## Run the staged duel, capturing the trajectory the far-tier pass produces, KEYED BY THE
## SIM'S OWN TICK COUNTER rather than by sample index. Two runs can begin observing on
## different ticks (the first await lands wherever the physics frame happens to be relative
## to add_child), which offsets index-aligned arrays by one sample and reads exactly like a
## divergence. Keying by tick compares the sim against itself instead of against the
## observer's phase.
func _run_duel(max_ticks: int) -> Dictionary:
	var battle: Node2D = _spawn_duel()
	var caps := {
		"demoted": false, "first_casualty_tick": -1, "rout_tick": -1,
		"by_tick": {},
	}
	var weak: Unit = _duel_unit(1)
	var strong: Unit = _duel_unit(0)
	assert_not_null(weak, "the scenario spawned the team-1 formation")
	assert_not_null(strong, "the scenario spawned the team-0 formation")
	if weak == null or strong == null:
		battle.free()
		return caps
	var start: int = weak.soldiers
	while battle.current_tick() < max_ticks:
		await get_tree().physics_frame
		var tick: int = battle.current_tick()
		if not caps["demoted"] \
				and weak.tier == FormationTier.FAR and strong.tier == FormationTier.FAR:
			caps["demoted"] = true
		if caps["first_casualty_tick"] < 0 and weak.soldiers < start:
			caps["first_casualty_tick"] = tick
		if caps["rout_tick"] < 0 and weak.state == Unit.State.ROUTING:
			caps["rout_tick"] = tick
		caps["by_tick"][tick] = [weak.soldiers, snappedf(weak.morale, 0.0001)]
	caps["end_soldiers"] = weak.soldiers
	battle.free()
	return caps


func test_a_live_battle_resolves_far_tier_combat_through_the_battle_tick() -> void:
	var caps: Dictionary = await _run_duel(200)
	assert_true(caps["demoted"],
		"the tightened tier band demoted both formations while they were still in reach")
	assert_gt(caps["first_casualty_tick"], 0,
		"a far-tier formation took casualties from the live Battle tick")
	assert_gt(caps["rout_tick"], 0,
		"and broke, through Unit._rout(), once its morale was spent")
	assert_gt(caps["rout_tick"], caps["first_casualty_tick"] - 1,
		"the rout followed the casualties rather than preceding them")


func test_the_far_tier_fight_is_deterministic_under_a_forced_seed() -> void:
	var first: Dictionary = await _run_duel(160)
	var second: Dictionary = await _run_duel(160)
	var a: Dictionary = first["by_tick"]
	var b: Dictionary = second["by_tick"]
	var compared: int = 0
	for tick in a:
		if not b.has(tick):
			continue   # observer phase, not sim state -- see _run_duel's own comment
		compared += 1
		assert_eq(a[tick], b[tick],
			"tick %d: the same seeded battle books the same casualties and morale" % tick)
	# Without this the loop above would vacuously pass on two empty captures -- the
	# negative control a same-shape comparison always needs.
	assert_gt(compared, 100, "the two runs overlapped on enough ticks to be a real check")
	assert_eq(first["rout_tick"], second["rout_tick"], "and breaks on the same tick")
	assert_eq(first["first_casualty_tick"], second["first_casualty_tick"],
		"and takes its first casualty on the same tick")
	assert_eq(first["end_soldiers"], second["end_soldiers"], "and ends at the same strength")
