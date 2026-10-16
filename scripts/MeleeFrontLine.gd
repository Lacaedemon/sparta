class_name MeleeFrontLine
## Two blocks front to front meet at their front ranks, not each grid ordered deep into the
## other as centre-to-centre ranges left them: contact_extension (via within_contact) and
## floor_from add the missing reach back, times weight(): 1 squarely front to front, 0 for a
## flank or rear attack. Cavalry, missile and far blocks keep the old ranges; a square fronts
## every way. MeleeFrontGeometry and MeleeFrontProfile measure the blocks.


## Vector3(w, reach_a, reach_b). w: the smaller melee_front_line_scale (0..1) times the fronts'
## opposition (a ramp from the larger melee_front_line_min_cos to 1; a square opposes any front),
## each block's men lying ahead of the other's along the pair's axis (a ramp over one RADIUS, so
## the weight holds while the press closes), and the share of the narrower front facing the other.
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
	var axis: Vector2 = fa - fb   # the pair's front axis: a's front and b's reversed
	if a.in_square():
		axis = -fb
	elif b.in_square():
		axis = fa
	else:
		var lo: float = maxf(a.melee_front_line_min_cos, b.melee_front_line_min_cos)
		opposed = MeleeFrontGeometry.ramp(-fa.dot(fb), lo)
	if opposed <= 0.0 or axis.length_squared() < 0.000001:  # a min_cos below 0 passes parallels
		return Vector3.ZERO
	axis = axis.normalized()
	var shift: Vector2 = MeleeFrontGeometry.men_offset(b, fb) - MeleeFrontGeometry.men_offset(a, fa)
	var to_b: Vector2 = last_gap + shift
	var ahead: float = clampf(to_b.dot(axis) / Unit.RADIUS, 0.0, 1.0)
	var ra: Vector2 = MeleeFrontGeometry.reach(a, pa, fa, axis)
	var rb: Vector2 = MeleeFrontGeometry.reach(b, pb, fb, axis)
	var overlap: float = MeleeFrontGeometry.front_overlap(ra.y, rb.y,
			absf(to_b.dot(axis.orthogonal())))
	var scale: float = clampf(minf(a.melee_front_line_scale, b.melee_front_line_scale), 0.0, 1.0)
	var w: float = scale * opposed * ahead * overlap
	last_gap += shift * w
	return Vector3(w, ra.x, rb.x)


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
