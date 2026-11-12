extends RefCounted
## Which units could hold a body near a man, for one frame: the units in play, each unit's
## bounding circle (its farthest body from its position), and a spatial-hash lookup.
##
## Candidates come from the per-frame unit SpatialHash when it has been rebuilt for the
## frame, and from the `units` list otherwise. A unit that enters play after the frame's
## rebuild is found only on the list path until the next rebuild.

var _frame: int = -1
var _units: Array = []
# unit -> [body count when measured, farthest body from the unit's position], and the
# largest such reach of any unit.
var _reach: Dictionary = {}
var _max_reach: float = 0.0


## Bind this frame's units and drop the last frame's measurements. ManPerception calls it
## once per frame.
func bind(frame: int, units: Array) -> void:
	_frame = frame
	_units = units
	_reach.clear()
	_max_reach = 0.0


## Units that could hold a body within `radius` of `pos`, in ascending uid order so the
## hash path and the list path sum the same bodies in the same order. Only members of the
## bound list count: the caller's list says which units are in play.
func candidates(pos: Vector2, radius: float) -> Array:
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


## How far a candidate's bodies can lie from its position, padded by the same one cell
## that covers how far the block can have moved since it was measured.
func reach_of(foe: Unit) -> float:
	return float(_reach[foe][1]) + SpatialHash.CELL_SIZE


# Measure the bounding circle of every unit in play that has bodies, again whenever its
# body count has changed since it was measured. Checked on every query, so a unit that
# gains bodies mid-frame (a far-tier block promoted, a merge inserting newcomers) is
# measured as soon as it has them. A unit that has lost all its bodies drops out.
func _ensure_reach() -> void:
	for u in _units:
		var unit: Unit = u
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
