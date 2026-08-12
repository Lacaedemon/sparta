extends SceneTree
## Force-compile every .gd in the project and exit non-zero if any fails.
##
## The import pass (`godot --headless --import`) compiles only what the imported
## resources reach: a script nothing references at import time -- a tools/ helper, a
## scene-swapped runner's dependency -- can carry a hard parse error straight past the
## validate gate and only blow up when something finally load()s it at runtime.
## Loading a script forces its compilation, so sweeping load() over every .gd closes
## that gap: a broken script comes back null (Godot prints the SCRIPT ERROR itself),
## and this sweep turns that into a listed failure plus a real non-zero exit code.
##
## Run headlessly after an import (so class_name globals resolve):
##   godot --headless -s tools/ci/compile_all_scripts.gd
##
## Used by `tools/check.sh validate` and CI's "Import & validate project" step.

func _initialize() -> void:
	# Self-test the detector before trusting it: write a deliberately-broken script and
	# confirm compiles() rejects it. If a Godot change ever makes broken scripts load
	# cleanly, the sweep fails LOUDLY here instead of silently passing everything --
	# a green sweep certifies the detector, not just the tree. (This is also why the
	# negative case doesn't live in the GUT suite: the engine prints parse-error
	# markers for it, and check.sh's test gate greps logs for exactly those markers.)
	print("[compile-sweep] self-test: the next parse error is deliberate.")
	var probe := "user://compile_sweep_self_test.gd"
	var f := FileAccess.open(probe, FileAccess.WRITE)
	f.store_string("extends RefCounted\nfunc broken() -> void:\n\tvar _x = TotallyUndeclaredIdentifier\n")
	f.close()
	var probe_rejected: bool = not compiles(probe)
	DirAccess.remove_absolute(probe)
	if not probe_rejected:
		printerr("[compile-sweep] SELF-TEST FAILED: a broken script compiled -- the sweep cannot be trusted.")
		quit(1)
		return

	var failures: Array = []
	var count: int = 0
	for path in gd_paths("res://"):
		count += 1
		if not compiles(path):
			failures.append(path)
	if failures.is_empty():
		print("[compile-sweep] %d scripts compiled clean." % count)
		quit(0)
		return
	# Godot already printed each script's own SCRIPT ERROR above; this list is the
	# summary a log reader (and the caller's grep) keys on.
	for path in failures:
		printerr("[compile-sweep] FAILED to compile: %s" % path)
	printerr("[compile-sweep] %d of %d scripts failed to compile." % [failures.size(), count])
	quit(1)


## Whether the script at `path` loads AND compiled. Both checks are load-bearing:
## load() returns null when a DEPENDENCY failed to compile ("Failed to compile
## depended scripts"), but for a script whose OWN body has the parse error it still
## returns the resource object -- with can_instantiate() false, since no valid
## compiled class backs it. Every script in this project is a concrete class, so a
## non-instantiable load is a compile failure, not a design choice.
static func compiles(path: String) -> bool:
	var script: Script = load(path)
	return script != null and script.can_instantiate()


## Every .gd file under `root`, recursively, sorted for a stable report. Skips hidden
## directories (.git, .godot -- the editor cache holds no source) but deliberately
## includes addons/: broken vendored code breaks runs just the same.
static func gd_paths(root: String) -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var path: String = root.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(gd_paths(path))
		elif entry.ends_with(".gd"):
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
