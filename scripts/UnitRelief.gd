class_name UnitRelief
## Line-relief swaps for a Unit, extracted from Unit.gd: a fresh regiment takes over an
## engaged friendly's fight while the tired one peels back to the rear. The swap's
## execution state lives on the reliever's RELIEF order (Order.friendly_target, a generic
## pass-through link any order type can arm): the pair is mutually exempt from separation
## while the link is live (Unit._separation_exempt checks it from either side), so they
## pass through each other during the swap, and the exemption clears once they're apart --
## or dies with the order on an interrupt, since the order owns it. While the link is live
## both blocks also widen their back-rank slot spacing (Unit._apply_relief_corridor_to_slots)
## so the partner's front line can march between without intra-unit overlap. The tired unit
## gets a plain MOVE order for its retreat -- marched with its facing held, so it backs out
## of the line still fronting the enemy -- so both sides of the swap read straight off the
## queue. Static helpers on the unit -- deterministic (positions / state only, no RNG), so
## live play and replay swap identically. RELIEF is just one consumer of the generic
## friendly_target link and its Order.resolve_friendly_target helper (see Order.gd); this
## file only adds the RELIEF-specific swap behavior (targeting takeover + retreat order).


## Begin relieving an engaged friendly: `u` (fresh) takes over `tired`'s fight and
## advances, `tired` peels back to the rear. `order` is u's RELIEF order, already made
## current by the caller (Battle's apply site, so live play and replay share one path);
## the swap link is armed on it here. A self-relief is refused -- the link never arms, so
## the no-op order retires on the next bookkeeping pass.
static func begin(u: Unit, tired: Unit, order: Order) -> void:
	if tired == u:
		return   # a unit can't relieve itself
	order.friendly_target = tired
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
	# Back out of the line facing the enemy rather than turning tail: a relieved regiment
	# withdraws as a fighting body, the same drill Unit.disengage uses for a step back. The
	# mechanism is the held facing itself -- a non-zero ordered_facing puts the retreat in
	# _move_to's "maneuvering" branch, which holds the heading instead of pivoting toward
	# travel and walks the whole leg. Without it the block pivots 180 deg toward its
	# destination, and the turn-before-march clamp (facing.dot(steer_dir) * 2) zeroes the
	# advance while it does, so the slot grid sweeps through a half-turn the bodies cannot
	# track -- the men scramble across the block and the formation reads as a blob for the
	# rest of the retreat. Arrival clears the hold (Unit._think's move bookkeeping, where
	# every other maneuver hold is dropped too), so it lives exactly as long as this leg.
	tired.ordered_facing = tired.facing


## A point toward `u`'s own back edge -- where a relieved unit retreats to.
static func _rear_point(u: Unit) -> Vector2:
	var back: Vector2 = Vector2.UP if u.team == 0 else Vector2.DOWN
	return u.position + back * 160.0


## Resolve the pass-through link once the partner has left the line (gone, dead, or
## routing) or the swapping pair has moved clear of each other. Runs on the reliever's
## tick only -- the tired side holds no state. Delegates the actual clearing (and its
## soldier_block_extent-aware distance check) to Order.resolve_friendly_target, the
## generic helper any order type carrying a friendly_target link can reuse; clearing it
## disarms the separation exemption for both sides and lets the RELIEF order retire
## (see Unit._update_current_order).
static func update(u: Unit) -> void:
	var order: Order = u.current_order
	if order == null or order.type != Order.Type.RELIEF:
		return
	Order.resolve_friendly_target(u)
