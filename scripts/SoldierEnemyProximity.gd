class_name SoldierEnemyProximity
extends RefCounted
## Cross-team, cross-unit living-soldier spatial hash for the SQUARE/SCHILTRON
## engaged-set selection (Unit.engaged_soldier_indices). Distinct from
## SoldierSpatialHash (which indexes only the soldiers a unit's OWN
## engaged-set selection already picked, for friendly-avoidance steering and
## enemy-contact resolution): this class answers the question the selection
## itself needs answered BEFORE any engaged set exists -- "is a real enemy
## soldier, within ITS OWN weapon reach, close enough to threaten this
## position" -- so it has to index every living soldier of every unit, not a
## pre-filtered subset.
##
## Determinism: iterates the gathered nodes in whatever order the scene tree
## groups return them (stable within a run), buckets purely by position, and
## `has_enemy_within`'s membership test only depends on the frozen per-tick
## `_sim_soldier_pos`/`_sim_soldier_hp` snapshot -- no RNG, no wall-clock.
##
## Testing: this is keyed by Engine.get_physics_frames(), not a caller-supplied
## frame number, so two synchronous GUT test functions that never advance a
## physics tick between them share the same cache key. Call reset() at the
## start of any test that builds its own units and exercises a code path
## depending on this cache, or it may silently reuse a neighboring test's
## stale grid instead of rebuilding from its own fixtures (see
## .claude/memories/sparta.md, "A new physics-frame-keyed static cache...").

# Cell size must exceed the largest real query radius (self radius + candidate
# radius + candidate reach): the longest weapon reach today is the spear
# (2.4m * Battle.WORLD_UNITS_PER_METER = 48.0 world units) plus two cavalry
# mark radii (10.0 each) = 68.0. 80.0 keeps a margin above that so the 3x3
# cell block queried in has_enemy_within stays a guaranteed superset (mirrors
# SoldierSpatialHash's own CELL_SIZE rationale). Re-check this margin if
# weapon reach or mark-radius constants change.
const CELL_SIZE := 80.0

static var _frame: int = -1
static var _cells: Dictionary = {}   # Vector2i -> PackedInt32Array (indices into _pos/_team/_radius/_reach)
static var _pos: PackedVector2Array = PackedVector2Array()
static var _team: PackedInt32Array = PackedInt32Array()
static var _radius: PackedFloat32Array = PackedFloat32Array()
static var _reach: PackedFloat32Array = PackedFloat32Array()


static func _key(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL_SIZE)), int(floor(p.y / CELL_SIZE)))


## True when the grid has been rebuilt for `frame` and can be queried.
static func is_current(frame: int) -> bool:
	return frame == _frame


## Rebuild the grid from EVERY living soldier of EVERY unit in `units` --
## not gated by is_engaged() or any unit's own engaged-set selection, since
## that selection is exactly what a caller uses this data to compute.
## Idempotent within a frame.
static func rebuild(units: Array, frame: int) -> void:
	if frame == _frame:
		return
	_frame = frame
	_cells.clear()
	_pos = PackedVector2Array()
	_team = PackedInt32Array()
	_radius = PackedFloat32Array()
	_reach = PackedFloat32Array()
	for o in units:
		var u: Unit = o as Unit
		if u == null or u.state == Unit.State.DEAD:
			continue
		var r: float = u.soldier_body_radius()
		var reach: float = u.soldier_reach()
		for i in range(u._sim_soldier_pos.size()):
			if i < u._sim_soldier_hp.size() and u._sim_soldier_hp[i] <= 0.0:
				continue
			_pos.push_back(u._sim_soldier_pos[i])
			_team.push_back(u.team)
			_radius.push_back(r)
			_reach.push_back(reach)
	for i in range(_pos.size()):
		var key := _key(_pos[i])
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		_cells[key].append(i)


## True when a living soldier of a team OTHER than `team` is within STRIKING distance of
## `pos` -- either side's own reach counts, not just the candidate's: a longer-reach soldier
## (e.g. a spear) can threaten a shorter-reach enemy (e.g. a sword) from beyond the sword's
## own reach, the same spear-vs-sword standoff SoldierMelee.resolve's own reach search
## honours (a longer reach lets a soldier strike foes who cannot strike back). Using only
## the candidate's reach here would silently drop that soldier from the engaged set the
## instant it's the LONGER-reach side, even though it's positioned to strike.
static func has_enemy_within(pos: Vector2, team: int, self_radius: float, self_reach: float) -> bool:
	var c := _key(pos)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell: Variant = _cells.get(Vector2i(c.x + dx, c.y + dy))
			if cell == null:
				continue
			for idx in cell:
				if _team[idx] == team:
					continue
				var contact: float = self_radius + _radius[idx] + maxf(self_reach, _reach[idx])
				if pos.distance_squared_to(_pos[idx]) <= contact * contact:
					return true
	return false


## Forget any built grid so the next rebuild() runs. Used by tests for isolation.
static func reset() -> void:
	_frame = -1
	_cells.clear()
	_pos = PackedVector2Array()
	_team = PackedInt32Array()
	_radius = PackedFloat32Array()
	_reach = PackedFloat32Array()
