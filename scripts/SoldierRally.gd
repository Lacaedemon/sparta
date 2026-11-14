class_name SoldierRally
extends RefCounted
## Riders a chase left scattered rally on their standard: each rides to his place beside the man
## he rallies on, read off the formation's shape (no place on the ground); the ilarch, at the
## squadron's front angle (Asclepiodotus 7.2, Arrian Tactica 16.5), pulls up, and the troop moves
## off once he sees it formed on him. None of these sources describes a rally after a pursuit, so
## whom a man rallies on is the sim's inference, a named variant (Unit.chase_rally): FILE (default),
## the man ahead in his file, as Xenophon's files follow their leaders (Hipparchicus 2); ILARCH, the
## ilarch, inferred from a wedge's riders watching their one leader (Asclepiodotus 7.3).

enum Mode { FILE, ILARCH }


static func is_rallying(unit: Unit) -> bool:
	return not unit._sim_rally_on.is_empty()


## Deal whom each man rallies on; the ilarch, the front rank's most central man, on nobody (-1).
static func begin(unit: Unit, n: int) -> void:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	var ang: float = unit.soldier_block_world_angle()
	var off := PackedVector2Array()
	for i in range(n):
		off.push_back((slots[i] - unit.position).rotated(-ang) if i < slots.size() else Vector2.ZERO)
	var half: float = unit.file_pitch_wu() * 0.5
	var ilarch: int = 0
	for i in range(n):
		if off[i].y < off[ilarch].y - half \
				or (absf(off[i].y - off[ilarch].y) <= half and absf(off[i].x) < absf(off[ilarch].x)):
			ilarch = i
	var on := PackedInt32Array()
	on.resize(n)
	for i in range(n):
		on[i] = -1 if i == ilarch else _ahead(off, i, half, ilarch, unit.chase_rally)
	unit._sim_rally_offset = off
	unit._sim_rally_on = on


## The man `i` rallies on: under FILE the nearest man ahead of him in his file, else `ilarch`.
static func _ahead(off: PackedVector2Array, i: int, half: float, ilarch: int, mode: int) -> int:
	if mode == Mode.ILARCH:
		return ilarch
	var best: int = ilarch
	for j in range(off.size()):
		if j != i and absf(off[j].x - off[i].x) <= half and off[j].y < off[i].y - half \
				and (best == ilarch or off[j].y > off[best].y):
			best = j
	return best


## Step the rallying men; false, touching nobody, once the ilarch is formed and the troop moves
## off. A man is formed within Unit.standoff_off_slot_pitches file pitches of his place beside
## the man he rallies on, once every man rallying on him is.
static func step(unit: Unit, n: int, delta: float) -> bool:
	if unit._sim_rally_on.size() != n:
		begin(unit, n)   # a man has fallen since: deal again
	var on: PackedInt32Array = unit._sim_rally_on
	var off: PackedVector2Array = unit._sim_rally_offset
	var ilarch: int = on.find(-1)
	var turn: float = unit._sim_soldier_facing[ilarch].angle() + PI * 0.5
	var up_sq: float = pow(unit.standoff_off_slot_pitches * unit.file_pitch_wu(), 2.0)
	var places := PackedVector2Array(off)   # each man's place, filled below
	var formed: PackedInt32Array = on.duplicate()   # 1 for a man formed, filled below
	for i in range(n):
		var r: int = on[i]
		places[i] = unit._sim_soldier_pos[i] if r < 0 \
				else unit._sim_soldier_pos[r] + (off[i] - off[r]).rotated(turn)
		formed[i] = 1 if unit._sim_soldier_pos[i].distance_squared_to(places[i]) <= up_sq else 0
	for pass_i in range(n):   # a man is formed only once each man rallying on him is
		for i in range(n):
			if on[i] >= 0 and formed[i] == 0:
				formed[on[i]] = 0
	if formed[ilarch] == 1:
		unit._sim_rally_on = PackedInt32Array()
		unit._sim_rally_offset = PackedVector2Array()
		return false
	var accel: float = maxf(unit.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var cap: float = unit.move_speed * unit.superphysical_speed_frac
	var contact: PackedVector2Array = SoldierBodies.standoff_free(unit, n, cap)
	for i in range(n):
		var pos: Vector2 = unit._sim_soldier_pos[i]
		var vel: Vector2 = unit._sim_body_vel[i]
		var to: Vector2 = places[i] - pos
		var dist: float = to.length()
		var speed: float = vel.length()
		# A rider whose place lies off his line reins in to turn rather than circling it at a gallop.
		var ahead: float = 1.0 if speed <= SoldierBodies.REST_SPEED or dist <= 0.01 \
				else maxf(0.0, vel.dot(to) / (speed * dist))
		var desired: Vector2 = Vector2.ZERO if dist <= 0.01 \
				else to / dist * minf(unit.move_speed, sqrt(2.0 * accel * dist)) * ahead
		var new_vel: Vector2 = SoldierPursuitStep.ride(vel, desired, accel, Unit.TURN_RATE, delta) \
				.limit_length(maxf(cap, speed))
		unit._sim_body_vel[i] = new_vel
		var shove: Vector2 = contact[i] if not contact.is_empty() else Vector2.ZERO
		unit._sim_soldier_pos[i] = pos + SoldierBodies.with_contact(new_vel, shove, cap) * delta
		if new_vel.length_squared() > SoldierBodies.REST_SPEED * SoldierBodies.REST_SPEED:
			unit._sim_soldier_facing[i] = new_vel.normalized()
	unit._render_dirty = true
	SimOps.add(SimOps.BODY_STEP, n)
	return true
