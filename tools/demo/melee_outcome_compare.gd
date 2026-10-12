extends SceneTree
## Headless CLI for the perturbed melee-outcome comparison (MeleeOutcomeDelta). Run by
## tools/ci/melee-outcome-delta.sh; see that script and tools/README.md for the protocol.
##
##   godot --headless --path . -s tools/demo/melee_outcome_compare.gd -- <base-root> \
##       <head-root> [--clips a,b] [--seeds-base 1,2,..] [--seeds-head 1,2,..] [--alpha A] \
##       [--correction bh|by] [--min-effect E] [--floor-ticks T] [--floor-metres M] \
##       [--floor-men N] [--min-runs R] [--metrics <regex>] [--travel 60,150,300] \
##       [--markdown <out.md>] [--label <text>]
##   godot --headless --path . -s tools/demo/melee_outcome_compare.gd -- --extract <run-dir> \
##       [--travel 60,150,300] [--end <tick>]
##
## Each root holds <clip>/seed<k>/: one directory per clip, one subdirectory per perturbed
## run. --clips names the clip directories to load, and --seeds-base and --seeds-head the
## runs on each side; every other directory is ignored, so runs left in the out-dir by an
## earlier comparison with other clips or seeds never join this one, and a named run that
## is missing fails the comparison. Without them every directory is loaded. The other options are
## MeleeOutcomeDelta.DEFAULTS' tunables.
##
## Every metric row is printed as a tab-separated MELEE line: clip, metric, runs per side,
## base and head medians, shift, threshold, p, smallest attainable p, minimum detectable
## shift, status, flag. --markdown also writes a summary to paste into a PR.
##
## Parsing a run's snapshots is the slow part, so --extract writes that run's metrics to
## <run-dir>/metrics.json once, and the comparison reads a metrics.json made with the same
## --travel offsets instead of the snapshots. --end is the clip's last covered tick, which
## tells a complete run from a cut-off one (MeleeOutcomes); a run read straight from its
## snapshots is taken as complete. The delta script extracts each run in its parallel
## pool, right after the dump.
##
## Exit code: 0 = nothing flagged (or extracted), 1 = at least one flagged shift, 2 = usage
## or input error (a root or run with no readable data). push_error alone exits 0, so the
## exit code is the contract.

const OPTIONS := {
	"--alpha": "alpha", "--min-effect": "min_effect", "--floor-ticks": "floor_ticks",
	"--floor-metres": "floor_metres", "--floor-men": "floor_men", "--min-runs": "min_runs",
}
const METRICS_FILE := "metrics.json"

## The first run directory that could not be read, so the caller fails instead of silently
## dropping it: a named run that is missing, or a metrics.json made with other travel
## offsets beside no snapshots to re-extract from.
var _bad_run: String = ""


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		_fail("usage: melee_outcome_compare.gd -- <base-root> <head-root> [options]")
		return
	var config: Dictionary = {}
	var travel: Array = MeleeOutcomes.DEFAULT_TRAVEL_OFFSETS
	var seeds: Dictionary = {"--seeds-base": [], "--seeds-head": []}
	var markdown: String = ""
	var label: String = ""
	var end_tick: int = -1
	var clips: Array = []
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
		elif flag == "--travel" or seeds.has(flag):
			var ticks: Array = DemoFrames.parse_ticks(value)
			if ticks.is_empty():
				_fail("%s needs a comma-separated list of integers, got '%s'" % [flag, value])
				return
			if flag == "--travel":
				travel = ticks
			else:
				seeds[flag] = ticks
		elif flag == "--clips":
			clips = Array(value.split(",", false))
		elif flag == "--correction":
			if value != "bh" and value != "by":
				_fail("--correction must be bh or by, got '%s'" % value)
				return
			config["correction"] = value
		elif flag == "--metrics":
			if value != "" and not RegEx.create_from_string(value).is_valid():
				_fail("--metrics is not a valid regular expression: '%s'" % value)
				return
			config["metrics"] = value
		elif flag == "--end":
			if not value.is_valid_int() or value.to_int() < 0:
				_fail("--end must be a tick, got '%s'" % value)
				return
			end_tick = value.to_int()
		elif flag == "--markdown":
			markdown = value
		elif flag == "--label":
			label = value
		else:
			_fail("unknown option %s" % flag)
			return
		i += 2
	if extract:
		_extract(args[1], travel, end_tick)
		return
	var base: Dictionary = _load_root(args[0], travel, seeds["--seeds-base"], clips)
	var head: Dictionary = _load_root(args[1], travel, seeds["--seeds-head"], clips)
	if _bad_run != "":
		_fail("cannot read run %s (missing, or metrics for other --travel offsets with no snapshots left)" % _bad_run)
		return
	if base.is_empty() or head.is_empty():
		_fail("no clip runs under %s" % (args[0] if base.is_empty() else args[1]))
		return
	var result: Dictionary = MeleeOutcomeDelta.compare(base, head, config)
	var flagged: int = 0
	for r in result["rows"]:
		if r["flag"]:
			flagged += 1
		print("\t".join(PackedStringArray(["MELEE", r["clip"], r["metric"], str(r["n_base"]),
				str(r["n_head"]), MeleeOutcomeDelta.cell(r["base"]),
				MeleeOutcomeDelta.cell(r["head"]), MeleeOutcomeDelta.cell(r["shift"]),
				MeleeOutcomeDelta.cell(r["threshold"]), str(r["p"]), str(r["min_p"]),
				"n/a" if r["mds"] < 0.0 else MeleeOutcomeDelta.cell(r["mds"]), r["status"],
				"FLAG" if r["flag"] else "-"])))
	print("MELEE-SUMMARY\tclips=%d\ttested=%d\tflagged=%d\tlevel=%s" % [base.keys().filter(
			func(c) -> bool: return head.has(c)).size(), result["tested"], flagged,
			str(result["level"])])
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
func _extract(dir: String, travel: Array, end_tick: int) -> void:
	var snaps: Array = _snapshots(dir)
	if snaps.is_empty():
		_fail("no state_*.json snapshots in %s" % dir)
		return
	var f: FileAccess = FileAccess.open(dir.path_join(METRICS_FILE), FileAccess.WRITE)
	if f == null:
		_fail("could not write %s" % dir.path_join(METRICS_FILE))
		return
	var metrics: Dictionary = MeleeOutcomes.extract(snaps, travel, end_tick)
	f.store_string(JSON.stringify({"travel": travel, "metrics": metrics}, "", true, true))
	f.close()
	quit(0)


## clip -> Array of per-run MeleeOutcomes dictionaries for every clip directory under
## `root` named in `clips` (every one when empty): the runs seed<k> for each k in `seeds`,
## or every run directory when `seeds` is empty.
func _load_root(root: String, travel: Array, seeds: Array, clips: Array) -> Dictionary:
	var out: Dictionary = {}
	for clip in DirAccess.get_directories_at(root):
		if not clips.is_empty() and not clips.has(clip):
			continue
		var clip_dir: String = root.path_join(clip)
		var names: Array = Array(DirAccess.get_directories_at(clip_dir))
		if not seeds.is_empty():
			names = seeds.map(func(k: int) -> String: return "seed%d" % k)
		var runs: Array = []
		for run in names:
			var metrics = _run_metrics(clip_dir.path_join(run), travel)
			if metrics == null:
				if not seeds.is_empty() and _bad_run == "":
					_bad_run = clip_dir.path_join(run)
				continue
			runs.append(metrics)
		if not runs.is_empty():
			out[clip] = runs
	return out


## One run's metrics: its metrics.json when that was made with the same travel offsets,
## otherwise extracted from its snapshots. null when the run has neither; a metrics.json
## made with other offsets and no snapshots left also marks the run bad.
func _run_metrics(dir: String, travel: Array):
	var path: String = dir.path_join(METRICS_FILE)
	var cached = null
	if FileAccess.file_exists(path):
		cached = JSON.parse_string(FileAccess.get_file_as_string(path))
	if cached is Dictionary and cached.get("travel", []).map(func(t) -> int: return int(t)) == travel:
		return cached["metrics"]
	var snaps: Array = _snapshots(dir)
	if snaps.is_empty():
		if cached != null and _bad_run == "":
			_bad_run = dir
		return null
	return MeleeOutcomes.extract(snaps, travel)


func _snapshots(dir: String) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for fname in DirAccess.get_files_at(dir):
		if not (fname.begins_with("state_") and fname.ends_with(".json")):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(fname)))
		if parsed is Dictionary and parsed.has("units"):
			out.append(parsed)
	return out
