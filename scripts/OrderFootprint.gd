class_name OrderFootprint
## Unit-level validation of a move order's destination against impassable terrain: an
## officer does not order his block into a cliff. Routing (PathField.next_step) only steers
## the unit's CENTRE to the ordered point, so a point just outside a hill was accepted and
## a deep block's rear ranks ended up standing inside it. This tests the whole formation
## footprint at the destination, in the facing it will hold there, and pulls an
## overlapping destination back along the move toward the unit's start until the
## footprint is clear. When no point along the move is clear, the unit holds where it is.
## A unit whose footprint already overlaps terrain where it stands (a deep block spawned
## against a hill) is not frozen there: its order is pulled back only as far as needed to
## overlap the terrain no more than it already does, so it can still step out or along.
## The rule bounds the overlapping AREA, with no slack, so successive orders can never
## ratchet a block deeper by area; it does not bound penetration depth, so a block may
## trade overlap along one edge for the same area reaching farther in along another.
##
## Static and deterministic (no RNG, a pure function of the obstacle set and the
## arguments), so live play and replay validate alike.

## Default pull-back search step: how far back along the move each probe moves while
## looking for the first clear footprint. Small next to a file pitch, so a clear band
## narrower than a man is the most the coarse pass can step over.
const SEARCH_STEP := 8.0   # tuned in wu

## Default tolerance the search narrows the clear point to once the coarse pass has
## bracketed the terrain edge: the returned destination sits at most this far short of
## the nearest clear point.
const SEARCH_TOLERANCE := 1.0   # tuned in wu


## The destination a move from `origin` toward `dest` should actually be given. `field`
## supplies the impassable terrain; `file_axis` (a unit vector) and `half_extents`
## (half-width, half-depth, already grown by the soldiers' body radius) describe the
## footprint the formation will occupy at the destination. Returns `dest` unchanged when
## its footprint is clear, the clear point nearest `dest` on the segment back to `origin`
## otherwise, and `origin` itself (hold position) when nothing along the move is clear.
## From a start that already overlaps terrain, "clear" means overlapping no more terrain
## area than the start does. `step` and `tolerance` are the search's coarse stride and
## final precision; both must be positive, and a non-positive one fails loudly and holds
## position rather than looping forever. `bounds`, when it has an area, is the ground the
## formation must stay on: everything outside it counts as impassable, so an order is
## pulled back until the whole footprint fits inside, as it is off a hill. `field` may be
## null when there is no terrain to test.
static func clamp_destination(field: PathField, origin: Vector2, dest: Vector2,
		file_axis: Vector2, half_extents: Vector2, step: float = SEARCH_STEP,
		tolerance: float = SEARCH_TOLERANCE, bounds: Rect2 = Rect2()) -> Vector2:
	var blocked := func(p: Vector2) -> bool:
		return (field != null and field.footprint_blocked(p, file_axis, half_extents)) \
				or _leaves_bounds(p, file_axis, half_extents, bounds)
	var overlap := func(p: Vector2) -> float:
		var area: float = _outside_area(p, file_axis, half_extents, bounds)
		if field != null:
			area += field.footprint_overlap_area(p, file_axis, half_extents)
		return area
	if not blocked.call(dest):
		return dest
	if step <= 0.0 or tolerance <= 0.0:
		push_error("OrderFootprint.clamp_destination: step and tolerance must be positive")
		return origin
	var start_overlap: float = 0.0
	if blocked.call(origin):
		start_overlap = overlap.call(origin)
	var too_deep := func(p: Vector2) -> bool:
		if start_overlap <= 0.0:
			return blocked.call(p)
		return overlap.call(p) > start_overlap
	if not too_deep.call(dest):
		return dest
	# Past this point dest != origin: the start is never too deep (it is clear, or exactly
	# as deep as it already stands), so a destination that is must lie elsewhere.
	var back: Vector2 = origin - dest
	var span: float = back.length()
	var dir: Vector2 = back / span
	# Coarse pass: walk back from the destination until a probe is acceptable. The start
	# always is (clear, or exactly as deep as it already stands), so the walk ends there
	# at the latest.
	var blocked_at: float = 0.0
	var clear_at: float = minf(step, span)
	while clear_at < span and too_deep.call(dest + dir * clear_at):
		blocked_at = clear_at
		clear_at = minf(clear_at + step, span)
	# Fine pass: bisect the bracket down to `tolerance`, keeping the acceptable end.
	while clear_at - blocked_at > tolerance:
		var mid: float = (blocked_at + clear_at) * 0.5
		if too_deep.call(dest + dir * mid):
			blocked_at = mid
		else:
			clear_at = mid
	return origin if clear_at >= span else dest + dir * clear_at


## The four corners of the rectangular footprint centred on `centre`, its width along the
## unit vector `file_axis` and its depth perpendicular to it.
static func _corners(centre: Vector2, file_axis: Vector2, half: Vector2) -> PackedVector2Array:
	var u: Vector2 = file_axis * half.x
	var v: Vector2 = file_axis.orthogonal() * half.y
	return PackedVector2Array([centre - u - v, centre + u - v, centre + u + v, centre - u + v])


## Whether the footprint reaches outside `bounds`. A footprint is convex and `bounds` is a
## rect, so it lies inside exactly when every corner does. A `bounds` with no area means
## no bounds.
static func _leaves_bounds(centre: Vector2, file_axis: Vector2, half: Vector2,
		bounds: Rect2) -> bool:
	if not bounds.has_area():
		return false
	for corner in _corners(centre, file_axis, half):
		if corner.x < bounds.position.x or corner.x > bounds.end.x \
				or corner.y < bounds.position.y or corner.y > bounds.end.y:
			return true
	return false


## Area (square world units) of the footprint that lies outside `bounds`: its whole area
## less the part clipped inside. 0 when it lies wholly inside, or `bounds` has no area.
static func _outside_area(centre: Vector2, file_axis: Vector2, half: Vector2,
		bounds: Rect2) -> float:
	if not _leaves_bounds(centre, file_axis, half, bounds):
		return 0.0
	var poly := _corners(centre, file_axis, half)
	var box := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y),
			bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	var inside: float = 0.0
	for piece in Geometry2D.intersect_polygons(poly, box):
		inside += absf(PathField._polygon_area(piece))
	return maxf(0.0, 4.0 * half.x * half.y - inside)
