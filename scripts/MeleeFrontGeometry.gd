class_name MeleeFrontGeometry
## The block geometry MeleeFrontLine weighs and extends a frontal pair by: where a block's slot
## grid faces, how deep its front rank stands and how wide it runs, and how far a neighbourhood
## query has to reach to find every pair an extension can join. Reads each block's slot grid,
## not its heading: a heading turn the grid absorbs (folded into Unit.grid_fold, so the slots
## stay where the men stand) leaves the men's front rank where it was.


## The direction `u`'s slot grid's front rank faces: its heading turned by grid_fold(), the
## fold its men turned in place plus the lag the grid trails a small heading correction by.
## The same rotation soldier_world_slots() lays the grid out at.
static func grid_front(u: Unit) -> Vector2:
	return u.facing.rotated(u.grid_fold())


## The distance from `u`'s centre to its grid's front rank, in wu: half its live rank count
## less one, times its rank pitch, along the grid's own rank axis. The live rank count is a
## file-major block's deepest surviving file (Unit.live_rank_count), since its grid centres on
## that file. Unit._front_depth() without its cap.
static func front_rank_depth(u: Unit) -> float:
	var files: int = maxi(1, u.formation_files(u.soldiers))
	var ranks: int = u.live_rank_count(files)
	return float(maxi(0, ranks - 1)) * 0.5 * u.rank_pitch_wu()


## Half the width of `u`'s front rank, centre file to end file, in wu: its file count (or its
## headcount, when that is fewer) less one, times half its file pitch.
static func front_half_width(u: Unit) -> float:
	var files: int = mini(maxi(1, u.formation_files(u.soldiers)), maxi(1, u.soldiers))
	return float(files - 1) * 0.5 * u.file_pitch_wu()


## front_rank_depth for a unit that can take part in an extension, else 0: the most `u` can
## add to any pair's range, which SpatialHash's neighbourhood query has to cover.
static func extension_depth(u: Unit) -> float:
	return front_rank_depth(u) if MeleeFrontLine.eligible(u) else 0.0


## The radius a neighbourhood query around `u` must cover so it finds every unit `u` can
## pair with at an extended range, given `deepest`, the largest extension_depth of any unit
## it might pair with. SpatialHash.CELL_SIZE bounds every centre-based range (reach plus
## Unit.RADIUS a side, or the capped engaged floor). An extended contact range adds each
## block's depth beyond RADIUS, and an extended floor reaches the two front-rank depths, which
## is never more, so the query widens by those two terms. It widens for an eligible unit even
## when it is one rank deep: a deep partner's depth alone can carry the pair's range past one
## cell, and the pair must find each other from both sides.
static func query_radius(u: Unit, deepest: float) -> float:
	if not MeleeFrontLine.eligible(u):
		return SpatialHash.CELL_SIZE
	return SpatialHash.CELL_SIZE + maxf(0.0, front_rank_depth(u) - Unit.RADIUS) \
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
