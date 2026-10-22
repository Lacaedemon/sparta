class_name MeleeFrontLine
## Two blocks in melee meet at their outer ranks, not each grid ordered deep into the other as
## centre-to-centre ranges left them: contact_extension (via within_contact) and floor_from add
## the missing reach back, times weight(). Front to front, each block reaches its front rank. A
## block whose front faces the other's flank or rear reaches its own front rank and the other's
## outer file or rank: the defender fronts every way, as a square does. Cavalry, missile and far
## blocks keep the old ranges. MeleeFrontGeometry and MeleeFrontProfile measure the blocks.


## Vector3(w, reach_a, reach_b). w: the smaller melee_front_line_scale (0..1) times the sum of
## two parts. The frontal part: the fronts' opposition (a ramp from the larger
## melee_front_line_min_cos to 1; a square opposes any front), each block's men lying ahead of
## the other's along the pair's axis (a ramp over one RADIUS, so the weight holds while the
## press closes), and the share of the narrower front facing the other. The side part, for fronts
## too far from opposed (side_gate): the same ahead and overlap terms with one block's front as
## the axis and the other met on whatever side faces it (MeleeFrontGeometry.outline). The reaches
## are the two parts' reaches averaged by their weights.
static func pair(a: Unit, b: Unit) -> Vector3:
	return _pair(a, b, MeleeFrontProfile.of(a), MeleeFrontProfile.of(b))


## What _pair last measured, from a to b: the positions' gap plus the shift toward the men's
## centres (an anchored frontage stands its men off its position) times the weight, so every
## distance the extension reads moves from the positions at weight 0 to the men's centres at 1.
## Read it right after pair(), contact_extension() or toward() for the same a and b.
static var last_gap := Vector2.ZERO


static func _pair(a: Unit, b: Unit, pa: MeleeFrontProfile, pb: MeleeFrontProfile) -> Vector3:
	last_gap = b.position - a.position
	if not (pa.eligible and pb.eligible) or (a.in_square() and b.in_square()):
		return Vector3.ZERO
	var fa: Vector2 = MeleeFrontGeometry.grid_front(a)
	var fb: Vector2 = MeleeFrontGeometry.grid_front(b)
	var opposed: float = 1.0
	var side: float = 0.0
	var axis: Vector2 = fa - fb   # the pair's front axis: a's front and b's reversed
	if a.in_square():
		axis = -fb
	elif b.in_square():
		axis = fa
	else:
		var lo: float = maxf(a.melee_front_line_min_cos, b.melee_front_line_min_cos)
		opposed = MeleeFrontGeometry.ramp(-fa.dot(fb), lo)
		side = side_gate(-fa.dot(fb), lo,
				minf(a.melee_side_contact_max_cos, b.melee_side_contact_max_cos))
	# (A min_cos below 0 passes parallels, whose axis is degenerate.)
	var frontal: bool = opposed > 0.0 and axis.length_squared() >= 0.000001
	if not frontal and side <= 0.0:
		return Vector3.ZERO
	var shift: Vector2 = MeleeFrontGeometry.men_offset(b, fb) - MeleeFrontGeometry.men_offset(a, fa)
	var to_b: Vector2 = last_gap + shift
	var scale: float = clampf(minf(a.melee_front_line_scale, b.melee_front_line_scale), 0.0, 1.0)
	var w: float = 0.0
	var ra: float = 0.0
	var rb: float = 0.0
	if frontal:
		axis = axis.normalized()
		var ahead: float = clampf(to_b.dot(axis) / Unit.RADIUS, 0.0, 1.0)
		var reach_a: Vector2 = MeleeFrontGeometry.reach(a, pa, fa, axis)
		var reach_b: Vector2 = MeleeFrontGeometry.reach(b, pb, fb, axis)
		var overlap: float = MeleeFrontGeometry.front_overlap(reach_a.y, reach_b.y,
				absf(to_b.dot(axis.orthogonal())))
		w = scale * opposed * ahead * overlap
		ra = reach_a.x
		rb = reach_b.x
	if side > 0.0:
		var s: Vector3 = _side_part(pa, pb, fa, fb, to_b)
		var w_side: float = scale * side * s.x
		if w_side > 0.0:
			var total: float = w + w_side
			ra = (w * ra + w_side * s.y) / total
			rb = (w * rb + w_side * s.z) / total
			w = total
	last_gap += shift * w
	return Vector3(w, ra, rb)


## How much of a pair's weight the side part can carry, from `c`, the cosine between one front
## and the other reversed: 0 at or above `hi` (fronts near enough opposed that the frontal part
## alone weighs them), rising to 1 at `lo` (where the frontal part reaches 0) and below. Beside
## the frontal part's ramp the two never sum past 1. A `hi` of -1 or less turns the side part off.
static func side_gate(c: float, lo: float, hi: float) -> float:
	return clampf((hi - c) / maxf(hi - lo, 0.000001), 0.0, 1.0)


## The side part of a pair (profiles `pa`, `pb`, men facing `fa`, `fb`, b's men `to_b` from
## a's): Vector3(w, reach_a, reach_b), unscaled. Each block whose front faces the other weighs
## how far the other lies ahead of that front (a ramp over one RADIUS) times how much of that
## front faces the other's outline across it (MeleeFrontGeometry.outline, the other met on
## whichever side faces it). A block reaches its front rank along its own front and its outline
## along the other's. The weight is the larger of the two orientations; the reaches are their
## average by weight, so an L-shaped meeting where both fronts bear blends smoothly.
static func _side_part(pa: MeleeFrontProfile, pb: MeleeFrontProfile, fa: Vector2,
		fb: Vector2, to_b: Vector2) -> Vector3:
	var ob: Vector2 = MeleeFrontGeometry.outline(pb, fb, fa)
	var w_ab: float = clampf(to_b.dot(fa) / Unit.RADIUS, 0.0, 1.0) \
			* MeleeFrontGeometry.front_overlap(pa.half, ob.y, absf(to_b.dot(fa.orthogonal())))
	var oa: Vector2 = MeleeFrontGeometry.outline(pa, fa, fb)
	var w_ba: float = clampf(-to_b.dot(fb) / Unit.RADIUS, 0.0, 1.0) \
			* MeleeFrontGeometry.front_overlap(pb.half, oa.y, absf(to_b.dot(fb.orthogonal())))
	var w_sum: float = w_ab + w_ba
	if w_sum <= 0.0:
		return Vector3.ZERO
	return Vector3(maxf(w_ab, w_ba), (w_ab * pa.depth + w_ba * oa.x) / w_sum,
			(w_ab * ob.x + w_ba * pb.depth) / w_sum)


## How squarely `a` and `b` meet front to front, 0 to 1 (see pair()). Symmetric in a and b.
static func weight(a: Unit, b: Unit) -> float:
	return pair(a, b).x


## Added to a close-tier contact range: each block's reach beyond the radius its base range
## counts for it (`ra`, `rb`; 0 for a pursuer's own, which a router's range leaves out).
static func contact_extension(a: Unit, b: Unit, ra: float = Unit.RADIUS,
		rb: float = Unit.RADIUS) -> float:
	var p: Vector3 = pair(a, b)
	return p.x * (maxf(0.0, p.y - ra) + maxf(0.0, p.z - rb)) if p.x > 0.0 else 0.0


## Whether `a` and `b` are in contact: positions within `base` (`dist_sq` their squared distance),
## or within `base` plus contact_extension on the weighted gap (last_gap), after a reject on
## both blocks' own live extension bounds (each covers its anchor shift).
static func within_contact(a: Unit, b: Unit, base: float, dist_sq: float,
		ra: float = Unit.RADIUS, rb: float = Unit.RADIUS) -> bool:
	if dist_sq <= base * base:
		return true
	var pa: MeleeFrontProfile = MeleeFrontProfile.of(a)
	var pb: MeleeFrontProfile = MeleeFrontProfile.of(b)
	var bound: float = base + pa.ext + pb.ext
	if not (pa.eligible and pb.eligible) or dist_sq > bound * bound:
		return false
	var p: Vector3 = _pair(a, b, pa, pb)
	var reach: float = base + p.x * (maxf(0.0, p.y - ra) + maxf(0.0, p.z - rb))
	return p.x > 0.0 and last_gap.length_squared() <= reach * reach


## The floor's extension for pair `p` (pair(a, b)): each reach past its capped _front_depth().
static func floor_from(p: Vector3, a: Unit, b: Unit) -> float:
	return p.x * (maxf(0.0, p.y - a._front_depth()) + maxf(0.0, p.z - b._front_depth()))


## From `a` toward `b` as the extension measures it: the positions' gap plus the weighted shift.
static func toward(a: Unit, b: Unit) -> Vector2:
	if a.frontage_anchor_offset != 0.0 or b.frontage_anchor_offset != 0.0:
		pair(a, b)
	else:
		last_gap = b.position - a.position
	return last_gap
