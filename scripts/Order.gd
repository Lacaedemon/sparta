class_name Order
extends RefCounted
## Phases 1-3 of the unified orders-queue design (docs/orders-queue-design.md): the
## `Order` value type. A queue entry describing one thing a `Unit` is doing or will do -- a
## verb, in the design doc's terms. Durable "mode" state (formation_mode, order_mode,
## rank_relief, ...) stays on `Unit` itself; an Order is what writes it, not where it lives.
##
## Phase 2 made the queue authoritative for the movement maneuvers: an in-place turn (the
## rear-move about-face phase, the standalone about-face/quarter-turn drills) and the wheel
## carry their own execution state here (turn_target / turn_start_facing / pivot), and a
## phased rear move carries its recorded reform choice and parks its march destination in
## target_pos until the turn completes. `Unit._think` reads and advances that state off
## `current_order`.
##
## Phase 3 finishes absorbing the route and the relief swap: a queued waypoint leg IS a
## queued MOVE order (the parallel Unit.waypoints list is gone), and a line relief's
## pass-through execution state lives here (friendly_target) instead of on both units.
## The in-flight targeting references (Unit.target_enemy / support_target) stay on the
## unit: the reactive layer (enemy AI, auto-engage) writes target_enemy directly with no
## order behind it, so they are execution state the queue reads, not queue state.
##
## Phase 4 adds an optional GUARD to any order: a bounded, enumerated condition (see
## OrderGuards.gd) that -- once satisfied -- retires the order early and promotes the next
## queued one, exactly like any other early-retirement path (an interrupt, an arrival).
## "Advance UNTIL contact THEN attack" is a MOVE order with guard = CONTACT_MADE followed
## by an appended ATTACK order; "hold UNTIL in range THEN fire" is the existing
## ranged-auto-fire behaviour, so a HOLD stance with guard = ENEMY_IN_RANGE on a queued
## follow-on order covers the general "wait, then act" shape without a HOLD-specific
## carve-out. Every guard reads only serialized Unit/sim state (positions, facing, morale,
## fatigue, a per-order elapsed-tick counter) -- no wall-clock, no RNG -- so it evaluates
## identically on replay (docs/orders-queue-design.md, "Two invariants").

## The order kinds phases 1-3 cover. Most arrive via Battle's recorded/replayed
## order-dispatch path; the two standalone drills (ABOUT_FACE / QUARTER_TURN, the V/Q/E
## keys) are queue entries created by Unit itself and deliberately NOT recorded -- see
## SelectionManager.gd for why the drill gestures stay out of the replay stream. The queue
## is not serialized, so an unrecorded drill order changes nothing about what a replay
## reproduces (exactly as the old drill flags didn't).
enum Type {
	MOVE,       ## March to a destination (a waypoint leg or a plain move); carries an execution
	            ## style chosen by geometry at issue time (direct march, or an about-face phase
	            ## for a rear-sector move -- see Phase below).
	ATTACK,     ## Chase and fight a specific enemy unit until it dies or the order is superseded.
	RELIEF,     ## Inter-unit relief: a fresh unit passes through/replaces a tired ally in contact.
	SUPPORT,    ## Guard a friendly ward, engaging threats near it until the ward is gone.
	WHEEL,      ## Circumductio: swing the line 90 degrees about a fixed flank file.
	NUDGE,      ## A short fixed-distance drill step (side-step, back-step, or forward-step),
	            ## holding facing.
	FORMATION,  ## Change formation_mode (tight/loose/square/shield-wall/testudo). Instantaneous.
	FRONTAGE,   ## Resize frontage to an absolute file count (manual resize or a file-double/
	            ## file-halve maneuver -- same execution, different caller-derived target width).
	            ## Instantaneous.
	ABOUT_FACE,   ## Standalone conversio drill (V key): every soldier reverses 180° in place.
	              ## Created by Unit.conversio(), not recorded. Appended after the phase-1 types
	              ## so recorded transcripts keep their type values stable.
	QUARTER_TURN, ## Standalone quarter-turn drill (Q/E keys): every soldier pivots 90° in place.
	              ## Created by Unit.quarter_turn(), not recorded.
	STANCE,       ## Standalone stance change (no movement): writes the durable order_mode
	              ## and/or the intra-unit rank-relief mode on the unit. Instantaneous, like
	              ## FORMATION/FRONTAGE. Appended after the phase-2 types so recorded
	              ## transcripts keep their type values stable.
	FORM_UP,      ## Group-level drag-line deploy (docs/atomic-order-decomposition-design.md):
	              ## never a leaf and never any Unit's own current_order -- purely the shared
	              ## parent tagging a multi-unit form-up's per-unit MOVE orders as one
	              ## conceptual command (children holds those orders; each child's own
	              ## `parent` points back here). Appended last so recorded transcripts keep
	              ## every other type's value stable.
}

## An order's internal choreography, for the phased case that already exists: a move into a
## unit's rear sector runs an about-face (conversio) in place, then -- when the order was issued
## with the reform-before-move drill -- REFORMS the ranks square to the new heading (so the
## fullest rank fronts it, not the old partial rear rank), and only then marches. Multiple phases
## of one queue entry, not multiple queue entries (docs/orders-queue-design.md, "Intra-order
## phasing"). Every other order type stays NONE; the mechanism exists so a later phase can add
## more phased orders without a new Order subtype.
enum Phase {
	NONE,        ## Not phased, or a phased order that hasn't started its first phase yet.
	TURN,        ## In-place about-face running before the march (move-to-rear only).
	MARCH,       ## Marching to the destination -- the phase every other MOVE order is in
	             ## throughout.
	REFORM,      ## Re-forming the ranks square to the new heading between the about-face and
	             ## the march (move-to-rear issued with reform-before-move on). Appended after
	             ## MARCH so recorded transcripts keep their phase values stable.
	RETURN_TURN, ## Turning back to the pre-pivot facing after the march arrives (a lateral
	             ## pivot's closing phase -- see Unit.begin_pivot / pivot_return_angle). The
	             ## grid was never reformed during the march, so nothing but facing needs to
	             ## move here. Appended after REFORM so recorded transcripts keep their phase
	             ## values stable.
	WHEEL,       ## The flank-pivot phase of an about-face + wheel + march composite (see
	             ## Unit.begin_about_face_with_wheel) -- a WHEEL-typed leaf sitting BETWEEN
	             ## the opening about-face and the march, so it needs its own label rather
	             ## than falling into effective_phase_name()'s by-position TURN/RETURN_TURN
	             ## guess. Appended after RETURN_TURN so recorded transcripts keep their
	             ## phase values stable.
}

## Phase 4's bounded, enumerated guard vocabulary (docs/orders-queue-design.md,
## "Guards from a bounded, enumerated vocabulary"). A guard names a condition that, once
## true, retires the order early -- the self-terminating form of queue advancement. Kept
## deliberately closed (no free-form predicate) so every guard is a pure function of
## serialized state (OrderGuards.satisfied); adding a new guard is a new enum member plus a
## new OrderGuards branch, never inline scripting on the order itself.
enum Guard {
	NONE,            ## No guard: the order runs to its own normal completion only.
	ENEMY_IN_RANGE,  ## A live enemy is within guard_param world units of this unit.
	CONTACT_MADE,    ## A live enemy is within melee contact distance (attack_range + radii).
	MORALE_BELOW,    ## This unit's morale has fallen below guard_param.
	ALLY_EXHAUSTED,  ## The unit named by guard_uid (a friendly) has fatigue >= guard_param.
	TICKS_ELAPSED,   ## guard_param physics ticks have elapsed since the order became current.
	FLANKED,         ## A live enemy currently stands in this unit's flank/rear arc within
	                 ## guard_param world units (contact range when guard_param <= 0).
}

const GUARD_NAMES := {
	Guard.NONE: "NONE",
	Guard.ENEMY_IN_RANGE: "ENEMY_IN_RANGE",
	Guard.CONTACT_MADE: "CONTACT_MADE",
	Guard.MORALE_BELOW: "MORALE_BELOW",
	Guard.ALLY_EXHAUSTED: "ALLY_EXHAUSTED",
	Guard.TICKS_ELAPSED: "TICKS_ELAPSED",
	Guard.FLANKED: "FLANKED",
}

const TYPE_NAMES := {
	Type.MOVE: "MOVE",
	Type.ATTACK: "ATTACK",
	Type.RELIEF: "RELIEF",
	Type.SUPPORT: "SUPPORT",
	Type.WHEEL: "WHEEL",
	Type.NUDGE: "NUDGE",
	Type.FORMATION: "FORMATION",
	Type.FRONTAGE: "FRONTAGE",
	Type.ABOUT_FACE: "ABOUT_FACE",
	Type.QUARTER_TURN: "QUARTER_TURN",
	Type.STANCE: "STANCE",
	Type.FORM_UP: "FORM_UP",
}

const PHASE_NAMES := {
	Phase.NONE: "NONE",
	Phase.TURN: "TURN",
	Phase.MARCH: "MARCH",
	Phase.REFORM: "REFORM",
	Phase.RETURN_TURN: "RETURN_TURN",
	Phase.WHEEL: "WHEEL",
}

var type: int = Type.MOVE
var phase: int = Phase.NONE

# --- Order tree (docs/atomic-order-decomposition-design.md) -------------------
# A composite order (the rear-move and lateral-pivot maneuvers, plus a reform-before-move
# hold, whether standalone or interstitial to a rear-move) decomposes into a small tree of
# its own atomic steps instead of cycling `phase` through TURN/MARCH/REFORM/RETURN_TURN on
# itself: each step is a genuine child Order, and _active_child names which one is currently
# driving Unit._think (see active_leaf() below). `phase` still exists, but as of Slice 1 it is
# only ever set on a LEAF -- REFORM marks a leaf that IS the interstitial hold (reform_timer/
# reform_until_settled/reform_settle_eps below are that leaf's own state) -- never on a
# composite itself. Every order with no children -- the overwhelming majority, including
# every standalone drill -- is unaffected: active_leaf() just returns the order itself.
#
# A second, shallower use of `parent` (no `children` of its own on the parent side, from a
# per-unit order's point of view): a multi-unit drag-line form-up's per-unit MOVE orders each
# point `parent` at a shared FORM_UP order tagging them as one group (Battle._apply_order_cmd
# builds it, keyed by the recorded "form_up_group" id) -- the group order is never installed
# as any Unit's own current_order, so nothing ever walks INTO it via active_leaf(); it exists
# purely so a child's own `parent` reference resolves to something, and for a future HUD to
# read "these orders belong to the same group command" off it.

## Nested sub-orders; empty (the default) means this order is a genuine leaf/atomic step.
var children: Array[Order] = []
## Index into `children` of the currently-executing sub-order.
var _active_child: int = 0
## Back-reference to the composite this order is a child of; null for a top-level order
## (Unit.current_order) or any other leaf order that was never installed as a child. Set
## once, alongside `children`, when a composite builds its steps -- never re-derived.
var parent: Order = null

## The genuinely atomic order actually driving this tick's movement/turn logic: walks
## children[_active_child] recursively until it finds a leaf (empty children). Called on
## the top-level order (Unit.current_order); a leaf order -- no children at all, the case
## for everything except the composites above -- returns itself unchanged.
func active_leaf() -> Order:
	var node := self
	while node != null and not node.children.is_empty():
		node = node.children[node._active_child]
	return node


# --- REFORM leaf state (docs/atomic-order-decomposition-design.md, Slice 1) --------------
# A reform-before-move hold -- a plain move's pause, a form-up's reshape, or the interstitial
# re-square a rear-move/lateral-pivot composite runs between its turn and its march -- is a
# genuine MOVE-typed leaf marked `phase == Phase.REFORM`, carrying its own countdown instead
# of the bare Unit._reform_timer/_reform_target/_reform_until_settled/_reform_settle_eps
# fields the hold used before this slice. `target_pos` (declared below) IS the held
# destination; no separate field is needed for it.

## Countdown (seconds) for this REFORM leaf's interstitial hold; > 0 while holding, 0 once it
## has committed (or on any ordinary, non-holding leaf, which never touches this field).
## Unit._commit_pending_reform advances the tree cursor to this leaf's next sibling once the
## countdown (or an early settle) ends the hold.
var reform_timer: float = 0.0
## True when the hold above ends EARLY on genuine settlement (Unit._reform_bodies_settled)
## rather than only on reform_timer running out -- a form-up's reshape hold opts into this; a
## plain reform-before-move keeps the fixed countdown (this stays false for it).
var reform_until_settled: bool = false
## The settle tolerance reform_until_settled checks against: Unit.REFORM_SETTLE_EPS for a
## same-shape fold, Unit.REFORM_SETTLE_EPS_RESHAPE for a full frontage reshape. Unused while
## reform_until_settled is false.
var reform_settle_eps: float = 0.0


## The Phase name this order reads as from the outside (the transcript's `order_phase`
## field, chiefly): a composite's TURN/MARCH/RETURN_TURN/REFORM all live in which child is
## active (REFORM specifically via that child's own `phase == Phase.REFORM`), not in this
## order's own `phase` -- every reform-before-move hold, standalone or interstitial to a
## rear-move/lateral-pivot, is installed as a child (see Unit._commit_pending_reform and
## Unit._finish_order_turn), never left on the composite itself. A genuine leaf (no children
## at all) just reports its own `phase` unchanged (always NONE in practice -- nothing installs
## a leaf order as `current_order` directly with `phase` pre-set).
func effective_phase_name() -> String:
	if children.is_empty():
		return phase_name(phase)
	var leaf: Order = active_leaf()
	if leaf.phase == Phase.REFORM:
		return phase_name(Phase.REFORM)
	if leaf.type == Type.MOVE:
		return phase_name(Phase.MARCH)
	if leaf.type == Type.WHEEL:
		return phase_name(Phase.WHEEL)
	return phase_name(Phase.TURN if _active_child == 0 else Phase.RETURN_TURN)


## Movement destination (MOVE/NUDGE); ZERO when unused.
var target_pos: Vector2 = Vector2.ZERO
## Target unit uid (ATTACK/RELIEF/SUPPORT); -1 when unused.
var target_uid: int = -1
## FORMATION target (Unit.FORMATION_* constant); -1 when unused.
var formation: int = -1
## FRONTAGE target file count; -1 when unused.
var frontage: int = -1
## FRONTAGE anchor shift (UnitFormation.anchor_shift): the local-X offset an asymmetric
## explicatio/duplicatio holds one flank fixed with; 0.0 is the plain centred resize.
var frontage_anchor_offset: float = 0.0
## WHEEL/NUDGE/QUARTER_TURN direction (Battle.NudgeDir for NUDGE; +-1 otherwise); 0 when unused.
var dir: int = 0
## The order_mode (Battle.OrderMode) the issuing command carried, for MOVE/ATTACK/SUPPORT.
var order_mode: int = 0
## The gait (Battle.Gait: WALK/JOG/RUN/SPRINT) for MOVE orders. When >= 0, overrides
## the normal AUTO gait logic and uses the specified speed. Defaults to -1 (disabled).
## When disabled, units use AUTO mode (walk by default, jog under fire, sprint at close range).
var gait: int = -1
## Whether this MOVE order is "in haste": too urgent for even a disciplined unit to execute
## a formed centre-pivot turn before marching (Unit._is_move_order_in_haste). Distinct from
## `gait` -- a Shift+right-click waypoint append also carries `gait == RUN` to keep travel
## speed continuous with the leg before it (SelectionManager._gait_from_click_count), but
## that is NOT an urgency signal, so `new_move` clears `haste` for append legs regardless
## of `gait`. Only a genuine triple/quadruple-click order (not an append) sets it.
var haste: bool = false
## STANCE target order_mode (Battle.OrderMode) to write on the unit; -1 = leave unchanged.
var stance: int = -1
## STANCE rank-relief mode toggle (Battle.RankRelief): LEAVE keeps the unit's current
## setting, ON/OFF write it. Rides the recorded command's "frontage" field, like the
## nudge direction, so the replay format is unchanged.
var rank_relief: int = 0

# --- Maneuver execution state (phase 2) --------------------------------------
# Owned by the order: Unit._think reads and advances these off current_order instead of off
# parallel Unit fields, so an interrupted or replaced order takes its in-flight maneuver
# state with it. Set deterministically at the exactly-once apply site (or by the drill
# methods themselves), never from frame timing, so live play and replay stay in lockstep.

## Goal facing of the in-place turn / wheel swing this order is running; ZERO when the
## maneuver is idle or complete. Non-zero for a rear MOVE's TURN phase, a live ABOUT_FACE /
## QUARTER_TURN drill, and a WHEEL mid-swing.
var turn_target: Vector2 = Vector2.ZERO
## The heading when the turn was armed, kept so completing (or interrupting) the turn can
## fold exactly how far it turned into Unit._formation_angle -- every man then holds his
## own slot under the new facing instead of surging to a reorganised grid.
var turn_start_facing: Vector2 = Vector2.ZERO
## WHEEL only: the fixed hinge point (parent-local, like Unit._sim_soldier_pos), captured
## once when the wheel is armed so the arc reproduces exactly on replay.
var pivot: Vector2 = Vector2.ZERO
## MOVE only: the reform-before-move drill choice the issuing command carried (the recorded
## "reform" field). For a rear move: true = re-form the ranks square to the new heading
## between the about-face and the march; false = step off at once and re-form on arrival.
var reform: bool = false
## MOVE only, lateral-pivot composite: the signed turn angle (radians, Unit.begin_pivot's
## `facing.rotated(angle)` convention) to turn back BY once the march arrives -- the negation
## of the initial pivot's own signed angle. Zero (default) means this MOVE order has no
## return leg -- every other MOVE order, and a lateral pivot whose initial turn never armed
## (see Battle._apply_order_cmd), leaves it at zero. Set once at issue time, consumed (and
## cleared to zero, so it only fires once) by Unit._think's arrival handler.
var pivot_return_angle: float = 0.0
## MOVE only, Unit.countermarch()'s composite: which exelismos variant (Unit.CountermarchVariant)
## this order is running, or -1 for every other order (including a plain rear move built the
## same way -- see begin_about_face). Unit.current_maneuver()/order_summary() read this first,
## ahead of about_face_goal()/is_order_turning(), since a countermarch's opening phase IS a
## bare Order.Type.ABOUT_FACE leaf and can't otherwise be told apart from a plain conversio or
## rear-move turn. Set once at issue time; never mutated afterward.
var countermarch_variant: int = -1
## A live pass-through link to a friendly unit, settable by ANY order type -- not just
## RELIEF. While armed, Unit._separation_exempt lets the two units interpenetrate instead
## of shoving each other apart, and resolve_friendly_target (below) clears the link once
## the pair is apart or the partner has left the line. The whole link dies with the order
## on an interrupt, since the pass-through's execution state lives here, not on either
## unit. null when idle or resolved. RELIEF is the first consumer (UnitRelief.begin arms
## it, UnitRelief.update resolves it via the shared helper below); a future multi-unit
## maneuver that needs the same "walk through a named friendly" behavior sets this same
## field and gets the exemption and resolution for free, with no Unit.gd changes.
## (target_uid still carries a RELIEF order's ally uid for the transcript; this is the
## resolved node the exemption compares.)
var friendly_target: Unit = null

# --- Terminal-condition / guard state (phase 4) -------------------------------
# The guard itself (which condition, and its parameter) is set once at issue time and never
# mutated; _guard_ticks is the one piece of live execution state a guard needs, owned by the
# order like every other maneuver-execution field above so it resets cleanly when the order
# is replaced or interrupted.

## The bounded guard condition gating this order's early retirement; Guard.NONE (default)
## means the order runs to its own ordinary completion only. Set at issue time.
var guard: int = Guard.NONE
## The guard's numeric parameter: a range in world units (ENEMY_IN_RANGE, FLANKED), a morale
## threshold (MORALE_BELOW), a fatigue threshold (ALLY_EXHAUSTED), or a tick count
## (TICKS_ELAPSED). Unused (0.0) for CONTACT_MADE, which has no parameter.
var guard_param: float = 0.0
## The friendly unit's uid ALLY_EXHAUSTED watches; -1 for every other guard.
var guard_uid: int = -1
## TICKS_ELAPSED only: physics ticks counted since this order became current. Advanced once
## per tick by Unit._think (a deterministic per-order counter, not a wall-clock read) and
## reset whenever the order (re)starts, so an order re-armed after an interrupt restarts its
## count rather than inheriting a stale one.
var _guard_ticks: int = 0


## Attach a guard to this order and return it, for a fluent call at the constructor site
## (e.g. `Order.new_move(dest).with_guard(Order.Guard.CONTACT_MADE)`). `param` and `uid`
## default to "unused" so most call sites only need the guard kind itself.
func with_guard(guard_kind: int, param: float = 0.0, uid: int = -1) -> Order:
	guard = guard_kind
	guard_param = param
	guard_uid = uid
	return self


## Resolve `u`'s live friendly_target link on its current order, if any: clears it once
## the named partner has left the line (gone, dead, or routing) or the two units have
## moved clear of each other. No-op when there's no live link, so any maneuver's own
## per-tick update can call this unconditionally.
##
## The "clear of each other" distance adds each unit's own soldier_block_extent() (the
## same reach the render/shadow already size off, a function of soldier count, frontage
## and formation density -- not a flat per-type radius) on top of the regiments'
## separation_radius floor. The pass-through exemption this resolves is all-or-nothing
## across every soldier-body pair between the two regiments (see SoldierSteering), so
## clearing it on the regiments' bare CENTER distance alone can fire while a wide
## LOOSE-order block's edge is still well inside the other block -- every overlapping
## body pair then gets shoved apart on the same tick, a chaotic swirl. Extracted from
## UnitRelief so any future order type that arms friendly_target reuses this exact
## distance math instead of re-deriving it (and risking that same bug).
static func resolve_friendly_target(u: Unit) -> void:
	var order: Order = u.current_order
	if order == null or order.friendly_target == null:
		return
	var partner: Unit = order.friendly_target
	var gone: bool = not is_instance_valid(partner) \
		or partner.state == Unit.State.DEAD \
		or partner.state == Unit.State.ROUTING
	var apart: bool = is_instance_valid(partner) \
		and u.position.distance_to(partner.position) \
			> u.separation_radius + partner.separation_radius \
				+ u.soldier_block_extent() + partner.soldier_block_extent()
	if gone or apart:
		order.friendly_target = null


## Serializes this order -- and, recursively, its children -- to a plain Dictionary for
## Replay's derived state-snapshot cache (see ReplaySnapshotCache.gd / Unit.to_snapshot_dict).
## `friendly_target`, the only Unit reference an Order carries, is deliberately NOT captured:
## it's a live pass-through link used only to exempt two specific units from separation mid-
## relief-swap (see the field's own doc comment above), so the rare case of a snapshot landing
## exactly inside that swap loses the exemption for one tick -- the units shove apart instead
## of interpenetrating -- rather than resolving into whatever they'd have naturally settled to
## a moment later either way.
func to_dict() -> Dictionary:
	var d := {
		"type": type,
		"phase": phase,
		"active_child": _active_child,
		"reform_timer": reform_timer,
		"reform_until_settled": reform_until_settled,
		"reform_settle_eps": reform_settle_eps,
		"target_pos": target_pos,
		"target_uid": target_uid,
		"formation": formation,
		"frontage": frontage,
		"frontage_anchor_offset": frontage_anchor_offset,
		"dir": dir,
		"order_mode": order_mode,
		"gait": gait,
		"haste": haste,
		"stance": stance,
		"rank_relief": rank_relief,
		"turn_target": turn_target,
		"turn_start_facing": turn_start_facing,
		"pivot": pivot,
		"reform": reform,
		"pivot_return_angle": pivot_return_angle,
		"countermarch_variant": countermarch_variant,
		"guard": guard,
		"guard_param": guard_param,
		"guard_uid": guard_uid,
		"guard_ticks": _guard_ticks,
		"children": [],
	}
	for child in children:
		d["children"].append(child.to_dict())
	return d


## Rebuilds an order tree from to_dict()'s output (children recursively, each with `parent`
## re-linked back to its rebuilt parent). See to_dict()'s doc for what's deliberately not
## round-tripped (friendly_target).
static func from_dict(d: Dictionary) -> Order:
	var o := Order.new()
	o.type = int(d.get("type", Type.MOVE))
	o.phase = int(d.get("phase", Phase.NONE))
	o._active_child = int(d.get("active_child", 0))
	o.reform_timer = float(d.get("reform_timer", 0.0))
	o.reform_until_settled = bool(d.get("reform_until_settled", false))
	o.reform_settle_eps = float(d.get("reform_settle_eps", 0.0))
	o.target_pos = d.get("target_pos", Vector2.ZERO)
	o.target_uid = int(d.get("target_uid", -1))
	o.formation = int(d.get("formation", -1))
	o.frontage = int(d.get("frontage", -1))
	o.frontage_anchor_offset = float(d.get("frontage_anchor_offset", 0.0))
	o.dir = int(d.get("dir", 0))
	o.order_mode = int(d.get("order_mode", 0))
	o.gait = int(d.get("gait", -1))
	o.haste = bool(d.get("haste", false))
	o.stance = int(d.get("stance", -1))
	o.rank_relief = int(d.get("rank_relief", 0))
	o.turn_target = d.get("turn_target", Vector2.ZERO)
	o.turn_start_facing = d.get("turn_start_facing", Vector2.ZERO)
	o.pivot = d.get("pivot", Vector2.ZERO)
	o.reform = bool(d.get("reform", false))
	o.pivot_return_angle = float(d.get("pivot_return_angle", 0.0))
	o.countermarch_variant = int(d.get("countermarch_variant", -1))
	o.guard = int(d.get("guard", Guard.NONE))
	o.guard_param = float(d.get("guard_param", 0.0))
	o.guard_uid = int(d.get("guard_uid", -1))
	o._guard_ticks = int(d.get("guard_ticks", 0))
	var kids: Array[Order] = []
	for c in d.get("children", []):
		var child := from_dict(c)
		child.parent = o
		kids.append(child)
	o.children = kids
	return o


static func type_name(value: int) -> String:
	return TYPE_NAMES.get(value, "TYPE(%d)" % value)


static func phase_name(value: int) -> String:
	return PHASE_NAMES.get(value, "PHASE(%d)" % value)


static func guard_name(value: int) -> String:
	return GUARD_NAMES.get(value, "GUARD(%d)" % value)


## Readable one-line description for logs/transcripts, e.g. "MOVE:TURN", "ATTACK", or
## "MOVE until CONTACT_MADE". The guard suffix is appended after any phase suffix so a
## phased, guarded order (rare but not disallowed) still reads left-to-right.
func describe() -> String:
	var base: String = type_name(type)
	if phase != Phase.NONE:
		base = "%s:%s" % [base, phase_name(phase)]
	if guard != Guard.NONE:
		base = "%s until %s" % [base, guard_name(guard)]
	return base


## `haste` is a plain passthrough, not derived from `gait`: a caller issuing a genuine
## click-count-driven RUN/SPRINT order passes `haste = true`, but SelectionManager's
## waypoint-append path also forces `gait == RUN` for travel-speed continuity with the leg
## before it (not urgency), so it must pass `haste = false` even at that same gait.
static func new_move(dest: Vector2, mode: int = 0, gait: int = -1, haste: bool = false) -> Order:
	var o := Order.new()
	o.type = Type.MOVE
	o.target_pos = dest
	o.order_mode = mode
	if gait >= 0:
		o.gait = gait
	o.haste = haste
	return o


static func new_attack(enemy_uid: int, mode: int = 0) -> Order:
	var o := Order.new()
	o.type = Type.ATTACK
	o.target_uid = enemy_uid
	o.order_mode = mode
	return o


static func new_relief(ally_uid: int) -> Order:
	var o := Order.new()
	o.type = Type.RELIEF
	o.target_uid = ally_uid
	return o


static func new_support(ward_uid: int) -> Order:
	var o := Order.new()
	o.type = Type.SUPPORT
	o.target_uid = ward_uid
	return o


static func new_wheel(wheel_dir: int) -> Order:
	var o := Order.new()
	o.type = Type.WHEEL
	o.dir = wheel_dir
	return o


static func new_about_face() -> Order:
	var o := Order.new()
	o.type = Type.ABOUT_FACE
	return o


static func new_quarter_turn(turn_dir: int) -> Order:
	var o := Order.new()
	o.type = Type.QUARTER_TURN
	o.dir = turn_dir
	return o


static func new_nudge(nudge_dir: int) -> Order:
	var o := Order.new()
	o.type = Type.NUDGE
	o.dir = nudge_dir
	return o


static func new_stance(stance_mode: int, rank_relief_toggle: int = 0) -> Order:
	var o := Order.new()
	o.type = Type.STANCE
	o.stance = stance_mode
	o.rank_relief = rank_relief_toggle
	return o


static func new_formation(formation_mode: int) -> Order:
	var o := Order.new()
	o.type = Type.FORMATION
	o.formation = formation_mode
	return o


static func new_frontage(files: int, anchor_offset: float = 0.0) -> Order:
	var o := Order.new()
	o.type = Type.FRONTAGE
	o.frontage = files
	o.frontage_anchor_offset = anchor_offset
	return o


## The shared group-tagging order a multi-unit drag-line form-up builds once (see the
## "Order tree" note above): never installed as any Unit's current_order, so it needs
## none of the other constructors' per-kind fields -- callers set `children` themselves as
## each per-unit order joins the group.
static func new_form_up() -> Order:
	var o := Order.new()
	o.type = Type.FORM_UP
	return o
