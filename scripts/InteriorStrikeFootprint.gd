class_name InteriorStrikeFootprint
## The region SoldierInteriorStrike calls inside a block: behind its striking set's rearmost
## man along Unit.near_front_forward (depths measured from `origin`, the block's position),
## and within the grid's rectangle about `centre`, the live men's mean, from `rear` to
## `depth` along `grid` and `half_width` across it. `grid` is the way the men face along the
## grid's depth axis (MeleeFrontGeometry.facing_front), the grid's rear rank while the grid's
## turn off the heading (Unit.grid_fold) is past a quarter-turn, as the striking set is ranked
## (Unit.near_front_reversed), so `rear` is always
## behind the strikers. Pure geometry, no RNG.

var origin := Vector2.ZERO
var fwd := Vector2.ZERO
var front_depth: float = 0.0
var centre := Vector2.ZERO
var grid := Vector2.ZERO
var across := Vector2.ZERO
var rear: float = 0.0
var depth: float = 0.0
var half_width: float = 0.0


## `block`'s footprint behind the striking set `front` (non-empty): the grid's front-rank
## depth and front half-width (MeleeFrontProfile) about its live men's mean, padded on the
## flanks and rear by Unit.interior_strike_margin. Null when no man of the block is alive.
static func of(block: Unit, front: PackedInt32Array) -> InteriorStrikeFootprint:
	var mean: Variant = live_centre(block)
	if mean == null:
		return null
	var box := InteriorStrikeFootprint.new()
	box.origin = block.position
	box.fwd = block.near_front_forward()
	box.front_depth = INF
	for i in front:
		box.front_depth = minf(box.front_depth, (block._sim_soldier_pos[i] - box.origin).dot(box.fwd))
	box.centre = mean
	# The rear padding goes behind the striking set, so a set ranked toward the grid's rear rank
	# (Unit.near_front_reversed) reads the box from that end.
	box.grid = MeleeFrontGeometry.facing_front(block)
	box.across = box.grid.orthogonal()
	var prof: MeleeFrontProfile = MeleeFrontProfile.of(block)
	var margin: float = block.interior_strike_margin
	box.rear = -prof.depth - margin
	box.depth = prof.depth
	box.half_width = prof.half + margin
	return box


## The mean of `u`'s living men's positions, or null when none is alive. A unit's centre in
## this sense, not its `position`, which a standing frontage_anchor_offset shifts off its men.
static func live_centre(u: Unit) -> Variant:
	var n: int = mini(u._sim_soldier_pos.size(), u._sim_soldier_hp.size())
	var sum := Vector2.ZERO
	var live: int = 0
	for i in range(n):
		if u._sim_soldier_hp[i] > 0.0:
			sum += u._sim_soldier_pos[i]
			live += 1
	if live == 0:
		return null
	return sum / float(live)


func has(p: Vector2) -> bool:
	if (p - origin).dot(fwd) >= front_depth:
		return false
	var rel: Vector2 = p - centre
	var along: float = rel.dot(grid)
	return along >= rear and along <= depth and absf(rel.dot(across)) <= half_width
