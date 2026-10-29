class_name MeleeFrontGeometry
## The block geometry MeleeFrontLine weighs and extends a pair by: where a block's men face,
## how far its men reach from its centre toward the other block, how wide its front runs, and
## how far a neighbourhood query has to reach to find every pair an extension can join.
## Reads where the men stand, not the heading: a heading turn the grid absorbs (folded into
## Unit.grid_fold) or one still in progress in place (the men stand fast until it settles)
## leaves the front where the men are. The size measurements come from MeleeFrontProfile.


## The direction `u`'s slot grid fronts: the heading an in-place turn started from while one is
## in progress (an engage turn, or an order's about-face or quarter-turn: the men hold their
## ground and the fold is only written when the turn settles), else the heading, turned by
## grid_fold() either way. The same rotation soldier_world_slots() lays a settled grid out at,
## so it is the frame the grid's own offsets are read in (men_offset). Where the men face is
## facing_front: the same axis, reversed while the grid's turn off the heading (grid_fold) is
## past a quarter-turn.
static func grid_front(u: Unit) -> Vector2:
	var heading: Vector2 = u.facing
	if u._engage_turn_target != Vector2.ZERO:
		heading = u._engage_turn_start_facing
	elif u.is_order_turning():
		heading = u.active_leaf().turn_start_facing
	return heading.rotated(u.grid_fold())


## The direction `u`'s men face, along the grid's depth axis: grid_front, reversed while the grid's
## turn off the heading (grid_fold) is past a quarter-turn (Unit.near_front_reversed). Every man
## faces the heading, so a block that turned in place more than a quarter of the way round (an
## engage re-face, an about-face) has the grid's rear rank in front of it, and its men face away
## from the grid's own front.
static func facing_front(u: Unit) -> Vector2:
	var front: Vector2 = grid_front(u)
	return -front if u.near_front_reversed() else front


## The distance from `u`'s centre to its grid's front rank, in wu: half its live rank count
## less one, times its rank pitch (a square's file pitch, as its grid lays it). The live rank
## count is a file-major block's deepest surviving file (Unit.live_rank_count), since its grid
## centres on that file. Unit._front_depth() without its cap.
static func front_rank_depth(u: Unit) -> float:
	return MeleeFrontProfile.of(u).depth


## Half the width of `u`'s front rank, centre file to end file, in wu: its file count (or its
## headcount, when that is fewer) less one, times half its file pitch.
static func front_half_width(u: Unit) -> float:
	return MeleeFrontProfile.of(u).half


## How far `u`'s men (profile `p`, men facing `front`) reach from their centre along `axis` (a
## unit vector), and how far across it, in wu: a line's front-rank depth and front half-width,
## read along its own grid. A square fronts every way, so it reaches its slot rectangle's
## extent along the axis whichever side faces the other block. Returns Vector2(along, across).
static func reach(u: Unit, p: MeleeFrontProfile, front: Vector2, axis: Vector2) -> Vector2:
	if not u.in_square():
		return Vector2(p.depth, p.half)
	return outline(p, front, axis)


## How far a block's men (profile `p`, men facing `front`) reach from their centre along `axis`
## (a unit vector) whichever of its sides faces that way, and how far across it, in wu: its
## slot rectangle's extent, front-rank depth by front half-width, read along the axis. Along its
## own front or back that is its front-rank depth; along a flank, its front half-width. Returns
## Vector2(along, across).
static func outline(p: MeleeFrontProfile, front: Vector2, axis: Vector2) -> Vector2:
	var c: float = absf(axis.dot(front))
	var s: float = absf(axis.dot(front.orthogonal()))
	return Vector2(p.depth * c + p.half * s, p.half * c + p.depth * s)


## The offset of `u`'s men's centre from its position (a flank-anchored frontage shifts them),
## laid out at the angle the men face (`front`, usually grid_front(u)), not the heading's.
static func men_offset(u: Unit, front: Vector2) -> Vector2:
	if u.frontage_anchor_offset == 0.0:
		return Vector2.ZERO
	var local: Vector2 = u._slot_anchor_centre()
	if u._formation_mirror_x:
		local.x = -local.x
	return local.rotated(front.angle() + PI * 0.5)


## The most `u` can add to any pair's range, measured from its position: its reach along any
## axis plus how far its men's centre stands off its position (an anchored frontage), or 0
## when it takes part in no extension.
static func extension_depth(u: Unit) -> float:
	return MeleeFrontProfile.of(u).ext


## How far `u` can carry a pair past a centre-based contact range: its reach beyond the
## Unit.RADIUS that range counts for it (a router's range leaves the radius out and adds the
## whole reach: the same total), plus its whole anchor shift, which no range counts.
static func query_extension(u: Unit) -> float:
	return MeleeFrontProfile.of(u).beyond


## The radius a neighbourhood query around `u` must cover to find every unit `u` can pair
## with at an extended range, given `deepest`, the largest query_extension of any partner.
## SpatialHash.CELL_SIZE bounds every centre-based range; an extended pair reaches at most the
## two blocks' query_extension past it. A deep partner alone can carry the range.
static func query_radius(u: Unit, deepest: float) -> float:
	var p: MeleeFrontProfile = MeleeFrontProfile.of(u)
	if not p.eligible:
		return SpatialHash.CELL_SIZE
	return SpatialHash.CELL_SIZE + p.beyond + deepest


## The share of the narrower of two fronts, of half-widths `ha` and `hb`, that faces the other
## when their centres stand `lateral` apart across the front axis: 1 when it lies wholly
## within the wider front, 0 once the two no longer overlap.
static func front_overlap(ha: float, hb: float, lateral: float) -> float:
	var narrow: float = minf(ha, hb)
	if narrow <= 0.0:
		return 1.0 if lateral <= maxf(ha, hb) else 0.0
	var overlap: float = minf(ha, lateral + hb) - maxf(-ha, lateral - hb)
	return clampf(overlap / (2.0 * narrow), 0.0, 1.0)


## 0 at or below `lo`, 1 at 1, linear between. A `lo` of 1 or more reads 1 only at 1.
static func ramp(c: float, lo: float) -> float:
	if lo >= 1.0:
		return 1.0 if c >= 1.0 else 0.0
	return clampf((c - lo) / (1.0 - lo), 0.0, 1.0)
