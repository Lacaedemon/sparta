class_name DemoState
## Pure serialization for the scripted-input demo state-dump path (see demos/README.md,
## "Verifying a demo by state (AI verification)"). Turns authoritative game state into a
## compact, readable JSON-ready Dictionary at a chosen tick, so an AI reviewer (or a test)
## can assert on exact values — a unit's state, morale, position — instead of interpreting a
## rendered frame. It is the machine-readable companion to the PNG frame capture (DemoFrames).
##
## Everything here is a deterministic function of its arguments — no node lookups, no engine
## globals — so the enum-name mapping and the per-soldier summary are directly unit-testable
## like DemoFrames / CameraKeyframes. The recorder walks the live units, pulls their fields,
## and hands them to these helpers to build the snapshot.

## Unit.State int -> readable name. Mirrors `enum State { IDLE, MOVING, FIGHTING, ROUTING, DEAD }`
## on Unit.gd. Kept as an explicit table (not a reflected enum) so the dump names stay stable
## even if the enum gains members, and an out-of-range int reads as "UNKNOWN(<n>)" rather than
## silently dropping.
const STATE_NAMES := {
	0: "IDLE",
	1: "MOVING",
	2: "FIGHTING",
	3: "ROUTING",
	4: "DEAD",
}

## Unit.formation_mode int -> readable name. Mirrors the FORMATION_* consts on Unit.gd
## (NORMAL 0, TIGHT 1, LOOSE 2, SQUARE 3, SHIELD_WALL 4, TESTUDO 5).
const FORMATION_NAMES := {
	0: "NORMAL",
	1: "TIGHT",
	2: "LOOSE",
	3: "SQUARE",
	4: "SHIELD_WALL",
	5: "TESTUDO",
	6: "SCHILTRON",
}

## The node groups that together hold every combat unit still on the field. A unit lives in
## exactly one at a time: "units" while fightable, "routers" while ROUTING (Unit._rout()
## moves it over; _rally() moves it back). A snapshot must walk BOTH — walking "units" alone
## makes a unit vanish from the transcript mid-rout, hiding exactly the arc (state ROUTING,
## morale recovering, position fleeing) the dump exists to expose. Same union
## Battle._team_in_play() scans when deciding whether a team is still in play.
const COMBAT_GROUPS := ["units", "routers"]


## Map an int to a name via a table, falling back to "UNKNOWN(<n>)" for an unmapped value so a
## new enum member surfaces as a visible, greppable token instead of a missing field.
static func name_from(table: Dictionary, value: int, fallback_prefix: String) -> String:
	return table.get(value, "%s(%d)" % [fallback_prefix, value])


static func state_name(value: int) -> String:
	return name_from(STATE_NAMES, value, "STATE")


static func formation_name(value: int) -> String:
	return name_from(FORMATION_NAMES, value, "FORMATION")


## An order_mode int -> its readable name using Battle.ORDER_MODE_NAMES (passed in so this
## stays node-free and testable). Falls back to "MODE(<n>)" for an unmapped value.
static func order_mode_name(order_mode_names: Dictionary, value: int) -> String:
	return name_from(order_mode_names, value, "MODE")


## Order two unit records by uid, for sort_custom.
static func _uid_less(a: Dictionary, b: Dictionary) -> bool:
	return a["uid"] < b["uid"]


## Sort unit records by uid, in place, returning the array. Group enumeration order shifts
## when a unit changes groups — a router leaves "units" for "routers", and a rallied unit
## re-enters "units" at the END of the group — so raw group order reshuffles the transcript
## between ticks. A fixed uid order keeps tick-to-tick records aligned for diffing.
static func sort_records_by_uid(records: Array) -> Array:
	records.sort_custom(_uid_less)
	return records


## Round a float to `places` decimals for compact, readable JSON — raw sim floats carry a long
## fractional tail that adds noise without helping a reviewer assert on a value.
static func round_to(value: float, places: int = 2) -> float:
	var factor: float = pow(10.0, places)
	return round(value * factor) / factor


## A rounded [x, y] pair for a Vector2, for JSON. Keeps positions/facings readable.
static func vec2_pair(v: Vector2, places: int = 2) -> Array:
	return [round_to(v.x, places), round_to(v.y, places)]


## Summarize a regiment's per-soldier bodies without dumping the full 44-byte/soldier arrays.
## Given the world-space soldier positions and the prone timers (index-aligned; prone > 0 means
## down), returns {count, centroid:[x,y], bbox:[w,h], prone_count}. An empty body list yields a
## zeroed summary (centroid [0,0], bbox [0,0], counts 0) so a routed/empty unit still serializes.
## Pure: reads only its two array arguments.
static func soldier_summary(positions: PackedVector2Array, prone: PackedFloat32Array) -> Dictionary:
	var count: int = positions.size()
	if count == 0:
		return {"count": 0, "centroid": [0.0, 0.0], "bbox": [0.0, 0.0], "prone_count": 0}
	var sum: Vector2 = Vector2.ZERO
	var min_p: Vector2 = positions[0]
	var max_p: Vector2 = positions[0]
	for p in positions:
		sum += p
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	var centroid: Vector2 = sum / float(count)
	var prone_count: int = 0
	var prone_n: int = prone.size()
	for i in range(count):
		if i < prone_n and prone[i] > 0.0:
			prone_count += 1
	return {
		"count": count,
		"centroid": vec2_pair(centroid),
		"bbox": [round_to(max_p.x - min_p.x), round_to(max_p.y - min_p.y)],
		"prone_count": prone_count,
	}
