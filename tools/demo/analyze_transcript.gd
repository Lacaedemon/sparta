extends SceneTree
## Headless CLI entry for DemoDefects: analyze a directory of FULL state-dump snapshots
## (state_*.json, from SPARTA_DEMO_STATE_FULL=1) and print per-unit defect verdicts.
##
##   godot --headless --path . -s tools/demo/analyze_transcript.gd -- <dump-dir> [--json] \
##       [--script <input-script.json>]
##   godot --headless --path . -s tools/demo/analyze_transcript.gd -- <dump-dir> \
##       --compare-hashes <other-dump-dir>
##   godot --headless --path . -s tools/demo/analyze_transcript.gd -- <base-tree> \
##       --compare-hash-trees <pr-tree>
##
## --script points at the clip's own input script and reads two optional declarations from
## it: the `expect` list (intent as data: {tick, uid, field, value}), evaluated against the
## same snapshots, and `defect_exemptions` (metric -> {uids, reason}), which forgives that
## metric for the units it names and prints them as EXEMPT instead of FAIL. An exemption
## must name its units and state its reason; one whose named unit now passes anyway prints
## as STALE so it gets removed. Either declaration may be absent, but a present one of the
## wrong shape exits 3 and gates, rather than skipping the scan behind a green check.
## --expect is an alias for the same flag.
## --compare-hashes is its own mode: instead of defect analysis, compare the two dump
## runs' per-tick hash streams (hash_stream.jsonl, written by every armed dump run --
## see DemoStateHash / DemoHashStream) and report the FIRST divergent tick and tier, replacing an
## eyeball diff of the full field-level dumps when asking "when did two runs of this
## clip diverge."
## --compare-hash-trees is the whole-catalog counterpart: each argument is a TREE of
## per-clip transcript subdirectories (website/tools/dump-demo-states.sh output), and it
## prints one `HASHCMP<TAB>...` line per clip classifying it SAME / CHANGED / ADDED /
## REMOVED / UNKNOWN from the hash streams alone. This is website-demo-diff.yml's fast
## pre-filter: the cheap hash compare says which clips changed (and the exact first
## divergent tick + tier) so the expensive field-level jq analysis runs only for those.
## Exit code 0 = every verdict passed (or streams identical, or the tree compare ran);
## 1 = at least one defect (or a divergence); 2 = usage/input error; 3 = the demo script
## itself declares something malformed.
##
## 2 and 3 are deliberately distinct. 2 means the data to judge is absent (no snapshots, a
## failed dump) -- there is nothing to gate on, so callers warn and move on. 3 means a
## script the author wrote is wrong, and the scan therefore judged NOTHING for that clip;
## folding that into 2 would let a single typo in a `defect_exemptions` block silently
## disable every metric for the clip behind a green check. Callers gate on 3.
## push_error alone can't fail a CI step (it still exits 0 -- see CLAUDE.md), so the
## exit code IS the contract; --json additionally prints the machine-readable verdicts
## for a CI step to attach to a comment.


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: godot --headless -s tools/demo/analyze_transcript.gd -- <dump-dir> [--json] [--script <input-script.json>] [--compare-hashes <other-dump-dir>] [--compare-hash-trees <pr-tree>]")
		quit(2)
		return
	var dir_path: String = args[0]
	var tree_idx: int = args.find("--compare-hash-trees")
	if tree_idx != -1:
		if tree_idx + 1 >= args.size():
			push_error("--compare-hash-trees needs the PR transcript tree to compare against")
			quit(2)
			return
		_compare_hash_trees(dir_path, args[tree_idx + 1])
		return
	var cmp_idx: int = args.find("--compare-hashes")
	if cmp_idx != -1:
		if cmp_idx + 1 >= args.size():
			push_error("--compare-hashes needs the other dump directory to compare against")
			quit(2)
			return
		_compare_hashes(dir_path, args[cmp_idx + 1])
		return
	var as_json: bool = args.has("--json")
	# One flag carries the demo script, which declares both the `expect` intent list and
	# any `defect_exemptions`; either may be absent. (Callers used to pass --expect only
	# when a script had expectations, which left exemptions unreachable for every script
	# without them. --expect stays accepted as an alias.)
	var expects: Array = []
	var exemptions: Dictionary = {}
	var script_idx: int = args.find("--script")
	if script_idx == -1:
		script_idx = args.find("--expect")
	if script_idx != -1:
		if script_idx + 1 >= args.size():
			push_error("--script needs the input script path declaring expectations/exemptions")
			quit(2)
			return
		var script_path: String = args[script_idx + 1]
		var parsed_script = JSON.parse_string(FileAccess.get_file_as_string(script_path))
		if not (parsed_script is Dictionary):
			push_error("not a readable demo script: " + script_path)
			quit(2)
			return
		# Absent is fine; present-but-wrong-shape is an authoring error, and it exits 3 so
		# callers gate on it. Silence here would be the worst outcome available: the scan
		# returns before computing a single metric, so a stray typo in one declaration
		# would disable every check for the clip while the run still looked healthy.
		var declared = parsed_script.get("expect")
		if declared != null and not (declared is Array):
			push_error("`expect` must be an array in: " + script_path)
			quit(3)
			return
		var declared_exempt = parsed_script.get("defect_exemptions")
		if declared_exempt != null and not (declared_exempt is Dictionary):
			push_error("`defect_exemptions` must be an object in: " + script_path)
			quit(3)
			return
		if declared is Array:
			expects = declared
			# Shape-validate every entry up front: a malformed expectation (a [480] range
			# missing its upper bound, a missing field) is an authoring error under this
			# tool's own exit-code contract, not a demo defect -- so it exits 3 and gates,
			# because nothing after this point gets judged.
			for e in expects:
				var shape_error: String = DemoDefects.expect_entry_error(e)
				if shape_error != "":
					push_error("malformed expect entry (%s): %s" % [shape_error, str(e)])
					quit(3)
					return
		if declared_exempt is Dictionary:
			for metric in declared_exempt:
				var ex_error: String = DemoDefects.exemption_error(metric, declared_exempt[metric])
				if ex_error != "":
					push_error("bad defect_exemptions entry: " + ex_error)
					quit(3)
					return
			exemptions = declared_exempt
	var snapshots: Array = _load_snapshots(dir_path)
	if snapshots.is_empty():
		push_error("no state_*.json snapshots found in: " + dir_path)
		quit(2)
		return
	var result: Dictionary = DemoDefects.analyze(snapshots)
	var verdicts: Array = result["verdicts"]
	verdicts.append_array(DemoDefects.check_expectations(expects, snapshots))
	verdicts = DemoDefects.apply_exemptions(verdicts, exemptions)
	if verdicts.is_empty():
		# A transcript without soldiers_full/motion_ref (a non-FULL dump) has nothing to
		# verify -- fail loudly rather than passing vacuously. (Declared expectations
		# alone are enough: those check the compact fields every dump carries.)
		push_error("no analyzable units: the dump lacks soldiers_full/motion_ref (run with SPARTA_DEMO_STATE_FULL=1)")
		quit(2)
		return
	var failed := 0
	for v in verdicts:
		if not v["pass"]:
			failed += 1
	if as_json:
		print(JSON.stringify({"failed": failed, "verdicts": verdicts}))
	else:
		for v in verdicts:
			# worst/threshold are numbers for the defect metrics but can be strings for
			# expectation verdicts (an actual field value, or a no-data note) -- print
			# them as-is rather than forcing floats.
			# An exemption never hides: it prints in place of the verdict, with the reason
			# the script had to state to claim it. STALE marks one the clip has outgrown.
			var label: String = "PASS" if v["pass"] else "FAIL"
			if v.has("exempt"):
				label = "STALE" if bool(v.get("stale_exempt", false)) else "EXEMPT"
			print("%s uid%d %-20s worst=%s threshold=%s%s" % [
					label, v["uid"], v["metric"],
					str(v["worst"]), str(v["threshold"]),
					("  <- " + str(v["exempt"])) if v.has("exempt") else ""])
		print("%d/%d verdicts passed" % [verdicts.size() - failed, verdicts.size()])
	quit(0 if failed == 0 else 1)


## Compare two dump runs' hash streams and report the first divergent tick (see
## DemoHashStream.compare_streams for the tick-matching and tier semantics). Exit 0 =
## the common tick range is hash-identical, 1 = a divergence, 2 = a stream is
## missing/empty.
func _compare_hashes(dir_a: String, dir_b: String) -> void:
	var streams: Array = []
	for d in [dir_a, dir_b]:
		var path: String = String(d).path_join("hash_stream.jsonl")
		var stream: Array = DemoHashStream.parse_stream(FileAccess.get_file_as_string(path))
		if stream.is_empty():
			push_error("no usable hash stream at: " + path)
			quit(2)
			return
		streams.append(stream)
	var verdict: Dictionary = DemoHashStream.compare_streams(streams[0], streams[1])
	if verdict["divergent"]:
		print("DIVERGENT tick=%d tier=%s (%d common ticks compared)"
				% [verdict["tick"], verdict["tier"], verdict["compared"]])
		quit(1)
		return
	print("IDENTICAL over %d common ticks (%d only in first stream, %d only in second)"
			% [verdict["compared"], verdict["only_a"], verdict["only_b"]])
	quit(0)


## Whole-catalog hash pre-filter: compare every clip's hash stream between the two transcript
## trees and print one machine-readable line per clip. The verdict is in the lines (a
## `HASHCMP`-prefixed TSV, robust against Godot's own banner noise on stdout), not the exit
## code, so this always quits 0 -- website-demo-state-diff.sh consumes the lines to decide
## which clips need the expensive field-level jq. Per clip:
##   HASHCMP<TAB><name><TAB>SAME                     -- hash-identical over the common range
##   HASHCMP<TAB><name><TAB>CHANGED<TAB><tick><TAB><tier>  -- first divergent tick + tier
##   HASHCMP<TAB><name><TAB>ADDED                    -- clip present only in the PR tree
##   HASHCMP<TAB><name><TAB>REMOVED                  -- clip present only in the base tree
##   HASHCMP<TAB><name><TAB>UNKNOWN                  -- a side has no usable hash stream
##                                                      (a tree predating the stream); the
##                                                      caller falls back to a full compare
func _compare_hash_trees(base_dir: String, pr_dir: String) -> void:
	var base_names: Dictionary = _subdir_set(base_dir)
	var pr_names: Dictionary = _subdir_set(pr_dir)
	var all_names: Array = base_names.keys()
	for n in pr_names:
		if not base_names.has(n):
			all_names.append(n)
	all_names.sort()
	for name in all_names:
		var in_base: bool = base_names.has(name)
		var in_pr: bool = pr_names.has(name)
		if in_base and not in_pr:
			print("HASHCMP\t%s\tREMOVED" % name)
			continue
		if in_pr and not in_base:
			print("HASHCMP\t%s\tADDED" % name)
			continue
		var base_stream: Array = DemoHashStream.parse_stream(FileAccess.get_file_as_string(
				String(base_dir).path_join(name).path_join("hash_stream.jsonl")))
		var pr_stream: Array = DemoHashStream.parse_stream(FileAccess.get_file_as_string(
				String(pr_dir).path_join(name).path_join("hash_stream.jsonl")))
		if base_stream.is_empty() or pr_stream.is_empty():
			print("HASHCMP\t%s\tUNKNOWN" % name)
			continue
		var verdict: Dictionary = DemoHashStream.compare_streams(base_stream, pr_stream)
		if verdict["divergent"]:
			print("HASHCMP\t%s\tCHANGED\t%d\t%s" % [name, int(verdict["tick"]), str(verdict["tier"])])
		else:
			print("HASHCMP\t%s\tSAME" % name)
	quit(0)


## The set (Dictionary used as a set) of immediate subdirectory names under `dir`, or empty
## when the directory doesn't exist (a tree that dumped no clips on its side).
func _subdir_set(dir: String) -> Dictionary:
	var out: Dictionary = {}
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out[sub] = true
	return out


func _load_snapshots(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var names: Array = []
	for f in dir.get_files():
		if f.begins_with("state_") and f.ends_with(".json"):
			names.append(f)
	names.sort()
	for f in names:
		var text: String = FileAccess.get_file_as_string(dir_path.path_join(f))
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary and parsed.has("units"):
			out.append(parsed)
	return out
