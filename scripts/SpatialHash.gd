class_name SpatialHash
extends RefCounted
## Per-physics-frame spatial hash for unit separation.
##
## Battle rebuilds this once at the start of each tick (before the Units process);
## Unit._separate() then queries the 3x3 cell block around a unit to get a small
## superset of possible overlaps, replacing the old O(n^2) all-pairs scan with
## O(n) bucketing + local neighbourhoods.
##
## When no grid has been built for the current frame (e.g. a unit test that calls
## _separate() directly, with no Battle running), callers fall back to a full
## group scan — see Unit._separation_candidates().

# The cell size must exceed the widest centre-based separation floor (cavalry+cavalry
# = 48) and melee contact range plus a unit's per-frame drift, so querying the 3x3
# block around a position is a guaranteed superset of every unit within those
# distances. A frontal pair's MeleeFrontLine extensions reach further, up to the two
# blocks' front-rank depths, so query() takes a radius and widens the block to cover
# it. The per-pair distance check in _separate() then filters that superset down to
# the exact same set of overlaps a brute-force scan would find.
const CELL_SIZE := 128.0

static var _frame: int = -1
static var _cells: Dictionary = {}
# The largest MeleeFrontLine.extension_depth of any unit in this frame's grid.
static var _max_extension_depth: float = 0.0


static func _key(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL_SIZE)), int(floor(p.y / CELL_SIZE)))


## True when the grid has been rebuilt for `frame` and can be queried.
static func is_current(frame: int) -> bool:
	return frame == _frame


## Rebuild the grid from the live unit set (units + routers) for this frame.
## Idempotent within a frame, so it is safe to call from more than one place.
static func rebuild(tree: SceneTree, frame: int) -> void:
	if frame == _frame:
		return
	_frame = frame
	_cells.clear()
	_max_extension_depth = 0.0
	var all: Array = tree.get_nodes_in_group("units")
	all.append_array(tree.get_nodes_in_group("routers"))
	for o in all:
		var n: Node2D = o as Node2D
		if n == null:
			continue
		if n is Unit:
			_max_extension_depth = maxf(_max_extension_depth,
					MeleeFrontLine.extension_depth(n as Unit))
		var key := _key(n.position)
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append(n)


## Candidate units in the cell block around `pos` — a superset of every unit within
## `radius` (at least CELL_SIZE, the 3x3 block). Traversal order is deterministic (fixed
## dx/dy loop, then each cell's insertion order), so separation results are reproducible
## for replays.
static func query(pos: Vector2, radius: float = CELL_SIZE) -> Array:
	var out: Array = []
	var c := _key(pos)
	var rings: int = maxi(1, ceili(radius / CELL_SIZE))
	for dx in range(-rings, rings + 1):
		for dy in range(-rings, rings + 1):
			var cell: Variant = _cells.get(Vector2i(c.x + dx, c.y + dy))
			if cell != null:
				out.append_array(cell)
	return out


## Forget any built grid so the next rebuild() runs. Used by tests for isolation.
static func reset() -> void:
	_frame = -1
	_cells.clear()
	_max_extension_depth = 0.0


## The largest MeleeFrontLine.extension_depth of any unit in the current grid.
static func max_extension_depth() -> float:
	return _max_extension_depth
