class_name ExplicatioOpening
## When an explicatio's files open, against when its men step into the intervals, where the
## sources differ or are silent (docs/historical-reshaping-maneuvers.md, "The explicatio drills"):
## - TOGETHER, the default and the sim's own inference: the files open out sideways while the men
##   who change file step out and come up the intervals.
## - FILES_FIRST: each old file opens out to its distance as a whole, its men keeping their
##   places in it, and only then do its men step into the interval beside it, each once the man
##   ahead of him has gone. Bingham's note on Aelian 29.3 says the doubling "must be done in open
##   order", the files "standing in open order" when the middlemen march up between them; that
##   the files must therefore stand open first is the sim's reading. The opening is the files
##   moving out to their distance, as in Aelian 33, "the rest proceeding on to the Target", and
##   Bingham's note on it, "moue on till the first distance recouered". Doing the opening first
##   in the lengthening explicatio, which opens and inserts in one drill, is the sim's inference.
## Asclepiodotus 10.17 and Aelian 29.3 insert on the same ground, the phalanx keeping its length
## ("keeping the same ground"); Asclepiodotus 10.18 then opens it, and Arrian, Tactica 25.3 to
## 25.5, inserts and then extends the line. That is the same-ground reading
## (UnitFormation.ExplicatioGround.SAME_GROUND) followed by an opening of the order, not a
## reading of this one. Pure: functions of their arguments only.

enum Reading { TOGETHER = 0, FILES_FIRST = 1 }

const READINGS := [Reading.TOGETHER, Reading.FILES_FIRST]
const NAMES := {Reading.TOGETHER: "together", Reading.FILES_FIRST: "files first"}


## `plan` (UnitFormation.explicatio_follow_plan) with each man of an old file who has not yet
## moved off kept in it: he follows the man ahead of him in it, a rank pitch behind, so the file
## opens out as a whole. The old file is new files f and f ^ 1 (file_ids >> 1); its leader is
## the front man of the file that stays (rank 0; a casualty closes the ranks up behind him). The
## man ahead of each man behind the leader is the nearest man of his old file ahead of him along
## `forward`, read from where the men stand (`bodies`), so a man who falls drops out of the file
## and the man behind him follows the next man ahead. The leader keeps his own plan, dressing on
## the next file toward the guide. Each man reads only the man ahead of him, this tick: the man
## right behind the leader waits until the leader has taken his place (`following` 0); every other
## man waits until the man ahead of him has taken his place or has stepped out of his file, more
## than half a file pitch (`file_pitch`) to the side of him. So the file opens from its leader
## back, each man moving off once he sees the man ahead of him go, a tick or more after him. Adds
## "waiting", 1 for each man held so; `plan` is changed in place and returned.
static func hold_unopened(plan: Dictionary, file_ids: PackedInt32Array, ranks: PackedInt32Array,
		bodies: PackedVector2Array, forward: Vector2, lane_split: int, inward: bool,
		following: PackedByteArray, file_pitch: float, rank_pitch: float) -> Dictionary:
	var n: int = file_ids.size()
	var waiting := PackedByteArray()
	waiting.resize(n)
	plan["waiting"] = waiting
	if following.size() != n or bodies.size() < n or ranks.size() != n:
		return plan
	var leaders: PackedInt32Array = plan["leaders"]
	var offsets: PackedVector2Array = plan["offsets"]
	var guides: PackedInt32Array = plan["guides"]
	var side := Vector2(-forward.y, forward.x)
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
		var depth: float = bodies[head].dot(forward)
		var men: Array = (files[k] as Array).filter(func(i: int) -> bool:
			return bodies[i].dot(forward) < depth)
		men.sort_custom(func(a: int, b: int) -> bool:
			var da: float = bodies[a].dot(forward)
			var db: float = bodies[b].dot(forward)
			return da > db or (da == db and a < b))   # front to rear
		var ahead: int = head
		for i in men:
			var gone: bool = following[ahead] == 0 or (ahead != head
					and absf((bodies[ahead] - bodies[i]).dot(side)) > 0.5 * file_pitch)
			if not gone:
				leaders[i] = ahead
				offsets[i] = Vector2(0.0, rank_pitch)
				guides[i] = SoldierFollow.NOT_FOLLOWING
				waiting[i] = 1
			ahead = i
	plan["leaders"] = leaders
	plan["offsets"] = offsets
	plan["guides"] = guides
	plan["waiting"] = waiting
	return plan
