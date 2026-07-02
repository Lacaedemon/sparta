class_name UnitLeader
## Battle.gd has no class_name (see its own file for why), so its constants are reached
## through a preload alias -- the same pattern HUD.gd / SelectionManager.gd / KeybindingsDialog.gd
## / ShortcutsOverlay.gd already use.
const BattleRef = preload("res://scripts/Battle.gd")

## Phase 1 of the chain-of-command battle AI (docs/battle-ai-design.md): the unit leader.
## Decides what one AI-controlled unit does this AI tick and returns that decision as an
## order-command Dictionary shaped exactly like Battle.enqueue_order/_apply_order_cmd's
## "cmd" -- so Battle applies it through the single apply site, the same path a player
## order takes. No direct unit-state writes happen here; a leader's decision is data, not
## an action -- Battle._run_enemy_ai is the only thing that acts on it.
##
## Pure function of sim state only (perception is the omniscient placeholder the design
## doc describes -- every living unit is visible; phase 5 swaps this for a fogged view):
## no RNG, no wall-clock, no node-iteration-order dependence beyond what the caller
## already controls. Same seed -> same perception -> same decisions, so replay re-derives
## AI orders exactly as the old _run_enemy_ai did.
##
## Tactical repertoire (first slice, per #584's acceptance criteria):
##   1. Face a flank threat -- an enemy already in contact from the unit's flank/rear
##      gets retargeted so the unit turns to meet it (Unit._face_for_action re-faces
##      toward target_enemy; see UnitCombat.flank_multiplier for the same geometry).
##   2. Form anti-cavalry square -- an anti_cavalry unit not already square, with enemy
##      cavalry closing inside SQUARE_TRIGGER_RANGE, forms FORMATION_SQUARE.
##   3. Call for relief when wavering -- a unit below RELIEF_MORALE_THRESHOLD, already in
##      contact, with a fresh (non-fighting, high-morale) ally within RELIEF_CALL_RANGE,
##      requests that ally relieve it.
##   4. Advance/attack -- the fallback: idle (or already-attacking) units close on the
##      nearest living enemy, subsuming the old direct target_enemy write.
## Checked in this order per unit per decision tick: an already-fighting unit facing a
## flank threat reacts to it before any square/relief call, and a unit forming square
## doesn't also request relief the same tick (a fresh order replaces the current one, so
## only the highest-priority decision should apply this tick).


## Morale floor below which a unit in contact calls for relief.
const RELIEF_MORALE_THRESHOLD := 35.0
## How far away a fresh ally can be and still answer a relief call.
const RELIEF_CALL_RANGE := 220.0
## How close enemy cavalry must close before an anti_cavalry unit forms square.
const SQUARE_TRIGGER_RANGE := 160.0
## facing.dot(to_attacker) at/below which a live threat counts as flank or rear
## (mirrors UnitCombat.flank_multiplier's own -0.35 frontal cutoff -- see there).
const FLANK_DOT_THRESHOLD := 0.35


## Decide this unit's action for the current AI tick. `all_units` is every live node in
## the "units" group (the caller's perception source -- see the class doc: omniscient
## today, fogged in phase 5 without this signature changing). Returns an
## enqueue_order/_apply_order_cmd-shaped Dictionary, or {} for "no change this tick"
## (Battle skips applying anything, leaving whatever order is already running).
static func decide(u: Unit, all_units: Array) -> Dictionary:
	if u.state == Unit.State.DEAD or u.state == Unit.State.ROUTING:
		return {}

	var flanker: Unit = _flank_threat(u, all_units)
	if flanker != null:
		return _attack_cmd(u, flanker)

	if _should_form_square(u, all_units):
		return _formation_cmd(u, Unit.FORMATION_SQUARE)

	if u.state == Unit.State.FIGHTING and u.morale < RELIEF_MORALE_THRESHOLD:
		var reliever: Unit = _relief_candidate(u, all_units)
		if reliever != null:
			return _relief_cmd(reliever, u)

	# Fallback: advance/attack the nearest living enemy, subsuming the old
	# direct-target-write behaviour. Skip units already committed to a fight --
	# their own _think loop chases/engages target_enemy without a fresh order.
	if u.state != Unit.State.FIGHTING:
		var nearest: Unit = UnitTargeting.nearest_enemy_to(u, u.position, INF)
		if nearest != null and u.target_enemy != nearest:
			return _attack_cmd(u, nearest)

	return {}


## A living enemy already in contact (attack range) that is closing from this unit's
## flank or rear rather than its front. Contact-only (not DETECTION_RANGE) so a leader
## doesn't spin to face a distant threat it hasn't met yet -- the advance/attack fallback
## closes the distance first, and by the time the lines meet the frontal approach usually
## already has the unit facing the right way; this reacts to the case where it doesn't
## (a flanking maneuver, or an enemy that closed on an unengaged side).
static func _flank_threat(u: Unit, all_units: Array) -> Unit:
	var best: Unit = null
	var best_dot := FLANK_DOT_THRESHOLD
	for node in all_units:
		var e := node as Unit
		if e == null or e.team == u.team or e.state == Unit.State.DEAD \
				or e.state == Unit.State.ROUTING:
			continue
		var contact: float = u.attack_range + Unit.RADIUS + e.RADIUS
		if u.position.distance_to(e.position) > contact:
			continue
		var to_e: Vector2 = (e.position - u.position).normalized()
		var d: float = u.facing.dot(to_e)
		if d < best_dot:
			best_dot = d
			best = e
	return best


## Whether `u` should form the anti-cavalry square this tick: an anti_cavalry unit,
## not cavalry itself, not already square, with living enemy cavalry closing inside
## SQUARE_TRIGGER_RANGE. Mirrors the design doc's phase-1 scope ("cavalry closing on a
## spear unit triggers Order.new_formation(FORMATION_SQUARE) while there is still time
## to form it") -- triggers before contact, unlike the flank-threat reaction above.
static func _should_form_square(u: Unit, all_units: Array) -> bool:
	if not u.anti_cavalry or u.is_cavalry or u.in_square():
		return false
	for node in all_units:
		var e := node as Unit
		if e == null or e.team == u.team or not e.is_cavalry \
				or e.state == Unit.State.DEAD or e.state == Unit.State.ROUTING:
			continue
		if u.position.distance_to(e.position) <= SQUARE_TRIGGER_RANGE:
			return true
	return false


## Nearest fresh (non-fighting, non-routing, healthy-morale, not already committed to
## someone else's relief or support) ally within RELIEF_CALL_RANGE that can answer
## `tired`'s relief call -- the same fitness a player would look for before ordering a
## relief swap (UnitRelief.begin does the actual swap once the order applies). Null when
## no ally qualifies, so a wavering unit with no one to call on just keeps fighting.
static func _relief_candidate(tired: Unit, all_units: Array) -> Unit:
	var best: Unit = null
	var best_d: float = RELIEF_CALL_RANGE
	for node in all_units:
		var a := node as Unit
		if a == null or a == tired or a.team != tired.team \
				or a.state == Unit.State.DEAD or a.state == Unit.State.ROUTING \
				or a.state == Unit.State.FIGHTING or a.morale < RELIEF_MORALE_THRESHOLD \
				or a.support_target != null \
				or (a.current_order != null and a.current_order.type == Order.Type.RELIEF):
			continue
		var d: float = tired.position.distance_to(a.position)
		if d < best_d:
			best_d = d
			best = a
	return best


## An ATTACK order-command for `u` against `target` -- same shape enqueue_order builds,
## so Battle._apply_order_cmd's merge/attack branch (target_uid >= 0, not in `units`)
## drives it exactly like a player attack click.
static func _attack_cmd(u: Unit, target: Unit) -> Dictionary:
	return {
		"units": [u.uid],
		"x": target.position.x,
		"y": target.position.y,
		"target": target.uid,
	}


## A RELIEF order-command: `reliever` (outside `units`) is the merge-style target that
## Battle._apply_order_cmd's relief branch (team match, not FOCUSED attack) resolves into
## Order.new_relief + UnitRelief.begin.
static func _relief_cmd(reliever: Unit, tired: Unit) -> Dictionary:
	return {
		"units": [reliever.uid],
		"x": 0.0,
		"y": 0.0,
		"target": tired.uid,
	}


## A FORMATION-only order-command -- same shape enqueue_formation builds.
static func _formation_cmd(u: Unit, formation: int) -> Dictionary:
	return {
		"units": [u.uid],
		"x": 0.0,
		"y": 0.0,
		"target": BattleRef.ORDER_FORMATION_ONLY,
		"mode": BattleRef.OrderMode.NORMAL,
		"formation": formation,
	}
