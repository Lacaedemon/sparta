class_name General
## Phase 3 of the chain-of-command battle AI (docs/battle-ai-design.md): the general. Reads a
## doctrine profile (DoctrineRegistry) plus the same omniscient perception every other command
## level uses, and produces:
##   - an army PLAN (which of the doctrine's known plans applies this tick);
##   - a GROUP split of the team's own (non-reserve) units, one array per Subcommander group;
##   - a RESERVE pool, held back until a legible serialized-state condition releases it;
##   - the doctrine's ROUT-EXPLOITATION flag, threaded down to UnitLeader.decide.
##
## Stateless, like UnitLeader (phase 1) and Subcommander (phase 2): one entry point,
## decide_army(), a pure function of already-serialized sim state (the team's own units, every
## living unit, and the doctrine data) called once per AI tick from Battle._run_enemy_ai(). No
## RNG, no wall-clock, no node-iteration-order dependence beyond what the caller already
## controls -- same seed -> same perception -> same plan/groups/reserves, so replay re-derives
## the whole chain exactly like every other AI decision.
##
## OUTPUT, not actuation: decide_army() returns plain data (unit arrays, a plan name, a reserve
## list) -- never an order-command Dictionary and never a unit-state write. The general never
## touches a Unit field directly; Subcommander.decide_group turns the returned groups into
## per-unit directives exactly as phase 2 already does, and UnitLeader.decide turns those (plus
## the general's own reserve-hold directives, see reserve_directives()) into real Orders through
## Battle._apply_order_cmd -- the same single apply site every other command level goes through.
##
## Group assignment (phase 3 scope, per the design doc's own "start static" open-question
## answer): recomputed identically every AI tick from the team's CURRENT living units and the
## chosen plan -- not cached. A pure function recomputed every tick is just as deterministic as
## a persisted cache for this phase's purposes, and it sidesteps the extra state-serialization
## surface a cache would add (docs/battle-ai-design.md, "Group assignment dynamics ... start
## static"). Re-grouping mid-battle as the plan or losses change is explicitly out of scope --
## the plan itself only changes when select_plan's own inputs (unit counts) change enough to
## cross its threshold, which already happens for free since decide_army recomputes it fresh.
##
## Reserve commitment is likewise recomputed every tick rather than driven by a one-way,
## persisted flag: once the active groups' morale recovers back above the doctrine's threshold,
## a committed-but-not-yet-engaged reserve unit reverts to held-back. In practice this almost
## never fires in the "wrong" direction: a reserve unit that has already made contact is
## FIGHTING, and UnitLeader.decide only reads a directive for a non-FIGHTING unit (see its own
## priority-order doc comment), so an engaged reserve can't be "recalled" mid-fight -- only a
## reserve still marching up can revert, and reverting holds it at the trailing reserve offset
## behind the active line (or at its current position if no active line remains) rather than
## snapping it back to its original spawn position. A genuine hysteresis (stays committed even
## after morale recovers, absent contact) would need a persisted per-battle flag -- deliberately
## deferred per the design doc's "start static" scope; the phase-3 acceptance criteria ask only
## that commitment fire on a legible condition, not that it be sticky.

const PLAN_ADVANCE_LINE := "advance_line"
const PLAN_ENVELOP := "envelop"
const PLAN_DEFEND := "defend"
const PLAN_DEFEND_FEATURE := "defend_feature"
const PLAN_WITHDRAW := "withdraw"
const PLAN_AMBUSH := "ambush"
const PLAN_HIDE := "hide"
const PLAN_SCOUT := "scout"
const PLAN_HOLD := "hold"
const PLAN_DO_NOTHING := "do_nothing"


## Decide this AI tick's army-level decision for one team. `team_units` is the team's whole
## ROSTER still on the field -- fightable AND currently-routing units (Battle._team_roster(team),
## the "units" + "routers" union, mirroring _team_in_play/_team_survivors' own convention) --
## deliberately not the narrower "units"-only set: see _reserve_uids' doc comment for why a
## routing unit must still count toward the reserve-fraction denominator even though it can't
## itself be assigned to a group. `all_units` is every living node in the "units" group, the
## same omniscient perception source every other command level reads; `doctrine` is the parsed
## profile (DoctrineRegistry.doctrine(id)). Returns:
##   {"plan": String, "groups": Array[Array], "reserve_units": Array, "pursue_routers": bool}
## `groups` is an array of unit arrays, one per Subcommander group (Subcommander itself decides
## what to do with each -- including silently dropping a ROUTING member, since its own
## `_living()` filter excludes one exactly like this file's `_roster()` does not); `reserve_units`
## are the team's own units held back this tick (not a member of any group). An empty/malformed
## doctrine falls back to phase 2's own behaviour: one group holding the whole team, no
## reserves, routers pursued.
static func decide_army(team_units: Array, all_units: Array, doctrine: Dictionary) -> Dictionary:
	if doctrine.is_empty():
		return {"plan": PLAN_ADVANCE_LINE, "groups": [team_units], "reserve_units": [],
				"pursue_routers": true}

	var roster: Array = _roster(team_units)
	var reserve_fraction: float = float(doctrine.get("reserve_fraction", 0.0))
	var reserve_uids: Dictionary = _reserve_uids(roster, reserve_fraction)

	var active: Array = []
	var reserve_units: Array = []
	for node in roster:
		var u := node as Unit
		if reserve_uids.has(u.uid):
			reserve_units.append(u)
		else:
			active.append(u)

	# Reserves fold into the active line once the line's own morale is legibly in trouble --
	# see the class doc's note on why this is recomputed each tick rather than sticky.
	if not reserve_units.is_empty() and should_commit_reserves(
			active, float(doctrine.get("reserve_commit_morale_threshold", 0.0))):
		active.append_array(reserve_units)
		reserve_units = []

	var plan: String = select_plan(active, all_units, doctrine)
	var groups: Array = assign_groups(active, all_units, plan)

	return {
		"plan": plan,
		"groups": groups,
		"active_units": active,
		"reserve_units": reserve_units,
		"pursue_routers": bool(doctrine.get("pursue_routers", true)),
	}


## `team_units`, filtered to STILL-ON-THE-FIELD units -- excludes only DEAD, deliberately
## keeping ROUTING ones in (unlike Subcommander._living, which excludes both -- a subcommander
## can't usefully coordinate a routing unit, but the general still needs to count it as part of
## the roster; see _reserve_uids' doc comment). Battle._team_roster already applies this same
## union, but the general doesn't rely on that either.
static func _roster(team_units: Array) -> Array:
	var out: Array = []
	for node in team_units:
		var u := node as Unit
		if u != null and u.state != Unit.State.DEAD:
			out.append(u)
	return out


## The uids held back as reserves this tick: the highest-uid `reserve_fraction` (by count) of
## `roster` -- deterministic from the doctrine's fraction and a stable sort order (the design
## doc's own suggested reserve-pool shape), never Replay.rng-randomized. Returns a Dictionary
## used as a uid set ({uid: true, ...}) for O(1) membership checks.
##
## `roster` deliberately includes ROUTING units (see _roster()): if it didn't, a unit routing
## for any reason would shrink the denominator and could silently reclassify a genuine reserve
## as active by pure headcount arithmetic (n - reserve_count crossing a different uid), with no
## connection to the doctrine's own reserve_commit_morale_threshold at all -- exactly the
## "legible serialized-state condition" the design doc asks reserve release to be gated on, not
## an incidental side effect of who else on the team happens to be routing this tick.
static func _reserve_uids(roster: Array, reserve_fraction: float) -> Dictionary:
	var out: Dictionary = {}
	var n: int = roster.size()
	var reserve_count: int = int(float(n) * reserve_fraction)
	if reserve_count <= 0:
		return out
	var uids: Array[int] = []
	for node in roster:
		uids.append((node as Unit).uid)
	uids.sort()
	for i in range(maxi(0, n - reserve_count), n):
		out[uids[i]] = true
	return out


## Units-weighted average morale of `active` units (weighted by soldier count, so a reduced
## unit's morale counts proportionally less than a fresh one -- the same "how much fighting
## force is actually wavering" question a real commander would ask) compared against
## `threshold`. True (commit the reserves) when there's no active line left to weigh, or when
## the weighted average has dropped below the threshold.
static func should_commit_reserves(active: Array, threshold: float) -> bool:
	if active.is_empty():
		return true
	var total_soldiers: int = 0
	var weighted_morale: float = 0.0
	for node in active:
		var u := node as Unit
		total_soldiers += u.soldiers
		weighted_morale += u.morale * u.soldiers
	if total_soldiers <= 0:
		return true
	return (weighted_morale / float(total_soldiers)) < threshold


## Which of the doctrine's known plans applies this tick. Evaluates the doctrine's available
## plans based on force ratios:
##   - "envelop" (if known) once the active unit ratio clears envelop_ratio_threshold;
##   - "defend" (if known) once the active unit ratio falls at or below defend_ratio_threshold,
##     or as base plan if defend is primary/sole plan;
##   - otherwise "advance_line" (or the doctrine's primary plan).
## Purely a function of unit COUNTS -- no positional reasoning here, that's assign_groups' (and, at
## the per-unit level, Subcommander's own) job once the groups exist.
static func select_plan(active: Array, all_units: Array, doctrine: Dictionary) -> String:
	var plans: Array = doctrine.get("plans", [])
	if active.is_empty():
		return PLAN_ADVANCE_LINE
	var team: int = (active[0] as Unit).team
	var enemy_count: int = 0
	for node in all_units:
		var e := node as Unit
		if e != null and e.team != team and e.state != Unit.State.DEAD \
				and e.state != Unit.State.ROUTING:
			enemy_count += 1
	if enemy_count == 0:
		if plans.has(PLAN_ADVANCE_LINE):
			return PLAN_ADVANCE_LINE
		return str(plans[0]) if not plans.is_empty() else PLAN_ADVANCE_LINE

	var ratio: float = float(active.size()) / float(enemy_count)
	if plans.has(PLAN_ENVELOP):
		var envelop_thresh: float = float(doctrine.get("envelop_ratio_threshold", INF))
		if ratio >= envelop_thresh:
			return PLAN_ENVELOP

	if plans.has(PLAN_DEFEND):
		if doctrine.has("defend_ratio_threshold"):
			var defend_thresh: float = float(doctrine.get("defend_ratio_threshold", 0.0))
			if ratio <= defend_thresh:
				return PLAN_DEFEND
		elif not plans.has(PLAN_ADVANCE_LINE) or str(plans[0]) == PLAN_DEFEND:
			return PLAN_DEFEND

	if plans.has(PLAN_ADVANCE_LINE):
		return PLAN_ADVANCE_LINE
	return str(plans[0]) if not plans.is_empty() else PLAN_ADVANCE_LINE


## The fewest units a wing may have and still be worth splitting off as its own Subcommander
## group. Below this, Subcommander.decide_group's own "living.size() < 2 -> {}" degenerate
## case means a lone unit in its own "group" gets no subcommander coordination at all (not
## even the mutual-support/line-integrity/flank-coverage behaviours phase 2 already provides)
## -- worse than just leaving it in the main line. A general wouldn't split a two-man command
## into two one-man wings either; this mirrors that same real-world floor.
const MIN_WING_SIZE := 2

## Split `active` into Subcommander groups per `plan`. ADVANCE_LINE keeps phase 2's own
## behaviour: one group holding every active unit. ENVELOP splits the team laterally
## (perpendicular to the team's own advance axis toward the living enemy centroid) into a left
## and a right wing -- mirroring the same axis/perpendicular geometry
## Subcommander._advance_axis / _flank_coverage_directives already use at the group scale, so
## "left/right of the line" means the same thing at both command levels. Degenerates to a
## single group when there is no axis to split across (no living enemy), a split would leave
## one side empty (too few units, or a degenerate lateral spread), or either resulting wing
## would fall below MIN_WING_SIZE (see its own doc comment).
static func assign_groups(active: Array, all_units: Array, plan: String) -> Array:
	if plan != PLAN_ENVELOP or active.size() < MIN_WING_SIZE * 2:
		return [active]
	var axis: Vector2 = _team_advance_axis(active, all_units)
	if axis == Vector2.ZERO:
		return [active]
	var perp := Vector2(-axis.y, axis.x)
	var centroid: Vector2 = _centroid(active)
	var left: Array = []
	var right: Array = []
	for node in active:
		var u := node as Unit
		if (u.position - centroid).dot(perp) < 0.0:
			left.append(u)
		else:
			right.append(u)
	if left.size() < MIN_WING_SIZE or right.size() < MIN_WING_SIZE:
		return [active]
	return [left, right]


static func _centroid(units: Array) -> Vector2:
	var sum := Vector2.ZERO
	for node in units:
		sum += (node as Unit).position
	return sum / max(units.size(), 1)


## A unit vector from `team_units`' own centroid toward the living enemy team's centroid -- the
## same computation Subcommander._advance_axis makes for one group, mirrored here at the whole-
## team scale (before groups exist, so General can't call Subcommander's own group-scoped
## helper -- and the two are kept as separate small functions rather than one shared utility so
## neither class reaches into the other's private surface). Vector2.ZERO ("no axis") when there
## are no living enemies, or the two centroids coincide -- the same degenerate-case convention
## Subcommander's version uses.
static func _team_advance_axis(team_units: Array, all_units: Array) -> Vector2:
	if team_units.is_empty():
		return Vector2.ZERO
	var team: int = (team_units[0] as Unit).team
	var enemy_sum := Vector2.ZERO
	var enemy_count := 0
	for node in all_units:
		var e := node as Unit
		if e == null or e.team == team or e.state == Unit.State.DEAD \
				or e.state == Unit.State.ROUTING:
			continue
		enemy_sum += e.position
		enemy_count += 1
	if enemy_count == 0:
		return Vector2.ZERO
	var delta: Vector2 = (enemy_sum / enemy_count) - _centroid(team_units)
	if delta.length_squared() < 1.0:
		return Vector2.ZERO
	return delta.normalized()


## How far behind the active committed line's centroid a reserve unit is held along the
## army's advance axis. Set to 140.0 wu -- well within UnitLeader.RELIEF_CALL_RANGE (220.0 wu),
## so a reserve remains in position to answer relief calls and arrive promptly when committed.
const RESERVE_TRAIL_DISTANCE := 140.0  # tuned in wu


## HOLD_LINE-shaped directives (Subcommander's own directive vocabulary -- see its class doc)
## positioning each reserve unit at an offset trailing behind the active committed line's
## centroid along the team's advance axis (recomputed as the line moves), so the reserve
## advances with the army in reserve rather than staying pinned at its original spawn point.
## When there are no active units or no advance axis, falls back to holding each reserve unit
## at its own current position.
## Idempotent via UnitLeader._move_directive_cmd's own POINT_EPSILON check, exactly like an
## ordinary Subcommander HOLD_LINE directive. A unit's own flank-threat / anti-cavalry-square /
## relief-call reactions (UnitLeader.decide's priorities 1-3) still run first, so a reserve can
## still defend itself or relieve a fighting ally -- only the uncoordinated advance/attack
## fallback is suppressed. Committed reserves (folded into `active` by decide_army) never reach
## this function, since it's only ever called with the tick's actual reserve_units.
static func reserve_directives(reserve_units: Array, active_units: Array = [], all_units: Array = [],
		trail_distance: float = RESERVE_TRAIL_DISTANCE) -> Dictionary:
	var out: Dictionary = {}
	if reserve_units.is_empty():
		return out
	var living_active: Array = []
	for node in active_units:
		var u := node as Unit
		if u != null and u.state != Unit.State.DEAD and u.state != Unit.State.ROUTING:
			living_active.append(u)
	var axis: Vector2 = _team_advance_axis(living_active, all_units)
	var active_centroid: Vector2 = _centroid(living_active)
	var perp := Vector2(-axis.y, axis.x)
	for node in reserve_units:
		var u := node as Unit
		if u == null:
			continue
		var target_pos: Vector2 = u.position
		if not living_active.is_empty() and axis != Vector2.ZERO:
			var lat_offset: float = (u.position - active_centroid).dot(perp)
			target_pos = (active_centroid - axis * trail_distance) + perp * lat_offset
		out[u.uid] = {
			"type": Subcommander.DIRECTIVE_HOLD_LINE,
			"x": target_pos.x,
			"y": target_pos.y,
		}
	return out
