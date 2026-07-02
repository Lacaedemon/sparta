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

# Promotion/demotion thresholds, in world units — TUNED against the tools/benchmark/
# measurements (the recorded numbers live in docs/large-scale-simulation-design.md,
# "Validating tier thresholds"). Two constraints pin PROMOTE_RANGE from both sides:
# - Floor (correctness): it must exceed auto-acquisition (Unit.DETECTION_RANGE, 190)
#   plus the charge runway (Unit.SPRINT_START_DISTANCE, 200), so a formation is back at
#   individual fidelity before it can detect, shoot at, or charge anything.
# - Ceiling (budget): the benchmark puts the reference engaged front (~1,700 soldiers,
#   all close-tier) right at the 16.67ms/tick budget on the dev PC, and doubling it
#   2.2x over — so the promoted bubble has no headroom for a second echelon, and the
#   right threshold is the smallest one that still satisfies the combat floor.
# DEMOTE_RANGE is 1.5x further out — a hysteresis gap, so a formation drifting near one
# boundary doesn't thrash between tiers tick to tick. It is also the depth at which a
# deployed reserve actually demotes: the echelon-battle benchmark pair measures reserves
# beyond it demoting on spawn (promoted bubble = the fronts) while reserves parked inside
# the band keep their close spawn tier for good. Re-tune when per-soldier realism grows —
# rerun the sweep plus the echelon pair and update the design doc's recorded numbers.
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
