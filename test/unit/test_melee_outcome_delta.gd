extends GutTest
## The perturbed melee-outcome delta's pure parts: DemoSeed (the opt-in perturbation),
## MeleeOutcomes (per-run metrics from synthetic snapshots) and MeleeOutcomeDelta (the
## flagging rule). The Godot runs themselves are exercised by tools/ci/melee-outcome-delta.sh.


## A compact unit record as DemoState writes it, with only the fields the metrics read.
func _rec(uid: int, team: int, state: String, soldiers: int, contact: bool, x: float) -> Dictionary:
	return {"uid": uid, "team": team, "state": state, "soldiers": soldiers,
			"in_enemy_contact": contact, "soldier_summary_m": {"centroid_m": [x, 0.0]}}


func _snap(tick: int, units: Array, over: bool = false) -> Dictionary:
	var s: Dictionary = {"tick": tick, "units": units}
	if over:
		s["battle_over"] = true
	return s


## A router (uid 1) that meets uid 0 at tick 10, breaks at 30, gets clear at 50 and runs
## 1 m per 10 ticks from x = 5. Snapshots every 10 ticks to `last`.
func _router_run(last: int, over: bool = false) -> Array:
	var snaps: Array = []
	for t in range(0, last + 1, 10):
		var contact: bool = t >= 10 and t < 50
		var state: String = "ROUTING" if t >= 30 else ("FIGHTING" if t >= 10 else "MOVING")
		var x: float = 5.0 + maxf(0.0, float(t - 30) / 10.0)
		snaps.append(_snap(t, [_rec(0, 0, "FIGHTING", 20, contact, 0.0),
				_rec(1, 1, state, 8, contact, x)], over and t == last))
	return snaps


func test_seed_run_parses_and_is_off_by_default() -> void:
	assert_eq(DemoSeed.parse_run(""), 0, "unset is off")
	assert_eq(DemoSeed.parse_run(" 3 "), 3)
	assert_eq(DemoSeed.parse_run("abc"), -1, "a typo is an error, not off")
	assert_eq(DemoSeed.parse_run("-2"), -1)


func test_seed_for_run_keeps_run_zero_and_varies_the_rest() -> void:
	assert_eq(DemoSeed.seed_for_run(12345, 0), 12345, "run 0 plays the clip's own seed")
	var seen: Dictionary = {}
	for run in range(1, 17):
		var s: int = DemoSeed.seed_for_run(12345, run)
		assert_true(s >= 0, "a forced seed must be non-negative to take effect")
		seen[s] = true
	assert_eq(seen.size(), 16, "16 runs give 16 distinct seeds")
	assert_eq(DemoSeed.seed_for_run(12345, 4), DemoSeed.seed_for_run(12345, 4), "deterministic")


func test_extract_router_metrics() -> void:
	var m: Dictionary = MeleeOutcomes.extract(_router_run(400), [60, 150])
	assert_eq(m["first_contact"], 10)
	assert_eq(m["uid1_first_contact"], 10)
	assert_eq(m["uid1_break"], 30)
	assert_eq(m["uid1_contact_break"], 20, "clear at 50, broke at 30")
	assert_almost_eq(float(m["uid1_travel_60"]), 6.0, 1e-6, "x 5 -> 11 by tick 90")
	assert_almost_eq(float(m["uid1_travel_150"]), 15.0, 1e-6)
	assert_eq(m["uid0_break"], null, "uid 0 never broke")
	assert_false(m.has("uid0_contact_break"), "no contact-break metric without a break")
	assert_eq(m["team_0_men"], 20)
	assert_eq(m["team_1_men"], 8)


func test_extract_cut_off_versus_decided_stream() -> void:
	# The stream ends at tick 100, 70 ticks after the break.
	var cut: Dictionary = MeleeOutcomes.extract(_router_run(100), [60, 150])
	assert_almost_eq(float(cut["uid1_travel_60"]), 6.0, 1e-6)
	assert_eq(cut["uid1_travel_150"], null, "a cut-off stream cannot say where the router got to")
	var decided: Dictionary = MeleeOutcomes.extract(_router_run(100, true), [60, 150])
	assert_almost_eq(float(decided["uid1_travel_150"]), 7.0, 1e-6, "a decided battle is frozen at its end")


func test_extract_router_cut_down_in_contact() -> void:
	var snaps: Array = [
		_snap(0, [_rec(0, 0, "FIGHTING", 20, true, 0.0), _rec(1, 1, "FIGHTING", 5, true, 5.0)]),
		_snap(10, [_rec(0, 0, "FIGHTING", 20, true, 0.0), _rec(1, 1, "ROUTING", 2, true, 6.0)]),
		_snap(20, [_rec(0, 0, "FIGHTING", 20, true, 0.0)], true),
	]
	var m: Dictionary = MeleeOutcomes.extract(snaps, [60])
	assert_eq(m["uid1_break"], 10)
	assert_eq(m["uid1_contact_break"], null, "never got clear before it was cut down")
	assert_almost_eq(float(m["uid1_travel_60"]), 0.0, 1e-6, "travel stops at its last living centroid")
	assert_eq(m["team_1_men"], 0, "an absent unit has no men")


func _runs(values: Array) -> Array:
	return values.map(func(v) -> Dictionary: return {"uid1_break": v})


func test_compare_same_distribution_flags_nothing() -> void:
	var runs: Array = _runs([600, 640, 610, 700, 655, 620, 690, 630])
	var result: Dictionary = MeleeOutcomeDelta.compare({"c": runs}, {"c": runs})
	assert_eq(result["tested"], 1)
	assert_false(result["rows"][0]["flag"])
	assert_eq(result["rows"][0]["p"], 1.0)


func test_compare_flags_a_large_significant_shift_only() -> void:
	var base: Array = _runs([600, 610, 620, 630, 640, 650, 660, 670])
	var late: Array = _runs([700, 710, 720, 730, 740, 750, 760, 770])
	var r: Dictionary = MeleeOutcomeDelta.compare({"c": base}, {"c": late})["rows"][0]
	assert_true(r["flag"], "100 ticks later with no overlap is flagged")
	assert_eq(r["shift"], 100.0)
	# One to eight ticks later than a constant is significant but under the 30-tick threshold.
	var nudged: Array = _runs([601, 602, 603, 604, 605, 606, 607, 608])
	var near: Dictionary = MeleeOutcomeDelta.compare({"c": _runs([600, 600, 600, 600, 600, 600, 600, 600])},
			{"c": nudged})["rows"][0]
	assert_true(near["significant"])
	assert_false(near["flag"], "a significant shift below the practical threshold is not flagged")
	var loose: Dictionary = MeleeOutcomeDelta.compare({"c": base}, {"c": late}, {"min_ticks": 200.0})
	assert_false(loose["rows"][0]["flag"], "the threshold is configurable")


func test_compare_counts_never_as_latest() -> void:
	var base: Array = _runs([null, null, null, null, null, null])
	var head: Array = _runs([400, 410, 420, 430, 440, 450])
	var r: Dictionary = MeleeOutcomeDelta.compare({"c": base}, {"c": head})["rows"][0]
	assert_true(r["flag"], "a unit that now breaks every run where it never did is flagged")
	assert_eq(r["never_base"], 6)
	assert_eq(MeleeOutcomeDelta.cell(r["base"]), "never")


func test_compare_skips_too_few_runs_and_identical() -> void:
	var r: Dictionary = MeleeOutcomeDelta.compare({"c": _runs([1, 2, 3])}, {"c": _runs([50, 60, 70])})
	assert_eq(r["rows"][0]["status"], "too few runs")
	assert_eq(r["tested"], 0)
	var same: Dictionary = MeleeOutcomeDelta.compare({"c": _runs([5, 5, 5, 5])}, {"c": _runs([5, 5, 5, 5])})
	assert_eq(same["rows"][0]["status"], "identical")


func test_metric_units_and_thresholds() -> void:
	assert_eq(MeleeOutcomeDelta.metric_unit("team_0_men"), "men")
	assert_eq(MeleeOutcomeDelta.metric_unit("uid3_travel_150"), "metres")
	assert_eq(MeleeOutcomeDelta.metric_unit("uid3_contact_break"), "ticks")
	assert_eq(MeleeOutcomeDelta.threshold("team_0_men", {"min_men": 5.0}), 5.0)
	assert_eq(MeleeOutcomeDelta.threshold("uid3_break", {}), 30.0)


func test_report_names_flagged_rows() -> void:
	var base: Dictionary = {"c": _runs([600, 610, 620, 630, 640, 650, 660, 670])}
	var head: Dictionary = {"c": _runs([700, 710, 720, 730, 740, 750, 760, 770])}
	var md: String = MeleeOutcomeReport.markdown(MeleeOutcomeDelta.compare(base, head), {}, base, "L")
	assert_string_contains(md, "**1 flagged shift(s):**")
	assert_string_contains(md, "| `c` | `uid1_break` | 635.0 | 735.0 | 100.0 ticks |")
	var none: String = MeleeOutcomeReport.markdown(MeleeOutcomeDelta.compare(base, base), {}, base)
	assert_string_contains(none, "**No flagged shifts.**")
