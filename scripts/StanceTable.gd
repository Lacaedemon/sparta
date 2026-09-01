class_name StanceTable
extends RefCounted
## Central flags table and query API for OrderMode stances (Issue #956).
## Defines orthogonal behavioral flags for each stance (acquisition, response,
## movement, reflow, and leashing), eliminating ad-hoc enum branching across hot paths.

class StanceFlags extends RefCounted:
	var target_visible_enemies: bool = true
	var target_attackers_always: bool = true
	var respond_chase: bool = false
	var respond_stand_ground: bool = false
	var respond_hold_ground: bool = false
	var can_give_ground: bool = false
	var is_pushing: bool = false
	var flank_wrap: bool = false
	var multi_engage_reflow: bool = false
	var march_to_contact: bool = false
	var auto_advance: bool = true
	var allow_intermixing: bool = true
	var default_leash_radius: float = 0.0

	func _init(
		p_target_visible: bool = true,
		p_target_attackers: bool = true,
		p_chase: bool = false,
		p_stand_ground: bool = false,
		p_hold_ground: bool = false,
		p_give_ground: bool = false,
		p_push: bool = false,
		p_flank_wrap: bool = false,
		p_multi_engage: bool = false,
		p_march_to_contact: bool = false,
		p_auto_advance: bool = true,
		p_allow_intermix: bool = true,
		p_leash: float = 0.0
	) -> void:
		target_visible_enemies = p_target_visible
		target_attackers_always = p_target_attackers
		respond_chase = p_chase
		respond_stand_ground = p_stand_ground
		respond_hold_ground = p_hold_ground
		can_give_ground = p_give_ground
		is_pushing = p_push
		flank_wrap = p_flank_wrap
		multi_engage_reflow = p_multi_engage
		march_to_contact = p_march_to_contact
		auto_advance = p_auto_advance
		allow_intermixing = p_allow_intermix
		default_leash_radius = p_leash

static var _DEFAULT := StanceFlags.new()

static var _TABLE: Dictionary = {
	# NORMAL (0): standard aggressive stance, advances on near foes, allows intermix
	0: StanceFlags.new(true, true, false, false, false, false, false, false, false, false, true, true, 0.0),
	# HOLD (1): holds ground, no auto-advance, no intermixing, defends only in place
	1: StanceFlags.new(false, true, false, true, true, false, false, false, false, false, false, false, 0.0),
	# ATTACK_FLANK (2): biases approach to enemy flanks
	2: StanceFlags.new(true, true, false, false, false, false, false, false, false, false, true, true, 0.0),
	# ATTACK_REAR (3): biases approach to enemy rear
	3: StanceFlags.new(true, true, false, false, false, false, false, false, false, false, true, true, 0.0),
	# SKIRMISH (4): kites at missile range
	4: StanceFlags.new(true, true, false, false, false, false, false, false, false, false, true, true, 0.0),
	# SUPPORT (5): guards a friendly unit
	5: StanceFlags.new(true, true, false, false, false, false, false, false, false, false, true, true, 0.0),
	# CYCLE_CHARGE (6): charge, strike, withdraw, and recharge
	6: StanceFlags.new(true, true, false, false, false, false, false, false, false, false, true, true, 0.0),
	# SWEEP_ROUTERS (7): actively chases routing units
	7: StanceFlags.new(true, true, true, false, false, false, false, false, false, false, true, true, 0.0),
	# ROLL_THE_LINE (8): rolls along the enemy line
	8: StanceFlags.new(true, true, true, false, false, false, false, false, false, false, true, true, 0.0),
	# PIN_DOWN (9): fixes enemy unit in place within leash
	9: StanceFlags.new(true, true, false, true, false, false, false, false, false, false, false, true, 300.0),
	# ALL_OUT_ATTACK (10): aggressive attack, pursues relentlessly
	10: StanceFlags.new(true, true, true, false, false, false, false, false, false, false, true, true, 0.0),
	# CHASE (11): relentless pursuit of quarry
	11: StanceFlags.new(true, true, true, false, false, false, false, false, false, false, true, true, 0.0),
	# WEDGE_CHARGE (12): wedge formation charge
	12: StanceFlags.new(true, true, false, false, false, false, false, false, false, false, true, true, 0.0),
	# KNOCKBACK_FOCUS (13): focuses melee impulse
	13: StanceFlags.new(true, true, false, false, false, false, false, false, false, false, true, true, 0.0),
	# GIVE_GROUND (14): fighting retreat
	14: StanceFlags.new(true, true, false, false, false, true, false, false, false, false, false, true, 0.0),
	# PUSH (15): aggressive forward shove
	15: StanceFlags.new(true, true, false, false, false, false, true, false, false, false, true, true, 0.0),
	# MULTIPLE_ENGAGE (16): widens front when pressed by multiple foes
	16: StanceFlags.new(true, true, false, false, false, false, false, false, true, false, true, true, 0.0),
	# MARCH_TO_CONTACT (17): plain move that stops to fight in path, then resumes
	17: StanceFlags.new(true, true, false, false, false, false, false, false, false, true, false, true, 0.0),
	# BRACE (18): plant and hold against charge, receives full brace bonus
	18: StanceFlags.new(false, true, false, true, true, false, false, false, false, false, false, false, 0.0),
	# FLANKING_MANEUVER (19): wraps outer ranks around enemy flanks
	19: StanceFlags.new(true, true, false, false, false, false, false, true, false, false, true, true, 0.0),
}

static func get_flags(mode: int) -> StanceFlags:
	return _TABLE.get(mode, _DEFAULT)

static func can_auto_advance(mode: int) -> bool:
	return get_flags(mode).auto_advance

static func allows_intermixing(mode: int) -> bool:
	return get_flags(mode).allow_intermixing

static func can_acquire_visible(mode: int) -> bool:
	return get_flags(mode).target_visible_enemies

static func should_chase(mode: int) -> bool:
	return get_flags(mode).respond_chase

static func is_march_to_contact(mode: int) -> bool:
	return get_flags(mode).march_to_contact

static func is_giving_ground(mode: int) -> bool:
	return get_flags(mode).can_give_ground

static func is_pushing(mode: int) -> bool:
	return get_flags(mode).is_pushing

static func has_flank_wrap(mode: int) -> bool:
	return get_flags(mode).flank_wrap

static func has_multi_engage_reflow(mode: int) -> bool:
	return get_flags(mode).multi_engage_reflow

static func default_leash(mode: int) -> float:
	return get_flags(mode).default_leash_radius
