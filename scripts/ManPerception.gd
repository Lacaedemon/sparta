extends RefCounted
## Per-man threat perception: what one soldier can perceive of the enemy around him.
##
## Perception.gd answers which enemy UNITS a team sees, from unit centres. This answers it
## one level down, for a single man: which enemy bodies he himself can see (ManScan, from
## his own position under the fog's sight rule, ManSight), how strongly each presses on him
## (ManWeights: nearer and in front weighs more), and which is nearest.
##
## The threat vector is the weighted sum of the unit directions from him to each foe he
## perceives, so it points TOWARD the threat (a man fleeing it runs the other way).
## His sight radius is by default his unit's base `sight_range`, the radius the fog model
## gives that unit's observers, without the cut the fog applies while a unit routs (a
## fleeing man's look is his facing, which the front arc already models).
##
## Read-only: it reads unit and body state, the SpatialHash grid, and PathField.active.
## Cached per tick: the first query for a man in a frame fixes his answer for that frame,
## unless his unit's or his nearest foe's body arrays change size (a casualty reap or a
## merge re-packs them). A reap and a merge in one frame that leave a unit's size unchanged
## are not detected. A far-tier unit carries no bodies, so its men are not perceived.
const Sight = preload("res://scripts/ManSight.gd")
const Weights = preload("res://scripts/ManWeights.gd")
const Foes = preload("res://scripts/ManFoes.gd")
const Scan = preload("res://scripts/ManScan.gd")

## The sight radius every queried man uses, in world units. Zero or negative (the
## default) means each man uses his own unit's `sight_range`.
var sight_radius: float = -1.0
## Half-angle of the visual field, radians. Must lie in [0, PI]; else reported and refused.
var visual_field_half_angle: float = Weights.VISUAL_FIELD_HALF_ANGLE:
	set(value):
		if value < 0.0 or value > PI:
			push_error("ManPerception: visual_field_half_angle %f outside [0, PI]" % value)
			return
		visual_field_half_angle = value
## Weight of a foe directly behind a man. Must lie in (0, 1]; else reported and refused.
var rear_weight: float = Weights.REAR_WEIGHT:
	set(value):
		if value <= 0.0 or value > 1.0:
			push_error("ManPerception: rear_weight %f outside (0, 1]" % value)
			return
		rear_weight = value

var _frame: int = -1
var _sight: Dictionary = {}
var _foes := Foes.new()
# unit -> {"count": body count when cached, "by_index": {index -> result}}.
var _results: Dictionary = {}


## Bind this frame's inputs: the physics-frame counter SpatialHash is built with, every unit
## in play ("units" and "routers" groups), and Perception.perceives' sight inputs.
## Idempotent within a frame: a second call keeps the first call's inputs and cache.
func prepare(frame: int, units: Array, terrain: Array, path_field: Object) -> void:
	if frame == _frame:
		return
	_frame = frame
	_sight = Sight.compile(terrain, path_field)
	_foes.bind(frame, units)
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
	# A reap or a merge re-packs the body arrays, so an index cached before it may now name
	# a different man: drop the unit's cache whenever its body count changes.
	if entry.is_empty() or int(entry["count"]) != count:
		entry = {"count": count, "by_index": {}}
		_results[unit] = entry
	var by_index: Dictionary = entry["by_index"]
	if by_index.has(index) and _nearest_still_valid(by_index[index]):
		return _public(by_index[index])
	var radius: float = sight_radius if sight_radius > 0.0 else unit.sight_range
	var result: Dictionary = Scan.scan(unit, index, radius, _sight, _foes,
		visual_field_half_angle, rear_weight)
	by_index[index] = result
	return _public(result)


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