class_name MeleeFrontLine
## Where two blocks fighting front to front meet: at their front ranks, not with each grid
## ordered most of its depth into the other.
##
## The regiment layer measures melee contact and the engaged separation floor between block
## CENTRES: reach plus Unit.RADIUS (0.9 m) a side, and the two _front_depth() values, each
## capped at half the reach. A block's real centre-to-front-rank distance grows by half a rank
## pitch per rank, so two deep blocks closing front to front came into contact only after their
## front ranks had walked into each other, and the press then ordered each grid most of a block
## deep inside the other.
##
## For a frontal pair this adds the missing depth back (MeleeFrontGeometry measures it):
## contact_extension to the close-tier melee contact ranges (each site that reads it names it),
## so contact starts as the front ranks come within reach, and floor_extension to the engaged
## floor, so the press stops with the two front ranks on one line. Both scale with weight(),
## 1 for grids squarely front to front and 0 for a flank or rear attack, which keeps the old
## ranges. So do pairs with cavalry (6 m between ranks: where every charge lands would move), a
## missile unit (it shoots until an enemy is in contact), a square (no front) or a far block.


## Whether `u` can take part in a frontal extension at all.
static func eligible(u: Unit) -> bool:
	return u.melee_front_line_scale > 0.0 and not u.is_cavalry and not u.is_ranged \
			and u.tier != FormationTier.FAR and not u.in_square()


## How squarely `a` and `b` meet front to front, 0 to 1, times the smaller of their
## melee_front_line_scale values (clamped to 0..1). The product of three terms. The two grid
## fronts point against each other: a ramp, 0 at or below the larger melee_front_line_min_cos
## and 1 at a cosine of 1. Their fronts overlap across the pair's front axis: the share of the
## narrower front facing the other's. And each lies ahead of the other along that axis,
## ramping to 1 within one Unit.RADIUS, so a pair that has passed each other weighs nothing.
## None reads how far apart the centres are along the axis, so the weight holds while the
## press closes the pair: a bearing term falls as an offset pair closes, lowering the floor
## and closing them further. Symmetric in a and b.
static func weight(a: Unit, b: Unit) -> float:
	if not (eligible(a) and eligible(b)):
		return 0.0
	var fa: Vector2 = MeleeFrontGeometry.grid_front(a)
	var fb: Vector2 = MeleeFrontGeometry.grid_front(b)
	var lo: float = maxf(a.melee_front_line_min_cos, b.melee_front_line_min_cos)
	var opposed: float = MeleeFrontGeometry.ramp(-fa.dot(fb), lo)
	var axis: Vector2 = fa - fb   # the pair's front axis: a's front and b's reversed
	if opposed <= 0.0 or axis.length_squared() < 0.000001:  # a min_cos below 0 passes parallels
		return 0.0
	axis = axis.normalized()
	var to_b: Vector2 = b.position - a.position
	var ahead: float = clampf(to_b.dot(axis) / Unit.RADIUS, 0.0, 1.0)
	var overlap: float = MeleeFrontGeometry.front_overlap(MeleeFrontGeometry.front_half_width(a),
			MeleeFrontGeometry.front_half_width(b), absf(to_b.dot(axis.orthogonal())))
	var scale: float = clampf(minf(a.melee_front_line_scale, b.melee_front_line_scale), 0.0, 1.0)
	return scale * opposed * ahead * overlap


## Added to a close-tier melee contact range (reach plus Unit.RADIUS a side): each block's
## front-rank depth beyond RADIUS, times weight(). Two blocks squarely front to front are then
## in contact once their front ranks are within reach of each other.
static func contact_extension(a: Unit, b: Unit) -> float:
	var w: float = weight(a, b)
	if w <= 0.0:
		return 0.0
	return w * (maxf(0.0, MeleeFrontGeometry.front_rank_depth(a) - Unit.RADIUS)
			+ maxf(0.0, MeleeFrontGeometry.front_rank_depth(b) - Unit.RADIUS))


## Whether `a` and `b`, centres sqrt(`dist_sq`) apart, are within `base` (a centre-based
## contact range) plus contact_extension(a, b): the same answer as comparing against the full
## range, but it answers from `base` alone, or rejects on the extension's upper bound (both
## depths beyond Unit.RADIUS), before it pays for weight(). The contact sites that scan every
## unit call this.
static func within_contact(a: Unit, b: Unit, base: float, dist_sq: float) -> bool:
	if dist_sq <= base * base:
		return true
	if not (eligible(a) and eligible(b)):
		return false
	var bound: float = base + maxf(0.0, MeleeFrontGeometry.front_rank_depth(a) - Unit.RADIUS) \
			+ maxf(0.0, MeleeFrontGeometry.front_rank_depth(b) - Unit.RADIUS)
	if dist_sq > bound * bound:
		return false
	var reach: float = base + contact_extension(a, b)
	return dist_sq <= reach * reach


## Added to the engaged separation floor (the two _front_depth() values): each block's
## front-rank depth beyond its capped _front_depth(), times weight(), so two blocks squarely
## front to front stop pressing with their front ranks on one line. At any one weight the floor
## stays inside the contact range above.
static func floor_extension(a: Unit, b: Unit) -> float:
	var w: float = weight(a, b)
	if w <= 0.0:
		return 0.0
	return w * (maxf(0.0, MeleeFrontGeometry.front_rank_depth(a) - a._front_depth())
			+ maxf(0.0, MeleeFrontGeometry.front_rank_depth(b) - b._front_depth()))
