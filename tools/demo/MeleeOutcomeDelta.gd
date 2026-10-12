class_name MeleeOutcomeDelta
## The comparison behind tools/ci/melee-outcome-delta.sh: given each side's per-run
## MeleeOutcomes metrics for every clip, test each metric's base and head distributions
## and decide which shifts to flag. Pure: reads only its arguments, so it is unit-tested
## without a battle (test/unit/test_melee_outcome_delta.gd).
##
## A shift is flagged only when it is both significant and large:
##   - significant: the exact two-sided rank-sum p-value (OutcomeStats.rank_sum_p) survives
##     Benjamini-Hochberg at `alpha` across every metric tested in the whole report, so
##     with no real change anywhere the chance of any flag is at most `alpha`;
##   - large: the Hodges-Lehmann shift is at least the practical threshold for the metric's
##     unit (ticks, metres or men).
## An event that never happened in a run (no break, never got clear) ranks above every
## tick, so a change in how OFTEN it happens is tested along with when.

## Rank value standing for "never happened in this run".
const NEVER := 1.0e12

## Defaults for every tunable; each can be overridden through `config`.
const DEFAULTS := {
	"alpha": 0.05,
	"min_ticks": 30.0,
	"min_metres": 3.0,
	"min_men": 2.0,
	"min_runs": 4,
}


## "men", "metres" or "ticks": the unit a metric key is measured in.
static func metric_unit(key: String) -> String:
	if key.ends_with("_men"):
		return "men"
	if key.contains("_travel_"):
		return "metres"
	return "ticks"


## The practical threshold for `key` under `config` (DEFAULTS filled in).
static func threshold(key: String, config: Dictionary) -> float:
	var cfg: Dictionary = DEFAULTS.merged(config, true)
	match metric_unit(key):
		"men":
			return float(cfg["min_men"])
		"metres":
			return float(cfg["min_metres"])
	return float(cfg["min_ticks"])


## One side's sample of `key` over `runs` (MeleeOutcomes dictionaries). A run without the
## key (a unit that never broke has no contact-break metric) adds nothing; a null tick adds
## NEVER; a null travel (a stream cut off before its tick) adds nothing.
static func sample(runs: Array, key: String) -> Array:
	var out: Array = []
	for run in runs:
		if not run.has(key):
			continue
		var v = run[key]
		if v == null:
			if metric_unit(key) == "ticks":
				out.append(NEVER)
			continue
		out.append(float(v))
	return out


## Compare every clip. `base` and `head` map clip name -> Array of per-run metric
## dictionaries. Returns {"rows": [...], "tested": int} where each row is
## {clip, metric, unit, n_base, n_head, base, head, shift, p, status, flag}; status is
## "tested", "identical" or "too few runs", and only tested rows carry a p-value.
static func compare(base: Dictionary, head: Dictionary, config: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = DEFAULTS.merged(config, true)
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
			rows.append(_row(clip, key, sample(base[clip], key), sample(head[clip], key), cfg))
	var tested: Array = rows.filter(func(r: Dictionary) -> bool: return r["status"] == "tested")
	var rejected: Array = OutcomeStats.benjamini_hochberg(
			tested.map(func(r: Dictionary) -> float: return r["p"]), float(cfg["alpha"]))
	for i in range(tested.size()):
		var r: Dictionary = tested[i]
		r["significant"] = rejected[i]
		r["flag"] = rejected[i] and absf(r["shift"]) >= threshold(r["metric"], cfg)
	return {"rows": rows, "tested": tested.size()}


static func _row(clip: String, key: String, b: Array, h: Array, cfg: Dictionary) -> Dictionary:
	var row: Dictionary = {
		"clip": clip, "metric": key, "unit": metric_unit(key),
		"n_base": b.size(), "n_head": h.size(),
		"base": OutcomeStats.median(b), "head": OutcomeStats.median(h),
		"never_base": b.count(NEVER), "never_head": h.count(NEVER),
		"shift": OutcomeStats.hodges_lehmann(b, h),
		"p": 1.0, "status": "tested", "significant": false, "flag": false,
	}
	var min_runs: int = maxi(1, int(cfg["min_runs"]))
	if b.size() < min_runs or h.size() < min_runs:
		row["status"] = "too few runs"
	elif (b + h).all(func(v) -> bool: return v == b[0]):
		row["status"] = "identical"
	else:
		row["p"] = OutcomeStats.rank_sum_p(b, h)
	return row


## A median or shift for a report cell: "never" for a NEVER rank, otherwise the number
## with up to 3 decimals.
static func cell(value: float) -> String:
	if absf(value) >= NEVER / 2.0:
		return "never" if value > 0.0 else "-never"
	return str(snappedf(value, 0.001))
