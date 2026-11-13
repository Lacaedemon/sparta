class_name SoldierFlight
extends RefCounted
## Where one routed man runs. A routed unit is not a formation: each man flees on his own,
## from the foes he perceives (ManPerception) toward a refuge he knows, and he takes his line
## partly from the comrades of his file running ahead of him. SoldierFlightStep moves him.
##
## Sources. Routed men made for a known place of safety, and not all for the same one: after
## Delium "some made for Delium and the sea, some for Oropus, and others for Mount Parnes"
## (Thucydides 4.96.7). They crowded and trampled each other where the way narrowed (Xenophon,
## Hellenica 4.4.11-12, at the Long Walls of Corinth; Arrian, Anabasis 2.11.3, the Persian
## horse at Issus). The crowd rule is the herding term of D. Helbing, I. Farkas and T. Vicsek,
## "Simulating dynamical features of escape panic", Nature 407 (2000) 487-490: a panicking
## person's direction mixes his own with that of the people near him, by a weight p. The
## sources fix neither the refuge nor the crowd rule, so each reading is a named variant.
const ManPerceptionRef = preload("res://scripts/ManPerception.gd")

## Refuge readings. EDGE: his own rear edge of the field, where the army's camp lies behind
## its line, straight back from where he stands. LINES: the nearest formed friendly unit (the
## Delium men making for the fort and their friends), falling back to EDGE when there is none.
enum Refuge { EDGE, LINES }
## Crowd readings. HERD: Helbing's mixed direction, toward the run of the file-mate ahead.
## COLUMN: he falls in one rank pitch behind that file-mate (SoldierFollow.place), so the rout
## streams in files. ALONE: he takes no line from anyone (Helbing's p = 0).
enum Follow { HERD, COLUMN, ALONE }

## Whether routers query ManPerception at all; off, they flee toward refuge alone. The cost
## instrument (test_router_perception_cost.gd) flips it to measure the queries' cost.
static var perceive_threats: bool = true
static var _perception: RefCounted = ManPerceptionRef.new()
static var _frame: int = -1


## Bind this frame's perception inputs, as ManPerception.prepare. Battle calls it once a tick
## before the bodies step, and only while some unit is routing.
static func prepare(frame: int, units: Array, terrain: Array, path_field: Object) -> void:
	_frame = frame
	if perceive_threats:
		_perception.prepare(frame, units, terrain, path_field)


## What man `i` of `unit` perceives (ManPerception.perceive's answer), out to his unit's whole
## sight_range: a man running from foes still sees the ones ahead of him, so the fog's routing cut
## does not apply. Nothing when perception is off or nothing prepared it this frame.
static func perceived(unit: Unit, i: int, frame: int) -> Dictionary:
	if not perceive_threats or frame != _frame:
		return {"threat": Vector2.ZERO, "nearest_unit": null, "nearest_index": -1,
				"nearest_distance": INF}
	return _perception.perceive(unit, i, frame)


## The unit direction from `pos` toward the refuge `unit`'s men know.
static func refuge_direction(unit: Unit, pos: Vector2) -> Vector2:
	if unit.rout_refuge == Refuge.LINES and unit.is_inside_tree():
		var best: Unit = null
		var best_sq: float = INF
		for o in unit.get_tree().get_nodes_in_group("units"):
			var friend: Unit = o as Unit
			if friend == null or friend == unit or friend.team != unit.team \
					or friend.state == Unit.State.DEAD:
				continue
			var d_sq: float = pos.distance_squared_to(friend.position)
			if d_sq < best_sq:
				best_sq = d_sq
				best = friend
		if best != null and best_sq > 0.0:
			return (best.position - pos).normalized()
	# Team 0 deploys from the top edge and team 1 from the bottom, so a man's camp lies that way.
	return Vector2.UP if unit.team == 0 else Vector2.DOWN


## His own direction: away from the `threat` he perceives, toward his refuge (rout_refuge_weight
## against the summed threat, whose terms each weigh at most 1).
static func own_direction(unit: Unit, i: int, threat: Vector2) -> Vector2:
	var pos: Vector2 = unit._sim_soldier_pos[i]
	var refuge: Vector2 = refuge_direction(unit, pos)
	var d: Vector2 = refuge * unit.rout_refuge_weight - threat
	return d.normalized() if d.length_squared() > 0.000001 else refuge


## His direction once he takes a line from `mate` (a file-mate's body index, or -1): `own`
## turned toward the mate's run (HERD) or toward the place a rank pitch behind him (COLUMN),
## by rout_herding times how far ahead of him the mate is, up to one rank `pitch` (0 beside or
## behind him, so there is no switch in who leads).
static func with_mate(unit: Unit, i: int, own: Vector2, mate: int, pitch: float) -> Vector2:
	if mate < 0 or unit.rout_follow == Follow.ALONE or pitch <= 0.0:
		return own
	var pos: Vector2 = unit._sim_soldier_pos[i]
	var ahead: float = (unit._sim_soldier_pos[mate] - pos).dot(own)
	var w: float = unit.rout_herding * clampf(ahead / pitch, 0.0, 1.0)
	var run: Vector2 = unit._sim_body_vel[mate]
	if w <= 0.0 or run.length_squared() <= 0.000001:
		return own
	var line: Vector2 = run.normalized()
	if unit.rout_follow == Follow.COLUMN:
		var to_place: Vector2 = SoldierFollow.place(unit._sim_soldier_pos[mate],
				Vector2(0.0, pitch), line) - pos
		line = to_place.normalized() if to_place.length_squared() > 0.000001 else line
	var mixed: Vector2 = own * (1.0 - w) + line * w
	return mixed.normalized() if mixed.length_squared() > 0.000001 else own
