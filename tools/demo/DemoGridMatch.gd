class_name DemoGridMatch
extends RefCounted
## Whether men stand on a grid's cells, whoever stands where. The cells are the grid's `a`
## (centred places) turned by a rotation, the men `b` (centred positions). Two readings: `near`,
## each man's distance to the nearest cell, and `fill`, each cell's distance to the nearest man.
## Men on the grid have both small; men in transit, or trailing off the grid's end, do not.
## Pure, and a leaf.


## The rotation of `a` onto `b` to read the grid by, with the `near` and `fill` distances under it
## (index-aligned with `a` and `b`). Starts from `turn` (the least-squares fit); when that leaves
## the grid unsettled (the larger of the two mean distances over `settle`), as men standing on the
## wrong places do by dragging the fit off, the principal-axis rotation and its quarter turns are
## tried and the most settled wins.
static func best(a: Array, b: Array, turn: float, settle: float) -> Dictionary:
	var chosen: float = turn
	var read: Dictionary = _read(a, b, turn)
	if read["score"] > settle:
		for k in range(4):
			var candidate: float = _axis(b) - _axis(a) + k * PI * 0.5
			var tried: Dictionary = _read(a, b, candidate)
			if tried["score"] < read["score"]:
				chosen = candidate
				read = tried
	read["turn"] = chosen
	return read


static func _read(a: Array, b: Array, turn: float) -> Dictionary:
	var cells: Array = []
	for p in a:
		cells.append((p as Vector2).rotated(turn))
	var near: Array = _distances(b, cells)
	var fill: Array = _distances(cells, b)
	return {"near": near, "fill": fill, "score": maxf(_mean(near), _mean(fill))}


## For each of `from`, the distance to the nearest of `to`.
static func _distances(from: Array, to: Array) -> Array:
	var out: Array = []
	for p in from:
		var nearest: float = INF
		for q in to:
			nearest = minf(nearest, (p as Vector2).distance_to(q))
		out.append(nearest)
	return out


static func _mean(values: Array) -> float:
	var total: float = 0.0
	for v in values:
		total += v
	return total / maxf(1.0, float(values.size()))


## The angle of the principal axis of the centred points `pts`.
static func _axis(pts: Array) -> float:
	var sxx: float = 0.0
	var syy: float = 0.0
	var sxy: float = 0.0
	for p in pts:
		sxx += p.x * p.x
		syy += p.y * p.y
		sxy += p.x * p.y
	return 0.5 * atan2(2.0 * sxy, sxx - syy)
