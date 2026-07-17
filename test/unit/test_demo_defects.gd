extends GutTest
## DemoDefects: the deterministic defect metrics behind algorithmic demo review.
## All-pure module, so every test builds synthetic geometry directly -- a slot grid and
## body arrays with a known, constructed defect -- and asserts the metric detects exactly
## that defect and nothing else. Thresholds come from the same motion_ref shape the FULL
## state dump emits, so these tests also pin the analyzer's input contract.

const SPACING := 9.0


func _grid(files: int, ranks: int, spacing: float, origin: Vector2 = Vector2.ZERO,
		angle: float = 0.0) -> Array:
	var out: Array = []
	for r in range(ranks):
		for f in range(files):
			var local := Vector2(
					(f - (files - 1) * 0.5) * spacing,
					(r - (ranks - 1) * 0.5) * spacing)
			var p: Vector2 = origin + local.rotated(angle)
			out.append([p.x, p.y])
	return out


func _snapshot(tick: int, bodies: Array, slots: Array, engaged: bool = false,
		state: String = "MOVING", facing: Array = [0.0, 1.0]) -> Dictionary:
	return {"tick": tick, "units": [{
		"uid": 1, "engaged": engaged, "state": state, "facing": facing,
		"soldiers_full": {"pos": bodies, "slots": slots},
		"motion_ref": {"formation_spacing": SPACING, "walk_speed": 34.0,
				"jog_speed": 64.0, "move_speed": 126.0, "pivot_radius": 56.0,
				"turn_rate": PI},
	}]}


func _verdict(result: Dictionary, metric: String) -> Dictionary:
	for v in result["verdicts"]:
		if v["metric"] == metric:
			return v
	return {}


# --- nearest-neighbour stats --------------------------------------------------

func test_nnd_stats_of_a_clean_grid_read_the_formation_spacing() -> void:
	var stats: Dictionary = DemoDefects.nnd_stats(_grid(6, 4, SPACING))
	assert_almost_eq(float(stats["min"]), SPACING, 0.001, "grid neighbours sit one spacing apart")
	assert_almost_eq(float(stats["median"]), SPACING, 0.001, "median matches the spacing too")


# --- Kabsch ordered-vs-actual fit ----------------------------------------------

func test_kabsch_fit_recovers_a_pure_rotation_with_zero_residual() -> void:
	var slots: Array = _grid(6, 4, SPACING)
	var bodies: Array = _grid(6, 4, SPACING, Vector2.ZERO, deg_to_rad(40.0))
	var fit: Dictionary = DemoDefects.kabsch_fit(slots, bodies)
	assert_almost_eq(float(fit["angle"]), deg_to_rad(40.0), 0.001,
			"the fitted angle is the block's true physical rotation")
	assert_almost_eq(float(fit["residual_rms"]), 0.0, 0.001,
			"a rigid rotation leaves no shape residual")


func test_kabsch_fit_reports_scramble_as_residual_not_rotation() -> void:
	# NOTE: a plain array REVERSE is not a scramble -- on a centred grid it maps every
	# position to its negation, which IS a rigid 180-degree rotation and rightly fits
	# with zero residual (the same point-reflection identity _formation_mirror_x's own
	# docs describe). Identity swaps that preserve the point set are misslotted_count's
	# job; the shape residual catches geometry no rigid motion explains, so scramble
	# here with a scatter permutation that pairs each slot with an unrelated one.
	var slots: Array = _grid(6, 4, SPACING)
	var bodies: Array = []
	for i in range(slots.size()):
		bodies.append(slots[(i * 7 + 3) % slots.size()])
	var fit: Dictionary = DemoDefects.kabsch_fit(slots, bodies)
	assert_gt(float(fit["residual_rms"]), SPACING,
			"slot-scattered bodies read as shape error no rotation explains")


# --- slot misassignment ---------------------------------------------------------

func test_misslotted_count_zero_on_slots_and_full_on_a_swap() -> void:
	var slots: Array = _grid(4, 3, SPACING)
	assert_eq(DemoDefects.misslotted_count(slots, slots.duplicate()), 0,
			"bodies standing on their own slots are not misslotted")
	var swapped: Array = slots.duplicate()
	var tmp = swapped[0]
	swapped[0] = swapped[11]
	swapped[11] = tmp
	assert_eq(DemoDefects.misslotted_count(slots, swapped), 2,
			"a two-man swap misslots exactly those two")


func test_aligned_slots_absorb_a_rigid_rotation_so_turn_lag_is_not_misassignment() -> void:
	# A block physically rotated 40 deg off its ordered grid: against the RAW slots many
	# soldiers sit nearer a neighbour's slot (turn lag), but against the FIT-ALIGNED
	# slots every man is back on his own -- only identity scramble survives alignment.
	var slots: Array = _grid(6, 4, SPACING)
	var bodies: Array = _grid(6, 4, SPACING, Vector2.ZERO, deg_to_rad(40.0))
	var fit: Dictionary = DemoDefects.kabsch_fit(slots, bodies)
	var aligned: Array = DemoDefects.aligned_slots(slots, bodies, fit)
	assert_eq(DemoDefects.misslotted_count(aligned, bodies), 0,
			"a rigid rotation leaves nobody misslotted after alignment")
	assert_gt(DemoDefects.misslotted_count(slots, bodies), 0,
			"the same rotation against raw slots would have false-positived")


# --- facing whipsaw --------------------------------------------------------------

func test_facing_reversals_counts_big_sign_flips_only() -> void:
	var one_turn: Array = [0.0, 0.3, 0.6, 0.9]
	assert_eq(DemoDefects.facing_reversals(one_turn, deg_to_rad(10.0)), 0,
			"a monotonic turn has no reversals")
	var whipsaw: Array = [0.0, 0.6, 0.0, 0.6, 0.0]
	assert_eq(DemoDefects.facing_reversals(whipsaw, deg_to_rad(10.0)), 3,
			"each direction flip past the swing floor counts")
	var jitter: Array = [0.0, 0.01, 0.0, 0.01, 0.0]
	assert_eq(DemoDefects.facing_reversals(jitter, deg_to_rad(10.0)), 0,
			"sub-threshold jitter is not a whipsaw")


# --- per-soldier speed ------------------------------------------------------------

func test_max_soldier_speed_reads_displacement_over_ticks() -> void:
	var a: Array = [[0.0, 0.0], [10.0, 0.0]]
	var b: Array = [[0.0, 30.0], [10.0, 0.0]]
	# 30 wu over 30 ticks at 60 tps = 0.5 s -> 60 wu/s.
	assert_almost_eq(DemoDefects.max_soldier_speed(a, b, 30), 60.0, 0.001,
			"speed is the fastest soldier's displacement over elapsed sim time")


# --- whole-transcript verdicts -----------------------------------------------------

func test_clean_march_passes_every_verdict() -> void:
	var slots0: Array = _grid(6, 4, SPACING, Vector2(100, 100))
	var slots1: Array = _grid(6, 4, SPACING, Vector2(100, 117))
	var snaps: Array = [
		_snapshot(0, slots0.duplicate(), slots0),
		_snapshot(60, slots1.duplicate(), slots1),
	]
	var result: Dictionary = DemoDefects.analyze(snaps)
	for v in result["verdicts"]:
		assert_true(bool(v["pass"]), "clean march passes metric '%s'" % v["metric"])


func test_sustained_compression_fails_the_blob_verdict_pre_contact_only() -> void:
	var slots: Array = _grid(6, 4, SPACING)
	var blob: Array = _grid(6, 4, SPACING * 0.5)   # everyone at half spacing
	var pre: Array = [
		_snapshot(0, blob, slots), _snapshot(60, blob, slots), _snapshot(120, blob, slots)]
	assert_false(bool(_verdict(DemoDefects.analyze(pre), "blob")["pass"]),
			"sustained half-spacing compression pre-contact is a blob")
	var engaged: Array = [
		_snapshot(0, blob, slots, true), _snapshot(60, blob, slots, true),
		_snapshot(120, blob, slots, true)]
	assert_true(bool(_verdict(DemoDefects.analyze(engaged), "blob")["pass"]),
			"the same compression during melee press is exempt")


func test_colocated_soldiers_fail_the_overlap_verdict_on_one_sample() -> void:
	var slots: Array = _grid(6, 4, SPACING)
	var bodies: Array = slots.duplicate()
	bodies[1] = [float(bodies[0][0]) + 0.3, float(bodies[0][1])]   # two men share ground
	var result: Dictionary = DemoDefects.analyze([_snapshot(0, bodies, slots)])
	assert_false(bool(_verdict(result, "overlap")["pass"]),
			"a single pre-contact sample with co-located soldiers fails overlap")


func test_scrambled_block_fails_shape_residual_while_a_rotated_one_passes() -> void:
	var slots: Array = _grid(6, 4, SPACING)
	var rotated: Array = _grid(6, 4, SPACING, Vector2.ZERO, deg_to_rad(45.0))
	var rot_result: Dictionary = DemoDefects.analyze([
		_snapshot(0, rotated, slots), _snapshot(60, rotated, slots)])
	assert_true(bool(_verdict(rot_result, "shape_residual")["pass"]),
			"a rigidly rotated block is turning, not scrambled")
	var scrambled: Array = []
	for i in range(slots.size()):
		scrambled.append(slots[(i * 7 + 3) % slots.size()])
	var scr_result: Dictionary = DemoDefects.analyze([
		_snapshot(0, scrambled, slots), _snapshot(60, scrambled, slots)])
	assert_false(bool(_verdict(scr_result, "shape_residual")["pass"]),
			"a slot-scattered block is scrambled")
	assert_false(bool(_verdict(scr_result, "misslotted")["pass"]),
			"and its soldiers stand on each other's slots")
	assert_true(bool(_verdict(rot_result, "misslotted")["pass"]),
			"while a rigidly rotated block's men all keep their own slots")


func test_teleporting_soldier_fails_superphysical_only_when_sustained() -> void:
	var slots: Array = _grid(6, 4, SPACING)
	var far1: Array = _grid(6, 4, SPACING, Vector2(0, 200))
	var far2: Array = _grid(6, 4, SPACING, Vector2(0, 400))
	# One big jump then stillness: a knockback-like transient, exempt.
	var transient: Array = [
		_snapshot(0, slots.duplicate(), slots), _snapshot(30, far1.duplicate(), far1),
		_snapshot(60, far1.duplicate(), far1)]
	assert_true(bool(_verdict(DemoDefects.analyze(transient), "superphysical_speed")["pass"]),
			"a single-sample spike is a legitimate impulse")
	# Jumping every sample: 200 wu / 0.5 s = 400 wu/s, sustained -> fails vs 126 sprint.
	var sustained: Array = [
		_snapshot(0, slots.duplicate(), slots), _snapshot(30, far1.duplicate(), far1),
		_snapshot(60, far2.duplicate(), far2)]
	assert_false(bool(_verdict(DemoDefects.analyze(sustained), "superphysical_speed")["pass"]),
			"soldiers holding 3x sprint across samples are super-physical")


func test_whipsaw_verdict_fails_an_oscillating_march() -> void:
	var slots: Array = _grid(6, 4, SPACING)
	var snaps: Array = []
	# Eight swings = six direction reversals, well past the S-detour allowance the
	# threshold is calibrated to (a legitimate detour produces at most about three).
	var angles: Array = [0.0, 0.6, 0.0, 0.6, 0.0, 0.6, 0.0, 0.6]
	for i in range(angles.size()):
		snaps.append(_snapshot(i * 60, slots.duplicate(), slots, false, "MOVING",
				[cos(angles[i]), sin(angles[i])]))
	assert_false(bool(_verdict(DemoDefects.analyze(snaps), "facing_whipsaw")["pass"]),
			"a facing that keeps reversing direction while marching is a whipsaw")


# --- the dump provides what the analyzer consumes -----------------------------------

func test_full_dump_carries_slots_and_motion_ref_matching_the_unit() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = 40
	add_child_autofree(u)
	u.position = Vector2(200, 200)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	var rec: Dictionary = DemoState.unit_record(u, {}, 1.0, true)
	assert_true(rec.has("soldiers_full"), "FULL record carries the per-soldier arrays")
	assert_true(rec["soldiers_full"].has("slots"), "and the canonical slot grid")
	assert_true(rec.has("motion_ref"), "and the per-unit motion constants")
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	assert_eq((rec["soldiers_full"]["slots"] as Array).size(), slots.size(),
			"one dumped slot per soldier")
	var first: Array = rec["soldiers_full"]["slots"][0]
	assert_almost_eq(float(first[0]), slots[0].x, 0.01, "slot x matches the sim's own slot math")
	assert_almost_eq(float(first[1]), slots[0].y, 0.01, "slot y matches the sim's own slot math")
	assert_almost_eq(float(rec["motion_ref"]["formation_spacing"]),
			Unit.FORMATION_SPACING * u.spacing_scale, 0.001,
			"spacing is the unit's own, not a hardcoded copy")
	assert_almost_eq(float(rec["motion_ref"]["pivot_radius"]), u._pivot_radius(), 0.01,
			"pivot radius is the unit's own")
