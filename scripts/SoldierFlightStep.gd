class_name SoldierFlightStep
extends RefCounted
## One tick of a routed unit's men. Each runs where SoldierFlight sends him, at his flee pace
## slowed by the ground under him (PathField.speed_at), and changes his velocity no faster than
## his own acceleration allows: there is no slot, no anchor and no flight of the unit's to keep
## pace with. Near impassable terrain he veers along the face he is running at
## (SoldierBodies.router_terrain_avoid). He faces the way he runs. Called by SoldierBodies.step
## in place of the slot arrival, after the bodies are resized and before the terrain backstop.


## How far ahead along his own line a routed man looks for the way round terrain, in world
## units: past any block rect, so the way round is judged to beyond the rock, not to a point on
## it. A solver reach rather than a gameplay quantity, tuned in wu.
const LOOK_AHEAD: float = 10000.0


## Step `unit`'s first `n` routed men by `delta`. `guard` is SoldierBodies._terrain_entry_guard's
## result for this tick (empty: no block terrain).
static func step(unit: Unit, n: int, guard: Dictionary, delta: float) -> void:
	var frame: int = Engine.get_physics_frames()
	var body_accel: float = maxf(unit.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var mass: float = unit.combat_profile()["mass"]
	var pitch: float = unit.rank_pitch_wu()
	var mates: Array[PackedInt32Array] = SoldierFileNeighbours.compute(
			unit, n, unit.formation_files(n))
	var field: PathField = PathField.active
	var top: float = unit.flee_speed()
	var cap_floor: float = top * unit.superphysical_speed_frac
	for i in range(n):
		var pos: Vector2 = unit._sim_soldier_pos[i]
		var vel: Vector2 = unit._sim_body_vel[i]
		var own: Vector2 = SoldierFlight.own_direction(unit, i, frame)
		var mate: int = _mate_ahead(unit, i, own, mates)
		var dir: Vector2 = SoldierFlight.with_mate(unit, i, own, mate, pitch)
		var pace: float = top * (field.speed_at(pos) if field != null else 1.0)
		var desired: Vector2 = dir * pace + unit._sim_steer[i]
		if not guard.is_empty() and guard["inside"][i] == 0:
			desired = SoldierBodies.router_terrain_avoid(pos, vel, pos + own * LOOK_AHEAD,
					desired, guard["grown"], body_accel, delta)
		var pre: float = vel.length()
		var damped: Vector2 = SoldierCollision.apply_kinetic_friction(vel, mass, 0.0, delta)
		var cap: float = maxf(cap_floor, pre)
		var new_vel: Vector2 = damped.move_toward(desired, body_accel * delta).limit_length(cap)
		unit._sim_body_vel[i] = new_vel
		unit._sim_soldier_pos[i] = pos + new_vel * delta
		if new_vel.length_squared() > SoldierBodies.REST_SPEED * SoldierBodies.REST_SPEED:
			unit._sim_soldier_facing[i] = new_vel.normalized()
			unit._render_dirty = true
	SimOps.add(SimOps.BODY_STEP, n)


## The file-mate ahead of man `i` along `own`: of the men in front of and behind him in his
## file (`mates`, SoldierFileNeighbours.compute), the one farther ahead along his line, or -1
## when neither is ahead of him.
static func _mate_ahead(unit: Unit, i: int, own: Vector2, mates: Array[PackedInt32Array]) -> int:
	var pos: Vector2 = unit._sim_soldier_pos[i]
	var best: int = -1
	var best_ahead: float = 0.0
	for side in mates:
		var j: int = side[i]
		if j < 0:
			continue
		var ahead: float = (unit._sim_soldier_pos[j] - pos).dot(own)
		if ahead > best_ahead:
			best_ahead = ahead
			best = j
	return best
