class_name PathField
extends RefCounted
## Deterministic pathfinding layer. Units route around blocked terrain instead
## of walking straight through it.
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
##
## Two layers of obstacle geometry, serving different jobs:
## - The EXACT terrain rects decide what is actually blocked: every sightline
##   test (the straight-line fast path, string-pulling visibility, is_blocked)
##   runs against the drawn rects themselves, grown by the caller's own
##   `clearance` — so the routed footprint is the terrain the player sees plus
##   the querying unit's real half-extent, not a grid artifact. A rect that
##   overlaps a routing cell by a sliver no longer blocks the whole cell.
## - The coarse CELL grid only supplies A* with a corridor topology (which way
##   around an obstacle). Its cells stay conservatively blocked on any overlap,
##   which is fine for topology: the funnel step against the exact rects is what
##   picks the waypoint actually steered for (the clearance-grown blocking
##   rect's own corner on the corridor's side — see _funnel_corner), so the
##   walked path hugs the drawn terrain plus the unit's own margin regardless
##   of where the cell boundaries fall.

# A coarse routing grid — far wider than a unit footprint, since this is for
# corridor topology around walls/terrain, not unit-vs-unit spacing (that stays
# in _separate()).
const CELL := 64.0

# Published instance the units consult. null => everyone moves in straight lines.
static var active: PathField = null

var _cell: float
var _origin: Vector2
var _cols: int
var _rows: int
var _blocked: Dictionary = {}            # Vector2i -> true (A* corridor topology only)
var _block_rects: Array[Rect2] = []      # exact terrain rects; all sightline tests
var _speed_rects: Array[Rect2] = []      # exact speed-zone rects, registration order
var _speed_scales: PackedFloat32Array = PackedFloat32Array()


func _init(bounds: Rect2, cell: float = CELL) -> void:
	_cell = cell
	_origin = bounds.position
	_cols = int(ceil(bounds.size.x / cell))
	_rows = int(ceil(bounds.size.y / cell))


## Register `rect` (world space) as impassable terrain: stored exactly for the
## sightline tests, and coarsened onto the A* grid for corridor topology.
func block_rect(rect: Rect2) -> void:
	_block_rects.append(rect)
	var lo := _cell_coord(rect.position)
	# rect.end is exclusive: nudge inward so a cell-aligned edge maps to the last
	# overlapped cell, not the next one over (which would block a wider band).
	var hi := _cell_coord(rect.end - Vector2(0.001, 0.001))
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var c := Vector2i(cx, cy)
			if _in_bounds(c):
				_blocked[c] = true


## Whether `world` sits inside impassable terrain, grown by `clearance` on every
## side. Exact-rect test: a point in the routing cell an obstacle merely clips
## is NOT blocked.
func is_blocked(world: Vector2, clearance: float = 0.0) -> bool:
	for r in _block_rects:
		if r.grow(clearance).has_point(world):
			return true
	return false


## Speed zone (not obstacle): units slow on entry but A* never detours around it — penalty applies on traversal only.
func set_speed_rect(rect: Rect2, scale: float) -> void:
	_speed_rects.append(rect)
	_speed_scales.append(scale)


## Speed scale at `world` position (1.0 if no speed zone is registered there).
## Exact-rect test; where zones overlap, the last-registered one wins (the same
## precedence the old per-cell overwrite gave).
func speed_at(world: Vector2) -> float:
	var out: float = 1.0
	for i in _speed_rects.size():
		if _speed_rects[i].has_point(world):
			out = _speed_scales[i]
	return out


## The next world-space waypoint a unit at `from` should steer toward to reach
## `to`. Straight to the target when the line is clear; otherwise the funnel
## corner of the clearance-grown blocking rect on the A* corridor's side -- or,
## when no corner is cleanly visible, the farthest point of the A* route still
## in direct line of sight (falls back to `to` if no route is found).
##
## The lookahead (string-pulling) matters for formations: an A* path is an
## 8-connected polyline of CELL-sized legs, so the bearing to the ADJACENT path
## point jumps in coarse quanta as the walker crosses cells -- a regiment
## steering by it whipsaws far off its true corridor direction and back (a
## shallow one-cell detour reads as a hard ~68 deg turn followed by a hard
## counter-turn), and the soldier bodies scramble after the swinging slot grid.
## The A* lookahead alone still walks the CELL lane, though: mid-detour the
## farthest visible cell centre sits along the coarse corridor, so units of
## very different widths all converge onto the same lane, up to about a cell
## wider than their own clearance requires. The funnel corner is what makes the
## walked detour tangent the grown rect's corners and run straight along the
## grown boundary between them -- the drawn terrain plus exactly this unit's
## own margin. The adjacent path point remains the last fallback when a genuine
## corner blocks every farther candidate.
##
## `clearance` is the querying unit's own half-extent (see Unit.terrain_clearance):
## sightlines treat the terrain rects as grown by it, so a wide block rounds an
## obstacle with its flank — not its centre — skimming the drawn edge.
##
## `lane_offset` shifts the funnel corner sideways, along its own tangent
## direction (see _funnel_corner) — purely a routing-tie-break knob for the
## caller, not a distance this function measures anything against. Two units
## of the same type, clearance, and heading resolve to the identical funnel
## corner otherwise (PathField never reads unit identity or position, only
## static geometry — see Unit.funnel_lane_offset for why that determinism
## matters and how the offset is derived). Zero by default, so a solo query
## still steers for the exact geometric corner.
func next_step(from: Vector2, to: Vector2, clearance: float = 0.0, lane_offset: float = 0.0) -> Vector2:
	if not _segment_blocked(from, to, clearance):
		return to
	var path := find_path(from, to)
	if path.size() < 2:
		return to
	# Corridor candidate: the farthest A* path point in direct line of sight.
	# Candidate waypoints are synthetic cell centres, not real destinations,
	# so the room-available cap must not quietly shrink their sightlines (see
	# _segment_blocked): prefer the farthest candidate that clears the FULL
	# margin. Only when no candidate can — the unit's own margin is wider
	# than the room the A* corridor's cells offer at all (a broad line
	# rounding this field's obstacles) — fall back to the farthest candidate
	# at the room actually available, which degrades the margin smoothly
	# rather than collapsing steering to the adjacent cell's coarse bearing.
	var corridor: Vector2 = path[1]
	var full_margin_candidate: bool = false
	for i in range(path.size() - 1, 1, -1):
		if not _segment_blocked(from, path[i], clearance, false):
			corridor = path[i]
			full_margin_candidate = true
			break
	if not full_margin_candidate:
		for i in range(path.size() - 1, 1, -1):
			if not _segment_blocked(from, path[i], clearance, true):
				corridor = path[i]
				break
	# Funnel refinement: the corridor candidate is a cell centre ON the coarse
	# A* lane, so mid-detour every unit walks that same lane — up to about a
	# cell wider than its own clearance requires. Steer instead for the
	# clearance-grown blocking rect's own corner on the corridor's side, so the
	# walked detour tangents the grown corner and runs straight along the grown
	# boundary between corners: the drawn terrain plus exactly this unit's own
	# margin. The corner is computed from the grown rect's geometry — never from
	# repeatedly re-capped sightline probes, whose standoff ratchets inward leg
	# by leg (each re-tangent caps at the current distance and the walker slowly
	# spirals into the obstacle over a long straightaway). The corridor point
	# stays the fallback whenever no grown corner is cleanly visible (compound
	# obstacle geometry, or a walker already shoved inside its own margin).
	var corner: Vector2 = _funnel_corner(from, to, path, clearance, lane_offset)
	if corner.is_finite():
		return corner
	return corridor


## Whether a from..to leg actually needs a detour -- i.e. the straight line
## itself is blocked by clearance-grown terrain, so next_step() won't just
## return `to` verbatim. Exposed so a caller can cheaply gate more expensive
## per-leg bookkeeping (Unit.funnel_lane_offset's same-team congestion check)
## on "is this unit actually about to detour" without duplicating
## _segment_blocked's own rect-margin logic, or paying for that bookkeeping on
## every straight-line leg a marching unit ever takes.
func is_leg_blocked(from: Vector2, to: Vector2, clearance: float = 0.0) -> bool:
	return _segment_blocked(from, to, clearance)


## Whether a route from `from` to `to` actually exists: either the straight line
## is clear, or (when it isn't) A* found a real path around the obstacles.
## Unlike next_step()'s return value, this makes the "no route exists" case
## distinguishable from "the straight line is clear" -- both of which make
## next_step() fall back to returning `to` verbatim.
func has_path(from: Vector2, to: Vector2, clearance: float = 0.0) -> bool:
	if not _segment_blocked(from, to, clearance):
		return true
	return not find_path(from, to).is_empty()


## Whether a genuine escape route exists heading `direction` from `from`: the
## straight line is clear, or A* finds a route around obstacles. The candidate
## target is clipped to just inside this field's own grid bounds first --
## querying has_path() against a point beyond the grid is meaningless, since
## A* can never reach a goal outside `_in_bounds()` regardless of terrain, so
## an unclipped far-off target would always read as "no path" on open ground.
func has_escape_route(from: Vector2, direction: Vector2, clearance: float = 0.0) -> bool:
	return has_path(from, _clip_to_bounds(from, direction.normalized()), clearance)


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
func next_step_fleeing(from: Vector2, direction: Vector2, clearance: float = 0.0) -> Vector2:
	var dir: Vector2 = direction.normalized()
	var clipped: Vector2 = _clip_to_bounds(from, dir)
	# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
	if from.distance_squared_to(clipped) < _cell * _cell:
		return from + dir * 1000.0
	return next_step(from, clipped, clearance)


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
## endpoints share a cell, the goal is blocked, or no route exists). A blocked
## START cell is passable to leave: cells block conservatively on any rect
## overlap while footprints are exact, so a walker can legitimately stand on
## the clear ground of a cell an obstacle only clips — failing there would
## silently drop the detour (the caller falls back to a straight step) right
## next to the terrain, where the detour matters most.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := _cell_coord(from)
	var goal := _cell_coord(to)
	if start == goal or _blocked.has(goal):
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


# Slack subtracted from the room actually available when capping a sightline's
# margin below, so a point sitting exactly at its capped margin reads as just
# outside the grown rect instead of touching it (which would block every
# sightline from that point at t=0). Purely a float-boundary guard.
const CLEARANCE_SLACK := 0.5   # tuned in wu

# How far outside the clearance-grown boundary a funnel corner waypoint is
# placed: a segment ENDING exactly on the grown boundary counts as touching it
# (segment_intersects_rect counts endpoints), so the tangent leg toward a corner
# sitting right on the margin would read as blocked. Must exceed CLEARANCE_SLACK.
# A solver epsilon like the slack above, not a gameplay margin.
const CORNER_STANDOFF := 2.0   # tuned in wu, solver epsilon

# A funnel corner this close to the walker is "reached": steering for it again
# would aim the unit at (nearly) its own feet and stall the walk at the corner --
# the NEXT corner along the boundary always loses a straight-line cost comparison
# to the one underfoot (triangle inequality), so the reached corner must be
# excluded rather than out-scored. Half a routing cell, because it must dominate
# a formed REGIMENT's own position wobble: the unit anchor follows its soldier
# bodies (SoldierBodies.couple), which swings a wide line's position by tens of
# wu while cornering -- a smaller radius lets the wobble flip the corner in and
# out of "reached" and the regiment orbits a corner it keeps re-targeting
# (observed on a 120-man line at a 4.0 radius). When excluding the near corner
# leaves no visible candidate for a beat, next_step's corridor fallback covers
# the handoff. Solver epsilon, same family as the two above.
const CORNER_ARRIVE_EPS := CELL * 0.5   # tuned in wu, solver epsilon

# How far off the corridor_axis line (in world units, measured as perpendicular
# distance -- |cross| / axis.length(), not a raw cross-product magnitude, so
# this reads on the same length scale as the corridor itself regardless of
# axis magnitude) a route_side candidate point may sit before it still counts
# as informative. In EXACT arithmetic a path point that truly lies on the
# axis line reads a cross of precisely 0.0 -- but float32 doesn't hold that:
# two independently-rounded subtractions (`p - centre` for two different `p`)
# can leave one point at exactly 0.0 and a genuinely-collinear sibling at a
# tiny nonzero float-rounding residual, so an exact `== 0.0` test can let
# that rounding noise decide a route's side instead of correctly reading "no
# preference." 0.001 wu sits roughly 4x above a measured worst-case float32
# rounding artifact across this map's own coordinate range (Battle.FIELD is
# 1600x1200 wu; a measured worst case there is about 2.44e-4 wu -- well
# under one order of magnitude, not the order-of-magnitude margin an
# ULP-scale back-of-envelope estimate would suggest) while staying two to
# three orders of magnitude below the smallest REAL geometric margin in this
# file (CLEARANCE_SLACK, 0.5 wu) -- enough headroom to absorb roundoff
# without mistaking it for a real near-miss, far too small to mask any
# genuine one.
const ROUTE_SIDE_COLLINEAR_EPS := 0.001   # tuned in wu, solver epsilon

## True if the straight segment from..to crosses any terrain rect, each grown by
## the sightline's margin on every side. Exact geometry against the drawn rects —
## not the routing cells — so a line that merely passes through a cell an
## obstacle clips stays clear, and the only margin is the one the caller's own
## footprint needs.
##
## The margin for each rect is `clearance`, capped at the room actually
## available at the segment's REAL endpoints: a unit already inside its own
## margin (spawned or shoved there) keeps sightlines at the standoff it has —
## it can slide along or away from the obstacle, just never deeper — instead
## of every test failing where it stands; and a leg whose destination sits
## inside the margin (a commanded move or attack to the obstacle's very edge)
## is judged at the room the destination leaves, so orders there remain
## reachable. Legs between far-off points keep the full margin.
##
## `cap_to` marks whether `to` is such a real endpoint. A string-pull CANDIDATE
## waypoint is not — it's a synthetic A* cell centre, and an open cell adjoining
## a blocked one sits only half a routing cell from the drawn rect, so capping
## on it would silently shrink every corner sightline to ~half a cell no matter
## how wide the querying unit is, letting its flank cut into terrain exactly
## where routing bends. Candidates must clear the FULL margin (cap_to false);
## a candidate inside the margin is simply not picked.
func _segment_blocked(from: Vector2, to: Vector2, clearance: float = 0.0,
		cap_to: bool = true) -> bool:
	for r in _block_rects:
		var room: float = _distance_to_rect(from, r)
		if cap_to:
			room = minf(room, _distance_to_rect(to, r))
		var eff: float = minf(clearance, room - CLEARANCE_SLACK)
		if segment_intersects_rect(from, to, r.grow(maxf(0.0, eff))):
			return true
	return false


## Distance from `p` to the nearest point of `r` (0 inside the rect).
static func _distance_to_rect(p: Vector2, r: Rect2) -> float:
	return p.distance_to(Vector2(clampf(p.x, r.position.x, r.end.x),
			clampf(p.y, r.position.y, r.end.y)))


## Index into _block_rects of the FIRST rect the from..to segment enters (each
## grown by the same room-capped margin _segment_blocked judges real endpoints
## with), or -1 when none blocks it. The first-entered rect is the one a detour
## must round first.
func _first_blocking_rect_index(from: Vector2, to: Vector2, clearance: float) -> int:
	var best_idx: int = -1
	var best_t: float = INF
	for i in _block_rects.size():
		var r: Rect2 = _block_rects[i]
		var room: float = minf(_distance_to_rect(from, r), _distance_to_rect(to, r))
		var eff: float = minf(clearance, room - CLEARANCE_SLACK)
		var t: float = segment_rect_entry(from, to, r.grow(maxf(0.0, eff)))
		if t < best_t:
			best_t = t
			best_idx = i
	return best_idx


## The next funnel waypoint for a blocked from..to leg: the corner of the
## clearance-grown first-blocking rect, on the A* corridor's side of the leg,
## that is cleanly visible at the full margin and cheapest by straight-line
## detour cost. Returns Vector2.INF when no corner qualifies -- the caller keeps
## the corridor cell centre instead (compound obstacle geometry where every
## corner of the first rect is masked by another, or a walker already inside its
## own margin, whose sightlines the room cap handles on the corridor path).
##
## The corner comes from the grown rect's own geometry, deliberately NOT from a
## re-capped sightline probe: probing "pull the waypoint toward the goal until
## the sightline just grazes" caps each leg's standoff at the walker's current
## distance minus slack, and every re-tangent then re-caps from the new,
## slightly smaller standoff -- ratcheting the margin inward until a long
## straightaway walks the unit into the obstacle. A geometric corner is the
## same point every tick regardless of how close the last leg drifted.
##
## `lane_offset` nudges each of the (up to 4) candidate corners along the
## rect's own tangent direction — perpendicular to `heading` — before the
## visibility and cost checks run, so an offset candidate is only accepted
## when it still clears the obstacle by the full margin, exactly like the
## un-offset corner. This still returns the same point every tick for a given
## `lane_offset` (it's baked into the candidate before any sightline test
## runs, not derived from one), so it doesn't reopen the ratcheting hazard
## the paragraph above rules out.
func _funnel_corner(from: Vector2, to: Vector2, path: PackedVector2Array, clearance: float,
		lane_offset: float = 0.0) -> Vector2:
	var idx: int = _first_blocking_rect_index(from, to, clearance)
	if idx < 0:
		return Vector2.INF
	var rect: Rect2 = _block_rects[idx]
	var grown: Rect2 = rect.grow(clearance + CORNER_STANDOFF)
	var heading: Vector2 = to - from
	var tangent: Vector2 = heading.orthogonal().normalized() if heading.length_squared() > 0.0 else Vector2.ZERO
	var centre: Vector2 = rect.get_center()
	# Which way around THIS rect: the side of the rect the A* route squeezes
	# past on -- which can deliberately be the geometrically-longer way, when
	# other obstacles block the short one. Measured about the rect's own
	# centre and the CORRIDOR's own axis (`corridor_axis` below) -- never
	# `heading` (to - from) and never the route's deviation from the from->to
	# chord: on a graze (the chord clipping just the grown corner, endpoints
	# both already past the rect) the route and the chord sit on the SAME
	# side of each other while the rounding side is still well-defined about
	# the rect -- a chord-side reading there flips the funnel to the far
	# corner and oscillates the walker in place.
	#
	# Two prior attempts at this axis both failed under review, and the
	# reasons rule out the whole design space they represent:
	# - `heading` itself: `from` is the querying unit's own live position,
	#   which drifts by a fraction of a world unit most ticks even while the
	#   unit is otherwise stationary (soldier-body coupling, the same
	#   routine noise Unit._move_to's own BEARING_STEER_FREEZE_RADIUS
	#   comment describes for a different call site). Whenever the nearest
	#   path point and the rect centre sit close to collinear with
	#   `heading`, that noise is enough to flip the sign of the cross
	#   product below -- a near-cancellation of two large terms whose
	#   magnitude can sit within single digits while the terms themselves
	#   are in the tens of thousands -- whipsawing the funnel between two
	#   near-opposite corners every tick, worst for an extreme-aspect-ratio
	#   (wide, single-rank) formation whose `clearance`
	#   (Unit.terrain_clearance, itself Unit._pivot_radius() derived) is
	#   large enough to make a routing detour reach a rect hundreds of world
	#   units away in the first place.
	# - A FIXED axis (`to - centre`) removes that noise, but breaks the
	#   opposite case: test_funnel_walk_hugs_the_boundary_without_ratcheting_inward
	#   walks a real, multi-corner detour by re-querying next_step every
	#   step, and needs the corner classification to re-aim as the walker
	#   passes the first corner and approaches the second -- a fixed axis
	#   can't distinguish "still approaching" from "already rounded", and
	#   the walker got stuck oscillating between the two corners of one
	#   wall face, well short of arriving.
	# - A THRESHOLD switching between the two (heading normally, the fixed
	#   axis only when heading is near-collinear) fixes both of the above,
	#   but reintroduces the identical whipsaw AT the threshold itself:
	#   `heading` and the fixed axis can classify a corner on OPPOSITE
	#   sides, so a `from` perturbation of a couple of world units -- well
	#   under one tick of movement -- that crosses the threshold flips the
	#   chosen corner exactly as before, just relocated to a different
	#   `from` value.
	#
	# The fix is to stop deriving the axis from `from`/`to` at all.
	# `corridor_axis` is a function of the corridor itself -- both endpoints
	# are CELL centres (find_path's own nodes), so this axis only changes in
	# CELL-sized steps as `from`/`to` cross routing cells: no per-tick,
	# sub-world-unit noise reaches it, and no continuous threshold sits
	# between two disagreeing formulas.
	#
	# One endpoint is always `path`'s own LAST point (the cell nearest `to`):
	# `path[path.size() - 1]` advances in CELL-sized steps as the walker's
	# own cell changes while it walks a multi-corner route, which is what
	# the walk test above needs (a fixed axis can't distinguish "still
	# approaching" from "already rounded" -- see the rejected fixed-axis
	# attempt above). The OTHER endpoint is deliberately NOT always
	# `path[0]` (the cell nearest `from`): it's the path point CLOSEST to
	# the rect being rounded -- `nearest_point` below, found by plain
	# distance, no axis needed -- falling back to `path[0]` whenever that
	# nearest point turns out to BE the last point (the rect sits right at
	# the corridor's own far end, so there's no "middle" to anchor on; using
	# `path[0]` there reproduces this fix's very first version exactly,
	# which every one of this file's simpler tests already exercises).
	#
	# Anchoring on the nearest point rather than `path[0]` matters because a
	# LONG, multi-leg corridor's own start-to-end chord can point in a
	# meaningfully different direction than the corridor's actual approach
	# to THIS rect: `path[0]` sits back at the querying unit's own cell,
	# `path[-1]` sits past a later leg the route takes only after it has
	# already rounded the rect, and averaging the two into one straight-line
	# axis can land near neither. Measured repro: a wide single-rank Cavalry
	# formation's funnel query against this file's own default-map hill
	# terrain, where the full start-to-end axis lands on an EXACT
	# 45-degree grid diagonal through the rect's own centre -- both
	# components identical multiples of CELL -- misclassifying the
	# entry/exit corner PAIR on opposite sides of where `heading` (and the
	# nearest-point axis below) put them: the near, correct-direction corner
	# reads as excluded, and the far, wrong-direction one reads as
	# included and, being cheaper, wins the tie-break outright. Anchoring
	# on the path point nearest the rect instead of `path[0]` fixes this
	# because that point is exactly where the corridor actually interacts
	# with the rect, the same locality `route_side` below already keys off
	# of -- so the axis and the route_side it measures describe the same
	# approach, not two different legs of a longer corridor stitched
	# together.
	#
	# The one instability left is a walker whose EQUILIBRIUM position sits
	# exactly ON a cell boundary and straddles it tick to tick, so the path
	# (and with it either endpoint) flips between two cells -- a much
	# narrower target (a 64-world-unit grid line, not every position
	# everywhere) than the whipsaw this axis removes, and a limitation of
	# routing off a coarse cell grid this file already carries (see
	# `find_path` and the CELL const) rather than a new one this axis
	# introduces.
	#
	# Whichever pair of path points supplies it, `route_side` here and each
	# candidate corner's own `side` further down MUST read the SAME axis:
	# comparing a side computed on one axis against a route_side computed on
	# another compares two unrelated quantities, and can point the filter at
	# the wrong corners entirely rather than merely at an
	# occasionally-unstable one (measured on this function's own
	# hill-terrain repro: `to=(650,730)` and `centre=(1275,480)` put
	# `heading` and `to - centre` about 179 degrees apart there, flipping
	# the sign of all four of the rect's corners relative to each other).
	var nearest_point: Vector2 = Vector2.ZERO
	var nearest_point_d: float = INF
	for p in path:
		var d: float = _distance_to_rect(p, rect)
		if d < nearest_point_d:
			nearest_point_d = d
			nearest_point = p
	var corridor_axis: Vector2 = Vector2.ZERO
	if path.size() >= 2:
		corridor_axis = path[path.size() - 1] - nearest_point
		if corridor_axis.length_squared() <= 0.0:
			corridor_axis = path[path.size() - 1] - path[0]
	if corridor_axis.length_squared() <= 0.0:
		# A degenerate corridor (its last cell centre coincides with both
		# `path[0]` and the point nearest the rect, or an empty/single-point
		# `path` -- reachable only from a direct call in tests; next_step's
		# own `path.size() < 2` guard never lets a live query reach this
		# function with such a `path`) has no axis of its own to measure
		# against. `heading` is the least surprising fallback, matching this
		# function's behaviour before any of this axis machinery existed.
		corridor_axis = heading
	# The corridor point that FIXES route_side is the nearest one whose side
	# is clearly off the axis line through `centre` -- not simply the
	# nearest point outright, and not an exact `cross == 0.0` test either.
	# The nearest point can itself land (near enough to float rounding)
	# right on the axis line through `centre`, "no preference," purely by
	# coincidence of where that one point happens to sit, while a farther
	# path point still carries a real, informative side. Skipping a point
	# that close to the axis costs nothing -- it was never going to filter
	# anything reliably on its own -- and can only make route_side MORE
	# informative, never less. When EVERY path point sits within tolerance
	# of that line (in EXACT arithmetic the corridor's own two endpoints
	# always read the identical cross against `centre` -- see
	# ROUTE_SIDE_COLLINEAR_EPS and this file's test for the identity and why
	# float32 alone can't be trusted to hold it exactly -- so if they, or
	# the whole straight-line corridor, sit on that line, so does everything
	# else on it), no point can rescue it and route_side correctly stays
	# 0.0: a fully axis-degenerate corridor has no side to prefer, the same
	# "no preference" semantics the empty-path case already pins
	# intentionally.
	var route_side: float = 0.0
	var nearest_d: float = INF
	var axis_len: float = corridor_axis.length()
	for p in path:
		# axis_len can still be exactly 0.0 here -- the length_squared()
		# fallback to `heading` above only replaces a zero corridor_axis,
		# not a zero `heading` too (from == to). No caller today constructs
		# that combination, but a zero axis makes EVERY cross 0.0 as well
		# (cross of the zero vector is always 0), so guard the division
		# explicitly rather than resting on that being unreachable: a point
		# with nothing to measure against is exactly the "no preference"
		# case this whole loop exists to detect.
		if axis_len <= 0.0:
			continue
		var cross: float = corridor_axis.cross(p - centre)
		# Perpendicular distance from `p` to the axis line, not the raw
		# cross-product magnitude: dividing by axis_len puts this on the
		# same world-unit scale ROUTE_SIDE_COLLINEAR_EPS is tuned against,
		# regardless of how long or short corridor_axis itself happens to
		# be.
		if absf(cross) / axis_len < ROUTE_SIDE_COLLINEAR_EPS:
			continue
		var side: float = signf(cross)
		var d: float = _distance_to_rect(p, rect)
		if d < nearest_d:
			nearest_d = d
			route_side = side
	var best: Vector2 = Vector2.INF
	var best_cost: float = INF
	for raw_c in [grown.position, Vector2(grown.end.x, grown.position.y),
			grown.end, Vector2(grown.position.x, grown.end.y)]:
		var c: Vector2 = raw_c + tangent * lane_offset
		# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
		if from.distance_squared_to(c) < CORNER_ARRIVE_EPS * CORNER_ARRIVE_EPS:
			continue
		# The corner's side about the same centre/axis route_side was
		# measured on (corridor_axis, not `heading` -- see the comment
		# above for why the two must not be mixed): a corner strictly on
		# the other side of the rect from the route is not a candidate.
		# (For a diagonal axis the entry/exit corners shared by both
		# roundings land on either sign -- the filter only excludes the
		# strictly-opposite one.)
		var side: float = signf(corridor_axis.cross(raw_c - centre))
		if route_side != 0.0 and side != 0.0 and side != route_side:
			continue
		if _segment_blocked(from, c, clearance, false):
			continue
		var cost: float = from.distance_to(c) + c.distance_to(to)
		if cost < best_cost:
			best_cost = cost
			best = c
	return best


## Whether the segment from..to touches `rect` (endpoints inside count).
## Deterministic float math, so paths stay replay-reproducible.
static func segment_intersects_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	return is_finite(segment_rect_entry(from, to, rect))


## The segment parameter t in [0, 1] where from..to first enters `rect` (0.0 when
## `from` starts inside), or INF when the segment never touches it. Pure
## Liang-Barsky slab clip: the segment hits the rect iff the parameter interval
## where it is inside all four half-planes is non-empty within [0, 1] -- the
## interval's lower bound is the entry. The funnel uses the entry order to pick
## WHICH blocking rect a detour must round first; segment_intersects_rect is the
## boolean view of the same clip.
static func segment_rect_entry(from: Vector2, to: Vector2, rect: Rect2) -> float:
	var d := to - from
	var t_min: float = 0.0
	var t_max: float = 1.0
	for axis in 2:
		var lo: float = rect.position[axis] - from[axis]
		var hi: float = rect.end[axis] - from[axis]
		if absf(d[axis]) < 0.000001:
			# Segment parallel to this axis pair: blocked on it only if the
			# fixed coordinate already lies inside the slab.
			if lo > 0.0 or hi < 0.0:
				return INF
			continue
		var t0: float = lo / d[axis]
		var t1: float = hi / d[axis]
		if t0 > t1:
			var swap := t0
			t0 = t1
			t1 = swap
		t_min = maxf(t_min, t0)
		t_max = minf(t_max, t1)
		if t_min > t_max:
			return INF
	return t_min
