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

## Parse a `map` block into {field: Rect2, terrain: Array, spawn_lines: Array}.
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
	return out


## The JSON-ready form of a live map, for the replay header. Inverse of parse():
## parse(serialize(field, terrain, spawn_lines)) reproduces the same values, so
## a replay reconstructs the exact battlefield it was recorded on.
static func serialize(field: Rect2, terrain: Array, spawn_lines: Array) -> Dictionary:
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
	return {
		"field": [field.size.x, field.size.y],
		"terrain": patches,
		"spawn_lines": [float(spawn_lines[0]), float(spawn_lines[1])],
	}


## Whether a live map differs from the default one -- decides if a replay needs
## the map recorded at all (a default-map replay stays byte-identical to the
## pre-map format, so old replays and new default-map replays are the same shape).
static func differs_from_default(field: Rect2, terrain: Array, spawn_lines: Array,
		default_field: Rect2, default_terrain: Array, default_spawn_lines: Array) -> bool:
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


static func _num(v) -> bool:
	return v is float or v is int
