class_name MeleeFrontLine
## Where two blocks fighting front to front meet: at their front ranks. The regiment layer
## measures contact and the engaged floor between CENTRES (reach plus Unit.RADIUS a side; the
## _front_depth() pair, capped at half the reach), so deep blocks met only after their front
## ranks had walked into each other, and the press ordered each grid deep into the other.
##
## For a frontal pair this adds the missing reach back (MeleeFrontGeometry measures it):
## contact_extension to the close-tier contact ranges, tested through within_contact, and
## floor_extension to the engaged floor, both times weight(): 1 for men squarely front to
## front, 0 for a flank or rear attack, which keeps the old ranges. So do pairs with cavalry
## (6 m between ranks: where every charge lands would move), a missile unit (it shoots until
## an enemy is in contact) or a far block. A square fronts every way.


## Whether `u` can take part in a frontal extension at all.
static func eligible(u: Unit) -> bool:
	return u.melee_front_line_scale > 0.0 and not u.is_cavalry and not u.is_ranged \
			and u.tier != FormationTier.FAR


## Vector3(w, reach_a, reach_b): the pair's weight and each block's reach toward the other.
## w is the smaller melee_front_line_scale (clamped to 0..1) times three terms: the fronts
## oppose (a ramp, 0 at or below the larger melee_front_line_min_cos, 1 at a cosine of 1; a
## square opposes any front), each block's men lie ahead of the other's along the pair's front
## axis (ramping to 1 within one Unit.RADIUS, so a pair that has passed each other weighs
## nothing), and the share of the narrower front facing the other across that axis. Past one
## RADIUS no term reads the axial distance, so the weight holds while the press closes a pair.
static func pair(a: Unit, b: Unit) -> Vector3:
	if not (eligible(a) and eligible(b)) or (a.in_square() and b.in_square()):
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
	# The men's centres: an anchored frontage shifts a block's men off its position.
	var to_b: Vector2 = (b.position + b.block_centre_offset()) \
			- (a.position + a.block_centre_offset())
	var ahead: float = clampf(to_b.dot(axis) / Unit.RADIUS, 0.0, 1.0)
	var ra: Vector2 = MeleeFrontGeometry.reach(a, axis)
	var rb: Vector2 = MeleeFrontGeometry.reach(b, axis)
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


## Whether `a` and `b`, centres sqrt(`dist_sq`) apart, are within `base` plus
## contact_extension(a, b, ra, rb): the same answer as the full range. It answers from `base`,
## rejects against the deepest block on the field (SpatialHash.max_extension_depth, when a
## grid is current) and then both blocks' own depths before it pays for pair().
static func within_contact(a: Unit, b: Unit, base: float, dist_sq: float,
		ra: float = Unit.RADIUS, rb: float = Unit.RADIUS) -> bool:
	if dist_sq <= base * base:
		return true
	if SpatialHash.is_current(Engine.get_physics_frames()):
		var field: float = base + 2.0 * SpatialHash.max_extension_depth()
		if dist_sq > field * field:
			return false
	if not (eligible(a) and eligible(b)):
		return false
	var bound: float = base + MeleeFrontGeometry.extension_depth(a) \
			+ MeleeFrontGeometry.extension_depth(b)
	if dist_sq > bound * bound:
		return false
	var reach: float = base + contact_extension(a, b, ra, rb)
	return dist_sq <= reach * reach


## Added to the engaged floor: each block's reach past its capped _front_depth(), times weight().
static func floor_extension(a: Unit, b: Unit) -> float:
	var p: Vector3 = pair(a, b)
	if p.x <= 0.0:
		return 0.0
	return p.x * (maxf(0.0, p.y - a._front_depth()) + maxf(0.0, p.z - b._front_depth()))
