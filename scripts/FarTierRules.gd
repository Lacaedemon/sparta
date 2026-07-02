class_name FarTierRules
extends RefCounted
## Statistical evolution rules for far-tier formations (docs/large-scale-simulation-design.md,
## phase 2). Every function is static, deterministic, and RNG-free: the rules consume and
## produce only FarTierFormation's aggregate fields — never a per-soldier array — so a
## far-tier fight costs O(formations) per tick and replays identically without drawing from
## the seeded Replay.rng stream.
##
## The rules mirror the close tier's own regiment-level combat path IN EXPECTATION. Where
## UnitCombat.strike draws a seeded roll in [0.6, 1.4] per strike, the far tier applies the
## roll's mean (1.0) as a continuous casualty rate; morale bookkeeping follows
## UnitCombat.register_casualties' formula exactly. Two simplifications, both formation-level
## abstractions rather than lost soldier detail:
## - Fatigue, cohesion, and training read as fresh/untrained defaults — the far-tier
##   record carries none of them (so there is no rank-cycle in-fight morale recovery).
## - Every engagement resolves as sustained melee contact; ranged volley pacing is a
##   refinement the far tier doesn't model yet.
## The attacker's output also scales with its remaining-strength ratio (a thinned formation
## presents less fighting frontage), which is where the model earns its Lanchester-style
## attrition curves: the close tier's live per-soldier melee scales output with living
## fighters the same way, so the ratio keeps the aggregate broadly consistent with it.


## Remaining-strength ratio in [0, 1]: the aggregate analog of soldiers / max_soldiers.
static func strength_ratio(rec: FarTierFormation) -> float:
	if rec.max_soldiers <= 0:
		return 0.0
	return clampf(float(rec.count) / float(rec.max_soldiers), 0.0, 1.0)


## Every soldier lost. The far-tier analog of Unit's soldiers <= 0 death check.
static func is_destroyed(rec: FarTierFormation) -> bool:
	return rec.count <= 0


## Morale spent. The far-tier analog of the close tier's rout trigger (morale <= 0). Broken
## is absorbing at this tier for now — no rally, no pursuit — matching how the close tier's
## take_casualties path also stops applying attrition to a ROUTING unit.
static func is_broken(rec: FarTierFormation) -> bool:
	return rec.morale <= 0.0


static func can_fight(rec: FarTierFormation) -> bool:
	return not is_destroyed(rec) and not is_broken(rec)


## Offensive-output scale from the stance — mirrors Unit.formation_attack_factor: the
## anti-cav square hunkers to defend all around and hits softer.
static func formation_attack_factor(rec: FarTierFormation) -> float:
	return Unit.SQUARE_ATTACK_FACTOR if rec.formation_mode == Unit.FORMATION_SQUARE else 1.0


## Melee-output scale from the stance — mirrors Unit.formation_melee_attack_factor: a
## testudo fights head-down under overhead cover and hits softest.
static func formation_melee_attack_factor(rec: FarTierFormation) -> float:
	return 1.0 - Unit.TESTUDO_MELEE_PENALTY if rec.formation_mode == Unit.FORMATION_TESTUDO else 1.0


## Cap on the formation's top pace — mirrors Unit.formation_speed_factor: the planted
## close-order stances barely move.
static func formation_speed_factor(rec: FarTierFormation) -> float:
	match rec.formation_mode:
		Unit.FORMATION_SHIELD_WALL:
			return Unit.SHIELD_WALL_SPEED_SCALE
		Unit.FORMATION_TESTUDO:
			return Unit.TESTUDO_SPEED_SCALE
		Unit.FORMATION_SQUARE:
			return Unit.SQUARE_MOVE_FACTOR
		_:
			return 1.0


## Whether a blow from `attacker_pos` lands on the defender's frontal arc — mirrors
## Unit._is_frontal_attack (the full forward hemisphere).
static func is_frontal(defender: FarTierFormation, attacker_pos: Vector2) -> bool:
	var to_attacker: Vector2 = attacker_pos - defender.position
	if to_attacker.length() < 0.001:
		return true
	return defender.facing.dot(to_attacker.normalized()) > 0.0


## Incoming-melee damage scale from the defender's stance — mirrors
## Unit.melee_defense_factor: a braced shield wall blunts a frontal assault; flank and
## rear blows land full.
static func melee_defense_factor(defender: FarTierFormation, attacker_pos: Vector2) -> float:
	if defender.formation_mode == Unit.FORMATION_SHIELD_WALL and is_frontal(defender, attacker_pos):
		return 1.0 - Unit.SHIELD_WALL_MELEE_DEFENSE
	return 1.0


## 1.0 frontal, 1.5 flank, 2.0 rear, relative to the DEFENDER's facing — mirrors
## UnitCombat.flank_multiplier, including the square's all-around defence (no weak side).
static func flank_multiplier(defender: FarTierFormation, attacker_pos: Vector2) -> float:
	if defender.formation_mode == Unit.FORMATION_SQUARE:
		return 1.0
	var to_attacker: Vector2 = attacker_pos - defender.position
	if to_attacker.length() < 0.001:
		return 1.0
	var d: float = defender.facing.dot(to_attacker.normalized())
	if d >= 0.35:
		return 1.0
	elif d >= -0.5:
		return 1.5
	else:
		return 2.0


## Expected casualties from ONE close-tier regiment strike (UnitCombat.strike's formula
## path) with the damage roll at its mean: max(1, effective attack - defense), then the
## defender's stance blunting. Flanking and the attacker's thinning scale the rate, not
## the strike, so they live in casualty_rate below.
static func strike_expectation(attacker: FarTierFormation, defender: FarTierFormation) -> float:
	var eff_attack: float = float(attacker.attack) \
			* formation_attack_factor(attacker) * formation_melee_attack_factor(attacker)
	var base: float = maxf(1.0, eff_attack - float(defender.defense))
	return base * melee_defense_factor(defender, attacker.position)


## Expected casualties per second the attacker inflicts on the defender: one expected
## strike per ATTACK_INTERVAL, scaled by the defender's flank exposure and the attacker's
## remaining-strength ratio (the Lanchester-style thinning term).
static func casualty_rate(attacker: FarTierFormation, defender: FarTierFormation) -> float:
	return strike_expectation(attacker, defender) \
			* flank_multiplier(defender, attacker.position) \
			* strength_ratio(attacker) / Unit.ATTACK_INTERVAL


## Whether the attacker's centroid is close enough to strike — mirrors the close tier's
## contact check (attack_range + both unit radii), so a longer-reach formation opens up
## first, exactly like a spear line meeting a sword line.
static func in_striking_range(attacker: FarTierFormation, defender: FarTierFormation) -> bool:
	var reach: float = attacker.attack_range + Unit.RADIUS * 2.0
	return attacker.position.distance_to(defender.position) <= reach


## Apply `killed` whole casualties to the record: clamp to the living, book the losses,
## and erode morale by UnitCombat.register_casualties' exact formula — the
## fraction-of-force base erosion plus the crumble boost once the formation thins below
## the threshold ratio. Returns the casualties actually applied. Morale floors at zero
## (broken) rather than going negative, since the record has no rout state to hand off to.
static func apply_casualties(rec: FarTierFormation, killed: int) -> int:
	var applied: int = clampi(killed, 0, rec.count)
	if applied <= 0:
		return 0
	rec.count -= applied
	rec.casualties += applied
	if rec.max_soldiers > 0:
		var casualty_frac: float = float(applied) / float(rec.max_soldiers)
		var base_erosion: float = casualty_frac * Unit.MORALE_LOSS_PER_FULL_LOSS
		rec.morale -= base_erosion
		var ratio: float = strength_ratio(rec)
		if ratio < Unit.MORALE_CRUMBLE_RATIO_THRESHOLD:
			var crumble_depth: float = (Unit.MORALE_CRUMBLE_RATIO_THRESHOLD - ratio) \
					/ Unit.MORALE_CRUMBLE_RATIO_THRESHOLD
			rec.morale -= base_erosion * Unit.MORALE_CRUMBLE_BOOST * crumble_depth
	rec.morale = maxf(rec.morale, 0.0)
	return applied


## Advance the continuous casualty rate by one tick: accumulate the fractional expectation
## in the record's carry and apply whole soldiers as they complete, so the totals over any
## span match rate * time exactly regardless of tick size. Returns casualties applied.
static func tick_attrition(defender: FarTierFormation, rate: float, delta: float) -> int:
	defender.casualty_carry += rate * delta
	var whole: int = int(defender.casualty_carry)
	if whole <= 0:
		return 0
	defender.casualty_carry -= float(whole)
	return apply_casualties(defender, whole)


## Out-of-combat morale recovery — mirrors UnitMorale.tick_morale's resting branch. A
## broken formation does not recover (broken is absorbing at this tier; see is_broken).
static func tick_recovery(rec: FarTierFormation, delta: float) -> void:
	if not can_fight(rec) or rec.morale >= 100.0:
		return
	rec.morale = minf(100.0, rec.morale + Unit.MORALE_RECOVER_PER_SEC * delta)


## The formation's aggregate march pace: its sustained speed capped by the stance.
static func effective_speed(rec: FarTierFormation) -> float:
	return rec.march_speed * formation_speed_factor(rec)


## March the centroid straight toward `target` at the effective pace, clamped so it never
## oversteps the point in one tick; facing tracks the direction of travel. Terrain routing
## and the close tier's arrival braking are below this tier's resolution.
static func advance(rec: FarTierFormation, target: Vector2, delta: float) -> void:
	var to_target: Vector2 = target - rec.position
	var dist: float = to_target.length()
	if dist < 0.001:
		return
	var dir: Vector2 = to_target / dist
	var step: float = minf(effective_speed(rec) * delta, dist)
	rec.position += dir * step
	rec.facing = dir


## Turn the formation in place to face `point` (used on contact, where the line squares up
## against the enemy rather than marching past it).
static func face_toward(rec: FarTierFormation, point: Vector2) -> void:
	var to_point: Vector2 = point - rec.position
	if to_point.length() < 0.001:
		return
	rec.facing = to_point.normalized()


## One tick of the isolated two-formation engagement the phase verifies: two far-tier
## formations close on each other, exchange attrition once in reach, and stop when one
## breaks or is destroyed, with survivors recovering morale afterward. All reads happen
## against the PRE-tick state before any write, so the exchange is simultaneous — neither
## side gets a first-mover advantage, and a mirrored matchup stays exactly symmetric.
## Orchestrating many formations (target selection, pursuit) is later-phase work; this
## driver is the two-body rule the design doc's done-check runs.
static func tick_pair(a: FarTierFormation, b: FarTierFormation, delta: float) -> void:
	var a_fights: bool = can_fight(a)
	var b_fights: bool = can_fight(b)
	if not (a_fights and b_fights):
		# No live fight (one side gone or broken): survivors recover where they stand.
		if a_fights:
			tick_recovery(a, delta)
		if b_fights:
			tick_recovery(b, delta)
		return
	# Snapshot every input before mutating anything (simultaneity; see the docstring).
	var a_in_reach: bool = in_striking_range(a, b)
	var b_in_reach: bool = in_striking_range(b, a)
	var rate_on_b: float = casualty_rate(a, b) if a_in_reach else 0.0
	var rate_on_a: float = casualty_rate(b, a) if b_in_reach else 0.0
	var a_target: Vector2 = b.position
	var b_target: Vector2 = a.position
	# A side in reach squares up and fights; one out of reach presses into contact (so a
	# shorter-reach line closes the last stretch under a spear line's blows, as it does
	# in the close tier). An advancing side is MOVING rather than FIGHTING, so it also
	# recovers morale, mirroring UnitMorale.tick_morale's out-of-combat branch.
	if a_in_reach:
		face_toward(a, a_target)
	else:
		advance(a, a_target, delta)
		tick_recovery(a, delta)
	if b_in_reach:
		face_toward(b, b_target)
	else:
		advance(b, b_target, delta)
		tick_recovery(b, delta)
	if rate_on_b > 0.0:
		tick_attrition(b, rate_on_b, delta)
	if rate_on_a > 0.0:
		tick_attrition(a, rate_on_a, delta)
