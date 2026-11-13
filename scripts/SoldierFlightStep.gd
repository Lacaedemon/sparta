class_name SoldierFlightStep
extends RefCounted
## One tick of a routed unit's men. Each runs where SoldierFlight sends him, at his flee pace
## slowed by the ground under him (PathField.speed_at), and changes his velocity no faster than
## his own acceleration allows: there is no slot, no anchor and no flight of the unit's to keep
## pace with. Near impassable terrain he veers along the face he is running at
## (SoldierBodies.router_terrain_avoid). He faces the way he runs. He looks round only once a
## reaction time (Unit.rout_reaction_ticks), on a tick of his own, and runs the way he then chose
## until he looks again (Unit._sim_flight_dir); a man who finds no way to run stands and fights
## (SoldierCornered). Called by SoldierBodies.step in place of the slot arrival, after the bodies
## are resized and before the terrain backstop.


## How far along his own line a routed man judges the way round terrain: past any block rect,
## not to a point on it. A solver reach rather than a gameplay quantity, tuned in wu.
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
	var period: int = unit.rout_reaction_ticks()
	var grown: Array[Rect2] = guard["grown"] if not guard.is_empty() else ([] as Array[Rect2])
	_size_choices(unit, n)
	for i in range(n):
		var pos: Vector2 = unit._sim_soldier_pos[i]
		var vel: Vector2 = unit._sim_body_vel[i]
		if (frame + i) % period == 0:
			_look_round(unit, i, frame, grown)
		var own: Vector2 = unit._sim_flight_dir[i]
		var desired: Vector2 = unit._sim_steer[i]
		if own != Vector2.ZERO:
			var mate: int = _mate_ahead(unit, i, own, mates)
			var dir: Vector2 = SoldierFlight.with_mate(unit, i, own, mate, pitch)
			desired += dir * top * (field.speed_at(pos) if field != null else 1.0)
		if own != Vector2.ZERO and not guard.is_empty() and guard["inside"][i] == 0:
			desired = SoldierBodies.router_terrain_avoid(pos, vel, pos + own * LOOK_AHEAD,
					desired, guard["grown"], body_accel, delta)
		var pre: float = vel.length()
		var damped: Vector2 = SoldierCollision.apply_kinetic_friction(vel, mass, 0.0, delta)
		var cap: float = maxf(cap_floor, pre)
		var new_vel: Vector2 = damped.move_toward(desired, body_accel * delta).limit_length(cap)
		unit._sim_body_vel[i] = new_vel
		unit._sim_soldier_pos[i] = pos + new_vel * delta
		if new_vel.length_squared() > SoldierBodies.REST_SPEED * SoldierBodies.REST_SPEED:
			if own != Vector2.ZERO:   # a man standing to fight keeps facing his foe
				unit._sim_soldier_facing[i] = new_vel.normalized()
			unit._render_dirty = true
	SimOps.add(SimOps.BODY_STEP, n)


## One chosen direction per man; a man with none yet runs for his refuge until he looks round.
static func _size_choices(unit: Unit, n: int) -> void:
	var have: int = unit._sim_flight_dir.size()
	if have == n:
		return
	unit._sim_flight_dir.resize(n)
	for i in range(have, n):
		unit._sim_flight_dir[i] = SoldierFlight.refuge_direction(unit, unit._sim_soldier_pos[i])


## Man `i` looks round: he chooses his way from what he perceives, or, finding none, turns to
## the foe nearest him (ZERO in _sim_flight_dir: he stands and fights).
static func _look_round(unit: Unit, i: int, frame: int, grown: Array[Rect2]) -> void:
	var seen: Dictionary = SoldierFlight.perceived(unit, i, frame)
	var own: Vector2 = SoldierFlightWay.choose(unit, i, seen["threat"], grown)
	if SoldierCornered.is_cornered(unit, i, own, seen, grown):
		var foe: Unit = seen["nearest_unit"]
		var to_foe: Vector2 = foe._sim_soldier_pos[seen["nearest_index"]] - unit._sim_soldier_pos[i]
		if to_foe.length_squared() > 0.0:
			unit._sim_soldier_facing[i] = to_foe.normalized()
		own = Vector2.ZERO
	unit._sim_flight_dir[i] = own


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
