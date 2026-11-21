class_name SoldierTouch
extends RefCounted
## Which men's bodies touch an enemy body this tick: each close-tier man of every unit, whatever
## his unit's state or his place in it, is marked (Unit._sim_touching_foe) when an enemy body
## lies within the two bodies' radii of his. Battle runs it once a tick before the bodies step,
## and SoldierPress reads the marks. A unit with no enemy body near its own skips the per-man look
## (SoldierCornered.foes_near).

## The men of one frame, by team and cell: team -> {cell key -> PackedInt32Array of man ids}.
static var _cells: Dictionary = {}
static var _pos := PackedVector2Array()
static var _radius := PackedFloat32Array()


## Clear and fill every unit's touching marks for this tick.
static func mark(units: Array) -> void:
	var near: Array[Unit] = []
	var r_max: float = 0.0
	for o in units:
		var u: Unit = o as Unit
		if u == null:
			continue
		u._sim_touching_foe = PackedByteArray()
		if u.state == Unit.State.DEAD or u.tier == FormationTier.FAR or u._sim_soldier_pos.is_empty():
			continue
		if SoldierCornered.foes_near(u, u.position, SoldierCornered._spread(u)).is_empty():
			continue
		u._sim_touching_foe.resize(u._sim_soldier_pos.size())
		near.append(u)
		r_max = maxf(r_max, u.soldier_body_radius())
	if near.is_empty():
		return
	var cell: float = 2.0 * r_max
	_cells = {}
	_pos = PackedVector2Array()
	_radius = PackedFloat32Array()
	for u in near:
		var by_cell: Dictionary = _cells.get_or_add(u.team, {})
		var r: float = u.soldier_body_radius()
		var hp: PackedFloat32Array = u._sim_soldier_hp
		for i in range(u._sim_soldier_pos.size()):
			if i < hp.size() and hp[i] <= 0.0:
				continue
			var q: Vector2 = u._sim_soldier_pos[i]
			var key: int = (floori(q.x / cell) << 32) ^ (floori(q.y / cell) & 0xFFFFFFFF)
			var bucket: Variant = by_cell.get(key)
			if bucket == null:
				by_cell[key] = PackedInt32Array([_pos.size()])
			else:
				by_cell[key].append(_pos.size())
			_pos.append(q)
			_radius.append(r)
	for u in near:
		var foes: Array = []   # the other teams' cells
		for t: int in _cells:
			if t != u.team:
				foes.append(_cells[t])
		var r: float = u.soldier_body_radius()
		var hp: PackedFloat32Array = u._sim_soldier_hp
		for i in range(u._sim_soldier_pos.size()):
			if (i >= hp.size() or hp[i] > 0.0) and _touches(u._sim_soldier_pos[i], foes, r, cell):
				u._sim_touching_foe[i] = 1


## Whether a body filed in `foes` (cell dictionaries) lies within the two radii of a body of
## radius `r` at `p`.
static func _touches(p: Vector2, foes: Array, r: float, cell: float) -> bool:
	var cx: int = floori(p.x / cell)
	var cy: int = floori(p.y / cell)
	for by_cell: Dictionary in foes:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var bucket: Variant = by_cell.get(((cx + dx) << 32) ^ ((cy + dy) & 0xFFFFFFFF))
				if bucket == null:
					continue
				for m: int in bucket:
					var touch: float = r + _radius[m]
					if _pos[m].distance_squared_to(p) <= touch * touch:
						return true
	return false
