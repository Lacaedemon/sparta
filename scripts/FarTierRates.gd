class_name FarTierRates
extends RefCounted
## The far tier's attrition expectation, evaluated against two Units' OWN fields.
##
## FarTierRules holds the same arithmetic written against the standalone FarTierFormation
## record, which no live battle ever constructs; it stays as the isolated, unit-testable
## reference model. This is the live twin, shaped so the resolution step (FarTierCombat)
## can read a real regiment without building a shadow record for it each tick.
## test_far_tier_combat.gd pins the two against each other so they cannot drift.
##
## The model is UnitCombat.strike/shoot's own regiment formula with the seeded damage roll
## replaced by its mean of 1.0, so this file draws no RNG at all. Fatigue, cohesion, and
## the order-mode modifiers are deliberately omitted, exactly as FarTierRules omits them:
## the far tier reads them at their fresh defaults.


## Remaining-strength ratio in [0, 1] -- the Lanchester-style thinning term. The Unit-field
## twin of FarTierRules.strength_ratio (count / max_soldiers on the record).
static func strength_ratio(u: Unit) -> float:
	if u.max_soldiers <= 0:
		return 0.0
	return clampf(float(u.soldiers) / float(u.max_soldiers), 0.0, 1.0)


## This attacker's own strike cadence in seconds: Unit.RANGED_INTERVAL for a ranged
## formation, else its equipped weapon's melee interval (Unit.melee_attack_interval, which
## already falls back to Unit.ATTACK_INTERVAL when no weapon type is equipped). Reading the
## unit's own cadence rather than the bare const is the one place this is MORE faithful to
## the close tier than FarTierRules can be -- Unit._think spends melee_attack_interval()
## per strike, and the record carries no weapon.
static func attack_interval(attacker: Unit) -> float:
	return Unit.RANGED_INTERVAL if attacker.is_ranged else attacker.melee_attack_interval()


## How far this attacker reaches, in world units: Unit.RANGED_RANGE for a ranged formation,
## else its own melee reach plus both regiment radii -- the same contact distance
## Unit._think computes. Unit.RADIUS is a shared const, so this equals
## FarTierRules.in_striking_range's attack_range + RADIUS * 2.
static func striking_reach(attacker: Unit, defender: Unit) -> float:
	if attacker.is_ranged:
		return Unit.RANGED_RANGE
	return attacker.attack_range + Unit.RADIUS + defender.RADIUS


## Whether the attacker's centroid is close enough to strike the defender's.
static func in_striking_range(attacker: Unit, defender: Unit) -> bool:
	var reach: float = striking_reach(attacker, defender)
	# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
	return attacker.position.distance_squared_to(defender.position) <= reach * reach


## Expected casualties from ONE strike at the mean damage roll: UnitCombat.strike's formula
## path -- max(1, effective attack - defense) -- then the defender's stance blunting. A
## ranged attacker mirrors UnitCombat.shoot instead: no melee-stance offence penalty (a
## testudo still looses volleys head-up), Unit.RANGED_DAMAGE_FACTOR applied, and
## missile_defense_factor rather than melee_defense_factor. Flanking and the attacker's
## thinning scale the RATE, not the strike, so they live in casualty_rate below.
static func strike_expectation(attacker: Unit, defender: Unit) -> float:
	if attacker.is_ranged:
		var eff_ranged: float = float(attacker.attack) * attacker.formation_attack_factor()
		var ranged_base: float = maxf(1.0, eff_ranged - float(defender.defense)) \
				* Unit.RANGED_DAMAGE_FACTOR
		return ranged_base * defender.missile_defense_factor(attacker)
	var eff_attack: float = float(attacker.attack) \
			* attacker.formation_attack_factor() * attacker.formation_melee_attack_factor()
	var base: float = maxf(1.0, eff_attack - float(defender.defense))
	return base * defender.melee_defense_factor(attacker)


## Expected casualties per second the attacker inflicts on the defender: one expected
## strike per attack_interval, scaled by the defender's flank exposure through
## UnitCombat.flank_multiplier -- the very function the close tier uses, so a square's
## all-around defence and a rear blow's doubling are one implementation, not two.
##
## A MELEE attacker is also scaled by its remaining-strength ratio: a thinned line presents
## less fighting frontage, which is what gives the aggregate its Lanchester-style curve and
## keeps it consistent with the close tier's per-soldier melee. A RANGED attacker is exempt,
## because UnitCombat.shoot draws volley damage from the flat attack stat with no
## soldier-count scaling -- a gutted archer regiment volleys as hard as a full one, and the
## far tier must match that to stay a faithful mirror.
static func casualty_rate(attacker: Unit, defender: Unit) -> float:
	var interval: float = attack_interval(attacker)
	if interval <= 0.0:
		return 0.0
	var thinning: float = 1.0 if attacker.is_ranged else strength_ratio(attacker)
	return strike_expectation(attacker, defender) \
			* UnitCombat.flank_multiplier(defender, attacker) \
			* thinning / interval
