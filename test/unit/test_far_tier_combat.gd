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
## layer, exactly as TierTransition.demote leaves one. It starts in State.FIGHTING because
## FarTierCombat.engaged_target gates on that state -- the way it inherits Unit._think's
## disengage rule and its mid-turn facing hold rather than reimplementing either. In a live
## battle _think sets it; these tests never run _think, so they set it here.
func _far_unit(team: int, pos: Vector2, facing: Vector2, count: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins "units"
	u.team = team
	u.position = pos
	u.facing = facing
	u.tier = FormationTier.FAR
	u.state = Unit.State.FIGHTING
	return u


## A frontal far-tier pair in melee reach: the defender at the origin facing DOWN, the
## attacker below it facing UP, one melee contact distance apart.
func _frontal_pair(count: int = 120) -> Array:
	var defender: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN, count)
	var gap: float = defender.attack_range + Unit.RADIUS * 2.0 - 1.0
	var attacker: Unit = _far_unit(1, Vector2(0.0, gap), Vector2.UP, count)
	return [attacker, defender]


## The same pair, but with the attacker pulled back beyond melee contact and inside
## Unit.RANGED_RANGE -- where a ranged attacker actually resolves as a volley, and so where
## FarTierRules' unconditional ranged branch is the right thing to compare against.
func _volley_pair(count: int = 120) -> Array:
	var defender: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN, count)
	var contact: float = defender.attack_range + Unit.RADIUS * 2.0
	var gap: float = (contact + Unit.RANGED_RANGE) * 0.5
	var attacker: Unit = _far_unit(1, Vector2(0.0, gap), Vector2.UP, count)
	attacker.is_ranged = true
	return [attacker, defender]


## Every live formation, defenders included once they break out of "units" into "routers".
## DELIBERATELY WIDER than what Battle._tick_far_tier_combat passes, which is the "units"
## group alone: routers are filtered out by can_fight either way, so handing them in proves
## the filter rather than relying on the caller to have excluded them.
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
			* FarTierRates.attack_interval(attacker, defender)


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
	# Each case perturbs one input the formula reads. The DEFENDER's stance drives the
	# missile/melee blunting and the all-around square; its facing drives the flank
	# multiplier; the ATTACKER's own stance drives formation_attack_factor (both square
	# variants) and formation_melee_attack_factor (testudo), which a defender-only sweep
	# would leave entirely unpinned; and the thinned attacker exercises the Lanchester term.
	var cases: Array = [
		{"name": "frontal melee", "facing": Vector2.DOWN, "mode": Unit.FORMATION_NORMAL,
			"attacker_mode": Unit.FORMATION_NORMAL},
		{"name": "flanked melee", "facing": Vector2.RIGHT, "mode": Unit.FORMATION_NORMAL,
			"attacker_mode": Unit.FORMATION_NORMAL},
		{"name": "rear melee", "facing": Vector2.UP, "mode": Unit.FORMATION_NORMAL,
			"attacker_mode": Unit.FORMATION_NORMAL},
		{"name": "shield wall", "facing": Vector2.DOWN, "mode": Unit.FORMATION_SHIELD_WALL,
			"attacker_mode": Unit.FORMATION_NORMAL},
		{"name": "orbis", "facing": Vector2.RIGHT, "mode": Unit.FORMATION_SQUARE,
			"attacker_mode": Unit.FORMATION_NORMAL},
		{"name": "testudo", "facing": Vector2.DOWN, "mode": Unit.FORMATION_TESTUDO,
			"attacker_mode": Unit.FORMATION_NORMAL},
		{"name": "testudo attacker", "facing": Vector2.DOWN, "mode": Unit.FORMATION_NORMAL,
			"attacker_mode": Unit.FORMATION_TESTUDO},
		{"name": "schiltron attacker", "facing": Vector2.DOWN, "mode": Unit.FORMATION_NORMAL,
			"attacker_mode": Unit.FORMATION_SCHILTRON},
		{"name": "orbis attacker", "facing": Vector2.RIGHT, "mode": Unit.FORMATION_TIGHT,
			"attacker_mode": Unit.FORMATION_SQUARE},
	]
	for case in cases:
		var pair := _frontal_pair()
		var attacker: Unit = pair[0]
		var defender: Unit = pair[1]
		defender.facing = case["facing"]
		defender.formation_mode = case["mode"]
		attacker.formation_mode = case["attacker_mode"]
		attacker.soldiers = 70   # thinned: exercises the Lanchester term
		assert_almost_eq(_per_strike(attacker, defender),
			_rules_per_strike(attacker, defender), TOL,
			"live and reference rates agree: %s" % case["name"])


func test_the_attacker_stance_cases_actually_move_the_rate() -> void:
	# The negative control for the sweep above: if formation_attack_factor and
	# formation_melee_attack_factor did nothing, every attacker-stance case would agree with
	# the plain one and the parity assertions would pass having tested nothing.
	var plain := _frontal_pair()
	var base: float = _per_strike(plain[0], plain[1])
	for mode in [Unit.FORMATION_TESTUDO, Unit.FORMATION_SCHILTRON, Unit.FORMATION_SQUARE]:
		var pair := _frontal_pair()
		pair[0].formation_mode = mode
		assert_lt(_per_strike(pair[0], pair[1]), base,
			"an attacker in a hunkered stance hits softer than one in line")


func test_ranged_rate_matches_the_record_model_and_skips_the_thinning_term() -> void:
	# Beyond melee contact, where a volley is what actually resolves -- see
	# resolves_as_ranged, and the in-contact case below.
	var pair := _volley_pair()
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	assert_true(FarTierRates.resolves_as_ranged(attacker, defender),
		"the pair is staged where the exchange really is a volley")
	attacker.soldiers = 12   # a gutted archer regiment still volleys at full weight
	assert_almost_eq(_per_strike(attacker, defender),
		_rules_per_strike(attacker, defender), TOL,
		"a ranged attacker's live rate matches the reference model")
	var full: Unit = _far_unit(1, attacker.position, attacker.facing)
	full.is_ranged = true
	assert_almost_eq(FarTierRates.casualty_rate(attacker, defender),
		FarTierRates.casualty_rate(full, defender), TOL,
		"ranged output does not scale with the shooter's remaining strength")


func test_a_ranged_attacker_in_melee_contact_resolves_as_melee() -> void:
	# Unit._think gates its ranged branch on `not in_contact`, so an archer regiment whose
	# enemy has closed falls through to the melee branch and UnitCombat.strike. The far tier
	# mirrors that; FarTierRules, whose records carry no such rule, deliberately does not.
	var pair := _frontal_pair()   # staged AT melee contact
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	attacker.is_ranged = true
	assert_false(FarTierRates.resolves_as_ranged(attacker, defender),
		"an archer regiment in melee contact is fighting, not shooting")
	assert_almost_eq(FarTierRates.striking_reach(attacker, defender),
		FarTierRates.melee_contact_distance(attacker, defender), TOL,
		"so it reaches melee contact, not RANGED_RANGE")
	assert_almost_eq(FarTierRates.attack_interval(attacker, defender),
		attacker.melee_attack_interval(), TOL,
		"and strikes on its melee cadence, not RANGED_INTERVAL")
	# The blunting swaps with the branch: a TESTUDO defender's all-round missile cover stops
	# applying, and its (absent) melee cover does not replace it.
	defender.formation_mode = Unit.FORMATION_TESTUDO
	var melee_only: Unit = _far_unit(1, attacker.position, attacker.facing)
	assert_almost_eq(FarTierRates.strike_expectation(attacker, defender),
		FarTierRates.strike_expectation(melee_only, defender), TOL,
		"in contact, a ranged regiment's expectation is the melee one")
	# Backing it off past contact flips every one of those back.
	attacker.position = Vector2(0.0, Unit.RANGED_RANGE - 1.0)
	assert_true(FarTierRates.resolves_as_ranged(attacker, defender),
		"and out of contact it is a volley again")
	assert_almost_eq(FarTierRates.attack_interval(attacker, defender),
		Unit.RANGED_INTERVAL, TOL, "on the volley cadence")


func test_the_precomputed_flank_multiplier_matches_the_derived_one() -> void:
	# FarTierCombat computes the flank reading once and passes it into both the rate and the
	# morale bookkeeping. This pins the override against the value casualty_rate derives for
	# itself, so the two cannot drift -- REAR_MORALE_EXTRA being 0.0 hides the morale half.
	for facing in [Vector2.DOWN, Vector2.RIGHT, Vector2.UP]:
		var pair := _frontal_pair()
		pair[1].facing = facing
		var flank: float = UnitCombat.flank_multiplier(pair[1], pair[0])
		assert_almost_eq(FarTierRates.casualty_rate(pair[0], pair[1], -1.0, flank),
			FarTierRates.casualty_rate(pair[0], pair[1]), TOL,
			"passing the precomputed flank multiplier matches deriving it")


func test_ranged_reach_is_ranged_range_and_melee_reach_is_contact() -> void:
	var pair := _frontal_pair()
	assert_almost_eq(FarTierRates.striking_reach(pair[0], pair[1]),
		pair[0].attack_range + Unit.RADIUS * 2.0, TOL,
		"melee reach is the regiment contact distance")
	var volley := _volley_pair()
	assert_almost_eq(FarTierRates.striking_reach(volley[0], volley[1]), Unit.RANGED_RANGE, TOL,
		"a ranged formation out of contact reaches RANGED_RANGE")


func test_melee_contact_distance_contracts_against_routing_defender() -> void:
	# Mirrors Unit._think: when the defender is ROUTING, contact distance contracts
	# to attack_range + defender.RADIUS (omitting the attacker's RADIUS) so the pursuer
	# only considers itself in melee contact when actual weapon reach connects.
	var pair := _frontal_pair()
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	var standing_contact: float = FarTierRates.melee_contact_distance(attacker, defender)
	assert_almost_eq(standing_contact, attacker.attack_range + Unit.RADIUS + defender.RADIUS, TOL,
		"standing defender contact includes both radii")
	defender.state = Unit.State.ROUTING
	var routing_contact: float = FarTierRates.melee_contact_distance(attacker, defender)
	assert_almost_eq(routing_contact, attacker.attack_range + defender.RADIUS, TOL,
		"routing defender contact contracts to weapon reach plus defender radius")
	assert_almost_eq(FarTierRates.striking_reach(attacker, defender), routing_contact, TOL,
		"striking reach mirrors the contracted contact distance")


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
	# Staged within the contracted routing contact distance (attack_range + defender.RADIUS).
	attacker.position = Vector2(0.0, FarTierRates.melee_contact_distance(attacker, defender) - 1.0)
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


# --- the close tier's own disengage and facing gates, inherited ----------------------------

func test_a_formation_under_a_plain_move_order_does_not_grind_down_a_router() -> void:
	# Unit._think's melee branch is gated on `in_contact and (target_enemy != null or not
	# has_move_target or chasing or MARCH_TO_CONTACT)`, so a plain move order past a broken
	# enemy is a DISENGAGE: the close tier marches by without striking. The far tier inherits
	# that by refusing to book attrition unless _think already put the unit in FIGHTING.
	var router: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN, 40)
	router.state = Unit.State.ROUTING
	router.remove_from_group("units")
	router.add_to_group("routers")
	var marcher: Unit = _far_unit(1, Vector2.ZERO, Vector2.UP)
	var gap: float = FarTierRates.melee_contact_distance(marcher, router) - 1.0
	marcher.position = Vector2(0.0, gap)
	marcher.state = Unit.State.MOVING   # marching past, not fighting
	marcher.has_move_target = true
	marcher.target_enemy = null
	for _i in range(120):
		FarTierCombat.tick_all(_combatants(), _tick_seconds())
	assert_eq(router.soldiers, router.max_soldiers,
		"a disengaging formation marches past the router instead of running it down")
	assert_null(FarTierCombat.engaged_target(marcher),
		"and has no engaged target while it is not fighting")
	# The same formation, now actually fighting, does run it down -- the negative control
	# that separates the gate from a staging mistake.
	marcher.state = Unit.State.FIGHTING
	for _i in range(120):
		FarTierCombat.tick_all(_combatants(), _tick_seconds())
	assert_lt(router.soldiers, router.max_soldiers,
		"once it commits to the fight, the same formation does run the router down")


func test_no_attrition_while_the_men_are_mid_turn() -> void:
	# _face_for_action withholds the close tier's strike until the front is brought to bear;
	# is_maneuver_turning() is the state that survives the tick for the far tier to read.
	var pair := _frontal_pair()
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	attacker._engage_turn_target = Vector2(0.0, -1.0)
	assert_true(attacker.is_maneuver_turning(), "the attacker is mid-arc")
	assert_null(FarTierCombat.engaged_target(attacker),
		"a formation still turning onto its target books nothing")
	attacker._engage_turn_target = Vector2.ZERO
	assert_not_null(FarTierCombat.engaged_target(attacker),
		"and resumes the moment the front is brought to bear")


# --- guards and degenerate inputs ---------------------------------------------------------

func test_a_null_formation_neither_fights_nor_is_struck() -> void:
	assert_false(FarTierCombat.can_fight(null), "a null formation cannot deal attrition")
	assert_false(FarTierCombat.can_be_struck(null), "and cannot absorb any")


func test_strength_ratio_is_zero_for_a_formation_with_no_roster() -> void:
	var u: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN)
	u.max_soldiers = 0
	assert_almost_eq(FarTierRates.strength_ratio(u), 0.0, TOL,
		"a formation with no roster presents no fighting frontage")


func test_a_non_positive_cadence_yields_no_rate_rather_than_an_infinite_one() -> void:
	var pair := _frontal_pair()
	assert_almost_eq(FarTierRates.casualty_rate(pair[0], pair[1], 0.0), 0.0, TOL,
		"a zero strike cadence yields no attrition instead of dividing by zero")


func test_far_tier_attrition_books_nothing_against_an_emptied_formation() -> void:
	var pair := _frontal_pair()
	pair[1].soldiers = 0
	assert_eq(FarTierAttrition.apply(pair[1], pair[0], 100.0, 1.0), 0,
		"a formation with no men left absorbs no further casualties")


func test_tick_all_skips_an_entry_that_is_not_a_formation() -> void:
	var stray := Node2D.new()
	add_child_autofree(stray)
	assert_eq(FarTierCombat.tick_all([stray], _tick_seconds()), 0,
		"a non-formation entry is skipped rather than crashing the pass")


func test_a_defender_wiped_by_an_earlier_plan_is_skipped_by_the_later_one() -> void:
	# Two attackers, one man between them: the plans are built together against the pre-tick
	# state, so the second one's defender is already gone by the time it applies.
	var defender: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN, 1)
	var front: Unit = _far_unit(1, Vector2(0.0, 40.0), Vector2.UP)
	var rear: Unit = _far_unit(1, Vector2(0.0, -40.0), Vector2.DOWN)
	# Pre-load the carry so the first attacker completes a whole casualty this very tick --
	# which is this defender's last man.
	defender._far_tier_casualty_carry = 0.999
	FarTierCombat.tick_all(_combatants(), _tick_seconds())
	assert_eq(defender.state, Unit.State.DEAD, "the first attacker wiped the defender out")
	assert_gt(front.soldiers, 0, "and the attackers came through it")
	assert_gt(rear.soldiers, 0, "including the one whose plan found nothing left to hit")


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


func test_a_far_tier_strike_still_spends_the_charge() -> void:
	# Both paths inside strike() zero _approach_velocity so the momentum bonus lands on the
	# contact-making blow only. The far-tier early return has to do the same: its own model
	# carries no charge term, so an unspent velocity would sit on the unit and then cash an
	# undeserved bonus on its first close-tier strike after promotion.
	var pair := _frontal_pair()
	var attacker: Unit = pair[0]
	var defender: Unit = pair[1]
	attacker.is_cavalry = true
	attacker._approach_velocity = Vector2(0.0, -Unit.CHARGE_REFERENCE_SPEED)
	assert_gt(UnitCombat.charge_multiplier(attacker, defender), 1.0,
		"the staged approach really would have carried a charge bonus")
	UnitCombat.strike(attacker, defender)
	assert_eq(attacker._approach_velocity, Vector2.ZERO,
		"the far-tier early return spends the charge rather than banking it")
	assert_almost_eq(UnitCombat.charge_multiplier(attacker, defender), 1.0, TOL,
		"so a later close-tier strike gets no leftover momentum bonus")


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


func test_the_casualty_carry_survives_a_real_snapshot_round_trip() -> void:
	# The carry is mutable sim state, so a PLAYBACK rewind that dropped it would resume a
	# mid-fight formation from zero and diverge. Unit.to_snapshot_dict/apply_snapshot_dict's
	# field-level contract is covered in test_unit_snapshot.gd; this is the proof that a REAL
	# Battle.restore_snapshot -- which respawns the units from scratch -- carries it.
	var battle: Node2D = _spawn_duel()
	var weak: Unit = _duel_unit(1)
	assert_not_null(weak, "the scenario spawned the team-1 formation")
	if weak == null:
		battle.free()
		return
	var uid: int = weak.uid
	while battle.current_tick() < 260 and weak._far_tier_casualty_carry <= 0.0:
		await get_tree().physics_frame
	var carry: float = weak._far_tier_casualty_carry
	assert_gt(carry, 0.0, "the fight left a sub-soldier fraction standing to preserve")
	var snap: Dictionary = battle.capture_snapshot()
	battle.restore_snapshot(snap)
	var restored: Unit = battle.unit_by_uid(uid) as Unit
	assert_not_null(restored, "the formation came back from the snapshot")
	if restored != null:
		assert_almost_eq(restored._far_tier_casualty_carry, carry, TOL,
			"the carry survives, so a mid-fight rewind resumes from the same fraction")
	battle.free()


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
	# The second negative control: two dead sims agree perfectly too, so assert the fight
	# actually happened before reading the agreement as evidence of determinism.
	assert_gt(first["rout_tick"], 0, "the runs being compared actually fought and broke")
	assert_eq(first["rout_tick"], second["rout_tick"], "and breaks on the same tick")
	assert_eq(first["first_casualty_tick"], second["first_casualty_tick"],
		"and takes its first casualty on the same tick")
	assert_eq(first["end_soldiers"], second["end_soldiers"], "and ends at the same strength")
