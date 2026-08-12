class_name DemoHashStream
## The hash_stream.jsonl file format and its offline comparison -- the pure half of the
## per-tick state-hash pipeline (DemoStateHash computes the hashes from live game state;
## this class never touches a game script). Kept dependency-free on purpose:
## analyze_transcript.gd runs as a bare `godot -s` SceneTree with no autoloads, where any
## reference chain into the game scripts (Unit -> Settings, ...) spews compile errors --
## the same reason DemoDefects reads snapshots as plain Dictionaries.
##
## Stream shape, one line per tick:
##   {"tick": 12, "cheap": "<md5 hex>"}                       -- every tick
##   {"tick": 20, "cheap": "<md5 hex>", "full": "<md5 hex>"}  -- every FULL_EVERY ticks

## Full-tier cadence, matching 0 A.D.'s every-20-turns full hash: the cheap tier
## localizes the first divergent tick, the bracketing full hashes tell whether
## non-position state (morale, orders, the RNG) diverged first.
const FULL_EVERY := 20


## Open (truncating) the stream file for a dump run. Callers keep the handle for the
## whole run and append_line() flushes after every line, so a run that quits without
## an explicit close still leaves a complete stream on disk.
static func open_stream(dir: String) -> FileAccess:
	return FileAccess.open("%s/hash_stream.jsonl" % dir.trim_suffix("/"), FileAccess.WRITE)


## Append one tick's line. `full` is the full-tier hash for a FULL_EVERY tick, or ""
## on the (cheap-only) ticks in between.
static func append_line(f: FileAccess, tick: int, cheap: String, full: String) -> void:
	var entry: Dictionary = {"tick": tick, "cheap": cheap}
	if full != "":
		entry["full"] = full
	f.store_line(JSON.stringify(entry))
	f.flush()


## Parse a hash_stream.jsonl text into the entry list compare_streams takes. Malformed
## lines are skipped (a truncated final line from a killed run shouldn't poison the
## whole comparison) -- via the instance JSON API, whose parse failures are a return
## code rather than the pushed engine error JSON.parse_string emits.
static func parse_stream(text: String) -> Array:
	var out: Array = []
	var json := JSON.new()
	for line in text.split("\n", false):
		if json.parse(line) != OK:
			continue
		var parsed = json.data
		if parsed is Dictionary and parsed.has("tick") and parsed.has("cheap"):
			out.append(parsed)
	return out


## Compare two parsed streams and report the FIRST divergent tick. Ticks are matched
## by number (not position), so streams of different lengths compare over their
## common range; ticks present in only one stream are counted but are not themselves
## a divergence. Returns:
##   {"divergent": true, "tick": N, "tier": "cheap"|"full", "compared": n}
##   {"divergent": false, "compared": n, "only_a": x, "only_b": y}
## A tick whose cheap hashes match but whose full hashes differ diverged in
## non-position state (morale, orders, the RNG) -- tier names which.
static func compare_streams(a: Array, b: Array) -> Dictionary:
	var by_tick_b: Dictionary = {}
	for e in b:
		by_tick_b[int(e["tick"])] = e
	var common: Array = []
	for e in a:
		if by_tick_b.has(int(e["tick"])):
			common.append(e)
	common.sort_custom(func(x, y): return int(x["tick"]) < int(y["tick"]))
	var compared: int = common.size()
	for e in common:
		var tick: int = int(e["tick"])
		var other: Dictionary = by_tick_b[tick]
		if e["cheap"] != other["cheap"]:
			return {"divergent": true, "tick": tick, "tier": "cheap", "compared": compared}
		if e.get("full", "") != other.get("full", ""):
			return {"divergent": true, "tick": tick, "tier": "full", "compared": compared}
	return {"divergent": false, "compared": compared,
			"only_a": a.size() - compared, "only_b": b.size() - compared}
