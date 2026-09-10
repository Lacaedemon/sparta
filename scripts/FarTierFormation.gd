class_name FarTierFormation
extends RefCounted
## The aggregate far-tier formation record of the multi-resolution simulation design
## (docs/large-scale-simulation-design.md). A far-tier formation carries no per-soldier state
## at all — just this small fixed-size record, evolved by the coarse statistical rules in
## FarTierRules instead of per-soldier physics. Still isolated from play: the record and its
## rules are unit-tested on their own, but no live battle constructs or ticks one yet — the
## in-battle tier transition (TierTransition) keeps the unit's own scalar fields as the
## aggregate source of truth, so this record stays the vehicle for the isolated far-tier
## rules and the later far-vs-far battle orchestration.

## Living soldiers — the aggregate stand-in for the per-soldier array length.
var count: int = 0
## Unit-level morale scalar, same 0..100 scale as Unit.morale.
var morale: float = 100.0
## Formation centroid. Parent-local like Unit.position (the soldier arrays' frame).
var position: Vector2 = Vector2.ZERO
## Formation orientation, a unit vector like Unit.facing.
var facing: Vector2 = Vector2.DOWN
## Losses so far — the running total as count decreases over time, kept so a later
## promotion can reconstruct plausible losses without per-soldier history.
var casualties: int = 0
## Durable mode fields, carried over unchanged from the close tier. The design doc names
## them formation_mode / spacing / stance; in code the spacing knob is Unit.spacing_scale
## and the stance is Unit.order_mode, so the record mirrors those field names and types.
var formation_mode: int = 0   # Unit.FORMATION_* constant
var spacing_scale: float = Unit.NORMAL_SPACING_SCALE
var order_mode: int = 0   # Battle.OrderMode value, mirrored as a plain int like Unit.order_mode

## Durable regiment-level stats the far-tier rules (FarTierRules) read — the same unit-level
## scalars the close tier's regiment combat formula (UnitCombat) and march pacing use. They
## describe the formation as a whole, not its soldiers, so carrying them keeps the record
## fixed-size. Defaults mirror Unit's exported defaults where a zero would be misleading
## (reach and pace are real lengths/speeds); combat power defaults to zero so an empty
## record has none until a real unit's stats are copied in.
var max_soldiers: int = 0
var attack: int = 0
var defense: int = 0
## Melee reach, matching Unit.attack_range's default (the gladius baseline).
var attack_range: float = 26.0
## Sustained march pace, matching Unit.walk_speed's default: the walk, which is what the
## close tier's AUTO pacing holds for the whole approach. The sprint is a burst below the
## far tier's resolution (the terminal charge lasts seconds), so the record never carries
## it; a jog is not (a jog approach runs for the whole march), so it does -- see gait.
var march_speed: float = 45.0
## Jog pace, matching Unit.jog_speed's default; the pace the record moves at while gait
## is Unit.GAIT_JOG (FarTierRules.pace_speed).
var jog_speed: float = 67.5
## Sprint pace, matching Unit.move_speed's default; used by FarTierRules.tick_stamina
## to classify paces against the jog/sprint midpoint.
var sprint_speed: float = 90.0
## The formation's gait: Unit.GAIT_WALK (march_speed) or Unit.GAIT_JOG (jog_speed). The
## far tier's only two paces -- a walk approach, or a jog approach that arrives sooner and
## pays for it in stamina (FarTierRules.tick_stamina). from_unit maps a unit's ordered
## jog/run/sprint to the jog and everything else to the walk.
var gait: int = Unit.GAIT_WALK
## Aggregate stamina pool, the far tier's stand-in for the per-soldier
## Unit._sim_soldier_stamina array: one scalar in [0, max_stamina], following the same
## per-gait flow (rest regenerates, a walk is neutral, a jog drains) and scaling the
## formation's strike expectation through SoldierCombat.stamina_factor exactly as each
## close-tier soldier's own pool scales his blows. Defaults mirror the Infantry profile.
var stamina: float = 100.0
var max_stamina: float = 100.0
## The per-gait stamina rates, carried from the unit's own fields (Unit.stamina_rest_regen_per_s
## and siblings) so a demoted formation keeps paying the SAME rates it would at close tier.
## The record has no sprint gait for ordered march;
## routing flees at the sprint pace and bills stamina_sprint_drain_per_s.
var stamina_rest_regen_per_s: float = SoldierCombat.RHO_STAMINA
var stamina_walk_regen_per_s: float = SoldierCombat.RHO_STAMINA_WALK
var stamina_jog_drain_per_s: float = SoldierCombat.KAPPA_JOG
var stamina_sprint_drain_per_s: float = SoldierCombat.KAPPA_SPRINT
## Whether this formation is a ranged formation (archers), matching Unit.is_ranged's default.
## Drives FarTierRules' rate/reach split: a ranged formation strikes at RANGED_RANGE on the
## RANGED_INTERVAL/RANGED_DAMAGE_FACTOR cadence and never takes return melee attrition from a
## target beyond melee reach, mirroring how a close-tier archer skirmishes rather than presses.
var is_ranged: bool = false

## Fractional casualties accumulated by the far tier's continuous attrition rate, carried
## between ticks until a whole soldier falls (FarTierRules.tick_attrition). Sub-soldier
## BOOKKEEPING, not per-soldier state: one scalar per formation, no array. Persists across
## a disengage the way the close tier's attack timer does.
var casualty_carry: float = 0.0

## Rout state (a FarTierRules phase 2 follow-up) — the aggregate analog of
## Unit.state == State.ROUTING / Unit._rout_timer. A formation whose morale hits zero
## breaks (FarTierRules.is_broken); ROUTING is the persistent flag that keeps it fleeing
## rather than fighting even after morale recovers past zero (mirroring the close tier's
## rout arc, where morale climbs toward ROUT_RALLY_BASELINE while still routing).
## Ordinary combat/movement never sets these directly — only FarTierRules.enter_rout,
## tick_rout, rally, and shatter.
var routing: bool = false
## Counts down from rout_time below (default Unit.ROUT_TIME) while routing; when it (or the
## earlier rally check) resolves, the formation either rallies (routing = false, reduced
## morale) or shatters (count = 0), matching Unit._process_rout's timer.
var rout_timer: float = 0.0

## The three rout/rally thresholds Unit's own rout arc uses, carried forward from the live
## unit's own instance fields (Unit.rout_time/shatter_strength_frac/rally_morale_threshold --
## each caller-configurable, defaulting to Unit.ROUT_TIME/SHATTER_STRENGTH_FRAC/
## RALLY_MORALE_THRESHOLD) so a formation demoted to far tier keeps evaluating rout/rally
## against the SAME per-unit thresholds it would have at close tier, instead of silently
## falling back to the global default. Defaults here mirror Unit's own const defaults.
var rout_time: float = 6.0
var shatter_strength_frac: float = 0.15
var rally_morale_threshold: float = 35.0


## Snapshot a live unit's aggregate view — the pure reduction a real demotion will perform.
## Read-only and RNG-free (a deterministic function of the unit's fields, per the design
## doc's tier-boundary invariant); it copies values out, never mutates the unit. The actual
## demotion TRANSITION — dropping per-soldier state, swapping sim paths — is a later phase;
## this only builds the record.
static func from_unit(u: Unit) -> FarTierFormation:
	var rec := FarTierFormation.new()
	rec.count = u.soldiers
	rec.morale = u.morale
	rec.position = u.position
	rec.facing = u.facing
	rec.casualties = u.max_soldiers - u.soldiers
	rec.formation_mode = u.formation_mode
	rec.spacing_scale = u.spacing_scale
	rec.order_mode = u.order_mode
	rec.max_soldiers = u.max_soldiers
	rec.attack = u.attack
	rec.defense = u.defense
	rec.attack_range = u.attack_range
	rec.march_speed = u.walk_speed
	rec.jog_speed = u.jog_speed
	rec.sprint_speed = u.move_speed
	rec.gait = gait_for_ordered(u.ordered_gait())
	rec.stamina = u.mean_soldier_stamina()
	rec.max_stamina = u.combat_profile()["max_stamina"]
	rec.stamina_rest_regen_per_s = u.stamina_rest_regen_per_s
	rec.stamina_walk_regen_per_s = u.stamina_walk_regen_per_s
	rec.stamina_jog_drain_per_s = u.stamina_jog_drain_per_s
	rec.stamina_sprint_drain_per_s = u.stamina_sprint_drain_per_s
	rec.is_ranged = u.is_ranged
	rec.routing = u.state == Unit.State.ROUTING
	if rec.routing:
		rec.rout_timer = u._rout_timer
	rec.rout_time = u.rout_time
	rec.shatter_strength_frac = u.shatter_strength_frac
	rec.rally_morale_threshold = u.rally_morale_threshold
	return rec


## The far-tier gait a unit's ordered gait collapses to: a jog, run, or sprint order all
## become the jog (a run's or sprint's terminal burst is below this tier's resolution;
## its sustained leg is a jog), and a walk or AUTO order (-1) becomes the walk, which is
## what the AUTO ladder holds beyond the sprint window anyway.
static func gait_for_ordered(ordered_gait: int) -> int:
	return Unit.GAIT_JOG if ordered_gait >= Unit.GAIT_JOG else Unit.GAIT_WALK
