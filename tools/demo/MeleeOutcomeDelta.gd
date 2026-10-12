class_name MeleeOutcomeDelta
## The comparison behind tools/ci/melee-outcome-delta.sh: given each side's per-run
## MeleeOutcomes metrics for every clip, test each metric's base and head distributions
## and decide which shifts to flag. Pure apart from OutcomeStats' cache, so it is
## unit-tested without a battle (test/unit/test_melee_outcome_delta.gd).
##
## A shift is flagged only when it is both significant and large:
##   - significant: the exact two-sided rank-sum p-value (OutcomeStats.rank_sum_p) is
##     rejected by Benjamini-Hochberg (or, with correction "by", Benjamini-Yekutieli) at
##     `alpha` across every row tested in the report. That bounds the expected share of
##     false flags among the flags (the false discovery rate) at alpha. Only when no row has
##     a real change does it also bound the chance of any flag, and BH's bound assumes the
##     rows are independent or positively dependent; BY's holds under any dependence.
##   - large: the Hodges-Lehmann shift is at least the row's threshold, `min_effect` times
##     the row's own run-to-run spread (OutcomeStats.robust_sd of the base runs), and never
##     less than the resolution floor of the metric's unit. A standardized effect criterion,
##     so a noisy row needs a larger shift than a steady one.
##
## Every tested row also reports what it COULD detect: its smallest attainable p-value, and
## its minimum detectable shift, the smallest pure shift of its own base runs that would reach
## the level a single row must reach alone (alpha / m, divided again by the harmonic number
## for BY), with a head sample the size of the base one. A row whose smallest attainable p,
## at its actual sample sizes, is above that level cannot be flagged whatever the change: its
## minimum detectable shift is INF, and its silence says nothing.
##
## An event that never happened in a complete run ranks above every tick, so a change in
## how often it happens is tested along with when. An unobserved value (null) is dropped.

## Rank value standing for "never happened in this run".
const NEVER := 1.0e12

## Defaults for every tunable; each can be overridden through `config`.
##   alpha        false discovery rate
##   correction   "bh" (Benjamini-Hochberg) or "by" (Benjamini-Yekutieli)
##   min_effect   threshold as a multiple of the row's run-to-run spread
##   floor_*      smallest threshold per unit: the snapshot cadence for ticks, and the
##                resolution of the other measurements
##   min_runs     fewest runs per side for a row to be tested
##   metrics      a regular expression a metric key must match to be in the report at all
##                ("" keeps every metric), so a question about a few rows keeps m small
const DEFAULTS := {
	"alpha": 0.05,
	"correction": "bh",
	"min_effect": 0.5,
	"floor_ticks": 5.0,
	"floor_metres": 0.1,
	"floor_men": 1.0,
	"floor_indicator": 0.5,
	"min_runs": 4,
	"metrics": "",
}


## "men", "indicator", "metres" or "ticks": the unit a metric key is measured in.
static func metric_unit(key: String) -> String:
	if key.ends_with("_men"):
		return "men"
	if key.contains("_removed_by_"):
		return "indicator"
	if key.contains("_travel_"):
		return "metres"
	return "ticks"


## The row's threshold: min_effect times the spread of its finite base values, but at
## least the floor for its unit.
static func threshold(key: String, base: Array, config: Dictionary) -> float:
	var cfg: Dictionary = DEFAULTS.merged(config, true)
	var finite: Array = base.filter(func(v) -> bool: return v != NEVER)
	var floor_value: float = float(cfg["floor_" + metric_unit(key)])
	return maxf(floor_value, float(cfg["min_effect"]) * OutcomeStats.robust_sd(finite))


## One side's sample of `key` over `runs` (MeleeOutcomes dictionaries): "never" becomes
## NEVER, and a run without the key or with a null (unobserved) value adds nothing.
static func sample(runs: Array, key: String) -> Array:
	var out: Array = []
	for run in runs:
		var v = run.get(key)
		if v == null:
			continue
		out.append(NEVER if str(v) == MeleeOutcomes.NEVER else float(v))
	return out


## The p-value level one row must reach to be flagged on its own among `m` tested rows.
static func single_row_level(m: int, config: Dictionary) -> float:
	var cfg: Dictionary = DEFAULTS.merged(config, true)
	var level: float = float(cfg["alpha"]) / float(maxi(m, 1))
	if str(cfg["correction"]) == "by":
		level /= OutcomeStats.harmonic(m)
	return level


## Compare every clip. `base` and `head` map clip name -> Array of per-run metric
## dictionaries. Returns {"rows": [...], "tested": int, "level": float} where each row is
## {clip, metric, unit, n_base, n_head, base, head, shift, threshold, p, min_p, mds,
## status, significant, flag}; status is "tested", "identical" or "too few runs", and only
## tested rows carry p, min_p and mds (-1 for a censored row, INF when undetectable).
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
			rows.append(_row(clip, key, sample(base[clip], key), sample(head[clip], key), cfg))
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
		r["min_p"] = OutcomeStats.min_attainable_p(r["_b"], r["_h"])
		if r["never_base"] > 0:
			r["mds"] = -1.0
		elif r["min_p"] > level:
			r["mds"] = INF
		else:
			r["mds"] = OutcomeStats.min_detectable_shift(r["_b"], level)
	for r in rows:
		r.erase("_b")
		r.erase("_h")
	return {"rows": rows, "tested": tested.size(), "level": level}


static func _row(clip: String, key: String, b: Array, h: Array, cfg: Dictionary) -> Dictionary:
	var row: Dictionary = {
		"clip": clip, "metric": key, "unit": metric_unit(key),
		"n_base": b.size(), "n_head": h.size(),
		"base": OutcomeStats.median(b), "head": OutcomeStats.median(h),
		"never_base": b.count(NEVER), "never_head": h.count(NEVER),
		"shift": OutcomeStats.hodges_lehmann(b, h), "threshold": threshold(key, b, cfg),
		"p": 1.0, "min_p": 1.0, "mds": -1.0, "status": "tested", "significant": false,
		"flag": false, "_b": b, "_h": h,
	}
	var min_runs: int = maxi(1, int(cfg["min_runs"]))
	if b.size() < min_runs or h.size() < min_runs:
		row["status"] = "too few runs"
	elif (b + h).all(func(v) -> bool: return v == b[0]):
		row["status"] = "identical"
	else:
		row["p"] = OutcomeStats.rank_sum_p(b, h)
	return row


## A median, shift or threshold for a report cell: "never" for a NEVER rank, "inf" for an
## undetectable shift, otherwise the number with up to 3 decimals.
static func cell(value: float) -> String:
	if is_inf(value):
		return "inf"
	if absf(value) >= NEVER / 2.0:
		return "never" if value > 0.0 else "-never"
	return str(snappedf(value, 0.001))
