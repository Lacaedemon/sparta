class_name Order
extends RefCounted
## Phases 1-2 of the unified orders-queue design (docs/orders-queue-design.md): the
## `Order` value type. A queue entry describing one thing a `Unit` is doing or will do -- a
## verb, in the design doc's terms. Durable "mode" state (formation_mode, order_mode,
## stance, ...) stays on `Unit` itself; an Order is what writes it, not where it lives.
##
## Phase 2 makes the queue authoritative for the movement maneuvers: an in-place turn (the
## rear-move about-face phase, the standalone about-face/quarter-turn drills) and the wheel
## carry their own execution state here (turn_target / turn_start_facing / pivot), and a
## phased rear move carries its recorded reform choice and parks its march destination in
## target_pos until the turn completes. `Unit._think` reads and advances that state off
## `current_order`; the old parallel Unit fields (_conversio_target, _quarter_target,
## _wheel_target, _pending_march_*) are gone. The march plumbing itself (move_target /
## waypoints) and the targeting fields stay legacy until phase 3.

## The order kinds phases 1-2 cover. Most arrive via Battle's recorded/replayed
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
	NUDGE,      ## A short fixed-distance drill step (side-step or back-step), holding facing.
	FORMATION,  ## Change formation_mode (tight/loose/square/shield-wall/testudo). Instantaneous.
	FRONTAGE,   ## Resize frontage to an absolute file count (manual resize or a file-double/
	            ## file-halve maneuver -- same execution, different caller-derived target width).
	            ## Instantaneous.
	ABOUT_FACE,   ## Standalone conversio drill (V key): every soldier reverses 180° in place.
	              ## Created by Unit.conversio(), not recorded. Appended after the phase-1 types
	              ## so recorded transcripts keep their type values stable.
	QUARTER_TURN, ## Standalone quarter-turn drill (Q/E keys): every soldier pivots 90° in place.
	              ## Created by Unit.quarter_turn(), not recorded.
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
## WHEEL/NUDGE/QUARTER_TURN direction (Battle.NudgeDir for NUDGE; +-1 otherwise); 0 when unused.
var dir: int = 0
## The order_mode (Battle.OrderMode) the issuing command carried, for MOVE/ATTACK/SUPPORT.
var order_mode: int = 0

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


static func type_name(value: int) -> String:
	return TYPE_NAMES.get(value, "TYPE(%d)" % value)


static func phase_name(value: int) -> String:
	return PHASE_NAMES.get(value, "PHASE(%d)" % value)


## Readable one-line description for logs/transcripts, e.g. "MOVE:TURN" or "ATTACK".
func describe() -> String:
	if phase == Phase.NONE:
		return type_name(type)
	return "%s:%s" % [type_name(type), phase_name(phase)]


static func new_move(dest: Vector2, mode: int = 0) -> Order:
	var o := Order.new()
	o.type = Type.MOVE
	o.target_pos = dest
	o.order_mode = mode
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


static func new_formation(formation_mode: int) -> Order:
	var o := Order.new()
	o.type = Type.FORMATION
	o.formation = formation_mode
	return o


static func new_frontage(files: int) -> Order:
	var o := Order.new()
	o.type = Type.FRONTAGE
	o.frontage = files
	return o
