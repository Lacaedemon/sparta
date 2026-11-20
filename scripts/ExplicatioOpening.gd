class_name ExplicatioOpening
## When an explicatio's files open, against when its men step into the intervals. No source gives
## the order in the lengthening drill, which opens and inserts at once, so both readings are the
## sim's inference (docs/historical-reshaping-maneuvers.md, "The explicatio drills"):
## - TOGETHER, the default: the files open out while the men step out and come up the intervals.
## - FILES_FIRST: each old file opens out as a whole, its men keeping their places in it, and only
##   then do they step into the interval beside it. Bingham's note on Aelian 29.3 has the files
##   "standing in open order" for the doubling on the same ground; Aelian 33 and Bingham's note
##   on it have files "moue on till the first distance recouered", how a file opens.
## Asclepiodotus 10.17, Aelian 29.3 and Arrian, Tactica 25.3 to 25.5, insert on the same ground
## and then extend: UnitFormation.ExplicatioGround.SAME_GROUND, not a reading of this one. Pure.

enum Reading { TOGETHER = 0, FILES_FIRST = 1 }

const READINGS := [Reading.TOGETHER, Reading.FILES_FIRST]
const NAMES := {Reading.TOGETHER: "together", Reading.FILES_FIRST: "files first"}


## `plan` (UnitFormation.explicatio_follow_plan) with each man of an unopened old file (new files
## f and f ^ 1) kept a rank pitch behind the man ahead of him in it. Its leader, the front man of
## the file that stays (rank 0, closed up behind by a casualty), keeps his own plan. The man ahead
## of a man is the nearest of the leader and the old file's other men ahead of him
## along his own facing (`facings`), from where they stand (`bodies`). A man waits until he sees
## him go: stand, for good (`following` 0) or on the last tick (`stood`), or, but for the leader,
## step over half a file pitch (`file_pitch`) to his side. Once a man has moved off (`released`)
## he never waits again, though the men behind still see him: so the file opens from its leader
## back, a man at a time. Adds "waiting" and "released", the latter with this tick's added.
static func hold_unopened(plan: Dictionary, file_ids: PackedInt32Array, ranks: PackedInt32Array,
		bodies: PackedVector2Array, facings: PackedVector2Array, lane_split: int, inward: bool,
		following: PackedByteArray, stood: PackedByteArray, released: PackedByteArray,
		file_pitch: float, rank_pitch: float) -> Dictionary:
	var n: int = file_ids.size()
	var waiting := PackedByteArray()
	waiting.resize(n)
	var out_released := PackedByteArray()
	out_released.resize(n)
	if released.size() == n:
		out_released = released.duplicate()
	plan["waiting"] = waiting
	plan["released"] = out_released
	if following.size() != n or bodies.size() < n or facings.size() < n or ranks.size() != n:
		return plan
	var leaders: PackedInt32Array = plan["leaders"]
	var offsets: PackedVector2Array = plan["offsets"]
	var guides: PackedInt32Array = plan["guides"]
	var heads: Dictionary = {}
	var files: Dictionary = {}
	for i in range(n):
		var k: int = file_ids[i] >> 1
		if ranks[i] == 0 and UnitFormation.explicatio_file_stays(file_ids[i], lane_split, inward):
			heads[k] = i
		elif files.has(k):
			files[k].append(i)
		else:
			files[k] = [i]
	for k in files:
		var head: int = int(heads.get(k, -1))
		if head < 0:
			continue   # no leader to open out on
		var front: Vector2 = facings[head].normalized()
		var men: Array = files[k]
		men.sort_custom(func(a: int, b: int) -> bool:
			return bodies[a].dot(front) > bodies[b].dot(front))   # front to rear
		for i in men:
			if out_released[i] == 1 or following[i] == 0:
				continue   # he has moved off, or taken his place: he never waits in the file again
			var f: Vector2 = facings[i].normalized()
			var a: int = _man_ahead(i, head, men, bodies, f)
			var seen: bool = a >= 0 and (following[a] == 0 or (stood.size() == n and stood[a] == 1))
			var wait: bool = a >= 0 and not seen
			if wait and a != head and waiting[a] == 0:
				wait = absf((bodies[a] - bodies[i]).dot(Vector2(-f.y, f.x))) <= 0.5 * file_pitch
			if wait:
				leaders[i] = a
				offsets[i] = Vector2(0.0, rank_pitch)
				guides[i] = SoldierFollow.NOT_FOLLOWING
				waiting[i] = 1
			else:
				out_released[i] = 1
	plan["leaders"] = leaders
	plan["offsets"] = offsets
	plan["guides"] = guides
	plan["waiting"] = waiting
	plan["released"] = out_released
	return plan


## The nearest of `head` and `men` ahead of man `i` along `forward`, or -1.
static func _man_ahead(i: int, head: int, men: Array, bodies: PackedVector2Array,
		forward: Vector2) -> int:
	var best: int = -1
	var best_gap: float = INF
	for j in [head] + men:
		var gap: float = (bodies[j] - bodies[i]).dot(forward)
		if j != i and gap > 0.0 and gap < best_gap:
			best = j
			best_gap = gap
	return best
