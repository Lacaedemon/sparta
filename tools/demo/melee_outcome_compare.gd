extends SceneTree
## Headless CLI for the perturbed melee-outcome comparison (MeleeOutcomeDelta). Run by
## tools/ci/melee-outcome-delta.sh; see that script and tools/README.md for the protocol.
##
##   godot --headless --path . -s tools/demo/melee_outcome_compare.gd -- <base-root> \
##       <head-root> [--clips a,b] [--seeds-base 1,2,..] [--seeds-head 1,2,..] [--step S] \
##       [--alpha A] [--correction bh|by] [--min-effect E] [--floor-ticks T] \
##       [--floor-metres M] [--floor-men N] [--min-pp P] [--min-runs R] [--metrics <regex>] \
##       [--travel 60,150,300] [--markdown <out.md>] [--label <text>]
##   godot --headless --path . -s tools/demo/melee_outcome_compare.gd -- --extract <run-dir> \
##       --end <tick> --step <ticks> [--travel 60,150,300]
##
## Each root holds <clip>/seed<k>/ run directories (MeleeRunStore). --clips names the clip
## directories to load, and --seeds-base and --seeds-head the runs on each side; every other
## directory is ignored, so runs left in the out-dir by an earlier comparison with other
## clips or seeds never join this one, and a named run that is missing fails the comparison.
## --step refuses runs extracted at another snapshot cadence. The other options are
## MeleeOutcomeDelta.DEFAULTS' tunables.
##
## Every metric row is printed as a tab-separated MELEE line: clip, metric, runs per side,
## base and head, shift, threshold, p, smallest attainable p, minimum detectable change and
## its unit, unobserved runs per side, status, flag. --markdown also writes a summary to
## paste into a PR.
##
## --extract writes one run's metrics.json; --end is the last snapshot tick the delta script
## scheduled for it, which tells a complete run from a cut-off one (MeleeOutcomes).
##
## Exit code: 0 = nothing flagged (or extracted), 1 = at least one flagged shift, 2 = usage
## or input error. push_error alone exits 0, so the exit code is the contract.

const OPTIONS := {
	"--alpha": "alpha", "--min-effect": "min_effect", "--floor-ticks": "floor_ticks",
	"--floor-metres": "floor_metres", "--floor-men": "floor_men", "--min-pp": "min_pp",
	"--min-runs": "min_runs",
}
const INT_OPTIONS := ["--end", "--step"]


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		_fail("usage: melee_outcome_compare.gd -- <base-root> <head-root> [options]")
		return
	var config: Dictionary = {}
	var travel: Array = MeleeOutcomes.DEFAULT_TRAVEL_OFFSETS
	var seeds: Dictionary = {"--seeds-base": [], "--seeds-head": []}
	var ints: Dictionary = {"--end": -1, "--step": -1}
	var markdown: String = ""
	var label: String = ""
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
		elif INT_OPTIONS.has(flag):
			if not value.is_valid_int() or value.to_int() < 0:
				_fail("%s must be a non-negative integer, got '%s'" % [flag, value])
				return
			ints[flag] = value.to_int()
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
		elif flag == "--markdown":
			markdown = value
		elif flag == "--label":
			label = value
		else:
			_fail("unknown option %s" % flag)
			return
		i += 2
	if extract:
		if ints["--end"] < 0 or ints["--step"] < 0:
			_fail("--extract needs --end and --step")
			return
		var err: String = MeleeRunStore.extract(args[1], travel, ints["--end"], ints["--step"])
		if err != "":
			_fail(err)
			return
		quit(0)
		return
	var loaded_base: Dictionary = MeleeRunStore.load_root(args[0], travel, seeds["--seeds-base"],
			clips, ints["--step"])
	var loaded_head: Dictionary = MeleeRunStore.load_root(args[1], travel, seeds["--seeds-head"],
			clips, ints["--step"])
	for loaded in [loaded_base, loaded_head]:
		if loaded["error"] != "":
			_fail(loaded["error"])
			return
	var base: Dictionary = loaded_base["runs"]
	var head: Dictionary = loaded_head["runs"]
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
				MeleeOutcomeDelta.cell(r["mds"]), r["mds_unit"], str(r["dropped_base"]),
				str(r["dropped_head"]), r["status"], "FLAG" if r["flag"] else "-"])))
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
