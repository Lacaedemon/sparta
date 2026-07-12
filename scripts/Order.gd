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
## pass-through execution state lives here (relief_partner) instead of on both units.
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
}

## An order's internal choreography, for the phased case that already exists: a move into a
## unit's rear sector runs an about-face (conversio) in place, then -- when the order was issued
## with the reform-before-move drill -- REFORMS the ranks square to the new heading (so the
## fullest rank fronts it, not the old partial rear rank), and only then marches. Multiple phases
## of one queue entry, not multiple queue entries (docs/orders-queue-design.md, "Intra-order
## phasing"). Every other order type stays NONE; the mechanism exists so a later phase can add
## more phased orders without a new Order subtype.
enum Phase {
	NONE,   ## Not phased, or a phased order that hasn't started its first phase yet.
	TURN,   ## In-place about-face running before the march (move-to-rear only).
	MARCH,  ## Marching to the destination -- the phase every other MOVE order is in throughout.
	REFORM, ## Re-forming the ranks square to the new heading between the about-face and the
	        ## march (move-to-rear issued with reform-before-move on). Appended after MARCH so
	        ## recorded transcripts keep their phase values stable.
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
}

const PHASE_NAMES := {
	Phase.NONE: "NONE",
	Phase.TURN: "TURN",
	Phase.MARCH: "MARCH",
	Phase.REFORM: "REFORM",
}

var type: int = Type.MOVE
var phase: int = Phase.NONE

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
## RELIEF only: the tired ally this order is swapping with, while the pass-through
## exemption is live -- Unit._separation_exempt lets the pair interpenetrate as long as
## either side's current RELIEF order names the other. UnitRelief.update clears it (the
## swap has resolved) once the pair is apart or the partner has left the line, and the
## whole link dies with the order on an interrupt -- the swap's execution state lives
## here, not on the two units. null when idle or resolved. (target_uid still carries the
## ally's uid for the transcript; this is the resolved node the exemption compares.)
var relief_partner: Unit = null

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

# --- Macro grouping (Composability §2, "Macro expansion") ---------------------

## The group id every step of one Unit.enqueue_macro() call shares, so Unit.cancel_macro()
## can find and drop only that combo's own not-yet-executed remainder from the queue --
## see docs/orders-queue-design.md, "Macro expansion". -1 (the default) means this order
## was appended on its own, not as part of a combo.
var macro_id: int = -1


## Attach a guard to this order and return it, for a fluent call at the constructor site
## (e.g. `Order.new_move(dest).with_guard(Order.Guard.CONTACT_MADE)`). `param` and `uid`
## default to "unused" so most call sites only need the guard kind itself.
func with_guard(guard_kind: int, param: float = 0.0, uid: int = -1) -> Order:
	guard = guard_kind
	guard_param = param
	guard_uid = uid
	return self


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
