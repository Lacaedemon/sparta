class_name FarTierCombat
extends RefCounted
## Live far-tier combat resolution: the per-tick step that lets a demoted formation
## actually exchange casualties, lose morale, and break (Battle._tick_far_tier_combat).
##
## FarTierRates supplies the expectation math; this file books the result through
## UnitCombat.register_casualties, the entry point the close tier's regiment formula already
## uses, so morale erosion, the crumble, Unit._die(), and Unit._rout() (with its contagion
## shockwave) stay ONE implementation across both tiers. Only casualty resolution moves here:
## _think still drives facing, movement, targeting and FIGHTING, and UnitCombat.strike/shoot
## decline for a far-tier attacker so no fight is billed twice.


## Whether `u` can deal far-tier attrition: far-tier, alive, manned, and not itself routing.
## Mirrors FarTierRules.can_fight against Unit's state machine rather than a `routing` flag.
static func can_fight(u: Unit) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	return u.tier == FormationTier.FAR and u.soldiers > 0 and u.state != Unit.State.DEAD \
			and u.state != Unit.State.ROUTING


## Whether `target` can absorb casualties. A ROUTING one qualifies, as take_casualties has it
## at close tier: fleeing grants no immunity. A DEAD or emptied one does not.
static func can_be_struck(target: Unit) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return target.state != Unit.State.DEAD and target.soldiers > 0


## The formation this one resolves against this tick, or null when it is not fighting one.
## Reuses the ordinary targeting path (UnitTargeting.current_target), so the far tier adds no
## second targeting concept and winner pursuit arrives through UnitLeader's own retargeting.
## The FIGHTING gate matches _think's own: it enters FIGHTING only when its disengage rule
## allows, so a plain move order past a broken enemy marches by instead of grinding it down.
## The turning gate is deliberately STRICTER. _think's is _face_for_action's return, which
## permits a strike once the heading is within ENGAGE_TURN_FIGHT_TOLERANCE (50 deg) with
## _engage_turn_target still armed; is_maneuver_turning() holds through the whole arc, and
## through order turns and wheels _think never consults. That and reading last tick's state
## (Battle resolves this first) err alike: attrition is UNDER-booked, never double-booked.
static func engaged_target(u: Unit) -> Unit:
	if not can_fight(u) or not u.is_inside_tree():
		return null
	if u.state != Unit.State.FIGHTING or u.is_maneuver_turning():
		return null
	var target: Unit = UnitTargeting.current_target(u)
	if not can_be_struck(target) or not FarTierRates.in_striking_range(u, target):
		return null
	return target


## Apply `rate` casualties-per-second to `defender` for one `delta`: accumulate the fraction
## in the defender's own carry and book whole soldiers as they complete, so totals over any
## span match rate * time regardless of tick size. The subtraction happens here and the
## CONSEQUENCES go through register_casualties, its own contract and take_casualties' split.
static func apply_attrition(defender: Unit, attacker: Unit, rate: float, delta: float,
		morale_flank: float = 1.0) -> int:
	defender._far_tier_casualty_carry += rate * delta
	var whole: int = int(defender._far_tier_casualty_carry)
	if whole <= 0:
		return 0
	defender._far_tier_casualty_carry -= float(whole)
	var applied: int = clampi(whole, 0, defender.soldiers)
	if applied <= 0:
		return 0
	defender.soldiers -= applied
	UnitCombat.register_casualties(defender, applied, attacker, morale_flank)
	return applied


## The live per-tick pass: one tick of attrition for every far-tier formation in `units` with
## a target in striking range. Every rate is read from the PRE-tick state before any casualty
## is booked, so an exchange stays simultaneous -- FarTierRules.tick_pair's two-body guarantee
## generalized to the whole field. Application order is the caller's (Battle's tree order),
## so the pass is replay-deterministic.
static func tick_all(units: Array, delta: float) -> int:
	var plans: Array = []
	for node in units:
		var u: Unit = node as Unit
		if u == null:
			continue
		var target: Unit = engaged_target(u)
		if target == null:
			continue
		# ONE flank reading, feeding both the casualty rate and the morale bookkeeping.
		# Reading it twice would let the two drift with nothing to catch it, since
		# UnitCombat.REAR_MORALE_EXTRA is 0.0 today and hides the morale half entirely.
		var flank: float = UnitCombat.flank_multiplier(target, u)
		plans.append({"attacker": u, "defender": target, "flank": flank,
			"rate": FarTierRates.casualty_rate(u, target, -1.0, flank)})
	var booked: int = 0
	for plan in plans:
		var attacker: Unit = plan["attacker"]
		var defender: Unit = plan["defender"]
		# A defender wiped out by an EARLIER plan is no longer a target; one that merely
		# broke still is (see can_be_struck).
		if not is_instance_valid(attacker) or not can_be_struck(defender):
			continue
		booked += apply_attrition(defender, attacker, plan["rate"], delta, plan["flank"])
	return booked
