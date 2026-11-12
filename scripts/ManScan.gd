extends RefCounted
## One man's look at the enemy bodies around him: the work behind ManPerception.perceive,
## with no cache and no state of its own. He visits the bodies of every enemy unit whose
## bounding circle reaches his sight disc, keeps those inside the disc that pass his own
## line of sight (ManSight), and sums the unit directions to them, each weighted by distance
## and by his front arc (ManWeights). The nearest is tracked without the arc weighting: a
## man knows the foe at his elbow, whichever way he faces.
const Sight = preload("res://scripts/ManSight.gd")
const Weights = preload("res://scripts/ManWeights.gd")


## The answer for a man who perceives nothing.
static func none() -> Dictionary:
	return {"threat": Vector2.ZERO, "nearest_unit": null, "nearest_index": -1,
		"nearest_distance": INF, "perceived": 0, "nearest_pos": Vector2.ZERO,
		"own_pos": Vector2(INF, INF), "own_facing": Vector2(INF, INF), "contributors": []}


## Whether a cached answer still describes man `index` of `unit`: his own body is where it
## was and faces as it did (an out-of-range index stays so), every foe unit that contributed
## is alive and keeps its body count, and the nearest body is where it was. A reap or a
## merge re-packs the arrays, so an index can outlive the body it named, and a unit merged
## away keeps its bodies but is DEAD, which a fresh scan skips.
static func still_valid(unit: Unit, index: int, cached: Dictionary) -> bool:
	var own := Vector2(INF, INF)
	var facing := Vector2(INF, INF)
	if index >= 0 and index < unit._sim_soldier_pos.size():
		own = unit._sim_soldier_pos[index]
		facing = unit.soldier_facing(index)
	if own != cached["own_pos"] or facing != cached["own_facing"]:
		return false
	for c in cached["contributors"]:
		var foe: Unit = c[0]
		if foe.state == Unit.State.DEAD or foe._sim_soldier_pos.size() != int(c[1]):
			return false
	var nearest: Variant = cached["nearest_unit"]
	return nearest == null or (nearest as Unit)._sim_soldier_pos[cached["nearest_index"]] == cached["nearest_pos"]


## Returns the dictionary ManPerception.perceive documents, plus four keys that still_valid
## reads to notice that a cached answer went stale: "own_pos" and "own_facing" (his own
## body's position and facing, INF for an out-of-range index), "nearest_pos" (that body's
## position) and "contributors" ([unit, body count] for every foe unit with a perceived
## body). `rule` is ManSight.compile's answer for the frame, `foes` the frame's ManFoes,
## `radius` his sight in world units.
static func scan(unit: Unit, index: int, radius: float, rule: Dictionary, foes: RefCounted,
		half_angle: float, rear: float) -> Dictionary:
	var out: Dictionary = none()
	if index < 0 or index >= unit._sim_soldier_pos.size():
		return out
	var pos: Vector2 = unit._sim_soldier_pos[index]
	var facing: Vector2 = unit.soldier_facing(index)
	out["own_pos"] = pos
	out["own_facing"] = facing
	if radius <= 0.0:
		return out
	var local: Dictionary = Sight.near(rule, pos, radius)
	var open_ground: bool = (local["screens"] as Array).is_empty() and (local["blocks"] as Array).is_empty()
	var radius_sq: float = radius * radius
	var threat := Vector2.ZERO
	var nearest_sq: float = INF
	var perceived: int = 0
	for foe in foes.candidates(pos, radius):
		if foe.team == unit.team or foe.state == Unit.State.DEAD:
			continue
		var reach_out: float = radius + foes.reach_of(foe)
		if foe.position.distance_squared_to(pos) > reach_out * reach_out:
			continue
		var bodies: PackedVector2Array = foe._sim_soldier_pos
		var before: int = perceived
		for j in range(bodies.size()):
			var d_sq: float = pos.distance_squared_to(bodies[j])
			if d_sq > radius_sq:
				continue
			if not open_ground and not Sight.line_of_sight(pos, radius, bodies[j], local):
				continue
			perceived += 1
			if d_sq < nearest_sq:
				nearest_sq = d_sq
				out["nearest_unit"] = foe
				out["nearest_index"] = j
				out["nearest_pos"] = bodies[j]
			if d_sq <= 0.0:
				continue
			var to_foe: Vector2 = bodies[j] - pos
			var dist: float = sqrt(d_sq)
			threat += to_foe / dist * Weights.distance_weight(dist, radius) \
				* Weights.arc_weight(facing, to_foe, half_angle, rear)
		if perceived > before:
			(out["contributors"] as Array).append([foe, bodies.size()])
	out["threat"] = threat
	out["perceived"] = perceived
	if perceived > 0:
		out["nearest_distance"] = sqrt(nearest_sq)
	return out
