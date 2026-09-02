class_name FarTierCombat
extends RefCounted
## Live far-tier combat resolution: the per-tick step that lets a demoted formation
## actually exchange casualties, lose morale, and break (Battle._tick_far_tier_combat).
##
## The FLOW half: who is fighting whom, and in what order their attrition resolves.
## FarTierRates supplies the expectation math and FarTierAttrition books the casualties
## (through UnitCombat.register_casualties, so morale erosion, the crumble, Unit._die() and
## Unit._rout() stay one shared implementation). Only casualty resolution moved to the far
## tier at all: _think still drives facing, movement, targeting and FIGHTING, and
## UnitCombat.strike/shoot decline for a far-tier attacker so no fight is billed twice.

# Reused plan buffers for tick_all, cleared per call -- see its own doc comment. Static, so
# one battle's pass never allocates; the class is never instanced.
static var _attackers: Array[Unit] = []
static var _defenders: Array[Unit] = []
static var _rates := PackedFloat64Array()
static var _flanks := PackedFloat64Array()


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


## The live per-tick pass: one tick of attrition for every far-tier formation in `units` with
## a target in striking range. Every rate is read from the PRE-tick state before any casualty
## is booked, so an exchange stays simultaneous -- FarTierRules.tick_pair's two-body guarantee
## generalized to the whole field. Application order is the caller's (Battle's tree order),
## so the pass is replay-deterministic.
##
## The plan is four REUSED parallel buffers rather than a Dictionary per engaged formation:
## the pass runs every tick for the life of a battle, so a per-unit allocation would be pure
## churn. Float64 (not 32) keeps the stored rate bit-identical to the value that computed it,
## which replay determinism depends on.
static func tick_all(units: Array, delta: float) -> int:
	_attackers.clear()
	_defenders.clear()
	_rates.clear()
	_flanks.clear()
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
		_attackers.append(u)
		_defenders.append(target)
		_rates.append(FarTierRates.casualty_rate(u, target, -1.0, flank))
		_flanks.append(flank)
	var booked: int = 0
	for i in range(_attackers.size()):
		var attacker: Unit = _attackers[i]
		var defender: Unit = _defenders[i]
		# A defender wiped out by an EARLIER plan is no longer a target; one that merely
		# broke still is (see can_be_struck).
		if not is_instance_valid(attacker) or not can_be_struck(defender):
			continue
		booked += FarTierAttrition.apply(defender, attacker, _rates[i], delta, _flanks[i])
	return booked
