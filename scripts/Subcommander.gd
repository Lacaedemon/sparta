class_name Subcommander

## Phase 2 of the chain-of-command battle AI (docs/battle-ai-design.md): the
## subcommander. Keeps one unit group fighting as a group, per the design doc's
## "Subcommander (one per unit group)" section:
##   - line integrity -- no unit races ahead of the group into an unsupported melee.
##   - mutual support -- an engaged unit's unengaged neighbor is sent to guard it.
##   - flank coverage -- an exposed group flank gets a repositioned unit sent to cover it.
##
## Stateless, like UnitLeader (phase 1): one entry point, decide_group(), a pure function
## of already-serialized sim state (group + every living unit), called once per AI tick
## from Battle._run_enemy_ai(). No RNG, no wall-clock, no node-iteration-order dependence
## beyond what the caller already controls -- same seed -> same perception -> same
## directives, so replay re-derives them exactly like every other AI decision.
##
## Group assignment (phase 2 scope, per the design doc's own "start static" open-question
## answer): one group per team's AI-controlled units. Multi-group splitting by doctrine is
## phase 3's territory (the general) -- not built here.
##
## OUTPUT, not actuation: decide_group() returns {uid: directive} -- plain data describing
## intent, never an order-command Dictionary and never a unit-state write. Only the unit
## leader (UnitLeader.decide, taking a directive as its new optional parameter) turns a
## directive into a real Order through Battle._apply_order_cmd, the single apply site every
## other command level in this game already goes through. A subcommander never touches a
## Unit field directly.
##
## Directive shapes (all plain Dictionaries; UnitLeader is the only reader):
##   {"type": DIRECTIVE_SUPPORT, "ward_uid": int}       -- guard this fighting ally.
##   {"type": DIRECTIVE_HOLD_LINE, "x": float, "y": float}    -- hold near this point on the line.
##   {"type": DIRECTIVE_COVER_FLANK, "x": float, "y": float}  -- reposition to cover this point.
##
## Priority when more than one behaviour could claim the same unit this tick: mutual
## support first, flank coverage second, line integrity last. Support and flank coverage
## are reactions to an immediate threat (an ally already fighting, an enemy already closing
## on an open flank); line integrity is standing discipline with no urgency behind it. A
## unit already claimed by a higher-priority directive this tick is never reassigned by a
## lower one (see the `directives.has(uid)` guards throughout). This mirrors UnitLeader's
## own documented priority order (flank threat > square > relief > fallback): react to the
## sharpest need first.

const DIRECTIVE_SUPPORT := "support"
const DIRECTIVE_HOLD_LINE := "hold_line"
const DIRECTIVE_COVER_FLANK := "cover_flank"

## How far away an idle ally can be and still be sent to support a fighting neighbor --
## mirrors UnitLeader.RELIEF_CALL_RANGE's reasoning (a call for help only reaches a
## genuinely nearby ally, not the whole army).
const SUPPORT_CALL_RANGE := 220.0

## How far a unit may project ahead of the group's own median advance (along the group's
## advance axis, toward the enemy) before its subcommander holds it back near the line
## instead of letting it close alone. Comfortably larger than a routine few-step lead
## between neighbors, so only a genuine break from the group triggers a hold.
const LINE_AHEAD_THRESHOLD := 90.0

## How far beyond a flank unit a living enemy may sit and still count as bearing down on
## that open flank -- generous enough to react before the enemy actually closes, the same
## "react before contact, not after" spirit as UnitLeader.SQUARE_TRIGGER_RANGE, just at the
## group's larger scale.
const FLANK_ENEMY_RANGE := 260.0

## How far outward -- beyond the threatened flank unit's own lateral position -- the
## covering unit is sent, so it actually extends the line past the exposed edge instead of
## just crowding in beside the unit it's covering.
const FLANK_COVER_OFFSET := 80.0

## How close a directed point must already be considered "reached" by the callers that
## build move-style directives -- kept here (not on UnitLeader) since both hold-line and
## flank-coverage points are computed from this same tolerance's geometry.
const POINT_EPSILON := 12.0


## Decide this AI tick's directives for one team's group. `group` is the team's own living,
## non-routing units (Battle._team_units(team) -- the caller's group-assignment choice, see
## the class doc); `all_units` is every living node in the "units" group, the same
## omniscient perception source UnitLeader.decide reads. Returns {uid: directive} covering
## only units that should receive a directive this tick -- a uid absent from the result
## gets none (UnitLeader falls back to its own ordinary chase-nearest-enemy behaviour).
static func decide_group(group: Array, all_units: Array) -> Dictionary:
	var living: Array = _living(group)
	if living.size() < 2:
		return {}
	var directives: Dictionary = {}
	_mutual_support_directives(living, directives)
	var axis: Vector2 = _advance_axis(living, all_units)
	_flank_coverage_directives(living, all_units, axis, directives)
	if axis != Vector2.ZERO:
		_line_integrity_directives(living, axis, directives)
	return directives


## `group`, filtered to units that can actually receive or answer a directive this tick
## (Battle._team_units already excludes dead/routing units, but Subcommander doesn't rely
## on that -- it's a defensive filter, matching UnitLeader's own defensive state checks).
static func _living(group: Array) -> Array:
	var out: Array = []
	for node in group:
		var u := node as Unit
		if u != null and u.state != Unit.State.DEAD and u.state != Unit.State.ROUTING:
			out.append(u)
	return out


static func _centroid(units: Array) -> Vector2:
	var sum := Vector2.ZERO
	for node in units:
		var u := node as Unit
		if u != null:
			sum += u.position
	return sum / max(units.size(), 1)


## The group's advance axis: a unit vector from the group's own centroid toward the living
## enemy team's centroid. Vector2.ZERO ("no axis") when there are no living enemies to
## advance on, or when the two centroids coincide (degenerate, avoids a zero-length
## normalize) -- callers treat a zero axis as "skip axis-dependent behaviour this tick".
static func _advance_axis(group: Array, all_units: Array) -> Vector2:
	if group.is_empty():
		return Vector2.ZERO
	var team: int = (group[0] as Unit).team
	var enemy_sum := Vector2.ZERO
	var enemy_count := 0
	for node in all_units:
		var e := node as Unit
		if e == null or e.team == team or e.state == Unit.State.DEAD \
				or e.state == Unit.State.ROUTING:
			continue
		enemy_sum += e.position
		enemy_count += 1
	if enemy_count == 0:
		return Vector2.ZERO
	var delta: Vector2 = (enemy_sum / enemy_count) - _centroid(group)
	if delta.length() < 1.0:
		return Vector2.ZERO
	return delta.normalized()


## An engaged (FIGHTING) unit's nearest idle ally gets a SUPPORT directive naming it as the
## ward -- the subcommander's own version of the design doc's "mutual support" behaviour.
## Runs first (highest priority): an ally already in a fight is the sharpest need a group
## has this tick.
static func _mutual_support_directives(group: Array, directives: Dictionary) -> void:
	for node in group:
		var u := node as Unit
		if u == null or u.state != Unit.State.FIGHTING:
			continue
		var ally: Unit = _nearest_available(u.position, u, group, directives, SUPPORT_CALL_RANGE)
		if ally != null:
			directives[ally.uid] = {"type": DIRECTIVE_SUPPORT, "ward_uid": u.uid}


## Whether `u` is free to receive a NEW directive this tick: alive, not already fighting or
## routing, not already guarding a ward or mid-relief-swap from a previous tick's order, not
## already chasing a live target of its own, and not already claimed by a directive earlier
## this same decide_group() call. Shared fitness check for both mutual-support and
## flank-coverage candidate search -- the same criteria a player would look for before
## pulling a unit out of the group to send it somewhere else.
static func _is_available(u: Unit, self_unit: Unit, directives: Dictionary) -> bool:
	if u == null or u == self_unit or directives.has(u.uid):
		return false
	if u.state == Unit.State.FIGHTING or u.state == Unit.State.ROUTING \
			or u.state == Unit.State.DEAD:
		return false
	if u.support_target != null:
		return false
	if u.current_order != null and (u.current_order.type == Order.Type.RELIEF \
			or u.current_order.type == Order.Type.SUPPORT):
		return false
	# A unit mid-chase against a live target is UnitLeader.decide's own concern to leave
	# alone (see UnitLeader.is_chasing_live_target) -- don't even offer it as a directive
	# candidate here, so a directive is never built (and then discarded) for it.
	if UnitLeader.is_chasing_live_target(u):
		return false
	return true


## Nearest unit in `group` (besides `self_unit`) that passes _is_available, within
## `max_range` of `target_pos`. Null when nothing qualifies.
static func _nearest_available(target_pos: Vector2, self_unit: Unit, group: Array,
		directives: Dictionary, max_range: float) -> Unit:
	var best: Unit = null
	var best_d: float = max_range
	for node in group:
		var u := node as Unit
		if not _is_available(u, self_unit, directives):
			continue
		var d: float = target_pos.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	return best


## A unit projected further along `axis` (toward the enemy) than the group's own median
## projection, by more than LINE_AHEAD_THRESHOLD, gets a HOLD_LINE directive back to the
## line's own depth at its current lateral position -- the "no unit races ahead unsupported"
## behaviour. Runs last (lowest priority): skips a unit already claimed by mutual support or
## flank coverage this tick, and skips a unit already in contact (its own UnitLeader flank
## reaction, or ordinary melee, already owns it).
static func _line_integrity_directives(group: Array, axis: Vector2, directives: Dictionary) -> void:
	var projections: Array[float] = []
	for node in group:
		var u := node as Unit
		if u != null:
			projections.append(u.position.dot(axis))
	projections.sort()
	var median: float = _median(projections)
	var perp := Vector2(-axis.y, axis.x)
	for node in group:
		var u := node as Unit
		if u == null or directives.has(u.uid) or u.state == Unit.State.FIGHTING:
			continue
		# Same exemption as _is_available: a unit already chasing a live target of its own
		# is left to close and fight, not held back to the line mid-pursuit.
		if UnitLeader.is_chasing_live_target(u):
			continue
		var proj: float = u.position.dot(axis)
		if proj - median <= LINE_AHEAD_THRESHOLD:
			continue
		# Reconstruct the hold point from the (axis, perp) orthonormal basis: bring the
		# unit back to the group's own median depth while holding its lateral position --
		# it rejoins the line instead of teleporting to some other unit's spot.
		var lateral: float = u.position.dot(perp)
		var hold_point: Vector2 = axis * median + perp * lateral
		directives[u.uid] = {"type": DIRECTIVE_HOLD_LINE, "x": hold_point.x, "y": hold_point.y}


static func _median(sorted_values: Array[float]) -> float:
	var n: int = sorted_values.size()
	if n == 0:
		return 0.0
	if n % 2 == 1:
		return sorted_values[n / 2]
	return (sorted_values[n / 2 - 1] + sorted_values[n / 2]) * 0.5


## The group's two flanks -- the units with the least and greatest lateral (perpendicular
## to `axis`) projection from the group's own centroid -- each get checked for an
## outflanking enemy and, if found, an available ally is sent to cover the gap. Runs second
## (after mutual support, before line integrity): an open flank with an enemy already
## bearing down on it is more urgent than ordinary line discipline, but less urgent than an
## ally already mid-fight.
static func _flank_coverage_directives(group: Array, all_units: Array, axis: Vector2,
		directives: Dictionary) -> void:
	if axis == Vector2.ZERO or group.size() < 2:
		return
	var perp := Vector2(-axis.y, axis.x)
	var centroid: Vector2 = _centroid(group)
	var team: int = (group[0] as Unit).team
	var left_flank: Unit = null
	var right_flank: Unit = null
	var left_lat: float = INF
	var right_lat: float = -INF
	for node in group:
		var u := node as Unit
		if u == null:
			continue
		var lat: float = (u.position - centroid).dot(perp)
		if lat < left_lat:
			left_lat = lat
			left_flank = u
		if lat > right_lat:
			right_lat = lat
			right_flank = u
	_cover_one_flank(left_flank, -perp, group, all_units, team, directives)
	if right_flank != left_flank:
		_cover_one_flank(right_flank, perp, group, all_units, team, directives)


## Checks one flank unit for an outflanking enemy (living, within FLANK_ENEMY_RANGE, not yet
## in melee contact, sitting further out in `outward` than the flank unit itself) and, if
## found, sends the nearest available (non-flank) ally to a point FLANK_COVER_OFFSET further
## out than the flank unit -- extending the line past the exposed edge.
static func _cover_one_flank(flank: Unit, outward: Vector2, group: Array, all_units: Array,
		team: int, directives: Dictionary) -> void:
	if flank == null or flank.state == Unit.State.FIGHTING or directives.has(flank.uid):
		return
	if not _flank_is_outflanked(flank, outward, all_units, team):
		return
	var covering: Unit = _nearest_available(flank.position, flank, group, directives, INF)
	if covering == null:
		return
	var cover_point: Vector2 = flank.position + outward * FLANK_COVER_OFFSET
	directives[covering.uid] = {"type": DIRECTIVE_COVER_FLANK, "x": cover_point.x, "y": cover_point.y}


static func _flank_is_outflanked(flank: Unit, outward: Vector2, all_units: Array, team: int) -> bool:
	for node in all_units:
		var e := node as Unit
		if e == null or e.team == team or e.state == Unit.State.DEAD \
				or e.state == Unit.State.ROUTING:
			continue
		var to_e: Vector2 = e.position - flank.position
		var d: float = to_e.length()
		if d > FLANK_ENEMY_RANGE:
			continue
		# Already at melee-contact distance: the flank unit's own UnitLeader flank-threat
		# reaction already owns this case (see UnitLeader._flank_threat) -- the
		# subcommander only reacts to a flank an enemy hasn't closed on yet.
		var contact: float = flank.attack_range + Unit.RADIUS + e.RADIUS
		if d <= contact:
			continue
		if to_e.dot(outward) > 0.0:
			return true
	return false
