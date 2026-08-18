class_name UnitMorale
## Per-tick regiment condition updates for a Unit, extracted from Unit.gd: fatigue
## build-up/recovery (and the attack penalty it drives), the post-merge cohesion ramp, and
## morale recovery/erosion. Static helpers on the unit, driven by the fixed-step delta and combat
## state only -- no RNG, no wall-clock -- so they reproduce on replay. Called once per tick
## from Unit's _physics_process; the line-relief and merge logic live elsewhere on Unit.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")

enum Ladder { ROUTING, WAVERING, SHAKEN, FIRM, HIGH, IMPETUOUS, BERSERK }

const LADDER_NAMES := {
	Ladder.ROUTING: "routing",
	Ladder.WAVERING: "wavering",
	Ladder.SHAKEN: "shaken",
	Ladder.FIRM: "firm",
	Ladder.HIGH: "high",
	Ladder.IMPETUOUS: "impetuous",
	Ladder.BERSERK: "berserk",
}

# Morale ladder band boundaries
const THRESHOLD_WAVERING: float = 25.0
const THRESHOLD_SHAKEN: float = 50.0
const THRESHOLD_FIRM: float = 75.0
const THRESHOLD_HIGH: float = 90.0
const THRESHOLD_IMPETUOUS: float = 98.0

# 6m radius (120 WU) fits inside SpatialHash.CELL_SIZE (128 WU) so candidate queries stay complete
const LOCAL_FORCE_RADIUS_SQ: float = (6.0 * WorldScaleRef.WU_PER_M) * (6.0 * WorldScaleRef.WU_PER_M)
const UNOPPOSED_LOCAL_FORCE_RATIO: float = 2.0
const OUTNUMBERED_MORALE_EROSION_PER_SEC: float = 2.0
const UNDER_FIRE_MORALE_EROSION_PER_SEC: float = 1.5
const LOCAL_SUPERIORITY_MORALE_BOOST_PER_SEC: float = 1.0

enum CombatStatus { NOT_IN_COMBAT, WINNING_DECISIVELY, WINNING, BALANCED, LOSING, LOSING_DECISIVELY }

const COMBAT_STATUS_NAMES := {
	CombatStatus.NOT_IN_COMBAT: "not_in_combat",
	CombatStatus.WINNING_DECISIVELY: "winning_decisively",
	CombatStatus.WINNING: "winning",
	CombatStatus.BALANCED: "balanced",
	CombatStatus.LOSING: "losing",
	CombatStatus.LOSING_DECISIVELY: "losing_decisively",
}

# Local combat balance thresholds (ratio of friendly force / engaged enemy force)
const COMBAT_BALANCE_WINNING_DECISIVELY: float = 2.0
const COMBAT_BALANCE_WINNING: float = 1.25
const COMBAT_BALANCE_BALANCED: float = 0.8
const COMBAT_BALANCE_LOSING: float = 0.5

const LOSING_COMBAT_MORALE_EROSION_PER_SEC: float = 1.0
const LOSING_DECISIVELY_COMBAT_MORALE_EROSION_PER_SEC: float = 2.5


## Classifies a morale scalar (and routing state) into one of the 7 rungs of the morale ladder.
static func classify(morale: float, is_routing: bool = false) -> Ladder:
	if is_routing or morale <= 0.0:
		return Ladder.ROUTING
	elif morale <= THRESHOLD_WAVERING:
		return Ladder.WAVERING
	elif morale <= THRESHOLD_SHAKEN:
		return Ladder.SHAKEN
	elif morale <= THRESHOLD_FIRM:
		return Ladder.FIRM
	elif morale <= THRESHOLD_HIGH:
		return Ladder.HIGH
	elif morale <= THRESHOLD_IMPETUOUS:
		return Ladder.IMPETUOUS
	else:
		return Ladder.BERSERK


## Returns the human-readable string name for the current morale rung.
static func ladder_name(morale: float, is_routing: bool = false) -> String:
	return LADDER_NAMES[classify(morale, is_routing)]


## Derives a unit's local combat status from its melee engagement state, engaged enemy strength, and force ratio.
static func classify_combat_status(u: Unit, local_force_ratio: float = 1.0) -> CombatStatus:
	var engaged_enemies: Array = []
	if u.has_method("_adjacent_engaged_enemy_units"):
		engaged_enemies = u._adjacent_engaged_enemy_units()
	elif "_engaged_units" in u:
		engaged_enemies = u._engaged_units

	if (u.state != Unit.State.FIGHTING and not (u.has_method("is_engaged") and u.is_engaged())) or engaged_enemies.is_empty():
		return CombatStatus.NOT_IN_COMBAT

	var engaged_friendly: int = u.soldiers
	var engaged_enemy: int = 0
	for enemy in engaged_enemies:
		if enemy != null and "soldiers" in enemy and "state" in enemy:
			if enemy.state != Unit.State.DEAD and enemy.state != Unit.State.ROUTING:
				engaged_enemy += enemy.soldiers

	if engaged_enemy <= 0:
		return CombatStatus.WINNING_DECISIVELY

	var engaged_ratio: float = float(engaged_friendly) / float(engaged_enemy)
	var balance: float = engaged_ratio * local_force_ratio

	if balance >= COMBAT_BALANCE_WINNING_DECISIVELY:
		return CombatStatus.WINNING_DECISIVELY
	elif balance >= COMBAT_BALANCE_WINNING:
		return CombatStatus.WINNING
	elif balance >= COMBAT_BALANCE_BALANCED:
		return CombatStatus.BALANCED
	elif balance >= COMBAT_BALANCE_LOSING:
		return CombatStatus.LOSING
	else:
		return CombatStatus.LOSING_DECISIVELY


## Returns the human-readable string name for the current combat status.
static func combat_status_name(u: Unit, local_force_ratio: float = 1.0) -> String:
	return COMBAT_STATUS_NAMES[classify_combat_status(u, local_force_ratio)]


## Fatigue builds while fighting and recovers while resting. Well-trained melee units
## cycle their ranks, reducing effective buildup by up to RANK_CYCLE_FATIGUE_REDUCTION.
## The rotation is the intra-unit rank-relief mode (Unit.rank_relief, on by default,
## written by a stance order): with it off, even a veteran unit tires at the full rate.
static func tick_fatigue(u: Unit, delta: float) -> void:
	if u.state == Unit.State.FIGHTING:
		var cycles: bool = not u.is_ranged and u.rank_relief
		var cycle_reduction := u.training * Unit.RANK_CYCLE_FATIGUE_REDUCTION if cycles else 0.0
		# Wedge charge's tradeoff: the charge that punches through the line also wears the
		# men down faster (Unit.WEDGE_CHARGE_FATIGUE_MULT), on top of whatever rank-cycling
		# reduction the unit already earns.
		var wedge_mult: float = Unit.WEDGE_CHARGE_FATIGUE_MULT if u.order_mode == Unit.ORDER_WEDGE_CHARGE else 1.0
		u.fatigue = minf(100.0,
			u.fatigue + Unit.FATIGUE_PER_SEC * wedge_mult * (1.0 - cycle_reduction) * delta)
	else:
		u.fatigue = maxf(0.0, u.fatigue - Unit.FATIGUE_RECOVER_PER_SEC * delta)


## Attack multiplier from fatigue: 1.0 fresh, down to (1 - max penalty) spent.
static func fatigue_attack_factor(u: Unit) -> float:
	return 1.0 - Unit.FATIGUE_MAX_ATTACK_PENALTY * (u.fatigue / 100.0)


## The "strangers" cohesion debuff from a merge ramps back to full over time.
static func tick_cohesion(u: Unit, delta: float) -> void:
	if u.cohesion < 1.0:
		u.cohesion = minf(1.0, u.cohesion + Unit.COHESION_RECOVER_PER_SEC * delta)


## Morale recovers when resting; well-trained melee units also sustain it while fighting
## via visible rank rotation keeping the formation steady -- the same intra-unit
## rank-relief mode as the fatigue reduction above (Unit.rank_relief).
## Local force-ratio inputs (nearby friendly vs enemy soldier counts) and incoming fire
## adjust morale decay / stability each tick.
static func tick_morale(u: Unit, delta: float) -> void:
	# Query local neighborhood for force-ratio inputs
	var nearby_friendly_soldiers: int = u.soldiers
	var nearby_enemy_soldiers: int = 0
	if u.is_inside_tree():
		var candidates: Array = u._separation_candidates()
		var radius_sq := LOCAL_FORCE_RADIUS_SQ
		for candidate in candidates:
			if candidate == null or candidate == u:
				continue
			if "soldiers" in candidate and "team" in candidate and "state" in candidate:
				if candidate.state == Unit.State.DEAD or candidate.state == Unit.State.ROUTING:
					continue
				if u.position.distance_squared_to(candidate.position) <= radius_sq:
					if candidate.team == u.team:
						nearby_friendly_soldiers += candidate.soldiers
					else:
						nearby_enemy_soldiers += candidate.soldiers

	var local_force_ratio: float = 1.0
	if nearby_enemy_soldiers > 0:
		local_force_ratio = float(nearby_friendly_soldiers) / float(nearby_enemy_soldiers)
	elif nearby_friendly_soldiers > u.soldiers:
		local_force_ratio = UNOPPOSED_LOCAL_FORCE_RATIO

	# Local force ratio adjustments:
	if local_force_ratio < 1.0:
		var erosion := OUTNUMBERED_MORALE_EROSION_PER_SEC * (1.0 - local_force_ratio) * delta
		u.morale = maxf(0.0, u.morale - erosion)
	elif local_force_ratio >= 1.5 and u.morale < 100.0 and u.state != Unit.State.FIGHTING:
		var boost := LOCAL_SUPERIORITY_MORALE_BOOST_PER_SEC * delta
		u.morale = minf(100.0, u.morale + boost)

	# Local combat status erosion:
	var combat_status := classify_combat_status(u, local_force_ratio)
	if combat_status == CombatStatus.LOSING:
		u.morale = maxf(0.0, u.morale - LOSING_COMBAT_MORALE_EROSION_PER_SEC * delta)
	elif combat_status == CombatStatus.LOSING_DECISIVELY:
		u.morale = maxf(0.0, u.morale - LOSING_DECISIVELY_COMBAT_MORALE_EROSION_PER_SEC * delta)

	# Incoming fire erosion:
	if u._under_fire:
		var fire_erosion := UNDER_FIRE_MORALE_EROSION_PER_SEC * delta
		u.morale = maxf(0.0, u.morale - fire_erosion)

	# Resting recovery / rank-cycle in-fight recovery:
	if u.state != Unit.State.FIGHTING and u.morale < 100.0 and local_force_ratio >= 1.0 and not u._under_fire:
		u.morale = minf(100.0, u.morale + Unit.MORALE_RECOVER_PER_SEC * delta)
	elif u.state == Unit.State.FIGHTING and not u.is_ranged and u.rank_relief \
			and u.training >= Unit.RANK_CYCLE_MORALE_THRESHOLD and u.morale < 100.0:
		var strength_ratio: float = float(u.soldiers) / float(u.max_soldiers) if u.max_soldiers > 0 else 0.0
		if strength_ratio >= Unit.MORALE_CRUMBLE_RATIO_THRESHOLD:
			var recovery := Unit.RANK_CYCLE_MORALE_PER_SEC \
					* ((u.training - Unit.RANK_CYCLE_MORALE_THRESHOLD) / (1.0 - Unit.RANK_CYCLE_MORALE_THRESHOLD)) \
					* strength_ratio \
					* delta
			u.morale = minf(100.0, u.morale + recovery)
