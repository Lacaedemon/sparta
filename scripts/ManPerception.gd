extends RefCounted
## Per-man threat perception: what one soldier can perceive of the enemy around him.
## Perception.gd answers which enemy UNITS a team sees, from unit centres. This answers it
## one level down, for a single man: which enemy bodies he himself can see (ManScan, from
## his own position under the fog's sight rule, ManSight), how strongly each presses on him
## (ManWeights: nearer and in front weighs more), and which is nearest. The threat vector
## is the weighted sum of the unit directions from him to each foe he perceives, so it points
## TOWARD the threat (a man fleeing it runs the other way). His sight radius is by default his
## unit's base `sight_range`, the fog model's radius for that unit's observers; the cut the
## fog applies while a unit routs is dropped, and nothing replaces it yet.
## Read-only: it reads unit and body state, the SpatialHash grid, and PathField.active.
## Cached per tick: the first query for a man in a frame fixes his answer for that frame,
## unless his own body or his nearest foe's body at the cached index has moved or gone (a
## reap or a merge re-packs the arrays). A far-tier unit has no bodies.
const Sight = preload("res://scripts/ManSight.gd")
const Weights = preload("res://scripts/ManWeights.gd")
const Foes = preload("res://scripts/ManFoes.gd")
const Scan = preload("res://scripts/ManScan.gd")

## The sight radius every queried man uses, in world units. Zero or negative (the
## default) means each man uses his own unit's `sight_range`.
var sight_radius: float = -1.0:
	set(value):
		sight_radius = value
		_results.clear()
## Half-angle of the visual field, radians. Must lie in [0, PI]; else reported and refused.
var visual_field_half_angle: float = Weights.VISUAL_FIELD_HALF_ANGLE:
	set(value):
		if not (value >= 0.0 and value <= PI):
			push_error("ManPerception: visual_field_half_angle %f outside [0, PI]" % value)
			return
		visual_field_half_angle = value
		_results.clear()
## Weight of a foe directly behind a man. Must lie in (0, 1]; else reported and refused.
var rear_weight: float = Weights.REAR_WEIGHT:
	set(value):
		if not (value > 0.0 and value <= 1.0):
			push_error("ManPerception: rear_weight %f outside (0, 1]" % value)
			return
		rear_weight = value
		_results.clear()

var _frame: int = -1
var _sight: Dictionary = {}
var _foes := Foes.new()
# unit -> {index -> result}; Scan.still_valid says whether a result still holds.
var _results: Dictionary = {}


## Bind this frame's inputs: the physics-frame counter SpatialHash is built with, every unit
## in play ("units" and "routers"), and Perception.perceives' sight inputs. A second call
## for the same frame keeps the first call's inputs and cache.
func prepare(frame: int, units: Array, terrain: Array, path_field: Object) -> void:
	if frame == _frame:
		return
	_frame = frame
	_sight = Sight.compile(terrain, path_field)
	_foes.bind(frame, units)
	_results.clear()


## What man `index` of `unit` perceives this frame. Returns:
##   threat           Vector2, weighted sum of directions toward perceived foes (ZERO: none)
##   nearest_unit     the unit of the nearest perceived foe, or null
##   nearest_index    that foe's body index in nearest_unit, or -1
##   nearest_distance distance to that foe, world units (INF when none)
##   perceived        how many foe bodies he perceives
## A man with no body (an out-of-range index, or a far-tier unit) perceives nothing.
## `frame` must be the frame prepare() was last called with, else an error is reported and
## nothing is perceived: a missed prepare() would answer from last frame's cache.
func perceive(unit: Unit, index: int, frame: int) -> Dictionary:
	if frame != _frame:
		push_error("ManPerception: perceive() for frame %d, prepared for %d" % [frame, _frame])
		return _public(Scan.none())
	var by_index: Dictionary = _results.get(unit, {})
	_results[unit] = by_index
	if by_index.has(index) and Scan.still_valid(unit, index, by_index[index]):
		return _public(by_index[index])
	var radius: float = sight_radius if sight_radius > 0.0 else unit.sight_range
	var result: Dictionary = Scan.scan(unit, index, radius, _sight, _foes,
		visual_field_half_angle, rear_weight)
	by_index[index] = result
	return _public(result)


func _public(r: Dictionary) -> Dictionary:
	return {"threat": r["threat"], "nearest_unit": r["nearest_unit"],
		"nearest_index": r["nearest_index"], "nearest_distance": r["nearest_distance"],
		"perceived": r["perceived"]}
