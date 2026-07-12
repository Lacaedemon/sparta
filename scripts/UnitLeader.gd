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
## Tactical repertoire (first slice, matching docs/battle-ai-design.md's phase-1
## acceptance criteria):
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
##
## Phase 2 (docs/battle-ai-design.md) adds an optional `directive` parameter -- a plain
## Dictionary from Subcommander.decide_group, or {} for "no directive this tick". A
## directive only ever reshapes the fallback branch (4, above): it is strictly
## lower-priority than every one of a unit's own immediate reactions (1-3), because a
## subcommander's group-level intent should never override a unit's own self-preservation.
## Only the bottom level actuates -- decide() still returns the same order-command shape
## either way, so a directive-driven decision goes through the exact same apply path.
##
## Phase 3 (docs/battle-ai-design.md) adds an optional `pursue_routers` parameter -- the
## general's doctrine-driven rout-exploitation flag (General.decide_army's own
## "pursue_routers" output). It governs ONLY whether the advance/attack fallback's own
## nearest-enemy search (4, above) may pick a routing enemy as a fresh target; it changes
## nothing else about the priority order, and defaults to true so every existing caller that
## never passes it (including every phase-1/phase-2 test) sees the unchanged prior behaviour
## (include_routing was hardcoded true before this parameter existed).


## Morale floor below which a unit in contact calls for relief.
const RELIEF_MORALE_THRESHOLD := 35.0
## How far away a fresh ally can be and still answer a relief call.
const RELIEF_CALL_RANGE := 220.0
## How close enemy cavalry must close before an anti_cavalry unit forms square.
const SQUARE_TRIGGER_RANGE := 160.0
## facing.dot(to_attacker) at/below which a live threat counts as flank or rear
## (mirrors UnitCombat.flank_multiplier's own 0.35 frontal cutoff -- see there).
const FLANK_DOT_THRESHOLD := 0.35


## Decide this unit's action for the current AI tick. `all_units` is every live node in
## the "units" group (the caller's perception source -- see the class doc: omniscient
## today, fogged in phase 5 without this signature changing). `directive` is this unit's
## subcommander directive for the tick (Subcommander.decide_group's output for this uid),
## or {} when the unit has none -- existing callers that never pass one see the unchanged
## phase-1 behaviour. `pursue_routers` (phase 3) governs the advance/attack fallback's own
## targeting only -- see the class doc's phase-3 note; defaults to true (the old hardcoded
## behaviour). Returns an enqueue_order/_apply_order_cmd-shaped Dictionary, or {} for
## "no change this tick" (Battle skips applying anything, leaving whatever order is already
## running).
static func decide(u: Unit, all_units: Array, directive: Dictionary = {},
		pursue_routers: bool = true) -> Dictionary:
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
	# direct-target-write behaviour -- OR, when this unit's subcommander issued a
	# directive this tick, follow that instead (see the class doc's phase-2 note).
	# Skip units already committed to a fight -- their own _think loop
	# chases/engages target_enemy without a fresh order -- and skip a unit
	# already executing a RELIEF order: it's mid-swap with a tired ally
	# (UnitRelief.begin sets target_enemy but not state, so it isn't FIGHTING
	# yet), and a fresh order here would silently clobber the RELIEF order and
	# its relief_partner link. Mirrors the same exclusion in _relief_candidate,
	# which stops OTHER units from calling this one away.
	var already_relieving: bool = u.current_order != null \
		and u.current_order.type == Order.Type.RELIEF
	if u.state != Unit.State.FIGHTING and not already_relieving:
		# A directive is strictly lower-priority than a unit's own live pursuit of a real
		# threat, same as flank-threat/square/relief above: a unit already chasing a
		# target that's still alive and able to fight back must be left to close and
		# fight, not pulled off mid-chase into a group-level directive. This is the one
		# case priorities 1-3 above don't already cover -- a unit not yet in contact, so
		# _flank_threat's contact-only check doesn't see the closing enemy either.
		if not directive.is_empty() and not is_chasing_live_target(u):
			return _directive_cmd(u, directive)
		# include_routing=pursue_routers: press the advantage and chase down a fleeing
		# enemy too, unless the doctrine says to hold the line instead (phase 3).
		var nearest: Unit = UnitTargeting.nearest_enemy_to(u, u.position, INF, pursue_routers)
		if nearest != null and u.target_enemy != nearest:
			return _attack_cmd(u, nearest)

	return {}


## Whether `u` already has a live ATTACK order chasing a target that is still alive and
## able to fight back (not DEAD, not ROUTING). Shared by decide()'s own directive guard
## above and by Subcommander (which also skips such a unit as a directive candidate in the
## first place) -- see decide()'s comment for why this case needs guarding at all.
static func is_chasing_live_target(u: Unit) -> bool:
	return u.current_order != null and u.current_order.type == Order.Type.ATTACK \
		and u.target_enemy != null and u.target_enemy.state != Unit.State.DEAD \
		and u.target_enemy.state != Unit.State.ROUTING


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


## Phase 2 entry point: translate this unit's subcommander directive
## (Subcommander.decide_group's output for this uid) into an order-command, or {} when the
## unit is already doing what the directive asks -- the same idempotency the ordinary
## nearest-enemy fallback already has (see decide()'s "already targeting the nearest enemy"
## check), so a subcommander re-issuing the same intent every AI tick doesn't restart the
## unit's march each time. An unrecognised directive type is treated as "no directive",
## defensively -- Subcommander never actually emits one.
static func _directive_cmd(u: Unit, directive: Dictionary) -> Dictionary:
	match String(directive.get("type", "")):
		Subcommander.DIRECTIVE_SUPPORT:
			return _support_directive_cmd(u, directive)
		Subcommander.DIRECTIVE_HOLD_LINE, Subcommander.DIRECTIVE_COVER_FLANK:
			return _move_directive_cmd(u, directive)
		_:
			return {}


## A SUPPORT directive: guard the named ward, same shape the friendly-target SUPPORT branch
## of _apply_order_cmd resolves (mode == SUPPORT, target a friendly outside `units`).
## Idempotent: a unit already guarding that exact ward gets no fresh order.
static func _support_directive_cmd(u: Unit, directive: Dictionary) -> Dictionary:
	var ward_uid: int = int(directive.get("ward_uid", -1))
	if ward_uid < 0 or (u.support_target != null and u.support_target.uid == ward_uid):
		return {}
	return {
		"units": [u.uid],
		"x": 0.0,
		"y": 0.0,
		"target": ward_uid,
		"mode": BattleRef.OrderMode.SUPPORT,
	}


## A HOLD_LINE or COVER_FLANK directive: both just move the unit to a directed point and
## stop chasing -- the only difference between them is which Subcommander behaviour picked
## the point, so they share one apply path. Idempotent within Subcommander.POINT_EPSILON of
## the directed point (whether already arrived, or already marching there with no live
## target_enemy) so a directive re-issued every AI tick doesn't restart the march.
static func _move_directive_cmd(u: Unit, directive: Dictionary) -> Dictionary:
	var point := Vector2(float(directive.get("x", u.position.x)), float(directive.get("y", u.position.y)))
	var already_going_there: bool = u.target_enemy == null and (
		(u.has_move_target and u.move_target.distance_to(point) < Subcommander.POINT_EPSILON)
		or (not u.has_move_target and u.position.distance_to(point) < Subcommander.POINT_EPSILON))
	if already_going_there:
		return {}
	return {
		"units": [u.uid],
		"x": point.x,
		"y": point.y,
		"target": -1,
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
