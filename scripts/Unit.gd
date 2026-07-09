extends Node2D
class_name Unit
## A regiment: one selectable token with a soldier count and morale.
## Renders itself via _draw() with per-type sprite shapes: infantry kite
## shield, spearmen hoplon + spear, cavalry horse + rider.
## Its soldier marks are flat geometric shapes when zoomed out and swap to
## detailed figure silhouettes (a standing soldier, a mounted rider) when the
## camera zooms in past LOD_ZOOM_IN — see _update_lod / UnitMeshes.figure_mesh.

enum State { IDLE, MOVING, FIGHTING, ROUTING, DEAD }

var uid: int = -1

@export var unit_name: String = "Spearmen"
@export var team: int = 0
@export var max_soldiers: int = 120
@export var attack: int = 12
@export var defense: int = 6
@export var move_speed: float = 90.0
@export var walk_speed: float = 45.0
@export var jog_speed: float = 67.5
@export var back_speed_fraction: float = 0.5
@export var accel: float = 30.0
@export var decel: float = 60.0
@export var attack_range: float = 26.0
var weapon_type_id: int = LoadoutRegistry.WEAPON_GLADIUS
var shield_type_id: int = LoadoutRegistry.SHIELD_SCUTUM
@export var is_cavalry: bool = false
@export var anti_cavalry: bool = false
@export var is_ranged: bool = false
@export var order_response_delay: float = 0.5
@export var training: float = 0.0:
	set(v):
		training = clampf(v, 0.0, 1.0)

var soldiers: int
var morale: float = 100.0
var fatigue: float = 0.0
var cohesion: float = 1.0
var state: int = State.IDLE
var facing: Vector2 = Vector2.DOWN
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
var target_enemy: Unit = null
var selected: bool = false
var orders: Array[Order] = []
var current_order: Order = null
var order_mode: int = 0
var formation_mode: int = FORMATION_NORMAL
var rank_relief: bool = true
enum EngageReshapeMode { KEEP_NEW_FRONTING, RECREATE_WIDTH, MATCH_TARGET }
var engage_reshape_mode: int = EngageReshapeMode.KEEP_NEW_FRONTING
var tier: int = FormationTier.CLOSE
var frontage_override: int = 0
var frontage_anchor_offset: float = 0.0
var _ranks_closed: bool = false
var _formation_angle: float = 0.0
var _formation_mirror_x: bool = false
var deploy_facing: Vector2 = Vector2.ZERO
var ordered_facing: Vector2 = Vector2.ZERO
const ORDER_HOLD := 1
const ORDER_ATTACK_FLANK := 2
const ORDER_ATTACK_REAR := 3
const ORDER_SKIRMISH := 4
const ORDER_SUPPORT := 5
const ORDER_CYCLE_CHARGE := 6

const FORMATION_NORMAL := 0
const FORMATION_TIGHT := 1
const FORMATION_LOOSE := 2
const FORMATION_SQUARE := 3
const FORMATION_SHIELD_WALL := 4
const FORMATION_TESTUDO := 5
const FORMATION_SCHILTRON := 6
const TIGHT_MISSILE_DEFENSE: float = 0.25
const TIGHT_CHARGE_ABSORPTION: float = 0.55
const SHIELD_WALL_MISSILE_DEFENSE: float = 0.55
const SHIELD_WALL_MELEE_DEFENSE: float = 0.35
const TESTUDO_MISSILE_DEFENSE: float = 0.7
const TESTUDO_MELEE_PENALTY: float = 0.5
const SHIELD_WALL_SPEED_SCALE: float = 0.4
const TESTUDO_SPEED_SCALE: float = 0.3
const TIGHT_SEPARATION_SCALE: float = 0.75
const LOOSE_SEPARATION_SCALE: float = 1.35
const SQUARE_CHARGE_BACKFIRE: float = 0.5
const SQUARE_CHARGE_FLOOR: float = 0.6
const SQUARE_MOVE_FACTOR: float = 0.4
const SQUARE_ATTACK_FACTOR: float = 0.7
const ORBIS_MORALE_EROSION_RESIST: float = 0.7
const SCHILTRON_CHARGE_BACKFIRE: float = 0.75
const SCHILTRON_CHARGE_FLOOR: float = 0.45
const SCHILTRON_ATTACK_FACTOR: float = 0.55
const LOOSE_SPACING_SCALE: float = 2.0
const SHIELD_WALL_SPACING_SCALE: float = 0.75
const TESTUDO_SPACING_SCALE: float = 0.6
const MELEE_INTERMIX_RATE: float = 0.07
const MELEE_INTERMIX_DECAY_RATE: float = 0.28
const MELEE_INTERMIX_MAX: float = 0.85
const SPRINT_START_DISTANCE: float = 200.0
const ARRIVE_SPEED_EPSILON: float = 1.0
const ARRIVAL_ENVELOPE_MARGIN: float = 0.8
const TURN_RATE: float = PI
const TURN_RATE_TAPER_FLOOR: float = 0.4
const CONVERSIO_TURN_RATE: float = PI * 2.0
const WHEEL_TURN_RATE: float = PI * 0.5

const MELEE_PRESS_FRACTION: float = 0.6
const SKIRMISH_KITE_DISTANCE: float = 100.0
const CYCLE_CHARGE_STANDOFF: float = 280.0
const SUPPORT_GUARD_RADIUS: float = 180.0
const SUPPORT_FOLLOW_DISTANCE: float = 80.0
var walk_advance: bool = false
var _under_fire: bool = false

var support_target: Unit = null
var field_bounds: Rect2 = Rect2(-100000, -100000, 200000, 200000)
var retreat_bounds: Rect2 = Rect2(-100000, -100000, 200000, 200000)

const RADIUS: float = 18.0
const DETECTION_RANGE: float = 190.0
const ATTACK_INTERVAL: float = 0.6
const ROUT_TIME: float = 6.0
const REFORM_DURATION: float = 0.8
const REFORM_SETTLE_EPS: float = 1.0
const ROUT_SHOCK_RADIUS: float = 140.0
const RALLY_CONTACT_RADIUS: float = 160.0
const RALLY_MORALE: float = 30.0
const SHATTER_STRENGTH_FRAC: float = 0.15
const ROUT_RALLY_BASELINE: float = 45.0
const ROUT_MORALE_RECOVER_RATE: float = 0.25
const RALLY_MORALE_THRESHOLD: float = 35.0

const RANGED_RANGE: float = 160.0
const RANGED_INTERVAL: float = 1.0
const RANGED_DAMAGE_FACTOR: float = 0.7

const FATIGUE_PER_SEC: float = 0.7
const FATIGUE_RECOVER_PER_SEC: float = 0.5
const FATIGUE_MAX_ATTACK_PENALTY: float = 0.4
const RANK_CYCLE_FATIGUE_REDUCTION: float = 0.5
const RANK_CYCLE_MORALE_THRESHOLD: float = 0.5
const RANK_CYCLE_MORALE_PER_SEC: float = 1.2
const MORALE_CRUMBLE_RATIO_THRESHOLD: float = 0.4
const MORALE_LOSS_PER_FULL_LOSS: float = 90.0
const MORALE_CRUMBLE_BOOST: float = 4.0

const MORALE_RECOVER_PER_SEC: float = 2.0

const MERGE_COHESION_FLOOR: float = 0.6
const COHESION_RECOVER_PER_SEC: float = 0.1

const SEPARATION_RADIUS_INFANTRY: float = 18.0
const SEPARATION_RADIUS_SPEARMEN: float = 20.0
const SEPARATION_RADIUS_CAVALRY: float = 24.0
const SEPARATION_RADIUS_MAX: float = 28.0

const CHARGE_BONUS_AT_REF_SPEED: float = 0.8
const CHARGE_REFERENCE_SPEED: float = 170.0
const ANTI_CAV_CHARGE_BACKFIRE: float = 0.5
const ANTI_CAV_CHARGE_FLOOR: float = 0.6

var _attack_cd: float = 0.0
var _rout_timer: float = 0.0
var _shattered: bool = false
var _order_response_timer: float = 0.0
var _reform_target: Vector2 = Vector2.ZERO
var _reform_timer: float = 0.0
var _moved_last_frame: bool = false
var _approach_velocity: Vector2 = Vector2.ZERO
var _current_speed: float = 0.0
var current_speed: float:
	get: return _current_speed
var _body_follow_vel: Vector2 = Vector2.ZERO
var _cycle_recharging: bool = false
var team_color: Color = Color.WHITE
var separation_radius: float = SEPARATION_RADIUS_INFANTRY
var _base_separation_radius: float = SEPARATION_RADIUS_INFANTRY
var spacing_scale: float = 1.0
var _combat_intermixing: float = 0.0

var _flock_color: Color = Color(0, 0, 0, 0)
var _block_extent: float = RADIUS
var _render_dirty: bool = true
var _render_last_facing: Vector2 = Vector2.DOWN
var _render_extent_n: int = -1
var _render_extent_frontage: int = -1
var _render_extent_mode: int = -1
var _mm_body: MultiMesh = null
var _mm_outline: MultiMesh = null
var _mmi_body: MultiMeshInstance2D = null
var _mmi_outline: MultiMeshInstance2D = null
var _mm_facing_pip: MultiMesh = null
var _mmi_facing_pip: MultiMeshInstance2D = null
var _facing_pip_mesh: ArrayMesh = null
var _shadow: Polygon2D = null
var _mark_body_mesh: ArrayMesh = null
var _mark_outline_mesh: ArrayMesh = null
var _figure_body_mesh: ArrayMesh = null
var _figure_outline_mesh: ArrayMesh = null
var _figure_body_mesh_flip: ArrayMesh = null
var _figure_outline_mesh_flip: ArrayMesh = null
var _detailed_lod: bool = false
var _figure_faces_left: bool = false
