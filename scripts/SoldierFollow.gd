class_name SoldierFollow
extends RefCounted
## The follow target mode: a man who steers on another man he can see, rather than on a slot of
## a grid laid out from the unit's position.
##
## A plan names, for each man, the man he follows (`leaders`) and where he stands relative to
## him (`offsets`), as (to his own right, behind him) in his own frame: his facing is his front,
## and his right is his facing turned a quarter clockwise on screen. His place is then the
## leader's body plus that offset (place). A man who follows nobody either holds a point
## (STAND, `points`) or stays where he is (HOLD). Only men with a plan entry follow; NOT_FOLLOWING
## leaves a man to his slot.
##
## A man in a rank may also dress on a guide (`guides`): he takes his place across his front from
## the man he follows, but his depth along it from the guide, the man the whole rank dresses on.
## So the rank's line is the guide's, and a man who has run a little ahead does not carry the man
## dressing on him ahead with him, link after link along the rank.
##
## He heads for his place in the way a man in a file does: he first gets onto his place's line
## across his front, and closes along it only as he gets onto that line (steer_point). So a man
## who has to change file steps sideways out of the file he stands in before he advances or
## falls back, rather than cutting a diagonal through the men beside him.
##
## SoldierBodies.step steers each following man on his steer point instead of his slot. The
## explicatio drills build their plans with UnitFormation.explicatio_follow_plan.

## A man with no plan entry: he keeps to his slot.
const NOT_FOLLOWING := -3
## A man who follows nobody and holds the ground he stood on (his entry in `points`).
const STAND := -2
## A man who follows nobody and stays where he is.
const HOLD := -1


## His right, for a man facing `facing`: the facing turned a quarter clockwise on screen (y-down).
static func right_of(facing: Vector2) -> Vector2:
	return Vector2(-facing.y, facing.x)


## A man's place: `leader_pos` plus `offset` (to his right, behind him) in the frame of his own
## `facing`.
static func place(leader_pos: Vector2, offset: Vector2, facing: Vector2) -> Vector2:
	var front: Vector2 = facing.normalized()
	return leader_pos + right_of(front) * offset.x - front * offset.y


## Each man's place under a plan, index-aligned with `positions`: `positions` and `facings` are
## the men's bodies and facings; `leaders`, `offsets`, `points` and `guides` the plan. `points`
## is read for STAND men, and for a guide of STAND, and may be empty otherwise; `guides` may be
## empty, and an entry of NOT_FOLLOWING dresses on no guide. A man not following, or holding, is
## placed where he stands. Arrays that do not line up give an empty result.
static func places(positions: PackedVector2Array, facings: PackedVector2Array,
		leaders: PackedInt32Array, offsets: PackedVector2Array,
		points: PackedVector2Array = PackedVector2Array(),
		guides: PackedInt32Array = PackedInt32Array()) -> PackedVector2Array:
	var n: int = positions.size()
	var out := PackedVector2Array()
	if facings.size() != n or leaders.size() != n or offsets.size() != n:
		return out
	var guided: bool = guides.size() == n
	out.resize(n)
	for i in range(n):
		var j: int = leaders[i]
		if j >= 0 and j < n:
			out[i] = place(positions[j], offsets[i], facings[i])
		elif j == STAND and i < points.size():
			out[i] = points[i]
		else:
			out[i] = positions[i]
			continue
		if not guided:
			continue
		var g: int = guides[i]
		var line: Vector2
		if g >= 0 and g < n:
			line = positions[g]
		elif g == STAND and i < points.size():
			line = points[i]
		else:
			continue
		var front: Vector2 = facings[i].normalized()
		out[i] += front * (line - out[i]).dot(front)
	return out


## Where a man at `pos` facing `facing` heads this tick for `target`: the full step across his
## front, and only the share of the step along it that he is on the target's line, falling from
## all of it on the line to none `line_width` or more off it. `room` (0 to 1) is how much of the
## gap he is stepping into has opened, as he sees it: he takes no more of the step along his front
## than that share, so he comes up into the gap as it opens and not before. A non-positive
## `line_width` heads straight for the target.
static func steer_point(pos: Vector2, facing: Vector2, target: Vector2, line_width: float,
		room: float = 1.0) -> Vector2:
	if line_width <= 0.0:
		return target
	var front: Vector2 = facing.normalized()
	var right: Vector2 = right_of(front)
	var d: Vector2 = target - pos
	var across: float = d.dot(right)
	var along: float = d.dot(front)
	if along <= 0.0:
		return target   # falling back into his place cuts across no file ahead of him
	var share: float = clampf(room, 0.0, 1.0)
	var on_line: float = clampf(1.0 - absf(across) / line_width, 0.0, 1.0)
	return pos + right * across + front * along * minf(on_line, share)


## How much of the gap between two men at `a` and `b` has opened for a third to step into, seen
## across the front of a man facing `facing`: none while they stand `line_width` or less apart
## across it (shoulder to shoulder), all of it once they stand twice that apart.
static func room_between(a: Vector2, b: Vector2, facing: Vector2, line_width: float) -> float:
	if line_width <= 0.0:
		return 1.0
	var apart: float = absf((b - a).dot(right_of(facing.normalized())))
	return clampf(apart / line_width - 1.0, 0.0, 1.0)
