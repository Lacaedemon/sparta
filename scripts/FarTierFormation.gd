class_name FarTierFormation
extends RefCounted
## Phase 1 of the multi-resolution simulation design (docs/large-scale-simulation-design.md):
## the aggregate far-tier formation record. A far-tier formation carries no per-soldier state
## at all — just this small fixed-size record, evolved by coarse statistical rules (a later
## phase) instead of per-soldier physics. Representational only for now: the type exists and
## is unit-tested in isolation, but nothing in the sim constructs or reads one during play.

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
	return rec
