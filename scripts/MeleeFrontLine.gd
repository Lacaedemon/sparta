class_name MeleeFrontLine
## Where two blocks fighting front to front meet: at their front ranks, not with each grid
## ordered most of its depth into the other.
##
## The regiment layer measures melee contact and the engaged separation floor between block
## CENTRES. Contact range is weapon reach plus Unit.RADIUS (0.9 m) a side, and the floor is
## each block's _front_depth(), capped at half its reach. Both stand in for the distance from
## a block's centre to its front rank, which grows by half a rank pitch for every rank, so an
## 8-rank block's front rank stands about 2.5 ranks beyond RADIUS. Two deep blocks closing
## front to front therefore register contact only after their front ranks have walked into
## each other (no body contact resists them before the flag), and the press then closes their
## centres to the capped floor, with each grid's slots ordered most of a block deep inside the
## other.
##
## For a frontal pair this adds the missing front depth back: contact_extension to every
## close-tier contact range, so contact starts as the front ranks come within reach, and
## floor_extension to the engaged floor, so the press stops with the two front ranks on one
## line. Both scale with weight(), 1 for blocks squarely front to front and 0 once either
## turns a flank or its rear to the other, so flank and rear attacks keep the old ranges.
## Pairs involving cavalry, a missile unit, a square or a far-tier block keep them too. A
## cavalry block's ranks sit 6 m apart, so moving where its contact begins would move where
## every charge lands. A missile unit shoots until an enemy is in contact, so moving its
## contact out to its loose front rank would end its shooting earlier. A square has no front.


## Whether `u` can take part in a frontal extension at all.
static func eligible(u: Unit) -> bool:
	return u.melee_front_line_scale > 0.0 and not u.is_cavalry and not u.is_ranged \
			and u.tier != FormationTier.FAR and not u.in_square()


## How squarely `a` and `b` meet front to front, from 0 to 1, times the pair's
## melee_front_line_scale (the smaller of the two units' values, clamped to 0..1). The product
## of three ramps, each 0 at or below melee_front_line_min_cos (the larger of the two) and 1 at
## a cosine of 1: the two headings point against each other, `b` lies ahead of `a`, and `a`
## lies ahead of `b`. Symmetric in a and b, so both units measure the same range.
static func weight(a: Unit, b: Unit) -> float:
	if not (eligible(a) and eligible(b)):
		return 0.0
	var scale: float = clampf(minf(a.melee_front_line_scale, b.melee_front_line_scale), 0.0, 1.0)
	var to_b: Vector2 = b.position - a.position
	if to_b.length_squared() < 0.0001:  # tuned in wu
		return 0.0
	var dir: Vector2 = to_b.normalized()
	var lo: float = maxf(a.melee_front_line_min_cos, b.melee_front_line_min_cos)
	return scale * _ramp(-a.facing.dot(b.facing), lo) * _ramp(dir.dot(a.facing), lo) \
			* _ramp(-dir.dot(b.facing), lo)


## 0 at or below `lo`, 1 at 1, linear between. A `lo` of 1 or more reads 1 only at 1.
static func _ramp(c: float, lo: float) -> float:
	if lo >= 1.0:
		return 1.0 if c >= 1.0 else 0.0
	return clampf((c - lo) / (1.0 - lo), 0.0, 1.0)


## The distance from `u`'s centre to its front rank, in wu: half its rank count less one,
## times its rank pitch, on its current grid. _front_depth() without its cap.
static func front_rank_depth(u: Unit) -> float:
	var files: int = maxi(1, u.formation_files(u.soldiers))
	var ranks: int = UnitFormation.ranks_for(u.soldiers, files)
	return float(maxi(0, ranks - 1)) * 0.5 * u.rank_pitch_wu()


## front_rank_depth for a unit that can take part in an extension, else 0: the most `u` can
## add to any pair's range, which SpatialHash's neighbourhood query has to cover.
static func extension_depth(u: Unit) -> float:
	return front_rank_depth(u) if eligible(u) else 0.0


## Added to a close-tier melee contact range (reach plus Unit.RADIUS a side): each block's
## front-rank depth beyond RADIUS, times weight(). Two blocks squarely front to front are then
## in contact once their front ranks are within reach of each other.
static func contact_extension(a: Unit, b: Unit) -> float:
	var w: float = weight(a, b)
	if w <= 0.0:
		return 0.0
	return w * (maxf(0.0, front_rank_depth(a) - Unit.RADIUS)
			+ maxf(0.0, front_rank_depth(b) - Unit.RADIUS))


## Added to the engaged separation floor (the two _front_depth() values): each block's
## front-rank depth beyond its capped _front_depth(), times weight(). Two blocks squarely
## front to front then stop pressing with their front ranks on one line. At any one weight the
## floor stays inside the contact range above; a weight that falls while a pair is pressed
## (one block turning away) can still take it out of contact.
static func floor_extension(a: Unit, b: Unit) -> float:
	var w: float = weight(a, b)
	if w <= 0.0:
		return 0.0
	return w * (maxf(0.0, front_rank_depth(a) - a._front_depth())
			+ maxf(0.0, front_rank_depth(b) - b._front_depth()))
