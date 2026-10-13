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
	var m: Dictionary = MeleeOutcomes.extract(_router_run(400), [60, 150], 400)
	assert_eq(m["first_contact"], 10)
	assert_eq(m["uid1_first_contact"], 10)
	assert_eq(m["uid1_break"], 30)
	assert_eq(m["uid1_contact_break"], 20, "clear at 50, broke at 30")
	assert_almost_eq(float(m["uid1_travel_60"]), 6.0, 1e-6, "x 5 -> 11 by tick 90")
	assert_almost_eq(float(m["uid1_travel_150"]), 15.0, 1e-6)
	assert_eq(m["uid1_removed_by_150"], 0, "still on the field at break + 150")
	assert_eq(m["uid1_removed"], MeleeOutcomes.NEVER, "observed to the end, never removed")
	assert_eq(m["uid0_break"], MeleeOutcomes.NEVER, "observed to the end, never broke")
	assert_false(m.has("uid0_contact_break"), "no contact-break metric without a break")
	assert_eq(m["team_0_men"], 20)
	assert_eq(m["team_1_men"], 8)


func test_extract_cut_off_stream_is_unobserved_not_never() -> void:
	# The stream ends at tick 100 of a clip meant to run to 400, 70 ticks after the break.
	var cut: Dictionary = MeleeOutcomes.extract(_router_run(100), [60, 150], 400)
	assert_almost_eq(float(cut["uid1_travel_60"]), 6.0, 1e-6)
	assert_eq(cut["uid1_travel_150"], null, "a cut-off stream cannot say where the router got to")
	assert_eq(cut["uid1_removed_by_150"], null)
	assert_eq(cut["uid0_break"], null, "a cut-off stream cannot say uid 0 never breaks")
	assert_eq(cut["team_0_men"], null, "nor how many men are left at the end")
	var decided: Dictionary = MeleeOutcomes.extract(_router_run(100, true), [60, 150], 400)
	assert_almost_eq(float(decided["uid1_travel_150"]), 7.0, 1e-6, "a decided battle is frozen at its end")
	assert_eq(decided["uid0_break"], MeleeOutcomes.NEVER, "a decided battle is complete")
	assert_eq(decided["team_0_men"], 20)


func test_extract_router_cut_down_in_contact_is_censored() -> void:
	var snaps: Array = [
		_snap(0, [_rec(0, 0, "FIGHTING", 20, true, 0.0), _rec(1, 1, "FIGHTING", 5, true, 5.0)]),
		_snap(10, [_rec(0, 0, "FIGHTING", 20, true, 0.0), _rec(1, 1, "ROUTING", 2, true, 6.0)]),
		_snap(20, [_rec(0, 0, "FIGHTING", 20, true, 0.0)], true),
	]
	var m: Dictionary = MeleeOutcomes.extract(snaps, [60], 400)
	assert_eq(m["uid1_break"], 10)
	assert_eq(m["uid1_removed"], 20)
	assert_eq(m["uid1_contact_break"], null, "left play in contact: not a never-got-clear")
	assert_eq(m["uid1_travel_60"], null, "travel past its removal is censored, not ranked")
	assert_eq(m["uid1_removed_by_60"], 1)
	assert_eq(m["team_1_men"], 0, "an absent unit has no men")


func test_extract_unit_removed_before_routing() -> void:
	var snaps: Array = [
		_snap(0, [_rec(0, 0, "FIGHTING", 20, true, 0.0), _rec(1, 1, "FIGHTING", 5, true, 5.0)]),
		_snap(10, [_rec(0, 0, "FIGHTING", 20, true, 0.0), _rec(1, 1, "FIGHTING", 0, true, 5.0)]),
		_snap(20, [_rec(0, 0, "FIGHTING", 20, true, 0.0)]),
	]
	var m: Dictionary = MeleeOutcomes.extract(snaps, [60], 20)
	assert_eq(m["uid1_break"], null, "destroyed unbroken: whether it would break is unobserved")
	assert_eq(m["uid1_removed"], 10, "no men left counts as removed")


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
	# Base spread: MAD 20 ticks, robust sd 29.652; half of it is the threshold.
	assert_almost_eq(float(r["threshold"]), 14.826, 1e-6)
	assert_almost_eq(float(r["min_p"]), 2.0 / 12870.0, 1e-15)
	assert_true(r["mds"] >= r["threshold"] and r["mds"] < INF, "a finite MDS, never under the threshold")
	# One to eight ticks later than a constant: significant, but its 4.5-tick shift is under
	# the 5-tick resolution floor, which is the threshold of a row with no spread.
	var nudged: Array = _runs([601, 602, 603, 604, 605, 606, 607, 608])
	var near: Dictionary = MeleeOutcomeDelta.compare({"c": _runs([600, 600, 600, 600, 600, 600, 600, 600])},
			{"c": nudged})["rows"][0]
	assert_true(near["significant"])
	assert_false(near["flag"], "a significant shift below the row's threshold is not flagged")
	var loose: Dictionary = MeleeOutcomeDelta.compare({"c": base}, {"c": late}, {"min_effect": 10.0})
	assert_false(loose["rows"][0]["flag"], "the effect multiple is configurable")


func test_compare_counts_never_as_latest_and_drops_unobserved() -> void:
	var base: Array = _runs(["never", "never", "never", "never", "never", "never", null])
	var head: Array = _runs([400, 410, 420, 430, 440, 450, null])
	var result: Dictionary = MeleeOutcomeDelta.compare({"c": base}, {"c": head})
	var r: Dictionary = result["rows"][0]
	assert_true(r["flag"], "a unit that now breaks every run where it never did is flagged")
	assert_eq(r["never_base"], 6)
	assert_eq(r["n_base"], 6, "the unobserved run is dropped, not ranked")
	assert_eq(r["dropped_base"], 1)
	assert_eq(r["mds_unit"], "pp never", "its detectable change is in how often it never breaks")
	assert_true(r["mds"] < INF)
	var censor: Dictionary = result["rows"][1]
	assert_eq(censor["metric"], "uid1_break:unobserved")
	assert_false(censor["significant"], "1 of 7 on each side is no difference")
	assert_eq(MeleeOutcomeDelta.cell(r["base"]), "never")


func _flags(key: String, ones: int, zeros: int, nulls: int) -> Array:
	var out: Array = []
	for i in range(ones):
		out.append({key: 1})
	for i in range(zeros):
		out.append({key: 0})
	for i in range(nulls):
		out.append({key: null})
	return out


func test_indicator_is_a_proportion_tested_with_fisher() -> void:
	# Removed by +150 in 0 of 16 base runs and 7 of 16 head runs: 43.75 percentage points.
	var key: String = "uid1_removed_by_150"
	var r: Dictionary = MeleeOutcomeDelta.compare({"c": _flags(key, 0, 16, 0)},
			{"c": _flags(key, 7, 9, 0)})["rows"][0]
	assert_eq(r["kind"], "proportion")
	assert_almost_eq(float(r["shift"]), 43.75, 1e-9)
	assert_almost_eq(float(r["p"]), OutcomeStats.fisher_p(0, 16, 7, 16), 1e-12)
	assert_true(r["flag"], "a 0% to 44% change is flaggable, unlike a median of 0/1 values")
	assert_true(r["mds"] >= 20.0 and r["mds"] < INF, "in percentage points, at least min_pp")


func test_censoring_that_differs_makes_a_row_not_comparable() -> void:
	# Travel unobserved in 1 of 16 base runs but 12 of 16 head runs.
	var key: String = "uid1_travel_300"
	var base: Array = _flags(key, 0, 0, 1)
	var head: Array = _flags(key, 0, 0, 12)
	for i in range(15):
		base.append({key: 10.0 + i})
	for i in range(4):
		head.append({key: 20.0 + i})
	var rows: Array = MeleeOutcomeDelta.compare({"c": base}, {"c": head})["rows"]
	assert_eq(rows[1]["metric"], key + ":unobserved")
	assert_true(rows[1]["significant"], "1/16 against 12/16 unobserved")
	assert_true(rows[1]["flag"], "a censoring row is flagged on significance alone")
	assert_eq(rows[0]["status"], "not comparable")
	assert_false(rows[0]["flag"])
	assert_eq([rows[0]["dropped_base"], rows[0]["dropped_head"]], [1, 12])


func test_compare_skips_too_few_runs_and_identical() -> void:
	var r: Dictionary = MeleeOutcomeDelta.compare({"c": _runs([1, 2, 3])}, {"c": _runs([50, 60, 70])})
	assert_eq(r["rows"][0]["status"], "too few runs")
	assert_eq(r["tested"], 0)
	var same: Dictionary = MeleeOutcomeDelta.compare({"c": _runs([5, 5, 5, 5])}, {"c": _runs([5, 5, 5, 5])})
	assert_eq(same["rows"][0]["status"], "identical")


func test_compare_metric_filter_keeps_only_matching_rows() -> void:
	var runs: Array = [{"uid1_break": 1, "team_0_men": 5}, {"uid1_break": 2, "team_0_men": 6}]
	var rows: Array = MeleeOutcomeDelta.compare({"c": runs}, {"c": runs}, {"metrics": "_break$"})["rows"]
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["metric"], "uid1_break")


func test_single_row_level_bh_and_by() -> void:
	assert_almost_eq(MeleeOutcomeDelta.single_row_level(10, {}), 0.005, 1e-12)
	assert_almost_eq(MeleeOutcomeDelta.single_row_level(10, {"correction": "by"}),
			0.005 / OutcomeStats.harmonic(10), 1e-12)


func test_metric_units_and_thresholds() -> void:
	assert_eq(MeleeOutcomeDelta.metric_unit("team_0_men"), "men")
	assert_eq(MeleeOutcomeDelta.metric_unit("uid3_travel_150"), "metres")
	assert_eq(MeleeOutcomeDelta.metric_unit("uid3_removed_by_150"), "pp")
	assert_eq(MeleeOutcomeDelta.metric_unit("uid3_contact_break"), "ticks")
	assert_eq(MeleeOutcomeDelta.threshold("team_0_men", [10.0, 10.0, 10.0], {"floor_men": 5.0}), 5.0,
			"no spread: the floor")
	# Median 20, MAD 10, robust sd 14.826; half of it.
	assert_almost_eq(MeleeOutcomeDelta.threshold("uid3_break", [0.0, 10.0, 20.0, 30.0, 40.0], {}),
			7.413, 1e-9)


func test_report_names_flagged_rows_and_warns_about_silence() -> void:
	var base: Dictionary = {"c": _runs([600, 610, 620, 630, 640, 650, 660, 670])}
	var head: Dictionary = {"c": _runs([700, 710, 720, 730, 740, 750, 760, 770])}
	var md: String = MeleeOutcomeReport.markdown(MeleeOutcomeDelta.compare(base, head), {}, base, "L")
	assert_string_contains(md, "**1 flagged shift(s):**")
	assert_string_contains(md, "| `c` | `uid1_break` | 635.0 | 735.0 | 100.0 ticks |")
	assert_string_contains(md, "false discovery rate")
	assert_string_contains(md, "| 0.0002 |", "a p of 2 / 12870 to 4 decimals")
	assert_eq(MeleeOutcomeReport._p_cell(2.0 / 601080390.0), "3.3e-9", "a tiny p in exponent form")
	var none: String = MeleeOutcomeReport.markdown(MeleeOutcomeDelta.compare(base, base), {}, base)
	assert_string_contains(none, "**No flagged shifts.**")
	assert_string_contains(none, "**No flag is not evidence of no effect.**")


func test_travel_nulls_explained_by_the_indicator_add_no_second_test() -> void:
	# Per side: 8 runs still on the field (travel observed, removed_by 0), 6 removed before the
	# offset (travel null, removed_by 1) and 2 cut off (both null). Removal is tested by the
	# removed_by row and the cut-off by removed_by's ":unobserved" row, so travel must not
	# test either again.
	var runs: Array = []
	for i in range(8):
		runs.append({"uid1_travel_150": 3.0 + i, "uid1_removed_by_150": 0})
	for i in range(6):
		runs.append({"uid1_travel_150": null, "uid1_removed_by_150": 1})
	for i in range(2):
		runs.append({"uid1_travel_150": null, "uid1_removed_by_150": null})
	var rows: Array = MeleeOutcomeDelta.compare({"c": runs}, {"c": runs})["rows"]
	var names: Array = rows.map(func(r: Dictionary) -> String: return r["metric"])
	names.sort()
	assert_eq(names, ["uid1_removed_by_150", "uid1_removed_by_150:unobserved", "uid1_travel_150"],
			"one test per question: removal, cut-off, and the travel itself")
	assert_eq(MeleeOutcomeDelta.unexplained(runs, "uid1_travel_150"), [0, 8])
	assert_eq(MeleeOutcomeDelta.unexplained(runs, "uid1_removed_by_150"), [2, 16])


func test_report_does_not_count_a_not_comparable_row_as_significant_but_small() -> void:
	# The travel values differ hugely, but the two sides left very different shares unobserved.
	var key: String = "uid1_travel_300"
	var base: Array = _flags(key, 0, 0, 1)
	var head: Array = _flags(key, 0, 0, 12)
	for i in range(15):
		base.append({key: 10.0 + i})
	for i in range(4):
		head.append({key: 100.0 + i})
	var base_runs: Dictionary = {"c": base}
	var result: Dictionary = MeleeOutcomeDelta.compare(base_runs, {"c": head})
	assert_eq(result["rows"][0]["status"], "not comparable")
	var md: String = MeleeOutcomeReport.markdown(result, {}, base_runs)
	assert_false(md.contains("significant but below"), "a withdrawn row is not a small shift")
	assert_string_contains(md, "1 row(s) are not comparable")


## Runs of uid1 at +300: `observed` still on the field with travel `first`, `first` + 1, ...,
## and `removed` taken out of play before the offset.
func _travel_runs(observed: int, first: float, removed: int) -> Array:
	var runs: Array = []
	for i in range(observed):
		runs.append({"uid1_travel_300": first + i, "uid1_removed_by_300": 0, "uid1_break": 100})
	for i in range(removed):
		runs.append({"uid1_travel_300": null, "uid1_removed_by_300": 1, "uid1_break": 100})
	return runs


func test_travel_is_withdrawn_when_the_removal_shares_differ() -> void:
	# 2 of 16 removed on base against 12 of 16 on head: the head's travel describes 4
	# survivors, not the same units, so its large shift is not comparable.
	var result: Dictionary = MeleeOutcomeDelta.compare({"c": _travel_runs(14, 10.0, 2)},
			{"c": _travel_runs(4, 100.0, 12)})
	var by_metric: Dictionary = {}
	for r in result["rows"]:
		by_metric[r["metric"]] = r
	assert_true(by_metric["uid1_removed_by_300"]["significant"])
	assert_true(by_metric["uid1_removed_by_300"]["flag"], "the removal change is the finding")
	assert_eq(by_metric["uid1_travel_300"]["status"], "not comparable")
	assert_false(by_metric["uid1_travel_300"]["flag"])


func test_a_metrics_filter_on_travel_keeps_its_removal_indicator() -> void:
	var rows: Array = MeleeOutcomeDelta.compare({"c": _travel_runs(14, 10.0, 2)},
			{"c": _travel_runs(4, 100.0, 12)}, {"metrics": "travel_300$"})["rows"]
	var names: Array = rows.map(func(r: Dictionary) -> String: return r["metric"])
	names.sort()
	assert_eq(names, ["uid1_removed_by_300", "uid1_travel_300"],
			"the indicator comes along; the unfiltered break row does not")
	assert_false(rows.filter(func(r: Dictionary) -> bool: return r["metric"] == "uid1_travel_300")[0]["flag"])
