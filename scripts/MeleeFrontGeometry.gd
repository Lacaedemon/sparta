class_name MeleeFrontGeometry
## The block geometry MeleeFrontLine weighs and extends a pair by: where a block's men face,
## how far its men reach from its centre toward the other block, how wide its front runs, and
## how far a neighbourhood query has to reach to find every pair an extension can join.
## Reads where the men stand, not the heading: a heading turn the grid absorbs (folded into
## Unit.grid_fold) or one still in progress in place (the men stand fast until it settles)
## leaves the front where the men are.


## The direction `u`'s men face: the heading an in-place turn started from while one is in
## progress (an engage turn, or an order's about-face or quarter-turn: the men hold their
## ground and the fold is only written when the turn settles), else the heading, turned by
## grid_fold() either way. The same rotation soldier_world_slots() lays a settled grid out at.
static func grid_front(u: Unit) -> Vector2:
	var heading: Vector2 = u.facing
	if u._engage_turn_target != Vector2.ZERO:
		heading = u._engage_turn_start_facing
	elif u.is_order_turning():
		heading = u.active_leaf().turn_start_facing
	return heading.rotated(u.grid_fold())


## The distance from `u`'s centre to its grid's front rank, in wu: half its live rank count
## less one, times its rank pitch, along the grid's own rank axis. The live rank count is a
## file-major block's deepest surviving file (Unit.live_rank_count), since its grid centres on
## that file. A square lays both axes at its file pitch. Unit._front_depth() without its cap.
static func front_rank_depth(u: Unit) -> float:
	var files: int = maxi(1, u.formation_files(u.soldiers))
	var ranks: int = u.live_rank_count(files)
	var pitch: float = u.file_pitch_wu() if u.in_square() else u.rank_pitch_wu()
	return float(maxi(0, ranks - 1)) * 0.5 * pitch


## Half the width of `u`'s front rank, centre file to end file, in wu: its file count (or its
## headcount, when that is fewer) less one, times half its file pitch.
static func front_half_width(u: Unit) -> float:
	var files: int = mini(maxi(1, u.formation_files(u.soldiers)), maxi(1, u.soldiers))
	return float(files - 1) * 0.5 * u.file_pitch_wu()


## How far `u`'s men reach from its centre along `axis` (a unit vector), and how far across
## it, in wu: a line's front-rank depth and front half-width, read along its own grid. A square
## fronts every way, so it reaches its slot rectangle's extent along the axis whichever side
## faces the other block. Returns Vector2(along, across).
static func reach(u: Unit, axis: Vector2) -> Vector2:
	var depth: float = front_rank_depth(u)
	var half: float = front_half_width(u)
	if not u.in_square():
		return Vector2(depth, half)
	var f: Vector2 = grid_front(u)
	var along: float = depth * absf(axis.dot(f)) + half * absf(axis.dot(f.orthogonal()))
	var across: float = half * absf(axis.dot(f)) + depth * absf(axis.dot(f.orthogonal()))
	return Vector2(along, across)


## The most `u` can add to any pair's range, measured from its position: its reach along any
## axis plus how far its men's centre stands off its position (an anchored frontage), or 0
## when it takes part in no extension. SpatialHash's neighbourhood query has to cover it.
static func extension_depth(u: Unit) -> float:
	if not MeleeFrontLine.eligible(u):
		return 0.0
	var reach_max: float = front_rank_depth(u)
	if u.in_square():
		reach_max += front_half_width(u)
	return reach_max + absf(u.frontage_anchor_offset)


## The radius a neighbourhood query around `u` must cover so it finds every unit `u` can
## pair with at an extended range, given `deepest`, the largest extension_depth of any unit
## it might pair with. SpatialHash.CELL_SIZE bounds every centre-based range (reach plus
## Unit.RADIUS a side, or the capped engaged floor); an extended range adds at most each
## block's depth beyond RADIUS. It widens for an eligible unit even when it is one rank deep:
## a deep partner alone can carry the pair's range past one cell.
static func query_radius(u: Unit, deepest: float) -> float:
	if not MeleeFrontLine.eligible(u):
		return SpatialHash.CELL_SIZE
	return SpatialHash.CELL_SIZE + maxf(0.0, extension_depth(u) - Unit.RADIUS) \
			+ maxf(0.0, deepest - Unit.RADIUS)


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
