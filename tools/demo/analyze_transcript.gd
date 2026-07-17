extends SceneTree
## Headless CLI entry for DemoDefects: analyze a directory of FULL state-dump snapshots
## (state_*.json, from SPARTA_DEMO_STATE_FULL=1) and print per-unit defect verdicts.
##
##   godot --headless --path . -s tools/demo/analyze_transcript.gd -- <dump-dir> [--json]
##
## Exit code 0 = every verdict passed; 1 = at least one defect; 2 = usage/input error.
## push_error alone can't fail a CI step (it still exits 0 -- see CLAUDE.md), so the
## exit code IS the contract; --json additionally prints the machine-readable verdicts
## for a CI step to attach to a comment.


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: godot --headless -s tools/demo/analyze_transcript.gd -- <dump-dir> [--json]")
		quit(2)
		return
	var dir_path: String = args[0]
	var as_json: bool = args.has("--json")
	var snapshots: Array = _load_snapshots(dir_path)
	if snapshots.is_empty():
		push_error("no state_*.json snapshots found in: " + dir_path)
		quit(2)
		return
	var result: Dictionary = DemoDefects.analyze(snapshots)
	var verdicts: Array = result["verdicts"]
	if verdicts.is_empty():
		# A transcript without soldiers_full/motion_ref (a non-FULL dump) has nothing to
		# verify -- fail loudly rather than passing vacuously.
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
			print("%s uid%d %-20s worst=%.2f threshold=%.2f" % [
					"PASS" if v["pass"] else "FAIL", v["uid"], v["metric"],
					float(v["worst"]), float(v["threshold"])])
		print("%d/%d verdicts passed" % [verdicts.size() - failed, verdicts.size()])
	quit(0 if failed == 0 else 1)


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
