class_name DoctrineRegistry
## Phase 3 of the chain-of-command battle AI (docs/battle-ai-design.md): loads doctrine
## profile data files (data/doctrines/*.json) into the plain Dictionaries General.gd reads.
## Mirrors LoadoutRegistry's "load once, O(1) dictionary lookup, no per-call allocation"
## pattern and CampaignLoader's "parse_*() is pure, load_*() reads the file" split, so the
## parsing itself is directly unit-testable without touching the filesystem.
##
## A doctrine profile authored by a non-programmer needs only:
##   name                       display name (for debug/tooling use; the runtime never
##                              branches on it).
##   plans                      array of plan-name strings this doctrine knows (see
##                              General.gd's PLAN_* constants for the recognised names).
##   envelop_ratio_threshold    General.select_plan picks "envelop" (if it's in `plans`) once
##                              the team's own living-unit count is at least this multiple of
##                              the enemy's; otherwise "advance_line". A low threshold picks
##                              envelop readily (aggressive); a high one needs a lopsided
##                              advantage first (cautious).
##   reserve_fraction           0.0-1.0: the fraction of the team's own units held back as
##                              reserves instead of joining an active subcommander group.
##   reserve_commit_morale_threshold
##                              once the active groups' units-weighted average morale drops
##                              below this, reserves fold into the active groups. A high
##                              threshold commits at the first sign of trouble; a low one holds
##                              reserves until the line is close to breaking.
##   pursue_routers             whether UnitLeader's fallback targeting chases down a routing
##                              enemy (true) or leaves it be, holding the line instead (false).
##
## Doctrine data has no runtime dependency beyond plain JSON -- LLMs may draft it offline (see
## the design doc's "Doctrine profiles are data; LLMs stay offline" section), but the runtime
## here is a deterministic dictionary lookup like every other data table in this game.

const DOCTRINE_DIR := "res://data/doctrines/"

const REQUIRED_KEYS := [
	"name", "plans", "envelop_ratio_threshold", "reserve_fraction",
	"reserve_commit_morale_threshold", "pursue_routers",
]

## Cache: doctrine id (filename stem, e.g. "aggressive") -> parsed Dictionary. Built lazily on
## first lookup (not at class load like LoadoutRegistry's literal tables, since these are files
## on disk), but every doctrine loaded is then O(1) to re-fetch, and never mutated after load.
static var _cache: Dictionary = {}


## The parsed doctrine profile for `id` (e.g. "aggressive"), or {} if the file is missing or
## malformed. Reads data/doctrines/<id>.json the first time `id` is requested; later calls are
## a plain dictionary lookup.
static func doctrine(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var parsed: Dictionary = load_doctrine(DOCTRINE_DIR.path_join(id + ".json"))
	_cache[id] = parsed
	return parsed


## Read and parse a doctrine profile from `path` (res://...). Returns {} on any error. Split
## from parse_doctrine() (pure) so the parsing/validation logic is unit-testable without
## touching the filesystem, mirroring CampaignLoader.load_map/parse_map.
static func load_doctrine(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Doctrine profile: file not found: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_warning("Doctrine profile: empty or unreadable file: %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("Doctrine profile: invalid JSON in %s (line %d): %s"
				% [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		push_warning("Doctrine profile: %s must contain a JSON object" % path)
		return {}
	return parse_doctrine(json.data)


## Validate and convert an already-parsed doctrine dict into the in-memory format (typed plan
## array, clamped reserve fraction). Returns {} on any error.
static func parse_doctrine(raw: Dictionary) -> Dictionary:
	for key in REQUIRED_KEYS:
		if not raw.has(key):
			push_warning("Doctrine profile: missing required key '%s'" % key)
			return {}
	var raw_plans: Variant = raw["plans"]
	if typeof(raw_plans) != TYPE_ARRAY or raw_plans.is_empty():
		push_warning("Doctrine profile: 'plans' must be a non-empty array")
		return {}
	var plans: Array[String] = []
	for p in raw_plans:
		plans.append(str(p))
	return {
		"name": str(raw.get("name", "Doctrine")),
		"plans": plans,
		"envelop_ratio_threshold": float(raw["envelop_ratio_threshold"]),
		"reserve_fraction": clampf(float(raw["reserve_fraction"]), 0.0, 1.0),
		"reserve_commit_morale_threshold": float(raw["reserve_commit_morale_threshold"]),
		"pursue_routers": bool(raw["pursue_routers"]),
	}


## Every doctrine id with a data file on disk, sorted -- for tooling/tests that want to iterate
## the roster without hard-coding filenames.
static func doctrine_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(DOCTRINE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			out.append(fname.trim_suffix(".json"))
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
