class_name OrderFootprint
## Unit-level validation of a move order's destination against impassable terrain: an
## officer does not order his block into a cliff. Routing (PathField.next_step) only steers
## the unit's CENTRE to the ordered point, so a point just outside a hill was accepted and
## a deep block's rear ranks ended up standing inside it. This tests the whole formation
## footprint at the destination, in the facing it will hold there, and pulls an
## overlapping destination back along the move toward the unit's start until the
## footprint is clear. When no point along the move is clear, the unit holds where it is.
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
## `step` and `tolerance` are the search's coarse stride and final precision; both must
## be positive, and a non-positive one fails loudly and holds position rather than
## looping forever.
static func clamp_destination(field: PathField, origin: Vector2, dest: Vector2,
		file_axis: Vector2, half_extents: Vector2, step: float = SEARCH_STEP,
		tolerance: float = SEARCH_TOLERANCE) -> Vector2:
	if not field.footprint_blocked(dest, file_axis, half_extents):
		return dest
	if step <= 0.0 or tolerance <= 0.0:
		push_error("OrderFootprint.clamp_destination: step and tolerance must be positive")
		return origin
	var back: Vector2 = origin - dest
	var span: float = back.length()
	if span <= 0.0:
		return origin
	var dir: Vector2 = back / span
	# Coarse pass: walk back from the destination until a probe's footprint is clear.
	var blocked_at: float = 0.0
	var clear_at: float = minf(step, span)
	while field.footprint_blocked(dest + dir * clear_at, file_axis, half_extents):
		if clear_at >= span:
			return origin
		blocked_at = clear_at
		clear_at = minf(clear_at + step, span)
	# Fine pass: bisect the bracket down to `tolerance`, keeping the clear end.
	while clear_at - blocked_at > tolerance:
		var mid: float = (blocked_at + clear_at) * 0.5
		if field.footprint_blocked(dest + dir * mid, file_axis, half_extents):
			blocked_at = mid
		else:
			clear_at = mid
	return dest + dir * clear_at
