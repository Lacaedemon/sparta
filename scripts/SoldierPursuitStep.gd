class_name SoldierPursuitStep
extends RefCounted
## Horse riding a router down, rider by rider. A rider under an order to pursue
## (SoldierTakeUp) rides at the nearest routed man he sees, looking round once a reaction time
## (Unit.rout_reaction_ticks) on a battle tick of his own (SoldierFlight.tick), while he sees one
## (Unit._sim_chase_dir not ZERO), and strikes the routed men in his reach (strike). A rider who
## sees none keeps to his order, on his place in the ranks (SoldierBodies.step). At Cannae the
## Numidian horse cut most of the fleeing Roman cavalry down (Polybius 3.116); riding at the
## nearest is the sim's choice. Foot follow a rout in their ranks (SoldierFootPursuit).


## Whether any rider of `unit` is riding at a routed man he sees. Read off the men.
static func is_pursuing(unit: Unit) -> bool:
	if not unit.is_cavalry:
		return false
	for way in unit._sim_chase_dir:
		if way != Vector2.ZERO:
			return true
	return false


## Whether rider `i` of `unit` is riding at a routed man he sees.
static func chasing(unit: Unit, i: int) -> bool:
	return i < unit._sim_chase_dir.size() and unit._sim_chase_dir[i] != Vector2.ZERO


## Whether every one of `unit`'s first `n` riders is riding at a routed man.
static func all_chasing(unit: Unit, n: int) -> bool:
	if unit._sim_chase_dir.size() < n or n == 0:
		return false
	for i in range(n):
		if unit._sim_chase_dir[i] == Vector2.ZERO:
			return false
	return true


## Step those of `unit`'s first `n` riders who are riding a routed man down by `delta`; `guard`
## as SoldierFlightStep.step's. The others are stepped on their places (SoldierBodies.step).
static func step(unit: Unit, n: int, guard: Dictionary, delta: float) -> void:
	var accel: float = maxf(unit.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var mass: float = unit.combat_profile()["mass"]
	var top: float = unit.move_speed
	var cap_floor: float = top * unit.superphysical_speed_frac
	var field: PathField = PathField.active
	var contact: PackedVector2Array = SoldierBodies.standoff_free(unit, n, cap_floor)
	for i in range(n):
		if not chasing(unit, i):
			continue
		var pos: Vector2 = unit._sim_soldier_pos[i]
		var vel: Vector2 = unit._sim_body_vel[i]
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
static func ride(vel: Vector2, desired: Vector2, accel: float, turn: float,
		delta: float) -> Vector2:
	var speed: float = vel.length()
	if speed <= SoldierBodies.REST_SPEED or desired == Vector2.ZERO \
			or speed > desired.length() + accel * delta:
		return vel.move_toward(desired, accel * delta)
	var swing: float = clampf(vel.angle_to(desired), -turn * delta, turn * delta)
	return (vel / speed).rotated(swing) * move_toward(speed, desired.length(), accel * delta)


## `unit`'s pursuing men strike the routed men of any routed foe within their reach, as a
## fighting rank does (SoldierMelee.resolve_men), while it is on the move; once FIGHTING, its own
## strike (UnitCombat.strike) does. Returns whether it struck, so the caller arms the next cooldown.
static func strike(unit: Unit) -> bool:
	if unit.state != Unit.State.MOVING or not is_pursuing(unit) or unit._sim_soldier_pos.is_empty():
		return false
	var men := PackedInt32Array()
	for i in range(unit._sim_soldier_pos.size()):
		if chasing(unit, i):
			men.push_back(i)
	var defenders: Array[Unit] = []
	for foe in SoldierCornered.foes_near(unit, unit.position,
			unit.soldier_reach() + SoldierCornered._spread(unit)):
		if foe.state == Unit.State.ROUTING:
			defenders.append(foe)
	SoldierMelee.resolve_men(unit, men, defenders)
	return true
