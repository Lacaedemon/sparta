extends Node2D
class_name Unit
## A regiment: one selectable token with a soldier count and morale.
## Renders itself via _draw() with per-type sprite shapes: infantry kite
## shield, spearmen hoplon + spear, cavalry horse + rider.
## Its soldier marks are flat geometric shapes when zoomed out and swap to
## detailed figure silhouettes (a standing soldier, a mounted rider) when the
## camera zooms in past LOD_ZOOM_IN — see _update_lod / UnitMeshes.figure_mesh.

enum State { IDLE, MOVING, FIGHTING, ROUTING, DEAD }

# Stable per-battle id (assigned by Battle.gd at spawn). Replays reference units
# by this so recorded orders survive scene reloads.
var uid: int = -1

# --- Tunable stats (set by Battle.gd when spawning) ---
@export var unit_name: String = "Spearmen"
@export var team: int = 0
@export var max_soldiers: int = 120
@export var attack: int = 12
@export var defense: int = 6
@export var move_speed: float = 90.0    # sprint pace (also the loadout's declared top speed)
# Walk/jog paces, in world units/s -- independent per-type values (Battle sets them
# from the loadout's walk_mps/jog_mps), not a fixed fraction of move_speed. Real gaits
# don't scale by a uniform ratio across unit types (a horse's walk/trot/gallop ratios
# look nothing like a human's walk/jog/sprint ratios), and load-carriage research shows
# a heavier panoply costs proportionally more at a run than at a walk. Defaults here
# match the old 0.5/0.75 fractions of the default move_speed, for bare test units that
# never get a loadout.
@export var walk_speed: float = 45.0
@export var jog_speed: float = 67.5
# Backward-walk speed factor: a soldier repositioning BACKWARD relative to his own
# facing (a common motion during a maneuver -- conversio, quarter-turn, frontage
# reshape -- where the rear ranks back up into new slots) is capped slower than one
# moving forward. Real troops shuffle backward at roughly half their forward pace,
# so a maneuver where men must back up takes longer than one where they step forward.
# Battle.gd sets this per-type from the loadout's "back_fraction" (see
# Battle._default_loadout). This 0.5 default is the fallback for a bare test unit
# that never gets a loadout.
@export var back_speed_fraction: float = 0.5
# Acceleration/deceleration, in world units/s^2 -- how fast this unit's actual speed
# ramps toward whichever pace it's targeting (see _current_speed below), instead of
# snapping there instantly. Independent per-type values (Battle sets them from the
# loadout's accel_mps2/decel_mps2), following the same panoply-weight reasoning as
# walk_speed/jog_speed: heavier kit accelerates slower, and decel > accel for foot
# troops (stopping needs no propulsive effort; starting does). Cavalry is symmetric --
# a galloping horse can't be reined in any faster than it can build up speed.
# Defaults are a middling (infantry-like) value for bare test units without a loadout.
@export var accel: float = 30.0
@export var decel: float = 60.0
# Effective melee reach, in world units (Battle sets it per weapon from reach_m;
# the 26 default is the infantry/sword baseline). A unit counts as in melee
# contact when the gap to its target closes within attack_range + both RADII, so a
# longer-reach weapon (a spear) reaches contact — and strikes — sooner than a
# shorter one (a sword) as the lines close.
@export var attack_range: float = 26.0
# Interned loadout type ids (see LoadoutRegistry): which weapon and shield TYPE
# this regiment's soldiers carry. Battle._spawn_unit sets them per type from the
# loadout table, and the per-soldier arrays (_sim_soldier_weapon_id /
# _sim_soldier_shield_id below) are seeded from them. Defaults are the infantry
# baseline (gladius + scutum), matching the attack_range default above, so a
# bare test unit spawned without a loadout still resolves to real types.
var weapon_type_id: int = LoadoutRegistry.WEAPON_GLADIUS
var shield_type_id: int = LoadoutRegistry.SHIELD_SCUTUM
@export var is_cavalry: bool = false
@export var anti_cavalry: bool = false   # spearmen: blunt cavalry charges
@export var is_ranged: bool = false   # archers: loose volleys from a distance
# Seconds before the unit starts executing a new order. Models the real-world
# lag between a signal and the regiment actually stepping off. Default 0.5 s;
# faster units (cavalry) can be given a lower value at spawn time.
@export var order_response_delay: float = 0.5
# Discipline and experience level (0.0 raw recruits → 1.0 veteran legionaries).
# Well-trained melee units cycle their ranks in combat: fresh files rotate to the
# front, which reduces fatigue buildup and sustains morale through prolonged fights.
@export var training: float = 0.0:
	set(v):
		training = clampf(v, 0.0, 1.0)

# --- Runtime state ---
var soldiers: int
var morale: float = 100.0
var fatigue: float = 0.0   # 0 fresh .. 100 exhausted; rotated out by relief
var cohesion: float = 1.0   # 1.0 gelled; drops on a merge, then ramps back
var state: int = State.IDLE
var facing: Vector2 = Vector2.DOWN
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
var target_enemy: Unit = null
var selected: bool = false
# The unified orders queue (docs/orders-queue-design.md). `current_order` (orders[0],
# or null when idle) is the single, transcript-visible source of truth for "what is this
# unit doing right now" -- including its active phase, for a phased order like the
# move-to-rear about-face. As of phase 2 the queue is AUTHORITATIVE for the movement
# maneuvers: an in-place turn (a rear move's about-face phase, the standalone
# about-face/quarter-turn drills) and the wheel keep their execution state on the Order
# itself (turn_target / turn_start_facing / pivot), _think advances it off current_order,
# and replacing or clearing the queue interrupts the maneuver in flight
# (_interrupt_current_order). As of phase 3 the queue is also authoritative for the ROUTE:
# a queued waypoint leg IS a queued MOVE order (there is no parallel waypoint list), with
# move_target/has_move_target kept as the in-flight leg's execution state, and a line
# relief's swap state lives on the RELIEF order (Order.relief_partner). The in-flight
# targeting references (target_enemy / support_target) stay unit fields: the reactive
# layer (enemy AI, auto-engage) writes target_enemy directly with no order behind it, so
# they are execution state the queue reads -- _update_current_order retires
# ATTACK/RELIEF/SUPPORT orders by reading them.
var orders: Array[Order] = []
var current_order: Order = null
# Order stance, set by Battle._apply_order_cmd from the order's mode.
# Int rather than Battle.OrderMode to keep Unit decoupled; 0 == OrderMode.NORMAL.
# The smart-order behaviours read this; NORMAL is current behaviour.
var order_mode: int = 0
# KNOCKBACK_FOCUS's own per-order parameter: how far a struck enemy body should be shoved.
# false (default) -- just clear the battle line -- is the common case; true pushes it much
# further. A genuine per-ORDER setting, not a global Settings toggle: Battle._apply_order_cmd
# refreshes it from the order's own "knockback_indefinite" field each time the stance is
# (re)armed or (re)issued (Ctrl+<key> writes it immediately; the plain hotkey arms it for the
# next move/attack order), so the player picks a variant every time they give the order. Read
# by SoldierMelee.resolve() only when order_mode == ORDER_KNOCKBACK_FOCUS; meaningless otherwise.
var knockback_push_indefinite: bool = false
var formation_mode: int = FORMATION_NORMAL
# Intra-unit rank-relief: whether rear ranks rotate forward to relieve their own unit's
# fighting line. A durable mode (the design doc's verbs-vs-modes split), written by a
# STANCE order, NOT a queue entry -- the rotation is standing behavior inside one unit,
# unlike the inter-unit RELIEF order where a fresh unit swaps with a tired ally. On by
# default (the historical behavior); UnitMorale gates the training-driven rank-cycle
# fatigue reduction and in-fight morale recovery on it, so turning it off makes a
# disciplined unit tire and waver like an untrained one.
var rank_relief: bool = true
# Which frontage the unit settles into after an engage/attack re-face turn-in-place
# (_settle_engage_turn) completes. KEEP_NEW_FRONTING is the shipped MVP: the men stay put
# and the unit fights with whatever edge the turn left facing the enemy. The other two
# layer a reshape on top of that same turn, reusing the frontage-resize grid-op
# (UnitFormation.files_for_halfwidth / set_frontage) so the reshape eases in via the
# soldier-body arrival dynamics exactly like a manual [ / ] resize -- no teleport, no new
# mechanism. RECREATE_WIDTH restores the file count the unit had before the turn (a wide
# line stays a wide line facing the new way); MATCH_TARGET instead adopts the enemy's own
# current file count (to the extent this unit's max_soldiers allows).
enum EngageReshapeMode { KEEP_NEW_FRONTING, RECREATE_WIDTH, MATCH_TARGET }
var engage_reshape_mode: int = EngageReshapeMode.KEEP_NEW_FRONTING
# Simulation tier (FormationTier.CLOSE / FAR) — the multi-resolution design's per-formation
# fidelity marker (docs/large-scale-simulation-design.md). CLOSE runs the full per-soldier
# path; FAR carries no per-soldier state at all — the soldier-layer steps skip it (see
# step_all_sim_soldiers / couple_all_sim_soldiers) and the flock render draws its marks on
# the formation grid instead. Battle evaluates the distance triggers each tick and performs
# the transitions (Battle._tick_tier_transitions -> TierTransition).
var tier: int = FormationTier.CLOSE
# Player-set frontage (number of files / columns); 0 means "auto", deriving the
# stable wider-than-deep grid from max_soldiers (UnitFormation.frontage). The
# player can widen or narrow the line via SelectionManager (keyboard + drag); the
# change rides the replay command stream so playback reproduces it. Honoured and
# clamped to [1, max_soldiers] in UnitFormation.frontage.
var frontage_override: int = 0
# Lateral (local X) shift applied on top of the centred formation grid, so an
# anchored (asymmetric) explicatio/duplicatio can hold one flank's edge fixed
# while the opposite flank grows or shrinks (UnitFormation.anchor_shift). 0.0 is
# the plain centred behaviour every other resize/reshape already has. Set once,
# absolutely, by Battle._apply_order_cmd (ORDER_FRONTAGE_ONLY carries it), so
# re-applying the pending order on the tick is idempotent like frontage_override.
var frontage_anchor_offset: float = 0.0
# "Close the ranks": whether the auto (non-override) frontage is currently
# stepped down a notch to reform the casualty-thinned survivors into a deeper, denser
# block instead of holding the full-strength line's width. A single cached bool, not a
# recomputed-every-call fraction check, so the step is a discrete ONE-TIME reflow at the
# threshold crossing rather than a continuous per-tick recompute (the same churn the
# stable-frontage design already avoids -- see UnitFormation.frontage's docstring).
# Updated once per tick in _physics_process via UnitFormation.should_close_ranks, which
# hysteresis-gaps the contract/recover thresholds so a unit hovering near the line
# doesn't flap back and forth. Ignored while frontage_override is set -- a player's
# explicit frontage always wins, same as the auto width it stands in for.
var _ranks_closed: bool = false
# Extra rotation (radians) applied to the formation slot grid, on top of the unit heading.
# A quarter-turn turns every soldier in place WITHOUT reorganising the grid: each man
# faces a new way but stands where he stood. unit.facing rotates 90°, and this offset cancels
# that rotation in soldier_world_slots so the slots stay put -- the men don't drift. 0 = the
# grid is square to the heading (the default). A fresh move order / rout reforms it to 0.
var _formation_angle: float = 0.0
# True for exactly one thing: a countermarch just performed by reform_ranks() after an about-
# face folded _formation_angle to ±PI. A single rigid rotation of the whole grid by ang (the
# normal soldier_world_slots formula) is a POINT reflection -- it negates both the file (lateral)
# and rank (depth) axes of every local slot, which is correct for holding a body's world position
# steady DURING the turn (that's the identity-holding invariant _settle_order_turn relies on),
# but wrong for the reform that follows: re-squaring the grid should only reverse rank order
# within each file (a countermarch), never swap a soldier to the opposite flank. While this flag
# is set, soldier_world_slots negates each local slot's file (x) coordinate before rotating by the
# CURRENT ang -- a depth-only reflection -- so a body that stood in the front rank on one flank
# lands in the rear rank on that SAME flank, matching real countermarch drill. Cleared by
# set_current_order() and _rout() (any fresh order or maneuver re-squares from a clean baseline,
# so a stale mirror must not compound with the next turn's own _formation_angle fold).
#
# Deliberately NOT cleared by _settle_engage_turn() or _face_dir()'s snap-absorb branch: those
# both fold a rotation into _formation_angle specifically to hold `ang` (soldier_world_slots'
# rotation) INVARIANT across the facing change, so bodies don't surge. This flag has no bearing
# on whether `ang` is invariant -- a mirrored slot rotated by the same `ang` is exactly as
# stable a mapping as an unmirrored one -- so leaving it alone there preserves that no-surge
# guarantee. Forcing it to a new value in the SAME tick `ang` is held constant flips every
# off-centre soldier's sign for that tick even though nothing about the rotation changed: the
# exact point-reflection bug this flag exists to fix, just triggered by an engage re-face or a
# large facing snap instead of a reform, for a unit still marching after a countermarched
# reform.
var _formation_mirror_x: bool = false
# Facing to pivot to once a move order's destination is reached, set by a
# drag-to-form-up order so the unit deploys facing the dragged line rather than its
# march direction. Vector2.ZERO means "keep the march facing" (no deploy turn).
var deploy_facing: Vector2 = Vector2.ZERO
# A commanded heading held throughout a move order so the unit translates toward
# its target WITHOUT turning to face travel -- the side-step maneuver (a small
# lateral shift shuffles sideways instead of pivoting). The unit also moves at a
# measured walk while this is set, to keep its ranks orderly. Vector2.ZERO means
# "face the travel direction" (the default turn-and-march), set per order in
# Battle._apply_order_cmd via UnitManeuver.
var ordered_facing: Vector2 = Vector2.ZERO
# Stance values from Battle.OrderMode that Unit's own behaviour reacts to, mirrored
# as plain ints to avoid a Unit<->Battle preload cycle (kept in sync with the enum;
# Battle._ready asserts they match). NORMAL is 0 (Unit's default order_mode).
#
# These ARE the reactive ROE (rules-of-engagement) modes the unified orders-queue design
# calls for (docs/orders-queue-design.md, "Standing conditional behavior = the mode
# layer"): durable Unit state a StanceOrder writes, that modifies how the CURRENT order
# executes rather than branching inside it. HOLD is "don't chase past what's already
# engaged" (the _think fallthrough at the bottom of the enemy branch skips the
# auto-advance-on-a-near-enemy path when order_mode == ORDER_HOLD); it does NOT suppress
# fighting or firing at whatever is already in range/contact, so "hold UNTIL in range THEN
# fire" needs no HOLD-specific carve-out -- a ranged unit fires at anything within
# RANGED_RANGE unconditionally (see the is_ranged branch below _think's ORDER_SUPPORT
# early return), i.e. fire-at-will is the default rather than a mode of its own.
# CYCLE_CHARGE is the caracole/repeated-charge ROE; SKIRMISH is the ranged kite-at-range
# ROE; ATTACK_FLANK/ATTACK_REAR bias the approach angle. Phase 4 is the promotion
# referenced above: these were a "crude version" per the design doc before the guard
# vocabulary (Order.Guard / OrderGuards.gd) gave the queue a first-class way to gate an
# order's own early completion on one of them.
# CHASE is relentless pursuit: it overrides the normal disengage-on-plain-move-order
# path (the _think fallthrough that lets a unit break contact/pursuit when it has no
# explicit target_enemy — see the in_contact/elif target_enemy branches below) so a
# chasing unit keeps closing on and re-engaging the SAME fleeing/repositioning enemy
# instead of peeling off to obey a later move order or drift onto a closer distraction.
# It does not change target ACQUISITION (UnitTargeting.current_target/nearest_enemy
# already let a pursuer keep and re-close on a routing enemy indefinitely); it changes
# what makes the unit let go of a target once it has one.
const ORDER_HOLD := 1
const ORDER_ATTACK_FLANK := 2
const ORDER_ATTACK_REAR := 3
const ORDER_SKIRMISH := 4
const ORDER_SUPPORT := 5
const ORDER_CYCLE_CHARGE := 6
const ORDER_SWEEP_ROUTERS := 7
const ORDER_ROLL_THE_LINE := 8
const ORDER_PIN_DOWN := 9
const ORDER_ALL_OUT_ATTACK := 10
const ORDER_CHASE := 11
const ORDER_WEDGE_CHARGE := 12
const ORDER_KNOCKBACK_FOCUS := 13

# Movement gait for a MOVE order (Battle.Gait), duplicated as plain ints for the same
# decoupling reason as the ORDER_* constants above: WALK (single click), JOG (double),
# RUN (triple), SPRINT (quadruple+). See Battle.gd's Gait enum.
const GAIT_WALK := 0
const GAIT_JOG := 1
const GAIT_RUN := 2
const GAIT_SPRINT := 3

# Formation modes: how tightly the regiment is packed, plus the two shielded
# close-order stances built on TIGHT's locked-shield density, and the two hollow-square
# (anti-cavalry ring) variants.
# TIGHT: soldiers close ranks — better missile defense (shields raised) and
#        better charge resistance, at the cost of a smaller footprint.
# NORMAL: default spacing.
# LOOSE: soldiers spread out — wider area coverage.
# SQUARE (orbis): the all-around defensive ring, tuned as a last-stand stance. Soldiers
#         face spears/shields outward on every side, so the unit presents no weak flank
#         or rear to cavalry: the flank/rear damage multiplier no longer applies against
#         it, and it braces a charge coming from ANY direction. The price is mobility (it
#         crawls) and reduced offensive output. Its distinguishing trait vs SCHILTRON is
#         morale: a ring making its last stand holds together better under losses
#         (ORBIS_MORALE_EROSION_RESIST).
# SCHILTRON: the same hollow-square geometry as SQUARE/orbis, but tuned as the cavalry
#         specialist — a denser hedge of levelled spears braces a charge harder than the
#         orbis does (a lower charge floor / stronger backfire), at the cost of hitting
#         even softer in return (SCHILTRON_ATTACK_FACTOR below SQUARE_ATTACK_FACTOR). No
#         morale bonus — unlike orbis, it isn't a last-stand stance, just the hard
#         anti-cavalry counter.
# SHIELD_WALL: shields locked edge-to-edge in a static line. Strong FRONTAL missile
#        and melee defense, but slow and immobile — a holding stance.
# TESTUDO: shields locked front, sides, and overhead. Very strong missile defense
#        from ALL directions, but very slow and weak in melee — a turtle vs arrows.
const FORMATION_NORMAL := 0
const FORMATION_TIGHT := 1
const FORMATION_LOOSE := 2
const FORMATION_SQUARE := 3
const FORMATION_SHIELD_WALL := 4
const FORMATION_TESTUDO := 5
const FORMATION_SCHILTRON := 6
# In tight formation, shields reduce incoming missile damage by this fraction.
const TIGHT_MISSILE_DEFENSE: float = 0.25
# In tight formation, this fraction of a cavalry charge bonus is absorbed
# (braced soldiers brace against the impact — not a full reversal like anti-cav).
const TIGHT_CHARGE_ABSORPTION: float = 0.55
# Shield wall: shields locked edge-to-edge cut incoming FRONTAL missile damage by this
# fraction (a flank/rear shot bypasses the wall and lands full). A braced wall also
# blunts frontal melee, cutting frontal melee damage taken by SHIELD_WALL_MELEE_DEFENSE.
const SHIELD_WALL_MISSILE_DEFENSE: float = 0.55
const SHIELD_WALL_MELEE_DEFENSE: float = 0.35
# Testudo: shields lock overhead too, so missile fire is blunted from EVERY direction
# by this fraction. But the men are packed head-down under cover and can barely fight,
# so their melee output is cut by TESTUDO_MELEE_PENALTY.
const TESTUDO_MISSILE_DEFENSE: float = 0.7
const TESTUDO_MELEE_PENALTY: float = 0.5
# The two shielded stances plant and barely move; their top pace is capped to this
# fraction of normal (shield wall creeps, testudo shuffles). NORMAL/TIGHT/LOOSE = 1.0.
const SHIELD_WALL_SPEED_SCALE: float = 0.4
const TESTUDO_SPEED_SCALE: float = 0.3
# Separation-radius scale factors per formation mode.
const TIGHT_SEPARATION_SCALE: float = 0.75
const LOOSE_SEPARATION_SCALE: float = 1.35
# Anti-cavalry square (orbis / schiltron). Both variants share the defining trait of
# all-around defence: no weak flank/rear facing vs cavalry. UnitCombat reads these
# (gated on in_square(), true for SQUARE and SCHILTRON alike):
#   * a squared unit takes NO flank/rear damage multiplier -- an attack from any
#     direction is treated as frontal (flank_multiplier returns 1.0). The ring
#     presents spears/shields on every side.
#   * a charge into the square backfires like set anti-cav spears from any direction --
#     the same speed-scaled reversal, floored at the variant's charge floor, so cavalry
#     can't find an open side to hit at full impact.
# The shared cost: mobility (SQUARE_MOVE_FACTOR of pace for both variants). Offence and
# charge-bracing strength diverge below -- that's what makes them distinct stances
# rather than one generic square.
const SQUARE_CHARGE_BACKFIRE: float = 0.5
const SQUARE_CHARGE_FLOOR: float = 0.6
const SQUARE_MOVE_FACTOR: float = 0.4
const SQUARE_ATTACK_FACTOR: float = 0.7
# Orbis: the last-stand ring. Its offence/charge-bracing sit at the original square's
# baseline numbers above; its distinguishing trait is morale (ORBIS_MORALE_EROSION_RESIST
# below) -- a regiment making its final stand holds its nerve better under losses.
# Erosion resistance: a fraction ORBIS_MORALE_EROSION_RESIST of the normal morale hit from
# a casualty is what actually lands (0.7 = 30% less morale erosion per casualty) --
# register_casualties scales base_erosion by this for a unit in orbis.
const ORBIS_MORALE_EROSION_RESIST: float = 0.7
# Schiltron: the cavalry specialist. A denser hedge of levelled spears braces a charge
# harder than the orbis does -- a lower floor and a stronger backfire, so cavalry that
# rides into a schiltron comes off worse than riding into an orbis -- at the cost of
# hitting even softer in return than the orbis's already-reduced offence. No morale bonus:
# unlike orbis this isn't a last-stand stance, just the hard anti-cavalry counter.
const SCHILTRON_CHARGE_BACKFIRE: float = 0.75
const SCHILTRON_CHARGE_FLOOR: float = 0.45
const SCHILTRON_ATTACK_FACTOR: float = 0.55
# Both the square (orbis) and the schiltron pack to the same close-order floor as TIGHT
# (shields locked outward), so they reuse TIGHT_SEPARATION_SCALE and keep spacing_scale
# at 1.0.
# Open-order grid-spacing scale. FORMATION_SPACING already sits at the historically
# attested close-order / locked-shield floor (~0.45 m per man) -- there's no
# historically grounded room to pack soldiers tighter than that, so TIGHT reuses the
# same floor (spacing_scale stays 1.0; its bonuses come from
# TIGHT_MISSILE_DEFENSE/TIGHT_CHARGE_ABSORPTION and the smaller separation_radius
# above, not from squeezing marks closer than any real formation ever stood). Only
# LOOSE widens the grid, to ~0.9 m per man -- matching the researched "room to wield
# a weapon" open-order figure.
const LOOSE_SPACING_SCALE: float = 2.0
# SHIELD_WALL and TESTUDO lock their shields edge-to-edge, so unlike TIGHT/SQUARE
# (which pack to the historical close-order floor and stop there) they squeeze the
# grid spacing BELOW that floor -- a real, measurable tightening of the block on top
# of their combat-multiplier bonuses above, not just a flag. TESTUDO packs tighter
# than SHIELD_WALL (an overhead-locked roof needs the men closer than a single-rank
# wall does).
const SHIELD_WALL_SPACING_SCALE: float = 0.75
const TESTUDO_SPACING_SCALE: float = 0.6
# Melee intermixing: a legacy softening of enemy separation for fighting non-hold
# units. Largely superseded by the engaged-enemy front-rank close-up in _separate
# (which lets lines meet at contact and the per-soldier collision set the spacing);
# kept as a fallback for the non-engaged path. Rise is fraction per second; decay is
# 4x faster so a unit that breaks contact re-solidifies promptly.
const MELEE_INTERMIX_RATE: float = 0.07
const MELEE_INTERMIX_DECAY_RATE: float = 0.28
const MELEE_INTERMIX_MAX: float = 0.85
# How hard a committed melee unit presses onto the enemy while fighting, as a fraction
# of move speed. The separation / engaged-enemy front-rank floor counters it, so the
# value only sets how fast the lines close to contact, not the final spacing.
# AUTO mode walks by default (walk_speed), jogs when a ranged enemy is within
# RANGED_RANGE (jog_speed, under fire), and sprints (move_speed) once within
# SPRINT_START_DISTANCE of the target. WALK mode holds walk pace throughout —
# mandatory for formed stances (shield wall, pike phalanx) that break on a jog.
const SPRINT_START_DISTANCE: float = 200.0   # px from target: start full-speed charge
# Below this current speed a unit counts as stopped for arrival purposes -- small enough
# not to read as motion (every pace/gait is well above it), but nonzero so a unit that has
# braked all the way down its arrival envelope finalizes its order instead of forever
# creeping the last fraction of a wu/s.
const ARRIVE_SPEED_EPSILON: float = 1.0
# The arrival envelope is derated below the brake authority by this factor. Tracking
# sqrt(2 * a * d) while only able to shed speed at exactly `a` is neutrally stable: any
# excess speed shrinks d faster, which drops the envelope faster than the unit can shed,
# and the gap grows all the way to the destination. Demanding a decay the shed rate beats
# by a margin makes the ramp lock onto the envelope from above and hold it exactly.
const ARRIVAL_ENVELOPE_MARGIN: float = 0.8
# Orderly move orders pivot the block about its centre toward their travel direction at
# this angular rate (rad/s) rather than snapping, so the ranks turn in good order. A
# half-circle (180°) centre pivot takes ~PI / TURN_RATE seconds. Combat chases still snap
# (they pass orderly = false to _move_to). TURN_RATE is the rate at a stand -- an orderly
# march pivot tapers this down as the unit's current speed rises (real turning capacity is
# bounded by the lateral force a moving body/formation can exert without losing footing or
# cohesion), never dropping below TURN_RATE_TAPER_FLOOR of the stationary rate. A first-cut
# linear taper; the deeper pivot-radius/cohesion mechanics of an actual wheel maneuver are
# a dedicated maneuver (the circumductio flank wheel, see wheel()), not this general movement taper.
const TURN_RATE: float = PI
const TURN_RATE_TAPER_FLOOR: float = 0.4
# Conversio (drill about-face): every soldier turns in place to reverse, so unit.facing
# rotates toward the opposite heading at this rate (rad/s), taking ~0.5 s for a full 180°.
# This is NOT a pivot of the block — neither a centre pivot (move orders) nor a flank wheel
# (circumductio); each man simply turns where they stand. The arrival term in
# SoldierBodies.step is dropped while the turn runs, so soldiers stay at their grid positions
# despite the facing change — they rotate without drifting.
const CONVERSIO_TURN_RATE: float = PI * 2.0
# Wheel (circumductio) swing rate: a stately quarter-circle over ~1 s. Deliberately slower than
# the in-place CONVERSIO_TURN_RATE — the far flank actually MARCHES the arc (the whole regiment
# rotates rigidly about the hinge), so a fast rate would fling the outer files across the field.
# At this rate even the outermost file covers only a few px per tick, so the line reads as a door
# swinging on its hinge rather than a whip-around.
const WHEEL_TURN_RATE: float = PI * 0.5

const MELEE_PRESS_FRACTION: float = 0.6
# Skirmish: a kiting ranged unit backs off when a threat closes inside this
# distance, instead of standing to fire. Above melee contact (~62) and below
# RANGED_RANGE (160) so there's room to fire before being caught.
const SKIRMISH_KITE_DISTANCE: float = 100.0
# Cycle charge (caracole): a melee unit charges its target, lands the impact strike,
# then peels back to CYCLE_CHARGE_STANDOFF away to re-form before charging again — so
# it keeps trading momentum-scaled charge hits instead of grinding in a static melee
# where the charge bonus is spent. The unit switches from "recharging" (pulling back)
# to "charging" once it has opened at least this far, and back to recharging on the tick
# it makes contact and strikes. Set beyond SPRINT_START_DISTANCE (200) by enough runway
# that the next run reaches full sprint before contact: the charge bonus scales with the
# closing speed carried into the strike, and _move_to only sprints inside
# SPRINT_START_DISTANCE, so a standoff at (or just past) that line would land each cycle
# at a walk. 280 leaves ~80px of sprint build-up ahead of the ~62px contact.
const CYCLE_CHARGE_STANDOFF: float = 280.0
# Support: a unit ordered to guard a friendly "ward" engages any enemy that
# closes within SUPPORT_GUARD_RADIUS of the ward, otherwise shadows the ward,
# holding station SUPPORT_FOLLOW_DISTANCE off so it doesn't pile onto it. The guard
# radius is near DETECTION_RANGE (190) so it meets threats about as far as it would
# normally spot them; the follow distance sits just past two footprints (~36).
const SUPPORT_GUARD_RADIUS: float = 180.0
const SUPPORT_FOLLOW_DISTANCE: float = 80.0
# The friendly unit a SUPPORT order tells this one to guard (set by Battle from the
# order's target). Cleared when it dies/routs, reverting this unit to NORMAL.
# Pace mode: when true the unit always walks (walk_speed), overriding the
# AUTO escalation to jog/sprint. Set from the walk_advance setting at order time.
var walk_advance: bool = false
# Set to true in _think when a ranged enemy is within RANGED_RANGE; drives the
# AUTO-pace jog escalation. Cleared each frame before the check.
var _under_fire: bool = false

var support_target: Unit = null
# Field rectangle the unit keeps inside when kiting (set by Battle on spawn). The
# default is effectively unbounded so direct Unit tests don't need to set it.
var field_bounds: Rect2 = Rect2(-100000, -100000, 200000, 200000)
# Wider rectangle a ROUTING unit may flee into before it escapes for good (set by
# Battle on spawn, grown from field_bounds by a retreat margin). Non-routing behavior
# (including skirmisher kiting) still uses field_bounds, unaffected by this. The
# default matches field_bounds's effectively-unbounded default so direct Unit tests
# don't need to set it.
var retreat_bounds: Rect2 = Rect2(-100000, -100000, 200000, 200000)

const RADIUS: float = 18.0
const DETECTION_RANGE: float = 190.0
# How often a melee unit applies a damage tick. This is the regiment's *aggregate*
# cadence — one tick stands for the whole front rank trading blows over that span,
# not a single soldier's swing — so it's tuned for battle pace, not literal sword
# strikes per second. (Per-soldier strike timing would come with the individual-
# soldier layer; see docs/individual-collision-design.md.)
const ATTACK_INTERVAL: float = 0.6
# Pin down / stall: a defensive attack stance that trades attack tempo for a brief,
# self-inflicted exposure window. A pinning unit swings roughly half as often as the
# baseline melee/ranged cadence (PIN_DOWN_ATTACK_INTERVAL vs. ATTACK_INTERVAL/
# RANGED_INTERVAL) -- committing to a stall rather than a normal press -- but for
# PIN_DOWN_EXPOSURE_DURATION after each swing, the follow-through leaves it open:
# its own defense is scaled by PIN_DOWN_DEFENSE_FACTOR (see pin_down_defense_factor())
# for any hit landed while _pin_down_exposure_cd is still counting down. So the
# stance is a genuine tradeoff -- fewer, slower attacks for the unit itself, not a
# pure defensive buff -- rather than a strict upgrade over the normal stance.
const PIN_DOWN_ATTACK_INTERVAL: float = 1.2
const PIN_DOWN_EXPOSURE_DURATION: float = 0.3
const PIN_DOWN_DEFENSE_FACTOR: float = 0.7
const ROUT_TIME: float = 6.0
# How long a non-fighting unit holds position to reform its ranks after a fresh move
# order is issued with reform_before_move on. Runs concurrently with order_response_delay
# (both count from zero); the effective delay before the march is max(order_response_delay,
# REFORM_DURATION). Deterministic (a plain counter, no RNG), so replays stay exact.
const REFORM_DURATION: float = 0.8
# A body within this distance of its slot counts as formed up, for the post-about-face
# reform's "ranks have re-formed" check. Loose enough that couple()'s tiny centre drift
# can't stall the check, far tighter than a rank gap (FORMATION_SPACING is 9).
const REFORM_SETTLE_EPS: float = 1.0
# Radius over which a rout shakes friendly morale. Shared by the morale-spread
# loop and the cosmetic shockwave so the visual matches the actual area of effect.
const ROUT_SHOCK_RADIUS: float = 140.0
# Rout recovery: when a unit's rout timer runs out it RALLIES — recovers to your
# control — if it has broken contact (no living enemy within RALLY_CONTACT_RADIUS) and
# still fields enough men (>= SHATTER_STRENGTH_FRAC of its max). Otherwise it SHATTERS:
# run down or gutted past reforming, it leaves play for good. A rallied unit comes back
# at RALLY_MORALE, kept low so it stays fragile and can break again.
const RALLY_CONTACT_RADIUS: float = 160.0   # = RANGED_RANGE: in archer reach = not broken contact
const RALLY_MORALE: float = 30.0
const SHATTER_STRENGTH_FRAC: float = 0.15
# While routing, a shaken regiment's nerve slowly steadies: morale ticks UP toward
# ROUT_RALLY_BASELINE at a rate proportional to the remaining gap, so recovery is fast
# at first and levels off (an asymptotic approach, never quite reaching the baseline).
# A unit that breaks contact and steadies past RALLY_MORALE_THRESHOLD rallies on the spot —
# it need not run the full ROUT_TIME nor reach the map edge to return to play. The baseline
# sits above the threshold so a clear unit reliably crosses it before the timer runs out.
# Rates are deterministic (gap-proportional, delta-driven, no RNG), so replays stay exact.
const ROUT_RALLY_BASELINE: float = 45.0
const ROUT_MORALE_RECOVER_RATE: float = 0.25   # fraction of the gap closed per second
const RALLY_MORALE_THRESHOLD: float = 35.0

# Ranged combat. A ranged unit looses volleys at any enemy within
# RANGED_RANGE that isn't already in melee contact — far outreaching melee's
# ~62px contact, so archers skirmish from safety. RANGED_RANGE stays below
# DETECTION_RANGE so an auto-acquired target is always in detection too. Volleys
# fire on their own (slower) cadence and hit a touch softer per shot than melee.
const RANGED_RANGE: float = 160.0
const RANGED_INTERVAL: float = 1.0
const RANGED_DAMAGE_FACTOR: float = 0.7

# Fatigue builds while FIGHTING and recovers while resting; it bites into attack
# so rotating tired regiments out via line relief is a real tactical lever.
# Rates are tuned to real time (move speeds are real m/s, SPEED_SCALE = 1.0):
# sustained melee wears a unit down over minutes, not seconds. At FATIGUE_PER_SEC
# an untrained unit reaches full exhaustion after ~2.4 min of unbroken fighting
# (a meaningful ~20% attack penalty after ~1.2 min), and recovers fully after
# ~3.3 min of rest -- so relief is worth committing to but not constant churn.
const FATIGUE_PER_SEC: float = 0.7
const FATIGUE_RECOVER_PER_SEC: float = 0.5
const FATIGUE_MAX_ATTACK_PENALTY: float = 0.4
# Rank cycling: well-trained melee units rotate fresh files to the front, reducing
# effective fatigue buildup. At training=1.0, buildup is halved. Ranged units don't
# cycle ranks (they fire from static lines), so the reduction only applies to melee.
const RANK_CYCLE_FATIGUE_REDUCTION: float = 0.5
# Wedge charge (an attack-order subtype): trades defense (UnitCombat's
# WEDGE_CHARGE_DEFENSE_PENALTY) and faster fatigue buildup for a quicker approach, aiming
# to punch a hole in the enemy line before it can brace. 1.3x pace and 1.5x fatigue
# buildup are deliberately less extreme than all-out-attack's combat-only tradeoff, since
# this stance's cost lands continuously (every tick of movement AND fighting) rather than
# only while fighting.
const WEDGE_CHARGE_SPEED_BONUS: float = 1.3
const WEDGE_CHARGE_FATIGUE_MULT: float = 1.5
# A well-trained unit also sustains its morale while fighting — the visible discipline
# of rotation keeps the formation steady. Threshold is the minimum training for any
# morale recovery to kick in; at threshold it's minimal, scaling up to full at 1.0. This
# is a RATE lever, not immunity: UnitMorale.tick_morale additionally scales the recovery
# by the regiment's remaining strength ratio, so it shrinks toward 0 as the unit bleeds —
# a disciplined unit holds out longer under sustained casualties, but every unit still has
# a reachable rout threshold; higher training just costs the attacker more losses/time.
const RANK_CYCLE_MORALE_THRESHOLD: float = 0.5
const RANK_CYCLE_MORALE_PER_SEC: float = 1.2
# Once a regiment has thinned past this remaining-strength ratio it is CRUMBLING
# (UnitCombat.register_casualties adds an extra morale penalty below it): too few files
# left to rotate fresh men to the front, so rank-cycling can no longer sustain morale
# either -- tick_morale gates its in-fight recovery off at the same ratio. Shared so the
# two effects switch on/off together instead of drifting out of sync.
const MORALE_CRUMBLE_RATIO_THRESHOLD: float = 0.4
# Base per-casualty morale erosion (UnitCombat.register_casualties) is FRACTION-of-force
# scaled, not a flat per-head amount: losing `total` soldiers costs
# `(total / max_soldiers) * MORALE_LOSS_PER_FULL_LOSS` morale, so a percentage loss costs
# the same morale regardless of the regiment's roster size. A flat per-head cost (the old
# design) let a big-roster elite unit rack up hundreds of casualties for a trivial total
# morale hit -- mathematically incapable of reaching 0 morale before the regiment was wiped
# out. Set below 100 so erosion alone, even at total wipeout, doesn't quite force a
# rout on its own -- the thin-regiment crumble (below) and the in-fight recovery cutoff at
# the same ratio finish the job before the last man falls.
const MORALE_LOSS_PER_FULL_LOSS: float = 90.0
# The crumble penalty is ALSO fraction-of-force + casualty-count scaled (not a flat
# per-event amount): once ratio < MORALE_CRUMBLE_RATIO_THRESHOLD, each casualty's base
# erosion (above) is multiplied by up to (1 + MORALE_CRUMBLE_BOOST) as the regiment
# bottoms out, ramping linearly from x1 at the threshold to the full boost at ratio 0. A
# flat per-event crumble bonus (the old design) rewarded FREQUENT SMALL casualty batches
# with more total crumble erosion than a few large ones for the same total losses --
# fraction-scaling it ties the crumble effect to how much of the regiment is actually gone,
# independent of how casualties happen to be batched per tick.
const MORALE_CRUMBLE_BOOST: float = 4.0

# Morale recovers slowly when a unit is not engaged in combat, rewarding
# players who pull battered regiments back from the line to rest.
const MORALE_RECOVER_PER_SEC: float = 2.0

# Merging two regiments starts the result with a "strangers" cohesion debuff
# (scales attack) that ramps back to full as the merged unit gels.
const MERGE_COHESION_FLOOR: float = 0.6
const COHESION_RECOVER_PER_SEC: float = 0.1

# Per-type collision footprint: the center-to-center separation floor used in
# _separate(). RADIUS stays the visual/contact size; this is purely the body
# width for crowding, assigned per type in _ready(). Each stays below that type's
# melee contact (its attack_range + both RADII) so units still press into contact
# instead of bouncing apart. Cavalry are bulkier; spearmen a touch wider than
# infantry. (Spears reach far past their footprint; the foot-sword baseline,
# floor 36 < contact 62, is the tightest melee case.)
const SEPARATION_RADIUS_INFANTRY: float = 18.0
const SEPARATION_RADIUS_SPEARMEN: float = 20.0
const SEPARATION_RADIUS_CAVALRY: float = 24.0
# Hard ceiling on a footprint (merging widens it). Two maxed units floor at
# 2*28 = 56, still under the melee reaches of the foot/horse types (sword
# contact 62, spear far more), so even merged mega-units keep pressing into
# contact. (Archers carry a short sidearm by design and fight at range, so the
# pathological case of two maxed archer blobs is not a melee concern.)
const SEPARATION_RADIUS_MAX: float = 28.0

# Cavalry charge: a physics-based bonus, not a one-shot token. The damage
# multiplier scales with the rider's IMPACT VELOCITY at the moment of contact — the
# component of its approach velocity aimed straight at the target — so both closing
# speed and angle matter. Calibrated so a full-speed head-on gallop (~a cavalry's
# move_speed) lands roughly the old flat +0.8 (x1.8 damage); a shallow angle or a
# near-stationary unit (e.g. a shadowing supporter) earns proportionally less,
# down to nothing. Deterministic (positions + move_speed only) so replays stay exact.
const CHARGE_BONUS_AT_REF_SPEED: float = 0.8
# Reference closing speed at which a head-on charge yields the full bonus above. An
# independent balance knob, NOT a hard link to Battle: it's set near a typical cavalry
# gallop (~170 = the loadout's 8.5 m/s * Battle.WORLD_UNITS_PER_METER 20) so a full
# charge ~matches the intended x1.8, but it's a plain literal on purpose — deriving it
# from Battle's constants would reintroduce the Unit<->Battle preload cycle this file
# avoids elsewhere. Changing cavalry speed just rescales the charge (faster hits harder,
# by design); nothing breaks. The bonus always scales with the unit's own gallop
# (speed_toward <= move_speed): a cavalry at the reference speed peaks at the reference
# x1.8, and a faster one exceeds it on purpose — intended scaling, not a cap (no assert).
const CHARGE_REFERENCE_SPEED: float = 170.0
# Anti-cavalry spearmen brace and turn the charge against the rider: the momentum
# becomes a speed-scaled PENALTY (impaling yourself at a gallop hurts) instead of a
# bonus, floored so even a full charge into spears never drops below the old x0.6.
const ANTI_CAV_CHARGE_BACKFIRE: float = 0.5
const ANTI_CAV_CHARGE_FLOOR: float = 0.6

var _attack_cd: float = 0.0
# Counts down from PIN_DOWN_EXPOSURE_DURATION after a PIN_DOWN strike/shot lands;
# while positive, pin_down_defense_factor() reports the unit's own lowered defense.
# Unrelated to (and ticks independently of) _attack_cd -- the two windows overlap
# but PIN_DOWN_ATTACK_INTERVAL is tuned longer than PIN_DOWN_EXPOSURE_DURATION, so
# the exposure always closes well before the next swing is even possible.
var _pin_down_exposure_cd: float = 0.0
var _rout_timer: float = 0.0
# A ROUTING unit starts "broken" (this false): its morale still recovers and it can
# rally back to control. If it runs out of time still in contact, or too gutted to
# reform, it's SHATTERED (this true): it keeps fleeing but can never again recover
# morale or rally --- the only way out from there is to escape (see _shatter()/_escape()).
# Reset false at the top of every fresh _rout(), so a unit that rallies can break again.
var _shattered: bool = false
# Counts down after a new order is received; the unit holds its current action
# until this reaches zero. A fighting unit ticks it down but is not gated by it
# (it keeps executing _think() — retargets, disengages, and support orders all
# take effect immediately regardless of the timer).
var _order_response_timer: float = 0.0
# Reform-before-move: when a fresh move order arrives with "reform":true, the
# destination is stored here and _reform_timer counts down. Until it expires the
# unit holds position (IDLE); on expiry _commit_pending_reform() sets has_move_target.
# A subsequent order clears the timer, cancelling the pending reform.
var _reform_target: Vector2 = Vector2.ZERO
var _reform_timer: float = 0.0
var _moved_last_frame: bool = false
# This unit's actual travel velocity (direction + magnitude, world units/s) — not a
# combat-only quantity, just historically under-documented as one: the cavalry charge
# bonus (UnitCombat.charge_multiplier) reads it at contact, but so does the soldier-body
# march feed-forward (SoldierBodies.step) and the closing-speed term in SoldierMelee.
# _strike spends it on the contact-making strike (so only that first strike charges, not
# the grinding strikes after); otherwise, while idle, it decays in lockstep with
# _current_speed below rather than snapping to zero — one friction rule, not a separate
# instant "combat balance" reset (see the decay guard in _physics_process). Kept
# untouched while FIGHTING so a strike delayed by attack cooldown still lands it.
var _approach_velocity: Vector2 = Vector2.ZERO
# This unit's actual current speed (world units/s, unsigned), ramping toward whichever
# pace _move_to selects via accel/decel rather than snapping there. Bleeds off gradually
# (friction, not a snap) in lockstep with _approach_velocity above whenever the unit isn't
# actively locomoting this tick — see the decay guard in _physics_process.
var _current_speed: float = 0.0
# Read-only public view of the ramping speed above, for consumers outside this script
# (the order overlay's speed label). Keeps _current_speed private while giving readers a
# clean public name, matching the other cross-script unit reads (global_position, team, …).
var current_speed: float:
	get: return _current_speed
# Velocity the regiment center followed its soldiers' centroid at this tick (phase 5):
# the soldier->regiment coupling slides the center toward where its bodies actually are,
# so friendly collision (and later all collision) emerges from the soldier layer. Stored
# for diagnostics/tests; the move itself happens in SoldierBodies.couple, bounded so it
# never teleports.
var _body_follow_vel: Vector2 = Vector2.ZERO
# Cycle-charge phase: true while the unit is peeling back to its standoff after a
# charge, false while it's driving in for the next charge. Flipped by
# _cycle_charge_tick — set on the contact strike, cleared once the unit has opened
# to CYCLE_CHARGE_STANDOFF. Meaningful only while order_mode == ORDER_CYCLE_CHARGE.
var _cycle_recharging: bool = false
var team_color: Color = Color.WHITE
# Collision footprint for _separate(); assigned per type in _ready().
var separation_radius: float = SEPARATION_RADIUS_INFANTRY
# The merge-aware "base" footprint at Normal formation — updated on spawn and
# whenever absorb() widens separation_radius. set_formation(NORMAL) restores to
# this rather than to the raw type constant, so a merged unit doesn't silently
# lose its widened body on a formation cycle.
var _base_separation_radius: float = SEPARATION_RADIUS_INFANTRY
# Density scale for the formation grid itself: set_formation() sets this alongside
# separation_radius, so LOOSE (open marching order) actually spreads soldiers out --
# not just widens an abstract collision footprint. TIGHT stays at 1.0 (see
# LOOSE_SPACING_SCALE above for why there's no tighter-than-default grid spacing).
# UnitFormation.slots() and _front_depth() read it; the files/ranks count itself
# never changes, only the spacing between them.
var spacing_scale: float = 1.0
# Rises while this unit is locked in mutual melee (both FIGHTING, neither HOLD).
# Scales down the separation push vs. matched enemies so units gradually intermix.
var _combat_intermixing: float = 0.0

var _flock_color: Color = Color(0, 0, 0, 0)     # last body modulate applied to the marks
var _block_extent: float = RADIUS       # block half-size; sizes the ring/halo/bars/shadow
# Render fast-path bookkeeping. _render_dirty is raised by SoldierBodies.step whenever a
# body actually moves (and by seed / about-face relabel); _process consumes it so the
# MultiMeshes are only rewritten when something visible changed, not every idle frame.
# The extent inputs (soldier count, frontage) are cached so the shadow/chrome recompute —
# and its PackedVector2Array alloc — only runs when the formation footprint changes.
var _render_dirty: bool = true
var _render_last_facing: Vector2 = Vector2.DOWN
# Routing/normal translucency the regimental FLAG fades toward -- the flag is the one
# element that reads a unit's morale state (a wavering standard), not the soldiers
# themselves: the per-soldier marks/figures and the rest of the chrome (bars, state ring,
# shield overlay) always stay fully opaque regardless of routing, so the men themselves
# never look see-through. Never read directly for the flag's draw color -- _render_alpha
# (below) is what actually eases toward this target each tick, so a routing transition
# never jumps straight to 0.45 (or back to 1.0) in a single frame.
const ROUTING_ALPHA: float = 0.45
# Per-second rate _render_alpha eases toward its target (an active fade, not a snap) --
# fast enough to read as an immediate response to the state change, slow enough to
# actually be visible as a fade rather than an instant cut.
const ALPHA_FADE_RATE: float = 2.0
var _render_alpha: float = 1.0
# Tracks the last _render_alpha _draw() was invoked with, so _process can request a
# redraw only while the flag is actually mid-fade (not every idle tick).
var _render_last_alpha: float = 1.0
var _render_extent_n: int = -1
var _render_extent_frontage: int = -1
var _render_extent_mode: int = -1
var _mm_body: MultiMesh = null
var _mm_outline: MultiMesh = null
var _mmi_body: MultiMeshInstance2D = null
var _mmi_outline: MultiMeshInstance2D = null
# Per-soldier facing pip (figure LOD only): the figure silhouette only mirrors
# left/right (a full body rotation would look broken on a side-view figure), so a
# facing change that isn't left/right is otherwise invisible zoomed in. This
# small directional mark rotates freely to the soldier's actual facing, on top of
# (not instead of) the figure. Hidden at mark LOD -- the mark itself already rotates.
var _mm_facing_pip: MultiMesh = null
var _mmi_facing_pip: MultiMeshInstance2D = null
var _facing_pip_mesh: ArrayMesh = null
var _shadow: Polygon2D = null
# Both level-of-detail variants of the body/outline meshes, built once in
# _setup_flock_renderer and swapped on the MultiMeshes as the camera zooms.
var _mark_body_mesh: ArrayMesh = null       # flat geometric mark (zoomed out)
var _mark_outline_mesh: ArrayMesh = null
var _figure_body_mesh: ArrayMesh = null     # detailed figure silhouette, facing right (zoomed in)
var _figure_outline_mesh: ArrayMesh = null
var _figure_body_mesh_flip: ArrayMesh = null     # same figure mirrored to face left
var _figure_outline_mesh_flip: ArrayMesh = null
var _detailed_lod: bool = false             # true while the figure meshes are active
var _figure_faces_left: bool = false        # which mirror is on the MultiMeshes (figure LOD)
# The cosmetic mark/figure mesh geometry lives in UnitMeshes (built once, shared and
# cached across all units); this node just holds the per-unit mesh handles below.


func _ready() -> void:
	soldiers = max_soldiers
	team_color = Color("4a7fd6") if team == 0 else Color("d65a4a")
	separation_radius = _type_separation_radius()
	_base_separation_radius = separation_radius
	add_to_group("units")
	# Layer budget: field=0, then this unit's cosmetic stack sits 1..3 — shadow (eff 1),
	# marks (eff 2), chrome (this _draw, eff 3) — all below the z=4 rout shockwave / z=5
	# volley trails / z=100 selection box. The marks/shadow are child nodes (MultiMeshes /
	# Polygon2D) layered just under this node via their relative z_index (Stage B).
	z_index = 3
	_setup_flock_renderer()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if state == State.ROUTING:
		_process_rout(delta)
		if state != State.DEAD:   # timer expired: rallied (IDLE) or shattered (DEAD -> freed)
			_separate()   # routers still shoulder past anyone in their path
		return

	_attack_cd = max(0.0, _attack_cd - delta)
	_pin_down_exposure_cd = max(0.0, _pin_down_exposure_cd - delta)
	_moved_last_frame = false

	_think(delta)
	_tick_intermixing(delta)

	# Units are solid: resolve any overlap so an advancing regiment can't
	# walk straight through (or over) the one in front of it.
	_separate()

	UnitMorale.tick_fatigue(self, delta)
	UnitMorale.tick_cohesion(self, delta)
	UnitMorale.tick_morale(self, delta)
	tick_engaged(delta)
	UnitRelief.update(self)
	_ranks_closed = UnitFormation.should_close_ranks(_ranks_closed, soldiers, max_soldiers)

	# A stationary, non-fighting unit's momentum bleeds off under the same friction as an
	# orderly arrival (arrival_brake_rate(), the rate _move_to's own braking branch uses) —
	# whenever the unit isn't actively locomoting this tick (no _move_to call). _current_speed
	# ramps down instead of snapping to zero, and _approach_velocity — the unit's actual
	# travel velocity (SoldierBodies' march feed-forward and UnitCombat's charge bonus both
	# already read it as such; it was never combat-only, just under-documented as one) —
	# decays in lockstep: same direction, magnitude rescaled to the new _current_speed. No
	# separate instant "combat balance" reset — one velocity, one friction rule, kinematic
	# and cosmetic together. While FIGHTING this whole block is skipped, so a strike held
	# back by attack cooldown on the contact frame still charges on the next (_strike itself
	# spends the velocity on that first contact — see UnitCombat.strike — so grinding
	# strikes after don't re-charge).
	#
	# Kinematic, not cosmetic: residual speed actually coasts the unit forward as it decays,
	# mirroring _move_to's own effective_speed/advance/field-bounds-clamp, so a stopping unit
	# visibly slides to rest instead of a decaying number sitting frozen in place.
	#
	# Direction of travel is its own quantity, distinct from `facing` (visual/formation
	# orientation) -- the two can differ (an orderly march pivots facing gradually onto
	# its heading, so mid-turn the body still points somewhere other than where it's
	# actually moving). Read _approach_velocity's direction before rescaling its magnitude
	# below, rather than substituting `facing` (which would coast the unit toward whatever
	# it happens to be oriented at, not where it was actually headed). Rescaling instead of
	# zeroing also keeps that direction valid on every subsequent idle tick, so a multi-tick
	# coast to a full stop follows one consistent heading rather than losing it after the
	# first tick.
	#
	# Guard on both freeze timers too: a unit that was actively cruising and gets
	# re-ordered is frozen by start_order_response() for order_response_delay seconds,
	# and (for a normal move order with the default Settings.reform_before_move) then
	# held again by the reform-before-move hold for REFORM_DURATION (see _think below)
	# — _move_to() doesn't run during either freeze, so _moved_last_frame reads false
	# even though the unit had momentum a moment ago. The two holds run one after the
	# other (order-response first, then reform), so both must have drained before this
	# decay is safe to apply. Without this guard, every re-order (a rapid tap sequence,
	# or any fast order dispatch) would bleed speed away and force the next march to ramp
	# up from a near-standstill each time instead of carrying momentum through. A
	# genuinely idle unit already has _current_speed == 0, so skipping this while frozen
	# is a no-op for it — this only changes behavior for a unit that was moving.
	if not _moved_last_frame and state != State.FIGHTING \
			and _order_response_timer <= 0.0 and _reform_timer <= 0.0:
		var travel_dir: Vector2 = _approach_velocity.normalized() \
				if _approach_velocity.length_squared() > 0.0001 else Vector2.ZERO
		# UnitCombat's "spend the charge" strike-resolution reset can zero
		# _approach_velocity on the exact tick a unit's last opponent dies and it drops
		# out of FIGHTING with _current_speed still nonzero -- direction is lost with no
		# _move_to call left to rebuild it. Fall back to `facing`: at this instant the
		# unit was just fighting head-on, so its facing is a faithful stand-in for the
		# travel heading that was spent, and this only ever applies in that anomalous
		# zero-velocity/nonzero-speed state, never to a unit still under normal control.
		if travel_dir == Vector2.ZERO and _current_speed > 0.0:
			travel_dir = facing
		_current_speed = move_toward(_current_speed, 0.0, arrival_brake_rate() * delta)
		# Terrain-scaled, matching _move_to's own effective_speed -- a unit coasting to a
		# stop in a forest carries proportionally less real velocity, just like one still
		# under active order control, so downstream consumers (the march feed-forward, the
		# charge-bonus dot product) see a consistent value regardless of which code path
		# last touched _approach_velocity.
		var terrain_speed: float = PathField.active.speed_at(position) \
				if PathField.active != null else 1.0
		_approach_velocity = travel_dir * (_current_speed * terrain_speed)
		if _current_speed > 0.0 and travel_dir != Vector2.ZERO:
			position += travel_dir * (_current_speed * terrain_speed * delta)
			position.x = clampf(position.x, field_bounds.position.x, field_bounds.end.x)
			position.y = clampf(position.y, field_bounds.position.y, field_bounds.end.y)

	# The parallel soldier-body layer (seeding + the global engaged-soldier
	# separation) is orchestrated once per tick by Battle, AFTER every unit has
	# settled this frame — see Battle._on_soldier_tick. It's non-authoritative
	# (nothing in combat/movement/morale reads _sim_soldier_pos), so it changes no
	# gameplay; the debug overlay in _draw shows it. See docs/individual-collision-design.md.
	queue_redraw()


## Replace the orders queue with a single fresh order (a plain, non-append order): interrupts
## whatever maneuver the outgoing order had in flight, clears any queued continuation, and
## makes `order` current immediately. Mirrors the legacy "a fresh order discards the queued
## route" rule (see Battle._apply_order_cmd).
func set_current_order(order: Order) -> void:
	_interrupt_current_order()
	var q: Array[Order] = []
	if order != null:
		q.append(order)
	orders = q
	current_order = order
	# A fresh order always re-squares from a clean baseline (see start_order_response, called
	# right after this for every dispatched order): a stale countermarch mirror must not
	# compound with whatever fold the new order's own maneuver applies to _formation_angle.
	_formation_mirror_x = false


## Append `order` to the queue tail (a shift-click waypoint leg). If the unit is currently idle
## (no current order), the appended order becomes current right away -- mirrors the legacy
## "start marching now if idle" waypoint-append behaviour.
func append_order(order: Order) -> void:
	orders.append(order)
	if current_order == null:
		current_order = orders[0]


## Drop the queue head (it finished, or was interrupted) and promote the next queued order, if
## any, to current. A promoted MOVE leg that hasn't started (a queued waypoint, or a route
## continuation behind a finished attack/relief) commits its march here, so the queue alone
## carries the route -- there is no parallel waypoint list to pop.
func retire_current_order() -> void:
	if not orders.is_empty():
		orders.pop_front()
	current_order = orders[0] if not orders.is_empty() else null
	_start_promoted_move()
	_start_promoted_attack()


## Commit the march of a MOVE order just promoted to current, when no march is already in
## flight. Phase stays NONE -- a queued leg is a plain march, exactly like a Battle-committed
## plain move; the phased (rear-move) composite is only ever built on a fresh order at the
## apply site. No-op for every other order kind, an already-marching unit, or a phased order.
func _start_promoted_move() -> void:
	if current_order == null or current_order.type != Order.Type.MOVE:
		return
	if has_move_target or current_order.phase != Order.Phase.NONE:
		return
	move_target = current_order.target_pos
	has_move_target = true


## Resolve a just-promoted, UNRESOLVED ATTACK order (target_uid < 0) to whatever live enemy
## is already in melee contact -- the promotion path a guard-driven "advance UNTIL contact
## THEN attack" macro relies on (phase 4): the guard retires the MOVE order the instant
## contact is made, and the queue promotes the appended ATTACK order that names no specific
## enemy, so it must acquire target_enemy itself on the very tick it becomes current or
## _update_current_order's target_enemy == null check would retire it unfought. A resolved
## ATTACK order (target_uid >= 0, the ordinary player-issued case) is untouched here --
## Battle._apply_order_cmd already set target_enemy at issue time. No-op for every other
## order kind or an ATTACK that's already carrying a live target.
func _start_promoted_attack() -> void:
	if current_order == null or current_order.type != Order.Type.ATTACK:
		return
	if current_order.target_uid >= 0:
		return
	if target_enemy != null and is_instance_valid(target_enemy):
		return
	target_enemy = UnitTargeting.current_target(self)


## Destinations of the queued (not-yet-current) MOVE legs, in queue order -- the route the
## unit will march after the current order. What the overlay draws as waypoint dots and the
## order summary counts; replaces reads of the old parallel waypoint list.
func queued_move_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i in range(1, orders.size()):
		if orders[i].type == Order.Type.MOVE:
			points.append(orders[i].target_pos)
	return points


## True when a queued MOVE leg is waiting behind the current order -- the marching unit is
## on an intermediate leg of its route, not the last one. Appended legs queue in order, so
## checking the immediate next entry covers the route case.
func _has_queued_move_leg() -> bool:
	return orders.size() > 1 and orders[1].type == Order.Type.MOVE


## Clear the queue and current order outright (death, a merge, or a rout dropping every
## in-progress maneuver -- see _rout()). Interrupts any maneuver in flight first, so a
## partial in-place turn is folded rather than leaving the bodies to surge.
func clear_orders() -> void:
	_interrupt_current_order()
	orders.clear()
	current_order = null


## Interrupt whatever maneuver the outgoing current order has in flight, before the queue is
## replaced or cleared. A partial in-place turn is settled -- the rotation folds into
## _formation_angle so every man keeps his own slot and the bodies don't surge -- and a wheel
## is dropped where it stands (a partial swing is already a valid formation state: position
## and facing are consistent, so no settle step is needed). A parked rear-move march and its
## reform choice live on the dropped order, so they die with it -- an interrupting attack
## can no longer leave a stale rear destination behind to resurrect after the fight.
func _interrupt_current_order() -> void:
	if current_order == null:
		return
	if is_order_turning():
		_settle_order_turn()
	elif is_wheeling():
		current_order.turn_target = Vector2.ZERO


## True while current_order is running an in-place turn: a rear MOVE's about-face (TURN)
## phase, or a standalone ABOUT_FACE / QUARTER_TURN drill.
func is_order_turning() -> bool:
	if current_order == null or current_order.type == Order.Type.WHEEL:
		return false
	return current_order.turn_target != Vector2.ZERO


## True while current_order is a WHEEL mid-swing.
func is_wheeling() -> bool:
	if current_order == null or current_order.type != Order.Type.WHEEL:
		return false
	return current_order.turn_target != Vector2.ZERO


## True while ANY maneuver owns the soldier bodies' arrival: an order-driven in-place turn
## or wheel, or the combat engage re-face (which is reactive execution state, not a queue
## entry). SoldierBodies.step freezes the slot-approach term while this holds, so the men
## hold their ground (turns) or ride the rigid rotation (wheel) instead of chasing
## intermediate slot targets.
func is_maneuver_turning() -> bool:
	return is_order_turning() or is_wheeling() or _engage_turn_target != Vector2.ZERO


## Goal facing of the in-place 180° reversal current_order is running (a rear move's TURN
## phase or the standalone ABOUT_FACE drill), or ZERO when none. The figure render squashes
## the marks through a reversal; a quarter-turn keeps the ordinary facing render.
func about_face_goal() -> Vector2:
	if current_order == null:
		return Vector2.ZERO
	var reversing: bool = current_order.type == Order.Type.ABOUT_FACE \
			or (current_order.type == Order.Type.MOVE
					and current_order.phase == Order.Phase.TURN)
	return current_order.turn_target if reversing else Vector2.ZERO


## Advance current_order's bookkeeping for this tick: retire orders whose work is done. The
## maneuver phases themselves (TURN -> REFORM -> MARCH, the drill/wheel completions) are
## advanced at their execution sites in _think, which know exactly when a handoff happens;
## this pass covers the retirements that still key off legacy state -- arrival
## (has_move_target / waypoints), a dead attack target, a resolved relief or support -- AND,
## as of phase 4, an order's own guard condition (Order.Guard), checked before the per-type
## match so a satisfied guard retires ANY order kind early, regardless of how it would
## otherwise complete. This is the terminal-condition mechanism: "advance UNTIL contact THEN
## attack" is a MOVE order guarded by CONTACT_MADE with an appended ATTACK order behind it --
## the guard firing retires the MOVE and promotes the ATTACK on the very same tick.
func _update_current_order() -> void:
	if current_order == null:
		return
	if current_order.guard != Order.Guard.NONE:
		current_order._guard_ticks += 1
		if OrderGuards.satisfied(self, current_order):
			# A guard can fire mid-march (that's the whole point of CONTACT_MADE on a MOVE
			# order): settle any in-place turn the outgoing order had running, and drop the
			# march state, so nothing resurrects a stale move_target once the promoted order
			# takes over -- the same cleanup a fresh player order performs at the apply site.
			_interrupt_current_order()
			has_move_target = false
			retire_current_order()
			return
	match current_order.type:
		Order.Type.MOVE, Order.Type.NUDGE:
			# Retire on arrival (has_move_target cleared, no queued route leg), unless the
			# order still has work in flight that keeps has_move_target false without meaning
			# "arrived": an in-place about-face still turning (turn_target set), or a
			# reform-before-move hold (_reform_timer > 0 -- see _think()'s reform block and
			# Battle._apply_order_cmd's reform branch), both of which park the march.
			if not has_move_target and not _has_queued_move_leg() \
					and current_order.turn_target == Vector2.ZERO \
					and _reform_timer <= 0.0:
				retire_current_order()
		Order.Type.ABOUT_FACE, Order.Type.QUARTER_TURN, Order.Type.WHEEL:
			# The drills and the wheel retire at their execution sites the moment they
			# complete or are interrupted; this is a defensive sweep in case one is ever
			# observed with its turn already settled.
			if current_order.turn_target == Vector2.ZERO:
				retire_current_order()
		Order.Type.ATTACK:
			if target_enemy == null:
				retire_current_order()
		Order.Type.RELIEF:
			# UnitRelief.begin can resolve the primary reliever's foe to null (the tired unit had
			# no target_enemy, and UnitTargeting.nearest_enemy found none either -- e.g. the last
			# enemy died at that instant); when that happens it instead advances the reliever
			# onto the tired unit's slot (has_move_target = true), so target_enemy == null alone
			# doesn't mean the relief is done -- it can also mean "no foe to fight, still walking
			# into position." A live pass-through link (relief_partner still set) keeps the order
			# too: the swap itself is the order's work, and the exemption dies with the order, so
			# retiring mid-pass would shove the interpenetrating pair apart. Only retire once no
			# target remains to fight, no move is in flight, AND the swap has resolved
			# (UnitRelief.update clears the link once the pair is apart or the partner is gone).
			if target_enemy == null and not has_move_target \
					and current_order.relief_partner == null:
				retire_current_order()
		Order.Type.SUPPORT:
			if support_target == null:
				retire_current_order()
		Order.Type.FORMATION, Order.Type.FRONTAGE, Order.Type.STANCE:
			# Instantaneous: applied and complete in the same tick Battle issues them, so they
			# never accumulate here -- retire defensively in case one is ever observed live.
			retire_current_order()


## Arm the attack cooldown for the swing about to land, picking the interval that
## matches the unit's stance: PIN_DOWN swings on the slower PIN_DOWN_ATTACK_INTERVAL
## and opens its own exposure window (pin_down_defense_factor); every other stance
## uses the normal baseline (ATTACK_INTERVAL melee / RANGED_INTERVAL ranged). Called
## right before UnitCombat.strike()/shoot(), so the exposure window is already open
## for any riposte that lands later in the same tick.
func _start_attack_cd(baseline_interval: float) -> void:
	if order_mode == ORDER_PIN_DOWN:
		_attack_cd = PIN_DOWN_ATTACK_INTERVAL
		_pin_down_exposure_cd = PIN_DOWN_EXPOSURE_DURATION
	else:
		_attack_cd = baseline_interval


## Decide what to do this frame: fight if in contact, otherwise move.
func _think(delta: float) -> void:
	_update_current_order()
	# Order-response delay: tick down on every frame. Non-fighting units are frozen
	# until the timer expires; fighting units are not gated — they keep executing
	# _think() normally, so a disengage or retarget order issued mid-combat takes
	# effect on the same frame, not after the delay. When the timer hits 0 this
	# tick, fall through so motion starts immediately rather than waiting an
	# extra frame.
	if _order_response_timer > 0.0:
		_order_response_timer = maxf(0.0, _order_response_timer - delta)
		# Also drain the reform timer concurrently so both run in parallel; the
		# effective delay before the march is max(order_response_delay, REFORM_DURATION).
		# Guard on the order timer still being positive: if it expires this very frame
		# (just hit 0 above), fall through so the reform block below ticks it once —
		# not twice.
		if _reform_timer > 0.0 and _order_response_timer > 0.0:
			_reform_timer = maxf(0.0, _reform_timer - delta)
		if _order_response_timer > 0.0 and state != State.FIGHTING:
			return

	# Reform phase: unit holds position after the order-response delay expires until
	# reform timer runs out, then commits the pending move. A fighting unit skips the
	# hold and commits immediately so combat orders are never gated by a reform pause.
	# A post-about-face reform (_reform_until_settled) instead commits as soon as every
	# body stands on its re-squared slot -- its timer is only the safety timeout.
	if _reform_timer > 0.0:
		if state == State.FIGHTING:
			_commit_pending_reform()
		else:
			_reform_timer = maxf(0.0, _reform_timer - delta)
			if _reform_until_settled and _reform_bodies_settled():
				_reform_timer = 0.0   # ranks formed: no need to run out the timeout
			if _reform_timer > 0.0:
				state = State.IDLE
				# Use the hold to centre-pivot in place toward the pending destination, so
				# the ranks are already coming onto their heading before the first step. A
				# side-step holds its facing (ordered_facing set), so it doesn't pivot.
				if ordered_facing == Vector2.ZERO:
					_rotate_facing_toward(_reform_target - position, delta)
				return
			_commit_pending_reform()

	# In-place order turns (a rear MOVE's about-face phase, the standalone about-face /
	# quarter-turn drills): every soldier turns where they stand, the block does not advance
	# or pivot as a body. The turn state lives on current_order. Cancelled by engaging in
	# combat or by a march starting under the order (defensive: a waypoint append now
	# queues BEHIND the turning order rather than pre-empting it, so has_move_target
	# stays false through the turn -- if a stray march does start, the partial rotation is
	# preserved by the settle fold). On arrival (or an interrupt) the settle folds the
	# turned angle into _formation_angle so the re-engaged arrival sees ~zero error and
	# every man holds his OWN slot.
	if is_order_turning():
		if state == State.FIGHTING or has_move_target:
			# Fold the partial turn so the bodies don't surge, and retire the maneuver --
			# a rear march parked on the order dies with it.
			_settle_order_turn()
			retire_current_order()
		else:
			if _advance_turn(current_order.turn_target, delta):
				_settle_order_turn()
				_finish_order_turn()
			state = State.IDLE
			return

	# Wheel (circumductio): the block swings about a fixed flank file. facing rotates and the
	# regiment centre slides along an arc so the hinge holds; _advance_wheel rigidly rotates the
	# centre and every body about the hinge, with the arrival frozen (as for the in-place
	# turns) so it doesn't fight the rotation. An interrupt by combat or a move order just
	# drops the wheel where it is — the partial swing is already a valid formation state
	# (position and facing are consistent), so no settle step is needed.
	if is_wheeling():
		if state == State.FIGHTING or has_move_target:
			current_order.turn_target = Vector2.ZERO
			retire_current_order()
		else:
			if _advance_wheel(delta):
				current_order.turn_target = Vector2.ZERO
				retire_current_order()
			state = State.IDLE
			return

	# Under-fire detection for AUTO pace: true when any alive enemy ranged unit is
	# within RANGED_RANGE of this unit (i.e. could be shooting at us this frame).
	# Must run before the ORDER_SUPPORT early return so _support_tick's _move_to
	# calls see the correct value.
	_under_fire = false
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team != team and u.is_ranged and u.state != State.DEAD \
				and u.state != State.ROUTING \
				and position.distance_to(u.position) <= RANGED_RANGE:
			_under_fire = true
			break

	# Support stance: guard a friendly ward — engage threats near it, else
	# shadow it. Handled up front so it overrides the normal target/move logic. If
	# the ward is gone (dead, routed, or cleared) the order is spent, so drop it and
	# fall through to NORMAL auto-behaviour.
	if order_mode == ORDER_SUPPORT:
		if UnitTargeting.support_valid(self):
			_support_tick(delta)
			return
		support_target = null
		order_mode = 0   # ward gone: revert to NORMAL

	# Sweep routers: prioritize routing enemies over still-fighting units. A router in
	# range always wins (forces the switch, even off an already-committed target). With
	# none in range, fall back through current_target() -- which keeps an already-live
	# target rather than re-scanning for the nearest -- so a newly-closer non-routing
	# enemy doesn't yank the sweeper off a target it's already engaging. (This mirrors
	# every other order mode's persistence, but unlike them, SWEEP_ROUTERS still commits
	# the result to target_enemy so a state inspection sees the acquired target the same
	# way it would mid-router-chase.) That commit is gated by the same "not disengaging"
	# check the combat branches below use: a plain move order clears target_enemy to null
	# and sets has_move_target to signal disengage, and committing an auto-acquired target
	# here unconditionally would silently override that signal one tick early, re-engaging
	# a fight the player just tried to break off from.
	if order_mode == ORDER_SWEEP_ROUTERS:
		var routing_enemy: Unit = UnitTargeting.nearest_routing_enemy(self)
		if routing_enemy != null:
			target_enemy = routing_enemy
		elif target_enemy != null or not has_move_target:
			target_enemy = UnitTargeting.current_target(self)

	# Roll the line: a beaten (dead or routed) foe no longer holds this unit's attention --
	# it moves straight on to the next-closest enemy still actually fighting, instead of
	# either idling once the kill lands or grinding out a chase against a target that's
	# already broken (current_target's ordinary chase-to-destroy behaviour). Persist the
	# fresh pick to target_enemy itself (unlike current_target, which leaves that write to
	# an explicit order) -- ROLL_THE_LINE's whole point is to keep committing to a new foe
	# with no fresh player/AI order behind it, so the not-yet-in-contact chase branch below
	# (which reads the target_enemy field, not this local) needs it set too.
	var enemy: Unit
	if order_mode == ORDER_ROLL_THE_LINE:
		enemy = UnitTargeting.roll_the_line_target(self)
		target_enemy = enemy
	else:
		enemy = UnitTargeting.current_target(self)
	if enemy != null:
		var dist: float = position.distance_to(enemy.position)
		var in_contact: bool = dist <= attack_range + RADIUS + enemy.RADIUS
		# Chase: relentless pursuit. Everywhere else in this branch gates fighting/closing
		# on "target_enemy != null or not has_move_target" (an explicit attack order, or no
		# move order at all) — that's what lets a plain move order pull a unit off a foe it
		# only auto-acquired. A CHASE unit never takes that out: it keeps re-engaging and
		# re-closing on the SAME enemy regardless of any later move order, so it can't be
		# walked off a fleeing/repositioning target the way a normal unit can.
		var chasing: bool = order_mode == ORDER_CHASE
		# Cycle charge: a melee unit lands a charge, then peels back to a standoff and
		# re-charges, rather than grinding in a spent-bonus melee. Handled up front (like
		# skirmish) so it overrides the press-and-grind melee below. Ranged units and a
		# plain disengage move order fall through to the normal paths.
		if not is_ranged and order_mode == ORDER_CYCLE_CHARGE \
				and (target_enemy != null or not has_move_target):
			if _cycle_charge_tick(enemy, dist, in_contact, delta):
				return
		# Skirmish: a ranged unit kites — if a threat is inside the kite
		# distance it backs off (away from the threat, clamped to the field) rather
		# than standing to fire or being caught in melee; beyond it, it falls through
		# to the normal ranged fire below. Gated by the same "not disengaging" rule
		# as firing, so a plain move order still marches it off instead of kiting.
		if is_ranged and order_mode == ORDER_SKIRMISH and dist < SKIRMISH_KITE_DISTANCE \
				and (target_enemy != null or not has_move_target):
			var away: Vector2 = position - enemy.position
			if away.length() < 0.001:
				away = Vector2.UP if team == 0 else Vector2.DOWN   # degenerate: own back edge
			_move_to(UnitTargeting.clamp_to_field(self, position + away.normalized() * SKIRMISH_KITE_DISTANCE), delta)
			# Only commit to the retreat if it actually moved. If the unit is cornered
			# against the field edge (clamp snapped the target onto its position),
			# fall through to the fire/melee branches so it still shoots instead of
			# standing idle.
			if _moved_last_frame:
				return
		# Ranged units stand and loose volleys at any enemy inside RANGED_RANGE
		# that hasn't closed to melee — they skirmish at distance instead of charging.
		# Gated by the same "not disengaging" rule as melee: a plain move order with
		# no explicit attack target marches them off rather than rooting them to fire.
		if is_ranged and not in_contact and dist <= RANGED_RANGE \
				and (target_enemy != null or not has_move_target or chasing):
			state = State.FIGHTING
			# Turn to bring the line to bear before loosing; a large swing turns in place
			# gradually, a small correction snaps. Fire is withheld until faced.
			if _face_for_action(enemy.position, delta, enemy) and _attack_cd <= 0.0:
				_start_attack_cd(RANGED_INTERVAL)
				UnitCombat.shoot(self, enemy)
			return
		# Fight when in contact, UNLESS the player gave a plain move order with no
		# explicit attack target — that's a disengage command, so march off and let
		# the unit break contact. (Pulling out exposes the rear; the enemy chasing
		# it strikes for the ×2 flank bonus, which is the cost of disengaging.) A
		# CHASE unit never takes this disengage: it keeps fighting the same foe.
		if in_contact and (target_enemy != null or not has_move_target or chasing):
			state = State.FIGHTING
			# Re-face for action: a large swing off the current fronting turns the men in
			# place gradually (they hold their ground) before the line strikes; a small
			# correction snaps and fights now. _face_for_action reports when the front is
			# brought to bear — the strike is withheld until then.
			var faced: bool = _face_for_action(enemy.position, delta, enemy)
			if faced and _attack_cd <= 0.0:
				_start_attack_cd(ATTACK_INTERVAL)
				UnitCombat.strike(self, enemy)
			# Press into contact: a committed melee unit keeps advancing onto the enemy
			# while it fights, so the lines close to body contact (separation provides the
			# counterforce, settling them at the engaged-enemy front-rank floor) instead
			# of trading blows at arm's length. A HOLD stance holds its ground and doesn't
			# press; ranged units don't melee-press at all. While still turning in place to
			# bring the front to bear, hold position — the men turn where they stand, so the
			# press waits until the turn fully finishes.
			if _engage_turn_target == Vector2.ZERO and not is_ranged and order_mode != ORDER_HOLD:
				_press_into(enemy.position, delta)
			return
		elif target_enemy != null or (chasing and not in_contact):
			# Explicit attack order (or a CHASE unit's auto-acquired quarry), not yet in
			# contact: chase past any move target. A flank/rear stance closes on the
			# enemy's side or back instead of head-on, so the strike on arrival lands with
			# the flank/rear bonus.
			# If the enemy broke contact mid-turn, settle the re-face first — the unit is
			# marching after it now, so the frozen arrival must release (the turn resumes on
			# the next contact when _face_for_action runs again).
			if _engage_turn_target != Vector2.ZERO:
				_settle_engage_turn()
			var goal: Vector2 = enemy.position
			if order_mode == ORDER_ATTACK_FLANK or order_mode == ORDER_ATTACK_REAR:
				goal = UnitTargeting.attack_approach_point(self, enemy)
			_move_to(goal, delta)
			return

	# Obey a move order (disengaging if needed), else auto-advance on a near enemy.
	# A player move order marches orderly -- it centre-pivots gradually toward its heading
	# before advancing; combat chases above stay snappy (orderly = false).
	if has_move_target:
		# Arrival at the FINAL destination requires both a close position AND a near-zero
		# speed -- not position alone. _move_to's braking ramps _current_speed down along
		# the arrival envelope on the route's last leg, so by the time the unit is within
		# 5px it should nearly be stopped; the speed guard keeps a moving unit decelerating instead
		# of finalizing early and hard-snapping via the "no momentum while stationary" reset
		# elsewhere in this tick. Intermediate waypoints pop on position alone, so a queued
		# route rolls through each corner at pace instead of halting leg by leg.
		var on_last_leg: bool = not _has_queued_move_leg()
		var arrived: bool = position.distance_to(move_target) <= 5.0
		# Wait for the stop only when the unit can actually brake: a degenerate loadout
		# with no positive brake rate (decel <= 0) can never bleed speed, so it finalizes
		# on position alone -- the pre-braking contract -- instead of hanging on the
		# speed guard forever.
		var must_stop: bool = on_last_leg and arrival_brake_rate() > 0.0
		if not arrived or (must_stop and _current_speed > ARRIVE_SPEED_EPSILON):
			_move_to(move_target, delta, true)
		elif not on_last_leg:
			# Each queued leg marches on its own terms: drop any side-step hold from
			# the leg just finished so the next leg turns to face its own travel.
			ordered_facing = Vector2.ZERO
			# A queued waypoint leg IS a queued MOVE order (phase 3): end the finished
			# leg here, and retire its MOVE order -- the promoted next leg commits its
			# own march (retire_current_order -> _start_promoted_move), so the queue
			# reports the leg actually marching. A non-MOVE order that marched here (a
			# relief advancing onto the tired unit's slot with a route leg appended
			# behind it) is NOT retired by the route: it finishes by its own condition
			# (_update_current_order), and the promoted leg commits the march then.
			has_move_target = false
			if current_order != null and current_order.type == Order.Type.MOVE:
				retire_current_order()
		else:
			has_move_target = false
			state = State.IDLE
			# The side-step maneuver is spent on arrival; the held facing stays (it is
			# already the unit's facing), so just drop the maneuver flag.
			ordered_facing = Vector2.ZERO
			# A drag-to-form-up order parks a deploy facing here; pivot to it on
			# arrival (the soldier bodies then ease into the rotated formation).
			if deploy_facing != Vector2.ZERO:
				facing = deploy_facing
				deploy_facing = Vector2.ZERO
			# A hasty rear move deferred its reform until the march was done: the unit
			# stands at its destination now, so re-form the ranks square to the heading
			# (the bodies ease onto the re-squared slots while it stands idle).
			if _reform_on_arrival:
				_reform_on_arrival = false
				reform_ranks()
	elif enemy != null and order_mode != ORDER_HOLD:
		# Auto-advance on a near enemy the combat branches didn't engage this tick (out of
		# range/contact). If a re-face turn was in progress, settle it first: the unit is
		# marching now, so the frozen arrival must release (folding the partial rotation into
		# _formation_angle) or the bodies would stay pinned and never keep up with the march.
		if _engage_turn_target != Vector2.ZERO:
			_settle_engage_turn()
		_move_to(enemy.position, delta)
	else:
		# Idle: no enemy, or a HOLD stance that won't chase — the paths above
		# still fight/fire whatever reaches a held unit. If the engaged enemy vanished
		# (died/routed/left range) while a re-face turn was still running, settle it here so
		# the soldier-body arrival doesn't stay frozen indefinitely (folding the partial
		# rotation into _formation_angle so the bodies don't surge when the arrival re-enables).
		if _engage_turn_target != Vector2.ZERO:
			_settle_engage_turn()
		state = State.IDLE


## Cycle-charge stance: one tick of the caracole loop against `enemy`. A melee unit
## drives in for a charge, lands the momentum-scaled impact strike, then peels back to
## CYCLE_CHARGE_STANDOFF to rebuild closing speed before charging again — so it keeps
## landing high-impact charge hits instead of grinding where the bonus is already spent.
## Returns true when it fully handled the tick (caller should return); false to fall
## through to the normal chase/melee paths (e.g. still closing on a distant target, so
## the ordinary approach builds _approach_velocity for the charge). Deterministic — pure
## geometry plus the shared strike cadence, so live play and replay stay in lockstep.
func _cycle_charge_tick(enemy: Unit, dist: float, in_contact: bool, delta: float) -> bool:
	# Recharging: peel back to the standoff so the next run rebuilds closing speed.
	if _cycle_recharging:
		if dist < CYCLE_CHARGE_STANDOFF:
			var away: Vector2 = position - enemy.position
			if away.length() < 0.001:
				away = Vector2.UP if team == 0 else Vector2.DOWN   # degenerate: own back edge
			var goal: Vector2 = position + away.normalized() * (CYCLE_CHARGE_STANDOFF - dist)
			_move_to(UnitTargeting.clamp_to_field(self, goal), delta)
			# Cornered against the field edge with no room to peel off: give up the
			# retreat and fight in place so the unit isn't frozen.
			if not _moved_last_frame:
				_cycle_recharging = false
				return false
			return true
		# Opened past the standoff: end the pull-back and let the normal approach below
		# drive the next charge run (return false so the caller falls through to it).
		_cycle_recharging = false
		return false

	# Charging: on contact, land the (charge-scaled) strike, then flip to recharging so
	# the unit pulls back next tick instead of pressing into a grind. Otherwise fall
	# through so the normal approach closes on the enemy and carries a charge velocity.
	if in_contact:
		state = State.FIGHTING
		_face(enemy.position)
		# Only peel back once a hit actually lands: flipping to recharging is gated on the
		# strike so a contact that arrives mid-cooldown holds and fights until the cooldown
		# clears, rather than retreating without having landed the charge. (For current
		# cavalry speeds the cycle period exceeds ATTACK_INTERVAL, so this rarely bites —
		# but the gate keeps it correct if speed or the interval is later retuned.)
		if _attack_cd <= 0.0:
			_attack_cd = ATTACK_INTERVAL
			UnitCombat.strike(self, enemy)
			_cycle_recharging = true
		return true
	return false


# --- Targeting & support order ----------------------------------------------
# The target-acquisition QUERIES (current target, nearest threat, ward validity, approach
# point, field clamp) live in UnitTargeting; the order EXECUTION that consumes them stays
# here (the AI brain in _think, and _support_tick below).

## Support stance: guard the ward. If an enemy has closed within
## SUPPORT_GUARD_RADIUS of the ward, peel off and engage it (firing at standoff if
## ranged, melee in contact, else closing on it); otherwise shadow the ward,
## holding a short standoff so the supporter doesn't pile onto the unit it guards.
## Targeting keys off the WARD's position, so the supporter returns to its charge
## once a threat is dealt with. Deterministic (no RNG / wall-clock), matching the
## normal fire/melee cadence so live and replayed battles stay in lockstep.
func _support_tick(delta: float) -> void:
	var ward: Unit = support_target
	var threat: Unit = UnitTargeting.nearest_enemy_to(self, ward.position, SUPPORT_GUARD_RADIUS)
	if threat != null:
		var dist: float = position.distance_to(threat.position)
		var in_contact: bool = dist <= attack_range + RADIUS + threat.RADIUS
		if is_ranged and not in_contact and dist <= RANGED_RANGE:
			state = State.FIGHTING
			if _face_for_action(threat.position, delta, threat) and _attack_cd <= 0.0:
				_attack_cd = RANGED_INTERVAL
				UnitCombat.shoot(self, threat)
		elif in_contact:
			state = State.FIGHTING
			if _face_for_action(threat.position, delta, threat) and _attack_cd <= 0.0:
				_attack_cd = ATTACK_INTERVAL
				UnitCombat.strike(self, threat)
		else:
			# Threat out of range: chase it. Settle a dangling re-face first so the frozen
			# body arrival releases before the march (the turn re-arms on the next contact).
			if _engage_turn_target != Vector2.ZERO:
				_settle_engage_turn()
			_move_to(threat.position, delta)
		return
	# No threat near the ward: shadow it, holding station a short distance off so
	# the supporter doesn't crowd the unit it's guarding. If a re-face turn was still
	# running when the threat left (died/routed/cleared the guard radius), settle it here
	# so the body arrival isn't left frozen indefinitely.
	if _engage_turn_target != Vector2.ZERO:
		_settle_engage_turn()
	if position.distance_to(ward.position) > SUPPORT_FOLLOW_DISTANCE:
		_move_to(ward.position, delta)
	else:
		state = State.IDLE


# --- Movement --------------------------------------------------------------

## The rate an orderly march sheds speed with when braking onto its destination. Capped
## at what the soldier bodies can actually track: the bodies chase the marker's velocity
## (their feed-forward) under bounded acceleration -- maxf(accel, BODY_ACCEL_FLOOR), see
## SoldierBodies -- so a marker shedding speed faster than that leaves its bodies coasting
## past their slots, and the body->marker coupling then drags the whole regiment past its
## destination and back. Plain decel still governs every non-arrival slowdown (a mid-march
## downshift keeps the marker moving, so a transient body lag self-corrects there).
func arrival_brake_rate() -> float:
	return minf(decel, maxf(accel, SoldierBodies.BODY_ACCEL_FLOOR))


func _move_to(point: Vector2, delta: float, orderly: bool = false) -> void:
	# Route around terrain via the pathfinding layer when one is active; with no
	# obstacles registered the next step is the target itself (straight line).
	var step: Vector2 = point
	var terrain_speed: float = 1.0
	if PathField.active != null:
		step = PathField.active.next_step(position, point)
		terrain_speed = PathField.active.speed_at(position)
	var to: Vector2 = step - position
	if to.length() < 1.0:
		# Standing on the point already. An orderly march bleeds any residual speed at the
		# brake rate here -- and flags itself as still moving so the "no momentum while
		# stationary" reset can't hard-snap the tail of the ramp to 0 -- so the whole
		# stop reads as one continuous deceleration. Combat movers keep the old contract:
		# their callers gate follow-up behaviour on _moved_last_frame staying false.
		if orderly and _current_speed > 0.0:
			_current_speed = move_toward(_current_speed, 0.0, arrival_brake_rate() * delta)
			_moved_last_frame = true
		return
	var dir: Vector2 = to.normalized()
	var maneuvering: bool = ordered_facing != Vector2.ZERO
	# Pace: a maneuver or walk-advance holds walk speed throughout. AUTO otherwise
	# walks by default, jogs under missile fire, and sprints at full speed once
	# close to the target. Each pace is this unit's own gait speed, not a fraction
	# of another -- see walk_speed/jog_speed/move_speed above.
	# A MOVE order with an explicit gait (from multi-click) overrides AUTO: single-click
	# forces walk, double-click forces jog, triple-click defaults to run, quadruple-click
	# forces sprint.
	var pace_speed: float
	# Check if current_order specifies a gait to use
	var override_gait: bool = current_order != null and current_order.type == Order.Type.MOVE \
			and current_order.gait >= 0
	if override_gait:
		match current_order.gait:
			GAIT_WALK:
				pace_speed = walk_speed
			GAIT_JOG:
				pace_speed = jog_speed
			GAIT_RUN:
				pace_speed = move_speed if position.distance_to(point) <= SPRINT_START_DISTANCE else jog_speed
			GAIT_SPRINT:
				pace_speed = move_speed
			_:
				pace_speed = walk_speed  # fallback
	elif maneuvering or walk_advance:
		pace_speed = walk_speed
	elif position.distance_to(point) <= SPRINT_START_DISTANCE:
		pace_speed = move_speed  # sprint distance beats under-fire: charge through the kill zone at full speed
	elif _under_fire:
		pace_speed = jog_speed
	else:
		pace_speed = walk_speed
	# A planted close-order stance (shield wall, testudo, or the anti-cav square) caps
	# its top pace: the men hold a locked ring/wall and only creep, so the target pace
	# is scaled down before the ramp.
	pace_speed *= formation_speed_factor()
	# Wedge charge trades defense and fatigue (UnitCombat.order_mode_modifiers,
	# UnitMorale.tick_fatigue) for a faster approach -- the whole point of the stance is to
	# hit the enemy line harder and sooner, so the bonus applies to every pace, not just a
	# full sprint.
	if order_mode == ORDER_WEDGE_CHARGE:
		pace_speed *= WEDGE_CHARGE_SPEED_BONUS
	# Final approach: brake to a stop on the destination instead of holding pace to the
	# wire and letting the outer arrival check hard-reset _current_speed to 0 in a single
	# tick. The pace is capped at the (margin-derated) arrival envelope sqrt(2 * a * d) --
	# the speed from which the unit can still stop exactly at the point -- with a d/delta
	# ceiling so the target never asks to cross the point in one tick (the same arrive
	# profile the soldier bodies use for their slots). Only an orderly march on its
	# route's LAST leg brakes: combat chases and kiting must charge through at full pace
	# (the strike spends _approach_velocity, so braking would bleed the charge impact),
	# and intermediate waypoints roll through their corners at pace.
	var braking_to_stop: bool = false
	var dist_to_stop: float = 0.0
	var brake: float = arrival_brake_rate()
	if orderly and not _has_queued_move_leg() and brake > 0.0 and delta > 0.0:
		dist_to_stop = position.distance_to(point)
		var envelope: float = minf(
			sqrt(2.0 * brake * ARRIVAL_ENVELOPE_MARGIN * dist_to_stop),
			dist_to_stop / delta)
		if envelope < pace_speed:
			pace_speed = envelope
			braking_to_stop = true
	# Ramp toward the selected pace instead of snapping there -- a unit takes real time
	# to build up to a pace (accel) and slows down rather than instantly stopping/downshifting
	# (decel), per-type rates set from the loadout's panoply-weight-scaled accel_mps2/decel_mps2.
	# Braking onto the destination uses the body-trackable brake rate instead of raw decel --
	# see arrival_brake_rate.
	var rate: float = accel if pace_speed > _current_speed else decel
	if braking_to_stop and pace_speed < _current_speed:
		rate = brake
	_current_speed = move_toward(_current_speed, pace_speed, rate * delta)
	# Facing. A side-step holds its commanded heading and shuffles sideways. An orderly
	# move order centre-pivots gradually toward its travel direction (the ranks turn in
	# good order), tapering the pivot rate down as current speed rises -- real turning
	# capacity is bounded by the lateral force a moving body/formation can exert without
	# losing footing or cohesion. A combat chase faces travel instantly (must stay responsive).
	if maneuvering:
		_face_dir(ordered_facing)
	elif orderly:
		var speed_frac: float = clampf(_current_speed / move_speed, 0.0, 1.0)
		var pivot_rate: float = TURN_RATE * lerpf(1.0, TURN_RATE_TAPER_FLOOR, speed_frac)
		_rotate_facing_toward(dir, delta, pivot_rate)
	else:
		_face_dir(dir)
	var effective_speed: float = _current_speed * terrain_speed
	# Turn-before-march: while centre-pivoting an orderly move, scale the advance by how
	# far the unit has come onto its heading. A sharp turn (e.g. a 180° pivot to a rear
	# destination) nearly halts and pivots, then accelerates as it aligns -- so it
	# never slides backwards/sideways at speed. Full speed once within ~60 deg of the
	# heading; side-steps are exempt (they march at a fixed walk perpendicular).
	if orderly and not maneuvering:
		effective_speed *= clampf(facing.dot(dir) * 2.0, 0.0, 1.0)
	# Inbound clamp: never step PAST the immediate goal point in a single tick -- the
	# same post-step guard the soldier-body arrival uses. Without it a fast unit whose
	# per-tick step exceeds the remaining distance crosses the point, the direction
	# flips, and it oscillates around the destination instead of settling on it. A
	# braking march additionally caps the step at the remaining distance to the FINAL
	# destination: near the target the pathfinding node can sit past the exact ordered
	# point, and stepping to the node would cross it. The recorded charge velocity below
	# stays the unclamped speed -- landing ON a target must not bleed the impact.
	var advance: float = minf(effective_speed * delta, to.length())
	if braking_to_stop:
		advance = minf(advance, dist_to_stop)
	position += dir * advance
	# A non-routing unit stops at the field's own edge -- the retreat margin is for a
	# ROUTING unit to flee into (see Unit.retreat_bounds / _process_rout), not a place a
	# pursuer can follow it. This is the only thing that stops a unit chasing a routing
	# enemy from crossing into the margin after it: field_bounds is the same rect used
	# for skirmisher kiting (FIELD), just enforced here for ordinary chase/move movement.
	position.x = clampf(position.x, field_bounds.position.x, field_bounds.end.x)
	position.y = clampf(position.y, field_bounds.position.y, field_bounds.end.y)
	state = State.MOVING
	_moved_last_frame = true
	# Charge velocity; terrain-scaled so forest reduces the charge bonus (intentional — can't sprint in trees).
	_approach_velocity = dir * effective_speed


## Lean into a melee: nudge the position toward `point` WITHOUT flipping to MOVING or
## carrying a charge velocity. Unlike _move_to, it leaves `state` (FIGHTING) and
## `_approach_velocity` untouched — a grinding melee mustn't re-charge every strike,
## and the cavalry's one-shot impact velocity must survive the cooldown wait. The
## separation / engaged-enemy front-rank floor counters the press, so the line settles
## at body contact instead of trading blows at arm's length.
func _press_into(point: Vector2, delta: float) -> void:
	var to: Vector2 = point - position
	if to.length() < 1.0:
		return
	position += to.normalized() * move_speed * MELEE_PRESS_FRACTION * delta
	# Same field-edge stop as _move_to: a non-routing unit doesn't follow a routing
	# enemy into the retreat margin, even while pressing a lean into melee contact.
	position.x = clampf(position.x, field_bounds.position.x, field_bounds.end.x)
	position.y = clampf(position.y, field_bounds.position.y, field_bounds.end.y)


func _face(point: Vector2) -> void:
	_face_dir(point - position)


## Face `point` for an engage/attack action against `enemy_unit` (the target the turn is
## bringing the front to bear on; kept so the settle step can reshape toward it under
## MATCH_TARGET -- see engage_reshape_mode). A small heading correction snaps (stays
## responsive at close quarters); a large swing (>ENGAGE_TURN_THRESHOLD, ~a quarter-turn or
## more) turns the men in place gradually instead — the line pivots to bring its front to bear
## without the grid collapsing and re-expanding. Returns whether the unit is faced enough to
## fight this tick (true when snapping, or once a turn has closed to within
## ENGAGE_TURN_FIGHT_TOLERANCE); the caller withholds the strike while still turning. Reuses
## the drill turns' arrival-freeze + _formation_angle-absorb, so the bodies hold their ground.
func _face_for_action(point: Vector2, delta: float, enemy_unit: Unit = null) -> bool:
	var dir: Vector2 = point - position
	if dir.length() < 0.01:
		return true
	var offset: float = absf(angle_difference(facing.angle(), dir.angle()))
	# Already turning: keep rotating toward the (possibly moved) target and settle on arrival.
	if _engage_turn_target != Vector2.ZERO:
		_engage_turn_target = dir.normalized()
		_engage_turn_enemy = enemy_unit
		if _advance_turn(_engage_turn_target, delta):
			_settle_engage_turn()
		return absf(angle_difference(facing.angle(), dir.angle())) <= ENGAGE_TURN_FIGHT_TOLERANCE
	# Small offset: snap and fight now, as before.
	if offset <= ENGAGE_TURN_THRESHOLD:
		_face_dir(dir)
		return true
	# Large offset: begin a turn-in-place. Men hold their positions (arrival frozen) while
	# facing rotates; the strike is withheld until the front comes to bear. Capture the
	# pre-turn frontage and the enemy now, before anything reshapes or the target changes.
	_engage_turn_start_facing = facing
	_engage_turn_target = dir.normalized()
	_engage_turn_old_files = formation_files(soldiers)
	_engage_turn_enemy = enemy_unit
	if _advance_turn(_engage_turn_target, delta):
		_settle_engage_turn()
	return absf(angle_difference(facing.angle(), dir.angle())) <= ENGAGE_TURN_FIGHT_TOLERANCE


## Finish an engage turn-in-place: fold the rotation into _formation_angle (so the men keep
## their world positions and the block presents its new front without surging) and clear the
## turn state. Shares the settle math with the quarter-turn. Then, per engage_reshape_mode,
## optionally layers a frontage reshape on top of the turn that just completed -- RECREATE_WIDTH
## restores the file count the unit had before the turn, MATCH_TARGET adopts the enemy's own
## file count. Both go through set_frontage(), the SAME grid-op a manual [ / ] resize uses, so
## the bodies ease into the reshaped slots via the arrival dynamics (no teleport, no surge)
## instead of a new mechanism. KEEP_NEW_FRONTING (the default) reshapes nothing, matching the
## shipped MVP behavior exactly.
##
## Deliberately does NOT touch _formation_mirror_x. The _formation_angle fold above exists
## specifically to hold `ang` (soldier_world_slots' rotation) INVARIANT across the facing
## change -- that's what "the men keep their world positions... without surging" means.
## `_formation_mirror_x` doesn't affect whether `ang` is invariant (a mirrored slot rotated by
## the same `ang` is just as stable a mapping as an unmirrored one), so leaving it alone here
## preserves the no-surge guarantee. Forcing it to a new value in this same tick flips every
## off-centre soldier's target sign for that one tick even though `ang` itself didn't change:
## the exact point-reflection/flank-swap bug this file's countermarch fix exists to eliminate,
## just triggered by an engage re-face instead of a reform (reachable whenever a unit engages
## combat mid-march after a countermarched reform, since the mirror flag stays true through
## that march). The reshape branches above are orthogonal to this: set_frontage() changes the
## file/rank COUNT (which slot index `i` maps to), the same relabelling a reshape always causes
## regardless of the mirror -- _formation_mirror_x only decides whether soldier_world_slots
## negates local x before rotating, so it doesn't make a reshape any less (or more) consistent
## than an unmirrored one; the two concerns don't interact.
func _settle_engage_turn() -> void:
	var turned: float = angle_difference(_engage_turn_start_facing.angle(), facing.angle())
	_formation_angle = wrapf(_formation_angle - turned, -PI, PI)
	_engage_turn_target = Vector2.ZERO
	_render_dirty = true
	match engage_reshape_mode:
		EngageReshapeMode.RECREATE_WIDTH:
			if _engage_turn_old_files > 0:
				set_frontage(_engage_turn_old_files)
		EngageReshapeMode.MATCH_TARGET:
			var enemy: Unit = _engage_turn_enemy
			if enemy != null and is_instance_valid(enemy) and enemy.state != State.DEAD:
				# formation_files (not UnitFormation.frontage) so a hollow-square enemy
				# (SQUARE/SCHILTRON) is matched by its actual square file count, the same
				# accessor the RECREATE_WIDTH branch above uses for the acting unit's own
				# pre-turn frontage.
				set_frontage(enemy.formation_files(enemy.soldiers))
	_engage_turn_old_files = 0
	_engage_turn_enemy = null


## Snap `facing` to `dir` instantly. A small change (the common case: a moving unit's
## travel direction drifting tick to tick, or a close-quarters combat correction) is
## visually a non-event, so soldier_world_slots' facing-relative grid barely moves and the
## men stay near their own slots. A LARGE snap (e.g. an idle unit's very first move order
## firing while it still faces its spawn heading, or a combat chase target appearing behind
## it) would instead swap every slot to the opposite side of the block in one tick --
## _formation_angle absorbs the jump the same way a completed drill turn does, so
## soldier_world_slots reproduces each body's own pre-snap slot under the new facing and no
## soldier surges across the formation. Unlike the drill turns, this is a same-tick snap, not
## an animated turn-in-place -- a combat/chase re-face must stay responsive, only the
## resulting slot-swap churn is what's being suppressed.
##
## Deliberately does NOT touch _formation_mirror_x, for the same reason
## _settle_engage_turn() doesn't: this fold holds `ang` invariant across the snap, and
## _formation_mirror_x has no bearing on whether `ang` is invariant, so leaving it alone
## preserves the "no soldier surges" guarantee above. Forcing it to a fixed value here flips
## every off-centre soldier's sign in the same tick `ang` is held constant, reproducing the
## exact point-reflection bug this file's countermarch fix exists to eliminate -- just via a
## large facing snap (e.g. a chase target appearing behind a unit still marching off a
## countermarched reform) instead of a reform.
func _face_dir(dir: Vector2) -> void:
	if dir.length() <= 0.01:
		return
	var new_facing: Vector2 = dir.normalized()
	if absf(angle_difference(facing.angle(), new_facing.angle())) > FACING_SNAP_ABSORB_THRESHOLD:
		_formation_angle = wrapf(_formation_angle - angle_difference(facing.angle(), new_facing.angle()), -PI, PI)
		_render_dirty = true
	facing = new_facing


## Rotate `facing` toward `target_dir` by at most `rate` * delta this frame — the
## gradual turn primitive shared by the orderly move order's centre pivot and the
## conversio about-face, instead of snapping. Takes the shortest arc, so a 180°
## reversal turns through the nearer side.
func _rotate_facing_toward(target_dir: Vector2, delta: float, rate: float = TURN_RATE) -> void:
	if target_dir.length() < 0.01:
		return
	var cur: float = facing.angle()
	var diff: float = angle_difference(cur, target_dir.angle())
	var step: float = clampf(diff, -rate * delta, rate * delta)
	facing = Vector2.from_angle(cur + step)


## Collision footprint by unit type. Cavalry get the widest body, spearmen a bit
## wider than infantry; all stay below attack reach so melee still presses.
func _type_separation_radius() -> float:
	if is_cavalry:
		return SEPARATION_RADIUS_CAVALRY
	if anti_cavalry:
		return SEPARATION_RADIUS_SPEARMEN
	return SEPARATION_RADIUS_INFANTRY


## The block's depth from its centre to its FRONT rank, in world units: how far the
## leading rank sits ahead of the unit centre along its facing (the formation is
## rank-major, front rank at -Y locally). Two enemy blocks whose centres are this far
## apart, summed, meet front-to-front — so engaged enemies use it as their separation
## floor, closing the lines to contact instead of holding a fixed gap.
func _front_depth() -> float:
	# Use the CURRENT formation's own file count (formation_files), not the wide-line
	# frontage() -- a SQUARE unit's grid is the square layout, so its front depth must be
	# measured against that same grid, not the line frontage its soldiers aren't standing on.
	var files: int = formation_files(soldiers)
	var ranks: int = int(ceil(float(soldiers) / float(files)))
	var depth: float = float(ranks - 1) * 0.5 * FORMATION_SPACING * spacing_scale
	# Cap the depth used as the engaged-enemy separation floor. A very narrow,
	# deep player-set frontage would otherwise make the summed floor exceed melee
	# contact range, pushing fighting lines apart faster than they close and
	# stuttering the melee. Half the unit's own reach keeps the summed floor
	# (this + the foe's) safely inside contact distance for every unit type. Heavy
	# melee units at normal widths sit below their cap, so it only bites on
	# narrowed columns; short-reach archers can clip it even at auto width, but
	# that only allows fractionally more overlap and they kite rather than grind.
	return minf(depth, attack_range * 0.5)


## Formation spacing scale for a given formation `mode`, pure and independent of a live
## unit. This is the piece of set_formation's mode dispatch that Battle._spawn_line also
## needs -- to size a regiment's formation footprint (UnitFormation.half_width_for_soldiers)
## BEFORE the Unit node exists to call set_formation on. set_formation itself calls this
## rather than repeating the mapping, so the two can't drift apart.
static func spacing_scale_for_mode(mode: int) -> float:
	if mode == FORMATION_SHIELD_WALL:
		return SHIELD_WALL_SPACING_SCALE
	if mode == FORMATION_TESTUDO:
		return TESTUDO_SPACING_SCALE
	if mode == FORMATION_LOOSE:
		return LOOSE_SPACING_SCALE
	return 1.0   # NORMAL, TIGHT, SQUARE, SCHILTRON all sit at the historical floor


## Change the regiment's formation and recalculate its separation footprint.
## Uses _base_separation_radius (which absorb() keeps updated) so a formation
## cycle on a merged unit doesn't discard the merge-widened body.
func set_formation(mode: int) -> void:
	formation_mode = mode
	var base := _base_separation_radius
	# The close-order stances all build on TIGHT's locked-shield collision footprint.
	# SQUARE and SCHILTRON also pack to that floor but relay out their GRID as a real
	# square (soldier_world_slots / UnitFormation.square_slots), not the wide line --
	# they're the same hollow-square geometry, differing only in their combat tuning
	# (see the constants above). SHIELD_WALL and TESTUDO go further and squeeze the grid
	# spacing itself below the floor -- a real, measurably tighter block -- on top of
	# sharing the tight collision footprint.
	if mode == FORMATION_TIGHT or mode == FORMATION_SQUARE or mode == FORMATION_SCHILTRON:
		separation_radius = base * TIGHT_SEPARATION_SCALE
	elif mode == FORMATION_SHIELD_WALL:
		separation_radius = base * TIGHT_SEPARATION_SCALE
	elif mode == FORMATION_TESTUDO:
		separation_radius = base * TIGHT_SEPARATION_SCALE
	elif mode == FORMATION_LOOSE:
		separation_radius = minf(SEPARATION_RADIUS_MAX, base * LOOSE_SEPARATION_SCALE)
	else:
		separation_radius = base
	spacing_scale = spacing_scale_for_mode(mode)
	_reset_shield_hold_angles()


## The rest-pose hold angle for this unit's shield type: the single source every
## hold-angle default reads (SoldierBodies.seed, its tail resize, and the
## formation-change reset below). An unknown shield id resolves to 0.0 —
## defensive; the registry resolves every id the spawn path seeds.
func shield_rest_angle() -> float:
	var shield: Shield = LoadoutRegistry.shield(shield_type_id)
	if shield == null:
		return 0.0
	return shield.default_hold_angle


## Reset every soldier's shield hold angle (see docs/soldier-loadout-design.md,
## phase 2) back to its shield type's rest pose. Called on every set_formation()
## so posture state never carries a stale angle across a formation change. Today
## every soldier in a regiment carries the same shield type (phase 1's
## uniform-per-unit loadout), so this is a uniform fill; a real per-formation
## "locked" angle (shield-wall's edge-to-edge lock, testudo's overhead roof) is
## the formation-geometry work's concept to define spatially — this phase only
## keeps the data available and correctly defaulted, it does not yet compute a
## formation-specific angle. Representational only: nothing reads this array for
## combat or rendering yet (rendering is phase 3).
func _reset_shield_hold_angles() -> void:
	if _sim_soldier_shield_hold_angle.is_empty():
		return   # bodies not seeded yet; SoldierBodies.seed will fill it from scratch
	_sim_soldier_shield_hold_angle.fill(shield_rest_angle())


## Set the regiment's frontage (file count), and optionally an anchor shift for an
## asymmetric explicatio/duplicatio (UnitFormation.anchor_shift; 0.0 is the plain
## centred behaviour). Clamped to [1, max_soldiers]; the formation grid
## (UnitFormation.slots) picks both up on the next tick and the soldier bodies ease
## toward the reshaped slots at velocity (no teleport).
func set_frontage(files: int, anchor_offset: float = 0.0) -> void:
	frontage_override = clampi(files, 1, maxi(1, max_soldiers))
	frontage_anchor_offset = anchor_offset


## Multiplier applied to incoming ranged damage. Shielded stances raise shields to
## cut missile casualties:
##   TIGHT       — shields raised, all directions.
##   TESTUDO     — shields locked overhead too, stronger, all directions.
##   SHIELD_WALL — a locked wall, strongest of all, but only to the FRONT; a shot
##                 into the flank or rear bypasses the wall and lands full.
## SQUARE is deliberately NOT given a missile bonus: its shields face outward at the
## horizon to meet a charge on every side, not angled up against plunging arrows, so an
## orbis is no better against shot than an open line -- its all-around bonus is against
## melee/charge, not missiles. When `attacker` is given, SHIELD_WALL checks the incoming
## direction against the unit's facing; with no attacker (a plain query) it grants its
## frontal value. Normal/loose: no modifier.
func missile_defense_factor(attacker: Unit = null) -> float:
	match formation_mode:
		FORMATION_TIGHT:
			return 1.0 - TIGHT_MISSILE_DEFENSE
		FORMATION_TESTUDO:
			return 1.0 - TESTUDO_MISSILE_DEFENSE
		FORMATION_SHIELD_WALL:
			if _is_frontal_attack(attacker):
				return 1.0 - SHIELD_WALL_MISSILE_DEFENSE
			return 1.0
		_:
			return 1.0


## Multiplier applied to incoming MELEE damage. A locked SHIELD_WALL blunts a frontal
## melee assault (flank/rear blows slip past the wall and land full). Other stances: none.
func melee_defense_factor(attacker: Unit = null) -> float:
	if formation_mode == FORMATION_SHIELD_WALL and _is_frontal_attack(attacker):
		return 1.0 - SHIELD_WALL_MELEE_DEFENSE
	return 1.0


## Multiplier applied to THIS UNIT'S OWN defense stat (both melee and ranged --
## unlike melee_defense_factor/missile_defense_factor, the exposure isn't tied to the
## incoming attack's direction) while it's in a PIN_DOWN attack frame. A pinning unit
## commits its whole body to the stalled attack, so it's measurably easier to hit for
## PIN_DOWN_EXPOSURE_DURATION after each swing lands -- the cost side of the stall/pin
## tradeoff (see the PIN_DOWN_* constants above _attack_cd). Every other stance, or a
## PIN_DOWN unit between exposure windows, defends at full value.
func pin_down_defense_factor() -> float:
	if order_mode == ORDER_PIN_DOWN and _pin_down_exposure_cd > 0.0:
		return PIN_DOWN_DEFENSE_FACTOR
	return 1.0


## Multiplier applied to this unit's OWN melee output for shielded stances. A TESTUDO's
## men are packed head-down under overhead cover and can barely swing, so they hit softer.
## (The anti-cav SQUARE has its own offence penalty in formation_attack_factor, which
## covers both melee and ranged.) Other stances: full.
func formation_melee_attack_factor() -> float:
	return 1.0 - TESTUDO_MELEE_PENALTY if formation_mode == FORMATION_TESTUDO else 1.0


## Cap on this unit's top pace, as a fraction of normal. The planted close-order stances
## (shield wall, testudo, and the two square variants) barely move; others march at full
## speed. Orbis and schiltron share the same crawl -- SQUARE_MOVE_FACTOR -- their
## divergence is offence/charge-bracing, not mobility.
func formation_speed_factor() -> float:
	match formation_mode:
		FORMATION_SHIELD_WALL:
			return SHIELD_WALL_SPEED_SCALE
		FORMATION_TESTUDO:
			return TESTUDO_SPEED_SCALE
		FORMATION_SQUARE, FORMATION_SCHILTRON:
			return SQUARE_MOVE_FACTOR
		_:
			return 1.0


## Whether an attack from `attacker` lands on this unit's frontal arc (in the forward
## hemisphere -- strictly ahead of the line abreast, so a pure side/rear blow is not
## frontal). A null attacker counts as frontal (a plain defensive query, no direction).
##
## The frontal arc here (full forward hemisphere, dot > 0) is deliberately WIDER than
## the flank-bonus threshold in UnitCombat.flank_multiplier (which starts the 1.5x flank
## bonus once the attacker is more than ~70 deg off-front). A locked shield wall faces a
## whole hemisphere with its shields, so it earns its frontal cover across that arc; the
## flank casualty bonus is a separate, narrower geometric effect. So an attack in the
## ~70-90 deg band both gets the flank casualty bonus AND meets a shield-wall's front --
## a glancing hit on the shoulder of the wall that is neither a clean frontal push nor a
## clean flank envelopment. That overlap is intended, not a mismatch to reconcile.
func _is_frontal_attack(attacker: Unit) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return true
	var to_attacker: Vector2 = attacker.position - position
	if to_attacker.length() < 0.001:
		return true
	return facing.dot(to_attacker.normalized()) > 0.0


## True when the unit is holding either hollow-square variant (orbis / SQUARE, or
## schiltron / SCHILTRON): the all-around defensive ring. Combat reads this to negate
## the flank/rear multiplier and brace a charge from any direction; movement reads it
## for the mobility penalty; the formation-geometry helpers read it for the square grid.
func in_square() -> bool:
	return formation_mode == FORMATION_SQUARE or formation_mode == FORMATION_SCHILTRON


## True when the unit is specifically in the schiltron variant (the cavalry specialist),
## as opposed to the orbis (plain SQUARE). Combat reads this for schiltron's stronger
## charge brace and deeper offence penalty; morale erosion reads its complement (orbis
## alone gets the last-stand resistance).
func in_schiltron() -> bool:
	return formation_mode == FORMATION_SCHILTRON


## Offensive-output scale from the formation stance. Both square variants hunker to
## defend on every side, so they hit softer -- schiltron harder still than orbis
## (SCHILTRON_ATTACK_FACTOR < SQUARE_ATTACK_FACTOR), trading offence for the stronger
## anti-cavalry brace below. Every other stance is 1.0.
func formation_attack_factor() -> float:
	if formation_mode == FORMATION_SCHILTRON:
		return SCHILTRON_ATTACK_FACTOR
	if formation_mode == FORMATION_SQUARE:
		return SQUARE_ATTACK_FACTOR
	return 1.0


## Scale applied to morale erosion from a casualty (UnitCombat.register_casualties). Orbis
## is tuned as the last-stand ring: it holds its nerve better under losses
## (ORBIS_MORALE_EROSION_RESIST -- less erosion per casualty). Schiltron is the cavalry
## specialist, not a morale stance, so it takes normal erosion like any other formation;
## every other mode is unscaled too.
func formation_morale_erosion_factor() -> float:
	return ORBIS_MORALE_EROSION_RESIST if formation_mode == FORMATION_SQUARE else 1.0


## Push out of any overlapping unit so regiments form a solid line instead of
## passing through each other. Each pair shares the correction half each by
## default; an anti-cavalry spearman yields nothing to enemy cavalry (a hard
## block — see _push_share). Since units move sequentially (each only moves
## itself), one frame reduces an overlap by ~75%; it converges within a few frames.
func _separate() -> void:
	if state == State.DEAD:
		return
	# Consider living units and routers alike: nobody gets walked through.
	for o in _separation_candidates():
		var other: Unit = o as Unit
		# DEAD: queue_free'd but not yet removed from its group this frame.
		if other == null or other == self or other.state == State.DEAD:
			continue
		# Phase 5 (slice 1): friendly regiments no longer collide as circles -- their
		# spacing is resolved at the soldier level (SoldierSteering's friendly tier feeds
		# the body->regiment coupling). The regiment circle now only separates ENEMIES; the
		# enemy front-rank closeup and the spear-vs-cavalry hard block below are unchanged.
		# (The move-through-idle / relief exemptions were friendly-only, so they re-home to
		# the steering pass too.)
		if other.team == team:
			continue
		# (The move-through-idle / relief exemptions were friendly-only, so once friendlies
		# are skipped there's nothing left to exempt here -- the checks re-home to the
		# steering pass. _separation_exempt is still used there.)
		var min_dist: float
		if other.team != team and is_engaged() and other.is_engaged():
			# Engaged enemy lines close until their FRONT RANKS meet (centres a block-
			# depth apart on each side), then the per-soldier collision pass holds the
			# contact and packs the soldiers — so the spacing emerges from the bodies,
			# not a fixed enemy gap. No type-specific standoff here: a spear's reach
			# standoff is meant to emerge from knockback, not a separation rule.
			min_dist = _front_depth() + other._front_depth()
		else:
			min_dist = separation_radius + other.separation_radius
			if _is_melee_intermixing_with(other):
				var dissolve := minf(_combat_intermixing, other._combat_intermixing)
				min_dist *= (1.0 - dissolve)
		var offset: Vector2 = position - other.position
		var d: float = offset.length()
		if d >= min_dist:
			continue
		# Share of the correction this unit takes: 0.5 soft (the pair splits it),
		# but a spear line holds firm against enemy cavalry — 0 for the spearman,
		# 1 for the horse — so cavalry can't ride through a screen (hard block).
		var share: float = _push_share(other)
		var push: Vector2
		if d > 0.01:
			push = offset / d * ((min_dist - d) * share)
		else:
			# Exactly co-located: both units of the pair derive the SAME angle
			# (from the lower stable uid, for determinism) and push in OPPOSITE
			# directions, so they reliably fan apart instead of drifting
			# together. Using each unit's own id here would push near-adjacent
			# ids in almost the same direction and never separate them.
			#
			# Key off uid, NOT get_instance_id(): instance ids are assigned per
			# launch and differ between a live run and its replay, which would
			# desync co-located pushes. uid is the stable per-battle id. posmod
			# buckets the unspawned default (-1) into a valid 0..99 angle slot.
			# The push SIGN also comes from uid, except when both share a uid
			# (e.g. two unspawned test units, both -1): there's no stable order to
			# break the tie, so fall back to instance id for the sign alone — it's
			# always distinct, so the pair still fans apart instead of stacking.
			var lo: int = mini(uid, other.uid)
			var angle: float = float(posmod(lo, 100)) / 100.0 * TAU
			var dir: float
			if uid != other.uid:
				dir = 1.0 if uid > other.uid else -1.0
			else:
				dir = 1.0 if get_instance_id() > other.get_instance_id() else -1.0
			push = Vector2.RIGHT.rotated(angle) * dir * (min_dist * share)
		position += push


## Advance or decay this unit's intermixing meter. Rises while a non-ranged unit is
## actively fighting without a hold order; decays at 4x speed when not fighting.
func _tick_intermixing(delta: float) -> void:
	if state == State.FIGHTING and order_mode != ORDER_HOLD and not is_ranged:
		_combat_intermixing = minf(MELEE_INTERMIX_MAX,
				_combat_intermixing + MELEE_INTERMIX_RATE * delta)
	else:
		_combat_intermixing = maxf(0.0,
				_combat_intermixing - MELEE_INTERMIX_DECAY_RATE * delta)


## True when mutual melee intermixing should soften the separation push between
## this unit and `other`, so their lines close into contact. Both must be actively
## fighting without a hold order.
func _is_melee_intermixing_with(other: Unit) -> bool:
	if other.team == team:
		return false
	return state == State.FIGHTING \
			and other.state == State.FIGHTING \
			and order_mode != ORDER_HOLD \
			and other.order_mode != ORDER_HOLD


# --- Individual-soldier simulation (simulated bodies, rendered + authoritative melee) ---
# The soldiers you SEE are the simulated bodies. Each tick Battle advances every
# regiment's persistent parent-local `_sim_soldier_pos` at velocity (SoldierBodies): a
# body arrives at its formation slot under bounded force, feeds the friendly-avoidance
# steering velocity forward (SoldierSteering), and holds any knockback the melee dealt it
# (SoldierMelee) —
# no body teleports, and there is no position-correction separation pass. The render
# loop reads `_sim_soldier_pos` directly, so the cross-regiment per-soldier
# spacing is visible. The engaged positions are AUTHORITATIVE for per-soldier melee (who
# is in reach of whom), but movement, morale, and `_separate()` still read the regiment
# circle, so those OUTCOMES come from the circle. Full plan in
# docs/individual-collision-design.md.

# Master switch for the soldier layer. ON: the persistent soldier bodies advance one
# velocity step per tick (steering + knockback, no separation pass) and the soldier
# render follows them. Per-soldier melee reads the engaged bodies; regiment
# movement/morale still run off the circle.
const INDIVIDUAL_COLLISION: bool = true

# A soldier's global id is `uid * SOLDIER_ID_STRIDE + index`: a unique,
# replay-stable key per soldier for ordering and tie-breaks, stable even as a
# regiment loses soldiers. The stride exceeds any plausible max_soldiers
# (default 120), so two regiments' id ranges never overlap.
const SOLDIER_ID_STRIDE: int = 1024

# Parent-local positions (relative to the unit's transform, i.e. built from
# `unit.position` — compare against `.position`, not `.global_position`) of this
# regiment's simulated soldiers, index-aligned with their ids.
var _sim_soldier_pos: PackedVector2Array = PackedVector2Array()

# Persistent per-body velocity (parent-local, same frame as _sim_soldier_pos),
# index-aligned with _sim_soldier_pos.
# Phase 4 gives the bodies persistent dynamics: instead of re-seeding their positions
# from the formation every tick (phase 3), each engaged body arrives at its slot under
# bounded force and integrates this velocity, so a soldier displaced by separation HOLDS
# the displacement and eases back rather than snapping to formation. The arrival dynamics
# themselves live in SoldierBodies; this is the state it advances. Still non-authoritative.
var _sim_body_vel: PackedVector2Array = PackedVector2Array()

# Per-soldier friendly-avoidance steering velocity (parent-local, same frame as
# _sim_soldier_pos), index-aligned with _sim_soldier_pos. Recomputed each tick by
# SoldierSteering for the engaged subset (zero
# elsewhere); SoldierBodies feeds it forward so an engaged body drifts off a crowding
# friendly instead of overlapping it. Velocity-based — it never moves a body directly.
var _sim_steer: PackedVector2Array = PackedVector2Array()

# Per-soldier health pool (phase 4b), index-aligned with _sim_soldier_pos: each body
# accumulates wounds across ticks and dies (removed, re-packing the formation) when it
# reaches 0. Seeded to the per-type max health (see SoldierBodies.seed). A near-dead
# soldier also fights worse, via SoldierCombat.condition, so wounds compound.
var _sim_soldier_hp: PackedFloat32Array = PackedFloat32Array()

# Per-soldier weapon/shield TYPE ids, index-aligned with _sim_soldier_pos: each
# entry is an interned LoadoutRegistry id — a reference to one shared type object,
# never a per-soldier allocation. Every soldier currently carries its unit's
# weapon_type_id / shield_type_id (seeded by SoldierBodies.seed, kept aligned
# through resize and casualty compaction), so a per-soldier loadout still
# resolves to the same numbers as the unit's type. Strike-time combat reads
# THROUGH these ids (soldier_lethality / soldier_shield_block below), so a
# later phase's per-soldier write (weapon switching) changes combat immediately.
var _sim_soldier_weapon_id: PackedInt32Array = PackedInt32Array()
var _sim_soldier_shield_id: PackedInt32Array = PackedInt32Array()

# Per-soldier shield hold angle (phase 2, docs/soldier-loadout-design.md),
# index-aligned with _sim_soldier_pos: radians relative to the soldier's own
# facing, the actual per-soldier hold STATE (resting, braced, locked into a
# wall/roof) as opposed to the shield TYPE's default_hold_angle rest pose.
# Lives in its own array (never on the shared Shield instance) precisely
# because it varies per soldier — two soldiers carrying the same interned
# scutum must not be able to fight over one shared hold angle. Seeded from
# LoadoutRegistry.shield(shield_id).default_hold_angle at spawn (see
# SoldierBodies.seed) and kept aligned through resize/casualty compaction like
# every other _sim_* array. set_formation() resets every soldier back to the
# shield's rest pose on a formation change; nothing else writes it yet.
# Representational only — nothing reads this for combat or rendering (that is
# phase 3), so no gameplay or visual outcome changes.
var _sim_soldier_shield_hold_angle: PackedFloat32Array = PackedFloat32Array()

# Per-soldier prone timer (phase 4b), index-aligned with _sim_soldier_pos: seconds-to-rise
# remaining (0 = standing). A knockback impulse can fell a soldier (SoldierCombat.prone_chance);
# a prone soldier loses active defence and can't strike until the timer decays to 0
# (SoldierBodies.step decrements it). Seeded to 0 (everyone standing).
var _sim_prone: PackedFloat32Array = PackedFloat32Array()

# Per-soldier stamina pool (slice D), index-aligned with _sim_soldier_pos: current stamina
# in [0, max_stamina] where max_stamina is the per-type value from combat_profile(). Drained
# by every strike thrown (KAPPA_A), by every blow met (KAPPA_D*phi*(1+c)), and by rising from
# prone (KAPPA_P); restored at RHO_STAMINA per second in SoldierBodies.step. Low stamina
# reduces both offence and active defence through SoldierCombat.stamina_factor (g(sigma)).
var _sim_soldier_stamina: PackedFloat32Array = PackedFloat32Array()

# Per-soldier facing (the drill-maneuver foundation), index-aligned with
# _sim_soldier_pos. By default every body faces the unit heading (kept synced each
# tick in SoldierBodies.step). A per-soldier maneuver -- about-face (conversio),
# the quarter-turn -- takes ownership via set_all_soldier_facing/set_soldier_facing
# (which raise the _per_soldier_facing flag); the bodies then keep their own
# facings until release_soldier_facing() hands control back to the unit heading.
var _sim_soldier_facing: PackedVector2Array = PackedVector2Array()
# While true, _sim_soldier_facing is owned by a maneuver and NOT re-synced to the
# unit heading each tick. False = bodies track unit.facing (the default).
var _per_soldier_facing: bool = false
# The in-place drill turns (about-face / quarter-turn, and a rear move's about-face phase)
# and the wheel keep their in-progress state ON current_order (turn_target /
# turn_start_facing / pivot -- see Order.gd and is_order_turning / is_wheeling), not in
# parallel Unit fields. SoldierBodies.step drops the arrival term while a maneuver runs
# (is_maneuver_turning) so bodies don't drift to intermediate slot positions; on completion
# or an interrupt _settle_order_turn folds however far the turn got into _formation_angle,
# so every soldier holds its OWN world position and facing is the only thing that changes
# (a true drill turn, not an index-swap relabel). A wheel is NOT an in-place turn -- one
# flank file stays fixed while the whole block swings about it like a door on a hinge, so
# `position` slides along an arc as `facing` rotates and the men ride the rigid rotation;
# an interrupted wheel just stops where it is (a partial swing is a valid formation state).
# Non-zero while a unit is turning in place to bring its front to bear on an enemy it is
# engaging (an attack order or auto-engage that arrives ~>75° off the current fronting). The
# target facing (toward the enemy); unit.facing rotates toward it each tick with the arrival
# frozen, exactly like the drill turns, so the men hold their ground and the block does not
# collapse-and-re-expand. The start heading is kept so _formation_angle absorbs however far it
# turned when the turn finishes (or is interrupted), leaving the men where they stood — the
# unit then fights with the fronting it now presents. Unlike the drill turns this runs WHILE
# FIGHTING (a re-face for action, not an idle maneuver); a fresh combat re-face is throttled so
# it does not re-arm every tick.
var _engage_turn_target: Vector2 = Vector2.ZERO
var _engage_turn_start_facing: Vector2 = Vector2.ZERO
# The file count the unit presented just BEFORE the turn was armed, and the enemy it is
# turning to face -- captured once at arm time so the settle step can reshape the frontage
# per engage_reshape_mode without either value drifting mid-turn (the enemy may itself be
# maneuvering, and the unit's own live frontage changes the instant the turn starts folding
# into _formation_angle). The enemy ref is not re-validated here; _settle_engage_turn checks
# is_instance_valid/State.DEAD itself before reading it, same as every other target_enemy use.
var _engage_turn_old_files: int = 0
var _engage_turn_enemy: Unit = null
# Beyond this heading offset (radians) an engage/attack re-face turns in place gradually
# instead of snapping. Below it a small correction snaps, keeping close-quarters combat
# responsive; only a large swing (roughly a quarter-turn or more) turns the men in place.
const ENGAGE_TURN_THRESHOLD: float = deg_to_rad(75.0)
# The unit strikes once its front is within this offset of the enemy — a turn-in-place brings
# the line to bear before it fights, but it need not be dead-on. Slightly under a flank
# boundary so a re-faced unit lands frontal blows.
const ENGAGE_TURN_FIGHT_TOLERANCE: float = deg_to_rad(50.0)
# Beyond this heading offset (radians) an instant facing snap (_face_dir) folds the jump into
# _formation_angle instead of leaving soldier_world_slots' facing-relative grid to swap every
# slot to the new side of the block. A small snap (normal travel-direction drift, a
# close-quarters correction) is left alone -- the grid barely moves and there is nothing to
# absorb. Same threshold as ENGAGE_TURN_THRESHOLD (roughly a quarter-turn or more): past that
# angle the slot swap is large enough to read as the formation collapsing and re-expanding.
const FACING_SNAP_ABSORB_THRESHOLD: float = ENGAGE_TURN_THRESHOLD

# A rear-sector move order parks its march destination and its reform choice on the Order
# itself (target_pos / reform -- has_move_target stays false during the turn so _think's
# march path doesn't pre-empt it), and _finish_order_turn commits them when the about-face
# completes. _reform_on_arrival carries the hasty variant's deferred reform through the
# march; cleared by a fresh order, an interrupt, or a rout.
var _reform_on_arrival: bool = false
# While true, the reform hold (_reform_timer) ends EARLY once every body stands on its slot
# (_reform_bodies_settled) -- the timer is only the safety timeout. The plain reform-before-move
# hold keeps its fixed REFORM_DURATION countdown (this stays false for it).
var _reform_until_settled: bool = false

## Stable, globally-unique id for soldier `index` in this regiment. Pure — a
## function of the regiment uid and the index — so it survives across ticks and
## reproduces exactly on replay. Keys off `uid`, not `get_instance_id()`, for the
## same reason `_separate()` does: instance ids differ between a run and its replay.
func soldier_id(index: int) -> int:
	return uid * SOLDIER_ID_STRIDE + index


## World-space formation slots for `count` soldiers: the local formation grid
## (front rank toward the unit's facing) rotated by the facing and offset to the
## regiment position. Pure of RNG and frame timing — a deterministic function of
## (count, position, facing) — so it reproduces exactly on replay and is
## unit-testable. Reuses the render's slot grid and facing convention, minus the
## cosmetic jitter, so the sim layer stays exactly reproducible.
func soldier_world_slots(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var slots := formation_slots(count)
	# _formation_angle lets a quarter-turn rotate every soldier's facing without moving the
	# grid: it cancels the heading rotation here, so the slots (and the men) stay put.
	var ang: float = facing.angle() + PI * 0.5 + _formation_angle
	for i in range(slots.size()):
		var slot: Vector2 = slots[i]
		if _formation_mirror_x:
			# A countermarch reform: negate the local file (x) coordinate before rotating by
			# the CURRENT ang, instead of just rotating the raw slot. A plain rotation by ang
			# is a point reflection of the pre-reform grid (it swaps a soldier to the opposite
			# flank -- see the _formation_mirror_x field doc); negating x first turns that into
			# a depth-only reflection, so a body keeps its own flank and only trades its rank
			# (front <-> rear) -- a real countermarch, not a mirror-image swap.
			slot.x = -slot.x
		out.push_back(position + slot.rotated(ang))
	return out


## The file count (frontage) UNDER THE CURRENT formation_mode, for `count` soldiers.
## Either square variant (in_square(): SQUARE/orbis or SCHILTRON) lays out its own square
## grid (UnitFormation.square_files, files ~= ranks), not the wide-line frontage every
## other formation uses (UnitFormation.frontage). This is the SINGLE source of truth for
## "how many files is the live grid" -- formation_slots, soldier_world_facings, AND the
## combat geometry that reasons about ranks (_front_depth, engaged_soldier_indices) all key
## off this, so a squared unit's front-rank/engaged-soldier math always agrees with the
## grid its soldiers are actually standing on, instead of the render reading one file count
## and combat reading another. Pure -- a function of (count, formation_mode, the unit's
## frontage inputs).
func formation_files(count: int) -> int:
	if in_square():
		return UnitFormation.square_files(count)
	return UnitFormation.frontage(self)


## Local-space slot layout for `count` soldiers under the CURRENT formation_mode. Either
## square variant lays out a real square grid (UnitFormation.square_slots -- files ~=
## ranks, bbox aspect ~1) instead of the wide line frontage, so the block's actual
## footprint -- and everything sized off it (soldier_world_slots, the render
## extent/shadow) -- reads as a square, not just a combat-multiplier flag. Every other
## mode keeps the wide-line grid (UnitFormation.slots), with SHIELD_WALL/TESTUDO already
## packed tighter via spacing_scale (set in set_formation). Pure -- a function of (count,
## formation_mode, spacing_scale, the unit's frontage inputs) -- so it stays deterministic
## and replay-safe like the callers below.
func formation_slots(count: int) -> PackedVector2Array:
	if in_square():
		return UnitFormation.block_slots(count, formation_files(count), FORMATION_SPACING * spacing_scale)
	return UnitFormation.slots(self, count)


## World-space per-soldier facing directions for `count` soldiers, index-aligned with
## soldier_world_slots. Either square variant points every soldier on the block's outer
## ring radially OUTWARD from the block centre -- the anti-cav ring actually presents
## shields/spears on every side, not one uniform facing -- while the interior fill keeps
## the unit's own heading. Every other formation is uniform at the unit's heading (the
## prior behaviour). Pure -- deterministic in (count, position, facing, formation_mode,
## spacing_scale) -- so it reproduces exactly on replay like soldier_world_slots.
func soldier_world_facings(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(count)
	if not in_square():
		out.fill(facing)
		return out
	var files: int = formation_files(count)
	var slots := UnitFormation.block_slots(count, files, FORMATION_SPACING * spacing_scale)
	var ang: float = facing.angle() + PI * 0.5 + _formation_angle
	for i in range(slots.size()):
		if UnitFormation.square_is_perimeter(i, count, files) and slots[i].length_squared() > 0.0001:
			out[i] = slots[i].rotated(ang).normalized()
		else:
			out[i] = facing   # interior fill / degenerate centre slot keeps the unit heading
	return out


## --- Per-soldier facing (drill-maneuver foundation) -------------------------
## By default each body faces the unit heading; these let a maneuver orient bodies
## individually. _sim_soldier_facing is index-aligned with _sim_soldier_pos.

## Point every body at `dir` and take maneuver ownership (the per-tick re-sync to
## the unit heading stops until release_soldier_facing()). No-op for a zero dir.
func set_all_soldier_facing(dir: Vector2) -> void:
	# No bodies yet (pre-seed): take no ownership, so a later seed/step doesn't
	# leave the flag set with the bodies silently facing the unit heading.
	if dir.length() < 0.01 or _sim_soldier_facing.is_empty():
		return
	_per_soldier_facing = true
	var d: Vector2 = dir.normalized()
	for i in range(_sim_soldier_facing.size()):
		_sim_soldier_facing[i] = d


## Point a single body at `dir` and take maneuver ownership. Out-of-range index or
## a zero dir is a no-op.
func set_soldier_facing(index: int, dir: Vector2) -> void:
	if index < 0 or index >= _sim_soldier_facing.size() or dir.length() < 0.01:
		return
	_per_soldier_facing = true
	_sim_soldier_facing[index] = dir.normalized()


## Hand facing control back to the unit heading: clear the maneuver flag and
## re-sync every body to the current unit facing.
func release_soldier_facing() -> void:
	_per_soldier_facing = false
	if _sim_soldier_facing.size() > 0:
		_sim_soldier_facing.fill(facing)


## True when the unit can arm a standalone drill (about-face / quarter-turn / wheel) right
## now: standing idle -- not fighting, bodies seeded, no march or attack/support duty in
## flight, not parked in a reform hold, and no other maneuver already running. The drills
## are unrecorded gestures, so refusing them while any live behaviour runs keeps them from
## clobbering the order that behaviour runs off (and keeps the live queue no further from
## its replay than the old drill flags did).
func _can_drill() -> bool:
	return state != State.FIGHTING and not _sim_soldier_facing.is_empty() \
			and not has_move_target and target_enemy == null and support_target == null \
			and _reform_timer <= 0.0 \
			and not is_order_turning() and not is_wheeling()


## Conversio (about-face, Vegetius III): every soldier turns in place to reverse 180° at
## CONVERSIO_TURN_RATE rad/s (~0.5 s for a full reversal). The grid keeps its footprint —
## the block does not pivot, neither about its centre (a move order) nor on a flank
## (a wheel / circumductio); each man just turns where they stand, holding their OWN
## world position for the whole turn -- zero displacement per soldier, only facing changes.
## unit.facing tracks the turn each tick so the sim always knows the soldiers' current
## facing (shield side, etc.). SoldierBodies.step drops the arrival term while
## it turns, so bodies stay at their grid positions instead of drifting to intermediate
## slot targets. On arrival (or an interrupt) _settle_order_turn folds the rotation into
## _formation_angle -- the same mechanism the quarter-turn and engage-turn use -- so
## soldier_world_slots reproduces each body's own pre-turn slot under the new facing,
## instead of the front/rear ranks trading slots. The standalone drill is a queue entry
## (an ABOUT_FACE order created here, unrecorded); it no-ops unless the unit stands idle.
func conversio() -> void:
	if not _can_drill():
		return
	var order := Order.new_about_face()
	order.turn_start_facing = facing
	order.turn_target = Vector2(-facing.x, -facing.y)
	set_current_order(order)


## Quarter-turn (90° in-place turn, Aelian/Asclepiodotus): every soldier pivots a quarter
## turn to the left (`dir` = -1) or right (`dir` = +1); the unit's frontage and depth swap
## relative to the field, but the men do not march and the internal grid is NOT reorganized —
## each man just turns where they stand. facing rotates toward the target with the arrival frozen so
## the bodies hold their ground; on arrival _formation_angle absorbs the rotation so
## soldier_world_slots reproduces the men's positions (no transpose, no relabel). A queue
## entry like the about-face drill (a QUARTER_TURN order, unrecorded); it no-ops unless the
## unit stands idle -- re-arming mid-turn would reset the start heading and corrupt the
## settled offset.
func quarter_turn(dir: int) -> void:
	if dir == 0 or not _can_drill():
		return
	var order := Order.new_quarter_turn(dir)
	order.turn_start_facing = facing
	order.turn_target = facing.rotated(signf(dir) * PI * 0.5)
	set_current_order(order)


## Arm the about-face (TURN) phase of a rear-sector MOVE order: an in-place 180° reversal
## runs first; the march to order.target_pos starts when it completes (see
## _finish_order_turn for the reform-vs-hasty handoff). `order` must already be current --
## set_current_order has interrupted whatever ran before, so nothing else is turning.
## Returns false when the unit can't turn in place right now (fighting, or the soldier
## bodies aren't seeded yet); the caller falls back to a plain march.
func begin_about_face(order: Order) -> bool:
	if state == State.FIGHTING or _sim_soldier_facing.is_empty():
		return false
	order.turn_start_facing = facing
	order.turn_target = Vector2(-facing.x, -facing.y)
	order.phase = Order.Phase.TURN
	return true


## Fold the rotation the current order's in-place turn applied (start heading -> current
## heading) into _formation_angle, and clear the turn. A completed about-face turns exactly
## 180° and a quarter-turn exactly 90°, but this also settles an interrupted partial turn
## correctly (whatever angle actually turned), so soldier_world_slots always reproduces each
## body's own pre-turn slot and the arrival sees ~zero error either way — no man ever surges
## to a different soldier's slot.
func _settle_order_turn() -> void:
	var turned: float = angle_difference(current_order.turn_start_facing.angle(), facing.angle())
	_formation_angle = wrapf(_formation_angle - turned, -PI, PI)
	current_order.turn_target = Vector2.ZERO
	_render_dirty = true


## Complete the current order's in-place turn: hand a rear MOVE off to its next phase --
## reform the ranks square to the new heading first (the drilled default; the countermarch
## brings a full rank to the new front instead of the old partial rear rank), or step off at
## once with the flipped grid and reform on arrival (the hasty variant). Either way the
## block faces travel, so it advances forward, not backward. A standalone drill
## (ABOUT_FACE / QUARTER_TURN) is simply done, and retires.
func _finish_order_turn() -> void:
	if current_order.type != Order.Type.MOVE:
		retire_current_order()
		return
	if current_order.reform and reform_ranks():
		_reform_target = current_order.target_pos
		_reform_timer = _reform_timeout()
		_reform_until_settled = true
		current_order.phase = Order.Phase.REFORM
	else:
		_reform_on_arrival = not current_order.reform
		move_target = current_order.target_pos
		has_move_target = true
		current_order.phase = Order.Phase.MARCH


## Reform the ranks (a standalone, composable drill phase -- NOT part of the conversio
## primitive, which stays a pure in-place facing reversal): re-square the slot grid to the
## CURRENT heading by dropping the folded maneuver rotation, so soldier_world_slots lays the
## front rank -- always a full one, by block_slots' construction -- toward `facing` again.
## The bodies then march themselves onto the re-squared slots under the normal arrival
## dynamics, a countermarch: after an about-face this brings the original front-rank men back
## to the front and returns the short/partial rank to the rear, instead of leaving whatever
## the flip put in front (the depleted rear rank) to lead. No body teleports and no
## index-aligned array is relabelled, so per-soldier identity/state is untouched.
##
## No-ops (returns false) when there is nothing to bring forward: the grid is already square
## to the heading (its front rank is full by construction), or it is flipped a half-turn but
## has NO partial rank -- a full grid is centre-symmetric, so the flip already fronts a full
## rank and a reform would only churn every man through the block for zero shape change.
## Returns true when a reform actually starts.
##
## The ±PI case (an about-face fold, the only fold this composite's rear-move actually
## produces) arms _formation_mirror_x rather than just dropping the fold: a plain rotation by
## the post-reform ang is a POINT reflection of the pre-reform grid (it would swap every
## soldier to the OPPOSITE FLANK, not just trade rank order -- see soldier_world_slots and the
## field doc), so the ±PI case needs the depth-only reflection that flag arms instead. Any
## other fold (not ±PI -- unreachable via the rear-move composite today, but the general
## primitive is defensive here) keeps the old plain drop: nothing but a rear-move's about-face
## produces the point-reflection hazard the flag exists for.
func reform_ranks() -> bool:
	var angle: float = wrapf(_formation_angle, -PI, PI)
	if absf(angle) < 0.01:
		return false
	var files: int = maxi(1, formation_files(soldiers))
	# A single rank has no rear to tuck a gap into (its one rank IS the fullest), and a
	# half-turn of it is just a lateral mirror of the same centred row.
	if UnitFormation.ranks_for(soldiers, files) <= 1:
		return false
	var is_about_face_fold: bool = absf(absf(angle) - PI) < 0.01
	if is_about_face_fold and soldiers % files == 0:
		return false
	_formation_angle = 0.0
	_formation_mirror_x = is_about_face_fold
	_render_dirty = true
	return true


## True when every soldier body stands within REFORM_SETTLE_EPS of its formation slot --
## the ranks have re-formed. Trivially true before the bodies seed. Deterministic (pure
## positions, no RNG), so live play and replay agree tick for tick.
func _reform_bodies_settled() -> bool:
	var slots: PackedVector2Array = soldier_world_slots(soldiers)
	var n: int = mini(slots.size(), _sim_soldier_pos.size())
	for i in range(n):
		if _sim_soldier_pos[i].distance_squared_to(slots[i]) > REFORM_SETTLE_EPS * REFORM_SETTLE_EPS:
			return false
	return true


## Safety timeout (seconds) for the post-about-face reform hold. Re-squaring a half-turned
## grid moves every slot to its point-reflection through the block centre, so the longest
## march any body makes in the countermarch is the block's full DIAGONAL (a corner man
## crosses both the width and the depth), and the slowest mover is a body stepping backward
## at the back-pace fraction of jog. Double that worst leg (the arrival ramps up from rest
## under bounded acceleration and decelerates to land, so the average pace runs well under
## the cap) and add a fixed buffer. The hold normally ends before this via
## _reform_bodies_settled -- the timeout only bounds a pathological hold (e.g. bodies
## jostled off their slots by a crowding friendly regiment). Derived from the unit's own
## shape and pace stats, no tuned magic number.
func _reform_timeout() -> float:
	var files: int = maxi(1, formation_files(soldiers))
	var ranks: int = UnitFormation.ranks_for(soldiers, files)
	var span: float = FORMATION_SPACING * spacing_scale
	var width: float = float(maxi(0, files - 1)) * span
	var depth: float = float(maxi(0, ranks - 1)) * span
	var crossing: float = Vector2(width, depth).length()
	var slowest: float = maxf(1.0, jog_speed * back_speed_fraction)
	return crossing / slowest * 2.0 + 1.0


## Advance an in-place turn one tick: rotate `facing` toward `target` at the drill rate and
## report whether it arrived this tick (snapping exactly onto the target so the completion step
## runs on an exact heading — the conversio's body reverse, the quarter-turn's offset settle).
## Shared by the conversio and the quarter-turn.
func _advance_turn(target: Vector2, delta: float) -> bool:
	_rotate_facing_toward(target, delta, CONVERSIO_TURN_RATE)
	if facing.dot(target) > 1.0 - 0.0001:
		facing = target
		return true
	return false


## Parent-local hinge point for a wheel to `dir` (-1 wheel-left / +1 wheel-right): the front of
## the standing flank file. The formation grid (soldier_world_slots) lays its local +X along the
## world direction `facing.rotated(PI/2 + _formation_angle)` and its front (local -Y) along
## `facing.rotated(_formation_angle)`, so the flanks sit ±half_width along the file axis and the
## front rank sits front_depth ahead along the front axis. `_formation_angle` is normally 0, but a
## completed quarter-turn leaves it non-zero (it absorbs the heading change to keep the slots put),
## so the axes MUST fold it in — otherwise a quarter-turn-then-wheel chain hinges about the wrong
## point and the "standing" flank doesn't hold. The offset puts the hinge at the standing file's
## leading man rather than the block centre, so the line pivots about its corner like a real hinge.
## Parent-local (like `_sim_soldier_pos`): built from `position` and used in arithmetic with the
## bodies. Pure of the turn's progress — a function of the CURRENT position/facing/shape — so the
## caller captures it once when the wheel is armed.
func _wheel_pivot_point(dir: int) -> Vector2:
	# The same current-grid file count as _front_depth/engaged_soldier_indices, so a
	# wheel hinges against the grid the regiment is actually laid out on.
	var files: int = formation_files(soldiers)
	var half_width: float = float(files - 1) * 0.5 * FORMATION_SPACING * spacing_scale
	var file_axis: Vector2 = facing.rotated(PI * 0.5 + _formation_angle)   # slot-grid local +X direction
	var front_axis: Vector2 = facing.rotated(_formation_angle)             # slot-grid local -Y (toward front)
	var flank: Vector2 = position + file_axis * (half_width * signf(dir))
	# The front rank sits ahead of the centre along the front axis by the block's front depth, so
	# the hinge is the leading man of the standing file (a door hinges at its edge post, not its mid).
	var ranks: int = int(ceil(float(soldiers) / float(maxi(1, files))))
	var front_depth: float = float(ranks - 1) * 0.5 * FORMATION_SPACING * spacing_scale
	return flank + front_axis * front_depth


## Wheel (circumductio, Aelian/Asclepiodotus): the block swings about one fixed flank file like a
## door on a hinge, reorienting the whole line 90° to the left (`dir` = -1) or right (`dir` = +1)
## while preserving internal order. UNLIKE the quarter-turn — which turns every man in place and
## does not move the block — the standing flank file holds its ground and every other file marches
## an arc around it, so `position` slides along that arc as `facing` rotates. _advance_wheel
## rigidly rotates the centre and every soldier body about the hinge in lockstep, with the arrival
## term frozen (the same freeze the in-place turns use) so it doesn't fight the
## rigid rotation — the men swing to their new slots at velocity, no body teleports. A queue
## entry like the other drills (a WHEEL order created here, carrying the swing goal and the
## captured hinge); it no-ops unless the unit stands idle.
func wheel(dir: int) -> void:
	if dir == 0 or not _can_drill():
		return
	var order := Order.new_wheel(dir)
	order.pivot = _wheel_pivot_point(dir)
	order.turn_start_facing = facing
	order.turn_target = facing.rotated(signf(dir) * PI * 0.5)
	set_current_order(order)


## Advance a wheel one tick: rotate `facing` toward the order's swing goal at the drill rate,
## then rigidly rotate the WHOLE regiment — the centre `position` and every soldier body — about
## the order's fixed hinge by the same increment. Because the slots (soldier_world_slots) are a
## rigid function of position + facing and the bodies are rotated by the same arc step, body and
## slot stay locked together through the swing: the standing flank man holds his ground, the far
## end sweeps, and no body teleports (each tick is a small arc step). SoldierBodies.step freezes
## the restoring force while the wheel swings (is_wheeling), so it doesn't fight this rigid
## rotation. Returns true on arrival (snapping facing exactly onto the goal). Velocities are
## rotated too, so any residual body motion carries through cleanly rather than snapping
## direction.
func _advance_wheel(delta: float) -> bool:
	var goal: Vector2 = current_order.turn_target
	var hinge: Vector2 = current_order.pivot
	var before: float = facing.angle()
	_rotate_facing_toward(goal, delta, WHEEL_TURN_RATE)
	var step: float = angle_difference(before, facing.angle())
	position = hinge + (position - hinge).rotated(step)
	for i in range(_sim_soldier_pos.size()):
		_sim_soldier_pos[i] = hinge + (_sim_soldier_pos[i] - hinge).rotated(step)
		_sim_body_vel[i] = _sim_body_vel[i].rotated(step)
	_render_dirty = true
	if facing.dot(goal) > 1.0 - 0.0001:
		facing = goal
		return true
	return false


## The facing of body `index`; the unit heading for an out-of-range index (so
## callers never index past a mid-resize array).
func soldier_facing(index: int) -> Vector2:
	if index < 0 or index >= _sim_soldier_facing.size():
		return facing
	return _sim_soldier_facing[index]


## Half-extent of the seeded soldier block around the regiment center: the
## containment radius the parallel layer must stay within while the regiment
## circle is authoritative. Reuses the render's block-extent math.
func soldier_block_extent() -> float:
	return SoldierFlock.compute_extent(self, formation_slots(soldiers))


## The render block's current half-size: the cached extent _process maintains as
## the block forms and takes casualties (what _draw sizes the state ring / selection halo /
## bars to). Unlike soldier_block_extent(), this returns the maintained field rather than a
## fresh recompute, so the demo-pointer overlay's selection halo matches the drawn block.
func render_block_extent() -> float:
	return _block_extent


## Seed the parallel soldier-body layer from the current formation. Deterministic
## and side-effect-free beyond `_sim_soldier_pos`. Read by the global separation
## pass and the flock render (phase 3), but NOT by gameplay (the regiment circle
## stays authoritative), so it changes no combat/movement/morale outcome.
func seed_sim_soldiers() -> void:
	SoldierBodies.seed(self)


## Advance this regiment's persistent soldier bodies one fixed step. The dynamics
## live in SoldierBodies.step (the engaged front ranks arrive at their slots under
## bounded force and hold displacement; the unengaged bulk tracks its moving slots).
func step_sim_soldiers(delta: float) -> void:
	SoldierBodies.step(self, delta)


# --- Individual-soldier simulation: engaged tier --------------------------
# The expensive per-soldier work (the friendly-avoidance steering pass and per-soldier
# melee) runs only for *engaged* soldiers — the front ranks of a regiment in (or just out
# of) melee — while the unengaged bulk keeps following its formation slot cheaply. This is
# the level-of-detail split from docs/individual-collision-design.md: it bounds the work
# to ~the contact faces rather than every soldier on the field. The steering pass is
# global across all regiments (see Battle's per-tick soldier orchestration and
# SoldierSteering), so friendly front ranks avoid each other across regiment lines.

# A regiment is "engaged" while FIGHTING and for ENGAGED_LINGER seconds after, so
# the tier boundary has hysteresis and soldiers don't flap between full-sim and
# formation-follow at the threshold. ENGAGED_RANKS front ranks run the full pass.
const ENGAGED_LINGER: float = 0.5
const ENGAGED_RANKS: int = 3

# Soldier->regiment coupling (phase 5): each tick the regiment center slides a fraction
# FOLLOW_RATE*delta of the way toward its soldiers' centroid (geometric decay, stable for
# FOLLOW_RATE*delta < 1; ~10%/tick at 60 Hz). The step is capped at MAX_FOLLOW_SPEED*delta
# so the center can never teleport -- it only ever moves at a bounded velocity, like the
# soldier bodies. During a clean march the bodies sit on their slots, so the drift is ~0
# and the coupling is silent; it activates only when bodies are pushed off formation.
const FOLLOW_RATE: float = 6.0
const MAX_FOLLOW_SPEED: float = 80.0

# > 0 while engaged; FIGHTING refreshes it, otherwise it decays on the fixed tick.
var _engaged_linger: float = 0.0


## Advance the engaged-tier latch. Deterministic — driven by combat state and the
## fixed-step delta, never wall-clock — so it reproduces on replay.
func tick_engaged(delta: float) -> void:
	if state == State.FIGHTING:
		_engaged_linger = ENGAGED_LINGER
	else:
		_engaged_linger = maxf(0.0, _engaged_linger - delta)


## True while this regiment is in the engaged tier (its front ranks run the full
## per-soldier pass). A function of the latch only.
func is_engaged() -> bool:
	return _engaged_linger > 0.0


## How braced (set to receive) this regiment's soldiers are, in [0, 1] (#201 bracing): a
## regiment engaged and not skirmishing is set and buttresses knockback/knockdown; a loose
## skirmish line, or one not engaged, is not. Binary for now -- graded postures (advancing /
## sprinting / braced) come with the posture slice. Front-facing is enforced at the call site.
const BRACE_SET: float = 1.0
func soldier_brace() -> float:
	return BRACE_SET if (is_engaged() and order_mode != ORDER_SKIRMISH) else 0.0


## Indices of the engaged soldiers: the front ENGAGED_RANKS ranks of an engaged
## regiment, or none when it isn't engaged. The formation grid is rank-major
## (rank = index / files, rank 0 = front), so the front ranks are exactly the
## first files*ENGAGED_RANKS indices -- using `files` FROM THE SAME GRID the
## regiment is actually laid out on (formation_files), not the wide-line
## frontage() a SQUARE unit no longer uses. Pure and deterministic.
func engaged_soldier_indices(count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not is_engaged() or count <= 0:
		return out
	var cutoff: int = mini(count, formation_files(count) * ENGAGED_RANKS)
	for i in range(cutoff):
		out.push_back(i)
	return out


## A soldier body's radius for this regiment's type — the drawn mark radius, so
## cavalry (horses) take more room than foot. The center-to-center floor between
## two soldiers is the sum of their radii, mirroring the regiment circle's
## `separation_radius + other.separation_radius`.
func soldier_body_radius() -> float:
	return CAV_MARK_RADIUS if is_cavalry else MARK_RADIUS


## This regiment's per-soldier strike reach, in world units: the weapon reach
## (attack_range, set per type from #233 — e.g. spear 48 vs sword 26). A soldier can
## strike an enemy body within this center-to-center distance; a longer reach lets a
## soldier strike foes who cannot strike back — the spear-vs-sword standoff (#240).
func soldier_reach() -> float:
	return attack_range


## Step every regiment's persistent soldier bodies one fixed tick. Called by Battle each
## tick, after the steering pass has set the bodies' friendly-avoidance velocity bias.
## Order-free across regiments, so it stays replay-safe. A far-tier regiment is skipped:
## it carries no bodies, and running the step would re-seed them from the formation
## (SoldierBodies.step's resize path), silently undoing the demotion every tick.
static func step_all_sim_soldiers(units: Array, delta: float) -> void:
	for o in units:
		var u: Unit = o as Unit
		if u != null and u.state != State.DEAD and u.tier != FormationTier.FAR:
			u.step_sim_soldiers(delta)


## Slide every regiment's center toward its soldiers' centroid (phase 5), after the bodies
## have integrated this tick. Order-free across regiments (each reads only its own bodies
## and writes only its own position), so it stays replay-safe. Called by Battle each tick
## as the last soldier sub-step. A far-tier regiment is skipped alongside the body step:
## with no bodies there is no centroid to couple to (couple() would no-op on n == 0
## anyway; the guard keeps the two soldier sub-steps gated identically).
static func couple_all_sim_soldiers(units: Array, delta: float) -> void:
	for o in units:
		var u: Unit = o as Unit
		if u != null and u.state != State.DEAD and u.tier != FormationTier.FAR:
			SoldierBodies.couple(u, delta)


# --- Individual-soldier combat profile -------------------------------------
# The per-soldier combat MATH lives in SoldierCombat.gd (the opposed land contest,
# the wound, the charge term, the facing gate, the per-type profile). Unit just
# exposes its own profile, reading its type flags and training.

## This regiment's per-soldier combat profile, from its own type flags and training.
## See SoldierCombat.profile_for / docs/combat-model.md "Soldier attributes".
func combat_profile() -> Dictionary:
	return SoldierCombat.profile_for(is_cavalry, anti_cavalry, is_ranged, training)


## The lethality of the weapon soldier `i` carries: the per-soldier weapon id
## resolved through the interned registry, so a per-soldier loadout change (a
## future weapon switch) changes combat immediately. Falls back to the unit's
## own type id when the array is out of sync (defensive; seed, resize, and
## casualty compaction keep it aligned), then to the baseline lethality 1 —
## a blow always has a real wounding power behind it.
func soldier_lethality(i: int) -> float:
	var type_id: int = _sim_soldier_weapon_id[i] if i < _sim_soldier_weapon_id.size() else weapon_type_id
	var w: Weapon = LoadoutRegistry.weapon(type_id)
	if w == null:
		w = LoadoutRegistry.weapon(weapon_type_id)
	return w.lethality if w != null else 1.0


## The block value of the shield soldier `i` carries, resolved through the
## per-soldier shield id — the shield's OWN contribution to active defence.
## The full defensive shield weight composes as the type's stance residual
## (combat_profile()'s "shield_residual") plus this block value; SoldierMelee
## does that addition at strike time. Same fallback chain as soldier_lethality;
## an unresolvable shield blocks nothing.
func soldier_shield_block(i: int) -> float:
	var type_id: int = _sim_soldier_shield_id[i] if i < _sim_soldier_shield_id.size() else shield_type_id
	var s: Shield = LoadoutRegistry.shield(type_id)
	if s == null:
		s = LoadoutRegistry.shield(shield_type_id)
	return s.block_value if s != null else 0.0


# --- Order summary (for the HUD / selection overlay) -----------------------

## Human-readable description of this unit's current order — what the player
## told it to do (attack a target, move to a point) or, failing an explicit
## order, what it's doing on its own. Shown in the HUD's selected-unit panel.
func order_summary() -> String:
	if state == State.ROUTING:
		return "Routing!"
	# A SUPPORT order is reported by its ward, ahead of the target/move lookups
	# below — a supporter holds no target_enemy/move_target of its own.
	if order_mode == ORDER_SUPPORT and UnitTargeting.support_valid(self):
		return "Supporting %s" % support_target.unit_name
	# A just-killed unit lingers one frame before queue_free() prunes it, and may
	# still hold a stale target_enemy. Skip the order lookups for it (and for an
	# idle unit) and fall through to the neutral "holding" text below.
	if state != State.DEAD:
		# A live relief reads off its order's swap link (phase 3), ahead of the target
		# lookup -- the reliever holds the tired unit's foe as target_enemy, which would
		# otherwise report a plain "Attacking".
		if current_order != null and current_order.type == Order.Type.RELIEF \
				and current_order.relief_partner != null \
				and is_instance_valid(current_order.relief_partner):
			return "Relieving %s" % current_order.relief_partner.unit_name
		# A routing target still counts (it's still a live, fightable enemy --- see
		# UnitTargeting.nearest_enemy's include_routing), so the HUD keeps reporting
		# "Attacking" rather than falling through to "Holding position".
		var has_target: bool = target_enemy != null and is_instance_valid(target_enemy) \
				and target_enemy.state != State.DEAD
		if has_target:
			return "Attacking %s" % target_enemy.unit_name
		# A maneuver in flight reads straight off the queue (phase 2): the drills and the
		# wheel used to fall through to "Holding position" here.
		if is_wheeling():
			return "Wheeling"
		if is_order_turning():
			if current_order.type == Order.Type.QUARTER_TURN:
				return "Quarter-turning"
			return "About-facing"   # the V-key drill, or a rear move's turn phase
		if current_order != null and current_order.phase == Order.Phase.REFORM:
			# The rear-move composite's middle phase: the ranks counter-march square to
			# the new heading before the march steps off. Without this the panel would
			# say "Holding position" between "About-facing" and the march, reading as
			# if the order had been dropped mid-composite.
			return "Re-forming"
		if has_move_target:
			var dest: String = "Moving to (%d, %d)" % [int(round(move_target.x)), int(round(move_target.y))]
			var legs: int = queued_move_points().size()
			if legs > 0:
				dest += " (+%d waypoint%s)" % [legs, "" if legs == 1 else "s"]
			return dest
		if state == State.FIGHTING:
			return "Engaged"
		if state == State.MOVING:
			return "Advancing on enemy"
	return "Holding position"


## Human-readable formation name for the HUD.
func formation_summary() -> String:
	match formation_mode:
		FORMATION_TIGHT:
			return "Tight"
		FORMATION_LOOSE:
			return "Loose"
		FORMATION_SQUARE:
			return "Square"
		FORMATION_SHIELD_WALL:
			return "Shield Wall"
		FORMATION_TESTUDO:
			return "Testudo"
		FORMATION_SCHILTRON:
			return "Schiltron"
		_:
			return "Normal"


## Shared "collision-exemption" primitive: a moving unit may pass cleanly through
## an IDLE friendly (and vice versa), so the pair interpenetrates instead of
## shoving. Re-enables on its own once the mover stops (both IDLE) or the friendly
## moves off. Enemies are never exempt; two non-idle friendlies are not exempt;
## routers (a separate state/group) are never exempt and still get shouldered.
## Line relief and merging build on this same exemption.
func _separation_exempt(other: Unit) -> bool:
	if _relief_paired_with(other):
		return true   # the swapping pair interpenetrates during a relief
	if other.team != team:
		return false
	# FIGHTING and ROUTING are implicitly non-exempt (neither is IDLE/MOVING), so
	# only a moving unit and a stationary idle friendly pass through each other.
	return (state == State.MOVING and other.state == State.IDLE) \
		or (state == State.IDLE and other.state == State.MOVING)


## True when this unit and `other` are the two sides of a live relief swap. The swap's
## execution state lives on the reliever's RELIEF order (Order.relief_partner -- phase 3),
## so the pair link is checked from either side: my live relief names the other, or the
## other's live relief names me. The tired unit carries no state of its own.
func _relief_paired_with(other: Unit) -> bool:
	return _relief_names(self, other) or _relief_names(other, self)


## Whether `a`'s current order is a relief whose live pass-through link names `b`.
static func _relief_names(a: Unit, b: Unit) -> bool:
	var o: Order = a.current_order
	return o != null and o.type == Order.Type.RELIEF and o.relief_partner == b


## This unit's share of a separation correction. Normally a pair splits it 50/50
## (soft separation). But an anti-cavalry spearman HOLDS THE LINE against enemy
## cavalry: the spearman yields nothing (0) and the charging horse is shoved fully
## clear (1), so cavalry can't ride through a spear screen. The total correction
## still sums to 1.0, so separation speed is unchanged — only who yields differs.
## Friendly pairs and every other enemy matchup stay soft (0.5).
func _push_share(other: Unit) -> float:
	if other.team == team:
		# A unit locked in melee is ANCHORED against arriving friendlies: the newcomer
		# yields and flows around it, instead of shoving the fighting unit out of
		# position (which made it rotate to re-face the enemy). Both engaged, or
		# neither, split the correction evenly as before.
		if is_engaged() == other.is_engaged():
			return 0.5
		if is_engaged():
			return 0.0   # I'm fighting — hold the line; the newcomer gives way
		return 1.0       # the other is fighting — I give way fully and flow around it
	if anti_cavalry and not is_cavalry and other.is_cavalry:
		return 0.0   # spearman holds firm against the charging cavalry
	if is_cavalry and other.anti_cavalry and not other.is_cavalry:
		return 1.0   # cavalry is shoved fully clear of the spear line
	return 0.5


## Neighbours to test for overlap. Uses the per-frame spatial hash that Battle
## rebuilds at the start of each tick (a local 3x3-block lookup, O(k) in the
## neighbourhood rather than O(n) over all units); falls back to a full
## units+routers group scan when no grid is current for this frame — e.g. a unit
## test that calls _separate() directly with no Battle running.
func _separation_candidates() -> Array:
	if SpatialHash.is_current(Engine.get_physics_frames()):
		return SpatialHash.query(position)
	var all: Array = get_tree().get_nodes_in_group("units")
	all.append_array(get_tree().get_nodes_in_group("routers"))
	return all


# --- Combat -----------------------------------------------------------------
# The regiment-level combat resolution (charge multiplier, strike, volley,
# friendly-fire interception, casualty/morale/rout bookkeeping) lives in UnitCombat;
# the AI brain and support tick call UnitCombat.strike/shoot. Only resolve_soldier_melee
# stays here — a thin delegate to the per-soldier SoldierMelee, kept for _strike and the
# soldier-melee tests.

## Resolve a melee cadence per soldier against `enemy`. The resolution lives in
## SoldierMelee.resolve (the opposed contest, the wound to per-soldier health, and
## the death/re-pack); this thin wrapper keeps the call from UnitCombat and the tests.
func resolve_soldier_melee(enemy: Unit) -> void:
	SoldierMelee.resolve(self, enemy)


# --- Order response & merge -------------------------------------------------
# The per-tick condition updates live in UnitMorale and the line-relief swap in
# UnitRelief (Unit's _physics_process calls UnitMorale.tick_* and UnitRelief.update each
# frame); the order-response countdown and the regiment merge (absorb) stay here.

## Start the order-response countdown. Called by Battle after stamping new
## motion fields onto the unit. The unit holds its current action for
## order_response_delay seconds before executing the new order.
func start_order_response() -> void:
	_order_response_timer = order_response_delay
	# A move/attack order reforms a quarter-turned unit back square to its heading, so it
	# marches as a proper line rather than crabbing sideways. The bodies ease onto the
	# reformed slots via the arrival dynamics (a future turn-and-widen move maneuver will make
	# this a deliberate reshape; until then a clean reform is the safe default). Also drop any
	# in-flight engage re-face turn: the order supersedes it and the reform squares the block.
	_formation_angle = 0.0
	_formation_mirror_x = false
	_engage_turn_target = Vector2.ZERO
	_engage_turn_enemy = null


## Commit a pending reform-before-move: hand off the stored destination to the
## normal move machinery. Called when the reform timer expires or a fighting unit
## receives a move order with reform=true (fights can't be made to hold for reform).
## A rear-move composite parked in its REFORM phase steps off into MARCH here.
func _commit_pending_reform() -> void:
	move_target = _reform_target
	has_move_target = true
	_reform_timer = 0.0
	_reform_until_settled = false
	if current_order != null and current_order.phase == Order.Phase.REFORM:
		current_order.phase = Order.Phase.MARCH


## Fold another friendly regiment into this one: pool soldiers, blend the
## combat stats weighted by strength, and start with a cohesion debuff that
## decays. The absorbed unit is removed. Caller guarantees same team.
func absorb(other: Unit) -> void:
	var a: float = float(soldiers)
	var b: float = float(other.soldiers)
	var total: float = a + b
	if total <= 0.0:
		return
	max_soldiers += other.max_soldiers
	# Strength-weighted blend so the bigger regiment dominates the result.
	attack = int(round((attack * a + other.attack * b) / total))
	defense = int(round((defense * a + other.defense * b) / total))
	morale = (morale * a + other.morale * b) / total
	fatigue = (fatigue * a + other.fatigue * b) / total
	soldiers += other.soldiers
	# Strangers debuff and a wider body for the combined regiment — capped so the
	# footprint never grows past melee reach (which would deadlock contact).
	cohesion = MERGE_COHESION_FLOOR
	separation_radius = minf(maxf(separation_radius, other.separation_radius) + 2.0,
		SEPARATION_RADIUS_MAX)
	_base_separation_radius = separation_radius
	set_formation(formation_mode)
	other._merged_away()
	queue_redraw()


## Remove a unit that has been absorbed by a merge (not a battle death). Any relief this
## unit was running dies with its orders queue (_remove_from_play -> clear_orders); a
## partner's relief pointing AT this unit resolves via UnitRelief.update's gone check.
func _merged_away() -> void:
	_remove_from_play()



# --- Death & routing -------------------------------------------------------

## Annihilated: every soldier lost to combat while still on the field (see
## UnitCombat.register_casualties's soldiers <= 0 check) --- distinct from a routing unit
## being shattered (stays in play, fleeing) or escaping (leaves play, but got away).
func _die() -> void:
	_remove_from_play()


## Shared teardown for leaving the battle (a death or a merge): mark dead,
## deselect, leave the units group, and free.
func _remove_from_play() -> void:
	state = State.DEAD
	selected = false
	clear_orders()
	remove_from_group("units")
	remove_from_group("routers")   # no-op unless removing a routing unit
	queue_free()


func _rout() -> void:
	if state == State.ROUTING:
		return
	state = State.ROUTING
	selected = false
	target_enemy = null
	has_move_target = false
	# A rout drops every in-progress maneuver: clear_orders interrupts the current order
	# (any in-place turn, wheel, or the rear-move march parked on it dies with the queue;
	# unit.facing stays at its current angle).
	clear_orders()
	_reform_timer = 0.0   # cancel any pending reform so a rallied unit doesn't resume a stale destination
	_reform_until_settled = false
	_reform_on_arrival = false
	_engage_turn_target = Vector2.ZERO # cancel any engage re-face turn
	_engage_turn_enemy = null
	_pin_down_exposure_cd = 0.0        # a rout ends the exposure window instead of freezing it open
	_formation_angle = 0.0             # a routed unit reforms square to its heading on rally
	_formation_mirror_x = false
	_rout_timer = ROUT_TIME
	# Deliberately no `_shattered = false` here: a fresh rout starts "broken"
	# (recoverable) only when it wasn't already permanently shattered by a
	# prior _stop_rout_and_fight(). That call returns the unit to State.IDLE
	# (so it can fight again), and a later morale collapse can route back
	# through here -- leaving `_shattered` untouched is what keeps that
	# "fights to the death" guarantee from being quietly undone.
	_combat_intermixing = 0.0
	remove_from_group("units")   # no longer counts as a fighting unit
	add_to_group("routers")
	# Routing is contagious: shake nearby friends.
	for u in get_tree().get_nodes_in_group("units"):
		var friend: Unit = u as Unit
		if friend != null and friend.team == team:
			if position.distance_to(friend.position) < ROUT_SHOCK_RADIUS:
				friend.morale -= 12.0
	# Cosmetic morale-shock ripple marking the area allies were shaken. Spawned on
	# the deterministic sim tick but animated/faded on render time, in no sim group, so
	# it has no simulation/replay/determinism impact. Guarded like the volley trail.
	if is_inside_tree():
		RoutShockwave.spawn(get_parent(), global_position, ROUT_SHOCK_RADIUS, team_color)
	queue_redraw()


func _process_rout(delta: float) -> void:
	# Flee toward own back edge (team 0 started at top, team 1 at bottom). Route around
	# impassable terrain via PathField.next_step() if available (same as _move_to does).
	# If trapped with no escape path, fall back to fighting to the death.
	var flee: Vector2 = Vector2.UP if team == 0 else Vector2.DOWN

	# Check for viable escape path using PathField (like _move_to does).
	# If trapped in terrain with no escape route, stop routing and fight instead.
	if PathField.active != null and _is_escape_path_blocked(flee):
		_stop_rout_and_fight()
		return

	# Route around terrain: consult PathField for the next safe step. Unlike _move_to's
	# explicit destination, fleeing has no fixed target -- just a direction -- so this
	# goes through next_step_fleeing(), which clips the far-off candidate point to the
	# field's own grid bounds first (mirroring has_escape_route() above). An unclipped
	# point 1000px out lands off the grid for virtually every real position, which A*
	# can never reach regardless of terrain -- silently defeating this whole detour.
	var step: Vector2 = position + flee * 1000.0
	if PathField.active != null:
		step = PathField.active.next_step_fleeing(position, flee)

	# next_step() returns an absolute world-space point, not a direction -- subtract
	# position first (as _move_to() does) before normalizing.
	var to: Vector2 = step - position
	var dir: Vector2 = to.normalized()
	_face_dir(dir)
	var next: Vector2 = position + dir * (move_speed * 1.3) * delta
	if next.x < retreat_bounds.position.x or next.x > retreat_bounds.end.x \
			or next.y < retreat_bounds.position.y or next.y > retreat_bounds.end.y:
		_escape()
		return
	position = next

	# A SHATTERED unit has lost its nerve for good: it just keeps fleeing (the movement
	# above already ran), with no morale recovery and no rally check ever again. The only
	# way out from here is _escape() (handled above).
	if _shattered:
		queue_redraw()
		return

	# Still "broken" (recoverable): the regiment's nerve steadies as it flees, while below
	# the baseline morale ticks up toward it at a rate proportional to the remaining gap,
	# so it recovers quickly at first and levels off. A unit already above the baseline has
	# nothing to recover toward.
	if morale < ROUT_RALLY_BASELINE:
		morale += (ROUT_RALLY_BASELINE - morale) * ROUT_MORALE_RECOVER_RATE * delta

	# Rally the moment morale recovers past the threshold, provided contact is broken and
	# enough men remain — the unit needn't run out the full timer or reach the edge.
	# Note: a unit that enters routing with morale already >= RALLY_MORALE_THRESHOLD rallies
	# on the first call here (a one-tick rout). In practice routing is triggered by depleted
	# morale so this is dormant; keep it in mind if non-morale rout triggers are ever added.
	if morale >= RALLY_MORALE_THRESHOLD and _can_rally():
		_rally()
		return

	_rout_timer -= delta
	if _rout_timer > 0.0:
		queue_redraw()
		return
	# Timer ran out: a unit that broke contact and kept enough men RALLIES back into
	# the fight; one still in contact, or gutted past reforming, SHATTERS --- it keeps
	# fleeing (still on the field, still fightable) but can never recover morale or rally
	# again from here on.
	if _can_rally():
		_rally()
	else:
		_shatter()


## Whether a routed unit recovers rather than shatters when its rout times out:
## it must have broken contact — no living enemy within RALLY_CONTACT_RADIUS — and still
## field enough men to reform (>= SHATTER_STRENGTH_FRAC of its max). Positions + counts
## only, so it's deterministic and replay-safe.
func _can_rally() -> bool:
	if soldiers < int(round(max_soldiers * SHATTER_STRENGTH_FRAC)):
		return false
	return UnitTargeting.nearest_enemy_to(self, position, RALLY_CONTACT_RADIUS) == null


## Recover from a rout: the unit reforms under the player's control at low,
## fragile morale and rejoins the fightable units — the inverse of the state/group
## changes _rout() made. It can be re-ordered, and can break again, from here.
func _rally() -> void:
	state = State.IDLE
	# Keep whatever nerve the unit steadied to while fleeing, but never below the fragile
	# floor — a unit that rallies the instant its timer expires still reforms shaken.
	morale = maxf(morale, RALLY_MORALE)
	_rout_timer = 0.0
	# _rout() zeroed _formation_angle so the unit "reforms square to its heading on rally"
	# (its own comment), but fleeing can re-fold it via _face_dir's snap-absorb (a sharp
	# turn away from the enemy at the moment routing starts). reform_ranks() is the
	# established mechanism for dropping that fold back to zero -- unlike a raw
	# `_formation_angle = 0.0`, it correctly arms _formation_mirror_x for an exact
	# about-face fold instead of point-reflecting the whole block.
	reform_ranks()
	# The orders queue (route legs included) was already dropped by _rout()'s
	# clear_orders(), so a rallied unit reforms with no orders.
	remove_from_group("routers")
	add_to_group("units")
	queue_redraw()


## Shatter: a routed ("broken") unit that couldn't recover in time --- still in contact,
## or gutted past reforming --- loses its nerve for good. It does NOT leave play: it stays
## on the field, still simulated, still fightable, and keeps fleeing forever (see
## _process_rout's _shattered branch) with no more morale recovery and no more rallying.
## The only way it ever leaves play from here is to flee clear of the map (_escape()), or
## be run down and annihilated in combat (soldiers reach zero, see UnitCombat).
func _shatter() -> void:
	_shattered = true


## Escape: a routing unit (broken or shattered) whose flight carried it past the
## retreat_bounds margin has fled clear of the battlefield entirely --- gone for good, but
## got away rather than being run down. The terminal counterpart to a rally; reuses the
## synchronous group teardown so it never lingers in a spatial-hash / separation scan
## after leaving play (queue_free() alone defers to end of frame).
func _escape() -> void:
	_remove_from_play()


## Check if escape path is blocked: true if all viable escape directions (within 90 degree
## cone around the team's flee direction) are impassable. Assumes PathField.active is set --
## the sole call site already guards on that, so routing proceeds unchecked when there's no
## terrain layer at all rather than reaching this function.
func _is_escape_path_blocked(flee_direction: Vector2) -> bool:
	# Scan directions around the flee vector: check a 90-degree cone
	# (45 degrees to each side of the primary flee direction).
	var angles_to_check: Array = []
	var base_angle: float = flee_direction.angle()
	for offset_deg in [-45.0, -30.0, -15.0, 0.0, 15.0, 30.0, 45.0]:
		angles_to_check.append(base_angle + deg_to_rad(offset_deg))

	# Check each direction: if ANY has a genuine route out, the path is not fully blocked.
	# PathField.has_escape_route() distinguishes "a route exists" from "no route,
	# fell back to the raw target" -- next_step()'s own return value can't tell those
	# apart, and it clips the candidate target to the field's own bounds so the check
	# isn't asking for a route to an inherently unreachable off-map point.
	for angle in angles_to_check:
		var direction: Vector2 = Vector2.from_angle(angle)
		if PathField.active.has_escape_route(position, direction):
			return false

	# All directions blocked: unit is trapped.
	return true


## Unit is trapped by terrain with no viable escape path: stop routing and stand ground
## to fight to the death. Marks the unit as shattered (will fight but can't rally/escape).
func _stop_rout_and_fight() -> void:
	# Exit routing state: rejoin the fighting units instead of routers.
	state = State.IDLE
	remove_from_group("routers")
	add_to_group("units")
	# Mark as shattered so the unit will fight to the death without rallying if it
	# happens to break contact temporarily. The unit will only leave play via
	# annihilation (soldiers reach zero) or being run down in combat.
	_shattered = true
	# Morale was <= 0 -- that's what triggered the original rout -- and left
	# untouched, UnitCombat.register_casualties' "morale <= 0.0 and state !=
	# ROUTING" guard re-satisfies on the very next casualty, calling _rout() again
	# and flipping this unit straight back into ROUTING (replaying the rout
	# SFX/shockwave and re-firing the friendly-morale contagion every casualty
	# tick, instead of the one stable transition this function is meant to make).
	# _shattered already forecloses any further rally, so restoring morale here
	# grants no actual recovery -- it only stops that spurious re-trigger.
	morale = RALLY_MORALE
	queue_redraw()


# --- Visuals ------------------------------------------------------------------

# Individual-soldier rendering (Stage A). The regiment is drawn as a formation
# block of one small mark per living soldier (cosmetic only — never fed back into the
# sim), packed roughly within the unit's footprint so the on-field size still matches
# the collision RADIUS. Wider-than-deep, like a real formation.
# Historically-grounded metric values: close-order per-man frontage is
# ~0.45 m (Battle.WORLD_UNITS_PER_METER = 20), and a foot soldier's mark is sized
# to match — shoulder-to-shoulder at close order, no gap and no overlap. Cavalry
# marks are sized to a horse's ~1 m body width. World-units, not px.
const FORMATION_SPACING: float = 9.0    # world units between soldier marks (0.45 m)
const FORMATION_ASPECT: float = 1.7     # files-to-ranks ratio (> 1 = wider than deep)
const MARK_RADIUS: float = 4.5          # foot soldier mark (0.45 m across)
const CAV_MARK_RADIUS: float = 10.0     # cavalry marks are larger (1 m horse body)

# Zoom level-of-detail. Zoomed out, each soldier is a flat geometric mark (a
# disc / rect / diamond) — cheap and legible at a glance. Zoomed in past
# LOD_ZOOM_IN the marks become detailed figure silhouettes (a standing soldier,
# a mounted rider), so the regiment reads as a crowd of individuals rather than a
# field of dots. The swap reverts below LOD_ZOOM_OUT; the gap between the two is
# hysteresis so the figures don't flicker on and off at the threshold.
const LOD_ZOOM_IN: float = 1.55
const LOD_ZOOM_OUT: float = 1.30
# The figure-silhouette geometry and its foot-render-kind enum (FOOT_INFANTRY / SPEAR /
# ARCHER) live in UnitMeshes; _foot_kind maps a unit's type flags onto one of them.
const FLAG_POLE_BASE_GAP: float = 34.0  # px above the block extent where the pole foot sits
const FLAG_POLE_HEIGHT: float = 18.0    # pole from above-bar to flag attachment point
const FLAG_WIDTH: float = 12.0          # horizontal extent of the flag rectangle
const FLAG_HEIGHT: float = 8.0          # vertical extent of the flag rectangle
# Facing pip size, as a fraction of the mark radius -- small enough to read as
# a facing cue on the figure, not a second body.
const FACING_PIP_RADIUS_FRACTION: float = 0.35


const PRONE_COLOR: Color = Color(0.22, 0.22, 0.22, 0.80)   # dark grey, 80% alpha — felled soldiers are slightly translucent; stacks with rout modulate (0.45) to 0.36 for "prone AND routing"


# --- Soldier mark rendering ----------------------------------------------
# Render-time only: each living soldier draws as a mark at its simulated body position
# (_sim_soldier_pos). The render reads the sim; it never writes back into it.


## Build the cosmetic render layer: a ground shadow (Polygon2D) and two MultiMeshes
## (outline behind, body in front) for the soldier marks. z_index is RELATIVE to this
## node (z=3), so the children sit at: shadow eff 1, outline/body eff 2 — under this
## node's chrome (_draw at eff 3) but above the field (z=0). The body is added after the
## outline so it draws in front of it at the same effective z. One-time setup in _ready().
func _setup_flock_renderer() -> void:
	var mark_r: float = CAV_MARK_RADIUS if is_cavalry else MARK_RADIUS
	# Two LOD variants per unit: the flat geometric mark (zoomed out) and the
	# detailed figure silhouette (zoomed in). Both are built up front; _update_lod
	# swaps which pair the MultiMeshes draw as the camera zooms.
	_build_mark_meshes(mark_r)
	_build_figure_meshes(mark_r)

	_shadow = Polygon2D.new()
	_shadow.polygon = _ellipse_polygon()
	_shadow.color = Color(0, 0, 0, 0.22)
	_shadow.z_index = -2   # eff 1: above the field, below the marks
	add_child(_shadow)

	_mm_outline = MultiMesh.new()
	_mm_outline.transform_format = MultiMesh.TRANSFORM_2D
	_mm_outline.use_colors = true   # required for set_instance_color; outline always stays WHITE (body carries the prone tint)
	_mm_outline.mesh = _mark_outline_mesh
	_mmi_outline = MultiMeshInstance2D.new()
	_mmi_outline.multimesh = _mm_outline
	_mmi_outline.z_index = -1   # eff 2
	add_child(_mmi_outline)

	_mm_body = MultiMesh.new()
	_mm_body.transform_format = MultiMesh.TRANSFORM_2D
	_mm_body.use_colors = true     # per-instance tint for prone soldiers
	_mm_body.mesh = _mark_body_mesh
	_mmi_body = MultiMeshInstance2D.new()
	_mmi_body.multimesh = _mm_body
	_mmi_body.z_index = -1   # eff 2, added after the outline -> drawn in front of it
	add_child(_mmi_body)

	# Facing pip: a small directional mark layered on the figure at figure LOD only
	# (instance_count 0 -- and so invisible -- at mark LOD, where the mark itself rotates).
	# White so it reads against any team colour; sized well below the figure/mark radius so
	# it's a facing cue, not a second body.
	_facing_pip_mesh = UnitMeshes.pointer_mesh(mark_r * FACING_PIP_RADIUS_FRACTION)
	_mm_facing_pip = MultiMesh.new()
	_mm_facing_pip.transform_format = MultiMesh.TRANSFORM_2D
	_mm_facing_pip.mesh = _facing_pip_mesh
	_mmi_facing_pip = MultiMeshInstance2D.new()
	_mmi_facing_pip.multimesh = _mm_facing_pip
	_mmi_facing_pip.modulate = Color(1, 1, 1, 0.9)
	_mmi_facing_pip.z_index = -1   # eff 2, drawn in front of the body (added last)
	add_child(_mmi_facing_pip)

	# The render reads _sim_soldier_pos directly; those bodies are seeded on the first
	# physics tick (Battle._on_soldier_tick -> SoldierBodies.step), so the marks appear
	# from frame 1. Size the shadow/chrome from the formation extent up front.
	_block_extent = SoldierFlock.compute_extent(self, formation_slots(soldiers))
	_update_shadow()


## Flat geometric mark meshes (zoomed-out LOD). Per-type shapes so soldiers read
## differently at a glance: spearmen = tall thin rectangle (shaft), archers =
## All three are now compact *directional* glyphs so that rotating each instance by its
## soldier's facing reads as an arrow at any angle: spearmen = a flat-backed dart, archers
## = a directional kite, cavalry/infantry = the standard pointer (semicircle + triangle
## tip). All three reach about as far forward as the pointer and stay no longer along the
## facing axis, so a rotated rank can't merge into a bar. The earlier spearmen rect and
## archer diamond were elongated/symmetric and, laid flat across a rank, striped.
func _build_mark_meshes(mark_r: float) -> void:
	if anti_cavalry:
		_mark_body_mesh    = UnitMeshes.dart_mesh(mark_r * 1.15)
		_mark_outline_mesh = UnitMeshes.dart_mesh(mark_r * 1.15 + 0.6)
	elif is_ranged:
		_mark_body_mesh    = UnitMeshes.kite_mesh(mark_r * 1.15)
		_mark_outline_mesh = UnitMeshes.kite_mesh(mark_r * 1.15 + 0.6)
	else:
		_mark_body_mesh    = UnitMeshes.pointer_mesh(mark_r)
		_mark_outline_mesh = UnitMeshes.pointer_mesh(mark_r + 0.6)


## Detailed figure-silhouette meshes (zoomed-in LOD): a standing soldier for foot,
## a mounted rider for cavalry. Both are shared/cached like the mark meshes. Foot
## soldiers carry a per-type item (spear / bow / shield) matching their mark shape.
## Each is baked facing right and mirrored facing left, so the render can swap meshes
## to face the unit's march direction.
func _build_figure_meshes(mark_r: float) -> void:
	var foot_kind: int = _foot_kind()
	_figure_body_mesh = UnitMeshes.figure_mesh(is_cavalry, foot_kind, mark_r, false, false)
	_figure_outline_mesh = UnitMeshes.figure_mesh(is_cavalry, foot_kind, mark_r, true, false)
	_figure_body_mesh_flip = UnitMeshes.figure_mesh(is_cavalry, foot_kind, mark_r, false, true)
	_figure_outline_mesh_flip = UnitMeshes.figure_mesh(is_cavalry, foot_kind, mark_r, true, true)


## Which foot-figure variant this unit uses, mirroring the per-type mark shapes
## (spearmen = shaft, archers = bow, everything else = shield). Cavalry ignores it.
func _foot_kind() -> int:
	if anti_cavalry:
		return UnitMeshes.FOOT_SPEAR
	if is_ranged:
		return UnitMeshes.FOOT_ARCHER
	return UnitMeshes.FOOT_INFANTRY


## Unit-radius ellipse outline (pre-squished) for the ground shadow; scaled in _update_shadow().
func _ellipse_polygon(segments: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts.push_back(Vector2(cos(a) * 1.1, sin(a) * 0.36))
	return pts



func _process(delta: float) -> void:
	_update_lod()
	if state == State.DEAD:
		if _mm_body.instance_count != 0:
			_mm_body.instance_count = 0
			_mm_outline.instance_count = 0
			_mm_facing_pip.instance_count = 0   # else pips linger a frame after a figure-LOD death
		return
	# Ease the flag's routing/normal translucency toward its target rather than snapping
	# (see ROUTING_ALPHA/ALPHA_FADE_RATE above) -- purely cosmetic, no gameplay effect.
	# Lives here (frame-rate _process), not _physics_process: a ROUTING unit's
	# _physics_process takes an early return before ever reaching its render tail, so an
	# update placed there would never run while a unit is actually routing -- the one
	# state that needs it. _draw() (where the flag is drawn) only re-executes on
	# queue_redraw(), so request one while the fade is still moving; once it settles,
	# stop asking for redraws on its account.
	var target_alpha: float = ROUTING_ALPHA if state == State.ROUTING else 1.0
	_render_alpha = move_toward(_render_alpha, target_alpha, ALPHA_FADE_RATE * delta)
	if not is_equal_approx(_render_alpha, _render_last_alpha):
		_render_last_alpha = _render_alpha
		queue_redraw()
	# Block extent depends only on the soldier count, frontage, and formation mode
	# (SQUARE/SHIELD_WALL/TESTUDO reshape the grid itself, not just frontage), not body
	# positions, so recompute (and reshape the shadow/chrome) only when one of those
	# changes — not the fresh PackedVector2Array the old path allocated every frame.
	var fr: int = UnitFormation.frontage(self)
	if soldiers != _render_extent_n or fr != _render_extent_frontage \
			or formation_mode != _render_extent_mode:
		_render_extent_n = soldiers
		_render_extent_frontage = fr
		_render_extent_mode = formation_mode
		# A far-tier block draws its marks on the formation grid itself, so a shape change
		# (count / frontage / density-mode) must relay the grid marks, not just the chrome.
		# Nothing else raises _render_dirty for a far unit (no bodies step), so raise it here.
		_render_dirty = true
		var new_extent: float = SoldierFlock.compute_extent(self, formation_slots(soldiers))
		if not is_equal_approx(new_extent, _block_extent):
			_block_extent = new_extent
			_update_shadow()
			queue_redraw()
	# Marks mirror the simulated bodies. Refresh only when something visible changed: a body
	# moved (SoldierBodies.step raised _render_dirty), the facing turned (mark rotation,
	# figure mirror and conversio squash all key off it), the unit is fighting (front-rank
	# churn / prone flips), or the instance count drifted from the body count. The routing
	# fade does NOT belong here -- it never touches the marks (see _apply_flock_color).
	if _render_dirty or facing != _render_last_facing or state == State.FIGHTING \
			or _mm_body.instance_count != _render_body_count():
		_render_dirty = false
		_render_last_facing = facing
		_refresh_flock_render()


## Swap the soldier meshes between the flat marks and the detailed figures based on
## the camera zoom, with hysteresis so the two don't flicker at the threshold. Cheap:
## a viewport lookup, a float compare, and a MultiMesh.mesh reassignment only on the
## frame the level actually flips. Runs at render time, like the rest of the flock.
func _update_lod() -> void:
	if _mm_body == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var want: bool = SoldierFlock.lod_should_detail(_detailed_lod, cam.zoom.x)
	# At the figure LOD the mesh also depends on facing: figures are mirrored to face the
	# unit's march direction. Re-evaluate when either the LOD level or the facing side flips.
	var flip: bool = want and facing.x < 0.0
	if want == _detailed_lod and flip == _figure_faces_left:
		return
	_detailed_lod = want
	_figure_faces_left = flip
	_apply_lod_meshes()


## Assign the mesh pair the MultiMeshes draw for the current LOD and, at the figure LOD,
## facing side. The flat marks are symmetric, so only the figures pick a left/right mirror.
## The facing pip only shows at figure LOD -- the flat mark already rotates to show
## facing, so a second indicator there would be redundant. _refresh_flock_render() runs
## right after so the pip's transforms are populated the same frame it appears, not a
## frame late.
func _apply_lod_meshes() -> void:
	if not _detailed_lod:
		_mm_body.mesh = _mark_body_mesh
		_mm_outline.mesh = _mark_outline_mesh
	elif _figure_faces_left:
		_mm_body.mesh = _figure_body_mesh_flip
		_mm_outline.mesh = _figure_outline_mesh_flip
	else:
		_mm_body.mesh = _figure_body_mesh
		_mm_outline.mesh = _figure_outline_mesh
	_mm_facing_pip.instance_count = _render_body_count() if _detailed_lod else 0
	_refresh_flock_render()


## Number of marks the flock render draws: the simulated bodies at close tier, or the
## aggregate living count at far tier (whose marks sit on the formation grid — a far-tier
## unit carries no per-soldier positions to mirror, but it must still be visible).
func _render_body_count() -> int:
	return soldiers if tier == FormationTier.FAR else _sim_soldier_pos.size()


## Push the current mark positions/colours into the two MultiMeshes (1 instance per mark).
## The figures' facing is handled by a mesh swap (see _apply_lod_meshes), not a per-instance
## transform — MultiMesh 2D can't store a reflected (mirrored) instance transform. At figure
## LOD the facing pip carries the exact per-soldier facing instead, since the figure
## itself only mirrors left/right.
func _refresh_flock_render() -> void:
	# A far-tier unit has no simulated bodies: draw its marks on the formation grid itself —
	# a pure function of the unit's aggregate fields (count, facing, formation shape), so this
	# is presentation only and revives no per-soldier sim state. The grid offsets are local to
	# the unit node (which itself marches), so a translating far block needs no per-frame
	# rewrite; facing/count/formation changes re-enter here via the _process refresh checks.
	var far_tier: bool = tier == FormationTier.FAR
	var far_locals := PackedVector2Array()
	var far_facings := PackedVector2Array()
	if far_tier:
		far_locals = formation_slots(soldiers)
		var grid_ang: float = facing.angle() + PI * 0.5 + _formation_angle
		for fi in range(far_locals.size()):
			far_locals[fi] = far_locals[fi].rotated(grid_ang)
		far_facings = soldier_world_facings(far_locals.size())
	var n: int = _render_body_count()
	if _mm_body.instance_count != n:
		_mm_body.instance_count = n
		_mm_outline.instance_count = n
	if _detailed_lod and _mm_facing_pip.instance_count != n:
		_mm_facing_pip.instance_count = n
	var sim_prone_n: int = _sim_prone.size()
	for i in range(n):
		# Prone: squash/rotate the mark and tint the body dark; outline stays WHITE.
		# (A far-tier unit tracks no prone timers; everyone draws standing.)
		var prone: bool = i < sim_prone_n and _sim_prone[i] > 0.0
		var pos: Vector2 = far_locals[i] if far_tier else _sim_soldier_pos[i] - position
		var sf: Vector2 = facing
		if far_tier:
			sf = far_facings[i]
		elif i < _sim_soldier_facing.size():
			sf = _sim_soldier_facing[i]
		var t: Transform2D
		if prone:
			if _detailed_lod:
				t = Transform2D(PI * 0.5, pos)
			else:
				t = Transform2D(Vector2(1.3, 0.0), Vector2(0.0, 0.3), pos)
		elif _detailed_lod and about_face_goal() != Vector2.ZERO:
			var progress: float = (facing.dot(-about_face_goal()) + 1.0) * 0.5
			var squash: float = abs(cos(progress * PI))
			t = Transform2D(Vector2(squash, 0.0), Vector2(0.0, 1.0), pos)
		elif not _detailed_lod:
			t = Transform2D(sf.angle(), pos)
		else:
			t = Transform2D(0.0, pos)
		_mm_body.set_instance_transform_2d(i, t)
		_mm_outline.set_instance_transform_2d(i, t)
		_mm_body.set_instance_color(i, PRONE_COLOR if prone else Color.WHITE)
		_mm_outline.set_instance_color(i, Color.WHITE)
		if _detailed_lod:
			_mm_facing_pip.set_instance_transform_2d(i, _facing_pip_transform(prone, sf, pos))
	_apply_flock_color()


## The facing pip's instance transform for one soldier: points along its exact
## facing at figure LOD (the figure mesh itself only mirrors left/right). A prone soldier
## has no meaningful facing to point along, so its pip collapses to zero scale instead of
## drawing an arrow off a body that's on the ground. Pure -- unit-testable independent of
## the live MultiMesh (whose instance data isn't synchronously readable back in headless
## tests).
static func _facing_pip_transform(prone: bool, sf: Vector2, pos: Vector2) -> Transform2D:
	if prone:
		return Transform2D(Vector2.ZERO, Vector2.ZERO, pos)
	return Transform2D(sf.angle(), pos)



## Tint the marks via the MultiMeshInstance modulate (one colour for the whole block, so
## no per-instance colour buffer): team colour for the body, a darkened shade for the
## outline. Only re-applied when the colour actually changes.
func _apply_flock_color() -> void:
	# Member icons never fade, even while routing -- only the regimental flag does
	# (ROUTING_ALPHA/_render_alpha, applied in _draw()). The soldiers themselves are
	# still physically present and fighting/fleeing; dimming their marks would read as
	# them becoming see-through, which isn't what a routing state means.
	var alpha: float = 1.0
	var body_c := Color(team_color.r, team_color.g, team_color.b, alpha)
	if body_c == _flock_color:
		return
	_flock_color = body_c
	_mmi_body.modulate = body_c
	_mmi_outline.modulate = Color(body_c.r * 0.35, body_c.g * 0.35, body_c.b * 0.35, alpha)
	_mmi_facing_pip.modulate = Color(1.0, 1.0, 1.0, alpha * 0.9)


## Size/position the ground shadow ellipse to the current block extent.
func _update_shadow() -> void:
	if _shadow == null:
		return
	var r: float = _block_extent * 0.95
	_shadow.position = Vector2(0, _block_extent * 0.45)
	_shadow.scale = Vector2(r, r)


func _draw() -> void:
	# Chrome (bars, state ring, shield overlay, soldier-ID text) always stays fully
	# opaque -- only the regimental flag fades while routing (see the flag call at the
	# end of this function, which uses _render_alpha directly instead of this constant).
	var alpha: float = 1.0
	var body_c := Color(team_color.r, team_color.g, team_color.b, alpha)
	var dark_c := Color(body_c.r * 0.35, body_c.g * 0.35, body_c.b * 0.35, alpha)
	var lite_c := Color(minf(body_c.r + 0.30, 1.0), minf(body_c.g + 0.30, 1.0),
			minf(body_c.b + 0.30, 1.0), alpha)

	# The soldier marks (Stage B) are rendered by the flocking MultiMeshes and the
	# ground shadow by a Polygon2D — both child nodes layered under this chrome via
	# z_index. _draw() handles only the screen-relative chrome: state ring, shielded-stance
	# overlay, selection halo and stat bars. `_block_extent` (maintained by _process) sizes
	# them to the live block rather than the bare collision radius.
	var extent: float = _block_extent

	# State ring around the block: red = engaged, orange = routing.
	match state:
		State.FIGHTING:
			draw_arc(Vector2.ZERO, extent + 2.0, 0, TAU, 36,
					Color(0.90, 0.15, 0.15, alpha), 3.0)
		State.ROUTING:
			draw_arc(Vector2.ZERO, extent + 2.0, 0, TAU, 36,
					Color(0.95, 0.50, 0.05, 1.0), 3.5)

	# Shielded-stance overlay: a locked shield line (shield wall), an overhead shield roof
	# (testudo), or a ring of outward spear ticks (the hollow square, orbis/schiltron)
	# -- drawn in the facing-rotated block frame so it rotates with the unit and
	# scales with the block. Stays visible at the zoomed-in figure LOD -- it represents
	# raised/overhead shields or the outward-facing ring, which the individual soldier
	# silhouettes alone don't read clearly at every zoom (especially the ring at mark LOD,
	# zoomed out). No-op in any other formation. Sized off the live formation shape, not
	# the bare radius.
	if formation_mode == FORMATION_SHIELD_WALL or formation_mode == FORMATION_TESTUDO \
			or in_square():
		draw_set_transform(Vector2.ZERO, facing.angle() + PI * 0.5, Vector2.ONE)
		UnitShields.draw(self, body_c, dark_c, lite_c)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if selected:
		draw_arc(Vector2.ZERO, extent + 4.0, 0, TAU, 36, Color(0.95, 0.95, 0.3), 2.5)

	# Strength bar + morale bar stacked above the block.
	var bw: float = 38.0
	var by: float = -extent - 16.0
	var frac: float = clampf(float(soldiers) / float(max_soldiers), 0.0, 1.0)
	var morale_frac: float = clampf(morale / 100.0, 0.0, 1.0)
	var morale_color: Color
	if morale_frac > 0.60:
		morale_color = Color(0.30, 0.80, 0.30, alpha)
	elif morale_frac > 0.30:
		morale_color = Color(0.85, 0.75, 0.10, alpha)
	else:
		morale_color = Color(0.85, 0.20, 0.10, alpha)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-bw * 0.5, by - 3.0), str(soldiers),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, alpha))
	# Strength (green).
	draw_rect(Rect2(-bw * 0.5, by, bw, 5.0), Color(0.15, 0.15, 0.15, alpha))
	draw_rect(Rect2(-bw * 0.5, by, bw * frac, 5.0), Color(0.30, 0.80, 0.30, alpha))
	# Morale (green → yellow → red as it degrades).
	draw_rect(Rect2(-bw * 0.5, by + 7.0, bw, 4.0), Color(0.15, 0.15, 0.15, alpha))
	draw_rect(Rect2(-bw * 0.5, by + 7.0, bw * morale_frac, 4.0), morale_color)

	# Soldier ID overlay (dev/debug visual, figure-LOD gated, selected unit only).
	# _sim_soldier_pos is parent-local (like the body MultiMesh above), so convert to this
	# node's own local drawing space the same way the body loop does: subtract `position`,
	# not to_local() (which expects a global/world position and would double-convert).
	if selected and Settings.show_soldier_ids and _detailed_lod:
		var id_mark_r: float = CAV_MARK_RADIUS if is_cavalry else MARK_RADIUS
		for i in range(_sim_soldier_pos.size()):
			draw_string(font, (_sim_soldier_pos[i] - position) + Vector2(-4, -id_mark_r),
					str(i), HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(1, 1, 1, 0.9))

	# The regimental flag is the one element that fades while routing (a wavering
	# standard reads as morale faltering); a separate faded color, not the chrome's
	# always-opaque body_c/alpha above.
	var flag_c := Color(team_color.r, team_color.g, team_color.b, _render_alpha)
	UnitSprites.flag(self, flag_c, _render_alpha, extent)
