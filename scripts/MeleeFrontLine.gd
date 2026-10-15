class_name MeleeFrontLine
## Where two blocks fighting front to front meet: at their front ranks, not with each grid
## ordered deep into the other, as centre-to-centre contact and floor ranges left them.
## For a frontal pair this adds the missing reach back (MeleeFrontGeometry measures it):
## contact_extension to the close-tier contact ranges, tested through within_contact, and
## floor_extension to the engaged floor, both times weight(): 1 for men squarely front to
## front, 0 for a flank or rear attack, which keeps the old ranges. So do pairs with cavalry
## (6 m between ranks: where every charge lands would move), a missile unit (it shoots until
## an enemy is in contact) or a far block. A square fronts every way.


## Whether `u` can take part in a frontal extension at all (see MeleeFrontProfile).
static func eligible(u: Unit) -> bool:
	return MeleeFrontProfile.of(u).eligible


## Vector3(w, reach_a, reach_b). w: the smaller melee_front_line_scale (0..1) times the fronts'
## opposition (a ramp from the larger melee_front_line_min_cos to 1; a square opposes any
## front), each block's men lying ahead of the other's along the pair's axis (a ramp over one
## Unit.RADIUS), and the share of the narrower front facing the other. Past one RADIUS no term
## reads the axial distance, so the weight holds while the press closes a pair.
static func pair(a: Unit, b: Unit) -> Vector3:
	return _pair(a, b, MeleeFrontProfile.of(a), MeleeFrontProfile.of(b))


# The gap between the men's centres _pair last measured (b's minus a's).
static var _gap := Vector2.ZERO


static func _pair(a: Unit, b: Unit, pa: MeleeFrontProfile, pb: MeleeFrontProfile) -> Vector3:
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
	var to_b: Vector2 = b.position + MeleeFrontGeometry.men_offset(b, fb) \
			- (a.position + MeleeFrontGeometry.men_offset(a, fa))
	_gap = to_b
	var ahead: float = clampf(to_b.dot(axis) / Unit.RADIUS, 0.0, 1.0)
	var ra: Vector2 = MeleeFrontGeometry.reach(a, pa, fa, axis)
	var rb: Vector2 = MeleeFrontGeometry.reach(b, pb, fb, axis)
	var overlap: float = MeleeFrontGeometry.front_overlap(ra.y, rb.y,
			absf(to_b.dot(axis.orthogonal())))
	var scale: float = clampf(minf(a.melee_front_line_scale, b.melee_front_line_scale), 0.0, 1.0)
	return Vector3(scale * opposed * ahead * overlap, ra.x, rb.x)


## How squarely `a` and `b` meet front to front, 0 to 1 (see pair()). Symmetric in a and b.
static func weight(a: Unit, b: Unit) -> float:
	return pair(a, b).x


## Added to a close-tier contact range: each block's reach beyond the radius the base range
## already counts for it (`ra`, `rb`: Unit.RADIUS, or 0 for a side the base leaves out, as
## melee_contact_distance does for a pursuer against a router), times weight().
static func contact_extension(a: Unit, b: Unit, ra: float = Unit.RADIUS,
		rb: float = Unit.RADIUS) -> float:
	var p: Vector3 = pair(a, b)
	if p.x <= 0.0:
		return 0.0
	return p.x * (maxf(0.0, p.y - ra) + maxf(0.0, p.z - rb))


## Whether `a` and `b` are in contact: their positions within `base` (`dist_sq` is their squared
## distance), or, for a frontal pair, their men's centres within `base` plus
## contact_extension(a, b, ra, rb) (the men's centres: an anchored frontage stands its men off
## its position). It rejects on both cached extension bounds before it pays for _pair().
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
	if p.x <= 0.0:
		return false
	var reach: float = base + p.x * (maxf(0.0, p.y - ra) + maxf(0.0, p.z - rb))
	return _gap.length_squared() <= reach * reach


## Added to the engaged floor: each block's reach past its capped _front_depth(), times weight().
static func floor_extension(a: Unit, b: Unit) -> float:
	var p: Vector3 = pair(a, b)
	if p.x <= 0.0:
		return 0.0
	return p.x * (maxf(0.0, p.y - a._front_depth()) + maxf(0.0, p.z - b._front_depth()))
