class_name DemoRelational
extends RefCounted
## The men judged against the men they follow, never against a point of the world. A dump's
## `relations` (DemoState.relations) name each man's leader (ahead in his file) and dressing man
## (to his right in his rank) with the offsets from them in the grid's own frame as (right,
## behind), so a turn, shift or fold of the grid cannot read as an error. Pure, and a leaf.


## Each relation edge at `pos`: [actual world vector, grid-frame target, man, other, kind], kind
## 0 for a leader edge (man behind other) and 1 for a dressing edge (other to the man's right).
static func edges(pos: Array, rel: Dictionary) -> Array:
	var out: Array = []
	if not rel.has("leaders"):
		return out
	for kind in range(2):
		var who: Array = rel["leaders"] if kind == 0 else rel["dress"]
		var offs: Array = rel["offsets"] if kind == 0 else rel["dress_offsets"]
		for i in range(mini(who.size(), pos.size())):
			var j: int = int(who[i])
			if j < 0 or j >= pos.size():
				continue
			var a := Vector2(pos[i][0], pos[i][1])
			var b := Vector2(pos[j][0], pos[j][1])
			out.append([(a - b) if kind == 0 else (b - a),
					Vector2(offs[i][0], offs[i][1]), i, j, kind])
	return out


## The rotation that best fits every edge's target onto the men (2-D Kabsch over edge vectors).
static func angle(edge_list: Array) -> float:
	var dot_sum: float = 0.0
	var cross_sum: float = 0.0
	for e in edge_list:
		dot_sum += (e[1] as Vector2).dot(e[0])
		cross_sum += (e[1] as Vector2).cross(e[0])
	return atan2(cross_sum, dot_sum)


## Whether some man other than `leader` stands in man `i`'s column nearer ahead of him than his
## leader does (or any man does, with the leader out of the column): he is behind the wrong man.
## The column runs along the grid's ahead axis turned by `turn`, `half_width` to either side.
static func _behind_wrong_man(pos: Array, i: int, leader: int, turn: float,
		half_width: float) -> bool:
	var ahead: Vector2 = Vector2.UP.rotated(turn)
	var me := Vector2(pos[i][0], pos[i][1])
	var nearest_other: float = INF
	var leader_along: float = INF
	for k in range(pos.size()):
		var d := Vector2(pos[k][0], pos[k][1]) - me
		var along: float = d.dot(ahead)
		if k == i or along <= 0.0 or absf(d.dot(ahead.orthogonal())) > half_width:
			continue
		if k == leader:
			leader_along = along
		else:
			nearest_other = minf(nearest_other, along)
	return nearest_other < leader_along


## Reading of one sample. `rms`: the larger of the per-edge RMS error (each man from the place
## behind his leader and his interval to his dressing man) and the whole block's, the RMS walk of
## every man to his fitted place (DemoRelationalFit). `far`: the farthest walk. `behind_wrong`:
## men behind another man than their leader, or in the place of their dressing man as he is in
## theirs. `settled`: the larger of the mean distance from each man to the nearest fitted place
## of any man and from each place to the nearest man (DemoGridMatch): small for men on the grid
## whoever stands where, large for men in transit or trailing off the grid.
static func read(pos: Array, rel: Dictionary, stand: float, half_width: float) -> Dictionary:
	var list: Array = edges(pos, rel)
	if list.is_empty():
		return {"edges": 0, "rms": 0.0, "far": 0.0, "behind_wrong": 0, "settled": 0.0}
	var n: int = pos.size()
	var grid: Dictionary = DemoRelationalFit.grid(rel, n)
	var fit: Dictionary = DemoRelationalFit.fit(pos, grid["places"], grid["piece"], stand)
	var cells: PackedVector2Array = fit["cells"]
	var turn: float = angle(list)
	var sq: float = 0.0
	var wrong: Dictionary = {}
	for e in list:
		sq += ((e[0] as Vector2) - (e[1] as Vector2).rotated(turn)).length_squared()
		var theta: float = fit["grid_theta"][e[2]]
		if e[4] == 1:
			if ((e[0] as Vector2) + (e[1] as Vector2).rotated(theta)).length() < stand:
				wrong[e[2]] = true
				wrong[e[3]] = true
		elif _behind_wrong_man(pos, e[2], e[3], theta, half_width):
			wrong[e[2]] = true
	var walk_sq: float = 0.0
	var far: float = 0.0
	var near_sum: float = 0.0
	var fill_sum: float = 0.0
	for i in range(n):
		var walk: float = Vector2(pos[i][0], pos[i][1]).distance_to(cells[i])
		walk_sq += walk * walk
		far = maxf(far, walk)
		near_sum += fit["near"][i]
		fill_sum += fit["fill"][i]
	return {"edges": list.size(), "rms": maxf(sqrt(sq / list.size()), sqrt(walk_sq / n)),
			"far": far, "behind_wrong": wrong.size(), "settled": maxf(near_sum, fill_sum) / n}
