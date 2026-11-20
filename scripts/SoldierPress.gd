class_name SoldierPress
extends RefCounted
## Which men of a block stand in the press of a fight: within a given distance of an enemy man who
## fights. He fights when he is one of the men his block's melee strikes with this tick
## (Unit.engaged_soldier_indices: a pick its melee makes only while the block is engaged, a unit
## state; see prepare for which picks count), or when, standing and not running, his body touches
## an enemy body (Unit._sim_touching_foe, which SoldierTouch.mark fills: an enemy body within the
## two bodies' radii, whatever his unit's state or his place). A man pressing a flank fights whichever block his own targets; one only
## passing within weapon's reach does not; a running man (Unit._sim_flight_dir) fights no one.
## Battle files the fighting men once a tick before the bodies step (prepare); a test that rebuilds
## the field within one frame calls reset(), and an ask with nothing filed this frame files then.

static var _frame: int = -1
static var _cell: float = 1.0
static var _cells: Dictionary = {}   # team -> {cell key -> PackedVector2Array of fighting men}


## Per man of `unit`, 1 when `want` has him and a fighting enemy man stands within `dist` of him
## (`dist` no more than twice the longest reach on the field).
static func mask(unit: Unit, want: PackedByteArray, dist: float) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(unit._sim_soldier_pos.size())
	_build(unit)
	for i in range(mini(out.size(), want.size())):
		if want[i] == 1 and _near(unit._sim_soldier_pos[i], unit.team, dist):
			out[i] = 1
	return out


## Forget this frame's filing, so the next ask files the field again.
static func reset() -> void:
	_frame = -1


static func _build(unit: Unit) -> void:
	if Engine.get_physics_frames() == _frame:
		return
	_frame = Engine.get_physics_frames()
	_cells = {}
	if unit.is_inside_tree():
		prepare(unit.get_tree().get_nodes_in_group("units") + unit.get_tree().get_nodes_in_group("routers"))


## File this tick's fighting close-tier men of `units` by team and cell: the touching men, and the
## engaged men of each block whose pick one of this tick's passes before the bodies step made
## (Unit.engaged_soldier_indices' cache, filled by SoldierSteering, SoldierMeleeStandoff and
## SoldierEncirclement as they need it). A block none of them asked counts its touching men only:
## making its pick here as well (measured 2026-11-19) brought back general-doctrine-reserves'
## 1.34 wu overlap, and counting an engaged man only within his own reach moved last-unit-rally's
## breaks (seed 0 at 1192 against main's 976).
static func prepare(units: Array) -> void:
	_frame = Engine.get_physics_frames()
	_cells = {}
	var reach_max: float = 1.0
	for u: Unit in units:
		reach_max = maxf(reach_max, u.soldier_reach())
	_cell = 2.0 * reach_max
	for u: Unit in units:
		if u.tier != FormationTier.FAR and u._engaged_indices_cache_frame == _frame \
				and u._engaged_indices_cache_engaged:
			for j in u._engaged_indices_cache:
				_file(u, j)
		for j in range(u._sim_touching_foe.size()):
			if u._sim_touching_foe[j] == 1 \
					and (j >= u._sim_flight_dir.size() or u._sim_flight_dir[j] == Vector2.ZERO):
				_file(u, j)


## File man `j` of `u`, if he lives.
static func _file(u: Unit, j: int) -> void:
	if j >= u._sim_soldier_pos.size() or (j < u._sim_soldier_hp.size() and u._sim_soldier_hp[j] <= 0.0):
		return
	var q: Vector2 = u._sim_soldier_pos[j]
	var by_cell: Dictionary = _cells.get_or_add(u.team, {})
	var key: int = (floori(q.x / _cell) << 32) ^ (floori(q.y / _cell) & 0xFFFFFFFF)
	if not by_cell.has(key):
		by_cell[key] = PackedVector2Array()
	by_cell[key].append(q)


## Whether a filed fighting man of a team other than `team` stands within `dist` of `p`.
static func _near(p: Vector2, team: int, dist: float) -> bool:
	var cx: int = floori(p.x / _cell)
	var cy: int = floori(p.y / _cell)
	for t: int in _cells:
		if t == team:
			continue
		var by_cell: Dictionary = _cells[t]
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for q: Vector2 in by_cell.get(((cx + dx) << 32) ^ ((cy + dy) & 0xFFFFFFFF), PackedVector2Array()):
					if q.distance_squared_to(p) <= dist * dist:
						return true
	return false
