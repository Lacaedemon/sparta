class_name SkirmisherScreen
## The skirmisher-screen subcommander directive (docs/deployment-distance-design.md,
## "Skirmisher screening"): the group's light troops go forward to contest the ground
## between the lines, then break off and fall back THROUGH THE INTERVALS of their own heavy
## line as the enemy closes -- the opening Polybius gives both Cannae and Zama (3.115;
## 15.9-12), and the fall-back through the line behind that Livy describes (8.8).
##
## Stateless and pure like Subcommander and General -- one entry point over already-
## serialized positions, no RNG, no node-iteration-order dependence, so a replay re-derives
## the same screen on the same ticks. OUTPUT, not actuation: plain {uid: directive} data in
## Subcommander's own vocabulary, read only by UnitLeader's DIRECTIVE_SCREEN/WITHDRAW arms.
const WorldScaleRef = preload("res://scripts/WorldScale.gd")

## Go forward and skirmish at this point, in the SKIRMISH stance.
const DIRECTIVE_SCREEN := "screen"
## Break off and fall back through this interval in the heavy line.
const DIRECTIVE_WITHDRAW := "screen_withdraw"

## How far ahead of the heavy line's median depth the contest line sits: one ranged reach
## (Unit.RANGED_RANGE, 8 m), a band a few metres out rather than a hundred-metre duel.
const SCREEN_LEAD_DISTANCE := 8.0 * WorldScaleRef.WU_PER_M

## How close a living enemy may come to a screening unit before it breaks off and withdraws.
## Six metres sits just outside Unit.SKIRMISH_KITE_DISTANCE (5 m), so the recall supersedes
## the kite reflex, and inside Unit.RANGED_RANGE (8 m), so the volleys go off first.
const WITHDRAW_TRIGGER_RANGE := 6.0 * WorldScaleRef.WU_PER_M

## How far BEHIND the line's median depth a withdrawing unit rallies -- clear of the rear rank.
const RALLY_DEPTH := 8.0 * WorldScaleRef.WU_PER_M

## How near the contest line counts as "on station". A screener inside this radius keeps its
## directive -- so line integrity cannot haul it back to the line it deliberately stands
## ahead of -- but gets no fresh order, leaving it free to fire and kite. Wider than
## Unit.SKIRMISH_KITE_DISTANCE (5 m) so one kite step cannot cancel its own firefight.
const SCREEN_STATION_RADIUS := 7.0 * WorldScaleRef.WU_PER_M


## Screen and withdraw directives for `group`'s light troops, written into `out` -- one entry
## per light unit, unconditionally. `out` is the screen's OWN dictionary, not the group's
## directive table: Subcommander.decide_group runs this first (so mutual support and flank
## coverage can read the screen's membership), then merges `out` in behind whatever those two
## already assigned -- priority belongs there, since this class cannot know what else claimed
## a unit. `axis` is the group's advance axis (Subcommander._advance_axis); `all_units` is the
## usual omniscient perception. No-ops without an axis, without light troops, or without a
## heavy line to screen for -- a screen with nothing behind it has no intervals to fall through.
static func directives(group: Array, all_units: Array, axis: Vector2, out: Dictionary,
		lead: float = SCREEN_LEAD_DISTANCE, trigger: float = WITHDRAW_TRIGGER_RANGE,
		rally: float = RALLY_DEPTH, station: float = SCREEN_STATION_RADIUS) -> void:
	if axis == Vector2.ZERO:
		return
	var light: Array = []
	var heavy: Array = []
	_split_line(group, light, heavy)
	if light.is_empty() or heavy.is_empty():
		return
	var perp := Vector2(-axis.y, axis.x)
	var depth: float = ScreenIntervals.median_depth(heavy, axis)
	var gaps: Array[float] = ScreenIntervals.interval_laterals(heavy, perp)
	for node in light:
		var u := node as Unit
		var lateral: float = u.position.dot(perp)
		if _enemy_within(u, all_units, trigger):
			# Reconstructed from the (axis, perp) basis like Subcommander's hold-line point:
			# the line's depth minus the rally offset, at the nearest gap between blocks
			# instead of the unit's own lateral -- which is what puts the path through one.
			var back: Vector2 = axis * (depth - rally) \
				+ perp * ScreenIntervals.nearest(gaps, lateral)
			out[u.uid] = {"type": DIRECTIVE_WITHDRAW, "x": back.x, "y": back.y,
					"station": station}
			continue
		var post: Vector2 = axis * (depth + lead) + perp * lateral
		out[u.uid] = {"type": DIRECTIVE_SCREEN, "x": post.x, "y": post.y, "station": station}


## Split `group` into the light troops that form the screen and the heavy blocks it screens
## for. Light means a ranged FOOT unit: mounted skirmishers keep their own cavalry handling
## (a caracole is not a screen), and a dead or routing unit joins neither line.
static func _split_line(group: Array, light: Array, heavy: Array) -> void:
	for node in group:
		var u := node as Unit
		if u == null or u.state == Unit.State.DEAD or u.state == Unit.State.ROUTING:
			continue
		if u.is_ranged and not u.is_cavalry:
			light.append(u)
		else:
			heavy.append(u)


## Whether any living enemy stands within `radius` of `u` -- the "as the enemy closes"
## trigger, measured unit to unit rather than on a whole-line average.
static func _enemy_within(u: Unit, all_units: Array, radius: float) -> bool:
	var r_sq: float = radius * radius
	for node in all_units:
		var e := node as Unit
		if e == null or e.team == u.team or e.state == Unit.State.DEAD \
				or e.state == Unit.State.ROUTING:
			continue
		if u.position.distance_squared_to(e.position) <= r_sq:
			return true
	return false
