class_name SoldierEngagedEnemyProximity
extends RefCounted
## Reach-scoped spatial hash over just the ENGAGED tier (both teams), rebuilt fresh each tick
## by SoldierMeleeStandoff.accumulate() from Unit.engaged_soldier_indices() -- NOT a
## whole-battle scan like SoldierEnemyProximity (the scan SQUARE/Schiltron's own engaged-set
## selection needs, since at that point no engaged set exists yet -- that selection IS the
## question being answered). SoldierMeleeStandoff already knows the engaged set (computed
## moments earlier this same tick by SoldierSteering/SoldierEnemyContact and memoized per
## unit), so indexing only the soldiers already known to be engaged is both correct (a
## standoff bias only ever applies between two soldiers already locked in melee) and far
## cheaper than scanning every living soldier of every unit in the battle -- the engaged tier
## is typically a small fraction of the total. That whole-battle scan running unconditionally
## every tick was the root cause of a >100% per-tick regression on the reference-sized battle
## once melee standoff shipped (see .claude/memories/sparta.md, "Per-soldier sim cost scales
## SUPER-linearly").
##
## Deliberately distinct static state from SoldierEnemyProximity and SoldierSpatialHash:
## sharing either would create a real correctness hazard, since a frame-keyed cache can only
## ever serve ONE caller's population per tick -- whichever caller rebuilds first "wins" the
## key, and every other caller in the same tick either gets a stale wrong-scoped grid or
## forces a second full rebuild (worse, not better). See the comment above
## SoldierEnemyContact.accumulate's own call in Battle.gd for the exact rationale (its
## `-frame-1` offset against SoldierSteering's own SoldierSpatialHash rebuild), which applies
## here too -- this class simply avoids the problem by never sharing a key with anything else.
##
## Determinism: rebuild()'s input arrays are gathered by SoldierMeleeStandoff.accumulate in
## a fixed order (the `units` array as given, then each unit's own engaged indices in
## ascending order), so cell insertion order -- and nearest_enemy()'s insertion-order
## tie-break -- is reproducible. No RNG, no wall-clock.
##
## Testing: frame-keyed like its siblings -- call reset() at the start of any test that
## builds its own units and exercises a code path depending on this cache, or it may silently
## reuse a neighboring test's stale grid instead of rebuilding from its own fixtures (see
## .claude/memories/sparta.md, "A new physics-frame-keyed static cache...").

# Cell size must exceed the largest real query radius (self radius + candidate radius +
# candidate reach) -- identical rationale and value to SoldierEnemyProximity.CELL_SIZE (the
# physical inputs are the same; only the indexed POPULATION differs). Re-check this margin if
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


## Rebuild the grid from the caller-gathered engaged-tier arrays -- parallel
## pos/team/radius/reach, one entry per engaged soldier on either team. Idempotent within a
## frame.
static func rebuild(pos: PackedVector2Array, team: PackedInt32Array, radius: PackedFloat32Array,
		reach: PackedFloat32Array, frame: int) -> void:
	if frame == _frame:
		return
	_frame = frame
	_cells.clear()
	_pos = pos
	_team = team
	_radius = radius
	_reach = reach
	for i in range(_pos.size()):
		var key := _key(_pos[i])
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		_cells[key].append(i)


## Nearest engaged enemy soldier within striking distance of `pos` (same reach-asymmetric
## contact radius as SoldierEnemyProximity.has_enemy_within -- either side's own reach
## counts), or an empty Dictionary if none. Returns {"position": Vector2, "reach": float} for
## the closest candidate by squared distance. Ties break on insertion order (the
## first-encountered candidate wins) -- that order is itself deterministic (see the class doc
## comment above), so no separate tie-break key is needed.
static func nearest_enemy(pos: Vector2, team: int, self_radius: float, self_reach: float) -> Dictionary:
	var c := _key(pos)
	var best_d2: float = -1.0
	var best_idx: int = -1
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell: Variant = _cells.get(Vector2i(c.x + dx, c.y + dy))
			if cell == null:
				continue
			for idx in cell:
				if _team[idx] == team:
					continue
				var contact: float = self_radius + _radius[idx] + maxf(self_reach, _reach[idx])
				var d2: float = pos.distance_squared_to(_pos[idx])
				if d2 > contact * contact:
					continue
				if best_idx == -1 or d2 < best_d2:
					best_d2 = d2
					best_idx = idx
	if best_idx == -1:
		return {}
	return {"position": _pos[best_idx], "reach": _reach[best_idx]}


## Forget any built grid so the next rebuild() runs. Used by tests for isolation.
static func reset() -> void:
	_frame = -1
	_cells.clear()
	_pos = PackedVector2Array()
	_team = PackedInt32Array()
	_radius = PackedFloat32Array()
	_reach = PackedFloat32Array()
