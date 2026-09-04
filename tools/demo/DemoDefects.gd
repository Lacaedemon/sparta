class_name DemoDefects
extends RefCounted
## Deterministic defect metrics over a dumped state transcript: the algorithmic core of
## demo review. Every function here is pure (plain values in, plain values out -- no
## SceneTree, no RNG, no wall clock), so the whole module is directly GUT-testable and
## produces identical verdicts on every run of the same transcript.
##
## Must not reference Unit (or any script that uses the Settings autoload): this file
## is loaded by analyze_transcript.gd under bare `godot -s`, which has no autoloads.
## DistanceLegend is a leaf (WorldScale only) and is safe to preload. The HUD
## caption rebuild preloads it at the formation-label helpers below, not here,
## so this class docstring stays one block.
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
## Thresholds are expressed as fractions of the unit's OWN dumped constants (body
## radius for the physical-contact floors, grid pitch for the grid-deviation ones,
## gaits for speed), never absolute world-unit literals, so a retune of the sim
## retunes the verdicts with it. The grid/spacing checks -- and path_crossing,
## which needs both ends of a step admitted -- judge only the samples
## judged_mask() admits: samples in enemy CONTACT are exempt (melee press
## legitimately compresses and scrambles a block), as are ROUTING samples,
## samples adjacent to a contact flip, the sample right after a casualty
## compaction, and lone survivors -- see judged_mask's own doc for each
## rationale, including why contact reads `engaged` OR `in_enemy_contact`
## rather than `engaged` alone.

## Spacing floors derive from BODY GEOMETRY, not grid pitch: pitch is where the
## formation posts its slots, the body radius is how close two men can physically
## stand, and the two only coincide on isotropic foot grids (0.45 m pitch, 0.45 m
## body). Deriving from pitch scaled the floors up with cavalry's roomy grid and
## flagged ordinary combat press as defects. `two_bodies` below is the summed
## radii of a touching pair (2r) read from motion_ref, with a spacing/2-per-radius
## fallback for transcripts dumped before the field existed (exact for every
## current type, where min-pitch happens to equal the body diameter).
##
## Median-neighbour compression below this fraction of two touching bodies'
## summed radii, sustained for MIN_SUSTAIN consecutive judged samples, is a blob
## verdict -- bodies stacked well inside each other on MEDIAN, not merely packed.
const BLOB_BODY_FRAC := 0.5
## ...floored at this fraction of the grid pitch, so a genuine collapse on a
## roomy grid still fires even for hypothetical types with bodies much smaller
## than their pitch.
const BLOB_PITCH_FRAC := 0.25
## Min-neighbour distance below this fraction of two touching bodies' summed
## radii means two soldiers effectively share ground -- an overlap verdict on
## any single judged sample.
const OVERLAP_BODY_FRAC := 0.25
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
## legitimate knockback/contact impulse and exempt). Read from GaitLimits.gd -- the leaf
## script SoldierBodies.step()'s own engine-side clamp reads too -- rather than a second
## hand-kept copy of the fraction, so the metric's threshold and the engine's physical
## ceiling can never drift apart.
## Positions in transcripts round to DemoState's coordinate precision, which can add up to
## speed_quantization_margin(dt) worst-case measurement error to a soldier moving at the cap;
## the check admits that rounding allowance before judging speed super-physical.
const GaitLimitsRef = preload("res://scripts/GaitLimits.gd")
const SUPERPHYSICAL_SPEED_FRAC := GaitLimitsRef.SUPERPHYSICAL_SPEED_FRAC
## Must match DemoState.POSITION_DECIMAL_PLACES; cannot preload DemoState here because it pulls Unit.gd and Settings autoload into bare godot -s.
const POSITION_DECIMAL_PLACES := 2
## Dump position quantum (wu) derived from DemoState's coordinate rounding.
const POSITION_QUANTUM: float = pow(10.0, -float(POSITION_DECIMAL_PLACES))
## Samples after the last contact sample that stay exempt from grid-shape judgments,
## allowing a disengaging unit time to re-form.
const CONTACT_SETTLE_SAMPLES := 2
## More than this fraction of a unit's soldiers standing closer to some OTHER soldier's
## slot than their own (measured against the FIT-ALIGNED grid, so legitimate turn lag --
## a rigid offset the Kabsch fit removes -- cannot fire it), sustained pre-contact, is a
## misslot verdict: the men settled on each other's positions (rank/flank swapping).
## Identity is only meaningful once the men are actually STANDING ON the grid: while a
## block is in transit (a reshape, a march re-form) every body is between slots and
## "whose slot is nearest" is noise, so the fraction only counts on samples where the
## mean nearest-ANY-slot distance is within MISSLOT_SETTLED_FRAC of the spacing.
const MISSLOT_MAX_FRAC := 0.25
const MISSLOT_SETTLED_FRAC := 0.25
## Two soldiers whose routes cross swapped sides on the way to wherever they were going,
## rather than each walking to the nearest place that needed filling. Routes are measured
## in the block's own co-rotating frame (the rigid motion the whole block shares is
## removed first), so a wheel, a march, or an about-face cannot manufacture crossings.
## Only residual travel beyond this fraction of the grid pitch counts as a route at all --
## shorter residuals are jostle under press, not a journey across the block.
const CROSS_MIN_TRAVEL_FRAC := 0.5
## More than this fraction of a unit's soldiers taking crossing routes between two
## consecutive judged samples is a crossing verdict. An assignment minimizing total travel
## provably has no crossing straight-line paths -- swapping any crossing pair shortens the
## total -- so this is a direct reading of how far a reshape's slot assignment sits from
## optimal, not a proxy for it.
## Sized against the catalog rather than guessed: a legitimate big reshape (a schiltron
## forming, a square reform under the proximity pairing that fixed it) peaks around 0.14
## of the block and then goes quiet, while a reshape whose slots are dealt by array index
## holds a fifth to a half of the block on crossing routes for sample after sample. Pure
## translations and turns read a flat zero. Hence a threshold just above the healthy peak,
## plus MIN_SUSTAIN: both discriminators have to agree before a verdict fails.
const CROSS_MAX_FRAC := 0.15
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


## Worst-case speed error (wu/s) introduced by two rounded position endpoints sampled
## `dt_ticks` physics ticks apart. Each coordinate rounds to POSITION_QUANTUM, so each
## endpoint can drift by up to half a quantum in x and y (worst-case Euclidean error
## sqrt(2) * 0.5 * quantum). Two endpoints drifting in opposite directions introduce up
## to sqrt(2) * quantum displacement error over dt.
static func speed_quantization_margin(dt_ticks: int, tps: float = 60.0) -> float:
	if dt_ticks <= 0:
		return 0.0
	var dt: float = float(dt_ticks) / tps
	return (POSITION_QUANTUM * sqrt(2.0)) / dt


## Do two open segments properly cross? Orientation (cross-product sign) test on both
## pairs. Collinear and endpoint-touching cases are not crossings worth reporting, and
## exact zeros are measure-zero in float body data anyway.
static func _segments_cross(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var d1: float = (a2 - a1).cross(b1 - a1)
	var d2: float = (a2 - a1).cross(b2 - a1)
	var d3: float = (b2 - b1).cross(a1 - b1)
	var d4: float = (b2 - b1).cross(a2 - b1)
	return ((d1 > 0.0) != (d2 > 0.0)) and ((d3 > 0.0) != (d4 > 0.0))


## Which soldiers take a CROSSING route between two consecutive body samples -- the
## route-quality question every other metric here structurally cannot ask, because the
## rest all score where the men END UP and a bad route still reaches a good end state.
##
## The block's own rigid motion between the two samples is removed first (the same
## best-fit transform kabsch_fit and aligned_slots already use), so what remains per
## soldier is his travel WITHIN his own formation. A rigid rotation or translation of the
## whole block therefore leaves every residual path empty and can never register a
## crossing. Paths shorter than `min_travel` are dropped before any pairing, so ordinary
## press-jitter cannot accumulate into a verdict.
##
## Index-aligned: both samples must describe the same men in the same order, so callers
## skip pairs spanning a casualty compaction (which renumbers everyone). O(n^2) in the
## routed subset, which is empty for a block that is merely marching.
static func crossing_indices(prev: Array, cur: Array, min_travel: float) -> Array:
	var n: int = mini(prev.size(), cur.size())
	if n < 2:
		return []
	var fit: Dictionary = kabsch_fit(prev, cur)
	var start: Array = aligned_slots(prev, cur, fit)
	var routed: Array = []
	for i in range(n):
		if _vec(start[i]).distance_to(_vec(cur[i])) >= min_travel:
			routed.append(i)
	var crossed: Dictionary = {}
	for a in range(routed.size()):
		var i: int = routed[a]
		for b in range(a + 1, routed.size()):
			var j: int = routed[b]
			if crossed.has(i) and crossed.has(j):
				continue
			if _segments_cross(_vec(start[i]), _vec(cur[i]), _vec(start[j]), _vec(cur[j])):
				crossed[i] = true
				crossed[j] = true
	var out: Array = crossed.keys()
	out.sort()
	return out


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
					"ticks": [], "engaged": [], "in_enemy_contact": [],
					"moving": [], "routing": [], "counts": [],
					"formation": [], "frontage": [],
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
			# Physical press, not the combat-state decision: the two drop at different
			# moments (see judged_mask). Absent from transcripts dumped before the field
			# existed, where false leaves the mask exactly as `engaged` alone made it.
			s["in_enemy_contact"].append(bool(u.get("in_enemy_contact", false)))
			s["moving"].append(String(u.get("state", "")) == "MOVING")
			s["routing"].append(String(u.get("state", "")) == "ROUTING")
			s["counts"].append(bodies.size())
			s["formation"].append(String(u.get("formation", "")))
			s["frontage"].append(int(u.get("frontage", 0)))
			s["nnd_min"].append(nnd["min"])
			s["nnd_med"].append(nnd["median"])
			s["angle"].append(fit["angle"])
			s["residual"].append(fit["residual_rms"])
			# Misassignment counted against the fit-aligned grid: rigid turn lag is the
			# fit's to explain; only who-stands-where survives into this series -- and
			# only on samples where the men are actually standing on the grid (see
			# MISSLOT_SETTLED_FRAC): a body in transit is between slots, so its nearest
			# slot's identity is noise, not a swap.
			var aligned: Array = aligned_slots(slots, bodies, fit)
			var spacing_now: float = float(u["motion_ref"]["formation_spacing"])
			var settled: bool = _mean_nearest_slot_distance(aligned, bodies) \
					<= spacing_now * MISSLOT_SETTLED_FRAC
			s["misslotted"].append(
					misslotted_count(aligned, bodies) / maxf(1.0, float(bodies.size()))
					if settled else 0.0)
			var fa: Array = u.get("facing", [0.0, 1.0])
			s["facing_angle"].append(atan2(float(fa[1]), float(fa[0])))
			s["pos"].append(u["soldiers_full"]["pos"])
	var verdicts: Array = []
	for uid in series:
		verdicts.append_array(_unit_verdicts(int(uid), series[uid]))
	if not series.is_empty():
		verdicts.append_array(check_hud_consistency(snapshots))
	return {"series": series, "verdicts": verdicts}


## Which samples the grid/spacing-reference verdicts (blob, overlap, shape,
## misslot) actually judge -- and, one step removed, path_crossing, which
## measures a route between two samples and so needs BOTH of them admitted.
## The exemption those checks are built around is
## CONTACT -- a block with enemy bodies in among its own is legitimately
## compressed and scrambled, so the grid spacing it reads there says nothing
## about the formation code. Contact is `engaged` OR `in_enemy_contact`, not
## `engaged` alone: the first is a combat-state decision, the second is
## physical proximity, and they do not drop together. A regiment relieved out
## of a melee stops being `engaged` the moment the bookkeeping hands the fight
## over, while its men stay pressed against the enemy for tens of ticks
## afterwards as they back out -- so keying on `engaged` alone judged that
## whole window, reading the melee's own compression as a formation defect.
##
## Beyond contact, a sample is also exempt when:
## - the unit is ROUTING: a fleeing mob is legitimately not on any slot grid,
##   so grid-referenced geometry there is noise, not a defect;
## - it sits NEXT TO a contact sample in the series (the transition window):
##   a block charging into or peeling out of contact legitimately compresses
##   in the sampled moments just before contact flips, and judging one side
##   of the flip while exempting the other made verdicts a lottery on where
##   the sample landed relative to first contact; the post-contact buffer extends
##   to CONTACT_SETTLE_SAMPLES because a unit disengaging between two bouts needs
##   more than one sampled second to re-form;
## - the soldier count dropped since the previous sample: casualties compact
##   the arrays and the survivors converge on re-dealt slots, a legitimate
##   transient the superphysical check already skips for the same reason;
## - the unit reshaped (formation mode or frontage change) on the current or
##   preceding sample: ranks expanding, contracting, or wheeling to new slots
##   are in physical transit during the transition window;
## - fewer than 2 bodies remain: nnd_stats returns zeros for a lone survivor,
##   which would read as maximal compression forever.
static func judged_mask(s: Dictionary) -> Array:
	var n: int = s["ticks"].size()
	var contact: Array = []
	for i in range(n):
		contact.append(bool(s["engaged"][i]) or bool(s["in_enemy_contact"][i]))
	var reshaped: Array = []
	for i in range(n):
		reshaped.append(i > 0 and (
				(s.has("formation") and s["formation"].size() > i and String(s["formation"][i]) != String(s["formation"][i - 1]))
				or (s.has("frontage") and s["frontage"].size() > i and int(s["frontage"][i]) != int(s["frontage"][i - 1]))
		))
	var mask: Array = []
	for i in range(n):
		var ok: bool = not contact[i] and not s["routing"][i] \
				and int(s["counts"][i]) >= 2
		var post_contact := false
		for k in range(1, CONTACT_SETTLE_SAMPLES + 1):
			if i - k >= 0 and contact[i - k]:
				post_contact = true
				break
		if ok and (post_contact or (i > 0 and (int(s["counts"][i]) < int(s["counts"][i - 1]) or reshaped[i] or reshaped[i - 1]))):
			ok = false
		if ok and i + 1 < n and contact[i + 1]:
			ok = false
		mask.append(ok)
	return mask


static func _unit_verdicts(uid: int, s: Dictionary) -> Array:
	var out: Array = []
	var spacing: float = float(s["motion_ref"]["formation_spacing"])
	# Two touching bodies' summed radii (2r): the physical floor basis. Older
	# transcripts predate the soldier_body_radius field; spacing/2 per radius is
	# exact for every current type (min-pitch equals the body diameter), so the
	# fallback keeps merge-base sides of a defect delta comparable.
	var two_bodies: float = 2.0 * float(s["motion_ref"].get(
			"soldier_body_radius", spacing * 0.5))
	var sprint: float = float(s["motion_ref"]["move_speed"])
	var n: int = s["ticks"].size()
	var mask: Array = judged_mask(s)

	# Blob: median-neighbour compression, sustained -- bodies stacked well inside
	# each other on median, floored at a pitch fraction for roomy-grid collapse.
	out.append(_sustained_verdict(uid, "blob", s, "nnd_med",
			maxf(two_bodies * BLOB_BODY_FRAC, spacing * BLOB_PITCH_FRAC), mask, MIN_SUSTAIN))
	# Overlap: any single judged sample with two soldiers effectively co-located.
	out.append(_sustained_verdict(uid, "overlap", s, "nnd_min",
			two_bodies * OVERLAP_BODY_FRAC, mask, 1))
	# Shape scramble: post-fit residual, sustained. Pitch-based deliberately --
	# it measures deviation from the ordered grid, where pitch IS the basis.
	out.append(_sustained_verdict(uid, "shape_residual", s, "residual",
			spacing * SHAPE_RMS_FRAC, mask, MIN_SUSTAIN, true))
	# Slot misassignment: the fraction of soldiers nearer another man's (fit-aligned)
	# slot than their own, sustained.
	out.append(_sustained_verdict(uid, "misslotted", s, "misslotted",
			MISSLOT_MAX_FRAC, mask, MIN_SUSTAIN, true))

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
		var margin: float = speed_quantization_margin(dt)
		over_run = over_run + 1 if v > cap + margin else 0
		worst_run = maxi(worst_run, over_run)
	out.append({"uid": uid, "metric": "superphysical_speed", "pass": worst_run < MIN_SUSTAIN,
			"worst": worst_speed, "threshold": cap})

	# Crossing routes: soldiers swapping sides on the way to wherever they are going.
	# Deliberately NOT routed through _sustained_verdict. That helper forgives a series
	# that steadily improves, which is exactly the shape a reshape's crossing count has --
	# it falls to zero as the men arrive. Forgiving convergence here would forgive the
	# very defect this metric exists to catch, since a bad route still converges on a
	# correct end state; that is why the settled-state metrics cannot see this at all.
	var min_travel: float = spacing * CROSS_MIN_TRAVEL_FRAC
	var worst_cross := 0.0
	var cross_run := 0
	var worst_cross_run := 0
	for i in range(1, n):
		if s["counts"][i] != s["counts"][i - 1] or not (bool(mask[i]) and bool(mask[i - 1])):
			cross_run = 0   # renumbered by a casualty, or an exempt sample
			continue
		var crossed: int = crossing_indices(s["pos"][i - 1], s["pos"][i], min_travel).size()
		var frac: float = float(crossed) / maxf(1.0, float(s["counts"][i]))
		worst_cross = maxf(worst_cross, frac)
		cross_run = cross_run + 1 if frac > CROSS_MAX_FRAC else 0
		worst_cross_run = maxi(worst_cross_run, cross_run)
	out.append({"uid": uid, "metric": "path_crossing", "pass": worst_cross_run < MIN_SUSTAIN,
			"worst": worst_cross, "threshold": CROSS_MAX_FRAC})
	return out


## Fraction of meaningful improvement between consecutive failing samples below which
## a transition no longer counts as converging (see _sustained_verdict).
const CONVERGING_IMPROVEMENT_FRAC := 0.05


## Shared shape for threshold-over-a-series verdicts. `below` chooses the failing side
## (true = failing when the value drops BELOW the threshold). `mask` marks which
## samples are judged (see judged_mask; an empty mask judges everything);
## `sustain` consecutive failing samples fail the verdict -- but a
## failing sample that meaningfully IMPROVES on its predecessor resets the run rather
## than extending it. A legitimate long transition (a drag-widen reshape walking sixty
## men onto a new grid, a big commanded turn) reads far out of tolerance for many
## samples while steadily converging on it; a genuine defect holds or worsens. The
## convergence test is what separates them without any knowledge of maneuvers.
static func _sustained_verdict(uid: int, metric: String, s: Dictionary, key: String,
		threshold: float, mask: Array, sustain: int, above: bool = false) -> Dictionary:
	var run := 0
	var worst_run := 0
	var worst := INF if not above else 0.0
	var prev_v := NAN
	for i in range(s["ticks"].size()):
		if not mask.is_empty() and not bool(mask[i]):
			run = 0
			prev_v = NAN
			continue
		var v: float = float(s[key][i])
		worst = maxf(worst, v) if above else minf(worst, v)
		var failing: bool = v > threshold if above else v < threshold
		if not failing:
			run = 0
		else:
			var improving := false
			if not is_nan(prev_v):
				var dt: float = float(int(s["ticks"][i]) - int(s["ticks"][i - 1])) if i > 0 else 60.0
				var dt_scale: float = maxf(0.1, dt / 60.0)
				var margin: float = absf(prev_v) * CONVERGING_IMPROVEMENT_FRAC * dt_scale
				improving = (v < prev_v - margin) if above else (v > prev_v + margin)
			run = 1 if improving else run + 1
		worst_run = maxi(worst_run, run)
		prev_v = v
	if worst == INF:
		worst = 0.0
	return {"uid": uid, "metric": metric, "pass": worst_run < sustain,
			"worst": worst, "threshold": threshold}


## Every tick an `expect` list needs a snapshot at: scalar ticks verbatim, [lo, hi]
## ranges contribute both ends (range expectations are evaluated against whatever
## snapshots exist inside the range, so the ends guarantee at least two probes). The
## recorder merges these into its state-dump tick set, so declaring an expectation is
## enough to make the data it checks exist. Malformed entries (a bare number where an
## object belongs -- the adjacent `state` field's shape, an easy slip) contribute no
## ticks rather than crashing the live recording; their loud failure is the
## analyzer's validation, which the recorder cannot reach mid-record.
static func expect_ticks(expects: Array) -> Array:
	var out: Array = []
	for e in expects:
		if expect_entry_error(e) != "":
			continue
		var t = e.get("tick")
		var ticks: Array = t if t is Array else [t]
		for v in ticks:
			var tick: int = int(v)
			if not out.has(tick):
				out.append(tick)
	out.sort()
	return out


## Shape-validate one `expect` entry: returns an empty string when usable, else a
## message naming what's wrong. Pure, so the CLI can reject a malformed script with
## the exit-2 usage contract BEFORE evaluation, and check_expectations can stay
## crash-free on entries that reach it anyway (a [480] range typo must surface as an
## error, never as an out-of-bounds abort).
static func expect_entry_error(e) -> String:
	if not (e is Dictionary):
		return "entry is not an object"
	var t = e.get("tick")
	var tick_ok: bool = (t is float or t is int) \
			or (t is Array and (t as Array).size() == 2 \
				and (t[0] is float or t[0] is int) and (t[1] is float or t[1] is int))
	if not tick_ok:
		return "tick must be a number or a [lo, hi] pair"
	if not (e.get("uid") is float or e.get("uid") is int):
		return "missing numeric uid"
	if str(e.get("field", "")) == "":
		return "missing field"
	if not e.has("value"):
		return "missing value"
	return ""


## Evaluate declared demo intent against a dumped transcript: each expectation is
## {tick: N or [lo, hi], uid, field, value} and passes when the named unit's dumped
## record field equals the value at that tick (or at ANY snapshot inside the range --
## ranges express drift-tolerant claims like "engages between 780 and 840"). Returns
## one verdict per expectation, shaped like analyze()'s own verdicts so callers gate
## the same way. A missing snapshot, unit, or field is a failure, not a skip: an
## expectation that cannot be checked is an authoring error the run must surface.
## A malformed entry likewise yields a FAILED verdict naming the shape problem (the
## CLI additionally rejects malformed scripts up front with its usage exit code).
static func check_expectations(expects: Array, snapshots: Array) -> Array:
	var out: Array = []
	for e in expects:
		var shape_error: String = expect_entry_error(e)
		if shape_error != "":
			out.append({"uid": -1, "metric": "expect:(malformed entry)", "pass": false,
					"worst": shape_error, "threshold": str(e)})
			continue
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


## Shape-validate one `defect_exemptions` entry: empty string when usable, else a message
## naming what's wrong. An entry names the units it covers and states why:
##
##   "defect_exemptions": { "path_crossing": {"uids": [0], "reason": "..."} }
##
## Both fields are mandatory. The reason, because an exemption without a stated
## justification is indistinguishable from someone silencing a real defect, and the whole
## value of a deterministic scan is that suppressing it has to be argued in writing. The
## uid list, because most clips carry several units and a metric-wide exemption would
## forgive every one of them -- including a unit whose failure is genuine and unrelated to
## the maneuver being excused. Naming the units keeps an exemption as narrow as the claim
## behind it.
static func exemption_error(metric, entry) -> String:
	if not (metric is String) or String(metric).strip_edges().is_empty():
		return "exemption key must be a metric name"
	if not (entry is Dictionary):
		return "exemption for '%s' must be an object with `uids` and `reason`" % str(metric)
	var uids = (entry as Dictionary).get("uids")
	if not (uids is Array) or (uids as Array).is_empty():
		return "exemption for '%s' needs a non-empty `uids` list" % str(metric)
	for u in uids:
		if not (u is float or u is int):
			return "exemption for '%s' has a non-numeric uid: %s" % [str(metric), str(u)]
	var reason = (entry as Dictionary).get("reason")
	if not (reason is String) or String(reason).strip_edges().is_empty():
		return "exemption for '%s' needs a non-empty reason" % str(metric)
	return ""


## Apply a demo script's declared `defect_exemptions` to its verdicts. A verdict is
## forgiven only when BOTH its metric and its uid are named, and it then carries the
## reason so the analyzer prints it as EXEMPT rather than silently dropping it -- an
## exemption stays visible in every run's output.
##
## The per-uid match is what keeps an exemption honest. `analyze` flattens every unit's
## verdicts into one array, so matching on metric alone would forgive a second unit's
## genuine, unrelated failure in the same clip, and that collapsed verdict set feeds the
## website demo-diff comparison as well as the gating scan.
##
## `stale_exempt` marks a named unit whose metric was passing anyway: that unit no longer
## trips the check, so its claim has outlived its reason and wants removing. Scoping by
## uid is what makes this readable on a multi-unit clip -- a metric-wide match would report
## STALE off whichever unit happened to be passing, and acting on it would delete the
## exemption another unit still needs. A stale exemption is reported, not failed: failing
## it would redden the very PR that fixed the underlying defect.
##
## A uid named here that has no verdict at all (a typo) simply matches nothing, so the
## clip stays red -- the fail-safe direction.
static func apply_exemptions(verdicts: Array, exemptions: Dictionary) -> Array:
	var out: Array = []
	for v in verdicts:
		var entry = exemptions.get(String(v.get("metric", "")))
		if not (entry is Dictionary) or not _exempts_uid(entry, int(v.get("uid", -1))):
			out.append(v)
			continue
		var marked: Dictionary = (v as Dictionary).duplicate()
		marked["stale_exempt"] = bool(v["pass"])
		marked["exempt"] = String((entry as Dictionary).get("reason", ""))
		marked["pass"] = true
		out.append(marked)
	return out


## Does this exemption entry name `uid` among the units it covers?
static func _exempts_uid(entry: Dictionary, uid: int) -> bool:
	for u in entry.get("uids", []):
		if int(u) == uid:
			return true
	return false


static func _values_match(expected, actual) -> bool:
	if (expected is float or expected is int) and (actual is float or actual is int):
		return absf(float(expected) - float(actual)) < 0.001
	return str(expected) == str(actual)


## Mean distance from each body to its nearest slot of ANY identity -- how settled the
## block is on its grid, independent of who stands where. O(n^2), fine at regiment sizes.
static func _mean_nearest_slot_distance(slots: Array, positions: Array) -> float:
	var n: int = mini(slots.size(), positions.size())
	if n == 0:
		return 0.0
	var total := 0.0
	for i in range(n):
		var best := INF
		for j in range(n):
			best = minf(best, _vec(positions[i]).distance_squared_to(_vec(slots[j])))
		total += sqrt(best)
	return total / n


static func _vec(pair) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))


## Map a sim formation name to the expected HUD display text. Optional
## `file_pitch_wu` / `rank_pitch_wu` are the dumped live slot-center pitches
## (already density-scaled). When omitted (or unknown mode) this returns "" so
## the HUD check skips rather than guessing. Does NOT import Unit -- this file
## runs under bare `godot -s` with no Settings autoload.
const DistanceLegendRef = preload("res://scripts/DistanceLegend.gd")
const _FORMATION_LABEL_SUFFIX := {
	"NORMAL": "",
	"TIGHT": " locked",
	"LOOSE": "",
	"SQUARE": " Square",
	"SHIELD_WALL": " Shield Wall",
	"TESTUDO": " Testudo",
	"SCHILTRON": " Schiltron",
}


static func hud_formation_name(sim_formation: String, file_pitch_wu: float = -1.0,
		rank_pitch_wu: float = -1.0) -> String:
	if not _FORMATION_LABEL_SUFFIX.has(sim_formation):
		return ""
	if file_pitch_wu < 0.0:
		return ""
	# Square/schiltron geometry is isotropic at file pitch (formation_slots
	# omits rank). Rebuild must match that, not the unused rank dump.
	var rank: float = rank_pitch_wu
	if sim_formation == "SQUARE" or sim_formation == "SCHILTRON":
		rank = -1.0
	var interval: String = DistanceLegendRef.interval_pair_label(file_pitch_wu, rank)
	return interval + _FORMATION_LABEL_SUFFIX[sim_formation]


## `caption` with a trailing faction historical-name parenthetical removed:
## "0.45 m locked (synaspismos)" -> "0.45 m locked". Once a battle side has a faction, the HUD
## appends that side's historical name for the mode (Faction.get_formation_display_name), so a
## raw string compare against the sim rebuild would report every faction battle as a HUD
## mismatch. Stripping it keeps this metric on the interval-and-stance caption, which is the
## part that carries sim state -- the historical name is keyed on the very formation mode the
## comparison already covers, and no rebuilt caption ever contains a parenthesis of its own
## (DistanceLegend.interval_pair_label emits digits, "x", and a unit only).
static func strip_historical_name(caption: String) -> String:
	if not caption.ends_with(")"):
		return caption
	var open: int = caption.rfind(" (")
	if open <= 0:
		return caption
	return caption.substr(0, open)


## Check consistency between the player-visible HUD readout and sim state across all snapshots.
## Emits verdicts for formation display and selection display whenever hud data is present.
## Mismatches must sustain across MIN_SUSTAIN consecutive samples to fail, accommodating
## 1-frame latency between a physics-tick sim write and the process-frame HUD text refresh.
static func check_hud_consistency(snapshots: Array) -> Array:
	var out: Array = []
	var has_hud_data: bool = false
	var formation_run := 0
	var worst_formation_run := 0
	var selection_run := 0
	var worst_selection_run := 0
	var worst_formation: String = ""
	var worst_selection: String = ""

	for snap in snapshots:
		if not (snap is Dictionary) or not (snap as Dictionary).has("hud"):
			continue
		has_hud_data = true
		var hud: Dictionary = snap["hud"]
		var shown_uid = hud.get("shown_unit_uid")
		var tick: int = int(snap.get("tick", 0))

		if shown_uid == null or int(shown_uid) < 0:
			# No unit selected: control bar should not be active
			if hud.get("ctrl_bar_visible", false) == true:
				selection_run += 1
				worst_selection_run = maxi(worst_selection_run, selection_run)
				if worst_selection == "":
					worst_selection = "tick %d: ctrl_bar visible with no unit selected" % tick
			else:
				selection_run = 0
			formation_run = 0
			continue

		var uid: int = int(shown_uid)
		var matching_unit: Dictionary = {}
		for u in snap.get("units", []):
			if int(u.get("uid", -1)) == uid:
				matching_unit = u
				break

		if matching_unit.is_empty():
			selection_run += 1
			worst_selection_run = maxi(worst_selection_run, selection_run)
			if worst_selection == "":
				worst_selection = "tick %d: shown uid %d not present in sim units" % [tick, uid]
		else:
			selection_run = 0

		# 1. Formation verification: HUD button text vs dumped caption, else rebuilt
		# from dumped pitches (never via Unit -- this analyzer has no autoloads).
		# When both the dump caption and the pitch rebuild exist, they must agree
		# -- suffix-map drift or a stale formation_summary is a real mismatch.
		# Fail closed: a selected unit whose mode is missing from the suffix map,
		# or whose HUD caption is blank while an expected label exists, is a
		# mismatch -- do not skip and reset the run.
		var sim_formation: String = str(matching_unit.get("formation", ""))
		var hud_formation: String = strip_historical_name(
				str(hud.get("formation_text", "")).strip_edges())
		if not matching_unit.is_empty():
			var pitch: float = float(matching_unit.get("file_pitch", -1.0))
			var rank: float = float(matching_unit.get("rank_pitch", -1.0))
			if pitch < 0.0 and matching_unit.has("motion_ref"):
				var ref: Dictionary = matching_unit["motion_ref"]
				pitch = float(ref.get("file_pitch", -1.0))
				rank = float(ref.get("rank_pitch", -1.0))
			var unknown_mode := (
					sim_formation != "" and not _FORMATION_LABEL_SUFFIX.has(sim_formation))
			var rebuilt: String = hud_formation_name(sim_formation, pitch, rank)
			var dumped_label: String = str(matching_unit.get("formation_label", "")).strip_edges()
			var expected: String = dumped_label if dumped_label != "" else rebuilt
			var dump_rebuild_mismatch := (
					dumped_label != "" and rebuilt != "" and dumped_label != rebuilt)
			var blank_hud := expected != "" and hud_formation == ""
			if unknown_mode or blank_hud or (
					expected != "" and (hud_formation != expected or dump_rebuild_mismatch)):
				formation_run += 1
				worst_formation_run = maxi(worst_formation_run, formation_run)
				if worst_formation == "":
					if unknown_mode:
						worst_formation = (
								"tick %d: unknown formation '%s'" % [tick, sim_formation])
					elif dump_rebuild_mismatch:
						worst_formation = (
								"tick %d: formation_label '%s' vs pitch rebuild '%s'"
								% [tick, dumped_label, rebuilt])
					elif blank_hud:
						worst_formation = (
								"tick %d: blank hud vs expected '%s'" % [tick, expected])
					else:
						worst_formation = "tick %d: sim %s vs hud '%s'" % [
								tick, sim_formation, hud_formation]
			else:
				formation_run = 0
		else:
			formation_run = 0

	if has_hud_data:
		var sustain_req := MIN_SUSTAIN if snapshots.size() >= MIN_SUSTAIN else 1
		out.append({
			"uid": -1,
			"metric": "hud_formation_consistency",
			"pass": worst_formation_run < sustain_req,
			"worst": worst_formation if worst_formation_run >= sustain_req else 0,
			"threshold": 0,
		})
		out.append({
			"uid": -1,
			"metric": "hud_selection_consistency",
			"pass": worst_selection_run < sustain_req,
			"worst": worst_selection if worst_selection_run >= sustain_req else 0,
			"threshold": 0,
		})
	return out
