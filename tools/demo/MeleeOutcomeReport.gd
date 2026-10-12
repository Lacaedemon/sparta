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
	var flagged: Array = rows.filter(func(r: Dictionary) -> bool: return r["flag"])
	var small: Array = rows.filter(func(r: Dictionary) -> bool: return r["significant"] and not r["flag"])
	var runs: Array = []
	for clip in base:
		runs.append(base[clip].size())
	var lines: PackedStringArray = ["### Melee outcome delta", ""]
	if label != "":
		lines.append(label)
		lines.append("")
	lines.append(("%d clips, %s perturbed runs per side. %d metric rows were tested with an "
			+ "exact rank-sum test; Benjamini-Hochberg at alpha %s across all of them, so with no "
			+ "real change the chance of any flag is at most %s. A row is flagged only when its "
			+ "Hodges-Lehmann shift is also at least %s ticks, %s m or %s men.") % [
			base.size(), _range_text(runs), result["tested"], str(cfg["alpha"]), str(cfg["alpha"]),
			str(cfg["min_ticks"]), str(cfg["min_metres"]), str(cfg["min_men"])])
	lines.append("")
	if flagged.is_empty():
		lines.append("**No flagged shifts.** No metric moved by both a significant and a practically large amount.")
	else:
		lines.append("**%d flagged shift(s):**" % flagged.size())
		lines.append("")
		lines.append_array(_table(flagged))
	if not small.is_empty():
		lines.append("")
		lines.append("%d more row(s) are significant but below the practical threshold." % small.size())
	var tested: Array = rows.filter(func(r: Dictionary) -> bool: return r["status"] == "tested")
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
		"| Clip | Metric | Base median | Head median | Shift | p | Runs (base/head) |",
		"|---|---|---|---|---|---|---|",
	]
	for r in rows:
		out.append("| `%s` | `%s` | %s | %s | %s %s | %s | %d/%d |" % [r["clip"], r["metric"],
				_median_cell(r["base"], r["never_base"], r["n_base"]),
				_median_cell(r["head"], r["never_head"], r["n_head"]),
				MeleeOutcomeDelta.cell(r["shift"]), r["unit"], str(snappedf(r["p"], 0.0001)),
				r["n_base"], r["n_head"]])
	return out


static func _median_cell(value: float, never: int, n: int) -> String:
	var text: String = MeleeOutcomeDelta.cell(value)
	return text if never == 0 else "%s (%d/%d never)" % [text, never, n]


static func _range_text(values: Array) -> String:
	if values.is_empty():
		return "0"
	var lo: int = values.min()
	var hi: int = values.max()
	return str(lo) if lo == hi else "%d to %d" % [lo, hi]
