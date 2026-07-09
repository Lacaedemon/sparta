class_name UnitTargeting
## Target-acquisition queries for a Unit, extracted from Unit.gd. Pure-ish reads over the
## live units group and the unit's own order state: pick the current melee target, find
## the nearest threat (for auto-acquisition and the support stance), validate a support
## ward, compute a flank/rear approach point, and clamp a point to the field. No RNG and
## no wall-clock, so every result is a deterministic function of sim state — replay-safe.
## The order-EXECUTION that consumes these (the AI brain, the support tick) stays on Unit.


## The unit's committed melee target if it is still live; otherwise clear the stale
## reference and auto-acquire the nearest threat. A routing enemy (broken or shattered)
## stays a live target here --- a unit doesn't lose interest in prey just because it broke
## and ran; it keeps pressing the pursuit. Pursuit can be relentless (nothing caps how far
## a unit will chase); what keeps a chased router from rallying is morale, not a targeting
## radius --- continuing to take casualties while run down erodes morale (see
## UnitCombat.register_casualties) faster than _process_rout's baseline recovery, so it
## never crosses RALLY_MORALE_THRESHOLD. A router that actually breaks free (outruns its
## pursuer, or the pursuer disengages) stops taking hits and recovers normally.
static func current_target(u: Unit) -> Unit:
	var t: Unit = u.target_enemy
	if t != null and is_instance_valid(t) and t.state != Unit.State.DEAD:
		return t
	u.target_enemy = null
	return nearest_enemy(u)


## Nearest threat for normal auto-acquisition: centred on the unit, within DETECTION_RANGE.
## Includes routing enemies --- see nearest_enemy_to's include_routing.
static func nearest_enemy(u: Unit) -> Unit:
	return nearest_enemy_to(u, u.position, Unit.DETECTION_RANGE, true)


## Nearest routing enemy for SWEEP_ROUTERS stance: prioritizes routing enemies (broken/shattered)
## over still-fighting units. Searches within DETECTION_RANGE. Returns a routing enemy if one
## exists within range; otherwise falls back to the nearest non-routing enemy for fallback targeting.
static func nearest_routing_enemy(u: Unit) -> Unit:
	var best_router: Unit = null
	var best_router_d: float = Unit.DETECTION_RANGE
	var best_normal: Unit = null
	var best_normal_d: float = Unit.DETECTION_RANGE

	var groups: Array = ["units", "routers"]
	for group in groups:
		for o in u.get_tree().get_nodes_in_group(group):
			var other: Unit = o as Unit
			if other == null or other.team == u.team:
				continue
			if other.state == Unit.State.DEAD:
				continue

			var d: float = u.position.distance_to(other.position)

			# Prioritize routing enemies
			if other.state == Unit.State.ROUTING:
				if d < best_router_d:
					best_router_d = d
					best_router = other
			else:
				# Track nearest non-routing as fallback
				if d < best_normal_d:
					best_normal_d = d
					best_normal = other

	# Return routing enemy if found; otherwise fall back to nearest non-routing
	return best_router if best_router != null else best_normal


## Nearest living enemy within `radius` of `center`. Backs both normal auto-acquisition
## (centred on this unit, DETECTION_RANGE, routing enemies included) and the support
## stance, which scans around the WARD's position so a supporter meets threats closing on
## its charge rather than only ones near itself.
##
## `include_routing` (default false) governs whether a routing enemy (broken or
## shattered --- still on the field, in the "routers" group, until it escapes or is
## annihilated) counts as a candidate, at the same `radius` as everyone else --- no
## separate leash. Combat auto-acquisition wants routing enemies included (a fleeing
## regiment can still be run down, relentlessly if the pursuer can keep pace); the rally
## contact-check (Unit._can_rally) wants them excluded --- a routing enemy passing nearby
## shouldn't itself count as "still in contact" blocking this unit's own rally.
static func nearest_enemy_to(u: Unit, center: Vector2, radius: float,
		include_routing: bool = false) -> Unit:
	var best: Unit = null
	var best_d: float = radius
	var groups: Array = ["units", "routers"] if include_routing else ["units"]
	for group in groups:
		for o in u.get_tree().get_nodes_in_group(group):
			var other: Unit = o as Unit
			if other == null or other.team == u.team:
				continue
			if other.state == Unit.State.DEAD:
				continue
			var d: float = center.distance_to(other.position)
			if d < best_d:
				best_d = d
				best = other
	return best


## Whether this unit's SUPPORT order still has a valid ward to guard: a living,
## non-routing friendly that isn't this unit itself.
static func support_valid(u: Unit) -> bool:
	var w: Unit = u.support_target
	return w != null and is_instance_valid(w) \
		and w != u \
		and w.state != Unit.State.DEAD \
		and w.state != Unit.State.ROUTING


## Approach point for a flank/rear attack: a spot at melee-contact distance on the
## enemy's flank or rear, relative to its facing, so closing on it brings this unit
## alongside/behind the target and its strike lands with the flank/rear bonus.
## Recomputed each tick from sim state, so it tracks a turning or moving target and stays
## deterministic. Flank picks whichever side this unit is already nearer, so it doesn't
## wrap around unnecessarily.
static func attack_approach_point(u: Unit, enemy: Unit) -> Vector2:
	var contact: float = u.attack_range + Unit.RADIUS + enemy.RADIUS
	if u.order_mode == Unit.ORDER_ATTACK_REAR:
		return enemy.position - enemy.facing * contact
	var perp := Vector2(-enemy.facing.y, enemy.facing.x)
	# Tie-break: an attacker exactly on the enemy's fore/aft axis (dot == 0) goes to the
	# enemy's perp side (its left), deterministically rather than NaN/oscillating.
	var side: float = 1.0 if (u.position - enemy.position).dot(perp) >= 0.0 else -1.0
	return enemy.position + perp * (side * contact)


## Keep a point inside the playable field (used when a skirmisher kites), so a retreating
## unit doesn't back off the map edge.
static func clamp_to_field(u: Unit, p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, u.field_bounds.position.x, u.field_bounds.end.x),
		clampf(p.y, u.field_bounds.position.y, u.field_bounds.end.y))
