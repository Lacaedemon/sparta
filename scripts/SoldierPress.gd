class_name SoldierPress
extends RefCounted
## Which men of a block stand in the press of a fight: within a given distance of a foe man who
## is himself fighting. A foe man fights when he is one of his block's engaged men (the ones its
## melee strikes from, Unit.engaged_soldier_indices), or when he stands, not running, within his
## own reach of a man of this block: a man pressing a flank fights whichever block his own
## targets. A running man (a router on his way, Unit._sim_flight_dir) fights no one. The foe men
## are gathered once per call, so a block asks once a tick, not once a man.


## Per man of `unit`, 1 when `want` has him and a fighting foe man stands within `dist` of him.
static func mask(unit: Unit, want: PackedByteArray, dist: float) -> PackedByteArray:
	var n: int = unit._sim_soldier_pos.size()
	var out := PackedByteArray()
	out.resize(n)
	var fighters: PackedVector2Array = fighting_foe_men(unit, dist)
	if fighters.is_empty():
		return out
	var cells: Dictionary = _cells(fighters, dist)
	var dist_sq: float = dist * dist
	for i in range(mini(n, want.size())):
		if want[i] == 0:
			continue
		var p: Vector2 = unit._sim_soldier_pos[i]
		if _any_within(cells, p, dist, dist_sq):
			out[i] = 1
	return out


## Where the fighting foe men stand that could lie within `dist` of a man of `unit`.
static func fighting_foe_men(unit: Unit, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var own_spread: float = SoldierCornered._spread(unit)
	var own_cells: Dictionary = {}
	var own_cell: float = 0.0
	for foe in SoldierCornered.foes_near(unit, unit.position, dist + own_spread):
		var m: int = foe._sim_soldier_pos.size()
		var engaged := PackedByteArray()
		engaged.resize(m)
		for j in foe.engaged_soldier_indices(m):
			if j < m:
				engaged[j] = 1
		var reach: float = foe.soldier_reach()
		var bound_sq: float = pow(dist + own_spread, 2.0)
		for j in range(m):
			if j < foe._sim_soldier_hp.size() and foe._sim_soldier_hp[j] <= 0.0:
				continue
			var q: Vector2 = foe._sim_soldier_pos[j]
			if q.distance_squared_to(unit.position) > bound_sq:
				continue
			if engaged[j] == 1:
				out.append(q)
				continue
			if j < foe._sim_flight_dir.size() and foe._sim_flight_dir[j] != Vector2.ZERO:
				continue   # running
			if own_cell != reach:
				own_cell = reach
				own_cells = _cells(_living(unit), reach)
			if _any_within(own_cells, q, reach, reach * reach):
				out.append(q)
	return out


## The living men of `unit`, where they stand.
static func _living(unit: Unit) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(unit._sim_soldier_pos.size()):
		if i >= unit._sim_soldier_hp.size() or unit._sim_soldier_hp[i] > 0.0:
			out.append(unit._sim_soldier_pos[i])
	return out


## `points` bucketed into square cells `size` wide.
static func _cells(points: PackedVector2Array, size: float) -> Dictionary:
	var cells: Dictionary = {}
	for q in points:
		var k := Vector2i(floori(q.x / size), floori(q.y / size))
		if not cells.has(k):
			cells[k] = PackedVector2Array()
		cells[k].append(q)
	return cells


## Whether a point of `cells` (cells `size` wide) lies within `dist_sq` of `p`.
static func _any_within(cells: Dictionary, p: Vector2, size: float, dist_sq: float) -> bool:
	var c := Vector2i(floori(p.x / size), floori(p.y / size))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dy)
			if cells.has(k):
				for q: Vector2 in cells[k]:
					if q.distance_squared_to(p) <= dist_sq:
						return true
	return false
