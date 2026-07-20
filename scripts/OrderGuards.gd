class_name OrderGuards
## Phase 4 of the unified orders-queue design (docs/orders-queue-design.md): evaluation for
## the bounded, enumerated guard vocabulary (Order.Guard). Each guard is a PURE function of
## already-serialized Unit/sim state -- positions, facing, morale, fatigue, and the order's
## own elapsed-tick counter -- with no RNG and no wall-clock read, so a guarded order
## produces the identical branch on replay as it did live (the design doc's determinism
## invariant). `satisfied()` is the single entry point Unit._update_current_order calls;
## the per-guard helpers below are exposed separately so they're directly unit-testable
## without constructing a live Order.


## True once `order`'s guard condition holds for `u`. Guard.NONE (the default -- an
## unguarded order) is never satisfied, so it never short-circuits an order's own ordinary
## completion path.
static func satisfied(u: Unit, order: Order) -> bool:
	match order.guard:
		Order.Guard.NONE:
			return false
		Order.Guard.ENEMY_IN_RANGE:
			return enemy_in_range(u, order.guard_param)
		Order.Guard.CONTACT_MADE:
			return contact_made(u)
		Order.Guard.MORALE_BELOW:
			return morale_below(u, order.guard_param)
		Order.Guard.ALLY_EXHAUSTED:
			return ally_exhausted(u, order.guard_uid, order.guard_param)
		Order.Guard.TICKS_ELAPSED:
			return ticks_elapsed(order, order.guard_param)
		Order.Guard.FLANKED:
			return flanked(u, order.guard_param)
		_:
			return false


## A live, non-routing enemy is within `range_units` of `u`. range_units <= 0 falls back to
## u's own detection_range (a caller-configurable field, default Unit.DETECTION_RANGE).
## Unlike combat auto-acquisition (UnitTargeting.nearest_enemy), this guard does NOT count a
## routing enemy --- it gates order transitions ("enemy sighted"), where a fleeing regiment
## isn't the kind of threat that should re-trigger a scripted order.
static func enemy_in_range(u: Unit, range_units: float) -> bool:
	var radius: float = range_units if range_units > 0.0 else u.detection_range
	return UnitTargeting.nearest_enemy_to(u, u.position, radius) != null


## A live, non-routing enemy is within melee contact distance: u's attack_range plus both
## units' radii. Distinct from enemy_in_range -- contact is a fixed geometric distance, not
## a caller-chosen radius.
static func contact_made(u: Unit) -> bool:
	for o in u.get_tree().get_nodes_in_group("units"):
		var other: Unit = o as Unit
		if other == null or other.team == u.team:
			continue
		if other.state == Unit.State.DEAD or other.state == Unit.State.ROUTING:
			continue
		var contact: float = u.attack_range + Unit.RADIUS + other.RADIUS
		if u.position.distance_to(other.position) <= contact:
			return true
	return false


## u's own morale has fallen below `threshold`.
static func morale_below(u: Unit, threshold: float) -> bool:
	return u.morale < threshold


## The friendly unit named by `ally_uid` has fatigue at or above `threshold`. False if the
## ally can't be resolved (uid unset, dead, or no longer on the field) -- an exhausted ally
## that has left play can no longer trigger a relief-style handoff.
static func ally_exhausted(u: Unit, ally_uid: int, threshold: float) -> bool:
	if ally_uid < 0:
		return false
	for o in u.get_tree().get_nodes_in_group("units"):
		var ally: Unit = o as Unit
		if ally != null and ally.uid == ally_uid:
			return ally.state != Unit.State.DEAD and ally.fatigue >= threshold
	return false


## `ticks` physics ticks have elapsed since `order` became current (order._guard_ticks,
## advanced once per tick by Unit._think). Guards against a non-positive parameter reading
## as "already elapsed" on the very first tick.
static func ticks_elapsed(order: Order, ticks: float) -> bool:
	return ticks > 0.0 and order._guard_ticks >= int(ticks)


## A live, non-routing enemy currently stands in u's flank/rear arc (the same dot-product
## geometry UnitCombat.flank_multiplier strikes with) within `range_units` of u.
## range_units <= 0 falls back to melee contact distance, matching contact_made's default
## reach. A unit in the anti-cavalry square has no exploitable flank (flank_multiplier
## always reads frontal for it), so it can never be FLANKED.
static func flanked(u: Unit, range_units: float) -> bool:
	if u.in_square():
		return false
	var radius: float = range_units if range_units > 0.0 else (u.attack_range + Unit.RADIUS * 2.0)
	for o in u.get_tree().get_nodes_in_group("units"):
		var other: Unit = o as Unit
		if other == null or other.team == u.team:
			continue
		if other.state == Unit.State.DEAD or other.state == Unit.State.ROUTING:
			continue
		if u.position.distance_to(other.position) > radius:
			continue
		if UnitCombat.flank_multiplier(u, other) > 1.0:
			return true
	return false
