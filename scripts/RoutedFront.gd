class_name RoutedFront
extends RefCounted
## Where a unit following a rout brings its front to bear (Unit._face_for_action): on the nearest
## routed man standing outside its own block, the man its front rank would face. The centre of a
## routed unit's men is no man, and can stand among the block's own ranks, where a bearing names no
## front; a runner among the ranks is struck by the men he stands by, not faced by the block.


## The nearest man of routed `enemy` to `unit`'s anchor standing outside `unit`'s slot footprint
## (Unit.soldier_block_half_extents, in its grid's frame), or Vector2.INF when every one stands
## inside it.
static func point(unit: Unit, enemy: Unit) -> Vector2:
	var half: Vector2 = unit.soldier_block_half_extents()
	var angle: float = unit.soldier_block_world_angle()
	var best: float = INF
	var at := Vector2.INF
	for q in enemy._sim_soldier_pos:
		var local: Vector2 = (q - unit.position).rotated(-angle)
		if absf(local.x) <= half.x and absf(local.y) <= half.y:
			continue
		var d2: float = q.distance_squared_to(unit.position)
		if d2 < best:
			best = d2
			at = q
	return at
