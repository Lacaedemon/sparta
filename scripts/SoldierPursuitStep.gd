class_name SoldierPursuitStep
extends RefCounted
## Horse riding a router down: each rider chases the runner nearest him, not the routed unit's
## centre, which can lie where no runner is once the rout scatters. He looks round once a
## reaction time (Unit.rout_reaction_ticks), on a tick of his own, and rides at that runner until
## he next looks (Unit._sim_flight_dir); he strikes the runners in his reach at his unit's cadence
## (strike). Pursuing horse were the main killers of a rout (Polybius 3.116, Cannae). Foot keep
## their ranks and follow a rout as a block: the Spartans pursued briefly and not far
## (Thucydides 5.73.4). SoldierBodies.step calls step in place of the slot arrival, and
## SoldierBodies.couple reads the unit's `position` off its men while it pursues.


## Whether `unit` is riding a routed enemy down: a mounted unit after a routing target with men,
## on the move or already among its runners (FIGHTING).
static func is_pursuing(unit: Unit) -> bool:
	if not unit.is_cavalry:
		return false
	if unit.state != Unit.State.MOVING and unit.state != Unit.State.FIGHTING:
		return false
	var quarry: Unit = unit.target_enemy
	return is_instance_valid(quarry) and quarry.state == Unit.State.ROUTING \
			and quarry.team != unit.team and not quarry._sim_soldier_pos.is_empty()


## Step `unit`'s first `n` pursuing men by `delta`; `guard` as SoldierFlightStep.step's.
static func step(unit: Unit, n: int, guard: Dictionary, delta: float) -> void:
	var quarry: Unit = unit.target_enemy
	var frame: int = Engine.get_physics_frames()
	var period: int = unit.rout_reaction_ticks()
	var accel: float = maxf(unit.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var mass: float = unit.combat_profile()["mass"]
	var top: float = unit.move_speed
	var cap_floor: float = top * unit.superphysical_speed_frac
	var field: PathField = PathField.active
	var clear: PackedVector2Array = SoldierKeepClear.bias(unit, n, top)
	if unit._sim_flight_dir.size() != n:
		unit._sim_flight_dir.resize(n)
		for i in range(n):
			unit._sim_flight_dir[i] = _toward_nearest(unit._sim_soldier_pos[i], quarry)
	for i in range(n):
		var pos: Vector2 = unit._sim_soldier_pos[i]
		var vel: Vector2 = unit._sim_body_vel[i]
		if (frame + i) % period == 0:
			unit._sim_flight_dir[i] = _toward_nearest(pos, quarry)
		var dir: Vector2 = unit._sim_flight_dir[i]
		var desired: Vector2 = dir * top * (field.speed_at(pos) if field != null else 1.0) \
				+ unit._sim_steer[i] + clear[i]
		if not guard.is_empty() and guard["inside"][i] == 0:
			desired = SoldierBodies.router_terrain_avoid(pos, vel,
					pos + dir * SoldierFlightStep.LOOK_AHEAD, desired, guard["grown"], accel, delta)
		var damped: Vector2 = SoldierCollision.apply_kinetic_friction(vel, mass, 0.0, delta)
		var cap: float = maxf(cap_floor, vel.length())
		var new_vel: Vector2 = ride(damped, desired, accel, Unit.TURN_RATE, delta).limit_length(cap)
		unit._sim_body_vel[i] = new_vel
		unit._sim_soldier_pos[i] = pos + new_vel * delta
		if new_vel.length_squared() > SoldierBodies.REST_SPEED * SoldierBodies.REST_SPEED:
			unit._sim_soldier_facing[i] = new_vel.normalized()
			unit._render_dirty = true
	SimOps.add(SimOps.BODY_STEP, n)


## A rider's next velocity from `vel`: he swings onto `desired` at `turn` (radians a second) at his
## pace, as a horse at the gallop turns rather than pulling up to, gaining or shedding pace at
## `accel`. At rest, or shoved past the pace he wants, he changes straight toward `desired`.
static func ride(vel: Vector2, desired: Vector2, accel: float, turn: float, delta: float) -> Vector2:
	var speed: float = vel.length()
	if speed <= SoldierBodies.REST_SPEED or desired == Vector2.ZERO \
			or speed > desired.length() + accel * delta:
		return vel.move_toward(desired, accel * delta)
	var swing: float = clampf(vel.angle_to(desired), -turn * delta, turn * delta)
	return (vel / speed).rotated(swing) * move_toward(speed, desired.length(), accel * delta)


## The unit direction from `pos` to the nearest body of `quarry` (ZERO on top of one).
static func _toward_nearest(pos: Vector2, quarry: Unit) -> Vector2:
	var best: Vector2 = quarry.position
	var best_sq: float = INF
	for p in quarry._sim_soldier_pos:
		var d_sq: float = pos.distance_squared_to(p)
		if d_sq < best_sq:
			best_sq = d_sq
			best = p
	var to: Vector2 = best - pos
	return to.normalized() if to.length_squared() > 0.0 else Vector2.ZERO


## `unit`'s pursuing men strike the runners of their quarry within their reach, as a fighting
## rank does (SoldierMelee.resolve_men), while it is on the move; once FIGHTING, its own strike
## (UnitCombat.strike) does. Returns whether it struck, so the caller arms the next cooldown.
static func strike(unit: Unit) -> bool:
	if unit.state != Unit.State.MOVING or not is_pursuing(unit) or unit._sim_soldier_pos.is_empty():
		return false
	var men := PackedInt32Array()
	for i in range(unit._sim_soldier_pos.size()):
		men.push_back(i)
	var defenders: Array[Unit] = [unit.target_enemy]
	SoldierMelee.resolve_men(unit, men, defenders)
	return true
