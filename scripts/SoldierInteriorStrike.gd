class_name SoldierInteriorStrike
## Which enemy soldiers have got inside a block behind its striking ranks, for
## SoldierMelee.resolve. Only a block's near-front ranks strike (Unit.engaged_soldier_indices),
## and "front" follows the slot grid, so an enemy that has worked in past those ranks stands
## where no striker can reach him and is never struck. Every other man of the block within
## reach of such an enemy strikes him instead (SoldierMelee's interior pass).
##
## Inside means: behind the rearmost man of the striking set, along the axis that set is
## ranked on (Unit.near_front_forward), and within the block's footprint. The footprint is the
## grid's own rectangle in the frame its men stand in (MeleeFrontGeometry.grid_front, which
## holds through a turn still in progress): its front-rank depth and front half-width
## (MeleeFrontProfile) about the live men's mean, padded on the flanks and rear by
## Unit.interior_strike_margin. Taken from the grid rather than from the men's extremes, it
## neither swells into a turning block's corners nor follows one man knocked out of the ranks.
## An enemy pressing on a flank or the rear from outside is not inside, so a flank or rear
## attack keeps its edge over the ranks facing away. A square already strikes with whoever
## is threatened, so it has no interior pass. A routing block is a fleeing crowd with no ranks
## to be behind, so it has none either, and a routing enemy is never inside: a router overrun
## by its pursuer is the pursuit's to cut down, through the pursuer's own striking ranks.
## Pure geometry, no RNG.


## Per defender (aligned with `defenders` and `def_indices`), the indices of its living
## soldiers inside `attacker`'s block behind the striking set `front`. Returns an empty array
## when nothing is inside, so the caller's interior pass costs one footprint scan.
static func inside_candidates(attacker: Unit, front: PackedInt32Array, defenders: Array[Unit],
		def_indices: Array[PackedInt32Array]) -> Array[PackedInt32Array]:
	var none: Array[PackedInt32Array] = []
	var n: int = mini(attacker._sim_soldier_pos.size(), attacker._sim_soldier_hp.size())
	if front.is_empty() or front.size() >= n or attacker.in_square() \
			or attacker.state == Unit.State.ROUTING:
		return none
	var origin: Vector2 = attacker.position
	var fwd: Vector2 = attacker.near_front_forward()
	var front_depth: float = INF
	for i in front:
		front_depth = minf(front_depth, (attacker._sim_soldier_pos[i] - origin).dot(fwd))
	var centre := Vector2.ZERO
	var live: int = 0
	for i in range(n):
		if attacker._sim_soldier_hp[i] > 0.0:
			centre += attacker._sim_soldier_pos[i]
			live += 1
	if live == 0:
		return none
	centre /= float(live)
	var grid: Vector2 = MeleeFrontGeometry.grid_front(attacker)
	var across: Vector2 = grid.orthogonal()
	var prof: MeleeFrontProfile = MeleeFrontProfile.of(attacker)
	var margin: float = attacker.interior_strike_margin
	var rear: float = -prof.depth - margin
	var half_width: float = prof.half + margin
	var out: Array[PackedInt32Array] = []
	var any_inside := false
	var scanned: int = n
	for dj in range(defenders.size()):
		var inside := PackedInt32Array()
		var d: Unit = defenders[dj]
		if d.state == Unit.State.ROUTING:
			out.append(inside)
			continue
		scanned += def_indices[dj].size()
		for di in def_indices[dj]:
			var pos: Vector2 = d._sim_soldier_pos[di]
			if (pos - origin).dot(fwd) >= front_depth:
				continue
			var rel: Vector2 = pos - centre
			var along: float = rel.dot(grid)
			if along >= rear and along <= prof.depth and absf(rel.dot(across)) <= half_width:
				inside.push_back(di)
		any_inside = any_inside or not inside.is_empty()
		out.append(inside)
	SimOps.add(SimOps.MELEE_CHECK, scanned)
	return out if any_inside else none


## The block's men who may strike an inside enemy: every living man outside the striking set
## `front` (sorted, as Unit.engaged_soldier_indices returns it), in soldier-id order. Whether
## an inside enemy is actually within his reach is the caller's nearest-target search.
static func interior_strikers(attacker: Unit, front: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n: int = mini(attacker._sim_soldier_pos.size(), attacker._sim_soldier_hp.size())
	var k: int = 0
	for i in range(n):
		while k < front.size() and front[k] < i:
			k += 1
		if k < front.size() and front[k] == i:
			continue
		if attacker._sim_soldier_hp[i] > 0.0:
			out.push_back(i)
	return out
