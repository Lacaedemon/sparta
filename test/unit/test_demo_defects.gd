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
		state: String = "MOVING", facing: Array = [0.0, 1.0],
		motion_ref: Dictionary = {}, in_enemy_contact: bool = false,
		formation: String = "NORMAL", frontage: int = 6) -> Dictionary:
	var ref: Dictionary = {"formation_spacing": SPACING, "soldier_body_radius": SPACING * 0.5,
			"walk_speed": 34.0, "jog_speed": 64.0, "move_speed": 126.0,
			"pivot_radius": 56.0, "turn_rate": PI}
	ref.merge(motion_ref, true)
	return {"tick": tick, "units": [{
		"uid": 1, "engaged": engaged, "in_enemy_contact": in_enemy_contact,
		"state": state, "facing": facing,
		"formation": formation, "frontage": frontage,
		"soldiers_full": {"pos": bodies, "slots": slots},
		"motion_ref": ref,
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


func test_speed_quantization_margin_for_dt10_and_dt60() -> void:
	var expected_dt10: float = (0.01 * sqrt(2.0)) / (10.0 / 60.0)
	var expected_dt60: float = (0.01 * sqrt(2.0)) / (60.0 / 60.0)
	var defects_cls: Variant = DemoDefects
	var m10: float = defects_cls.speed_quantization_margin(10) if defects_cls.has_method("speed_quantization_margin") else -1.0
	var m60: float = defects_cls.speed_quantization_margin(60) if defects_cls.has_method("speed_quantization_margin") else -1.0
	assert_almost_eq(m10, expected_dt10, 0.0001,
			"margin at dt 10 accounts for two rounded endpoints over 10 ticks")
	assert_almost_eq(m60, expected_dt60, 0.0001,
			"margin at dt 60 accounts for two rounded endpoints over 60 ticks")


func test_demo_defects_position_decimal_places_matches_demo_state() -> void:
	assert_eq(DemoDefects.POSITION_DECIMAL_PLACES, DemoState.POSITION_DECIMAL_PLACES,
			"DemoDefects position precision matches DemoState dump precision")


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


func test_sustained_compression_fails_the_blob_verdict_outside_melee() -> void:
	var slots: Array = _grid(6, 4, SPACING)
	# For foot, two touching bodies span one spacing (0.45 m pitch, 0.45 m body), so
	# the blob floor is half that: bodies stacked well INSIDE each other on median.
	var blob: Array = _grid(6, 4, SPACING * 0.35)
	var pre: Array = [
		_snapshot(0, blob, slots), _snapshot(60, blob, slots), _snapshot(120, blob, slots)]
	assert_false(bool(_verdict(DemoDefects.analyze(pre), "blob")["pass"]),
			"sustained deep interpenetration outside melee is a blob")
	var engaged: Array = [
		_snapshot(0, blob, slots, true), _snapshot(60, blob, slots, true),
		_snapshot(120, blob, slots, true)]
	assert_true(bool(_verdict(DemoDefects.analyze(engaged), "blob")["pass"]),
			"the same compression during melee press is exempt")


func test_blob_floor_comes_from_body_size_not_grid_pitch() -> void:
	# Cavalry-style anisotropy: a roomy 20-wu min pitch with 10-wu bodies. The old
	# pitch-derived floor (0.75 * 20 = 15) read ordinary combat press -- horse
	# bodies packed to a 12-wu median, still mostly apart -- as a blob; the
	# body-derived floor (half of two touching bodies, 10) does not.
	var cav_ref: Dictionary = {"formation_spacing": 20.0, "soldier_body_radius": 10.0}
	var slots: Array = _grid(6, 4, 20.0)
	var press: Array = _grid(6, 4, 12.0)
	var press_snaps: Array = [
		_snapshot(0, press, slots, false, "MOVING", [0.0, 1.0], cav_ref),
		_snapshot(60, press, slots, false, "MOVING", [0.0, 1.0], cav_ref)]
	assert_true(bool(_verdict(DemoDefects.analyze(press_snaps), "blob")["pass"]),
			"combat-press proximity on a roomy grid is not a blob")
	var stacked: Array = _grid(6, 4, 7.0)
	var stacked_snaps: Array = [
		_snapshot(0, stacked, slots, false, "MOVING", [0.0, 1.0], cav_ref),
		_snapshot(60, stacked, slots, false, "MOVING", [0.0, 1.0], cav_ref)]
	assert_false(bool(_verdict(DemoDefects.analyze(stacked_snaps), "blob")["pass"]),
			"mounts genuinely stacked inside each other still read as a blob")


func test_blob_floor_keeps_a_pitch_fraction_for_tiny_bodies_on_roomy_grids() -> void:
	# A hypothetical type with bodies far smaller than its pitch: the pitch-fraction
	# floor binds, so a genuine collapse on a roomy grid still fires.
	var ref: Dictionary = {"formation_spacing": 20.0, "soldier_body_radius": 2.0}
	var slots: Array = _grid(6, 4, 20.0)
	var collapsed: Array = _grid(6, 4, 4.0)   # under the 20 * 0.25 = 5 pitch floor
	var snaps: Array = [
		_snapshot(0, collapsed, slots, false, "MOVING", [0.0, 1.0], ref),
		_snapshot(60, collapsed, slots, false, "MOVING", [0.0, 1.0], ref)]
	assert_false(bool(_verdict(DemoDefects.analyze(snaps), "blob")["pass"]),
			"a collapse past the pitch-fraction floor fires even with tiny bodies")


func test_routing_samples_are_exempt_from_grid_checks() -> void:
	# A fleeing mob is legitimately not on any slot grid: the same geometry that
	# would fail blob/shape while formed must pass while ROUTING.
	var slots: Array = _grid(6, 4, SPACING)
	var mob: Array = _grid(6, 4, SPACING * 0.35)
	var snaps: Array = [
		_snapshot(0, mob, slots, false, "ROUTING"),
		_snapshot(60, mob, slots, false, "ROUTING"),
		_snapshot(120, mob, slots, false, "ROUTING")]
	var result: Dictionary = DemoDefects.analyze(snaps)
	assert_true(bool(_verdict(result, "blob")["pass"]), "a routing mob is not a blob")
	assert_true(bool(_verdict(result, "shape_residual")["pass"]),
			"a routing mob has no grid to deviate from")


func test_samples_adjacent_to_an_engagement_flip_are_exempt() -> void:
	# The transition window: a block charging into contact legitimately compresses
	# in the sampled moment just before `engaged` flips. The same compression far
	# from any engagement still fails.
	var slots: Array = _grid(6, 4, SPACING)
	var press: Array = _grid(6, 4, SPACING * 0.2)   # under the single-sample overlap floor
	var charging: Array = [
		_snapshot(0, slots.duplicate(), slots),
		_snapshot(60, press, slots),               # adjacent to the engaged sample below
		_snapshot(120, press, slots, true)]
	assert_true(bool(_verdict(DemoDefects.analyze(charging), "overlap")["pass"]),
			"compression in the sample bordering first contact is the transition, not a defect")
	var open_field: Array = [
		_snapshot(0, slots.duplicate(), slots),
		_snapshot(60, press, slots),
		_snapshot(120, press, slots)]
	assert_false(bool(_verdict(DemoDefects.analyze(open_field), "overlap")["pass"]),
			"the same compression with no engagement anywhere near still fails")


func test_a_block_still_in_enemy_contact_is_exempt_even_once_disengaged() -> void:
	# `engaged` and `in_enemy_contact` do not drop together: a regiment relieved out
	# of a melee leaves the combat bookkeeping while its men are still physically in
	# the press, backing out of it. Those samples read the melee's own compression,
	# so the grid checks must forgive them exactly as they forgive an engaged block.
	var slots: Array = _grid(6, 4, SPACING)
	var press: Array = _grid(6, 4, SPACING * 0.2)   # under the single-sample overlap floor
	var backing_out: Array = [
		_snapshot(0, press, slots, false, "MOVING", [0.0, 1.0], {}, true),
		_snapshot(60, press, slots, false, "MOVING", [0.0, 1.0], {}, true),
		_snapshot(120, press, slots, false, "MOVING", [0.0, 1.0], {}, true)]
	var backing: Dictionary = DemoDefects.analyze(backing_out)
	assert_true(bool(_verdict(backing, "overlap")["pass"]),
			"a block still in the press is not judged for spacing once merely disengaged")
	assert_true(bool(_verdict(backing, "blob")["pass"]),
			"nor for median compression")
	assert_true(bool(_verdict(backing, "shape_residual")["pass"]),
			"nor for shape, which the same press scrambles")
	var clear: Array = [
		_snapshot(0, press, slots),
		_snapshot(60, press, slots),
		_snapshot(120, press, slots)]
	assert_false(bool(_verdict(DemoDefects.analyze(clear), "overlap")["pass"]),
			"the same compression clear of any contact still fails")


func test_the_transition_window_straddles_a_contact_flip_too() -> void:
	# The one-sample window on either side of the exemption is keyed on contact, not
	# on `engaged`: a block peeling out of the press is still compressed in the first
	# sample after contact drops, the same way it is in the last one before it starts.
	var slots: Array = _grid(6, 4, SPACING)
	var press: Array = _grid(6, 4, SPACING * 0.2)
	var peeling: Array = [
		_snapshot(0, press, slots, false, "MOVING", [0.0, 1.0], {}, true),
		_snapshot(60, press, slots),               # adjacent to the contact sample above
		_snapshot(120, slots.duplicate(), slots)]
	assert_true(bool(_verdict(DemoDefects.analyze(peeling), "overlap")["pass"]),
			"compression in the sample bordering the end of contact is the transition")


func test_judged_mask_masks_two_samples_after_contact_and_judges_third() -> void:
	var s: Dictionary = {
		"ticks": [0, 60, 120, 180, 240, 300],
		"engaged": [false, false, true, false, false, false],
		"in_enemy_contact": [false, false, false, false, false, false],
		"routing": [false, false, false, false, false, false],
		"counts": [24, 24, 24, 24, 24, 24],
	}
	var mask: Array = DemoDefects.judged_mask(s)
	assert_false(mask[2], "contact sample is masked")
	assert_false(mask[3], "first post-contact sample is masked")
	assert_false(mask[4], "second post-contact sample is masked")
	assert_true(mask[5], "third post-contact sample is judged")


func test_the_sample_after_a_casualty_compaction_is_exempt() -> void:
	# Casualties compact the body arrays and survivors converge on re-dealt slots:
	# the first sample after a count drop is a legitimate transient. The compression
	# persisting into the NEXT sample is judged again.
	var slots24: Array = _grid(6, 4, SPACING)
	var slots20: Array = _grid(5, 4, SPACING)
	var press20: Array = _grid(5, 4, SPACING * 0.2)
	var transient: Array = [
		_snapshot(0, slots24.duplicate(), slots24),
		_snapshot(60, press20, slots20),            # count just dropped 24 -> 20
		_snapshot(120, slots20.duplicate(), slots20)]
	assert_true(bool(_verdict(DemoDefects.analyze(transient), "overlap")["pass"]),
			"re-slot compression right after a casualty drop is a transient")
	var persisting: Array = [
		_snapshot(0, slots24.duplicate(), slots24),
		_snapshot(60, press20, slots20),
		_snapshot(120, press20, slots20)]
	assert_false(bool(_verdict(DemoDefects.analyze(persisting), "overlap")["pass"]),
			"compression that persists past the re-slot sample is judged and fails")


func test_the_sample_after_a_formation_reshape_is_exempt() -> void:
	# A formation reshape or frontage resize assigns a new slot grid instantly while bodies
	# take time to transition onto the new shape: the transition window right after the change
	# is a legitimate physical transient.
	var slots_norm: Array = _grid(6, 4, SPACING)
	var slots_tight: Array = _grid(6, 4, SPACING * 0.67)
	var transient: Array = [
		_snapshot(0, slots_norm.duplicate(), slots_norm, false, "MOVING", [0.0, 1.0], {}, false, "NORMAL", 6),
		_snapshot(60, slots_norm.duplicate(), slots_tight, false, "MOVING", [0.0, 1.0], {}, false, "TIGHT", 6), # reshape tick
		_snapshot(120, slots_tight.duplicate(), slots_tight, false, "MOVING", [0.0, 1.0], {}, false, "TIGHT", 6), # settled
	]
	assert_true(bool(_verdict(DemoDefects.analyze(transient), "shape_residual")["pass"]),
			"shape residual right after a formation reshape is exempt during transition")



func test_a_lone_survivor_is_not_a_blob() -> void:
	# nnd of a single body reads zero; the spacing verdicts must skip it rather
	# than report maximal compression forever.
	var slots: Array = _grid(1, 1, SPACING)
	var snaps: Array = [
		_snapshot(0, slots.duplicate(), slots), _snapshot(60, slots.duplicate(), slots)]
	var result: Dictionary = DemoDefects.analyze(snaps)
	assert_true(bool(_verdict(result, "blob")["pass"]), "one man cannot blob")
	assert_true(bool(_verdict(result, "overlap")["pass"]), "or overlap with himself")


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


func test_superphysical_speed_rounding_margin_boundary() -> void:
	var slots: Array = [[0.0, 0.0], [10.0, 0.0]]
	var sprint := 126.0
	var cap: float = sprint * GaitLimits.SUPERPHYSICAL_SPEED_FRAC
	var dt_ticks := 10
	var dt_sec: float = float(dt_ticks) / 60.0
	var defects_cls: Variant = DemoDefects
	var margin: float = defects_cls.speed_quantization_margin(dt_ticks) if defects_cls.has_method("speed_quantization_margin") else (0.01 * sqrt(2.0)) / dt_sec
	var v_pass: float = cap + 0.5 * margin
	var snaps_pass: Array = [
		_snapshot(0, [[0.0, 0.0], [10.0, 0.0]], slots),
		_snapshot(10, [[0.0, v_pass * dt_sec], [10.0, v_pass * dt_sec]], slots),
		_snapshot(20, [[0.0, 2.0 * v_pass * dt_sec], [10.0, 2.0 * v_pass * dt_sec]], slots),
		_snapshot(30, [[0.0, 3.0 * v_pass * dt_sec], [10.0, 3.0 * v_pass * dt_sec]], slots),
	]
	var res_pass: Dictionary = DemoDefects.analyze(snaps_pass)
	var verdict_pass: Dictionary = _verdict(res_pass, "superphysical_speed")
	assert_true(bool(verdict_pass["pass"]),
			"speed at cap plus half margin passes rounding allowance")
	var reported_pass_threshold: float = float(verdict_pass["threshold"])
	assert_gt(reported_pass_threshold, cap,
			"reported threshold is greater than cap when a margin applied")
	var v_fail: float = cap + 2.0 * margin
	var snaps_fail: Array = [
		_snapshot(0, [[0.0, 0.0], [10.0, 0.0]], slots),
		_snapshot(10, [[0.0, v_fail * dt_sec], [10.0, v_fail * dt_sec]], slots),
		_snapshot(20, [[0.0, 2.0 * v_fail * dt_sec], [10.0, 2.0 * v_fail * dt_sec]], slots),
		_snapshot(30, [[0.0, 3.0 * v_fail * dt_sec], [10.0, 3.0 * v_fail * dt_sec]], slots),
	]
	var res_fail: Dictionary = DemoDefects.analyze(snaps_fail)
	var verdict_fail: Dictionary = _verdict(res_fail, "superphysical_speed")
	assert_false(bool(verdict_fail["pass"]),
			"speed at cap plus 2x margin fails superphysical check")
	var reported_fail_threshold: float = float(verdict_fail["threshold"])
	assert_gt(reported_fail_threshold, cap,
			"reported threshold in failing verdict is also greater than cap when a margin applied")


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


func test_misslot_is_suppressed_while_the_block_is_in_transit() -> void:
	# Bodies caught halfway along their walks to reassigned positions (a reshape in
	# flight): nobody stands ON any slot, identity is noise, and the settled gate must
	# suppress the fraction -- a uniform offset won't do here, the fit would absorb it.
	var slots: Array = _grid(6, 4, SPACING)
	var transit: Array = []
	for i in range(slots.size()):
		var a: Array = slots[i]
		var b: Array = slots[(i * 7 + 3) % slots.size()]
		transit.append([(float(a[0]) + float(b[0])) * 0.5, (float(a[1]) + float(b[1])) * 0.5])
	var snaps: Array = [
		_snapshot(0, transit.duplicate(), slots), _snapshot(60, transit.duplicate(), slots),
		_snapshot(120, transit.duplicate(), slots)]
	assert_true(bool(_verdict(DemoDefects.analyze(snaps), "misslotted")["pass"]),
			"a block in transit between grids is not a rank swap")


func test_a_converging_transition_passes_where_a_stuck_defect_fails() -> void:
	# A legitimate long transition (a reshape walking bodies onto a new grid) reads far
	# out of tolerance for many samples while steadily improving; a stuck defect holds.
	# The convergence-aware sustain gate separates them with no maneuver knowledge.
	# A rigid translation would be absorbed by the fit, so build genuine shape error
	# with COMPRESSED grids annealing toward the ordered spacing.
	var slots: Array = _grid(6, 4, SPACING)
	var far: Array = _grid(6, 4, SPACING * 0.3)
	var mid: Array = _grid(6, 4, SPACING * 0.55)
	var near: Array = _grid(6, 4, SPACING * 0.8)
	var converging: Array = [
		_snapshot(0, far, slots), _snapshot(60, mid, slots), _snapshot(120, near, slots),
		_snapshot(180, slots.duplicate(), slots)]
	assert_true(bool(_verdict(DemoDefects.analyze(converging), "shape_residual")["pass"]),
			"a steadily improving residual is a transition, not a defect")
	var stuck: Array = [
		_snapshot(0, far.duplicate(), slots), _snapshot(60, far.duplicate(), slots),
		_snapshot(120, far.duplicate(), slots)]
	assert_false(bool(_verdict(DemoDefects.analyze(stuck), "shape_residual")["pass"]),
			"the same magnitude holding flat is a defect")


# --- declared expectations (intent as data) ------------------------------------------

func _swap_corners(grid: Array) -> Array:
	# Trade both diagonal corner pairs of a 6x4 block: four men cross the entire
	# formation, and the two diagonals genuinely intersect at its centre. A plain
	# two-man swap cannot serve here -- its paths are collinear, and for a block that
	# small the swap IS a rigid 180-degree turn, which the fit correctly absorbs.
	var out: Array = grid.duplicate()
	out[0] = grid[23]
	out[23] = grid[0]
	out[5] = grid[18]
	out[18] = grid[5]
	return out


func test_crossing_indices_ignores_a_block_that_only_turned_and_marched() -> void:
	var before: Array = _grid(6, 4, SPACING, Vector2(50, 50))
	var after: Array = _grid(6, 4, SPACING, Vector2(95, 20), deg_to_rad(35.0))
	assert_eq(DemoDefects.crossing_indices(before, after, SPACING * 0.5).size(), 0,
			"rigid motion is removed first, so no man has an in-formation route at all")


func test_crossing_indices_names_the_men_who_traded_places_across_the_block() -> void:
	var grid: Array = _grid(6, 4, SPACING)
	var crossed: Array = DemoDefects.crossing_indices(grid, _swap_corners(grid), SPACING * 0.5)
	assert_eq(crossed, [0, 5, 18, 23], "exactly the four corner men took crossing routes")


func test_crossing_indices_drops_jostle_below_the_travel_floor() -> void:
	var grid: Array = _grid(6, 4, SPACING)
	var jittered: Array = []
	for i in range(grid.size()):
		var away: float = 1.0 if i % 2 == 0 else -1.0
		jittered.append([float(grid[i][0]) + away * SPACING * 0.1,
				float(grid[i][1]) - away * SPACING * 0.1])
	assert_eq(DemoDefects.crossing_indices(grid, jittered, SPACING * 0.5).size(), 0,
			"sub-floor jitter is press, not a journey across the block")


func test_repeated_place_trading_fails_path_crossing_while_a_turn_passes() -> void:
	var grid: Array = _grid(6, 4, SPACING)
	var swapped: Array = _swap_corners(grid)
	var trading: Array = [
		_snapshot(0, grid, grid), _snapshot(30, swapped, grid), _snapshot(60, grid, grid)]
	assert_false(bool(_verdict(DemoDefects.analyze(trading), "path_crossing")["pass"]),
			"men crossing the block to trade places is a route defect")
	var turning: Array = [
		_snapshot(0, _grid(6, 4, SPACING), grid),
		_snapshot(30, _grid(6, 4, SPACING, Vector2.ZERO, deg_to_rad(20.0)), grid),
		_snapshot(60, _grid(6, 4, SPACING, Vector2.ZERO, deg_to_rad(40.0)), grid)]
	assert_true(bool(_verdict(DemoDefects.analyze(turning), "path_crossing")["pass"]),
			"a block turning through the same angles keeps every man on his own route")


func test_exemption_requires_named_units_and_a_written_reason() -> void:
	var good: Dictionary = {"uids": [0], "reason": "the drill re-deals every man"}
	assert_eq(DemoDefects.exemption_error("path_crossing", good), "",
			"named units plus a stated reason is usable")
	assert_ne(DemoDefects.exemption_error("path_crossing", "just a string"), "",
			"a bare reason cannot say which units it covers")
	assert_ne(DemoDefects.exemption_error("path_crossing", {"uids": [0], "reason": ""}), "",
			"an exemption with no reason is indistinguishable from silencing a defect")
	assert_ne(DemoDefects.exemption_error("path_crossing", {"uids": [0], "reason": "  "}), "",
			"and whitespace is not a reason either")
	assert_ne(DemoDefects.exemption_error("path_crossing", {"uids": [], "reason": "r"}), "",
			"an empty uid list would forgive nothing or everything")
	assert_ne(DemoDefects.exemption_error("path_crossing", {"uids": ["a"], "reason": "r"}), "",
			"uids are numbers")
	assert_ne(DemoDefects.exemption_error("", good), "", "the metric name is required")


func test_an_exemption_forgives_only_the_units_it_names() -> void:
	# The shape most real declarations take: a multi-unit clip where one unit's maneuver
	# is deliberate and another unit's failure of the SAME metric is genuine.
	var verdicts: Array = [
		{"uid": 0, "metric": "path_crossing", "pass": false, "worst": 0.4, "threshold": 0.15},
		{"uid": 1, "metric": "path_crossing", "pass": false, "worst": 0.9, "threshold": 0.15},
		{"uid": 0, "metric": "blob", "pass": false, "worst": 1.0, "threshold": 4.5},
	]
	var out: Array = DemoDefects.apply_exemptions(
			verdicts, {"path_crossing": {"uids": [0], "reason": "counter-march"}})
	assert_true(bool(out[0]["pass"]), "the named unit's metric is forgiven")
	assert_eq(String(out[0]["exempt"]), "counter-march", "and carries its reason for printing")
	assert_false(bool(out[1]["pass"]),
			"an unnamed unit's failure of the same metric survives")
	assert_false(out[1].has("exempt"), "and is not dressed up as an exemption")
	assert_false(bool(out[2]["pass"]), "an unexempted metric is untouched")


func test_a_passing_named_unit_is_reported_stale_without_dragging_in_its_neighbours() -> void:
	var verdicts: Array = [
		{"uid": 0, "metric": "path_crossing", "pass": true, "worst": 0.0, "threshold": 0.15},
		{"uid": 1, "metric": "path_crossing", "pass": true, "worst": 0.0, "threshold": 0.15},
	]
	var out: Array = DemoDefects.apply_exemptions(
			verdicts, {"path_crossing": {"uids": [0], "reason": "no longer needed"}})
	assert_true(bool(out[0]["stale_exempt"]),
			"a unit that outgrew its defect should be told to drop its claim")
	assert_false(out[1].has("stale_exempt"),
			"a unit the exemption never named is not part of that judgement")


func test_an_exemption_naming_an_absent_unit_forgives_nothing() -> void:
	var verdicts: Array = [
		{"uid": 0, "metric": "path_crossing", "pass": false, "worst": 0.4, "threshold": 0.15}]
	var out: Array = DemoDefects.apply_exemptions(
			verdicts, {"path_crossing": {"uids": [7], "reason": "typo'd uid"}})
	assert_false(bool(out[0]["pass"]), "a mistyped uid leaves the clip red, the safe direction")

func test_expect_ticks_collects_scalars_and_range_ends() -> void:
	var expects: Array = [
		{"tick": 60, "uid": 0, "field": "state", "value": "MOVING"},
		{"tick": [480, 620], "uid": 0, "field": "state", "value": "FIGHTING"},
		{"tick": 60, "uid": 1, "field": "engaged", "value": false},
	]
	assert_eq(DemoDefects.expect_ticks(expects), [60, 480, 620],
			"scalars verbatim, ranges by both ends, deduped and sorted")


func test_expect_ticks_skips_malformed_entries_instead_of_crashing_the_recorder() -> void:
	# A bare number where an entry object belongs -- the adjacent `state` field's own
	# shape, so an easy authoring slip -- must not abort the live recording; it just
	# contributes no ticks (the analyzer's validation is where it fails loudly).
	var expects: Array = [
		60,
		{"tick": [480]},
		{"tick": 120, "uid": 0, "field": "state", "value": "MOVING"},
	]
	assert_eq(DemoDefects.expect_ticks(expects), [120],
			"only the well-formed entry contributes a tick")


func test_check_expectations_passes_and_fails_on_field_values() -> void:
	var snaps: Array = [
		{"tick": 60, "units": [{"uid": 0, "state": "MOVING", "engaged": false}]},
		{"tick": 540, "units": [{"uid": 0, "state": "FIGHTING", "engaged": true}]},
	]
	var verdicts: Array = DemoDefects.check_expectations([
		{"tick": 60, "uid": 0, "field": "state", "value": "MOVING"},
		{"tick": 60, "uid": 0, "field": "state", "value": "FIGHTING"},
	], snaps)
	assert_true(bool(verdicts[0]["pass"]), "a matching field value passes")
	assert_false(bool(verdicts[1]["pass"]), "a mismatched field value fails")
	assert_eq(str(verdicts[1]["worst"]), "MOVING", "the failure reports the actual value")


func test_check_expectations_range_passes_on_any_snapshot_inside_it() -> void:
	var snaps: Array = [
		{"tick": 480, "units": [{"uid": 0, "state": "MOVING"}]},
		{"tick": 540, "units": [{"uid": 0, "state": "FIGHTING"}]},
	]
	var verdicts: Array = DemoDefects.check_expectations([
		{"tick": [480, 620], "uid": 0, "field": "state", "value": "FIGHTING"},
	], snaps)
	assert_true(bool(verdicts[0]["pass"]),
			"a drift-tolerant range claim passes when any snapshot in range matches")


func test_malformed_expect_entries_are_named_errors_not_crashes() -> void:
	# A [480] range typo (missing upper bound) must surface as a shape error under the
	# tool's own contract -- never an out-of-bounds abort mid-evaluation.
	assert_ne(DemoDefects.expect_entry_error({"tick": [480], "uid": 0, "field": "state", "value": "X"}),
			"", "a one-element tick range is malformed")
	assert_ne(DemoDefects.expect_entry_error({"tick": [], "uid": 0, "field": "state", "value": "X"}),
			"", "an empty tick range is malformed")
	assert_ne(DemoDefects.expect_entry_error({"uid": 0, "field": "state", "value": "X"}),
			"", "a missing tick is malformed")
	assert_ne(DemoDefects.expect_entry_error({"tick": 60, "field": "state", "value": "X"}),
			"", "a missing uid is malformed")
	assert_eq(DemoDefects.expect_entry_error({"tick": [480, 620], "uid": 0, "field": "state", "value": "X"}),
			"", "a well-formed range entry validates clean")
	var snaps: Array = [{"tick": 60, "units": [{"uid": 0, "state": "MOVING"}]}]
	var verdicts: Array = DemoDefects.check_expectations([
		{"tick": [480], "uid": 0, "field": "state", "value": "X"},
		{"tick": 60, "uid": 0, "field": "state", "value": "MOVING"},
	], snaps)
	assert_false(bool(verdicts[0]["pass"]), "the malformed entry yields a failed verdict")
	assert_true(bool(verdicts[1]["pass"]), "and evaluation continues to the valid entries")


func test_check_expectations_fails_when_nothing_probeable_exists() -> void:
	var snaps: Array = [{"tick": 60, "units": [{"uid": 0, "state": "MOVING"}]}]
	var verdicts: Array = DemoDefects.check_expectations([
		{"tick": 300, "uid": 0, "field": "state", "value": "MOVING"},
		{"tick": 60, "uid": 7, "field": "state", "value": "MOVING"},
		{"tick": 60, "uid": 0, "field": "no_such_field", "value": 1},
	], snaps)
	for v in verdicts:
		assert_false(bool(v["pass"]),
				"an uncheckable expectation (%s) is an authoring failure, not a skip" % v["metric"])


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
	assert_almost_eq(float(rec["motion_ref"]["soldier_body_radius"]), u.soldier_body_radius(),
			0.001, "the body radius is the unit's own, so contact floors track the type")


# --- HUD readout consistency checks -----------------------------------------

func test_hud_consistency_passes_when_hud_matches_sim() -> void:
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 1, "formation": "NORMAL", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m",
				"ctrl_bar_visible": true,
			},
		},
		{
			"tick": 20,
			"units": [{"uid": 1, "formation": "SQUARE", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m Square",
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_eq(verdicts.size(), 2)
	assert_true(bool(verdicts[0]["pass"]), "formation consistency passes")
	assert_true(bool(verdicts[1]["pass"]), "selection consistency passes")


func test_hud_consistency_forgives_single_sample_clock_skew() -> void:
	# 1-sample transient mismatch (e.g. order landing tick before _process updates HUD text)
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 1, "formation": "NORMAL", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m",
				"ctrl_bar_visible": true,
			},
		},
		{
			"tick": 20,
			"units": [{"uid": 1, "formation": "TIGHT", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m", # transient 1-sample skew
				"ctrl_bar_visible": true,
			},
		},
		{
			"tick": 30,
			"units": [{"uid": 1, "formation": "TIGHT", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m locked", # resynced on next sample
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_true(bool(verdicts[0]["pass"]), "single-sample transition skew is forgiven")


func test_hud_consistency_detects_sustained_formation_mismatch() -> void:
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 1, "formation": "TIGHT", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m",
				"ctrl_bar_visible": true,
			},
		},
		{
			"tick": 20,
			"units": [{"uid": 1, "formation": "TIGHT", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m",
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_eq(verdicts.size(), 2)
	var form_verdict: Dictionary = verdicts[0]
	assert_eq(form_verdict["metric"], "hud_formation_consistency")
	assert_false(bool(form_verdict["pass"]), "sustained formation mismatch fails")
	assert_string_contains(str(form_verdict["worst"]), "sim TIGHT vs hud '0.45 m'")


func test_hud_consistency_detects_selection_mismatch_missing_unit() -> void:
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 2, "formation": "NORMAL"}],
			"hud": {
				"shown_unit_uid": 99,
				"formation_text": "0.45 m",
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_eq(verdicts.size(), 2)
	var sel_verdict: Dictionary = verdicts[1]
	assert_eq(sel_verdict["metric"], "hud_selection_consistency")
	assert_false(bool(sel_verdict["pass"]), "missing shown unit fails selection check")


func test_hud_consistency_detects_ctrl_bar_visible_with_no_unit() -> void:
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 1, "formation": "NORMAL"}],
			"hud": {
				"shown_unit_uid": null,
				"formation_text": "",
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_eq(verdicts.size(), 2)
	var sel_verdict: Dictionary = verdicts[1]
	assert_eq(sel_verdict["metric"], "hud_selection_consistency")
	assert_false(bool(sel_verdict["pass"]), "ctrl_bar visible without unit fails selection check")


func test_analyze_compact_dump_with_hud_returns_empty_verdicts() -> void:
	# A compact dump (lacking soldiers_full and motion_ref) must return empty verdicts
	# so analyze_transcript.gd's "no analyzable units" error is preserved.
	var compact_snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 1, "formation": "NORMAL"}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m",
				"ctrl_bar_visible": true,
			},
		},
	]
	var res: Dictionary = DemoDefects.analyze(compact_snaps)
	assert_true(res["verdicts"].is_empty(), "compact dump produces no verdicts from analyze")


func test_hud_formation_name_rebuilds_cavalry_anisotropic_label() -> void:
	assert_eq(DemoDefects.hud_formation_name("NORMAL", 20.0, 60.0), "1 x 3 m",
			"cavalry dump rebuilds file x rank, not the infantry 0.45 m default")
	assert_eq(DemoDefects.hud_formation_name("LOOSE", 80.0, 240.0), "4 x 12 m")
	assert_eq(DemoDefects.hud_formation_name("TIGHT", 9.0, 9.0), "0.45 m locked")
	assert_eq(DemoDefects.hud_formation_name("SQUARE", 20.0, 60.0), "1 m Square",
			"Square rebuild is isotropic at file pitch, matching the square grid")
	assert_eq(DemoDefects.hud_formation_name("SQUARE", 9.0, 9.0), "0.45 m Square")
	assert_eq(DemoDefects.hud_formation_name("UNKNOWN", 9.0, 9.0), "",
			"unknown mode skips rather than guessing")
	assert_eq(DemoDefects.hud_formation_name("NORMAL"), "",
			"omitted pitch skips rather than loading Unit.FORMATION_SPACING")


func test_strip_historical_name_drops_a_factions_own_formation_name() -> void:
	assert_eq(DemoDefects.strip_historical_name("0.45 m locked (synaspismos)"), "0.45 m locked")
	assert_eq(DemoDefects.strip_historical_name("1 x 3 m (agmen quadratum)"), "1 x 3 m")


func test_strip_historical_name_leaves_a_plain_caption_alone() -> void:
	# Every caption the rebuild produces is digits, "x", and a unit -- no parentheses -- so
	# stripping must be a no-op on all of them.
	for caption in ["0.45 m", "0.45 m locked", "1 x 3 m", "0.45 m Square", "4 x 12 m Testudo", ""]:
		assert_eq(DemoDefects.strip_historical_name(caption), caption)


func test_hud_consistency_ignores_a_factions_historical_name() -> void:
	# A faction battle appends its own name to the HUD's formation caption; the sim dump and
	# the pitch rebuild stay plain, so the check has to compare the interval/stance part.
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 1, "formation": "NORMAL", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m (pyknosis)",
				"ctrl_bar_visible": true,
			},
		},
		{
			"tick": 20,
			"units": [{"uid": 1, "formation": "TIGHT", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m locked (synaspismos)",
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_true(bool(verdicts[0]["pass"]), "formation consistency passes with historical names")


func test_hud_consistency_still_catches_a_real_mismatch_under_a_historical_name() -> void:
	# The strip must not become a blanket pass: a caption whose INTERVAL disagrees with the
	# sim is still a mismatch, historical name or not.
	var snaps: Array = []
	for tick in [10, 20, 30, 40]:
		snaps.append({
			"tick": tick,
			"units": [{"uid": 1, "formation": "TIGHT", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m (pyknosis)",   # NORMAL's caption while sim says TIGHT
				"ctrl_bar_visible": true,
			},
		})
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_false(bool(verdicts[0]["pass"]), "a sustained interval/stance mismatch still fails")


func test_hud_consistency_passes_dumped_formation_label() -> void:
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 1, "formation": "NORMAL", "formation_label": "1 x 3 m"}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "1 x 3 m",
				"ctrl_bar_visible": true,
			},
		},
		{
			"tick": 20,
			"units": [{"uid": 1, "formation": "NORMAL", "formation_label": "1 x 3 m"}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "1 x 3 m",
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_true(bool(verdicts[0]["pass"]), "dumped formation_label matches HUD without rebuild")


func test_hud_consistency_passes_cavalry_anisotropic_label() -> void:
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 1, "formation": "NORMAL", "file_pitch": 20.0, "rank_pitch": 60.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "1 x 3 m",
				"ctrl_bar_visible": true,
			},
		},
		{
			"tick": 20,
			"units": [{"uid": 1, "formation": "NORMAL", "file_pitch": 20.0, "rank_pitch": 60.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "1 x 3 m",
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_true(bool(verdicts[0]["pass"]), "cavalry HUD label matches dumped pitches")


func test_hud_consistency_detects_dump_vs_rebuild_mismatch() -> void:
	# Dumped caption disagrees with the pitch rebuild: suffix-map drift, not HUD skew.
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{
				"uid": 1,
				"formation": "NORMAL",
				"file_pitch": 20.0,
				"rank_pitch": 60.0,
				"formation_label": "0.45 m",
			}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m",
				"ctrl_bar_visible": true,
			},
		},
		{
			"tick": 20,
			"units": [{
				"uid": 1,
				"formation": "NORMAL",
				"file_pitch": 20.0,
				"rank_pitch": 60.0,
				"formation_label": "0.45 m",
			}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m",
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_false(bool(verdicts[0]["pass"]), "dump caption vs pitch rebuild must fail")
	assert_string_contains(str(verdicts[0]["worst"]), "pitch rebuild")


func test_hud_suffix_map_covers_every_dumped_formation_name() -> void:
	# Fail-closed coverage: a mode DemoState can dump must have a suffix entry,
	# or rebuild silently skips. Compare against DemoState.FORMATION_NAMES so
	# this file never imports Unit.
	var dumped: Array = DemoState.FORMATION_NAMES.values()
	assert_eq(DemoDefects._FORMATION_LABEL_SUFFIX.size(), dumped.size(),
			"suffix map and dump name table stay the same size")
	for formation_name in dumped:
		assert_true(DemoDefects._FORMATION_LABEL_SUFFIX.has(String(formation_name)),
				"suffix map covers dumped formation '%s'" % String(formation_name))


func test_hud_consistency_fails_unknown_formation_closed() -> void:
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 1, "formation": "WEDGE", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m",
				"ctrl_bar_visible": true,
			},
		},
		{
			"tick": 20,
			"units": [{"uid": 1, "formation": "WEDGE", "file_pitch": 9.0, "rank_pitch": 9.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "0.45 m",
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_false(bool(verdicts[0]["pass"]), "unknown formation fails closed")
	assert_string_contains(str(verdicts[0]["worst"]), "unknown formation")


func test_hud_consistency_detects_sustained_blank_caption() -> void:
	var snaps: Array = [
		{
			"tick": 10,
			"units": [{"uid": 1, "formation": "NORMAL", "file_pitch": 18.0, "rank_pitch": 18.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "",
				"ctrl_bar_visible": true,
			},
		},
		{
			"tick": 20,
			"units": [{"uid": 1, "formation": "NORMAL", "file_pitch": 18.0, "rank_pitch": 18.0}],
			"hud": {
				"shown_unit_uid": 1,
				"formation_text": "",
				"ctrl_bar_visible": true,
			},
		},
	]
	var verdicts: Array = DemoDefects.check_hud_consistency(snaps)
	assert_false(bool(verdicts[0]["pass"]), "blank HUD with a known expected label fails")
	assert_string_contains(str(verdicts[0]["worst"]), "blank hud")


