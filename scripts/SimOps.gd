class_name SimOps
extends RefCounted
## Opt-in census of how much WORK the simulation does per tick, counted deterministically
## rather than timed.
##
## A timing benchmark answers "is this build slower on this machine, right now" -- and on a
## shared CI runner that signal carries a documented run-to-run swing wide enough to hide a
## real win or invent a fake one. These counters answer a different, reproducible question:
## how many candidate scans, contact pairs, body steps and square-root evaluations the sim
## actually performed on each tick. The same scenario and seed give the same counts on any
## machine, so a before/after graph of them is evidence that an optimization removed work.
##
## Cost when disabled: a counting call site belongs at PASS granularity -- once per steering
## pass, per contact pass, per unit-step -- never inside a per-soldier function or an inner
## loop, and it passes a batch size the pass already knows (an array size, a local tally, or
## plain arithmetic over the loop bounds). An ordinary game tick therefore pays a few dozen
## early-returning static calls in total, not thousands: measured at pass granularity the
## counters cost nothing detectable, while an earlier per-soldier placement of the same counts
## cost a measurable ~2% of every tick. Keep new sites at pass granularity.
##
## Turn it on with `SimOps.enabled = true` (tools/benchmark/BenchmarkRunner.gd does that when
## asked for a per-tick series) and drain each tick's totals with `take_tick()`.

## Work buckets. SQRT_EVAL cross-cuts the others: it counts the square-root-class evaluations
## (`length()`, `distance_to`, `normalized()`) the instrumented passes performed, which is the
## quantity a `distance_to` -> `distance_squared_to` optimization actually moves -- the pair and
## candidate counts around it stay flat through that kind of change.
const GRID_INSERT := 0
const GRID_CANDIDATE := 1
const STEER_PAIR := 2
const CONTACT_PAIR := 3
const BODY_STEP := 4
const MELEE_CHECK := 5
const REGIMENT_CHECK := 6
const UNIT_THINK := 7
const SQRT_EVAL := 8

## Report keys, indexed by the bucket ids above -- the names a recorded series and its graph
## carry, so renaming one invalidates comparison against an older series.
const BUCKET_NAMES: PackedStringArray = [
	"grid_insert", "grid_candidate", "steer_pair", "contact_pair", "body_step",
	"melee_check", "regiment_check", "unit_think", "sqrt_eval",
]

## Off in normal play, and in every test that doesn't explicitly opt in.
static var enabled: bool = false

static var _counts: PackedInt64Array = PackedInt64Array()


## Size the counter array on first use rather than at class load. A `_static_init()` here
## would run while the class is being loaded, which under the coverage addon's instrumentation
## is before its collector singleton exists -- the injected probe then dereferences a null and
## the whole coverage run reports a script error.
static func _ready_counts() -> void:
	if _counts.size() != BUCKET_NAMES.size():
		reset()


## Record `n` units of work in `bucket`. Call this once per pass, outside the loop, with a
## count the loop already produced -- never once per iteration.
static func add(bucket: int, n: int) -> void:
	if not enabled or n <= 0:
		return
	_ready_counts()
	_counts[bucket] += n


## Record a single whole-pass event (one unit's think pass, one grid query).
static func bump(bucket: int) -> void:
	add(bucket, 1)


## This tick's counts as `{bucket_name: count}` plus a summed `total`, clearing them so the
## next tick starts from zero. Returns zeros (not an empty dictionary) when disabled, so a
## consumer's schema doesn't change with the flag.
static func take_tick() -> Dictionary:
	_ready_counts()
	var out: Dictionary = {}
	var total: int = 0
	for i in range(BUCKET_NAMES.size()):
		out[BUCKET_NAMES[i]] = _counts[i]
		total += _counts[i]
	out["total"] = total
	reset()
	return out


## Current value of one bucket, without draining the tick. For tests and assertions.
static func peek(bucket: int) -> int:
	_ready_counts()
	return _counts[bucket]


## Drop every accumulated count (sizing the array on the first call). Used by `take_tick()`
## and by any test that needs isolation from whatever ran before it.
static func reset() -> void:
	_counts.resize(BUCKET_NAMES.size())
	_counts.fill(0)
