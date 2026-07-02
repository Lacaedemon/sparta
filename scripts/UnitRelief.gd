class_name UnitRelief
## Line-relief swaps for a Unit, extracted from Unit.gd: a fresh regiment takes over an
## engaged friendly's fight while the tired one peels back to the rear. The swap's
## execution state lives on the reliever's RELIEF order (Order.relief_partner): the pair
## is mutually exempt from separation while the link is live (Unit._separation_exempt
## checks it from either side), so they pass through each other during the swap, and the
## exemption clears once they're apart -- or dies with the order on an interrupt, since
## the order owns it. The tired unit gets a plain MOVE order for its retreat, so both
## sides of the swap read straight off the queue. Static helpers on the unit --
## deterministic (positions / state only, no RNG), so live play and replay swap
## identically.


## Begin relieving an engaged friendly: `u` (fresh) takes over `tired`'s fight and
## advances, `tired` peels back to the rear. `order` is u's RELIEF order, already made
## current by the caller (Battle's apply site, so live play and replay share one path);
## the swap link is armed on it here. A self-relief is refused -- the link never arms, so
## the no-op order retires on the next bookkeeping pass.
static func begin(u: Unit, tired: Unit, order: Order) -> void:
	if tired == u:
		return   # a unit can't relieve itself
	order.relief_partner = tired
	# Take over the tired unit's fight so the front isn't left open. A unit can be
	# FIGHTING an auto-acquired foe with target_enemy still null, so fall back to its
	# nearest enemy rather than just walking onto an empty slot.
	var foe: Unit = tired.target_enemy
	if foe == null:
		foe = UnitTargeting.nearest_enemy(tired)
	u.target_enemy = foe
	if foe != null:
		u.has_move_target = false
	else:
		u.move_target = tired.position   # truly no foe: advance onto its slot
		u.has_move_target = true
	# Tired unit disengages and falls back toward its own back edge -- a real MOVE order,
	# so the retreat is queue-visible like any other march, and it replaces (interrupts)
	# whatever the tired unit was doing, including a stale relief of its own.
	tired.target_enemy = null
	var retreat := Order.new_move(_rear_point(tired))
	tired.set_current_order(retreat)
	tired.move_target = retreat.target_pos
	tired.has_move_target = true


## A point toward `u`'s own back edge -- where a relieved unit retreats to.
static func _rear_point(u: Unit) -> Vector2:
	var back: Vector2 = Vector2.UP if u.team == 0 else Vector2.DOWN
	return u.position + back * 160.0


## Resolve the pass-through link once the partner has left the line (gone, dead, or
## routing) or the swapping pair has moved clear of each other. Runs on the reliever's
## tick only -- the tired side holds no state -- and clears Order.relief_partner, which
## disarms the separation exemption for both sides and lets the RELIEF order retire
## (see Unit._update_current_order).
static func update(u: Unit) -> void:
	var order: Order = u.current_order
	if order == null or order.type != Order.Type.RELIEF or order.relief_partner == null:
		return
	var partner: Unit = order.relief_partner
	var gone: bool = not is_instance_valid(partner) \
		or partner.state == Unit.State.DEAD \
		or partner.state == Unit.State.ROUTING
	var apart: bool = is_instance_valid(partner) \
		and u.position.distance_to(partner.position) \
			> u.separation_radius + partner.separation_radius + 24.0
	if gone or apart:
		order.relief_partner = null
