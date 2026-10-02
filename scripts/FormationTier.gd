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

# Promotion/demotion thresholds, in world units, applied to the distance Battle's tier
# pass measures: the EDGE GAP between two blocks (edge_gap: centre distance less each
# block's reach toward the other) when the block whose tier is decided has at most
# EDGE_GAP_MAX_SOLDIERS men, the centre-to-centre distance otherwise. Originally TUNED,
# on centre distance, against the tools/benchmark/
# measurements (the recorded numbers live in docs/large-scale-simulation-design.md,
# "Validating tier thresholds"). Two constraints pin PROMOTE_RANGE from both sides:
# - Floor (correctness): it must exceed auto-acquisition (Unit.DETECTION_RANGE, 190 --
#   the default a unit's own caller-configurable detection_range field starts at) plus
#   the charge runway (Unit.SPRINT_START_DISTANCE, 200), so a formation is back at
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


## The gap the tier pass judges two formations by: their centre distance less each
## block's reach toward the other (support_reach), never below zero. A deep block -- a
## cavalry squadron reaches 480 wu from its centre to its front -- is judged by where its
## front is, not by where its centre is. Face to face, the reaches are exactly the two
## half-depths and this is the true front-to-front distance. Obliquely, a reach is the
## rectangle's support distance, which is never less than where the line of centres
## leaves the block, so the gap can read shorter than the true edge distance: the error
## only ever promotes a block early or keeps it close-tier longer, never late.
static func edge_gap(centre_distance: float, reach_a: float, reach_b: float) -> float:
	return maxf(0.0, centre_distance - reach_a - reach_b)


## Default for Battle.tier_edge_gap_max_soldiers: the largest block, by deployed headcount,
## whose own tier the pass decides by the edge gap. A larger block's tier is decided by the
## centre distance, as before the edge gap existed. Tier is decided per formation, so
## judging a 4,000-8,000-man line by its front promotes every man in it: on cannae-scale,
## judging every block by edges took the close-tier bubble from 1,656 to 43,656 of 43,720
## soldiers, about 30x the tick cost, because its reserve corps read the small enemy
## cavalry's front within range. A small block still counts a big enemy's reach, so a
## cavalry squadron charging a huge line promotes before its front meets it; only small
## blocks promote that way, which keeps the cost bounded. The default roster's blocks
## (80-140 men, a cavalry squadron among them) sit well under it.
const EDGE_GAP_MAX_SOLDIERS: int = 500


## Whether the tier pass decides a block of `max_soldiers` deployed men's own tier by the
## edge gap (true, at or under `edge_gap_max_soldiers`) or by the centre distance.
static func judged_by_edge(max_soldiers: int, edge_gap_max_soldiers: int) -> bool:
	return max_soldiers <= edge_gap_max_soldiers


## How far a rectangular block with half-extents `half` (half-width along its files,
## half-depth along its ranks), turned to world angle `angle`, reaches from its centre
## toward world direction `dir`: the rectangle's support distance |x| * w + |y| * d, with
## (x, y) the unit direction in the block's own frame. Zero for a zero direction.
static func support_reach(half: Vector2, angle: float, dir: Vector2) -> float:
	if dir == Vector2.ZERO:
		return 0.0
	var local: Vector2 = dir.normalized().rotated(-angle)
	return absf(local.x) * half.x + absf(local.y) * half.y


## The tier pass's promote test on an edge gap: a far-tier formation whose nearest enemy
## is within `range_wu` of it, edge to edge, becomes close-tier. A pure predicate over
## already-serialized sim state -- no camera/attention signal -- so replay determinism
## can't depend on rendering. `range_wu` is a parameter (Battle.promote_range carries the
## per-battle value) because the default sits far outside every combat reach, so at the
## default a formation always promotes back to the close tier before it can be struck;
## a test or demo staging far-tier combat tightens it, and 0 never promotes, since two
## blocks in contact sit at a gap of exactly 0.
static func gap_promotes(gap: float, range_wu: float = PROMOTE_RANGE) -> bool:
	return gap < range_wu


## The tier pass's demote test on an edge gap: the mirror check against the farther
## DEMOTE_RANGE. Between the two thresholds neither fires.
static func gap_demotes(gap: float, range_wu: float = DEMOTE_RANGE) -> bool:
	return gap > range_wu


