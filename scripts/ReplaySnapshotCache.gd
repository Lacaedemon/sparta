class_name ReplaySnapshotCache
## Derived, in-memory cache of full-state replay snapshots, so rewinding or
## scrubbing during PLAYBACK doesn't have to resimulate from tick 0 every time. A snapshot
## captured at tick T lets Battle.restore_snapshot() resume simulating from T instead of 0 --
## the remaining (target - T) ticks still have to run (there is no way to derive a state
## without simulating it), but that's a small, bounded slice instead of the whole battle.
##
## Snapshots are NEVER written to the canonical .replay file (REPLAY.md's deterministic
## order-log format is unchanged) -- this cache lives only in memory for the life of one
## Battle instance, and is trivially regeneratable: a replay simulates identically with or
## without it, so it's always safe to clear() and rebuild.
##
## Pure indexing/eviction logic -- this class knows nothing about Battle or Unit. A caller
## supplies the actual snapshot payload as an opaque Dictionary and asks this class when to
## capture one (should_snapshot) and which one to resume a rewind from
## (nearest_at_or_before).

## Ticks between automatically-captured snapshots (the "density" the issue calls out as
## needing to be configurable). 300 ticks is ~5s of battle at Replay.PHYSICS_TPS -- coarse
## enough that a normal playback caches only a handful of snapshots, but no rewind ever has
## to resimulate more than about 5s to reach an arbitrary point. Callers needing finer
## scrub resolution while debugging a specific window pass a smaller interval to _init().
const DEFAULT_INTERVAL_TICKS := 300

## Maximum number of snapshots retained at once. Bounds memory for a long, rewind-heavy
## debugging session -- each snapshot carries a full per-unit/per-soldier state, so letting
## the cache grow with the length of the battle watched would be unbounded. Eviction is
## LRU by *last use* (see touch()), not insertion order: a snapshot a rewind keeps landing
## near stays cached even once newer ticks have been captured past it, while one nobody
## has sought near ages out first.
const DEFAULT_MAX_SNAPSHOTS := 20

var interval_ticks: int
var max_snapshots: int

# tick -> opaque snapshot payload.
var _snapshots: Dictionary = {}
# tick -> monotonically increasing "last touched" counter, for LRU eviction.
var _last_used: Dictionary = {}
var _use_counter: int = 0


func _init(interval: int = DEFAULT_INTERVAL_TICKS, capacity: int = DEFAULT_MAX_SNAPSHOTS) -> void:
	interval_ticks = maxi(1, interval)
	max_snapshots = maxi(1, capacity)


## Whether `tick` falls on a snapshot boundary. Pure -- doesn't consult what's already
## cached, so a caller that wants to avoid recapturing an existing tick checks has() too.
func should_snapshot(tick: int) -> bool:
	return tick >= 0 and tick % interval_ticks == 0


func has(tick: int) -> bool:
	return _snapshots.has(tick)


func size() -> int:
	return _snapshots.size()


## Every cached tick, ascending. For tests and debugging.
func ticks() -> Array:
	var out: Array = _snapshots.keys()
	out.sort()
	return out


## Cache `payload` under `tick`, evicting the least-recently-used entry first if the cache
## is already at capacity. Overwrites in place if `tick` is already cached (no eviction
## needed -- the slot count doesn't grow).
func store(tick: int, payload: Dictionary) -> void:
	if not _snapshots.has(tick) and _snapshots.size() >= max_snapshots:
		_evict_lru()
	_snapshots[tick] = payload
	_touch(tick)


## The cached snapshot at or before `tick`, or {} if none exists -- either the cache is
## empty, or every cached snapshot is later than `tick` (rewinding earlier than anything
## captured so far). The caller falls back to resimulating from tick 0 in that case,
## exactly like today. Marks the returned snapshot as just-used so a rewind that keeps
## landing on the same tick keeps it alive under eviction pressure.
func nearest_at_or_before(tick: int) -> Dictionary:
	var best: int = -1
	for t in _snapshots.keys():
		if t <= tick and t > best:
			best = t
	if best < 0:
		return {}
	_touch(best)
	return _snapshots[best]


func clear() -> void:
	_snapshots.clear()
	_last_used.clear()
	_use_counter = 0


func _touch(tick: int) -> void:
	_use_counter += 1
	_last_used[tick] = _use_counter


func _evict_lru() -> void:
	var oldest_tick: int = -1
	var oldest_use: int = -1
	for t in _snapshots.keys():
		var u: int = int(_last_used.get(t, -1))
		if oldest_tick < 0 or u < oldest_use:
			oldest_tick = t
			oldest_use = u
	if oldest_tick >= 0:
		_snapshots.erase(oldest_tick)
		_last_used.erase(oldest_tick)
