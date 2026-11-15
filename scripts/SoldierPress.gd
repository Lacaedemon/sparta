class_name SoldierPress
extends RefCounted
## Which men of a block stand in the press of a fight: within a given distance of an enemy man who
## fights, one of the engaged men his block's melee last picked, or one standing, not running, body
## to body with a man of the asking block (a man pressing a flank fights whichever block his own
## targets; one only passing within weapon's reach does not). A running man (Unit._sim_flight_dir)
## fights no one. Close-tier men are filed once a frame (a test rebuilding it calls reset()).

static var _frame: int = -1
static var _engaged: Grid = Grid.new(1.0)
static var _standing: Grid = Grid.new(1.0)


## Per man of `unit`, 1 when `want` has him and a fighting enemy man stands within `dist` of him
## (`dist` no more than twice the longest reach on the field).
static func mask(unit: Unit, want: PackedByteArray, dist: float) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(unit._sim_soldier_pos.size())
	_build(unit)
	var touching := Grid.new(_engaged.size)   # the enemy men standing body to body with this block
	for i in range(out.size()):
		if i >= unit._sim_soldier_hp.size() or unit._sim_soldier_hp[i] > 0.0:
			_standing.each_near(unit._sim_soldier_pos[i], unit.team, unit.soldier_body_radius(), touching)
	for i in range(mini(out.size(), want.size())):
		var p: Vector2 = unit._sim_soldier_pos[i]
		if want[i] == 1 and (_engaged.has_near(p, unit.team, dist) or touching.has_near(p, unit.team, dist)):
			out[i] = 1
	return out


## Forget this frame's filing, so the next ask files the field again.
static func reset() -> void:
	_frame = -1


## File this frame's close-tier men, once: the engaged ones as the melee last picked them (its
## cache, this frame's or the frame before's, read and never computed here), and the rest that
## stand, not running.
static func _build(unit: Unit) -> void:
	var frame: int = Engine.get_physics_frames()
	if frame == _frame or not unit.is_inside_tree():
		return
	_frame = frame
	var units: Array = (unit.get_tree().get_nodes_in_group("units") + unit.get_tree() \
			.get_nodes_in_group("routers")).filter(func(o: Unit) -> bool: return o.tier != FormationTier.FAR)
	_engaged = Grid.new(2.0 * units.reduce(func(a: float, o: Unit) -> float: return maxf(a, o.soldier_reach()), 1.0))
	_standing = Grid.new(2.0 * units.reduce(func(a: float, o: Unit) -> float: return maxf(a, o.soldier_body_radius()), 1.0))
	for o in units:
		var u: Unit = o
		var picked: bool = u._engaged_indices_cache_frame >= frame - 1 and u._engaged_indices_cache_engaged
		for j in range(u._sim_soldier_pos.size()):
			if j < u._sim_soldier_hp.size() and u._sim_soldier_hp[j] <= 0.0:
				continue
			if picked and u._engaged_indices_cache.has(j):
				_engaged.add(u._sim_soldier_pos[j], u.team, 0.0)
			elif j >= u._sim_flight_dir.size() or u._sim_flight_dir[j] == Vector2.ZERO:
				_standing.add(u._sim_soldier_pos[j], u.team, u.soldier_body_radius())


## Men's places, teams and body radii, bucketed into square cells `size` wide.
class Grid:
	var size: float
	var cells: Dictionary = {}   # cell key -> PackedInt32Array of indices
	var pos := PackedVector2Array()
	var team := PackedInt32Array()
	var radius := PackedFloat32Array()

	func _init(cell_size: float) -> void:
		size = cell_size

	func add(q: Vector2, t: int, r: float) -> void:
		var key: int = (floori(q.x / size) << 32) ^ (floori(q.y / size) & 0xFFFFFFFF)
		if not cells.has(key):
			cells[key] = PackedInt32Array()
		cells[key].append(pos.size())
		pos.append(q)
		team.append(t)
		radius.append(r)

	## Whether a man of a team other than `t` stands within `dist` (no more than `size`) of `p`.
	func has_near(p: Vector2, t: int, dist: float) -> bool:
		var cx: int = floori(p.x / size)
		var cy: int = floori(p.y / size)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for m: int in cells.get(((cx + dx) << 32) ^ ((cy + dy) & 0xFFFFFFFF), PackedInt32Array()):
					if team[m] != t and pos[m].distance_squared_to(p) <= dist * dist:
						return true
		return false

	## File into `into` each man of a team other than `t` whose body touches a body of radius `r`
	## at `p`.
	func each_near(p: Vector2, t: int, r: float, into: Grid) -> void:
		var cx: int = floori(p.x / size)
		var cy: int = floori(p.y / size)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for m: int in cells.get(((cx + dx) << 32) ^ ((cy + dy) & 0xFFFFFFFF), PackedInt32Array()):
					if team[m] != t and pos[m].distance_to(p) <= r + radius[m]:
						into.add(pos[m], team[m], 0.0)
