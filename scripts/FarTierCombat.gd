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
##
## Perception-gated to match the near tier's OWN melee-vs-ranged split exactly (Unit._think,
## ~line 2832): MELEE combat already in progress is unconditionally exempt, matching every
## other melee branch in this codebase (soldier-level combat stays unfogged once bodies are
## touching) -- but a RANGED/standoff exchange re-checks perception every tick regardless of
## whether target_enemy was already committed, because the near-tier ranged-fire branch does
## too (its own `_enemy_is_perceived(enemy)` check carries no "already committed" carve-out;
## only the melee/chase branch's `target_enemy != null` half is the disclosed exception).
## UnitTargeting.current_target also falls through to a bare, unfogged nearest_enemy() scan
## when u.target_enemy has died or gone invalid, and never persists that pick back to
## target_enemy -- so a FRESH melee pick is still exempt (mirrors the near-tier melee branch,
## which has no perception check at all, fresh or committed), while a FRESH ranged pick is
## covered by the same re-check every ranged tick already gets. That fresh pick is now RANKED
## with Unit.fresh_pick_allowed as current_target's own predicate (see the call below and
## UnitTargeting.nearest_enemy_to's doc comment): a closer enemy out of contact and
## unperceived no longer shadows a farther one already in contact (or perceived) out of
## consideration entirely -- it used to win the nearest-of-any pick regardless, leaving this
## function's own perception re-check just below to null it out even when a farther,
## engageable formation existed.
static func engaged_target(u: Unit) -> Unit:
	if not can_fight(u) or not u.is_inside_tree():
		return null
	if u.state != Unit.State.FIGHTING or u.is_maneuver_turning():
		return null
	# fresh_pick_allowed passed as a RANKING predicate (mirroring the near tier's own
	# current_target() call in Unit._think, ~line 2844): without it, a closer enemy this
	# gate would reject (out of contact, not perceived) wins the nearest-of-any ranking and
	# blocks a farther enemy already in contact (or perceived) from ever being considered --
	# the closer-hidden-shadows-farther-visible fog-of-war gap UnitTargeting.nearest_enemy_to's
	# own `predicate` parameter closes (see its doc comment). An ALREADY-live committed
	# target_enemy is unaffected either way (current_target returns it unfiltered, before
	# ever consulting the predicate).
	var target: Unit = UnitTargeting.current_target(u, Callable(u, "fresh_pick_allowed"))
	if target == null:
		return null
	if FarTierRates.resolves_as_ranged(u, target) and not u._enemy_is_perceived(target):
		return null
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
