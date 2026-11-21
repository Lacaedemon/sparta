class_name ExplicatioSettled
## Which men of an explicatio drill have settled and passed the word back, so that a man waiting
## in his unopened old file goes (ExplicatioOpening.hold_unopened). Read from what each man's body
## shows (Unit._explicatio_seen), the deal, and the word from the man he dresses on. Pure.


## Each of `n` men has settled, and passes the word back to the man behind him, when:
## - he is at rest on his own place by the deal (`seen` "at_rest", "placed") and has had the word
##   from the man he dresses on by the deal (`leaders`; "word", that man's word as passed on the
##   last tick; a man who dresses on a point needs none); or
## - he is at rest, gone from where he stood when the drill began ("moved"), and either the leader
##   of his file (`is_head`), held short of his place, or a man with rock or a man of another old
##   file directly in his way ("blocked", body_in_way).
## Sight alone cannot tell a man settled on his place from one trailing at a rank pitch, which is
## his place too, so the word passes back man by man, a tick each: the sim's inference. Aelian 35
## (Tactiks, 1616) has directions given by voice, visible sign and trumpet, and says nothing of a
## word passed along a file. Gone and at rest alone does not settle a man of the column: the men
## trailing a file as it opens come to rest with it. Settles nobody when the readings do not line
## up.
static func men(leaders: PackedInt32Array, is_head: PackedByteArray, seen: Dictionary,
		n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	var at_rest: PackedByteArray = seen.get("at_rest", PackedByteArray())
	var moved: PackedByteArray = seen.get("moved", PackedByteArray())
	var blocked: PackedByteArray = seen.get("blocked", PackedByteArray())
	var placed: PackedByteArray = seen.get("placed", PackedByteArray())
	if leaders.size() != n or at_rest.size() != n or moved.size() != n or blocked.size() != n \
			or placed.size() != n or is_head.size() != n:
		return out
	var word: PackedByteArray = seen.get("word", PackedByteArray())
	for i in range(n):
		var j: int = leaders[i]
		var told: bool = j < 0 or j >= n or (word.size() == n and word[j] == 1)
		var held: bool = moved[i] == 1 and (is_head[i] == 1 or blocked[i] == 1)
		if at_rest[i] == 1 and ((placed[i] == 1 and told) or held):
			out[i] = 1
	return out


## Whether a man of another old file (`old_files`, by index) stands directly in man `j`'s way to
## `place`: ahead of him along it, within a body's breadth (twice `r`) of it, and touching him, at
## most twice `r` and `reach` off. The men of his own old file are the column he trails, not men
## in his way: counting them settles a man of the column merely at rest behind it.
static func body_in_way(j: int, place: Vector2, bodies: PackedVector2Array,
		old_files: PackedInt32Array, r: float, reach: float) -> bool:
	var way: Vector2 = (place - bodies[j]).normalized()
	for k in range(mini(bodies.size(), old_files.size())):
		var d: Vector2 = bodies[k] - bodies[j]
		if old_files[k] != old_files[j] and d.dot(way) > 0.0 and absf(d.cross(way)) < 2.0 * r \
				and d.length() <= 2.0 * r + reach:
			return true
	return false
