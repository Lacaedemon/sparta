extends SceneTree
## Headless CLI for the perturbed melee-outcome comparison (MeleeOutcomeDelta). Run by
## tools/ci/melee-outcome-delta.sh; see that script and tools/README.md for the protocol.
##
##   godot --headless --path . -s tools/demo/melee_outcome_compare.gd -- <base-root> \
##       <head-root> [--alpha A] [--min-ticks T] [--min-metres M] [--min-men N] \
##       [--min-runs R] [--travel 60,150,300] [--markdown <out.md>] [--label <text>]
##   godot --headless --path . -s tools/demo/melee_outcome_compare.gd -- --extract <run-dir> \
##       [--travel 60,150,300]
##
## Each root holds <clip>/<run>/state_*.json: one directory per clip, one subdirectory per
## perturbed run. Every metric row is printed as a tab-separated MELEE line; --markdown also
## writes a summary to paste into a PR.
##
## Parsing a run's snapshots is the slow part, so --extract writes that run's metrics to
## <run-dir>/metrics.json once, and the comparison reads a metrics.json made with the same
## --travel offsets instead of the snapshots. The delta script extracts each run in its
## parallel pool, right after the dump.
##
## Exit code: 0 = nothing flagged (or extracted), 1 = at least one flagged shift, 2 = usage
## or input error (a root or run with no readable snapshots). push_error alone exits 0, so
## the exit code is the contract.

const OPTIONS := {
	"--alpha": "alpha", "--min-ticks": "min_ticks", "--min-metres": "min_metres",
	"--min-men": "min_men", "--min-runs": "min_runs",
}
const METRICS_FILE := "metrics.json"

## A run whose metrics.json used other travel offsets and has no snapshots left.
var _stale_run: String = ""


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		_fail("usage: melee_outcome_compare.gd -- <base-root> <head-root> [options]")
		return
	var config: Dictionary = {}
	var travel: Array = MeleeOutcomes.DEFAULT_TRAVEL_OFFSETS
	var markdown: String = ""
	var label: String = ""
	var extract: bool = args[0] == "--extract"
	var i: int = 2
	while i < args.size():
		var flag: String = args[i]
		if i + 1 >= args.size():
			_fail("%s needs a value" % flag)
			return
		var value: String = args[i + 1]
		if OPTIONS.has(flag):
			if not value.is_valid_float() or float(value) < 0.0:
				_fail("%s must be a non-negative number, got '%s'" % [flag, value])
				return
			config[OPTIONS[flag]] = float(value)
		elif flag == "--travel":
			travel = DemoFrames.parse_ticks(value)
			if travel.is_empty():
				_fail("--travel needs a comma-separated list of tick offsets, got '%s'" % value)
				return
		elif flag == "--markdown":
			markdown = value
		elif flag == "--label":
			label = value
		else:
			_fail("unknown option %s" % flag)
			return
		i += 2
	if extract:
		_extract(args[1], travel)
		return
	var base: Dictionary = _load_root(args[0], travel)
	var head: Dictionary = _load_root(args[1], travel)
	if _stale_run != "":
		_fail("%s holds metrics for other --travel offsets and no snapshots to re-extract; use a fresh out-dir" % _stale_run)
		return
	if base.is_empty() or head.is_empty():
		_fail("no clip runs under %s" % (args[0] if base.is_empty() else args[1]))
		return
	var result: Dictionary = MeleeOutcomeDelta.compare(base, head, config)
	var flagged: int = 0
	for r in result["rows"]:
		if r["flag"]:
			flagged += 1
		print("MELEE\t%s\t%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s" % [r["clip"], r["metric"],
				r["n_base"], r["n_head"], MeleeOutcomeDelta.cell(r["base"]),
				MeleeOutcomeDelta.cell(r["head"]), MeleeOutcomeDelta.cell(r["shift"]),
				str(snappedf(r["p"], 0.000001)), r["status"], "FLAG" if r["flag"] else "-"])
	print("MELEE-SUMMARY\tclips=%d\ttested=%d\tflagged=%d" % [base.keys().filter(
			func(c) -> bool: return head.has(c)).size(), result["tested"], flagged])
	if markdown != "":
		var f: FileAccess = FileAccess.open(markdown, FileAccess.WRITE)
		if f == null:
			_fail("could not write %s" % markdown)
			return
		f.store_string(MeleeOutcomeReport.markdown(result, config, base, label))
		f.close()
	quit(1 if flagged > 0 else 0)


func _fail(message: String) -> void:
	push_error(message)
	quit(2)


## Write `dir`'s metrics to dir/metrics.json, tagged with the travel offsets they used.
func _extract(dir: String, travel: Array) -> void:
	var snaps: Array = _snapshots(dir)
	if snaps.is_empty():
		_fail("no state_*.json snapshots in %s" % dir)
		return
	var f: FileAccess = FileAccess.open(dir.path_join(METRICS_FILE), FileAccess.WRITE)
	if f == null:
		_fail("could not write %s" % dir.path_join(METRICS_FILE))
		return
	f.store_string(JSON.stringify({"travel": travel, "metrics": MeleeOutcomes.extract(snaps, travel)}, "", true, true))
	f.close()
	quit(0)


## clip -> Array of per-run MeleeOutcomes dictionaries, for every clip directory under
## `root` holding at least one run with metrics or snapshots.
func _load_root(root: String, travel: Array) -> Dictionary:
	var out: Dictionary = {}
	for clip in DirAccess.get_directories_at(root):
		var runs: Array = []
		for run in DirAccess.get_directories_at(root.path_join(clip)):
			var metrics = _run_metrics(root.path_join(clip).path_join(run), travel)
			if metrics != null:
				runs.append(metrics)
		if not runs.is_empty():
			out[clip] = runs
	return out


## One run's metrics: its metrics.json when that was made with the same travel offsets,
## otherwise extracted from its snapshots. null when the run has neither. A metrics.json
## made with other offsets, beside no snapshots to re-extract from, is recorded in
## _stale_run so the caller fails instead of silently dropping the run.
func _run_metrics(dir: String, travel: Array):
	var path: String = dir.path_join(METRICS_FILE)
	var cached = null
	if FileAccess.file_exists(path):
		cached = JSON.parse_string(FileAccess.get_file_as_string(path))
	if cached is Dictionary and cached.get("travel", []).map(func(t) -> int: return int(t)) == travel:
		return cached["metrics"]
	var snaps: Array = _snapshots(dir)
	if snaps.is_empty():
		if cached != null:
			_stale_run = dir
		return null
	return MeleeOutcomes.extract(snaps, travel)


func _snapshots(dir: String) -> Array:
	var out: Array = []
	for fname in DirAccess.get_files_at(dir):
		if not (fname.begins_with("state_") and fname.ends_with(".json")):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(fname)))
		if parsed is Dictionary and parsed.has("units"):
			out.append(parsed)
	return out
