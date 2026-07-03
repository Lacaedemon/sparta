extends GutTest
## FarTierRules (docs/large-scale-simulation-design.md phase 2): the statistical rules that
## evolve a far-tier formation's morale, casualties, and position with no per-soldier state.
## Verified in isolation per the design doc's done-check: the scenario tests build only
## FarTierFormation records — no Unit, no Battle, no soldier arrays — and the rate math is
## cross-checked against the close-tier regiment combat formula it mirrors in expectation.

const SEED := 1234567

## Standard test formation: the Unit default stat line (attack 12, defense 6, 120 men),
## so expectations match the close-tier defaults the rules mirror.
func _make_rec(pos: Vector2 = Vector2.ZERO, facing: Vector2 = Vector2.DOWN) -> FarTierFormation:
	var rec := FarTierFormation.new()
	rec.count = 120
	rec.max_soldiers = 120
	rec.attack = 12
	rec.defense = 6
	rec.position = pos
	rec.facing = facing
	return rec


## A frontal attacker/defender pair standing in striking range: the defender at the origin
## facing DOWN, the attacker below it (on the defender's front) facing UP.
func _frontal_pair() -> Array:
	var defender := _make_rec(Vector2.ZERO, Vector2.DOWN)
	var attacker := _make_rec(Vector2(0.0, 50.0), Vector2.UP)
	return [attacker, defender]


# --- rate math mirrors the close-tier regiment formula -----------------------------------

func test_strike_expectation_is_the_regiment_formula_at_the_mean_roll() -> void:
	# UnitCombat.strike's formula path: max(1, attack - defense) * roll, roll mean 1.0.
	var pair := _frontal_pair()
	assert_eq(FarTierRules.strike_expectation(pair[0], pair[1]), 6.0)


func test_strike_expectation_floors_at_one_like_the_close_tier() -> void:
	var pair := _frontal_pair()
	var attacker: FarTierFormation = pair[0]
	attacker.attack = 3   # below the defender's defense of 6
	assert_eq(FarTierRules.strike_expectation(attacker, pair[1]), 1.0)


func test_casualty_rate_is_one_expected_strike_per_attack_interval() -> void:
	var pair := _frontal_pair()
	var expected: float = 6.0 / Unit.ATTACK_INTERVAL
	assert_almost_eq(FarTierRules.casualty_rate(pair[0], pair[1]), expected, 0.0001)


func test_casualty_rate_thins_with_the_attackers_remaining_strength() -> void:
	# The Lanchester-style term: a half-strength formation presents half the fighting
	# frontage, so it inflicts half the casualties per second.
	var pair := _frontal_pair()
	var attacker: FarTierFormation = pair[0]
	var full_rate: float = FarTierRules.casualty_rate(attacker, pair[1])
	attacker.count = 60
	assert_almost_eq(FarTierRules.casualty_rate(attacker, pair[1]), full_rate * 0.5, 0.0001)


func test_casualty_rate_is_zero_for_a_destroyed_attacker() -> void:
	var pair := _frontal_pair()
	var attacker: FarTierFormation = pair[0]
	attacker.count = 0
	assert_eq(FarTierRules.casualty_rate(attacker, pair[1]), 0.0)


func test_flank_multiplier_matches_the_close_tier_thresholds() -> void:
	var defender := _make_rec(Vector2.ZERO, Vector2.DOWN)
	assert_eq(FarTierRules.flank_multiplier(defender, Vector2(0.0, 100.0)), 1.0, "frontal")
	assert_eq(FarTierRules.flank_multiplier(defender, Vector2(100.0, 0.0)), 1.5, "flank")
	assert_eq(FarTierRules.flank_multiplier(defender, Vector2(0.0, -100.0)), 2.0, "rear")


func test_square_has_no_weak_side() -> void:
	var defender := _make_rec(Vector2.ZERO, Vector2.DOWN)
	defender.formation_mode = Unit.FORMATION_SQUARE
	assert_eq(FarTierRules.flank_multiplier(defender, Vector2(0.0, -100.0)), 1.0,
		"a rear attack on a square lands as a frontal hit")


func test_shield_wall_blunts_a_frontal_assault_but_not_a_rear_blow() -> void:
	var defender := _make_rec(Vector2.ZERO, Vector2.DOWN)
	defender.formation_mode = Unit.FORMATION_SHIELD_WALL
	var frontal: float = FarTierRules.melee_defense_factor(defender, Vector2(0.0, 100.0))
	var rear: float = FarTierRules.melee_defense_factor(defender, Vector2(0.0, -100.0))
	assert_almost_eq(frontal, 1.0 - Unit.SHIELD_WALL_MELEE_DEFENSE, 0.0001)
	assert_eq(rear, 1.0)


func test_stance_attack_factors_mirror_the_close_tier() -> void:
	var pair := _frontal_pair()
	var attacker: FarTierFormation = pair[0]
	attacker.formation_mode = Unit.FORMATION_SQUARE
	assert_almost_eq(FarTierRules.strike_expectation(attacker, pair[1]),
		maxf(1.0, 12.0 * Unit.SQUARE_ATTACK_FACTOR - 6.0), 0.0001)
	attacker.formation_mode = Unit.FORMATION_TESTUDO
	assert_almost_eq(FarTierRules.strike_expectation(attacker, pair[1]),
		maxf(1.0, 12.0 * (1.0 - Unit.TESTUDO_MELEE_PENALTY) - 6.0), 0.0001)


# --- attrition, morale erosion, and thresholds --------------------------------------------

func test_apply_casualties_books_losses_and_erodes_morale_by_the_close_tier_formula() -> void:
	# UnitCombat.register_casualties: erosion = (killed / max) * MORALE_LOSS_PER_FULL_LOSS.
	# 12 of 120 = a tenth of the force, so a tenth of the full-loss erosion (90) = 9.
	var rec := _make_rec()
	var applied := FarTierRules.apply_casualties(rec, 12)
	assert_eq(applied, 12)
	assert_eq(rec.count, 108)
	assert_eq(rec.casualties, 12)
	assert_almost_eq(rec.morale, 91.0, 0.0001)


func test_apply_casualties_adds_the_crumble_boost_below_the_threshold_ratio() -> void:
	# 12 more losses at 41/120 leave 29/120 ~ 0.2417, below the 0.4 crumble threshold:
	# base erosion 9.0, crumble depth (0.4 - 0.2417) / 0.4 ~ 0.3958, boost 9 * 4 * depth
	# = 14.25, total 23.25 — the same numbers register_casualties produces.
	var rec := _make_rec()
	rec.count = 41
	rec.casualties = 79
	var applied := FarTierRules.apply_casualties(rec, 12)
	assert_eq(applied, 12)
	assert_eq(rec.count, 29)
	assert_almost_eq(rec.morale, 76.75, 0.0001)


func test_apply_casualties_clamps_to_the_living_and_floors_morale_at_zero() -> void:
	var rec := _make_rec()
	rec.count = 5
	rec.casualties = 115
	rec.morale = 1.0
	var applied := FarTierRules.apply_casualties(rec, 50)
	assert_eq(applied, 5, "overkill applies only the remaining soldiers")
	assert_eq(rec.count, 0)
	assert_eq(rec.casualties, 120, "count + casualties never exceeds the roster")
	assert_eq(rec.morale, 0.0, "morale floors at zero instead of going negative")
	assert_true(FarTierRules.is_destroyed(rec))
	assert_false(FarTierRules.can_fight(rec))


func test_broken_at_zero_morale() -> void:
	var rec := _make_rec()
	assert_false(FarTierRules.is_broken(rec))
	rec.morale = 0.0
	assert_true(FarTierRules.is_broken(rec))
	assert_false(FarTierRules.can_fight(rec))


func test_tick_attrition_carries_fractions_until_a_whole_soldier_falls() -> void:
	var pair := _frontal_pair()
	var defender: FarTierFormation = pair[1]
	var rate: float = FarTierRules.casualty_rate(pair[0], defender)   # 10 per second
	var delta: float = 1.0 / Replay.PHYSICS_TPS
	var first_tick := FarTierRules.tick_attrition(defender, rate, delta)
	assert_eq(first_tick, 0, "a sixth of a soldier per tick: nobody falls on tick one")
	assert_almost_eq(defender.casualty_carry, rate * delta, 0.0001)
	# One second plus one guard tick (the extra tick absorbs float accumulation jitter
	# around the exact whole-soldier boundary): exactly rate-many soldiers have fallen.
	var total := first_tick
	for i in Replay.PHYSICS_TPS:
		total += FarTierRules.tick_attrition(defender, rate, delta)
	assert_eq(total, int(rate), "casualties over a second match the rate exactly")
	assert_eq(defender.count, 120 - int(rate))
	assert_eq(defender.casualties, int(rate))


# --- recovery ------------------------------------------------------------------------------

func test_recovery_mirrors_the_close_tier_resting_rate_and_caps_at_full() -> void:
	var rec := _make_rec()
	rec.morale = 50.0
	FarTierRules.tick_recovery(rec, 1.0)
	assert_almost_eq(rec.morale, 50.0 + Unit.MORALE_RECOVER_PER_SEC, 0.0001)
	rec.morale = 99.9
	FarTierRules.tick_recovery(rec, 1.0)
	assert_eq(rec.morale, 100.0)


func test_a_broken_formation_does_not_recover() -> void:
	var rec := _make_rec()
	rec.morale = 0.0
	FarTierRules.tick_recovery(rec, 10.0)
	assert_eq(rec.morale, 0.0, "broken is absorbing at the far tier — no rally rules yet")


# --- movement ------------------------------------------------------------------------------

func test_advance_marches_toward_the_target_and_faces_the_direction_of_travel() -> void:
	var rec := _make_rec(Vector2.ZERO, Vector2.DOWN)
	FarTierRules.advance(rec, Vector2(300.0, 0.0), 1.0)
	assert_almost_eq(rec.position.x, rec.march_speed, 0.0001)
	assert_almost_eq(rec.position.y, 0.0, 0.0001)
	assert_almost_eq(rec.facing.x, 1.0, 0.0001)
	assert_almost_eq(rec.facing.y, 0.0, 0.0001)


func test_advance_clamps_at_the_target_without_overshooting() -> void:
	var rec := _make_rec(Vector2.ZERO, Vector2.DOWN)
	FarTierRules.advance(rec, Vector2(10.0, 0.0), 1.0)   # a full second would cover 45
	assert_almost_eq(rec.position.x, 10.0, 0.0001)
	assert_almost_eq(rec.position.y, 0.0, 0.0001)


func test_advance_on_the_spot_changes_nothing() -> void:
	var rec := _make_rec(Vector2(5.0, 5.0), Vector2.DOWN)
	FarTierRules.advance(rec, Vector2(5.0, 5.0), 1.0)
	assert_almost_eq(rec.position.x, 5.0, 0.0001)
	assert_almost_eq(rec.position.y, 5.0, 0.0001)
	assert_eq(rec.facing.x, Vector2.DOWN.x)
	assert_eq(rec.facing.y, Vector2.DOWN.y)


func test_effective_speed_is_capped_by_the_stance() -> void:
	var rec := _make_rec()
	assert_almost_eq(FarTierRules.effective_speed(rec), rec.march_speed, 0.0001)
	rec.formation_mode = Unit.FORMATION_TESTUDO
	assert_almost_eq(FarTierRules.effective_speed(rec),
		rec.march_speed * Unit.TESTUDO_SPEED_SCALE, 0.0001)


func test_striking_range_mirrors_the_close_tier_contact_check() -> void:
	# Contact = attack_range + both unit radii, per the close tier's in_contact test.
	var a := _make_rec(Vector2.ZERO, Vector2.DOWN)
	var b := _make_rec(Vector2(0.0, a.attack_range + Unit.RADIUS * 2.0), Vector2.UP)
	assert_true(FarTierRules.in_striking_range(a, b))
	b.position.y += 1.0
	assert_false(FarTierRules.in_striking_range(a, b))


func test_striking_range_is_asymmetric_for_a_longer_reach() -> void:
	# A spear line opens up before a sword line can answer, exactly like the close tier.
	var spears := _make_rec(Vector2.ZERO, Vector2.DOWN)
	spears.attack_range = 48.0
	var swords := _make_rec(Vector2(0.0, 44.0 + Unit.RADIUS * 2.0), Vector2.UP)
	assert_true(FarTierRules.in_striking_range(spears, swords))
	assert_false(FarTierRules.in_striking_range(swords, spears))


# --- ranged/volley attrition ------------------------------------------------------------------

func test_ranged_striking_range_uses_ranged_range_not_melee_reach() -> void:
	var archers := _make_rec(Vector2.ZERO, Vector2.DOWN)
	archers.is_ranged = true
	var target := _make_rec(Vector2(0.0, Unit.RANGED_RANGE), Vector2.UP)
	assert_true(FarTierRules.in_striking_range(archers, target), "still in range at RANGED_RANGE")
	target.position.y += 1.0
	assert_false(FarTierRules.in_striking_range(archers, target), "just past RANGED_RANGE")


func test_ranged_striking_range_is_far_beyond_melee_reach() -> void:
	# RANGED_RANGE (160) far outreaches melee contact (attack_range 26 + both radii 36 = 62),
	# so an archer formation opens up long before a melee line could answer.
	var archers := _make_rec(Vector2.ZERO, Vector2.DOWN)
	archers.is_ranged = true
	var melee_contact: float = archers.attack_range + Unit.RADIUS * 2.0
	var target := _make_rec(Vector2(0.0, melee_contact + 50.0), Vector2.UP)
	assert_true(FarTierRules.in_striking_range(archers, target),
		"an archer formation strikes well beyond melee's own contact distance")


func test_ranged_strike_expectation_matches_the_close_tier_shoot_formula() -> void:
	# UnitCombat.shoot's formula path: max(1, attack - defense) * RANGED_DAMAGE_FACTOR * roll,
	# roll mean 1.0. No formation_melee_attack_factor term (a testudo still looses volleys
	# head-up; only the offence-scaling formation_attack_factor applies).
	var pair := _frontal_pair()
	var archers: FarTierFormation = pair[0]
	archers.is_ranged = true
	var expected: float = maxf(1.0, 12.0 - 6.0) * Unit.RANGED_DAMAGE_FACTOR
	assert_almost_eq(FarTierRules.strike_expectation(archers, pair[1]), expected, 0.0001)


func test_ranged_strike_expectation_floors_at_one_before_the_damage_factor() -> void:
	var pair := _frontal_pair()
	var archers: FarTierFormation = pair[0]
	archers.is_ranged = true
	archers.attack = 3   # below the defender's defense of 6
	assert_almost_eq(FarTierRules.strike_expectation(archers, pair[1]),
		1.0 * Unit.RANGED_DAMAGE_FACTOR, 0.0001)


func test_ranged_casualty_rate_is_one_expected_volley_per_ranged_interval() -> void:
	var pair := _frontal_pair()
	var archers: FarTierFormation = pair[0]
	archers.is_ranged = true
	var expected: float = (6.0 * Unit.RANGED_DAMAGE_FACTOR) / Unit.RANGED_INTERVAL
	assert_almost_eq(FarTierRules.casualty_rate(archers, pair[1]), expected, 0.0001)


func test_ranged_casualty_rate_does_not_scale_down_for_a_thinned_formation() -> void:
	# UnitCombat.shoot draws volley damage from the flat attack stat with no soldier-count
	# scaling: a 10-man archer regiment volleys exactly as hard as a 140-man one. The
	# strength_ratio thinning term is melee-only (its own justification is grounded in the
	# close tier's per-soldier melee path), so a half-strength archer formation must inflict
	# the SAME casualty rate as a full-strength one, unlike the melee case above.
	var pair := _frontal_pair()
	var archers: FarTierFormation = pair[0]
	archers.is_ranged = true
	var full_rate: float = FarTierRules.casualty_rate(archers, pair[1])
	archers.count = 60   # half of max_soldiers (120)
	assert_almost_eq(FarTierRules.casualty_rate(archers, pair[1]), full_rate, 0.0001,
		"a thinned archer formation volleys exactly as hard as a full-strength one")


func test_ranged_defender_uses_missile_defense_not_melee_defense() -> void:
	# TIGHT has no melee_defense_factor effect but does cut incoming missile damage.
	var pair := _frontal_pair()
	var archers: FarTierFormation = pair[0]
	archers.is_ranged = true
	var defender: FarTierFormation = pair[1]
	defender.formation_mode = Unit.FORMATION_TIGHT
	var expected: float = maxf(1.0, 12.0 - 6.0) * Unit.RANGED_DAMAGE_FACTOR \
			* (1.0 - Unit.TIGHT_MISSILE_DEFENSE)
	assert_almost_eq(FarTierRules.strike_expectation(archers, defender), expected, 0.0001)
	assert_eq(FarTierRules.melee_defense_factor(defender, archers.position), 1.0,
		"TIGHT has no melee_defense_factor bonus — only missile")


func test_shield_wall_missile_defense_is_frontal_only_like_melee_defense() -> void:
	var defender := _make_rec(Vector2.ZERO, Vector2.DOWN)
	defender.formation_mode = Unit.FORMATION_SHIELD_WALL
	var frontal: float = FarTierRules.missile_defense_factor(defender, Vector2(0.0, 100.0))
	var rear: float = FarTierRules.missile_defense_factor(defender, Vector2(0.0, -100.0))
	assert_almost_eq(frontal, 1.0 - Unit.SHIELD_WALL_MISSILE_DEFENSE, 0.0001)
	assert_eq(rear, 1.0, "a flank/rear volley bypasses the wall")


func test_square_gets_no_missile_defense_bonus() -> void:
	# Unlike melee/charge, a square's all-around shields don't help against plunging arrows.
	var defender := _make_rec(Vector2.ZERO, Vector2.DOWN)
	defender.formation_mode = Unit.FORMATION_SQUARE
	assert_eq(FarTierRules.missile_defense_factor(defender, Vector2(0.0, 100.0)), 1.0)
	assert_eq(FarTierRules.missile_defense_factor(defender, Vector2(0.0, -100.0)), 1.0)


func test_testudo_ranged_output_has_no_melee_offence_penalty() -> void:
	# A far-tier testudo takes the melee-only offence penalty (formation_melee_attack_factor)
	# when it strikes in melee, but not when it shoots — mirroring UnitCombat.shoot, which
	# never applies formation_melee_attack_factor to a volley.
	var pair := _frontal_pair()
	var archers: FarTierFormation = pair[0]
	archers.is_ranged = true
	archers.formation_mode = Unit.FORMATION_TESTUDO
	var expected: float = maxf(1.0, 12.0 - 6.0) * Unit.RANGED_DAMAGE_FACTOR
	assert_almost_eq(FarTierRules.strike_expectation(archers, pair[1]), expected, 0.0001,
		"testudo's melee penalty does not apply to ranged output")


func test_a_ranged_formation_takes_no_return_melee_attrition_beyond_melee_reach() -> void:
	# The archers stand at RANGED_RANGE — well beyond the melee attacker's own reach — and
	# strike every tick, while the melee side closes the gap and deals nothing until it
	# arrives at ITS OWN striking range.
	var archers := _make_rec(Vector2.ZERO, Vector2.DOWN)
	archers.is_ranged = true
	var melee := _make_rec(Vector2(0.0, Unit.RANGED_RANGE), Vector2.UP)
	var delta: float = 1.0 / Replay.PHYSICS_TPS
	FarTierRules.tick_pair(archers, melee, delta)
	assert_eq(melee.casualties, 0,
		"one tick isn't enough to kill a whole soldier, but the rate must be nonzero")
	assert_true(FarTierRules.in_striking_range(archers, melee), "archers are in their own range")
	assert_false(FarTierRules.in_striking_range(melee, archers),
		"the melee side is nowhere near its own (short) striking range yet")
	assert_eq(archers.casualties, 0, "no return melee attrition while still out of melee reach")
	# The melee side advances (not yet in reach); the archers hold and square up (in reach).
	assert_true(archers.position.distance_to(Vector2.ZERO) < 0.0001, "archers hold their ground")
	assert_true(melee.position.y < Unit.RANGED_RANGE, "the melee side presses in")


func test_a_ranged_formation_grinds_down_a_melee_formation_before_it_arrives() -> void:
	# Run the pair fight to resolution: since the archers open up at RANGED_RANGE while the
	# melee side must close nearly the whole gap first, the archers get several free ticks of
	# attrition — a plausibility check that the ranged branch actually behaves like a ranged
	# formation, not a melee one that closes to reach immediately.
	var archers := _make_rec(Vector2.ZERO, Vector2.DOWN)
	archers.is_ranged = true
	var melee := _make_rec(Vector2(0.0, 500.0), Vector2.UP)
	var delta: float = 1.0 / Replay.PHYSICS_TPS
	var melee_casualties_at_first_melee_hit := -1
	var archer_casualties_at_first_melee_hit := -1
	for i in 6000:
		if not (FarTierRules.can_fight(archers) and FarTierRules.can_fight(melee)):
			break
		FarTierRules.tick_pair(archers, melee, delta)
		if melee_casualties_at_first_melee_hit < 0 and archers.casualties > 0:
			melee_casualties_at_first_melee_hit = melee.casualties
			archer_casualties_at_first_melee_hit = archers.casualties
	assert_gt(melee_casualties_at_first_melee_hit, 0,
		"the archers inflicted real losses before the melee side ever landed a blow")


# --- the done-check scenario: two far-tier formations, no per-soldier state ---------------

## Run the isolated two-formation engagement until it resolves, asserting the curve
## invariants each tick. Returns the number of ticks the fight took.
func _run_pair_to_resolution(a: FarTierFormation, b: FarTierFormation, budget_ticks: int) -> int:
	var delta: float = 1.0 / Replay.PHYSICS_TPS
	var prev_gap: float = a.position.distance_to(b.position)
	var prev_casualties: int = a.casualties + b.casualties
	var prev_morale: float = a.morale + b.morale
	var ticks := 0
	while FarTierRules.can_fight(a) and FarTierRules.can_fight(b) and ticks < budget_ticks:
		FarTierRules.tick_pair(a, b, delta)
		ticks += 1
		var gap: float = a.position.distance_to(b.position)
		assert_true(gap <= prev_gap + 0.0001, "the formations never separate while fighting")
		assert_true(a.casualties + b.casualties >= prev_casualties, "casualties only accumulate")
		assert_true(a.morale + b.morale <= prev_morale + 0.0001,
			"morale only erodes while the fight is live")
		prev_gap = gap
		prev_casualties = a.casualties + b.casualties
		prev_morale = a.morale + b.morale
	return ticks


## Tick budget for a pair fight, derived from the sim constants rather than hard-coded:
## the approach time at both march speeds plus several attrition time-constants
## (max_soldiers / initial rate — the pace the exponential Lanchester thinning decays at).
func _pair_budget_ticks(a: FarTierFormation, b: FarTierFormation) -> int:
	var contact: float = a.attack_range + Unit.RADIUS * 2.0
	var gap: float = a.position.distance_to(b.position)
	var closing_speed: float = FarTierRules.effective_speed(a) + FarTierRules.effective_speed(b)
	var approach_secs: float = maxf(0.0, gap - contact) / closing_speed
	var initial_rate: float = FarTierRules.casualty_rate(a, b)
	var fight_secs: float = 6.0 * float(a.max_soldiers) / maxf(initial_rate, 0.0001)
	return int(ceil((approach_secs + fight_secs) * Replay.PHYSICS_TPS))


func test_two_far_tier_formations_close_fight_and_break_plausibly() -> void:
	# The phase's done-check: two aggregate formations approach, grind, and one (here,
	# by symmetry, both) breaks — casualties accumulate, morale erodes, nothing per-soldier
	# exists anywhere in the run.
	var a := _make_rec(Vector2.ZERO, Vector2.DOWN)
	var b := _make_rec(Vector2(0.0, 500.0), Vector2.UP)
	var budget := _pair_budget_ticks(a, b)
	var ticks := _run_pair_to_resolution(a, b, budget)
	assert_lt(ticks, budget, "the fight resolves within the derived budget")
	assert_true(FarTierRules.is_broken(a) or FarTierRules.is_destroyed(a)
			or FarTierRules.is_broken(b) or FarTierRules.is_destroyed(b),
		"at least one side breaks or is destroyed")
	assert_gt(a.casualties, 0, "the grind cost side A real losses")
	assert_gt(b.casualties, 0, "the grind cost side B real losses")
	assert_true(a.casualties < a.max_soldiers or b.casualties < b.max_soldiers,
		"morale broke a side before mutual annihilation, like the close-tier rout")
	assert_eq(a.count + a.casualties, a.max_soldiers, "side A's roster stays conserved")
	assert_eq(b.count + b.casualties, b.max_soldiers, "side B's roster stays conserved")


func test_a_mirrored_matchup_stays_exactly_symmetric() -> void:
	# The simultaneity contract: rates read the pre-tick state, so neither side gets a
	# first-mover advantage and identical formations produce identical curves.
	var a := _make_rec(Vector2.ZERO, Vector2.DOWN)
	var b := _make_rec(Vector2(0.0, 500.0), Vector2.UP)
	var ticks := _run_pair_to_resolution(a, b, _pair_budget_ticks(a, b))
	assert_gt(ticks, 0)
	assert_eq(a.count, b.count)
	assert_eq(a.casualties, b.casualties)
	assert_eq(a.morale, b.morale)
	assert_true(FarTierRules.is_broken(a) and FarTierRules.is_broken(b),
		"mirrored sides break on the same tick")


func test_the_stronger_side_wins_and_recovers_after_the_fight() -> void:
	var strong := _make_rec(Vector2.ZERO, Vector2.DOWN)
	strong.attack = 16
	var weak := _make_rec(Vector2(0.0, 500.0), Vector2.UP)
	_run_pair_to_resolution(strong, weak, _pair_budget_ticks(strong, weak))
	assert_true(FarTierRules.can_fight(strong), "the stronger side is still in the fight")
	assert_false(FarTierRules.can_fight(weak), "the weaker side broke first")
	assert_lt(strong.casualties, weak.casualties, "the winner bled less")
	# Post-fight: the survivor recovers morale where it stands (tick_pair's rest branch),
	# and the broken side stays broken.
	var morale_after_fight: float = strong.morale
	var delta: float = 1.0 / Replay.PHYSICS_TPS
	for i in Replay.PHYSICS_TPS:
		FarTierRules.tick_pair(strong, weak, delta)
	assert_almost_eq(strong.morale, morale_after_fight + Unit.MORALE_RECOVER_PER_SEC, 0.001)
	assert_true(FarTierRules.is_broken(weak))


func test_the_whole_run_is_deterministic() -> void:
	# Same records, same tick sequence, twice: every field lands on identical values —
	# the far tier draws no RNG at all, so this holds bit-for-bit, not just approximately.
	var results: Array = []
	for run in 2:
		var a := _make_rec(Vector2.ZERO, Vector2.DOWN)
		var b := _make_rec(Vector2(0.0, 500.0), Vector2.UP)
		b.attack = 14
		var delta: float = 1.0 / Replay.PHYSICS_TPS
		for i in _pair_budget_ticks(a, b):
			FarTierRules.tick_pair(a, b, delta)
		results.append([a.count, a.morale, a.casualties, a.position, a.facing, a.casualty_carry,
				b.count, b.morale, b.casualties, b.position, b.facing, b.casualty_carry])
	for field in results[0].size():
		assert_eq(results[0][field], results[1][field],
			"field %d matches across runs" % field)


func test_rules_source_never_touches_per_soldier_arrays() -> void:
	# The design doc's hard constraint, pinned as a tripwire: the far-tier rules must never
	# read or write _sim_soldier_* state. The scenario tests above already prove it by
	# construction (no Unit exists in them); this catches a future edit reintroducing one.
	var source := FileAccess.get_file_as_string("res://scripts/FarTierRules.gd")
	assert_false(source.contains("_sim_soldier_"),
		"FarTierRules must stay free of per-soldier state")
	assert_true(source.length() > 0, "the rules source loaded for the scan")


# --- plausibility against the close-tier model (the done-check's yardstick) ---------------

func test_far_tier_expectation_matches_the_close_tier_strike_distribution() -> void:
	# Land a run of REAL close-tier regiment strikes (UnitCombat.strike, seeded RNG) on a
	# fresh defender and compare the mean casualties per strike to the far tier's
	# expectation for the same stat line. The far tier is the mean of the close tier's
	# roll, so the sample mean must sit near it — this is the "broadly consistent with the
	# close-tier model" bar the done-check sets, checked mechanically.
	Replay.rng.seed = SEED
	# Kept OUT of the tree: strike's formula path never needs it, and staying out skips
	# the render-only Fallen markers register_casualties would otherwise spawn per strike.
	var u: Unit = autofree(Unit.new())
	u.max_soldiers = 120
	u.soldiers = 120
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	var enemy: Unit = autofree(Unit.new())
	enemy.max_soldiers = 120
	enemy.soldiers = 120
	enemy.team = 1
	enemy.position = Vector2(0.0, 100.0)
	enemy.facing = Vector2.UP
	var strikes := 50
	var killed_total := 0
	for i in strikes:
		enemy.soldiers = enemy.max_soldiers   # keep the ratio full: no crumble skew
		enemy.morale = 100.0                  # keep it fighting: no rout mid-sample
		var before: int = enemy.soldiers
		UnitCombat.strike(u, enemy)
		killed_total += before - enemy.soldiers
	var far_expectation := FarTierRules.strike_expectation(
			FarTierFormation.from_unit(u), FarTierFormation.from_unit(enemy))
	var close_mean := float(killed_total) / float(strikes)
	assert_almost_eq(close_mean, far_expectation, far_expectation * 0.15,
		"the far-tier expectation sits within 15%% of the sampled close-tier mean")
