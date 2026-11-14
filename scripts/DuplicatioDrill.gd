class_name DuplicatioDrill
extends RefCounted
## The duplicatio as the explicatio in reverse: the men an explicatio sent up the intervals go back
## to the stations they left (Asclepiodotus 10.20, Aelian 29.3; Unit._refresh_duplicatio_follow).


## The deal back of a block whose files an explicatio dealt onto 2 * `new_files` files, its
## intervals split at `lane_split` (UnitFormation.explicatio_lane_split, `inward` as dealt), from
## each man's file, rank and SoldierRole. New files 2k and 2k + 1 go back into old file k. A man
## with the EPISTATES role says every second man went up (ALTERNATE_RANK), so file and interval
## interleave again, file man m to rank 2m and interval man m to 2m + 1 while both have men; else
## the half-file went up (HALF_FILE) and the interval falls in behind the a men of its file, man r
## to rank a + r. Returns {"files", "ranks", "returning" (1 for each man of an interval), "drill"};
## {} when this is not an explicatio's deal: a file id out of range, ranks or roles that do not
## line up, no man with a role, or a man with a role who is not the head of an interval.
static func reverse_assignment(file_ids: PackedInt32Array, ranks: PackedInt32Array,
		roles: PackedByteArray, new_files: int, lane_split: int, inward: bool) -> Dictionary:
	var n: int = file_ids.size()
	if n == 0 or new_files <= 0 or ranks.size() != n or roles.size() != n:
		return {}
	var lengths := PackedInt32Array()
	lengths.resize(2 * new_files)
	var led: bool = false
	var alternate: bool = false
	for i in range(n):
		var f: int = file_ids[i]
		if f < 0 or f >= 2 * new_files:
			return {}
		lengths[f] += 1
		if roles[i] == UnitFormation.SoldierRole.NONE:
			continue
		if ranks[i] != 0 or UnitFormation.explicatio_file_stays(f, lane_split, inward):
			return {}
		led = true
		alternate = alternate or roles[i] == UnitFormation.SoldierRole.EPISTATES
	if not led:
		return {}
	var out_files := PackedInt32Array(file_ids)
	var out_ranks := PackedInt32Array(ranks)
	var returning := PackedByteArray(roles)
	for i in range(n):
		var f: int = file_ids[i]
		var stays: bool = UnitFormation.explicatio_file_stays(f, lane_split, inward)
		var a: int = lengths[f if stays else 4 * (f / 2) + 1 - f]   # the men of the file that stayed
		var b: int = lengths[4 * (f / 2) + 1 - f if stays else f]   # the men of its interval
		var r: int = ranks[i]
		if alternate:
			out_ranks[i] = r + mini(r, b) if stays else r + mini(r + 1, a)
		else:
			out_ranks[i] = r if stays else a + r
		out_files[i] = f / 2
		returning[i] = 0 if stays else 1
	return {"files": out_files, "ranks": out_ranks, "returning": returning,
			"drill": UnitFormation.ExplicatioDrill.ALTERNATE_RANK if alternate
			else UnitFormation.ExplicatioDrill.HALF_FILE}


## Whom each man follows while the files go back together (SoldierFollow), as
## UnitFormation.explicatio_follow_plan reads it for files that all stay: each man behind the head
## of his file follows the nearest man ahead of him in it, that many rank pitches behind; each file
## leader the next file leader toward `stand_file`, that many file pitches across and level, his
## depth dressed on the guide; the leader of `stand_file` holds his ground (STAND).
static func follow_plan(file_ids: PackedInt32Array, ranks: PackedInt32Array, stand_file: int,
		file_pitch: float, rank_pitch: float) -> Dictionary:
	var n: int = file_ids.size()
	var leaders := PackedInt32Array()
	var offsets := PackedVector2Array()
	var guides := PackedInt32Array()
	leaders.resize(n)
	offsets.resize(n)
	guides.resize(n)
	guides.fill(SoldierFollow.NOT_FOLLOWING)
	leaders.fill(SoldierFollow.HOLD)
	var at: Dictionary = {}
	for i in range(n):
		at[Vector2i(file_ids[i], ranks[i])] = i
	var guide: int = int(at.get(Vector2i(stand_file, 0), SoldierFollow.STAND))
	for i in range(n):
		var f: int = file_ids[i]
		var r: int = ranks[i]
		var step: int = signi(stand_file - f) if r == 0 else 0
		for back in range(1, maxi(r, absi(stand_file - f)) + 1):
			var key := Vector2i(f + step * back, 0) if r == 0 else Vector2i(f, r - back)
			var j: int = int(at.get(key, -1))
			if j >= 0:
				leaders[i] = j
				offsets[i] = Vector2(-step * back * file_pitch, back * rank_pitch * float(r > 0))
				break
		if r == 0:
			guides[i] = guide if guide != i else SoldierFollow.STAND
			if f == stand_file:
				leaders[i] = SoldierFollow.STAND
	return {"leaders": leaders, "offsets": offsets, "guides": guides}
