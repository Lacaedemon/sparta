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
var spacing_scale: float = 1.0
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
## Sustained march pace, matching Unit.walk_speed's default. The close tier's AUTO pacing
## walks by default and only jogs under fire or sprints on the terminal charge — bursts
## below the far tier's resolution, so the aggregate marches at the walk.
var march_speed: float = 45.0

## Fractional casualties accumulated by the far tier's continuous attrition rate, carried
## between ticks until a whole soldier falls (FarTierRules.tick_attrition). Sub-soldier
## BOOKKEEPING, not per-soldier state: one scalar per formation, no array. Persists across
## a disengage the way the close tier's attack timer does.
var casualty_carry: float = 0.0


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
	return rec
