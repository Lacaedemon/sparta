class_name OrderFootprint
## Unit-level validation of a move order's destination against impassable terrain and
## the edge of the field: an officer does not order his block into a cliff, or off the
## map. Routing (PathField.next_step) only steers
## the unit's CENTRE to the ordered point, so a point just outside a hill was accepted and
## a deep block's rear ranks ended up standing inside it. This tests the whole formation
## footprint at the destination, in the facing it will hold there, and pulls an
## overlapping destination back along the move toward the unit's start until the
## footprint is clear. When no point along the move is clear, the unit holds where it is.
## A unit whose footprint already overlaps terrain where it stands (a deep block spawned
## against a hill) is not frozen there: its order is pulled back only as far as needed to
## overlap the terrain no more than it already does, so it can still step out or along.
## Ground outside the field counts as impassable in the same way: a block is pulled back
## until it fits on the field, and one already overhanging the edge may move but not
## further off. Terrain and off-field ground share one overlap budget, so a block may
## trade one for the other, and a hill reaching past the edge counts twice where it does.
## The rule bounds the overlapping AREA, up to AREA_SLACK, so successive orders can never
## ratchet a block deeper by more than that; it does not bound penetration depth, so a
## block may trade overlap along one edge for the same area reaching farther in along
## another.
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

## Overlap area (square wu) an order from an already-overlapping start may add before it
## counts as deeper: float rounding only. The off-field and terrain areas are both clipped
## in the footprint's own centre-relative frame (see _outside_area and
## PathField.footprint_overlap_area), so a block sliding straight along an edge reads
## exactly the area it started with; this is far too small for successive orders to
## ratchet a block anywhere.
const AREA_SLACK := 0.001   # tuned in wu


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
		return overlap.call(p) > start_overlap + AREA_SLACK
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


## Which constraint a footprint centred on `dest` violates: TERRAIN when it overlaps
## impassable block terrain (the more specific cause, so it wins when both apply),
## FIELD_EDGE when it only reaches outside `bounds`, NONE when it is clear. Same arguments
## as clamp_destination(); a pure helper so a caller that already knows an order was
## clamped can say which constraint bound without re-deriving the geometry.
enum Constraint { NONE, TERRAIN, FIELD_EDGE }
static func binding_constraint(field: PathField, dest: Vector2, file_axis: Vector2,
		half_extents: Vector2, bounds: Rect2 = Rect2()) -> int:
	if field != null and field.footprint_blocked(dest, file_axis, half_extents):
		return Constraint.TERRAIN
	if _leaves_bounds(dest, file_axis, half_extents, bounds):
		return Constraint.FIELD_EDGE
	return Constraint.NONE


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
## Clipped against the four edges in turn (Sutherland-Hodgman), in coordinates relative
## to the footprint's own centre: Vector2 holds 32-bit floats, and a shoelace sum over
## field-sized coordinates rounds by most of a square wu, while one over the footprint's
## own half-extents stays exact to far below AREA_SLACK. A footprint slid along an edge
## must read the same area it started with, or the overhang rule would hold it in place.
static func _outside_area(centre: Vector2, file_axis: Vector2, half: Vector2,
		bounds: Rect2) -> float:
	if not _leaves_bounds(centre, file_axis, half, bounds):
		return 0.0
	var poly := _corners(Vector2.ZERO, file_axis, half)
	var local := PathField._relative_rect(bounds, centre)
	var inside: PackedVector2Array = PathField._clip_to_rect(poly, local)
	return maxf(0.0, 4.0 * half.x * half.y - absf(PathField._polygon_area(inside)))
