extends RefCounted
## Per-man threat perception: what one soldier can perceive of the enemy around him.
##
## Perception.gd answers which enemy UNITS a team sees, from unit centres. This answers the
## question one level down, for a single man: which enemy bodies he himself can see, how
## strongly each one presses on his attention, and which of them is nearest. It is the
## sense a man acts on when he flees, turns to a foe, or picks whom to strike.
##
## What a man perceives, and why:
## - His own line of sight. A foe body counts only when it passes the fog's sight rule
##   (Perception.perceives: range, screening terrain that shortens it, occluding terrain
##   that blocks it) sighted from the man's own position rather than from his unit's
##   centre. No unit-level gate decides for him: a foe at his elbow is seen even if its
##   unit's centre is out of view, and a foe behind a hill is not, even if a comrade sees
##   it. sight_rule() compiles the terrain once per frame; line_of_sight() applies it and
##   gives the same answer as Perception.perceives for the same inputs.
## - Sight radius. By default his unit's base `sight_range`, the radius the fog model gives
##   that unit's observers, without the cut the fog applies while a unit routs: where a
##   fleeing man looks is his facing, which the front arc below already models. Unit.gd
##   documents the value as tuned for legibility on the field rather than as an eyesight
##   claim; a man's sense uses it so that what he reacts to stays on the scale the battle
##   shows under fog. A caller sets `sight_radius` to model a different reach.
## - Front arc. His eyes face his own facing (Unit.soldier_facing). A foe inside his visual
##   field counts in full; behind it the weight falls off to `rear_weight` directly behind
##   him, where he knows of a foe only by sound, by a comrade's shout, or by contact. The
##   same line-of-sight test applies all round him: sound through a wood is not modelled.
## - Distance. A nearer foe weighs more: the weight falls linearly from 1 at his own
##   position to 0 at the edge of his sight. No source fixes the shape; linear is the
##   simplest falloff that is continuous at the edge, so a foe crossing the sight radius
##   adds nothing abruptly.
##
## The answer per man is a threat vector, the weighted sum of the unit directions from him
## to each foe he perceives, so it points TOWARD the threat (a man fleeing it runs the other
## way), and its length grows with how many foes he perceives and how near they are. The
## nearest perceived foe (unit and body index) is returned separately for melee, without
## the arc weighting: a man knows the foe at his elbow whichever way he faces.
##
## Read-only: it reads unit positions, teams, states, body positions and facings, and
## writes nothing back into any unit. It also reads two pieces of global state: the static
## SpatialHash grid, and PathField.active, which decides occlusion when a caller passes
## neither terrain nor a path field (Perception.perceives' own fallback).
##
## Cached per tick: the first query for a man in a frame fixes his answer for that frame,
## unless his unit's or his nearest foe's body arrays change size (a casualty reap or a
## merge re-packs them), which recomputes it. A reap and a merge in the same frame that
## leave a unit's size unchanged are not detected. Candidate enemy units come from the
## per-frame unit SpatialHash when it has been rebuilt for the frame, and from the `units`
## list otherwise.
##
## Cost: each query visits the bodies of the enemy units whose bounding circles reach the
## man's sight disc, so a tick's cost is the number of men queried times the foe bodies
## near each. Querying every close-tier man of cannae_scale is far dearer than querying the
## few a consumer needs (the routers, the men in contact).
##
## Limitations: a far-tier unit carries no bodies, so its men are not perceived (the tier
## pass promotes a block once an enemy comes near it); a unit that enters play after the
## frame's SpatialHash rebuild is found only on the list path until the next rebuild.
const PerceptionRef = preload("res://scripts/Perception.gd")
const PathFieldRef = preload("res://scripts/PathField.gd")

## Half-angle of a man's visual field, measured from straight ahead. The normal monocular
## field reaches about 107 degrees temporally from the line of sight (H. M. Traquair, "An
## Introduction to Clinical Perimetry", 1938, ch. 1), so with the eyes looking ahead a man
## sees out to 107 degrees on either side. A closed helmet (the Corinthian type, for one)
## narrowed this; a caller modelling one sets a smaller angle.
const VISUAL_FIELD_HALF_ANGLE: float = deg_to_rad(107.0)
## Weight of a foe directly behind a man, relative to one in his visual field. He cannot
## see a foe there; he learns of one by sound, by a comrade's shout or by contact. No
## source quantifies that awareness, so the default halves the weight and leaves it to the
## caller. It must stay above 0: a man with foes only behind him still perceives them.
const REAR_WEIGHT: float = 0.5

## The sight radius every queried man uses, in world units. Zero or negative (the
## default) means each man uses his own unit's `sight_range`.
var sight_radius: float = -1.0
## Half-angle of the visual field, radians, from straight ahead. Must lie in [0, PI]; an
## out-of-range value is reported and refused, keeping the previous one.
var visual_field_half_angle: float = VISUAL_FIELD_HALF_ANGLE:
	set(value):
		if value < 0.0 or value > PI:
			push_error("ManPerception: visual_field_half_angle %f outside [0, PI]" % value)
			return
		visual_field_half_angle = value
## Weight of a foe directly behind a man. Must lie in (0, 1]; an out-of-range value is
## reported and refused, keeping the previous one.
var rear_weight: float = REAR_WEIGHT:
	set(value):
		if value <= 0.0 or value > 1.0:
			push_error("ManPerception: rear_weight %f outside (0, 1]" % value)
			return
		rear_weight = value

var _frame: int = -1
var _units: Array = []
var _sight: Dictionary = {}
# Per frame: unit -> [body count when measured, farthest body from the unit's position]
# (its bounding circle), and the largest reach of any unit.
var _reach: Dictionary = {}
var _max_reach: float = 0.0
# Per frame: unit -> {"count": body count when cached, "by_index": {index -> result}}.
var _results: Dictionary = {}


## Bind this frame's inputs. `frame` is the physics-frame counter the caller also builds
## SpatialHash with (Engine.get_physics_frames()). `units` is every unit in play (the
## "units" and "routers" groups together). `terrain` and `path_field` are the sight inputs
## Perception.perceives takes (Battle's terrain and its sight path field). Idempotent
## within a frame: a second call for the same frame keeps the first call's inputs and cache.
func prepare(frame: int, units: Array, terrain: Array, path_field: Object) -> void:
	if frame == _frame:
		return
	_frame = frame
	_units = units
	_sight = sight_rule(terrain, path_field)
	_reach.clear()
	_max_reach = 0.0
	_results.clear()


## What man `index` of `unit` perceives this frame. Returns:
##   threat           Vector2, the weighted sum of directions toward perceived foes
##                    (ZERO when he perceives none)
##   nearest_unit     the unit of the nearest perceived foe, or null
##   nearest_index    that foe's body index in nearest_unit, or -1
##   nearest_distance distance to that foe, world units (INF when none)
##   perceived        how many foe bodies he perceives
## A man with no body (an out-of-range index, or a far-tier unit) perceives nothing.
## Call prepare() for the frame first.
func perceive(unit: Unit, index: int) -> Dictionary:
	var count: int = unit._sim_soldier_pos.size()
	var entry: Dictionary = _results.get(unit, {})
	# A casualty reap or a merge re-packs the body arrays, so an index cached before it may
	# now name a different man: drop the unit's cache whenever its body count changes.
	if entry.is_empty() or int(entry["count"]) != count:
		entry = {"count": count, "by_index": {}}
		_results[unit] = entry
	var by_index: Dictionary = entry["by_index"]
	if by_index.has(index):
		var cached: Dictionary = by_index[index]
		if _nearest_still_valid(cached):
			return _public(cached)
	var result: Dictionary = _compute(unit, index)
	by_index[index] = result
	return _public(result)


## Weight of a foe in direction `to_foe` from a man facing `facing`: 1 inside the visual
## field (|angle| <= half_angle), falling linearly to `rear` directly behind him. Pure.
## A zero facing reads as facing the foe (full weight).
static func arc_weight(facing: Vector2, to_foe: Vector2, half_angle: float, rear: float) -> float:
	var ang: float = absf(facing.angle_to(to_foe))
	if ang <= half_angle or half_angle >= PI:
		return 1.0
	return lerpf(1.0, rear, (ang - half_angle) / (PI - half_angle))


## Weight of a foe at `dist` from a man who sees out to `radius`: 1 at his position,
## falling linearly to 0 at the edge of his sight. Pure.
static func distance_weight(dist: float, radius: float) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	return 1.0 - dist / radius


## The terrain inputs of Perception.perceives, sorted once into what a sightline tests:
## "screens" (rects that shorten sight, in terrain order) with their "factors", and
## "blocks" (rects that stop it). Blocks come from where perceives reads them: the path
## field when one is given, else the terrain's blocking patches, else PathField.active.
## Pure apart from that last fallback's global read.
static func sight_rule(terrain: Array, path_field: Object) -> Dictionary:
	var screens: Array[Rect2] = []
	var factors := PackedFloat64Array()
	var blocks: Array[Rect2] = []
	for patch in terrain:
		var sight: String = patch.get("sight", "block" if patch.get("kind", "block") == "block" else "screen")
		if sight == "screen":
			screens.append(patch["rect"])
			factors.append(float(patch.get("screen_factor", Unit.SIGHT_SCREEN_FACTOR)))
	if path_field != null:
		blocks.append_array(path_field.block_rects())
	elif not terrain.is_empty():
		for patch in terrain:
			var sight: String = patch.get("sight", "block" if patch.get("kind", "block") == "block" else "screen")
			if sight == "block":
				blocks.append(patch["rect"])
	elif PathFieldRef.active != null:
		blocks.append_array(PathFieldRef.active.block_rects())
	return {"screens": screens, "factors": factors, "blocks": blocks}


## Whether `target` is in sight from `observer` at `radius` under `rule` (from
## sight_rule): Perception.perceives' answer for the same inputs, for a target already
## known to lie within `radius`. Pure.
static func line_of_sight(observer: Vector2, radius: float, target: Vector2, rule: Dictionary) -> bool:
	var screens: Array[Rect2] = rule["screens"]
	var factors: PackedFloat64Array = rule["factors"]
	var eff: float = radius
	for k in range(screens.size()):
		if PathFieldRef.segment_intersects_rect(observer, target, screens[k]):
			eff *= factors[k]
	if observer.distance_squared_to(target) > eff * eff:
		return false
	for r in (rule["blocks"] as Array[Rect2]):
		if PathFieldRef.segment_intersects_rect(observer, target, r):
			return false
	return true


# The part of the frame's sight rule that can touch a sightline from `pos` of length at
# most `radius`: rects overlapping the box around his sight disc, kept in their order.
func _local_sight(pos: Vector2, radius: float) -> Dictionary:
	var disc := Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	var screens: Array[Rect2] = []
	var factors := PackedFloat64Array()
	var all_screens: Array[Rect2] = _sight["screens"]
	var all_factors: PackedFloat64Array = _sight["factors"]
	for k in range(all_screens.size()):
		if all_screens[k].intersects(disc, true):
			screens.append(all_screens[k])
			factors.append(all_factors[k])
	var blocks: Array[Rect2] = []
	for r in (_sight["blocks"] as Array[Rect2]):
		if r.intersects(disc, true):
			blocks.append(r)
	return {"screens": screens, "factors": factors, "blocks": blocks}


# A cached nearest index stays valid while the foe unit's body arrays keep the size they
# had when it was computed; a reap or a merge re-packs them.
func _nearest_still_valid(cached: Dictionary) -> bool:
	var foe: Variant = cached["nearest_unit"]
	if foe == null:
		return true
	return (foe as Unit)._sim_soldier_pos.size() == int(cached["nearest_count"])


func _public(r: Dictionary) -> Dictionary:
	return {"threat": r["threat"], "nearest_unit": r["nearest_unit"],
		"nearest_index": r["nearest_index"], "nearest_distance": r["nearest_distance"],
		"perceived": r["perceived"]}


func _compute(unit: Unit, index: int) -> Dictionary:
	var out: Dictionary = {"threat": Vector2.ZERO, "nearest_unit": null, "nearest_index": -1,
		"nearest_distance": INF, "perceived": 0, "nearest_count": 0}
	if index < 0 or index >= unit._sim_soldier_pos.size():
		return out
	var radius: float = sight_radius if sight_radius > 0.0 else unit.sight_range
	if radius <= 0.0:
		return out
	var pos: Vector2 = unit._sim_soldier_pos[index]
	var facing: Vector2 = unit.soldier_facing(index)
	var local: Dictionary = _local_sight(pos, radius)
	var open_ground: bool = (local["screens"] as Array).is_empty() and (local["blocks"] as Array).is_empty()
	var radius_sq: float = radius * radius
	var threat := Vector2.ZERO
	var nearest_sq: float = INF
	var perceived: int = 0
	for foe in _candidates(pos, radius):
		if foe.team == unit.team or foe.state == Unit.State.DEAD:
			continue
		# The reach is measured at its first use this frame; the same one-cell pad as the
		# hash query covers how far the block can have moved since.
		var reach_out: float = radius + float(_reach[foe][1]) + SpatialHash.CELL_SIZE
		if foe.position.distance_squared_to(pos) > reach_out * reach_out:
			continue
		var bodies: PackedVector2Array = foe._sim_soldier_pos
		for j in range(bodies.size()):
			var d_sq: float = pos.distance_squared_to(bodies[j])
			if d_sq > radius_sq:
				continue
			if not open_ground and not line_of_sight(pos, radius, bodies[j], local):
				continue
			perceived += 1
			if d_sq < nearest_sq:
				nearest_sq = d_sq
				out["nearest_unit"] = foe
				out["nearest_index"] = j
				out["nearest_count"] = bodies.size()
			if d_sq <= 0.0:
				continue
			var to_foe: Vector2 = bodies[j] - pos
			var dist: float = sqrt(d_sq)
			var w: float = distance_weight(dist, radius) \
				* arc_weight(facing, to_foe, visual_field_half_angle, rear_weight)
			threat += to_foe / dist * w
	out["threat"] = threat
	out["perceived"] = perceived
	if perceived > 0:
		out["nearest_distance"] = sqrt(nearest_sq)
	return out


# Units that could hold a body within `radius` of `pos`, in ascending uid order so the
# hash path and the list path sum the same bodies in the same order. Only members of
# `_units` count: the caller's list says which units are in play.
func _candidates(pos: Vector2, radius: float) -> Array:
	_ensure_reach()
	var raw: Array
	if SpatialHash.is_current(_frame):
		# The hash buckets unit positions from the start of the frame; padding the query by
		# one cell covers how far a unit can have moved since.
		raw = SpatialHash.query(pos, radius + _max_reach + SpatialHash.CELL_SIZE)
	else:
		raw = _units
	var out: Array = []
	for u in raw:
		if _reach.has(u):
			out.append(u)
	out.sort_custom(func(a, b): return a.uid < b.uid)
	return out


# Measure the bounding circle of every unit in play that has bodies, again whenever its
# body count has changed since it was measured. Checked on every query, so a unit that
# gains bodies mid-frame (a far-tier block promoted, a merge inserting newcomers) is
# measured as soon as it has them. A unit that has lost all its bodies drops out.
func _ensure_reach() -> void:
	for u in _units:
		var unit: Unit = u as Unit
		if unit == null:
			continue
		var count: int = unit._sim_soldier_pos.size()
		if count == 0:
			_reach.erase(unit)
			continue
		var known: Variant = _reach.get(unit)
		if known != null and int(known[0]) == count:
			continue
		var far_sq: float = 0.0
		for p in unit._sim_soldier_pos:
			far_sq = maxf(far_sq, unit.position.distance_squared_to(p))
		var reach: float = sqrt(far_sq)
		_reach[unit] = [count, reach]
		_max_reach = maxf(_max_reach, reach)
