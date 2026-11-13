class_name SoldierKeepClear
extends RefCounted
## How a man with no place in a formation keeps off the men of his own unit: riders after one
## runner close on him from several sides, and a rider does not ride into a friend. A formed unit
## keeps its men apart by their places; a pursuing one (SoldierPursuitStep) has none.


## Each of `unit`'s first `n` men's way off his own unit's men whose bodies touch his: away from
## each, growing with how far the two overlap, to `top` (his own pace) when two stand on one spot.
static func bias(unit: Unit, n: int, top: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n)
	var reach: float = 2.0 * unit.soldier_body_radius()
	var cells: Dictionary = {}
	for i in range(n):
		var c := Vector2i((unit._sim_soldier_pos[i] / reach).floor())
		if not cells.has(c):
			cells[c] = []
		cells[c].append(i)
	for i in range(n):
		var pos: Vector2 = unit._sim_soldier_pos[i]
		var c := Vector2i((pos / reach).floor())
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for j in cells.get(c + Vector2i(dx, dy), []):
					var off: Vector2 = pos - unit._sim_soldier_pos[j]
					var d: float = off.length()
					if j == i or d >= reach:
						continue
					var away: Vector2 = off / d if d > 0.01 \
							else Vector2.RIGHT.rotated(float(mini(i, j))) * signf(float(i - j))
					out[i] += away * top * (reach - d) / reach
	return out
