extends Node2D
class_name Unit
## A regiment: one selectable token with a soldier count and morale.
## Renders itself via _draw() with per-type sprite shapes: infantry kite
## shield, spearmen hoplon + spear, cavalry horse + rider.
## Its soldier marks are flat geometric shapes when zoomed out and swap to
## detailed figure silhouettes (a standing soldier, a mounted rider) when the
## camera zooms in past LOD_ZOOM_IN — see _update_lod / UnitMeshes.figure_mesh.

enum State { IDLE, MOVING, FIGHTING, ROUTING, DEAD }

# Stable per-battle id (assigned by Battle.gd at spawn). Replays reference units
# by this so recorded orders survive scene reloads.
var uid: int = -1

# --- Tunable stats (set by Battle.gd when spawning) ---
@export var unit_name: String = "Spearmen"
@export var team: int = 0
@export var max_soldiers: int = 120
@export var attack: int = 12
@export var defense: int = 6
@export var move_speed: float = 90.0    # sprint pace (also the loadout's declared top speed)
# Walk/jog paces, in world units/s -- independent per-type values (Battle sets them
# from the loadout's walk_mps/jog_mps), not a fixed fraction of move_speed. Real gaits
# don't scale by a uniform ratio across unit types (a horse's walk/trot/gallop ratios
# look nothing like a human's walk/jog/sprint ratios), and load-carriage research shows
# a heavier panoply costs proportionally more at a run than at a walk. Defaults here
# match the old 0.5/0.75 fractions of the default move_speed, for bare test units that
# never get a loadout.
@export var walk_speed: float = 45.0
@export var jog_speed: float = 67.5
# Backward-walk speed factor: a soldier repositioning BACKWARD relative to his own
# facing (a common motion during a maneuver -- conversio, quarter-turn, frontage
# reshape -- where the rear ranks back up into new slots) is capped slower than one
# moving forward. Real troops shuffle backward at roughly half their forward pace,
# so a maneuver where men must back up takes longer than one where they step forward.
# Battle.gd sets this per-type from the loadout's "back_fraction" (see
# Battle._default_loadout). This 0.5 default is the fallback for a bare test unit
# that never gets a loadout.
@export var back_speed_fraction: float = 0.5
# Acceleration/deceleration, in world units/s^2 -- how fast this unit's actual speed
# ramps toward whichever pace it's targeting (see _current_speed below), instead of
# snapping there instantly. Independent per-type values (Battle sets them from the
# loadout's accel_mps2/decel_mps2), following the same panoply-weight reasoning as
# walk_speed/jog_speed: heavier kit accelerates slower, and decel > accel for foot
# troops (stopping needs no propulsive effort; starting does). Cavalry is symmetric --
# a galloping horse can't be reined in any faster than it can build up speed.
# Defaults are a middling (infantry-like) value for bare test units without a loadout.
@export var accel: float = 30.0
@export var decel: float = 60.0
# Effective melee reach, in world units (Battle sets it per weapon from reach_m;
# the 26 default is the infantry/sword baseline). A unit counts as in melee
# contact when the gap to its target closes within attack_range + both RADII, so a
# longer-reach weapon (a spear) reaches contact — and strikes — sooner than a
# shorter one (a sword) as the lines close.
@export var attack_range: float = 26.0
# Interned loadout type ids (see LoadoutRegistry): which weapon and shield TYPE
# this regiment's soldiers carry. Battle._spawn_unit sets them per type from the
# loadout table, and the per-soldier arrays (_sim_soldier_weapon_id /
# _sim_soldier_shield_id below) are seeded from them. Defaults are the infantry
# baseline (gladius + scutum), matching the attack_range default above, so a
# bare test unit spawned without a loadout still resolves to real types.
var weapon_type_id: int = LoadoutRegistry.WEAPON_GLADIUS
var shield_type_id: int = LoadoutRegistry.SHIELD_SCUTUM
@export var is_cavalry: bool = false
@export var anti_cavalry: bool = false   # spearmen: blunt cavalry charges
@export var is_ranged: bool = false   # archers: loose volleys from a distance
# Seconds before the unit starts executing a new order. Models the real-world
# lag between a signal and the regiment actually stepping off. Default 0.5 s;
# faster units (cavalry) can be given a lower value at spawn time.
@export var order_response_delay: float = 0.5
# Discipline and experience level (0.0 raw recruits → 1.0 veteran legionaries).
# Well-trained melee units cycle their ranks in combat: fresh files rotate to the
# front, which reduces fatigue buildup and sustains morale through prolonged fights.
@export var training: float = 0.0:
	set(v):
		training = clampf(v, 0.0, 1.0)

# --- Runtime state ---
var soldiers: int
var morale: float = 100.0
var fatigue: float = 0.0   # 0 fresh .. 100 exhausted; rotated out by relief
var cohesion: float = 1.0   # 1.0 gelled; drops on a merge, then ramps back
var state: int = State.IDLE
var facing: Vector2 = Vector2.DOWN
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
var target_enemy: Unit = null
var selected: bool = false
# The unified orders queue (docs/orders-queue-design.md). `current_order` (orders[0],
# or null when idle) is the single, transcript-visible source of truth for "what is this
# unit doing right now" -- including its active phase, for a phased order like the
# move-to-rear about-face. As of phase 2 the queue is AUTHORITATIVE for the movement
# maneuvers: an in-place turn (a rear move's about-face phase, the standalone
# about-face/quarter-turn drills) and the wheel keep their execution state on the Order
# itself (turn_target / turn_start_facing / pivot), _think advances it off current_order,
# and replacing or clearing the queue interrupts the maneuver in flight
# (_interrupt_current_order). As of phase 3 the queue is also authoritative for the ROUTE:
# a queued waypoint leg IS a queued MOVE order (there is no parallel waypoint list), with
# move_target/has_move_target kept as the in-flight leg's execution state, and a line
# relief's swap state lives on the RELIEF order (Order.relief_partner). The in-flight
# targeting references (target_enemy / support_target) stay unit fields: the reactive
# layer (enemy AI, auto-engage) writes target_enemy directly with no order behind it, so
# they are execution state the queue reads -- _update_current_order retires
# ATTACK/RELIEF/SUPPORT orders by reading them.
var orders: Array[Order] = []
var current_order: Order = null
# Order stance, set by Battle._apply_order_cmd from the order's mode.
# Int rather than Battle.OrderMode to keep Unit decoupled; 0 == OrderMode.NORMAL.
# The smart-order behaviours read this; NORMAL is current behaviour.
var order_mode: int = 0
var formation_mode: int = FORMATION_NORMAL
