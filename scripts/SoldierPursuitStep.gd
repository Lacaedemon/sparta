class_name SoldierPursuitStep
extends RefCounted
## Horse riding a router down: each rider chases the nearest routed man he sees (ManPerception, the
## men of every routed foe), not the routed unit's centre. He looks round once a reaction time
## (Unit.rout_reaction_ticks), on a battle tick of his own (SoldierFlight.tick), and rides at that
## man until he next looks (Unit._sim_chase_dir), riding on while he sees none; he strikes the
## routed men in his reach at his unit's cadence (strike): at Cannae the Numidian horse cut most of
## the fleeing Roman cavalry down (Polybius 3.116); riding at the nearest is the sim's choice. Foot
## follow a rout in their ranks (SoldierFootPursuit). SoldierBodies.step calls step in place of the
## slot arrival, and couple reads the unit's `position` off its men while it pursues.


## Whether `unit` is riding a routed enemy down: a mounted unit ordered at a routing foe with men,
## moving or among its runners (FIGHTING). The order sends it; each rider picks his man (step).
static func is_pursuing(unit: Unit) -> bool:
	if not unit.is_cavalry or (unit.state != Unit.State.MOVING and unit.state != Unit.State.FIGHTING):
		return false
	var quarry: Unit = unit.target_enemy
	return is_instance_valid(quarry) and quarry.state == Unit.State.ROUTING \
			and quarry.team != unit.team and not quarry._sim_soldier_pos.is_empty()


## Step `unit`'s first `n` pursuing men by `delta`; `guard` as SoldierFlightStep.step's.
static func step(unit: Unit, n: int, guard: Dictionary, delta: float) -> void:
	var frame: int = Engine.get_physics_frames()
	var period: int = unit.rout_reaction_ticks()
	var accel: float = maxf(unit.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var mass: float = unit.combat_profile()["mass"]
	var top: float = unit.move_speed
	var cap_floor: float = top * unit.superphysical_speed_frac
	var field: PathField = PathField.active
	var contact: PackedVector2Array = SoldierBodies.standoff_free(unit, n, cap_floor)
	if unit._sim_chase_dir.size() != n:
		var had: int = unit._sim_chase_dir.size()
		unit._sim_chase_dir.resize(n)
		for i in range(had, n):
			unit._sim_chase_dir[i] = look(unit, i, frame, unit._sim_body_vel[i].normalized())
	for i in range(n):
		var pos: Vector2 = unit._sim_soldier_pos[i]
		var vel: Vector2 = unit._sim_body_vel[i]
		if (SoldierFlight.tick + i) % period == 0:
			unit._sim_chase_dir[i] = look(unit, i, frame, unit._sim_chase_dir[i])
		var dir: Vector2 = unit._sim_chase_dir[i]
		var pace: float = top * (field.speed_at(pos) if field != null else 1.0)
		var desired: Vector2 = (dir * pace + unit._sim_steer[i]).limit_length(pace)
		if not guard.is_empty() and guard["inside"][i] == 0:
			desired = SoldierBodies.router_terrain_avoid(pos, vel,
					pos + dir * SoldierFlightStep.LOOK_AHEAD, desired, guard["grown"], accel, delta)
		var damped: Vector2 = SoldierCollision.apply_kinetic_friction(vel, mass, 0.0, delta)
		var cap: float = maxf(cap_floor, vel.length())
		var new_vel: Vector2 = ride(damped, desired, accel, Unit.TURN_RATE, delta).limit_length(cap)
		unit._sim_body_vel[i] = new_vel
		var shove: Vector2 = contact[i] if not contact.is_empty() else Vector2.ZERO
		unit._sim_soldier_pos[i] = pos + SoldierBodies.with_contact(new_vel, shove, cap) * delta
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


## The way rider `i` of `unit` rides when he looks round: toward the nearest routed man he sees,
## or on along `was` when he sees none.
static func look(unit: Unit, i: int, frame: int, was: Vector2) -> Vector2:
	var seen: Dictionary = SoldierFlight.perceived(unit, i, frame, true)
	var foe: Unit = seen["nearest_unit"]
	if foe == null:
		return was
	var to: Vector2 = foe._sim_soldier_pos[seen["nearest_index"]] - unit._sim_soldier_pos[i]
	return to.normalized() if to.length_squared() > 0.0 else was


## `unit`'s pursuing men strike the routed men of any routed foe within their reach, as a
## fighting rank does (SoldierMelee.resolve_men), while it is on the move; once FIGHTING, its own
## strike (UnitCombat.strike) does. Returns whether it struck, so the caller arms the next cooldown.
static func strike(unit: Unit) -> bool:
	if unit.state != Unit.State.MOVING or not is_pursuing(unit) or unit._sim_soldier_pos.is_empty():
		return false
	var men := PackedInt32Array()
	for i in range(unit._sim_soldier_pos.size()):
		men.push_back(i)
	var defenders: Array[Unit] = []
	for foe in SoldierCornered.foes_near(unit, unit.position,
			unit.soldier_reach() + SoldierCornered._spread(unit)):
		if foe.state == Unit.State.ROUTING:
			defenders.append(foe)
	SoldierMelee.resolve_men(unit, men, defenders)
	return true
