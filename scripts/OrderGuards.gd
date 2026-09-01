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
		Order.Guard.ENGAGED_FRACTION_ABOVE:
			# Deliberately always false here -- this guard doesn't self-terminate on a
			# per-tick true/false read like every other one above. Cancelling the instant the
			# fraction crosses threshold would interrupt a fight already worth finishing; the
			# actual resume-vs-cancel decision happens once, at the disengage transition, via
			# Unit._resolve_disengage_move_order() -- see that function and this guard's own
			# enum doc comment in Order.gd.
			return false
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
		# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
		if u.position.distance_squared_to(other.position) <= contact * contact:
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
		# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
		if u.position.distance_squared_to(other.position) > radius * radius:
			continue
		if UnitCombat.flank_multiplier(u, other) > 1.0:
			return true
	return false


## The CURRENT fraction (0..1) of u's living soldiers (u.soldiers, not max_soldiers) that
## are actively engaged in melee contact -- measuring real per-soldier enemy contact and
## weapon reach against adjacent enemy soldiers, rather than a static formation-shape
## rank capacity. 0.0 whenever the unit has no living soldiers or is not in contact/engaged.
## Exposed as a raw value, not just a threshold test, so a caller
## (Unit._move_order_peak_engaged_fraction) can track its PEAK over time -- a point-in-time
## read alone can't tell "this fight got heavy, then eased off" from "this fight was always light",
## since both read 0.0 the instant the unit actually disengages.
##
## Evaluates perimeter and contact-candidate living soldiers of u against adjacent enemy
## units within contact range: a soldier counts as engaged if at least one living enemy soldier
## sits within their combined body radius plus weapon reach (max of either reach, matching
## reach-standoff semantics). For synthetic unit tests where u is marked fighting with no
## enemy units in tree, falls back to the formation-capacity ratio.
static func current_engaged_fraction(u: Unit) -> float:
	var total: int = u.soldiers
	if total <= 0:
		return 0.0
	if not (u.is_engaged() or u._in_enemy_contact):
		return 0.0

	# Find candidate enemy units in physical contact/striking range of u.
	var defenders: Array[Unit] = []
	var has_live_enemy_in_tree: bool = false
	if u.is_inside_tree():
		var candidates: Array = u._separation_candidates()
		for o in candidates:
			var other: Unit = o as Unit
			if other == null or other == u or other.team == u.team or other.state == Unit.State.DEAD:
				continue
			has_live_enemy_in_tree = true
			var contact: float = maxf(u.attack_range, other.attack_range) + Unit.RADIUS + other.RADIUS
			# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
			if u.position.distance_squared_to(other.position) <= contact * contact:
				defenders.append(other)

	# If live enemy units exist in the tree/candidate pool but none are within physical contact distance,
	# the unit has 0.0 soldiers actively in contact (e.g. disengaged during linger window).
	if has_live_enemy_in_tree:
		if defenders.is_empty():
			return 0.0
	else:
		# Synthetic single-unit test fixtures where u is marked fighting with no enemy units in tree.
		if u.is_engaged():
			var engaged_indices: PackedInt32Array = u.engaged_soldier_indices(total)
			return float(engaged_indices.size()) / float(total)
		return 0.0

	# Measure actual living soldiers in physical striking/contact reach of any adjacent enemy soldier.
	var r_u: float = u.soldier_body_radius()
	var reach_u: float = u.soldier_reach()
	var n_pos: int = u._sim_soldier_pos.size()
	if n_pos == 0:
		var engaged_indices: PackedInt32Array = u.engaged_soldier_indices(total)
		return float(engaged_indices.size()) / float(total)

	var u_live: int = mini(total, n_pos)
	var u_candidates: PackedInt32Array = u.contact_soldier_indices(u_live)
	if u_candidates.is_empty():
		u_candidates = u.engaged_soldier_indices(u_live)
	if u_candidates.is_empty():
		return 0.0

	# Pre-gather invariant defender candidate data before iterating querier soldiers
	var d_max_dist_sq: PackedFloat32Array = PackedFloat32Array()
	var d_cand_list: Array[PackedInt32Array] = []
	var d_pos_list: Array[PackedVector2Array] = []
	var d_hp_list: Array[PackedFloat32Array] = []
	for d in defenders:
		var d_n_pos: int = d._sim_soldier_pos.size()
		if d_n_pos == 0:
			continue
		var d_live: int = mini(d.soldiers, d_n_pos)
		var d_candidates: PackedInt32Array = d.contact_soldier_indices(d_live)
		if d_candidates.is_empty():
			d_candidates = d.engaged_soldier_indices(d_live)
		if d_candidates.is_empty():
			continue
		var r_d: float = d.soldier_body_radius()
		var reach_d: float = d.soldier_reach()
		var max_dist: float = r_u + r_d + maxf(reach_u, reach_d)
		d_max_dist_sq.push_back(max_dist * max_dist)
		d_cand_list.append(d_candidates)
		d_pos_list.append(d._sim_soldier_pos)
		d_hp_list.append(d._sim_soldier_hp)

	var n_defenders: int = d_cand_list.size()
	if n_defenders == 0:
		return 0.0

	var in_reach_count: int = 0
	for i in u_candidates:
		if i < u._sim_soldier_hp.size() and u._sim_soldier_hp[i] <= 0.0:
			continue
		var p_u: Vector2 = u._sim_soldier_pos[i]
		var soldier_engaged: bool = false
		for k in range(n_defenders):
			var max_dist_sq: float = d_max_dist_sq[k]
			var d_candidates: PackedInt32Array = d_cand_list[k]
			var d_pos: PackedVector2Array = d_pos_list[k]
			var d_hp: PackedFloat32Array = d_hp_list[k]
			for j in d_candidates:
				if j < d_hp.size() and d_hp[j] <= 0.0:
					continue
				# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
				if p_u.distance_squared_to(d_pos[j]) <= max_dist_sq:
					soldier_engaged = true
					break
			if soldier_engaged:
				break
		if soldier_engaged:
			in_reach_count += 1

	return float(in_reach_count) / float(total)


## At least `fraction` (0..1) of u's CURRENT living soldiers are melee-engaged --
## current_engaged_fraction() tested against a threshold. The fractional counterpart to
## Unit.is_engaged()'s whole-regiment binary latch.
static func engaged_fraction_above(u: Unit, fraction: float) -> bool:
	return current_engaged_fraction(u) >= fraction


## Whether `dest` -- a unit's own move_target -- now falls inside a living, non-routing
## enemy's own physical footprint: within the COMBINED separation_radius + soldier_block_extent()
## of both `u` and the enemy (the same symmetric "clear of each other" reach
## Order.resolve_friendly_target already uses for a relief pass-through -- both sides' own
## footprint, not just the enemy's, since `u`'s own block will physically occupy space around
## `dest` too once it arrives). The disengage-time staleness check for a plain MOVE that just
## finished a heavy melee engagement (Unit._resolve_disengage_move_order): the march is worth
## cancelling only when the ground it was headed for is actually held by the enemy now, not
## merely because a fight happened somewhere along the way. A routing enemy doesn't count -- a
## broken, fleeing regiment doesn't hold ground the way a live one does (mirrors flanked()'s and
## enemy_in_range()'s own routing exclusion).
static func move_target_occupied_by_enemy(u: Unit, dest: Vector2) -> bool:
	var u_reach: float = u.separation_radius + u.soldier_block_extent()
	for o in u.get_tree().get_nodes_in_group("units"):
		var other: Unit = o as Unit
		if other == null or other.team == u.team:
			continue
		if other.state == Unit.State.DEAD or other.state == Unit.State.ROUTING:
			continue
		var reach: float = u_reach + other.separation_radius + other.soldier_block_extent()
		# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
		if dest.distance_squared_to(other.position) <= reach * reach:
			return true
	return false
