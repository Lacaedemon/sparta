class_name FarTierAttrition
extends RefCounted
## Booking far-tier casualties onto a defender: the EFFECT half of far-tier combat, split
## from FarTierCombat (the per-tick flow) and FarTierRates (the expectation math) so each new
## file stays inside tools/check.sh file_length's 100-line cap.
##
## The far tier's attrition is a continuous rate, so most ticks owe a defender some FRACTION
## of a casualty. That fraction accumulates in the defender's own carry until it completes a
## whole soldier, which is what makes the totals over any span match rate * time exactly
## rather than rounding away tick by tick.


## Apply `rate` casualties-per-second to `defender` for one `delta`. The subtraction happens
## here and the CONSEQUENCES go through UnitCombat.register_casualties -- that function's own
## documented contract, and the same split UnitCombat.take_casualties uses, so morale
## erosion, the crumble, Unit._die() and Unit._rout() stay one shared implementation.
## `morale_flank` rides along exactly as take_casualties passes it, so a later non-zero
## UnitCombat.REAR_MORALE_EXTRA reaches both tiers alike. Returns casualties applied.
static func apply(defender: Unit, attacker: Unit, rate: float, delta: float,
		morale_flank: float = 1.0) -> int:
	defender._far_tier_casualty_carry += rate * delta
	var whole: int = int(defender._far_tier_casualty_carry)
	if whole <= 0:
		return 0
	defender._far_tier_casualty_carry -= float(whole)
	# Clamped to the living: a tick whose accumulated fraction outruns the survivors books
	# the survivors and no more, rather than driving `soldiers` negative.
	var applied: int = clampi(whole, 0, defender.soldiers)
	if applied <= 0:
		return 0
	defender.soldiers -= applied
	UnitCombat.register_casualties(defender, applied, attacker, morale_flank)
	return applied
