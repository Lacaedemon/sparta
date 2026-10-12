class_name MeleeOutcomeReport
## The PR-ready markdown summary of a MeleeOutcomeDelta comparison. Pure: a function of
## the comparison result and the settings it ran with.

## How many of the smallest p-values the collapsed detail table lists.
const DETAIL_ROWS := 15


## The summary. `result` is MeleeOutcomeDelta.compare's return, `config` the settings it
## ran with, `base` the base side's clip -> runs map (for run counts), `label` an optional
## line naming the two trees.
static func markdown(result: Dictionary, config: Dictionary, base: Dictionary,
		label: String = "") -> String:
	var cfg: Dictionary = MeleeOutcomeDelta.DEFAULTS.merged(config, true)
	var rows: Array = result["rows"]
	var tested: Array = rows.filter(func(r: Dictionary) -> bool: return r["status"] == "tested")
	var flagged: Array = rows.filter(func(r: Dictionary) -> bool: return r["flag"])
	var small: Array = rows.filter(func(r: Dictionary) -> bool: return r["significant"] and not r["flag"])
	var blind: Array = tested.filter(func(r: Dictionary) -> bool: return r["min_p"] > result["level"])
	var runs: Array = []
	for clip in base:
		runs.append(base[clip].size())
	var method: String = "Benjamini-Yekutieli" if str(cfg["correction"]) == "by" else "Benjamini-Hochberg"
	var lines: PackedStringArray = ["### Melee outcome delta", ""]
	if label != "":
		lines.append(label)
		lines.append("")
	lines.append(("%d clips, %s perturbed runs per side, %d rows tested with an exact rank-sum "
			+ "test. %s at %s bounds the expected share of false flags among the flags (the false "
			+ "discovery rate) at %s%s. A row is flagged only when its Hodges-Lehmann shift is also "
			+ "at least its threshold: %s times its own run-to-run spread, and never under the "
			+ "measurement floor.") % [
			base.size(), _range_text(runs), result["tested"], method, str(cfg["alpha"]),
			str(cfg["alpha"]),
			"" if str(cfg["correction"]) == "by" else " for independent or positively dependent rows",
			str(cfg["min_effect"])])
	lines.append("")
	lines.append(("**No flag is not evidence of no effect.** One row must reach p <= %s to be flagged "
			+ "alone. %d of %d tested rows cannot reach it with any change; the MDS column gives each "
			+ "row's smallest detectable pure shift.") % [
			str(snappedf(result["level"], 0.000001)), blind.size(), tested.size()])
	lines.append("")
	if flagged.is_empty():
		lines.append("**No flagged shifts.**")
	else:
		lines.append("**%d flagged shift(s):**" % flagged.size())
		lines.append("")
		lines.append_array(_table(flagged))
	if not small.is_empty():
		lines.append("")
		lines.append("%d more row(s) are significant but below their threshold." % small.size())
	tested.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["p"] < y["p"])
	if not tested.is_empty():
		lines.append("")
		lines.append("<details><summary>Smallest p-values</summary>")
		lines.append("")
		lines.append_array(_table(tested.slice(0, DETAIL_ROWS)))
		lines.append("")
		lines.append("</details>")
	lines.append("")
	return "\n".join(lines)


static func _table(rows: Array) -> PackedStringArray:
	var out: PackedStringArray = [
		"| Clip | Metric | Base median | Head median | Shift | Threshold | MDS | p | Runs (base/head) |",
		"|---|---|---|---|---|---|---|---|---|",
	]
	for r in rows:
		out.append("| `%s` | `%s` | %s | %s | %s %s | %s | %s | %s | %d/%d |" % [r["clip"], r["metric"],
				_median_cell(r["base"], r["never_base"], r["n_base"]),
				_median_cell(r["head"], r["never_head"], r["n_head"]),
				MeleeOutcomeDelta.cell(r["shift"]), r["unit"],
				MeleeOutcomeDelta.cell(r["threshold"]),
				"n/a" if r["mds"] < 0.0 else MeleeOutcomeDelta.cell(r["mds"]),
				_p_cell(r["p"]), r["n_base"], r["n_head"]])
	return out


## A p-value with 4 decimals, or 2 significant digits in exponent form below 0.0001.
static func _p_cell(p: float) -> String:
	if p >= 0.0001:
		return str(snappedf(p, 0.0001))
	if p <= 0.0:
		return "0"
	var exponent: int = floori(log(p) / log(10.0))
	return "%.1fe%d" % [p / pow(10.0, exponent), exponent]


static func _median_cell(value: float, never: int, n: int) -> String:
	var text: String = MeleeOutcomeDelta.cell(value)
	return text if never == 0 else "%s (%d/%d never)" % [text, never, n]


static func _range_text(values: Array) -> String:
	if values.is_empty():
		return "0"
	var lo: int = values.min()
	var hi: int = values.max()
	return str(lo) if lo == hi else "%d to %d" % [lo, hi]
