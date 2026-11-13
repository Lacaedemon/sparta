class_name DemoRelationalFit
extends RefCounted
## The whole block's shape, read from the men's relations. Chaining each man's offsets back
## through his leaders and dressing men gives his identity place in the grid's own frame, as
## (right, behind) from the first man of his connected piece. That is no point of the world:
## it is where his file and rank put him against every other man. Fitting those places onto
## where the men stand (one rotation and shift per piece) leaves each man's walk to his place,
## so a block compressed, spread, sheared or bent as a whole reads, where the per-edge errors
## of DemoRelational stay small. Pure, and a leaf: it runs under bare `godot -s`.


## Each man's place in the grid frame and the piece he belongs to, by breadth-first walk over
## the leader and dressing relations of `rel` for `n` men. Men no relation reaches are pieces of
## their own.
static func grid(rel: Dictionary, n: int) -> Dictionary:
	var adj: Array = []
	for i in range(n):
		adj.append([])
	for kind in range(2):
		var who: Array = rel.get("leaders", []) if kind == 0 else rel.get("dress", [])
		var offs: Array = rel.get("offsets", []) if kind == 0 else rel.get("dress_offsets", [])
		for i in range(mini(n, who.size())):
			var j: int = int(who[i])
			if j < 0 or j >= n:
				continue
			var o := Vector2(offs[i][0], offs[i][1])
			# A leader edge puts man i at his leader plus o; a dressing edge puts man j at i plus o.
			var to_j: Vector2 = -o if kind == 0 else o
			adj[i].append([j, to_j])
			adj[j].append([i, -to_j])
	var places := PackedVector2Array()
	places.resize(n)
	var piece := PackedInt32Array()
	piece.resize(n)
	piece.fill(-1)
	var count: int = 0
	for start in range(n):
		if piece[start] >= 0:
			continue
		piece[start] = count
		var queue: Array = [start]
		var head: int = 0
		while head < queue.size():
			var i: int = queue[head]
			head += 1
			for e in adj[i]:
				if piece[e[0]] < 0:
					piece[e[0]] = count
					places[e[0]] = places[i] + (e[1] as Vector2)
					queue.append(e[0])
		count += 1
	return {"places": places, "piece": piece}


## The fit of `places` onto the men at `pos`, one rotation and shift per piece. `cells` and
## `theta` come from the best-fit rotation (2-D Kabsch), and give each man's walk to his place.
## `grid_theta` and `near` read the grid as a pattern, whoever stands where (DemoGridMatch.best,
## given `settle`): `near` is each man's distance to the nearest cell of any man, `fill` the
## distance from each man's own cell to the nearest man.
static func fit(pos: Array, places: PackedVector2Array, piece: PackedInt32Array,
		settle: float) -> Dictionary:
	var n: int = mini(pos.size(), places.size())
	var out: Dictionary = {"cells": PackedVector2Array(), "theta": PackedFloat32Array(),
			"grid_theta": PackedFloat32Array(), "near": PackedFloat32Array(),
			"fill": PackedFloat32Array()}
	for key in out:
		out[key].resize(n)
	var groups: Dictionary = {}
	for i in range(n):
		if not groups.has(piece[i]):
			groups[piece[i]] = []
		groups[piece[i]].append(i)
	for men in groups.values():
		var from_c := Vector2.ZERO
		var to_c := Vector2.ZERO
		for i in men:
			from_c += places[i]
			to_c += Vector2(pos[i][0], pos[i][1])
		from_c /= float(men.size())
		to_c /= float(men.size())
		var a: Array = []
		var b: Array = []
		var dot_sum: float = 0.0
		var cross_sum: float = 0.0
		for i in men:
			a.append(places[i] - from_c)
			b.append(Vector2(pos[i][0], pos[i][1]) - to_c)
			dot_sum += (a[-1] as Vector2).dot(b[-1])
			cross_sum += (a[-1] as Vector2).cross(b[-1])
		var turn: float = atan2(cross_sum, dot_sum)
		var matched: Dictionary = DemoGridMatch.best(a, b, turn, settle)
		for m in range(men.size()):
			var i: int = men[m]
			out["cells"][i] = (a[m] as Vector2).rotated(turn) + to_c
			out["theta"][i] = turn
			out["grid_theta"][i] = matched["turn"]
			out["near"][i] = matched["near"][m]
			out["fill"][i] = matched["fill"][m]
	return out
