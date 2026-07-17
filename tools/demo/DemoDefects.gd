class_name DemoDefects
extends RefCounted
## Deterministic defect metrics over a dumped state transcript: the algorithmic core of
## demo review. Every function here is pure (plain values in, plain values out -- no
## SceneTree, no RNG, no wall clock), so the whole module is directly GUT-testable and
## produces identical verdicts on every run of the same transcript.
##
## The input is the per-tick snapshot series a FULL state dump produces
## (SPARTA_DEMO_STATE_FULL=1 -- see tools/demo/DemoState.gd): each unit carries its
## actual body positions (`soldiers_full.pos`), its CANONICAL slot grid
## (`soldiers_full.slots` -- the ordered shape the bodies chase), and the per-unit
## motion constants thresholds derive from (`motion_ref`). Comparing ordered vs actual
## geometry decomposes "the formation looks wrong" into decidable stages:
##
##   1. ORIENTATION: the best-fit rigid rotation (2-D Kabsch) from slots onto bodies is
##      the block's true physical orientation; its magnitude is the turn lag behind the
##      commanded facing. Healthy = bounded and decaying after a commanded turn.
##   2. SHAPE: the RMS residual after removing that best-fit rotation + translation --
##      blob/smear/scramble irrespective of any legitimate turning.
##   3. SPACING: nearest-neighbour distances against the unit's own formation spacing --
##      compression (blobbing) and body overlap.
##
## plus per-series checks that need no reference geometry: facing whipsaw (direction
## reversals while marching), sustained super-physical per-soldier speed vs the unit's
## own gait caps, and slot misassignment (soldiers standing on each other's slots).
##
## Thresholds are expressed as fractions of the unit's OWN dumped constants (spacing,
## gaits), never absolute world-unit literals, so a retune of the sim retunes the
## verdicts with it. Post-contact samples (`engaged == true`) are exempt from the
## spacing/shape checks: melee press legitimately compresses and scrambles a block.

## Median-neighbour compression below this fraction of formation spacing, sustained for
## MIN_SUSTAIN consecutive pre-contact samples, is a blob verdict.
const BLOB_MED_FRAC := 0.75
## Min-neighbour distance below this fraction of formation spacing pre-contact means two
## soldiers effectively share ground -- an overlap verdict on any single sample.
const OVERLAP_MIN_FRAC := 0.25
## Shape residual (post-fit RMS slot error) above this fraction of formation spacing,
## sustained pre-contact, is a scramble/smear verdict.
const SHAPE_RMS_FRAC := 0.75
## Facing direction reversals (sign flips of the per-sample rotation, each at least
## WHIPSAW_MIN_SWING) beyond this count, over samples where the unit is MOVING, is a
## whipsaw verdict. Calibrated against a legitimate S-shaped terrain detour, which
## produces up to three genuine direction changes over a march (onto the corridor,
## around the far corner, back onto the target); pathological whipsaw (the march-swirl
## signature) oscillates well past that.
const WHIPSAW_MAX_REVERSALS := 4
const WHIPSAW_MIN_SWING_DEG := 10.0
## A soldier moving faster than this multiple of the unit's own sprint, sustained for
## MIN_SUSTAIN consecutive samples, is super-physical (a single-sample spike is a
## legitimate knockback/contact impulse and exempt).
const SUPERPHYSICAL_SPEED_FRAC := 1.15
## More than this fraction of a unit's soldiers standing closer to some OTHER soldier's
## slot than their own (measured against the FIT-ALIGNED grid, so legitimate turn lag --
## a rigid offset the Kabsch fit removes -- cannot fire it), sustained pre-contact, is a
## misslot verdict: the men settled on each other's positions (rank/flank swapping).
const MISSLOT_MAX_FRAC := 0.25
## Consecutive-sample count that turns a transient reading into a sustained verdict.
const MIN_SUSTAIN := 2


## Nearest-neighbour distance stats for one body array. O(n^2), fine at regiment sizes.
static func nnd_stats(positions: Array) -> Dictionary:
	var n: int = positions.size()
	if n < 2:
		return {"min": 0.0, "median": 0.0}
	var nnds: Array = []
	for i in range(n):
		var best := INF
		for j in range(n):
			if i == j:
				continue
			var d: float = _vec(positions[i]).distance_to(_vec(positions[j]))
			best = minf(best, d)
		nnds.append(best)
	nnds.sort()
	return {"min": nnds[0], "median": nnds[floori(n / 2.0)]}


## Best-fit rigid transform (2-D Kabsch/Procrustes, rotation + translation, no scale)
## from `slots` onto `positions`: the fitted angle is the block's true physical
## orientation relative to its ordered grid, and the residual RMS is the shape error
## that remains after granting the block that rotation -- scramble, not turning.
static func kabsch_fit(slots: Array, positions: Array) -> Dictionary:
	var n: int = mini(slots.size(), positions.size())
	if n == 0:
		return {"angle": 0.0, "residual_rms": 0.0}
	var slot_c := Vector2.ZERO
	var pos_c := Vector2.ZERO
	for i in range(n):
		slot_c += _vec(slots[i])
		pos_c += _vec(positions[i])
	slot_c /= n
	pos_c /= n
	# Optimal rotation maximizes sum(dot(R*s_i, p_i)) -> theta = atan2(sum cross, sum dot).
	var dot_sum := 0.0
	var cross_sum := 0.0
	for i in range(n):
		var s: Vector2 = _vec(slots[i]) - slot_c
		var p: Vector2 = _vec(positions[i]) - pos_c
		dot_sum += s.dot(p)
		cross_sum += s.cross(p)
	var angle: float = atan2(cross_sum, dot_sum)
	var sq_err := 0.0
	for i in range(n):
		var s: Vector2 = (_vec(slots[i]) - slot_c).rotated(angle) + pos_c
		sq_err += s.distance_squared_to(_vec(positions[i]))
	return {"angle": angle, "residual_rms": sqrt(sq_err / n)}


## How many soldiers stand strictly closer to some OTHER soldier's slot than to their
## own -- the slot-misassignment count behind rank/flank-swap defects. Transiently
## nonzero during a legitimate reshape; sustained high counts mean bodies settled on
## the wrong slots. Callers that want turning-tolerant counts pass FIT-ALIGNED slots
## (see aligned_slots), so a rigid rotation/translation the whole block shares cannot
## read as misassignment -- only identity scramble can.
static func misslotted_count(slots: Array, positions: Array) -> int:
	var n: int = mini(slots.size(), positions.size())
	var count := 0
	for i in range(n):
		var own: float = _vec(positions[i]).distance_squared_to(_vec(slots[i]))
		for j in range(n):
			if j == i:
				continue
			if _vec(positions[i]).distance_squared_to(_vec(slots[j])) < own:
				count += 1
				break
	return count


## The slot grid carried onto the bodies by kabsch_fit's own best rigid transform:
## rotate about the slot centroid by the fitted angle, then translate the centroid onto
## the body centroid. Comparing bodies against THESE slots isolates identity questions
## (who stands where) from the block's overall rotation/translation state.
static func aligned_slots(slots: Array, positions: Array, fit: Dictionary) -> Array:
	var n: int = mini(slots.size(), positions.size())
	if n == 0:
		return []
	var slot_c := Vector2.ZERO
	var pos_c := Vector2.ZERO
	for i in range(n):
		slot_c += _vec(slots[i])
		pos_c += _vec(positions[i])
	slot_c /= n
	pos_c /= n
	var out: Array = []
	var angle: float = float(fit["angle"])
	for i in range(n):
		var p: Vector2 = (_vec(slots[i]) - slot_c).rotated(angle) + pos_c
		out.append([p.x, p.y])
	return out


## Direction reversals in a facing-angle series: sign flips between consecutive
## rotation steps, counting only swings of at least `min_swing` radians on each side
## of the flip (sub-threshold jitter is not a reversal).
static func facing_reversals(angles: Array, min_swing: float) -> int:
	var reversals := 0
	var prev_step := 0.0
	for i in range(1, angles.size()):
		var step: float = angle_difference(float(angles[i - 1]), float(angles[i]))
		if absf(step) < min_swing:
			continue
		if prev_step != 0.0 and signf(step) != signf(prev_step):
			reversals += 1
		prev_step = step
	return reversals


## Fastest per-soldier speed (wu/s) between two consecutive body arrays sampled
## `dt_ticks` physics ticks apart. Index-aligned; a casualty compaction between the two
## samples makes indexes disagree, so callers skip sample pairs whose counts differ.
static func max_soldier_speed(prev: Array, cur: Array, dt_ticks: int, tps: float = 60.0) -> float:
	var n: int = mini(prev.size(), cur.size())
	if n == 0 or dt_ticks <= 0:
		return 0.0
	var dt: float = float(dt_ticks) / tps
	var best := 0.0
	for i in range(n):
		best = maxf(best, _vec(prev[i]).distance_to(_vec(cur[i])) / dt)
	return best


## Analyze a whole transcript: `snapshots` is an Array of parsed state-dump Dictionaries
## (each with "tick" and "units", the units carrying soldiers_full + motion_ref -- i.e. a
## FULL dump). Returns per-uid metric series and a flat `verdicts` array; every verdict
## carries {uid, metric, pass, worst, threshold} so a caller (CI step, local runner) can
## gate or report without re-deriving anything.
static func analyze(snapshots: Array) -> Dictionary:
	var series: Dictionary = {}   # uid -> {ticks, nnd_min, nnd_med, angle, residual, ...}
	for snap in snapshots:
		for u in snap["units"]:
			if not u.has("soldiers_full") or not u.has("motion_ref"):
				continue
			var uid: int = int(u["uid"])
			if not series.has(uid):
				series[uid] = {
					"ticks": [], "engaged": [], "moving": [], "counts": [],
					"nnd_min": [], "nnd_med": [], "angle": [], "residual": [],
					"misslotted": [], "facing_angle": [], "pos": [],
					"motion_ref": u["motion_ref"],
				}
			var s: Dictionary = series[uid]
			var bodies: Array = u["soldiers_full"]["pos"]
			var slots: Array = u["soldiers_full"]["slots"]
			var nnd: Dictionary = nnd_stats(bodies)
			var fit: Dictionary = kabsch_fit(slots, bodies)
			s["ticks"].append(int(snap["tick"]))
			s["engaged"].append(bool(u.get("engaged", false)))
			s["moving"].append(String(u.get("state", "")) == "MOVING")
			s["counts"].append(bodies.size())
			s["nnd_min"].append(nnd["min"])
			s["nnd_med"].append(nnd["median"])
			s["angle"].append(fit["angle"])
			s["residual"].append(fit["residual_rms"])
			# Misassignment counted against the fit-aligned grid: rigid turn lag is the
			# fit's to explain; only who-stands-where survives into this series.
			s["misslotted"].append(
					misslotted_count(aligned_slots(slots, bodies, fit), bodies)
					/ maxf(1.0, float(bodies.size())))
			var fa: Array = u.get("facing", [0.0, 1.0])
			s["facing_angle"].append(atan2(float(fa[1]), float(fa[0])))
			s["pos"].append(u["soldiers_full"]["pos"])
	var verdicts: Array = []
	for uid in series:
		verdicts.append_array(_unit_verdicts(int(uid), series[uid]))
	return {"series": series, "verdicts": verdicts}


static func _unit_verdicts(uid: int, s: Dictionary) -> Array:
	var out: Array = []
	var spacing: float = float(s["motion_ref"]["formation_spacing"])
	var sprint: float = float(s["motion_ref"]["move_speed"])
	var n: int = s["ticks"].size()

	# Blob: median-neighbour compression, sustained, pre-contact only.
	out.append(_sustained_verdict(uid, "blob", s, "nnd_med",
			spacing * BLOB_MED_FRAC, true, MIN_SUSTAIN))
	# Overlap: any single pre-contact sample with two soldiers effectively co-located.
	out.append(_sustained_verdict(uid, "overlap", s, "nnd_min",
			spacing * OVERLAP_MIN_FRAC, true, 1))
	# Shape scramble: post-fit residual, sustained, pre-contact only.
	out.append(_sustained_verdict(uid, "shape_residual", s, "residual",
			spacing * SHAPE_RMS_FRAC, true, MIN_SUSTAIN, true))
	# Slot misassignment: the fraction of soldiers nearer another man's (fit-aligned)
	# slot than their own, sustained, pre-contact only.
	out.append(_sustained_verdict(uid, "misslotted", s, "misslotted",
			MISSLOT_MAX_FRAC, true, MIN_SUSTAIN, true))

	# Facing whipsaw while marching.
	var moving_angles: Array = []
	for i in range(n):
		if s["moving"][i]:
			moving_angles.append(s["facing_angle"][i])
	var reversals: int = facing_reversals(moving_angles, deg_to_rad(WHIPSAW_MIN_SWING_DEG))
	out.append({"uid": uid, "metric": "facing_whipsaw", "pass": reversals <= WHIPSAW_MAX_REVERSALS,
			"worst": reversals, "threshold": WHIPSAW_MAX_REVERSALS})

	# Sustained super-physical soldier speed (index-aligned samples only).
	var cap: float = sprint * SUPERPHYSICAL_SPEED_FRAC
	var over_run := 0
	var worst_speed := 0.0
	var worst_run := 0
	for i in range(1, n):
		if s["counts"][i] != s["counts"][i - 1]:
			over_run = 0   # casualty compaction: indexes no longer align across the gap
			continue
		var dt: int = int(s["ticks"][i]) - int(s["ticks"][i - 1])
		var v: float = max_soldier_speed(s["pos"][i - 1], s["pos"][i], dt)
		worst_speed = maxf(worst_speed, v)
		over_run = over_run + 1 if v > cap else 0
		worst_run = maxi(worst_run, over_run)
	out.append({"uid": uid, "metric": "superphysical_speed", "pass": worst_run < MIN_SUSTAIN,
			"worst": worst_speed, "threshold": cap})
	return out


## Shared shape for threshold-over-a-series verdicts. `below` chooses the failing side
## (true = failing when the value drops BELOW the threshold). Pre-contact gating skips
## engaged samples; `sustain` consecutive failing samples fail the verdict.
static func _sustained_verdict(uid: int, metric: String, s: Dictionary, key: String,
		threshold: float, pre_contact_only: bool, sustain: int, above: bool = false) -> Dictionary:
	var run := 0
	var worst_run := 0
	var worst := INF if not above else 0.0
	for i in range(s["ticks"].size()):
		if pre_contact_only and s["engaged"][i]:
			run = 0
			continue
		var v: float = float(s[key][i])
		worst = maxf(worst, v) if above else minf(worst, v)
		var failing: bool = v > threshold if above else v < threshold
		run = run + 1 if failing else 0
		worst_run = maxi(worst_run, run)
	if worst == INF:
		worst = 0.0
	return {"uid": uid, "metric": metric, "pass": worst_run < sustain,
			"worst": worst, "threshold": threshold}


## Every tick an `expect` list needs a snapshot at: scalar ticks verbatim, [lo, hi]
## ranges contribute both ends (range expectations are evaluated against whatever
## snapshots exist inside the range, so the ends guarantee at least two probes). The
## recorder merges these into its state-dump tick set, so declaring an expectation is
## enough to make the data it checks exist.
static func expect_ticks(expects: Array) -> Array:
	var out: Array = []
	for e in expects:
		var t = e.get("tick")
		var ticks: Array = t if t is Array else [t]
		for v in ticks:
			var tick: int = int(v)
			if not out.has(tick):
				out.append(tick)
	out.sort()
	return out


## Evaluate declared demo intent against a dumped transcript: each expectation is
## {tick: N or [lo, hi], uid, field, value} and passes when the named unit's dumped
## record field equals the value at that tick (or at ANY snapshot inside the range --
## ranges express drift-tolerant claims like "engages between 780 and 840"). Returns
## one verdict per expectation, shaped like analyze()'s own verdicts so callers gate
## the same way. A missing snapshot, unit, or field is a failure, not a skip: an
## expectation that cannot be checked is an authoring error the run must surface.
static func check_expectations(expects: Array, snapshots: Array) -> Array:
	var out: Array = []
	for e in expects:
		var t = e.get("tick")
		var lo: int = int(t[0]) if t is Array else int(t)
		var hi: int = int(t[1]) if t is Array else int(t)
		var uid: int = int(e.get("uid", -1))
		var field: String = str(e.get("field", ""))
		var expected = e.get("value")
		var probed := false
		var passed := false
		var actual = null
		for snap in snapshots:
			var tick: int = int(snap.get("tick", -1))
			if tick < lo or tick > hi:
				continue
			for u in snap.get("units", []):
				if int(u.get("uid", -1)) != uid:
					continue
				if not u.has(field):
					continue
				probed = true
				actual = u[field]
				if _values_match(expected, actual):
					passed = true
			if passed:
				break
		var when: String = str(lo) if lo == hi else "%d-%d" % [lo, hi]
		out.append({"uid": uid, "metric": "expect:%s@%s" % [field, when],
				"pass": probed and passed,
				"worst": actual if actual != null else "(no snapshot/unit/field in range)",
				"threshold": expected})
	return out


static func _values_match(expected, actual) -> bool:
	if (expected is float or expected is int) and (actual is float or actual is int):
		return absf(float(expected) - float(actual)) < 0.001
	return str(expected) == str(actual)


static func _vec(pair) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))
