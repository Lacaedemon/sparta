class_name MenExtent
extends RefCounted
## What a block measures about itself from where its men stand: the farthest a man is from the
## block's position, how far the men reach along the block's own file and rank axes, and where
## the men stand on average. None of it reads the slot grid, which is only each man's place
## in the block (his file, his rank, his neighbours), never a point he is measured against.
## A block with no men yet (before the first physics tick seeds them, or a far-tier block, which
## has none) has nothing to measure; callers then read the block's layout parameters, which are
## spawn data: the headcount, frontage and pitches the men will be seeded from.


## Whether `u` has men to measure.
static func has_men(u: Unit) -> bool:
	return not u._sim_soldier_pos.is_empty()


## The distance from `centre` (an offset from `u.position`, parent-local) to the farthest man.
static func reach(u: Unit, centre: Vector2 = Vector2.ZERO) -> float:
	var far_sq: float = 0.0
	var origin: Vector2 = u.position + centre
	for p in u._sim_soldier_pos:
		far_sq = maxf(far_sq, p.distance_squared_to(origin))
	return sqrt(far_sq)


## How far the men reach from `u.position` along each axis of the frame turned by `angle`
## (the block's own frame is Unit.soldier_block_world_angle()): Vector2(along the file axis,
## along the rank axis), both unsigned. The same rectangle bound the slot grid's half extents
## gave, read off the men.
static func half_extents(u: Unit, angle: float) -> Vector2:
	var file_axis: Vector2 = Vector2.RIGHT.rotated(angle)
	var rank_axis: Vector2 = file_axis.orthogonal()
	var hw: float = 0.0
	var hd: float = 0.0
	for p in u._sim_soldier_pos:
		var d: Vector2 = p - u.position
		hw = maxf(hw, absf(d.dot(file_axis)))
		hd = maxf(hd, absf(d.dot(rank_axis)))
	return Vector2(hw, hd)


## Where the men stand on average across the front (a unit vector `front`: the direction the
## block's front rank faces), as a world-aligned offset from `u.position`: the middle of the line
## the block presents, which a flank-anchored frontage moves off the position. Only the part
## across the front: along it the position already stands where the front men do, since the
## regiment point is coupled to them (SoldierBodies.couple), and a mean over every man there
## would put the front behind that by however far the rear ranks have lagged.
static func lateral_centre(u: Unit, front: Vector2) -> Vector2:
	var side: Vector2 = front.orthogonal()
	var sum: float = 0.0
	for p in u._sim_soldier_pos:
		sum += (p - u.position).dot(side)
	return side * (sum / float(u._sim_soldier_pos.size()))


## The middle of the men's bounding rectangle in the frame turned by `angle`, as a world-aligned
## offset from `u.position`: where the block's footprint stands, which a flank-anchored frontage
## or a block whose men have spread off its position moves off the position. The rectangle's
## middle, not the men's mean, so a partial rear rank does not pull it toward the front.
static func centre_offset(u: Unit, angle: float) -> Vector2:
	var file_axis: Vector2 = Vector2.RIGHT.rotated(angle)
	var rank_axis: Vector2 = file_axis.orthogonal()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in u._sim_soldier_pos:
		var d: Vector2 = p - u.position
		var local := Vector2(d.dot(file_axis), d.dot(rank_axis))
		lo = lo.min(local)
		hi = hi.max(local)
	var mid: Vector2 = (lo + hi) * 0.5
	return file_axis * mid.x + rank_axis * mid.y
