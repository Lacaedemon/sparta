class_name FarTierRates
extends RefCounted
## The far tier's attrition expectation, evaluated against two Units' OWN fields.
##
## FarTierRules holds the same arithmetic against the standalone FarTierFormation record,
## which no live battle constructs; it stays the isolated reference model. This is the live
## twin, so FarTierCombat reads a real regiment without building a shadow record each tick.
##
## The model is UnitCombat.strike/shoot's regiment formula with the seeded damage roll
## replaced by its mean of 1.0, so this file draws no RNG. Also dropped, for phase-0 parity
## with FarTierRules: fatigue, cohesion, and the order-mode modifiers. The RECORD lacks those
## fields; the live Unit here CARRIES them -- fatigue accrues the whole time a unit is
## FIGHTING, cohesion sits below 1.0 after a merge -- so dropping them is a real divergence,
## not a read at fresh defaults. Fatigue and cohesion only ever cut output, so a fatigued or
## freshly-merged far-tier attacker hits HARDER than its close-tier twin; the order-mode
## modifiers cut both ways. UnitCombat.charge_multiplier and pin_down_defense_factor are
## dropped on their own grounds: per-CONTACT, per-SWING quantities with no meaning for a rate.


## Remaining-strength ratio in [0, 1] -- the Lanchester-style thinning term, and the
## Unit-field twin of FarTierRules.strength_ratio (count / max_soldiers on the record).
static func strength_ratio(u: Unit) -> float:
	if u.max_soldiers <= 0:
		return 0.0
	return clampf(float(u.soldiers) / float(u.max_soldiers), 0.0, 1.0)


## Centroid distance at which the two regiments are in melee contact: the attacker's reach
## plus both radii, the figure Unit._think computes and FarTierRules' attack_range + RADIUS*2.
static func melee_contact_distance(attacker: Unit, defender: Unit) -> float:
	return attacker.attack_range + Unit.RADIUS + defender.RADIUS


## Whether this exchange resolves as a volley rather than as melee. Mirrors Unit._think,
## whose ranged branch is gated on `not in_contact`: once melee contact closes, an archer
## regiment falls through to the melee branch and UnitCombat.strike. FarTierRules has no such
## rule, so this deliberately diverges from it for a ranged attacker in contact.
static func resolves_as_ranged(attacker: Unit, defender: Unit) -> bool:
	if not attacker.is_ranged:
		return false
	var contact: float = melee_contact_distance(attacker, defender)
	# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
	return attacker.position.distance_squared_to(defender.position) > contact * contact


## Strike cadence in seconds: Unit.RANGED_INTERVAL for a volley, else the equipped weapon's
## melee interval (Unit.melee_attack_interval, itself falling back to Unit.ATTACK_INTERVAL --
## MORE faithful than FarTierRules can be, since no weapon rides on the record).
static func attack_interval(attacker: Unit, defender: Unit) -> float:
	if resolves_as_ranged(attacker, defender):
		return Unit.RANGED_INTERVAL
	return attacker.melee_attack_interval()


## How far this attacker reaches, in world units.
static func striking_reach(attacker: Unit, defender: Unit) -> float:
	if resolves_as_ranged(attacker, defender):
		return Unit.RANGED_RANGE
	return melee_contact_distance(attacker, defender)


## Whether the attacker's centroid is close enough to strike the defender's.
static func in_striking_range(attacker: Unit, defender: Unit) -> bool:
	var reach: float = striking_reach(attacker, defender)
	# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
	return attacker.position.distance_squared_to(defender.position) <= reach * reach


## Expected casualties from ONE strike at the mean damage roll: max(1, effective attack -
## defense), then the defender's stance blunting. A volley mirrors UnitCombat.shoot instead:
## no melee-stance offence penalty, Unit.RANGED_DAMAGE_FACTOR applied, missile_defense_factor
## rather than melee_defense_factor. Flanking and thinning scale the RATE, so they live below.
static func strike_expectation(attacker: Unit, defender: Unit) -> float:
	if resolves_as_ranged(attacker, defender):
		var eff_ranged: float = float(attacker.attack) * attacker.formation_attack_factor()
		var ranged_base: float = maxf(1.0, eff_ranged - float(defender.defense)) \
				* Unit.RANGED_DAMAGE_FACTOR
		return ranged_base * defender.missile_defense_factor(attacker)
	var eff_attack: float = float(attacker.attack) \
			* attacker.formation_attack_factor() * attacker.formation_melee_attack_factor()
	var base: float = maxf(1.0, eff_attack - float(defender.defense))
	return base * defender.melee_defense_factor(attacker)


## Expected casualties per second: one expected strike per attack_interval, scaled by the
## defender's flank exposure (UnitCombat.flank_multiplier -- the close tier's own function).
## A MELEE exchange also scales by the attacker's remaining-strength ratio; a volley does
## not, since UnitCombat.shoot has no soldier-count scaling. `interval` and `flank` override
## the derived values, negative deriving each, so a caller holding a computed multiplier
## passes it rather than paying twice; a non-positive cadence yields no attrition.
static func casualty_rate(attacker: Unit, defender: Unit, interval: float = -1.0,
		flank: float = -1.0) -> float:
	var cadence: float = attack_interval(attacker, defender) if interval < 0.0 else interval
	if cadence <= 0.0:
		return 0.0
	var exposure: float = UnitCombat.flank_multiplier(defender, attacker) if flank < 0.0 \
			else flank
	var thinning: float = 1.0 if resolves_as_ranged(attacker, defender) \
			else strength_ratio(attacker)
	return strike_expectation(attacker, defender) * exposure * thinning / cadence
