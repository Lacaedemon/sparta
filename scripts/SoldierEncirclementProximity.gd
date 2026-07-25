class_name SoldierEncirclementProximity
extends RefCounted
## Reach-scoped spatial hash over the ENGAGED tier (both teams), rebuilt fresh each tick by
## SoldierEncirclement.accumulate() from Unit.engaged_soldier_indices() -- the same
## population and CELL_SIZE rationale as SoldierEngagedEnemyProximity (see that class's own
## doc comment for why the population is scoped to the engaged tier rather than a
## whole-battle scan). This class answers a DIFFERENT question than that one, though:
## "give me EVERY contacting enemy's position", not "just the nearest one" --
## SoldierEncirclement needs the full set of contact directions around a soldier to measure
## the angular arc they span (is_surrounded / retreat_direction), which a nearest-only query
## can't answer.
##
## Kept as its own static state rather than adding a second query method onto
## SoldierEngagedEnemyProximity's existing cache: two independently-tested per-tick passes
## populating the same frame-keyed cache from two separately-maintained gather loops is
## exactly the accidental-coupling hazard that class's own doc comment warns against (a
## future change to either gather loop could silently desync the other caller, with nothing
## structural to catch it). Duplicating this small gather+rebuild shape is the same
## tradeoff SoldierEnemyContact and SoldierMeleeStandoff already each make independently
## rather than share one populator.
##
## Determinism: iterates whatever order the caller's gathered arrays are in (SoldierEncirclement
## gathers unit-uid then ascending-soldier-index, mirroring SoldierEnemyContact/
## SoldierMeleeStandoff), buckets purely by position, and enemies_within only reads the frozen
## per-tick position/team/radius/reach arrays passed to rebuild() -- no RNG, no wall-clock.
##
## Testing: frame-keyed like its siblings -- call reset() at the start of any test that builds
## its own units and exercises a code path depending on this cache, or it may silently reuse a
## neighboring test's stale grid instead of rebuilding from its own fixtures (see
## .claude/memories/sparta.md, "A new physics-frame-keyed static cache...").

# Cell size must exceed the largest real query radius (self radius + candidate radius +
# candidate reach) -- identical rationale and value to SoldierEnemyProximity/
# SoldierEngagedEnemyProximity's own CELL_SIZE (the physical inputs are the same; only the
# indexed population and the query shape differ). Re-check this margin if weapon reach or
# mark-radius constants change.
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


## Every enemy soldier's position within striking distance of `pos` (same reach-asymmetric
## contact radius as SoldierEngagedEnemyProximity.nearest_enemy -- either side's own reach
## counts, not just the candidate's), across EVERY contacting enemy rather than just the
## nearest one. Insertion order (deterministic, see class doc) -- an empty array when nothing
## is in range.
static func enemies_within(pos: Vector2, team: int, self_radius: float, self_reach: float) -> PackedVector2Array:
	var out := PackedVector2Array()
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
					out.push_back(_pos[idx])
	return out


## Forget any built grid so the next rebuild() runs. Used by tests for isolation.
static func reset() -> void:
	_frame = -1
	_cells.clear()
	_pos = PackedVector2Array()
	_team = PackedInt32Array()
	_radius = PackedFloat32Array()
	_reach = PackedFloat32Array()
