class_name FarTierCombat
extends RefCounted
## Live far-tier combat resolution: the per-tick step that lets a demoted formation
## actually exchange casualties, lose morale, and break (Battle._tick_far_tier_combat).
##
## FarTierRates supplies the expectation math; this file books the result through
## UnitCombat.register_casualties, the entry point the close tier's regiment-formula path
## already uses. So morale erosion, the thin-regiment crumble, Unit._die(), and Unit._rout()
## (with its contagion shockwave over nearby friendlies) stay ONE implementation shared by
## both tiers, rather than a second morale/rout state machine kept in sync by hand. Facing,
## movement, targeting, and the FIGHTING state are NOT reimplemented here -- Unit._think
## drives all of them tier-agnostically. Only casualty resolution moves, and
## UnitCombat.strike/shoot return early for a far-tier attacker so one fight is never billed
## by both paths. Deterministic and RNG-free.


## Whether `u` can deal far-tier attrition: far-tier, alive, manned, and not itself routing.
## Mirrors FarTierRules.can_fight against Unit's state machine rather than a `routing` flag.
static func can_fight(u: Unit) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	return u.tier == FormationTier.FAR and u.soldiers > 0 \
			and u.state != Unit.State.DEAD and u.state != Unit.State.ROUTING


## Whether `target` can still absorb casualties. A ROUTING target deliberately qualifies:
## UnitCombat.take_casualties makes the same call at close tier -- fleeing grants no
## immunity, a broken formation can still be run down.
static func can_be_struck(target: Unit) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return target.state != Unit.State.DEAD and target.soldiers > 0


## The formation this one resolves against this tick, or null when it is not fighting one.
## Reuses the ordinary targeting path (UnitTargeting.current_target: an explicitly ordered
## target_enemy, else auto-acquisition inside the unit's own detection_range), so the far
## tier adds no second targeting concept and winner pursuit arrives through UnitLeader's
## existing retargeting, unchanged.
##
## Gated on the unit already being in State.FIGHTING, which is what inherits the close tier's
## own two gates rather than reimplementing either. Unit._think enters FIGHTING only when its
## disengage rule allows -- in contact AND (an explicit target, or no move order, or CHASE,
## or MARCH_TO_CONTACT) -- so a plain move order past a broken enemy marches by instead of
## grinding it down, exactly as at close tier. is_maneuver_turning() then withholds attrition
## while the men are mid-arc, mirroring _face_for_action holding the strike until the front
## is brought to bear. Since Battle resolves this before the units act, both read LAST tick's
## state, so attrition starts one tick after contact -- cheaper than the close tier's own
## attack cooldown, and the same direction.
static func engaged_target(u: Unit) -> Unit:
	if not can_fight(u) or not u.is_inside_tree():
		return null
	if u.state != Unit.State.FIGHTING or u.is_maneuver_turning():
		return null
	var target: Unit = UnitTargeting.current_target(u)
	if not can_be_struck(target) or not FarTierRates.in_striking_range(u, target):
		return null
	return target


## Apply `rate` casualties-per-second to `defender` for one `delta`: accumulate the
## fractional expectation in the defender's own carry and book whole soldiers as they
## complete, so totals over any span match rate * time regardless of tick size. The
## subtraction happens here and the CONSEQUENCES go through register_casualties -- that
## function's own documented contract, and the split UnitCombat.take_casualties uses.
## `morale_flank` rides along as take_casualties passes it, so a later non-zero
## UnitCombat.REAR_MORALE_EXTRA reaches both tiers alike. Returns casualties applied.
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


## The live per-tick pass: one tick of attrition for every far-tier formation in `units`
## with a target in striking range. Every rate is read from the PRE-tick state before any
## casualty is booked, so an exchange stays simultaneous -- neither side's thinning term
## sees the other's losses first, and a mirrored matchup stays exactly symmetric. That is
## FarTierRules.tick_pair's two-body guarantee generalized to however many formations are on
## the field, which is why no pair-orchestration layer is needed. Application order is the
## caller's iteration order (Battle's tree order), so the pass is replay-deterministic.
static func tick_all(units: Array, delta: float) -> int:
	var plans: Array = []
	for node in units:
		var u: Unit = node as Unit
		if u == null:
			continue
		var target: Unit = engaged_target(u)
		if target == null:
			continue
		# One flank reading, used by both the casualty rate and the morale bookkeeping.
		# Computing it twice would let the two drift apart silently, since
		# UnitCombat.REAR_MORALE_EXTRA is 0.0 today and hides the morale half entirely.
		var flank: float = UnitCombat.flank_multiplier(target, u)
		plans.append({"attacker": u, "defender": target, "flank": flank,
			"rate": FarTierRates.casualty_rate(u, target, -1.0, flank)})
	var booked: int = 0
	for plan in plans:
		var attacker: Unit = plan["attacker"]
		var defender: Unit = plan["defender"]
		# A defender wiped out by an EARLIER plan this tick is no longer a target; one that
		# merely broke still is (see can_be_struck).
		if not is_instance_valid(attacker) or not can_be_struck(defender):
			continue
		booked += apply_attrition(defender, attacker, plan["rate"], delta, plan["flank"])
	return booked
