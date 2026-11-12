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
## gap he is stepping into has opened, as he sees it: he takes no more of the step along his front
## than that share, so he comes up into the gap as it opens and not before. A target behind him,
## and a non-positive `line_width`, he heads straight for.
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
	return pos + right * across + front * along * minf(on_line, share)


## How much of the gap between two men at `a` and `b` has opened for a third to step into, seen
## across the front of a man facing `facing`, where `a` is the man of the file he opened from:
## he comes up on his place's line, a full `line_width` from `a`'s, so `b` stands (apart -
## line_width) from it. None while that is half a width, a body's radius, or less (they stand one
## and a half widths apart or less); all of it once it is a full width, a man shoulder to
## shoulder each side of him (two widths apart).
static func room_between(a: Vector2, b: Vector2, facing: Vector2, line_width: float) -> float:
	if line_width <= 0.0:
		return 1.0
	var apart: float = absf((b - a).dot(SoldierFollow.right_of(facing.normalized())))
	return clampf(2.0 * apart / line_width - 3.0, 0.0, 1.0)
