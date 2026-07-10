class_name PathField
extends RefCounted
## Deterministic grid A* pathfinding layer. Units route around blocked
## terrain instead of walking straight through it.
##
## Why not NavigationAgent2D? Its RVO avoidance is non-deterministic (threaded,
## time-based) and would break the fixed-step replay simulation, and the issue
## itself warns RVO fights the melee press. Grid A* is a pure function of the
## obstacle set, so paths are reproducible — the same property the rest of the sim
## relies on. It also sits cleanly ABOVE the custom melee separation: pathing only
## answers "get there around walls"; _separate() still handles unit-vs-unit press.
##
## Battle builds one over the field and publishes it as PathField.active; Unit
## consults it in _move_to() with a straight-line fast path, so with no obstacles
## registered (today) movement is unchanged.

# A coarse routing grid — far wider than a unit footprint, since this is for
# walls/terrain, not unit-vs-unit spacing (that stays in _separate()).
const CELL := 64.0

# Published instance the units consult. null => everyone moves in straight lines.
static var active: PathField = null

var _cell: float
var _origin: Vector2
var _cols: int
var _rows: int
var _blocked: Dictionary = {}   # Vector2i -> true
var _speed: Dictionary = {}     # Vector2i -> float (speed scale; absent = 1.0)


func _init(bounds: Rect2, cell: float = CELL) -> void:
	_cell = cell
	_origin = bounds.position
	_cols = int(ceil(bounds.size.x / cell))
	_rows = int(ceil(bounds.size.y / cell))


## Mark every cell overlapping `rect` (world space) as impassable terrain.
func block_rect(rect: Rect2) -> void:
	var lo := _cell_coord(rect.position)
	# rect.end is exclusive: nudge inward so a cell-aligned edge maps to the last
	# overlapped cell, not the next one over (which would block a wider band).
	var hi := _cell_coord(rect.end - Vector2(0.001, 0.001))
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var c := Vector2i(cx, cy)
			if _in_bounds(c):
				_blocked[c] = true


func is_blocked(world: Vector2) -> bool:
	return _blocked.has(_cell_coord(world))


## Speed zone (not obstacle): units slow on entry but A* never detours around it — penalty applies on traversal only.
func set_speed_rect(rect: Rect2, scale: float) -> void:
	var lo := _cell_coord(rect.position)
	var hi := _cell_coord(rect.end - Vector2(0.001, 0.001))
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var c := Vector2i(cx, cy)
			if _in_bounds(c):
				_speed[c] = scale


## Speed scale at `world` position (1.0 if no speed zone is registered there).
func speed_at(world: Vector2) -> float:
	return _speed.get(_cell_coord(world), 1.0)


## The next world-space waypoint a unit at `from` should steer toward to reach
## `to`. Straight to the target when the line is clear; otherwise the first turn
## of an A* route around the obstacles (falls back to `to` if nothing is found).
func next_step(from: Vector2, to: Vector2) -> Vector2:
	if not _segment_blocked(from, to):
		return to
	var path := find_path(from, to)
	if path.size() >= 2:
		return path[1]
	return to


## Whether a route from `from` to `to` actually exists: either the straight line
## is clear, or (when it isn't) A* found a real path around the obstacles.
## Unlike next_step()'s return value, this makes the "no route exists" case
## distinguishable from "the straight line is clear" -- both of which make
## next_step() fall back to returning `to` verbatim.
func has_path(from: Vector2, to: Vector2) -> bool:
	if not _segment_blocked(from, to):
		return true
	return not find_path(from, to).is_empty()


## Whether a genuine escape route exists heading `direction` from `from`: the
## straight line is clear, or A* finds a route around obstacles. The candidate
## target is clipped to just inside this field's own grid bounds first --
## querying has_path() against a point beyond the grid is meaningless, since
## A* can never reach a goal outside `_in_bounds()` regardless of terrain, so
## an unclipped far-off target would always read as "no path" on open ground.
func has_escape_route(from: Vector2, direction: Vector2) -> bool:
	return has_path(from, _clip_to_bounds(from, direction.normalized()))


## next_step(), but for a fleeing unit with no fixed destination -- just a
## direction to run in. Clips the far-off candidate target to this field's own
## grid bounds first, for the same reason has_escape_route() does: an
## unclipped point outside the grid can never be reached by find_path()'s A*,
## so next_step() would always fall back to the raw straight-line direction --
## silently defeating routing around terrain for every fleeing unit.
##
## Near (or past) this field's own edge, that clip degenerates toward `from`
## itself (_clip_to_bounds pulls the exit point in by one cell, which can put
## it behind `from` once there's less than a cell of grid left to cross) --
## freezing a fleeing unit in place instead of letting it continue on toward
## a caller's own, larger escape boundary. There's no terrain to route around
## out there anyway (this field only ever registers obstacles inside its own
## bounds), so fall back to the raw, unclipped target in that case, the same
## way next_step() itself falls back with no PathField active at all.
func next_step_fleeing(from: Vector2, direction: Vector2) -> Vector2:
	var dir: Vector2 = direction.normalized()
	var clipped: Vector2 = _clip_to_bounds(from, dir)
	if from.distance_to(clipped) < _cell:
		return from + dir * 1000.0
	return next_step(from, clipped)


## The point where a ray from `from` toward `direction` exits this field's grid,
## pulled in by one cell so the result lands solidly in-bounds rather than
## exactly on the edge.
func _clip_to_bounds(from: Vector2, direction: Vector2) -> Vector2:
	var min_pos: Vector2 = _origin
	var max_pos: Vector2 = _origin + Vector2(_cols, _rows) * _cell
	var t: float = INF
	if direction.x > 0.0:
		t = minf(t, (max_pos.x - from.x) / direction.x)
	elif direction.x < 0.0:
		t = minf(t, (min_pos.x - from.x) / direction.x)
	if direction.y > 0.0:
		t = minf(t, (max_pos.y - from.y) / direction.y)
	elif direction.y < 0.0:
		t = minf(t, (min_pos.y - from.y) / direction.y)
	if not is_finite(t):
		return from
	return from + direction * maxf(t - _cell, 0.0)


## Full A* route from `from` to `to` as world-space cell centres (empty when the
## endpoints share a cell, the goal is blocked, or no route exists).
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := _cell_coord(from)
	var goal := _cell_coord(to)
	if start == goal or _blocked.has(goal) or _blocked.has(start):
		return PackedVector2Array()

	var open: Array = [start]
	var came: Dictionary = {}
	var g: Dictionary = {start: 0.0}
	var f: Dictionary = {start: _heuristic(start, goal)}

	while not open.is_empty():
		var current: Vector2i = _lowest_f(open, f)
		if current == goal:
			return _reconstruct(came, current)
		open.erase(current)
		for nb in _neighbours(current):
			var tentative: float = g[current] + _step_cost(current, nb)
			if not g.has(nb) or tentative < g[nb]:
				came[nb] = current
				g[nb] = tentative
				f[nb] = tentative + _heuristic(nb, goal)
				if not open.has(nb):
					open.append(nb)
	return PackedVector2Array()


# --- grid helpers ----------------------------------------------------------

func _cell_coord(world: Vector2) -> Vector2i:
	return Vector2i(int(floor((world.x - _origin.x) / _cell)),
		int(floor((world.y - _origin.y) / _cell)))


func _cell_centre(c: Vector2i) -> Vector2:
	return _origin + Vector2((c.x + 0.5) * _cell, (c.y + 0.5) * _cell)


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _cols and c.y < _rows


func _neighbours(c: Vector2i) -> Array:
	var out: Array = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var n := Vector2i(c.x + dx, c.y + dy)
			if not _in_bounds(n) or _blocked.has(n):
				continue
			# No corner-cutting through a wall: a diagonal needs both shared
			# orthogonal cells open, or units would clip a blocked corner.
			if dx != 0 and dy != 0:
				if _blocked.has(Vector2i(c.x + dx, c.y)) or _blocked.has(Vector2i(c.x, c.y + dy)):
					continue
			out.append(n)
	return out


func _step_cost(a: Vector2i, b: Vector2i) -> float:
	return 1.41421356 if (a.x != b.x and a.y != b.y) else 1.0


func _heuristic(a: Vector2i, goal: Vector2i) -> float:
	return Vector2(a.x - goal.x, a.y - goal.y).length()


func _lowest_f(open: Array, f: Dictionary) -> Vector2i:
	# Linear scan (the routing grid is coarse). First minimum wins, so ties break
	# on insertion order — deterministic, which keeps replays reproducible.
	var best: Vector2i = open[0]
	var best_f: float = f[best]
	for c in open:
		if f[c] < best_f:
			best_f = f[c]
			best = c
	return best


func _reconstruct(came: Dictionary, current: Vector2i) -> PackedVector2Array:
	var cells: Array = [current]
	while came.has(current):
		current = came[current]
		cells.append(current)
	cells.reverse()
	var out := PackedVector2Array()
	for c in cells:
		out.append(_cell_centre(c))
	return out


## True if the straight segment from..to crosses any blocked cell. Sampled at
## half-cell steps, which is dense enough to catch a one-cell-thick wall.
func _segment_blocked(from: Vector2, to: Vector2) -> bool:
	if _blocked.is_empty():
		return false
	var span := to - from
	var steps: int = int(ceil(span.length() / (_cell * 0.5)))
	if steps <= 0:
		return _blocked.has(_cell_coord(to))
	for i in range(steps + 1):
		var p := from + span * (float(i) / float(steps))
		if _blocked.has(_cell_coord(p)):
			return true
	return false
