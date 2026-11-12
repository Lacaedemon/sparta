extends RefCounted
## One man's look at the enemy bodies around him: the work behind ManPerception.perceive,
## with no cache and no state of its own.
##
## He visits the bodies of every enemy unit whose bounding circle reaches his sight disc,
## keeps those inside the disc that pass his own line of sight (ManSight), and sums the unit
## directions to them, each weighted by distance and by his front arc (ManWeights). The
## nearest one is tracked without the arc weighting: a man knows the foe at his elbow
## whichever way he faces.
const Sight = preload("res://scripts/ManSight.gd")
const Weights = preload("res://scripts/ManWeights.gd")


## The answer for a man who perceives nothing.
static func none() -> Dictionary:
	return {"threat": Vector2.ZERO, "nearest_unit": null, "nearest_index": -1,
		"nearest_distance": INF, "perceived": 0, "nearest_count": 0,
		"nearest_pos": Vector2.ZERO}


## Returns the dictionary ManPerception.perceive documents, plus "nearest_count" (the nearest
## foe unit's body count, which the cache uses to notice a reap). `rule` is ManSight.compile's
## answer for the frame, `foes` the frame's ManFoes, `radius` his sight in world units.
static func scan(unit: Unit, index: int, radius: float, rule: Dictionary, foes: RefCounted,
		half_angle: float, rear: float) -> Dictionary:
	var out: Dictionary = none()
	if index < 0 or index >= unit._sim_soldier_pos.size():
		return out
	if radius <= 0.0:
		return out
	var pos: Vector2 = unit._sim_soldier_pos[index]
	var facing: Vector2 = unit.soldier_facing(index)
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
				out["nearest_count"] = bodies.size()
				out["nearest_pos"] = bodies[j]
			if d_sq <= 0.0:
				continue
			var to_foe: Vector2 = bodies[j] - pos
			var dist: float = sqrt(d_sq)
			threat += to_foe / dist * Weights.distance_weight(dist, radius) \
				* Weights.arc_weight(facing, to_foe, half_angle, rear)
	out["threat"] = threat
	out["perceived"] = perceived
	if perceived > 0:
		out["nearest_distance"] = sqrt(nearest_sq)
	return out
