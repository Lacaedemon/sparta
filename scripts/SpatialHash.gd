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
# The largest MeleeFrontGeometry.query_extension of any unit in this frame's grid.
static var _max_extension_depth: float = 0.0
# The largest MeleeFrontGeometry.extension_depth of any unit in this frame's grid.
static var _max_front_ext: float = 0.0


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
	var all: Array = tree.get_nodes_in_group("units")
	all.append_array(tree.get_nodes_in_group("routers"))
	_read_deepest(all)
	for o in all:
		var n: Node2D = o as Node2D
		if n == null:
			continue
		var key := _key(n.position)
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append(n)


## Candidate units in the cell block around `pos`: a superset of every unit within
## `radius` (at least CELL_SIZE, the 3x3 block). Traversal order is deterministic (fixed
## dx/dy loop, then each cell's insertion order), so separation results are reproducible
## for replays.
##
## A block wider than one ring scans whichever is fewer: the ring block's cells, or the
## occupied cells, keeping those inside the ring block. A deep block anywhere on the field
## widens every frontal query (MeleeFrontGeometry.query_radius), and a few hundred empty
## cells would cost more than the handful of units there are. The occupied cells are sorted
## into the ring scan's own order (x, then y), so either scan returns the same list.
static func query(pos: Vector2, radius: float = CELL_SIZE) -> Array:
	var out: Array = []
	var c := _key(pos)
	var rings: int = maxi(1, ceili(radius / CELL_SIZE))
	if rings > 1 and _cells.size() < (2 * rings + 1) * (2 * rings + 1):
		var inside: Array[Vector2i] = []
		for key in _cells:
			var k: Vector2i = key
			if absi(k.x - c.x) <= rings and absi(k.y - c.y) <= rings:
				inside.append(k)
		inside.sort()
		for k in inside:
			out.append_array(_cells[k])
		return out
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
	_max_front_ext = 0.0


## The largest MeleeFrontGeometry.extension_depth of any unit in the current grid, as of the
## last rebuild or refresh or the latest note_extension_depth (see refresh_extension_depth).
static func max_front_ext() -> float:
	return _max_front_ext


## The largest MeleeFrontGeometry.query_extension of any unit in the current grid.
static func max_extension_depth() -> float:
	return _max_extension_depth


## Re-read max_extension_depth from the live units, for the current frame's grid. rebuild()
## runs before the tick's orders and tier transitions, and an order that narrows a frontage
## or leaves a square, or a far block promoted close, can deepen a block after it; Battle
## calls this once those have run, and again after the AI. A block deepened later in the tick
## (a reserve merging in) reports its live depth when it next queries (note_extension_depth);
## a partner that queried before that reads it from the next frame's rebuild.
static func refresh_extension_depth(tree: SceneTree) -> void:
	var all: Array = tree.get_nodes_in_group("units")
	all.append_array(tree.get_nodes_in_group("routers"))
	_read_deepest(all)


## Raise max_extension_depth to `depth` if it is larger: a unit that has deepened since the
## last rebuild or refresh reports its live depth before it queries, so a partner that
## queries after it widens enough to find it.
static func note_extension_depth(depth: float, ext: float) -> void:
	_max_extension_depth = maxf(_max_extension_depth, depth)
	_max_front_ext = maxf(_max_front_ext, ext)


## Read the largest MeleeFrontGeometry.query_extension and extension_depth in `units`.
static func _read_deepest(units: Array) -> void:
	_max_extension_depth = 0.0
	_max_front_ext = 0.0
	for o in units:
		var u: Unit = o as Unit
		if u != null:
			var p: MeleeFrontProfile = MeleeFrontProfile.of(u)
			_max_extension_depth = maxf(_max_extension_depth, p.beyond)
			_max_front_ext = maxf(_max_front_ext, p.ext)
