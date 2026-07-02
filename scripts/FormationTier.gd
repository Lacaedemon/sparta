class_name FormationTier
extends RefCounted
## The per-formation simulation-tier ids and the distance-hysteresis promotion/demotion
## triggers of the multi-resolution simulation design (docs/large-scale-simulation-design.md).
## Distinct from the RENDER LOD (Unit._update_lod's mark/figure swap), which is a camera-zoom
## presentation choice — the simulation tier decides how much sim STATE a formation carries.
## Battle evaluates these predicates each tick and performs the transitions themselves via
## TierTransition (the seeded reconstruction / lossy reduction across the tier boundary).

## CLOSE: full individual-soldier fidelity (the _sim_soldier_* arrays) — today's only live path.
## FAR: aggregate/statistical record (FarTierFormation), no per-soldier state at all.
enum { CLOSE, FAR }

## Explicit table (not a reflected enum) so transcript/dump names stay stable as members are
## added, and an out-of-range int reads as a greppable "TIER(<n>)" instead of silently dropping.
const TIER_NAMES := {
	CLOSE: "CLOSE",
	FAR: "FAR",
}

# Placeholder promotion/demotion thresholds, in world units. PROVISIONAL values, not yet
# tuned: the real numbers come from sweeping the tools/benchmark/ scale runs against the
# measured close-tier soldier-count ceiling in a later phase of the design doc.
# PROMOTE_RANGE sits well outside auto-acquisition (Unit.DETECTION_RANGE, 190) plus the
# charge runway (Unit.SPRINT_START_DISTANCE, 200), so a formation is back at individual
# fidelity before it can detect, shoot at, or charge anything. DEMOTE_RANGE is 1.5x
# further out — a hysteresis gap, so a formation drifting near one boundary doesn't
# thrash between tiers tick to tick.
const PROMOTE_RANGE: float = 400.0
const DEMOTE_RANGE: float = 600.0


## Int tier id -> readable name, falling back to "TIER(<n>)" for an unmapped value.
static func tier_name(value: int) -> String:
	return TIER_NAMES.get(value, "TIER(%d)" % value)


## Placeholder promote trigger: a far-tier formation at `formation_pos` becomes close-tier
## when the nearest enemy (contact point, or nearest enemy formation before any contact)
## closes within PROMOTE_RANGE. Deliberately a pure predicate over two already-serialized
## positions — no camera/attention signal — so replay determinism can't depend on rendering.
static func should_promote(formation_pos: Vector2, nearest_enemy_pos: Vector2) -> bool:
	return formation_pos.distance_to(nearest_enemy_pos) < PROMOTE_RANGE


## Placeholder demote trigger: the mirror check against the farther DEMOTE_RANGE. Between
## the two thresholds neither predicate fires, so the formation keeps its current tier.
static func should_demote(formation_pos: Vector2, nearest_enemy_pos: Vector2) -> bool:
	return formation_pos.distance_to(nearest_enemy_pos) > DEMOTE_RANGE
