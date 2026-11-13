class_name SoldierFollowSteer
extends RefCounted
## How a following man (SoldierFollow) heads for his place: the way a man in a file does. He
## first gets onto his place's line across his front, and comes up along it only as he gets onto
## that line and as the gap he is stepping into opens. So a man who has to change file steps
## sideways out of the file he stands in before he advances, rather than cutting a diagonal
## through the men beside him. Falling back into his place is always free.
##
## SoldierBodies.step steers each following man on his steer_point instead of his slot.


## Where a man at `pos` facing `facing` heads this tick for `target`: the full step across his
## front, and only the share of the step along it that he is on the target's line, falling from
## all of it on the line to none `line_width` or more off it. `room` (0 to 1) is how much of the
## step along his front the way ahead allows (lane_blockers: 1 while his lane is empty, 0 while
## a man stands in it), so he comes up into the gap once it has opened and not before. A target
## behind him, and a non-positive `line_width`, he heads straight for.
static func steer_point(pos: Vector2, facing: Vector2, target: Vector2, line_width: float,
		room: float = 1.0) -> Vector2:
	if line_width <= 0.0:
		return target
	var front: Vector2 = facing.normalized()
	var right: Vector2 = SoldierFollow.right_of(front)
	var d: Vector2 = target - pos
	var across: float = d.dot(right)
	var along: float = d.dot(front)
	if along <= 0.0:
		return target   # falling back into his place cuts across no file ahead of him
	var share: float = clampf(room, 0.0, 1.0)
	var on_line: float = clampf(1.0 - absf(across) / line_width, 0.0, 1.0)
	# TODO(#1974): the step across is taken whole; a man should not step sideways into a body
	# beside him. Gating it on the space beside him left held drills that never ended.
	return pos + right * across + front * along * minf(on_line, share)


## The men standing in the lane a man at `pos`, facing `facing`, comes up to his place along the
## line through `line`: of the men `candidates` (indices into `positions`), those of a file other
## than `own_file` (`files`, index-aligned with `positions`; his own file follows him in column)
## less than `clear` off that line across his front, from level with him (`behind` back) to
## `reach` ahead of him along it. `clear` is what he needs: a body's width, so that two bodies
## pass side by side without touching, or the file pitch where the files stand closer than that,
## as near as the line will ever let them. He comes up only while the lane is empty.
static func lane_blockers(pos: Vector2, facing: Vector2, line: Vector2,
		positions: PackedVector2Array, candidates: PackedInt32Array, files: PackedInt32Array,
		own_file: int, clear: float, reach: float, behind: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var front: Vector2 = facing.normalized()
	var right: Vector2 = SoldierFollow.right_of(front)
	for j in candidates:
		if files[j] == own_file:
			continue
		var along: float = (positions[j] - pos).dot(front)
		if along < -behind or along > reach:
			continue
		if absf((positions[j] - line).dot(right)) < clear:
			out.push_back(j)
	return out
