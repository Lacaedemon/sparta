extends RefCounted
## Which units could hold a body near a man, for one frame: the units in play in uid order,
## each unit's bounding circle (its farthest body from its position), and a spatial-hash
## lookup. bind() measures every unit once; a query re-measures only a candidate whose body
## count has changed since (a far-tier block promoted, a merge inserting newcomers).
##
## Candidates come from the per-frame unit SpatialHash when it has been rebuilt for the
## frame, and from the bound list otherwise. On the hash path a bound unit that is missing
## from the hash (it entered play after the rebuild) is not found until the next rebuild.

var _frame: int = -1
var _ordered: Array = []     # the bound units, ascending uid
var _rank: Dictionary = {}   # unit -> its index in _ordered
# unit -> [body count when measured, farthest body from the unit's position], and the
# largest such reach of any unit.
var _reach: Dictionary = {}
var _max_reach: float = 0.0


## Bind this frame's units, sort them by uid and measure each once. ManPerception calls it
## once per frame.
func bind(frame: int, units: Array) -> void:
	_frame = frame
	_ordered = units.duplicate()
	_ordered.sort_custom(func(a, b): return a.uid < b.uid)
	_rank.clear()
	_reach.clear()
	_max_reach = 0.0
	for i in range(_ordered.size()):
		_rank[_ordered[i]] = i
		_refresh(_ordered[i])


## Units that could hold a body within `radius` of `pos`, in ascending uid order so the
## hash path and the list path sum the same bodies in the same order. Only bound units with
## bodies count: the caller's list says which units are in play.
func candidates(pos: Vector2, radius: float) -> Array:
	var raw: Array = _ordered
	if SpatialHash.is_current(_frame):
		# The hash buckets unit positions from the start of the frame; padding the query by
		# one cell covers how far a unit can have moved since.
		raw = SpatialHash.query(pos, radius + _max_reach + SpatialHash.CELL_SIZE)
	var ranks := PackedInt32Array()
	for u in raw:
		if _rank.has(u) and _refresh(u):
			ranks.push_back(_rank[u])
	ranks.sort()
	var out: Array = []
	for r in ranks:
		out.append(_ordered[r])
	return out


## How far a candidate's bodies can lie from its position, padded by the same one cell
## that covers how far the block can have moved since it was measured.
func reach_of(foe: Unit) -> float:
	return float(_reach[foe][1]) + SpatialHash.CELL_SIZE


# Whether `unit` has bodies, measuring its bounding circle again when its body count has
# changed since it was measured. A unit with none drops out and forgets its measurement.
func _refresh(unit: Unit) -> bool:
	var count: int = unit._sim_soldier_pos.size()
	if count == 0:
		_reach.erase(unit)
		return false
	var known: Variant = _reach.get(unit)
	if known != null and int(known[0]) == count:
		return true
	var far_sq: float = 0.0
	for p in unit._sim_soldier_pos:
		far_sq = maxf(far_sq, unit.position.distance_squared_to(p))
	var reach: float = sqrt(far_sq)
	_reach[unit] = [count, reach]
	_max_reach = maxf(_max_reach, reach)
	return true
