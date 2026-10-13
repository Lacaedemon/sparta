class_name MeleeRunStore
## The run directories of tools/ci/melee-outcome-delta.sh, read and written by
## melee_outcome_compare.gd. Each run directory holds:
##   - run.json: {"end", "step"}, written by the delta script when it schedules the run: the
##     last snapshot tick it scheduled, and the snapshot cadence;
##   - state_*.json: the run's snapshots (deleted after extraction unless kept);
##   - metrics.json: {"travel", "end", "step", "metrics"}, the run's MeleeOutcomes metrics.
##
## A metrics.json is used only when it was made with the same travel offsets and the same
## step as asked, and the same end as the run's run.json. Otherwise the run is re-extracted
## from its snapshots with run.json's end, so a cut-off run never turns into a complete one;
## a run that cannot be (no snapshots, or no run.json to say where it should end) is an error.

const METRICS_FILE := "metrics.json"
const RUN_FILE := "run.json"


## Extract `dir`'s snapshots into dir/metrics.json. Returns "" or an error message.
static func extract(dir: String, travel: Array, end_tick: int, step: int) -> String:
	var snaps: Array = snapshots(dir)
	if snaps.is_empty():
		return "no state_*.json snapshots in %s" % dir
	var f: FileAccess = FileAccess.open(dir.path_join(METRICS_FILE), FileAccess.WRITE)
	if f == null:
		return "could not write %s" % dir.path_join(METRICS_FILE)
	var metrics: Dictionary = MeleeOutcomes.extract(snaps, travel, end_tick)
	f.store_string(JSON.stringify({"travel": travel, "end": end_tick, "step": step,
			"metrics": metrics}, "", true, true))
	f.close()
	return ""


## One run's metrics: {"metrics": {...}}, {} when the directory holds no run at all, or
## {"error": message}. `step` < 0 accepts any step.
static func run_metrics(dir: String, travel: Array, step: int) -> Dictionary:
	var info = _read_json(dir.path_join(RUN_FILE))
	var cached = _read_json(dir.path_join(METRICS_FILE))
	if cached is Dictionary:
		if step >= 0 and int(cached.get("step", -1)) != step:
			return {"error": "%s was extracted at step %s, not %d; use a fresh out-dir"
					% [dir, str(cached.get("step")), step]}
		var same_travel: bool = cached.get("travel", []).map(func(t) -> int: return int(t)) == travel
		var same_end: bool = info is Dictionary and int(info.get("end", -1)) == int(cached.get("end", -2))
		if same_travel and same_end:
			return {"metrics": cached["metrics"]}
	var snaps: Array = snapshots(dir)
	if snaps.is_empty():
		if cached == null:
			return {}
		return {"error": "%s needs re-extracting (other travel offsets or end) but has no snapshots left" % dir}
	if not (info is Dictionary) or not info.has("end"):
		return {"error": "%s has snapshots but no %s to say where the run should end" % [dir, RUN_FILE]}
	if step >= 0 and int(info.get("step", -1)) != step:
		return {"error": "%s was dumped at step %s, not %d; use a fresh out-dir"
				% [dir, str(info.get("step")), step]}
	return {"metrics": MeleeOutcomes.extract(snaps, travel, int(info["end"]))}


## clip -> Array of per-run metrics for every clip directory under `root` named in `clips`
## (every one when empty): the runs seed<k> for each k in `seeds`, or every run directory when
## `seeds` is empty. Returns {"runs": {...}, "error": ""}; a named run that is missing or
## unreadable sets the error.
static func load_root(root: String, travel: Array, seeds: Array, clips: Array, step: int) -> Dictionary:
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
			var got: Dictionary = run_metrics(clip_dir.path_join(run), travel, step)
			if got.has("error"):
				return {"runs": out, "error": got["error"]}
			if got.is_empty():
				if not seeds.is_empty():
					return {"runs": out, "error": "run %s is missing" % clip_dir.path_join(run)}
				continue
			runs.append(got["metrics"])
		if not runs.is_empty():
			out[clip] = runs
	return {"runs": out, "error": ""}


## The parsed state_*.json snapshots in `dir`.
static func snapshots(dir: String) -> Array:
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


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
