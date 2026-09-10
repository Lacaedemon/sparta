class_name BattleMap
extends RefCounted
## Per-battle map definition: the battlefield rect, the terrain patch table, and
## the default spawn-line anchors, as plain data a caller configures instead of
## compile-time constants (the caller-configurable-parameters convention -- see
## CLAUDE.md; Battle's own consts remain as the DEFAULT map's values).
##
## Pure statics only: parsing and validation of the `map` block a demo input
## script (or, later, a campaign clash config) supplies, plus the serialization
## a replay records so playback reconstructs the same map. No SceneTree, no
## engine state -- directly unit-testable, like DemoState/DemoFrames.

## Parse a `map` block into {field: Rect2, terrain: Array, spawn_lines: Array,
## sight_scale: float}.
## Every key is optional; an absent key means "keep the battle's current
## default" and comes back absent from the result, so a caller merges only what
## the block actually set. Returns {error: String} instead when the block is
## malformed -- map geometry decides WHAT battle runs, so a bad block must fail
## the recording loudly rather than degrade to the wrong battlefield (the same
## strictness the recorder's scenario field gets).
static func parse(block: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if block.has("field"):
		var f = block["field"]
		if not (f is Array) or (f as Array).size() != 2 \
				or not _num(f[0]) or not _num(f[1]) \
				or float(f[0]) <= 0.0 or float(f[1]) <= 0.0:
			return {"error": "map.field must be a [width, height] pair of positive numbers"}
		out["field"] = Rect2(0, 0, float(f[0]), float(f[1]))
	if block.has("terrain"):
		var patches = block["terrain"]
		if not (patches is Array):
			return {"error": "map.terrain must be an array of patch objects"}
		var parsed: Array = []
		for p in patches:
			if not (p is Dictionary) or not (p.get("rect") is Array) \
					or (p["rect"] as Array).size() != 4:
				return {"error": "each map.terrain patch needs a rect: [x, y, w, h]"}
			var r: Array = p["rect"]
			for v in r:
				if not _num(v):
					return {"error": "each map.terrain patch needs a rect: [x, y, w, h]"}
			var kind: String = str(p.get("kind", "block"))
			if kind != "block" and kind != "slow":
				return {"error": "map.terrain patch kind must be 'block' or 'slow'"}
			if kind == "slow" and not _num(p.get("speed")):
				return {"error": "a 'slow' map.terrain patch needs a numeric speed scale"}
			var patch: Dictionary = {
				"rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])),
				"type": str(p.get("type", "hill")),
				"kind": kind,
			}
			if kind == "slow":
				patch["speed"] = float(p["speed"])
			parsed.append(patch)
		out["terrain"] = parsed
	if block.has("spawn_lines"):
		var s = block["spawn_lines"]
		if not (s is Array) or (s as Array).size() != 2 or not _num(s[0]) or not _num(s[1]):
			return {"error": "map.spawn_lines must be a [attacker_y, defender_y] pair"}
		out["spawn_lines"] = [float(s[0]), float(s[1])]
	if block.has("sight_scale"):
		var ss = block["sight_scale"]
		if not _num(ss) or float(ss) <= 0.0 or not is_finite(float(ss)):
			return {"error": "map.sight_scale must be a positive, finite number"}
		out["sight_scale"] = float(ss)
	return out


## The JSON-ready form of a live map, for the replay header. Inverse of parse():
## parse(serialize(field, terrain, spawn_lines, sight_scale)) reproduces the same values,
## so a replay reconstructs the exact battlefield it was recorded on.
static func serialize(field: Rect2, terrain: Array, spawn_lines: Array,
		sight_scale: float = -1.0) -> Dictionary:
	var patches: Array = []
	for p in terrain:
		var r: Rect2 = p["rect"]
		var patch: Dictionary = {
			"rect": [r.position.x, r.position.y, r.size.x, r.size.y],
			"type": str(p.get("type", "hill")),
			"kind": str(p.get("kind", "block")),
		}
		if patch["kind"] == "slow":
			patch["speed"] = float(p.get("speed", 1.0))
		patches.append(patch)
	var out: Dictionary = {
		"field": [field.size.x, field.size.y],
		"terrain": patches,
		"spawn_lines": [float(spawn_lines[0]), float(spawn_lines[1])],
	}
	if sight_scale > 0.0:
		out["sight_scale"] = sight_scale
	return out


## Whether a live map differs from the default one -- decides if a replay needs
## the map recorded at all (a default-map replay stays byte-identical to the
## pre-map format, so old replays and new default-map replays are the same shape).
static func differs_from_default(field: Rect2, terrain: Array, spawn_lines: Array,
		default_field: Rect2, default_terrain: Array, default_spawn_lines: Array,
		sight_scale: float = -1.0) -> bool:
	if sight_scale > 0.0:
		return true
	if field != default_field or spawn_lines != default_spawn_lines:
		return true
	if terrain.size() != default_terrain.size():
		return true
	for i in range(terrain.size()):
		var a: Dictionary = terrain[i]
		var b: Dictionary = default_terrain[i]
		if a.get("rect") != b.get("rect") or str(a.get("type", "")) != str(b.get("type", "")) \
				or str(a.get("kind", "block")) != str(b.get("kind", "block")) \
				or float(a.get("speed", 1.0)) != float(b.get("speed", 1.0)):
			return true
	return false


## The map a wider (or narrower) deployment produces from a base map. Team 0's line
## and the field origin stay where they are, team 1's line moves to `gap` world units
## below team 0's, and the field grows (or shrinks) downward by the same amount so
## team 1 keeps the ground it has behind its line on the base map. The base map's own
## gap reproduces the base map exactly, so a caller passing the default gap changes
## nothing. Returns {field: Rect2, spawn_lines: Array}. A non-positive gap would put
## the defender on or above the attacker's line; the callers validate their data
## before reaching here, so it is asserted rather than clamped; the same goes for a
## non-finite gap, which would put the defender nowhere.
static func with_line_gap(gap: float, field: Rect2, spawn_lines: Array) -> Dictionary:
	assert(is_finite(gap) and gap > 0.0, "a deployment gap must be a positive, finite number")
	var attacker_y: float = float(spawn_lines[0])
	var defender_y: float = attacker_y + gap
	var ground_behind: float = field.end.y - float(spawn_lines[1])
	var grown := Rect2(field.position,
			Vector2(field.size.x, defender_y + ground_behind - field.position.y))
	return {"field": grown, "spawn_lines": [attacker_y, defender_y]}


## The deployment gap a data file declares, validated: {"gap_m": float} for a positive,
## finite number (int or float), else {"error": String} naming the first problem. Shared
## by CampaignLoader (a province's deployment_gap_m) and DemoInputRecorder (an input
## script's), so the two data boundaries reject exactly the same values. NAN and INF are
## floats and each slips past a plain sign test (NAN <= 0 is false, INF > 0 is true): the
## first would read as unset in the battle and the second would put the defender's line
## at infinity, so finiteness is checked by name.
static func parse_line_gap_m(raw) -> Dictionary:
	if not _num(raw):
		return {"error": "deployment_gap_m must be a number of metres"}
	var gap_m: float = float(raw)
	if not is_finite(gap_m):
		return {"error": "deployment_gap_m must be a finite number of metres"}
	if gap_m <= 0.0:
		return {"error": "deployment_gap_m must be a positive number of metres"}
	return {"gap_m": gap_m}


static func _num(v) -> bool:
	return v is float or v is int
