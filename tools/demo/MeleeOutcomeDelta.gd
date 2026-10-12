class_name MeleeOutcomeDelta
## The comparison behind tools/ci/melee-outcome-delta.sh: given each side's per-run
## MeleeOutcomes metrics for every clip, test each metric's base and head distributions
## and decide which shifts to flag. Pure apart from OutcomeStats' and OutcomePower's caches,
## so it is unit-tested without a battle (test/unit/test_melee_outcome_delta.gd).
##
## Two kinds of row:
##   - rank rows (ticks, metres, men): the exact two-sided rank-sum test, the Hodges-Lehmann
##     shift as the effect, and a threshold of `min_effect` times the row's own run-to-run
##     spread (OutcomeStats.robust_sd of the base runs), never below the floor for its unit.
##     An event that never happened in a complete run ranks above every tick.
##     TODO(#1832): once escapes are told from deaths, test censored rows with a
##     censoring-aware rank test (Gehan) instead of dropping the censored runs.
##   - proportion rows: Fisher's exact test, the change in percentage points as the effect.
##     A removed-by indicator's threshold is `min_pp`. Every rank or indicator row with an
##     unobserved (null) value on either side also gets a "<metric>:unobserved" row testing how
##     often the value went unobserved, flagged on significance alone. When that row is
##     significant, the value row is "not comparable": its two sides dropped different runs.
##
## A row is significant when Benjamini-Hochberg (or, with correction "by",
## Benjamini-Yekutieli) rejects it at `alpha` across every row tested in the report. That
## bounds the expected share of false flags among the flags (the false discovery rate). Only
## when no row has a real change does it also bound the chance of any flag, and BH's bound
## assumes independent or positively dependent rows; BY's holds under any dependence.
## A rank or indicator row is flagged when it is significant and its effect reaches its
## threshold.
##
## Every tested row also reports its smallest attainable p-value and its minimum detectable
## change (MDS): the change a fresh pair of samples of the row's own sizes would show as
## significant alone (at alpha / m, divided again by the harmonic number for BY) with
## probability `power` (OutcomePower), and never less than the row's threshold, since a
## smaller change is never flagged. For a rank row it is a shift in the row's units (the
## normal-model shift in SD times the row's spread); for a rank row with "never" in its base
## runs, the change in how often the event never happens; for a proportion row, the change
## in percentage points. It is INF when the row cannot reach the level with any change.

## Rank value standing for "never happened in this run".
const NEVER := 1.0e12
## The suffix of a row testing how often a metric went unobserved.
const UNOBSERVED := ":unobserved"

## Defaults for every tunable; each can be overridden through `config`.
##   alpha        false discovery rate
##   correction   "bh" (Benjamini-Hochberg) or "by" (Benjamini-Yekutieli)
##   min_effect   rank-row threshold as a multiple of the row's run-to-run spread
##   floor_*      smallest rank-row threshold per unit: the snapshot cadence for ticks, and
##                the measurement resolution for metres and men
##   min_pp       indicator threshold, in percentage points
##   min_runs     fewest runs per side for a row to be tested
##   metrics      a regular expression a metric key must match to be in the report at all
##                ("" keeps every metric), so a question about a few rows keeps m small
##   power        the power the minimum detectable change is computed at
##   trials       simulation trials behind each minimum detectable change
const DEFAULTS := {
	"alpha": 0.05,
	"correction": "bh",
	"min_effect": 0.5,
	"floor_ticks": 5.0,
	"floor_metres": 0.1,
	"floor_men": 1.0,
	"min_pp": 20.0,
	"min_runs": 4,
	"metrics": "",
	"power": 0.8,
	"trials": 400,
}


## "men", "pp" (an indicator, as a proportion), "metres" or "ticks": a metric key's unit.
static func metric_unit(key: String) -> String:
	if key.ends_with("_men"):
		return "men"
	if key.contains("_removed_by_") or key.ends_with(UNOBSERVED):
		return "pp"
	if key.contains("_travel_"):
		return "metres"
	return "ticks"


## A rank row's threshold: min_effect times the spread of its finite base values, but at
## least the floor for its unit. An indicator's is min_pp, a censoring row's 0.
static func threshold(key: String, base: Array, config: Dictionary) -> float:
	var cfg: Dictionary = DEFAULTS.merged(config, true)
	if key.ends_with(UNOBSERVED):
		return 0.0
	if metric_unit(key) == "pp":
		return float(cfg["min_pp"])
	var finite: Array = base.filter(func(v) -> bool: return v != NEVER)
	var floor_value: float = float(cfg["floor_" + metric_unit(key)])
	return maxf(floor_value, float(cfg["min_effect"]) * OutcomeStats.robust_sd(finite))


## One side's sample of `key` over `runs` (MeleeOutcomes dictionaries):
## {"values": [...], "dropped": int}. "never" becomes NEVER; a null (unobserved) value is
## counted in dropped and left out; a run without the key adds nothing.
static func sample(runs: Array, key: String) -> Dictionary:
	var out: Array = []
	var dropped: int = 0
	for run in runs:
		if not run.has(key):
			continue
		var v = run[key]
		if v == null:
			dropped += 1
			continue
		out.append(NEVER if str(v) == MeleeOutcomes.NEVER else float(v))
	return {"values": out, "dropped": dropped}


## The p-value level one row must reach to be flagged on its own among `m` tested rows.
static func single_row_level(m: int, config: Dictionary) -> float:
	var cfg: Dictionary = DEFAULTS.merged(config, true)
	var level: float = float(cfg["alpha"]) / float(maxi(m, 1))
	if str(cfg["correction"]) == "by":
		level /= OutcomeStats.harmonic(m)
	return level


## Compare every clip. `base` and `head` map clip name -> Array of per-run metric
## dictionaries. Returns {"rows": [...], "tested": int, "level": float} where each row is
## {clip, metric, kind, unit, n_base, n_head, dropped_base, dropped_head, base, head,
## never_base, never_head, shift, threshold, p, min_p, mds, mds_unit, status, significant,
## flag}. status is "tested", "identical", "too few runs" or "not comparable"; base and head
## are medians for a rank row and percentages for a proportion row.
static func compare(base: Dictionary, head: Dictionary, config: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = DEFAULTS.merged(config, true)
	var filter := RegEx.new()
	if str(cfg["metrics"]) != "":
		filter.compile(str(cfg["metrics"]))
	var rows: Array = []
	var clips: Array = base.keys().filter(func(c) -> bool: return head.has(c))
	clips.sort()
	for clip in clips:
		var keys: Dictionary = {}
		for run in base[clip] + head[clip]:
			for k in run:
				keys[k] = true
		var names: Array = keys.keys()
		names.sort()
		for key in names:
			if filter.is_valid() and filter.search(key) == null:
				continue
			var b: Dictionary = sample(base[clip], key)
			var h: Dictionary = sample(head[clip], key)
			var row: Dictionary = _value_row(clip, key, b, h, cfg)
			rows.append(row)
			if b["dropped"] + h["dropped"] > 0:
				var censor: Dictionary = _proportion_row(clip, key + UNOBSERVED,
						b["dropped"], b["dropped"] + b["values"].size(),
						h["dropped"], h["dropped"] + h["values"].size(), cfg)
				censor["_parent"] = row
				rows.append(censor)
	var tested: Array = rows.filter(func(r: Dictionary) -> bool: return r["status"] == "tested")
	var p_values: Array = tested.map(func(r: Dictionary) -> float: return r["p"])
	var rejected: Array = OutcomeStats.benjamini_yekutieli(p_values, float(cfg["alpha"])) \
			if str(cfg["correction"]) == "by" \
			else OutcomeStats.benjamini_hochberg(p_values, float(cfg["alpha"]))
	var level: float = single_row_level(tested.size(), cfg)
	for i in range(tested.size()):
		var r: Dictionary = tested[i]
		r["significant"] = rejected[i]
		r["flag"] = rejected[i] and absf(r["shift"]) >= r["threshold"]
		_detectable(r, level, cfg)
	for r in rows:
		if r.has("_parent") and r["significant"]:
			r["_parent"]["status"] = "not comparable"
			r["_parent"]["flag"] = false
	for r in rows:
		for k in ["_b", "_h", "_parent"]:
			r.erase(k)
	return {"rows": rows, "tested": tested.size(), "level": level}


static func _value_row(clip: String, key: String, b: Dictionary, h: Dictionary,
		cfg: Dictionary) -> Dictionary:
	var bv: Array = b["values"]
	var hv: Array = h["values"]
	if metric_unit(key) == "pp":
		var row: Dictionary = _proportion_row(clip, key, bv.count(1.0), bv.size(), hv.count(1.0),
				hv.size(), cfg)
		row["dropped_base"] = b["dropped"]
		row["dropped_head"] = h["dropped"]
		return row
	var row: Dictionary = {
		"clip": clip, "metric": key, "kind": "rank", "unit": metric_unit(key),
		"n_base": bv.size(), "n_head": hv.size(),
		"dropped_base": b["dropped"], "dropped_head": h["dropped"],
		"base": OutcomeStats.median(bv), "head": OutcomeStats.median(hv),
		"never_base": bv.count(NEVER), "never_head": hv.count(NEVER),
		"shift": OutcomeStats.hodges_lehmann(bv, hv), "threshold": threshold(key, bv, cfg),
		"p": 1.0, "min_p": 1.0, "mds": INF, "mds_unit": metric_unit(key), "status": "tested",
		"significant": false, "flag": false, "_b": bv, "_h": hv,
	}
	var min_runs: int = maxi(1, int(cfg["min_runs"]))
	if bv.size() < min_runs or hv.size() < min_runs:
		row["status"] = "too few runs"
	elif (bv + hv).all(func(v) -> bool: return v == bv[0]):
		row["status"] = "identical"
	else:
		row["p"] = OutcomeStats.rank_sum_p(bv, hv)
	return row


## A proportion row: x1 of n1 base runs against x2 of n2 head runs, in percentage points.
static func _proportion_row(clip: String, key: String, x1: int, n1: int, x2: int, n2: int,
		cfg: Dictionary) -> Dictionary:
	var p1: float = 100.0 * x1 / n1 if n1 > 0 else 0.0
	var p2: float = 100.0 * x2 / n2 if n2 > 0 else 0.0
	var row: Dictionary = {
		"clip": clip, "metric": key, "kind": "proportion", "unit": "pp",
		"n_base": n1, "n_head": n2, "dropped_base": 0, "dropped_head": 0,
		"base": p1, "head": p2, "never_base": 0, "never_head": 0,
		"shift": p2 - p1, "threshold": threshold(key, [], cfg),
		"p": 1.0, "min_p": 1.0, "mds": INF, "mds_unit": "pp", "status": "tested",
		"significant": false, "flag": false, "_b": [x1, n1], "_h": [x2, n2],
	}
	var min_runs: int = maxi(1, int(cfg["min_runs"]))
	if n1 < min_runs or n2 < min_runs:
		row["status"] = "too few runs"
	elif x1 + x2 == 0 or x1 + x2 == n1 + n2:
		row["status"] = "identical"
	else:
		row["p"] = OutcomeStats.fisher_p(x1, n1, x2, n2)
	return row


## Fill a tested row's smallest attainable p and minimum detectable change at `level`.
static func _detectable(r: Dictionary, level: float, cfg: Dictionary) -> void:
	var power: float = float(cfg["power"])
	var trials: int = int(cfg["trials"])
	if r["kind"] == "proportion":
		var x: int = r["_b"][0] + r["_h"][0]
		var n1: int = r["_b"][1]
		var n2: int = r["_h"][1]
		var all_base: int = mini(x, n1)
		var all_head: int = mini(x, n2)
		r["min_p"] = minf(OutcomeStats.fisher_p(all_base, n1, x - all_base, n2),
				OutcomeStats.fisher_p(x - all_head, n1, all_head, n2))
		var change: float = OutcomePower.proportion_change(float(r["_b"][0]) / n1, n1, n2, level,
				power, trials)
		r["mds"] = maxf(100.0 * change, r["threshold"])
		return
	r["min_p"] = OutcomeStats.min_attainable_p(r["_b"], r["_h"])
	if r["min_p"] > level:
		r["mds"] = INF
		return
	var nb: int = r["n_base"]
	var nh: int = r["n_head"]
	if r["never_base"] > 0:
		r["mds_unit"] = "pp never"
		r["mds"] = 100.0 * OutcomePower.proportion_change(float(r["never_base"]) / nb, nb, nh,
				level, power, trials)
		return
	var shift_sd: float = OutcomePower.shift_sd(nb, nh, level, power, trials)
	if is_inf(shift_sd):
		r["mds"] = INF
		return
	r["mds"] = maxf(shift_sd * OutcomeStats.robust_sd(r["_b"]), r["threshold"])


## A median, shift or threshold for a report cell: "never" for a NEVER rank (or a median or
## shift that averages one with a tick), "inf" for an undetectable change, otherwise the
## number with up to 3 decimals.
static func cell(value: float) -> String:
	if is_inf(value):
		return "inf"
	if absf(value) >= NEVER / 4.0:
		return "never" if value > 0.0 else "-never"
	return str(snappedf(value, 0.001))
