class_name SoldierPress
extends RefCounted
## Which men of a block stand in the press of a fight: within a given distance of an enemy man who
## fights, one of the engaged men his block's melee last picked, or one standing, not running, body
## to body with a man of the asking block (a man pressing a flank fights whichever block his own
## targets; one only passing within weapon's reach does not). A running man (Unit._sim_flight_dir)
## fights no one. Close-tier men are filed once a frame (a test rebuilding the field within one
## frame calls reset()); only enemy men near an asker are read.

static var _frame: int = -1
static var _cell: float = 1.0
static var _cells: Dictionary = {}   # team -> {cell key -> PackedInt32Array of man ids}
static var _pos := PackedVector2Array()
static var _unit: Array[Unit] = []
static var _index := PackedInt32Array()
static var _kind := PackedByteArray()   # per man id: 0 not yet read, or ENGAGED, RUNNING, STANDING
enum { ENGAGED = 1, RUNNING, STANDING }


## Per man of `unit`, 1 when `want` has him and a fighting enemy man stands within `dist` of him
## (`dist` no more than twice the longest reach on the field).
static func mask(unit: Unit, want: PackedByteArray, dist: float) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(unit._sim_soldier_pos.size())
	_build(unit)
	for i in range(mini(out.size(), want.size())):
		if want[i] == 1 and _near(unit._sim_soldier_pos[i], unit, dist):
			out[i] = 1
	return out


## Forget this frame's filing, so the next ask files the field again.
static func reset() -> void:
	_frame = -1


## File this frame's close-tier men, once, by team and cell.
static func _build(unit: Unit) -> void:
	var frame: int = Engine.get_physics_frames()
	if frame == _frame or not unit.is_inside_tree():
		return
	_frame = frame
	var units: Array = (unit.get_tree().get_nodes_in_group("units") + unit.get_tree() \
			.get_nodes_in_group("routers")).filter(func(o: Unit) -> bool: return o.tier != FormationTier.FAR)
	var reach_max: float = units.reduce(func(a: float, o: Unit) -> float: return maxf(a, o.soldier_reach()), 1.0)
	_cell = 2.0 * reach_max
	_cells = {}
	_pos = PackedVector2Array()
	_unit = []
	_index = PackedInt32Array()
	for o in units:
		var u: Unit = o
		_cells.get_or_add(u.team, {})
		for i in range(u._sim_soldier_pos.size()):
			if i >= u._sim_soldier_hp.size() or u._sim_soldier_hp[i] > 0.0:
				var q: Vector2 = u._sim_soldier_pos[i]
				var key: int = (floori(q.x / _cell) << 32) ^ (floori(q.y / _cell) & 0xFFFFFFFF)
				if not _cells[u.team].has(key):
					_cells[u.team][key] = PackedInt32Array()
				_cells[u.team][key].append(_pos.size())
				_pos.append(q)
				_unit.append(u)
				_index.append(i)
	_kind = PackedByteArray()
	_kind.resize(_pos.size())


## Whether a fighting man of a team other than `asker`'s stands within `dist` of `p`.
static func _near(p: Vector2, asker: Unit, dist: float) -> bool:
	for t: int in _cells:
		if t != asker.team:
			for m: int in _around(t, p):
				if _pos[m].distance_squared_to(p) <= dist * dist and _fights(m, asker):
					return true
	return false


## The filed men of `team` in the cells round `p`.
static func _around(team: int, p: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in range(9):
		var key: int = ((floori(p.x / _cell) + k % 3 - 1) << 32) ^ ((floori(p.y / _cell) + k / 3 - 1) & 0xFFFFFFFF)
		out.append_array(_cells[team].get(key, []))
	return out


## Whether filed man `m` fights: engaged, or standing body to body with a man of `asker`.
static func _fights(m: int, asker: Unit) -> bool:
	var u: Unit = _unit[m]
	if _kind[m] == 0:
		var j: int = _index[m]
		_kind[m] = ENGAGED if u._engaged_indices_cache_frame >= _frame - 1 and \
				u._engaged_indices_cache_engaged and u._engaged_indices_cache.has(j) else (RUNNING \
				if j < u._sim_flight_dir.size() and u._sim_flight_dir[j] != Vector2.ZERO else STANDING)
	if _kind[m] != STANDING:
		return _kind[m] == ENGAGED
	for o: int in _around(asker.team, _pos[m]):
		if _unit[o] == asker and _pos[o].distance_to(_pos[m]) <= u.soldier_body_radius() + asker.soldier_body_radius():
			return true
	return false
