class_name ProjectilePhysics
## Pure ballistics for projectile entities (#435): a level-ground launch solver and the
## height arc, as deterministic functions of (geometry, gravity, angle) only -- no node,
## no RNG, no wall-clock -- so they're directly unit-testable and replay-safe (mirrors
## DistanceLegend / CameraKeyframes). Horizontal motion is linear from the launch point to
## the aim point; the height z(t) is a gravity parabola above the launch level. A projectile
## entity samples ground_at()/height_at() each physics tick; when z returns to 0 it has
## landed, and the landing ground position is tested against soldier/object footprints.
##
## Units are world units (Battle.WORLD_UNITS_PER_METER = 20 wu/m) and seconds. `gravity` is
## a tunable balance knob in wu/s^2: real gravity is 9.8*20 = 196, but a lower value gives
## slower, higher, more readable arcs at battlefield ranges -- ProjectileField owns the value.

# Launch angles (radians) the auto fire-mode picks between: a low, fast, flat trajectory for
# a direct shot at the front, and a high lob that clears intervening ranks / cover. The
# engine chooses which per shot (line-of-sight / cover gating lands in a later slice).
const ANGLE_FLAT: float = 20.0 * PI / 180.0
const ANGLE_ARCED: float = 55.0 * PI / 180.0

# Below this squared length a direction vector is treated as carrying no direction at all
# (a soldier whose facing was never set, or an arrow that landed on top of its own launch
# point). Named rather than inlined so every guard that needs it agrees on the threshold.
const DEGENERATE_LENGTH_SQ: float = 1e-6


## Launch speed and flight time to carry a projectile a level-ground horizontal distance
## `dist` at launch angle `angle` (radians above horizontal) under `gravity`, from the range
## equation R = v^2 sin(2θ)/g. Returns {speed, flight_time}, both 0 for a degenerate input
## (non-positive dist/gravity, or an angle outside (0, 90deg) where the level-ground range is
## undefined/zero).
static func solve_launch(dist: float, gravity: float, angle: float) -> Dictionary:
	if dist <= 0.0 or gravity <= 0.0 or angle <= 0.0 or angle >= PI * 0.5:
		return {"speed": 0.0, "flight_time": 0.0}
	var s2: float = sin(2.0 * angle)
	if s2 <= 0.0:
		return {"speed": 0.0, "flight_time": 0.0}
	var speed: float = sqrt(dist * gravity / s2)
	var flight_time: float = 2.0 * speed * sin(angle) / gravity
	return {"speed": speed, "flight_time": flight_time}


## Height above the launch level at time `t` for a shot launched at `speed`,`angle` under
## `gravity`: z(t) = v sinθ · t − ½ g t². Zero at t = 0 and again at the flight time.
static func height_at(speed: float, angle: float, gravity: float, t: float) -> float:
	return speed * sin(angle) * t - 0.5 * gravity * t * t


## Peak height of that arc (reached at t = v sinθ / g). 0 for a non-positive gravity.
static func peak_height(speed: float, angle: float, gravity: float) -> float:
	if gravity <= 0.0:
		return 0.0
	var vz: float = speed * sin(angle)
	return vz * vz / (2.0 * gravity)


## Ground (horizontal) position at flight fraction `f` in [0, 1]: linear from `from` to `to`.
## `f` = t / flight_time; clamped so a sampler slightly past landing stays at the target.
static func ground_at(from: Vector2, to: Vector2, f: float) -> Vector2:
	return from.lerp(to, clampf(f, 0.0, 1.0))


## The three ways a landing arrow can meet a shield. PIERCE is the only outcome that
## wounds: the arrow drives through, or there was no shield in its way to begin with.
## DEFLECT glances off the face and is spent. LODGE sticks fast in the shield -- the man
## behind it is unhurt, but the arrow now hangs its own weight on his arm, which is why a
## caller tracks lodged arrows separately from deflected ones.
enum Impact {PIERCE, DEFLECT, LODGE}


## The angle an arrow arrives at, expressed in the struck soldier's OWN frame (radians,
## signed, wrapped to [-PI, PI]): 0 is dead ahead, +/-PI is dead astern. `facing` is the
## direction the soldier faces; `incoming_from` points from the soldier toward where the
## arrow came from -- the same "attack_from_dir" convention SoldierCombat.facing_gate uses.
## The result is directly comparable against a Shield's hold angle, which is expressed in
## that same frame. A degenerate (zero-length) facing or direction reads as dead ahead, so
## an undefined facing is fully met rather than handed a free back-shot -- matching the
## defensive choice facing_gate makes on the same input.
static func incoming_angle(facing: Vector2, incoming_from: Vector2) -> float:
	if facing.length_squared() < DEGENERATE_LENGTH_SQ:
		return 0.0
	if incoming_from.length_squared() < DEGENERATE_LENGTH_SQ:
		return 0.0
	return facing.angle_to(incoming_from)


## The chance a shield that IS covering the incoming line stops the arrow at all (deflected
## or lodged, before the split between the two). `block_value` is the shield type's own
## defensive weight from the loadout registry; `scale` converts that weight into a stop
## probability; `sag` is cover already lost to arrows hanging in the shield. Clamped to
## [0, 1], so an unshielded soldier (block_value 0) stops nothing and no scale pushes a
## shield past certainty.
static func shield_block_chance(block_value: float, scale: float, sag: float) -> float:
	return clampf(block_value * scale - sag, 0.0, 1.0)


## Which outcome a landing arrow gets, from one uniform `roll` in [0, 1). An arrow arriving
## outside the shield's arc (`covered` false) always pierces -- there is nothing in its way,
## whatever the shield would have been worth had it faced the other way. Inside the arc,
## `block` of the rolls stop it, and `lodge_share` of THOSE stick rather than glancing off.
## Pure: the caller draws the roll from the one seeded stream, so the outcome is a
## deterministic function of that roll and the same seed replays the same volley.
static func resolve_impact(covered: bool, block: float, lodge_share: float, roll: float) -> Impact:
	if not covered:
		return Impact.PIERCE
	var stop: float = clampf(block, 0.0, 1.0)
	var deflect: float = stop * (1.0 - clampf(lodge_share, 0.0, 1.0))
	if roll < deflect:
		return Impact.DEFLECT
	if roll < stop:
		return Impact.LODGE
	return Impact.PIERCE
