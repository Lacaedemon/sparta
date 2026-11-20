class_name RoutedFront
extends RefCounted
## Where a unit following a rout brings its front to bear (Unit._face_for_action): on the routed
## unit's centre while that stands clear of its own block, and nowhere while it stands among its
## ranks, where a bearing from the anchor names no front, so the unit keeps its heading. A facing
## read off what the block's own men see is #1955 (facing from the men); until then the bearing
## stays the unit's, and the runners among the ranks are struck by the men they stand by.


## `enemy`'s position when it lies outside `unit`'s slot footprint (Unit.soldier_block_half_extents,
## in its grid's frame), else Vector2.INF.
static func point(unit: Unit, enemy: Unit) -> Vector2:
	var half: Vector2 = unit.soldier_block_half_extents()
	var local: Vector2 = (enemy.position - unit.position).rotated(-unit.soldier_block_world_angle())
	if absf(local.x) <= half.x and absf(local.y) <= half.y:
		return Vector2.INF
	return enemy.position
