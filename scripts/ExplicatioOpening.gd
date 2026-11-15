class_name ExplicatioOpening
## When an explicatio's files open, against when its men step into the intervals, where the
## sources differ or are silent (docs/historical-reshaping-maneuvers.md, "The explicatio drills"):
## - TOGETHER, the default and the sim's own inference: the files open out sideways while the men
##   who change file step out and come up the intervals.
## - FILES_FIRST: each old file opens out to its distance as a whole, its men keeping their
##   places in it, and only then do its men step into the interval beside it. Asclepiodotus 10.17
##   inserts the new files "between the original files", and Bingham's note on Aelian 29.3 says
##   the insertion "must be done in open order"; that the files must therefore stand open first
##   is the sim's reading. The opening is the files moving out to their distance, as in Aelian
##   33, "the rest proceeding on to the Target", and Bingham's note on it, "moue on till the
##   first distance recouered". Doing the opening first in the lengthening explicatio, which
##   opens and inserts in one drill, is the sim's inference.
## Arrian, Tactica 25.3 to 25.5, inserts first, on the same ground, and only then extends the line;
## that is the same-ground reading (UnitFormation.ExplicatioGround.SAME_GROUND) followed by an
## opening of the order, not a reading of this one. Pure: functions of their arguments only.

enum Reading { TOGETHER = 0, FILES_FIRST = 1 }

const READINGS := [Reading.TOGETHER, Reading.FILES_FIRST]
const NAMES := {Reading.TOGETHER: "together", Reading.FILES_FIRST: "files first"}


## The man who stood ahead of the man at new file `f`, rank `r` in his old file, before an
## explicatio by `drill` (UnitFormation.ExplicatioDrill) dealt it, as a key Vector2i(file, rank)
## of the new assignment; Vector2i(-1, -1) for an old file leader. `stays` is whether `f` is a file
## that stays, `partner` the other new file of the same old file, and `front_len` how many men
## the file that stays of that old file holds (the front half of a half-file deal).
static func old_ahead(f: int, r: int, stays: bool, partner: int, front_len: int,
		drill: int) -> Vector2i:
	if drill == UnitFormation.ExplicatioDrill.ALTERNATE_RANK:
		if stays:
			return Vector2i(-1, -1) if r == 0 else Vector2i(partner, r - 1)
		return Vector2i(partner, r)
	if stays:
		return Vector2i(-1, -1) if r == 0 else Vector2i(f, r - 1)
	return Vector2i(partner, front_len - 1) if r == 0 else Vector2i(f, r - 1)


## `plan` (UnitFormation.explicatio_follow_plan) with every man of an old file whose leader has
## not yet taken his place (`following` 1 for him) kept in that old file: he follows the man who
## stood ahead of him in it (old_ahead), a rank pitch behind, so the file opens out as a whole.
## The leader of each file that stays keeps his own plan, dressing on the next file toward the
## guide; once he has taken his place his file has opened and its men take the drill's plan.
## A man whose man ahead in the old file has fallen keeps the drill's plan. Adds "waiting", 1 for
## each man held so; `plan` is changed in place and returned.
static func hold_unopened(plan: Dictionary, file_ids: PackedInt32Array, ranks: PackedInt32Array,
		lane_split: int, inward: bool, drill: int, following: PackedByteArray,
		rank_pitch: float) -> Dictionary:
	var n: int = file_ids.size()
	var leaders: PackedInt32Array = plan["leaders"]
	var offsets: PackedVector2Array = plan["offsets"]
	var guides: PackedInt32Array = plan["guides"]
	var waiting := PackedByteArray()
	waiting.resize(n)
	var at: Dictionary = {}
	var lengths: Dictionary = {}
	for i in range(n):
		at[Vector2i(file_ids[i], ranks[i])] = i
		lengths[file_ids[i]] = int(lengths.get(file_ids[i], 0)) + 1
	for i in range(n):
		var f: int = file_ids[i]
		var stays: bool = UnitFormation.explicatio_file_stays(f, lane_split, inward)
		var front: int = f if stays else (f ^ 1)
		var head: int = int(at.get(Vector2i(front, 0), -1))
		if head < 0 or head == i or following.size() != n or following[head] == 0:
			continue
		var key: Vector2i = old_ahead(f, ranks[i], stays, f ^ 1, int(lengths.get(front, 0)), drill)
		var j: int = int(at.get(key, -1))
		if j < 0:
			continue
		leaders[i] = j
		offsets[i] = Vector2(0.0, rank_pitch)
		guides[i] = SoldierFollow.NOT_FOLLOWING
		waiting[i] = 1
	plan["leaders"] = leaders
	plan["offsets"] = offsets
	plan["guides"] = guides
	plan["waiting"] = waiting
	return plan
