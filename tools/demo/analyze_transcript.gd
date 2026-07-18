extends SceneTree
## Headless CLI entry for DemoDefects: analyze a directory of FULL state-dump snapshots
## (state_*.json, from SPARTA_DEMO_STATE_FULL=1) and print per-unit defect verdicts.
##
##   godot --headless --path . -s tools/demo/analyze_transcript.gd -- <dump-dir> [--json] \
##       [--expect <input-script.json>]
##   godot --headless --path . -s tools/demo/analyze_transcript.gd -- <dump-dir> \
##       --compare-hashes <other-dump-dir>
##
## --expect additionally evaluates the input script's declared `expect` list (intent as
## data: {tick, uid, field, value}) against the same snapshots -- see DemoDefects.
## --compare-hashes is its own mode: instead of defect analysis, compare the two dump
## runs' per-tick hash streams (hash_stream.jsonl, written by every armed dump run --
## see DemoStateHash / DemoHashStream) and report the FIRST divergent tick and tier, replacing an
## eyeball diff of the full field-level dumps when asking "when did two runs of this
## clip diverge."
## Exit code 0 = every verdict passed (or streams identical); 1 = at least one defect
## (or a divergence); 2 = usage/input error.
## push_error alone can't fail a CI step (it still exits 0 -- see CLAUDE.md), so the
## exit code IS the contract; --json additionally prints the machine-readable verdicts
## for a CI step to attach to a comment.


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: godot --headless -s tools/demo/analyze_transcript.gd -- <dump-dir> [--json] [--expect <input-script.json>] [--compare-hashes <other-dump-dir>]")
		quit(2)
		return
	var dir_path: String = args[0]
	var cmp_idx: int = args.find("--compare-hashes")
	if cmp_idx != -1:
		if cmp_idx + 1 >= args.size():
			push_error("--compare-hashes needs the other dump directory to compare against")
			quit(2)
			return
		_compare_hashes(dir_path, args[cmp_idx + 1])
		return
	var as_json: bool = args.has("--json")
	var expects: Array = []
	var expect_idx: int = args.find("--expect")
	if expect_idx != -1:
		if expect_idx + 1 >= args.size():
			push_error("--expect needs the input script path that declares the expectations")
			quit(2)
			return
		var script_text: String = FileAccess.get_file_as_string(args[expect_idx + 1])
		var parsed_script = JSON.parse_string(script_text)
		if not (parsed_script is Dictionary) or not (parsed_script.get("expect") is Array) \
				or (parsed_script["expect"] as Array).is_empty():
			push_error("no usable `expect` array in: " + args[expect_idx + 1])
			quit(2)
			return
		expects = parsed_script["expect"]
		# Shape-validate every entry up front: a malformed expectation (a [480] range
		# missing its upper bound, a missing field) is a usage error under this tool's
		# own exit-code contract, not a demo defect.
		for e in expects:
			var shape_error: String = DemoDefects.expect_entry_error(e)
			if shape_error != "":
				push_error("malformed expect entry (%s): %s" % [shape_error, str(e)])
				quit(2)
				return
	var snapshots: Array = _load_snapshots(dir_path)
	if snapshots.is_empty():
		push_error("no state_*.json snapshots found in: " + dir_path)
		quit(2)
		return
	var result: Dictionary = DemoDefects.analyze(snapshots)
	var verdicts: Array = result["verdicts"]
	verdicts.append_array(DemoDefects.check_expectations(expects, snapshots))
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
			print("%s uid%d %-20s worst=%s threshold=%s" % [
					"PASS" if v["pass"] else "FAIL", v["uid"], v["metric"],
					str(v["worst"]), str(v["threshold"])])
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
