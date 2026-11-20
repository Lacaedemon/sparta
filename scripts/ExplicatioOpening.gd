class_name ExplicatioOpening
## When an explicatio's files open, against when its men step into the intervals. No source gives
## the order in the lengthening drill, which opens and inserts at once, so both readings are the
## sim's inference (docs/historical-reshaping-maneuvers.md, "The explicatio drills"):
## - TOGETHER, the default: the files open out while the men step out and come up the intervals.
## - FILES_FIRST: each old file opens out as a whole, its men keeping their places in it, and only
##   then do they step into the interval beside it. Bingham's note on Aelian 29.3 (Tactiks of
##   Aelian, 1616, p. 134) has the files "standing in open order" for the doubling on the same
##   ground; Aelian 33 (p. 141) and his note on it (p. 142) have files "moue on till the first
##   distance recouered", how a file opens.
## Asclepiodotus 10.17, Aelian 29.3 and Arrian, Tactica 25.3 to 25.5, insert on the same ground
## and then extend: UnitFormation.ExplicatioGround.SAME_GROUND, not a reading of this one. Pure.

enum Reading { TOGETHER = 0, FILES_FIRST = 1 }

const READINGS := [Reading.TOGETHER, Reading.FILES_FIRST]
const NAMES := {Reading.TOGETHER: "together", Reading.FILES_FIRST: "files first"}

## `plan` (UnitFormation.explicatio_follow_plan) with each man of an unopened old file (new files
## f and f ^ 1) kept a rank pitch behind the man ahead of him in it, so the file opens out as a
## whole. The leader, the front man of the file that stays (rank 0), keeps his own plan. From
## where the men stand (`bodies`), the man ahead of a man is the nearest of the leader and the men
## of his old file within a file pitch (`file_pitch`) of his line and ahead of him by both men's
## facings (`facings`), so no two men wait on each other. A man waits until he sees that man
## settle (ExplicatioSettled.men, from what each man's body shows, `seen`) or step out: be a man
## the deal put in the interval file, standing over half a file pitch off his line. The motion
## cannot tell a man stepping out from one trailing the file sideways (8061 step-out offsets, 0 to
## 4.6 wu, lay within the 5.64 wu trailing men reached), so the step-out is read from the deal,
## drill every man knows. A man gone and over half a file pitch off his leader's line has stepped
## out (`released`) and never waits again. Adds "waiting" and "released" (with this tick's added).
static func hold_unopened(plan: Dictionary, file_ids: PackedInt32Array, ranks: PackedInt32Array,
		bodies: PackedVector2Array, facings: PackedVector2Array, lane_split: int, inward: bool,
		following: PackedByteArray, seen: Dictionary, released: PackedByteArray,
		file_pitch: float, rank_pitch: float) -> Dictionary:
	var n: int = file_ids.size()
	var waiting := PackedByteArray()
	waiting.resize(n)
	var out := PackedByteArray()
	out.resize(n)
	if released.size() == n:
		out = released.duplicate()
	plan["waiting"] = waiting
	plan["released"] = out
	if following.size() != n or bodies.size() < n or facings.size() < n or ranks.size() != n:
		return plan
	var leaders: PackedInt32Array = plan["leaders"]
	var offsets: PackedVector2Array = plan["offsets"]
	var guides: PackedInt32Array = plan["guides"]
	var heads: Dictionary = {}
	var files: Dictionary = {}
	var is_head := PackedByteArray()
	is_head.resize(n)
	for i in range(n):
		var k: int = file_ids[i] >> 1
		if ranks[i] == 0 and UnitFormation.explicatio_file_stays(file_ids[i], lane_split, inward):
			heads[k] = i
			is_head[i] = 1
		elif files.has(k):
			files[k].append(i)
		else:
			files[k] = [i]
	var settled: PackedByteArray = ExplicatioSettled.men(leaders, is_head, seen, n)
	var half: float = 0.5 * file_pitch
	for k in files:
		var head: int = int(heads.get(k, -1))
		if head < 0:
			continue   # no leader to open out on
		var hf: Vector2 = facings[head].normalized()
		for i in files[k]:
			if out[i] == 1 or following[i] == 0:
				continue   # he has stepped out, or taken his place: he never waits again
			var f: Vector2 = facings[i].normalized()
			var side := Vector2(-f.y, f.x)
			var a: int = head
			var best: float = (bodies[head] - bodies[i]).dot(f)
			for j in files[k]:
				var d: Vector2 = bodies[j] - bodies[i]
				var gap: float = d.dot(f)
				if j == i or gap <= 0.0 or gap >= best or absf(d.dot(side)) >= file_pitch \
						or d.dot(facings[j].normalized()) <= 0.0:
					continue   # not the nearest ahead of him in his file, by his eyes and his own
				a = j
				best = gap
			var gone: bool = settled[a] == 1
			if a != head and not UnitFormation.explicatio_file_stays(file_ids[a], lane_split, inward):
				gone = gone or absf((bodies[a] - bodies[i]).dot(side)) > half   # stepped out
			if best > 0.0 and not gone:
				leaders[i] = a
				offsets[i] = Vector2(0.0, rank_pitch)
				guides[i] = SoldierFollow.NOT_FOLLOWING
				waiting[i] = 1
			elif absf((bodies[i] - bodies[head]).dot(Vector2(-hf.y, hf.x))) > half:
				out[i] = 1   # gone, and out of his leader's line: he has stepped out
	plan["leaders"] = leaders
	plan["offsets"] = offsets
	plan["guides"] = guides
	plan["waiting"] = waiting
	plan["released"] = out
	return plan

