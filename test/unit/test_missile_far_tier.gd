extends GutTest
## Phase 5 acceptance tests: long ranges at the far tier (docs/longer-range-missile-design.md).
##
## Covers the three phase-5 acceptance criteria from the design note:
## 1. A far-tier formation takes casualties from a shooter outside DEMOTE_RANGE.
## 2. Far-tier and close-tier casualty rates agree for the same profile at the same range
##    (mirror property between FarTierRates, FarTierRules, and the close-tier expectation).
## 3. A battle at the Historical deployment preset opens with artillery fire and nothing else.
## Plus ammunition exhaustion and accuracy falloff at the far tier.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")
const TOL: float = 1e-5


func after_each() -> void:
	for child in get_children():
		if child is Fallen:
			child.free()


func _far_unit(team: int, pos: Vector2, facing: Vector2, count: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	u.attack = 20
	u.defense = 5
	add_child_autofree(u)
	u.team = team
	u.position = pos
	u.facing = facing
	u.tier = FormationTier.FAR
	u.state = Unit.State.FIGHTING
	return u


func test_far_tier_formation_takes_casualties_from_shooter_outside_demote_range() -> void:
	# Staged 1500 wu apart -- far beyond DEMOTE_RANGE (600 wu), inside the sling's 3600-wu range.
	var attacker: Unit = _far_unit(1, Vector2(0.0, 1500.0), Vector2.UP)
	var defender: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN)
	attacker.is_ranged = true
	attacker.equip_missile(LoadoutRegistry.MISSILE_SLING)

	assert_gt(attacker.position.distance_to(defender.position), FormationTier.DEMOTE_RANGE,
		"target is far outside DEMOTE_RANGE")
	assert_true(FarTierRates.in_striking_range(attacker, defender),
		"sling reaches 1500 wu (range 3600 wu)")
	assert_eq(FarTierCombat.engaged_target(attacker), defender,
		"far-tier combat engages target at this range")

	# Advance 2 seconds of far-tier combat
	var booked: int = FarTierCombat.tick_all([attacker, defender], 2.0)
	assert_gt(booked, 0, "casualties booked from long-range sling fire")
	assert_lt(defender.soldiers, 120, "defender lost soldiers")
	assert_eq(120 - defender.soldiers, booked, "casualties accurately tracked")


func test_casualty_rate_agreement_across_all_profiles_between_rates_and_rules() -> void:
	# For every registered profile, FarTierRates and FarTierRules must evaluate the exact same
	# continuous casualty rate at any test distance.
	var profiles: Array = [
		LoadoutRegistry.MISSILE_BOW,
		LoadoutRegistry.MISSILE_PILUM,
		LoadoutRegistry.MISSILE_JAVELIN,
		LoadoutRegistry.MISSILE_SLING,
		LoadoutRegistry.MISSILE_SELF_BOW,
		LoadoutRegistry.MISSILE_COMPOSITE_BOW,
		LoadoutRegistry.MISSILE_BOLT_SHOOTER,
		LoadoutRegistry.MISSILE_STONE_THROWER,
	]
	for type_id in profiles:
		var profile: MissileProfile = LoadoutRegistry.missile(type_id)
		var test_dist: float = profile.range_wu * 0.5
		var attacker: Unit = _far_unit(1, Vector2(0.0, test_dist), Vector2.UP)
		var defender: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN)
		attacker.is_ranged = true
		attacker.equip_missile(type_id)

		var live_rate: float = FarTierRates.casualty_rate(attacker, defender)
		var ra: FarTierFormation = FarTierFormation.from_unit(attacker)
		var rb: FarTierFormation = FarTierFormation.from_unit(defender)
		var rule_rate: float = FarTierRules.casualty_rate(ra, rb)

		assert_almost_eq(live_rate, rule_rate, TOL,
			"rates and rules casualty rates agree for %s" % profile.display_name)
		assert_gt(live_rate, 0.0, "rate is positive for %s" % profile.display_name)


func test_historical_deployment_preset_opens_with_artillery_fire_and_nothing_else() -> void:
	# Historical preset gap is 200 m = 4000 wu.
	var gap_wu: float = 200.0 * WorldScaleRef.WU_PER_M
	var defender: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN)

	# Artillery pieces reach across the 4000-wu gap:
	var bolt_shooter: Unit = _far_unit(1, Vector2(0.0, gap_wu), Vector2.UP)
	bolt_shooter.is_ranged = true
	bolt_shooter.equip_missile(LoadoutRegistry.MISSILE_BOLT_SHOOTER)
	assert_true(FarTierRates.in_striking_range(bolt_shooter, defender),
		"bolt-shooter reaches 4000 wu (range 7000 wu)")
	assert_gt(FarTierRates.casualty_rate(bolt_shooter, defender), 0.0,
		"bolt-shooter inflicts attrition at historical deployment gap")

	var stone_thrower: Unit = _far_unit(1, Vector2(0.0, gap_wu), Vector2.UP)
	stone_thrower.is_ranged = true
	stone_thrower.equip_missile(LoadoutRegistry.MISSILE_STONE_THROWER)
	assert_true(FarTierRates.in_striking_range(stone_thrower, defender),
		"stone-thrower reaches 4000 wu (range 7400 wu)")
	assert_gt(FarTierRates.casualty_rate(stone_thrower, defender), 0.0,
		"stone-thrower inflicts attrition at historical deployment gap")

	# Hand/bow weapons do NOT reach across the 4000-wu gap:
	var non_artillery_ids: Array = [
		LoadoutRegistry.MISSILE_BOW,
		LoadoutRegistry.MISSILE_PILUM,
		LoadoutRegistry.MISSILE_JAVELIN,
		LoadoutRegistry.MISSILE_SELF_BOW,
		LoadoutRegistry.MISSILE_SLING,
		LoadoutRegistry.MISSILE_COMPOSITE_BOW,
	]
	for type_id in non_artillery_ids:
		var shooter: Unit = _far_unit(1, Vector2(0.0, gap_wu), Vector2.UP)
		shooter.is_ranged = true
		shooter.equip_missile(type_id)
		var p: MissileProfile = LoadoutRegistry.missile(type_id)
		assert_false(FarTierRates.in_striking_range(shooter, defender),
			"%s does not reach 4000 wu (range %.0f wu)" % [p.display_name, p.range_wu])
		assert_null(FarTierCombat.engaged_target(shooter),
			"%s cannot engage at 4000 wu gap" % p.display_name)


func test_empty_missile_ammo_prevents_far_tier_ranged_fire() -> void:
	var attacker: Unit = _far_unit(1, Vector2(0.0, 450.0), Vector2.UP)
	var defender: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN)
	attacker.is_ranged = true
	attacker.equip_missile(LoadoutRegistry.MISSILE_JAVELIN)
	assert_true(FarTierRates.in_striking_range(attacker, defender), "javelin reaches 450 wu")

	attacker.missile_ammo = 0
	assert_false(attacker.has_missile_ammo(), "ammo is depleted")
	assert_false(FarTierRates.resolves_as_ranged(attacker, defender),
		"cannot resolve as ranged with 0 ammo")
	assert_false(FarTierRates.in_striking_range(attacker, defender),
		"out of striking range when ranged resolve fails and not in melee contact")
	assert_null(FarTierCombat.engaged_target(attacker),
		"cannot engage target when out of ammo at distance")


func test_far_tier_damage_scales_with_range_accuracy_falloff() -> void:
	var profile: MissileProfile = LoadoutRegistry.missile(LoadoutRegistry.MISSILE_SELF_BOW)
	# Defender at origin
	var defender: Unit = _far_unit(0, Vector2.ZERO, Vector2.DOWN)

	# Attacker near target, beyond melee contact (contact distance = 58 wu)
	var near_attacker: Unit = _far_unit(1, Vector2(0.0, 100.0), Vector2.UP)
	near_attacker.is_ranged = true
	near_attacker.equip_missile(LoadoutRegistry.MISSILE_SELF_BOW)

	# Attacker at max range
	var far_attacker: Unit = _far_unit(2, Vector2(0.0, profile.range_wu), Vector2.UP)
	far_attacker.is_ranged = true
	far_attacker.equip_missile(LoadoutRegistry.MISSILE_SELF_BOW)

	var near_rate: float = FarTierRates.casualty_rate(near_attacker, defender)
	var far_rate: float = FarTierRates.casualty_rate(far_attacker, defender)
	assert_gt(near_rate, far_rate, "closer shot deals higher casualty rate due to accuracy")

	# Ratio of strike expectations at max range vs near range matches accuracy ratio
	var exp_near: float = FarTierRates.strike_expectation(near_attacker, defender)
	var exp_far: float = FarTierRates.strike_expectation(far_attacker, defender)
	var expected_ratio: float = profile.accuracy(profile.range_wu) / profile.accuracy(100.0)
	assert_almost_eq(exp_far / exp_near, expected_ratio, TOL,
		"strike expectation scales with accuracy falloff")
