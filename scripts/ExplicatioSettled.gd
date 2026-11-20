class_name ExplicatioSettled
## Which men of an explicatio drill the men behind them see settled, so that a man waiting in his
## unopened old file goes (ExplicatioOpening.hold_unopened). Read only from what each man's body
## shows (Unit._explicatio_seen) and the deal, never from another man's drill state. Pure.


## Each of `n` men is settled when the men behind him see him:
## - on his own place by the deal (`seen` "placed"), at rest or not, with the man he dresses on
##   by the deal (`leaders`, a man with none dressing on a point) settled too; or
## - at rest ("at_rest") and gone from where he stood when the drill began ("moved"), and either
##   the leader of his file (`is_head`), held short of his place, or a man with rock or another
##   man's body directly in his way ("blocked", body_in_way: a man of another old file).
## Gone and at rest alone does not settle a man of the column: the men trailing a file as it opens
## come to rest with it, and every man stands at rest before the drill moves. Settles nobody when
## the readings do not line up.
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
	var changed: bool = true
	while changed:
		changed = false
		for i in range(n):
			if out[i] == 1:
				continue
			var j: int = leaders[i]
			var led: bool = j < 0 or j >= n or out[j] == 1
			var held: bool = at_rest[i] == 1 and moved[i] == 1 \
					and (is_head[i] == 1 or blocked[i] == 1)
			if held or (placed[i] == 1 and led):
				out[i] = 1
				changed = true
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
