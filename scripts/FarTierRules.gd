class_name FarTierRules
extends RefCounted
## Statistical evolution rules for far-tier formations (docs/large-scale-simulation-design.md,
## phase 2). Every function is static, deterministic, and RNG-free: the rules consume and
## produce only FarTierFormation's aggregate fields — never a per-soldier array — so a
## far-tier fight costs O(formations) per tick and replays identically without drawing from
## the seeded Replay.rng stream.
##
## The rules mirror the close tier's own regiment-level combat path IN EXPECTATION. Where
## UnitCombat.strike/shoot draws a seeded roll in [0.6, 1.4] per strike, the far tier applies
## the roll's mean (1.0) as a continuous casualty rate; morale bookkeeping follows
## UnitCombat.register_casualties' formula exactly. A formation's is_ranged flag (mirroring
## Unit.is_ranged) splits the rate/reach rules the same way the close tier does: a ranged
## attacker strikes from RANGED_RANGE on the RANGED_INTERVAL/RANGED_DAMAGE_FACTOR cadence
## against the defender's missile_defense_factor, instead of melee's ATTACK_INTERVAL/
## attack_range against melee_defense_factor — see strike_expectation/casualty_rate/
## in_striking_range. Interception and real flight time (ProjectileField) stay below this
## tier's resolution: a far-tier volley lands its expected casualties the same tick, with no
## simulated arrow travel. Remaining simplifications, both formation-level abstractions
## rather than lost soldier detail:
## - Fatigue, cohesion, and training read as fresh/untrained defaults — the far-tier
##   record carries none of them (so there is no rank-cycle in-fight morale recovery).
## A MELEE attacker's output also scales with its remaining-strength ratio (a thinned
## formation presents less fighting frontage), which is where the model earns its
## Lanchester-style attrition curves: the close tier's live per-soldier melee scales output
## with living fighters the same way, so the ratio keeps the aggregate broadly consistent
## with it. A RANGED attacker is exempt from this thinning term: UnitCombat.shoot draws
## volley damage from the flat attack stat with no soldier-count scaling, so the far tier's
## ranged output stays flat too, to keep mirroring it faithfully.


## A routing formation's flee pace, relative to its (stance-capped) march speed — mirrors
## Unit._process_rout's move_speed * 1.3 flee rate. The close tier flees at its sprint pace
## (move_speed), which the far-tier record doesn't carry (bursts are below this tier's
## resolution; see the walk-only march_speed field), so this scales the walk-derived
## effective_speed instead — the same 1.3 multiplier applied to the far tier's only pace.
const FLEE_SPEED_MULTIPLIER: float = 1.3


## Remaining-strength ratio in [0, 1]: the aggregate analog of soldiers / max_soldiers.
static func strength_ratio(rec: FarTierFormation) -> float:
	if rec.max_soldiers <= 0:
		return 0.0
	return clampf(float(rec.count) / float(rec.max_soldiers), 0.0, 1.0)


## Every soldier lost. The far-tier analog of Unit's soldiers <= 0 death check.
static func is_destroyed(rec: FarTierFormation) -> bool:
	return rec.count <= 0


## Morale spent: the far-tier analog of the close tier's rout TRIGGER (morale <= 0). This is
## the instantaneous threshold check, not the persistent state — enter_rout latches the
## formation into rec.routing, which (like the close tier) can outlast the morale dip that
## caused it, since morale climbs back toward ROUT_RALLY_BASELINE while still routing.
static func is_broken(rec: FarTierFormation) -> bool:
	return rec.morale <= 0.0


## Fightable: alive, not broken, and not already routing. A routing formation takes no
## further formula attrition and deals none — mirroring the close tier's take_casualties
## guard on a ROUTING unit — until it rallies (tick_rout) back into can_fight.
static func can_fight(rec: FarTierFormation) -> bool:
	return not is_destroyed(rec) and not is_broken(rec) and not rec.routing


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


## Incoming-RANGED damage scale from the defender's stance — mirrors Unit.missile_defense_factor:
## TIGHT/TESTUDO raise shields against volleys from any direction; SHIELD_WALL's locked wall
## only covers the front (a flank/rear volley bypasses it and lands full); SQUARE gets no
## missile bonus (its all-around shields face a charge, not plunging arrows).
static func missile_defense_factor(defender: FarTierFormation, attacker_pos: Vector2) -> float:
	match defender.formation_mode:
		Unit.FORMATION_TIGHT:
			return 1.0 - Unit.TIGHT_MISSILE_DEFENSE
		Unit.FORMATION_TESTUDO:
			return 1.0 - Unit.TESTUDO_MISSILE_DEFENSE
		Unit.FORMATION_SHIELD_WALL:
			if is_frontal(defender, attacker_pos):
				return 1.0 - Unit.SHIELD_WALL_MISSILE_DEFENSE
			return 1.0
		_:
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
## the strike, so they live in casualty_rate below. A ranged attacker mirrors
## UnitCombat.shoot instead: no melee-stance offence penalty (a testudo still looses
## volleys head-up), RANGED_DAMAGE_FACTOR applied, and the defender's stance blunts it via
## missile_defense_factor rather than melee_defense_factor.
static func strike_expectation(attacker: FarTierFormation, defender: FarTierFormation) -> float:
	if attacker.is_ranged:
		var eff_ranged: float = float(attacker.attack) * formation_attack_factor(attacker)
		var ranged_base: float = maxf(1.0, eff_ranged - float(defender.defense)) * Unit.RANGED_DAMAGE_FACTOR
		return ranged_base * missile_defense_factor(defender, attacker.position)
	var eff_attack: float = float(attacker.attack) \
			* formation_attack_factor(attacker) * formation_melee_attack_factor(attacker)
	var base: float = maxf(1.0, eff_attack - float(defender.defense))
	return base * melee_defense_factor(defender, attacker.position)


## Expected casualties per second the attacker inflicts on the defender: one expected
## strike per ATTACK_INTERVAL (or, for a ranged attacker, one expected volley per
## RANGED_INTERVAL), scaled by the defender's flank exposure. A melee attacker's output is
## also scaled by its remaining-strength ratio (the Lanchester-style thinning term) — mirroring
## the close tier's per-soldier melee, which naturally loses output as fighters fall. A ranged
## attacker is NOT thinned this way: UnitCombat.shoot draws volley damage from the flat
## attack stat with no soldier-count scaling, so a 10-man archer regiment volleys exactly as
## hard as a 140-man one, and the far tier must match that to stay a faithful mirror.
static func casualty_rate(attacker: FarTierFormation, defender: FarTierFormation) -> float:
	var interval: float = Unit.RANGED_INTERVAL if attacker.is_ranged else Unit.ATTACK_INTERVAL
	var thinning: float = 1.0 if attacker.is_ranged else strength_ratio(attacker)
	return strike_expectation(attacker, defender) \
			* flank_multiplier(defender, attacker.position) \
			* thinning / interval


## Whether the attacker's centroid is close enough to strike — mirrors the close tier's
## contact check for a melee attacker (attack_range + both unit radii), so a longer-reach
## formation opens up first, exactly like a spear line meeting a sword line. A ranged
## attacker instead uses RANGED_RANGE, matching the close tier's archer, which looses
## volleys from well beyond melee contact rather than closing to reach.
static func in_striking_range(attacker: FarTierFormation, defender: FarTierFormation) -> bool:
	var reach: float = Unit.RANGED_RANGE if attacker.is_ranged \
			else attacker.attack_range + Unit.RADIUS * 2.0
	return attacker.position.distance_to(defender.position) <= reach


## Apply `killed` whole casualties to the record: clamp to the living, book the losses,
## and erode morale by UnitCombat.register_casualties' exact formula — the
## fraction-of-force base erosion plus the crumble boost once the formation thins below
## the threshold ratio. Returns the casualties actually applied. Morale floors at zero.
## Mirrors register_casualties' own trigger order exactly: wipe-out takes priority (a
## formation whose count just hit zero is destroyed, not routing — is_destroyed already
## covers it, so enter_rout is skipped), otherwise a fresh break into zero morale latches
## rout THIS call, same tick as the casualties that caused it.
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
	if not is_destroyed(rec) and is_broken(rec):
		enter_rout(rec)
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


## Break into rout: the aggregate analog of Unit._rout(). Latches rec.routing and arms the
## timer at ROUT_TIME. A no-op if already routing, matching Unit._rout()'s own re-entrancy
## guard. Contagion (morale-shaking nearby friendlies, ROUT_SHOCK_RADIUS) is orchestration
## across many formations — out of this pair-scoped rule's reach; see tick_shock below for
## the isolated two-body analog this phase actually implements.
static func enter_rout(rec: FarTierFormation) -> void:
	if rec.routing:
		return
	rec.routing = true
	rec.rout_timer = Unit.ROUT_TIME


## Whether a routing formation recovers rather than shatters: the far-tier analog of
## Unit._can_rally(). It must still field enough men to reform (>= SHATTER_STRENGTH_FRAC of
## max_soldiers) and have broken contact with `enemy` — no live enemy within
## RALLY_CONTACT_RADIUS. The close tier scans every enemy on the field; the far tier's pair
## model has only the one opposing formation to check, the natural two-body analog.
static func can_rally(rec: FarTierFormation, enemy: FarTierFormation) -> bool:
	if rec.count < int(round(float(rec.max_soldiers) * Unit.SHATTER_STRENGTH_FRAC)):
		return false
	if is_destroyed(enemy):
		return true
	return rec.position.distance_to(enemy.position) > Unit.RALLY_CONTACT_RADIUS


## Recover from a rout: the far-tier analog of Unit._rally(). Clears the routing flag and
## floors morale at RALLY_MORALE (never lower — a rallied formation reforms shaken but
## fightable), so it re-enters can_fight from here.
static func rally(rec: FarTierFormation) -> void:
	rec.routing = false
	rec.morale = maxf(rec.morale, Unit.RALLY_MORALE)
	rec.rout_timer = 0.0


## Shatter: a routed formation that couldn't escape, or was gutted past recovery, leaves
## play for good — the far-tier analog of Unit._shatter(). count = 0 is already
## is_destroyed's own definition of gone, so shattering just empties the roster; the
## casualties ledger absorbs whoever was still standing, matching how a close-tier shatter
## removes the unit (soldiers implicitly to zero) rather than killing them one at a time.
static func shatter(rec: FarTierFormation) -> void:
	rec.casualties += rec.count
	rec.count = 0
	rec.routing = false
	rec.rout_timer = 0.0


## One tick of a routing formation's flight: the far-tier analog of Unit._process_rout().
## Flees straight away from `enemy` (the pair's own opposing formation — the far tier has no
## fixed "own back edge" to run toward, so fleeing the immediate threat is the natural
## two-body substitute) at 1.3x the march pace, matching the close tier's flee multiplier.
## Morale steadies toward ROUT_RALLY_BASELINE at a rate proportional to the remaining gap,
## and the formation rallies the moment it crosses RALLY_MORALE_THRESHOLD with contact
## broken — it need not run out the timer. Otherwise, when the timer expires, it rallies if
## it still can (can_rally) or shatters. No-op if the formation isn't routing.
static func tick_rout(rec: FarTierFormation, enemy: FarTierFormation, delta: float) -> void:
	if not rec.routing:
		return
	var away: Vector2 = rec.position - enemy.position
	if away.length() >= 0.001:
		rec.facing = away.normalized()
		rec.position += rec.facing * (effective_speed(rec) * FLEE_SPEED_MULTIPLIER) * delta
	if rec.morale < Unit.ROUT_RALLY_BASELINE:
		rec.morale += (Unit.ROUT_RALLY_BASELINE - rec.morale) * Unit.ROUT_MORALE_RECOVER_RATE * delta
	if rec.morale >= Unit.RALLY_MORALE_THRESHOLD and can_rally(rec, enemy):
		rally(rec)
		return
	rec.rout_timer -= delta
	if rec.rout_timer > 0.0:
		return
	if can_rally(rec, enemy):
		rally(rec)
	else:
		shatter(rec)


## Out-of-combat morale recovery — mirrors UnitMorale.tick_morale's resting branch. Gated by
## can_fight, so neither a broken-but-not-yet-routing formation nor an already-routing one
## uses this path: routing recovery follows its own curve toward ROUT_RALLY_BASELINE
## (tick_rout), not the ordinary resting rate up to 100.
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
## formations close on each other, exchange attrition once in reach, and a side
## that breaks flees, rallies, or shatters instead of just absorbing (the old phase-2
## behavior). All reads happen against the PRE-tick state before any write, so the exchange
## is simultaneous — neither side gets a first-mover advantage, and a mirrored matchup stays
## exactly symmetric. Orchestrating many formations (target selection, pursuit across more
## than a pair, contagion) is later-phase work; this driver is the two-body rule the design
## doc's done-checks run.
static func tick_pair(a: FarTierFormation, b: FarTierFormation, delta: float) -> void:
	# A side that broke on a PRIOR tick's attrition is already routing here: apply_casualties
	# latches enter_rout the instant morale hits zero (same tick as the casualties that
	# caused it, mirroring register_casualties' own u._rout() call), so by the time this
	# function runs for the next tick, rec.routing already reflects it.
	var a_fights: bool = can_fight(a)
	var b_fights: bool = can_fight(b)
	if a.routing:
		tick_rout(a, b, delta)
	if b.routing:
		tick_rout(b, a, delta)
	if not (a_fights and b_fights):
		# No live fight (one side gone, routing, or freshly broken): a still-fightable
		# survivor recovers where it stands. A routing side's own recovery already ran
		# above (tick_rout), so it's excluded here to avoid double-applying morale.
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
