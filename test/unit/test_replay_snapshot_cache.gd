extends GutTest
## ReplaySnapshotCache: pure indexing/eviction logic, no Battle/Unit involved --
## the payload is just an opaque Dictionary the cache never inspects.


func test_should_snapshot_is_true_on_every_interval_boundary() -> void:
	var c := ReplaySnapshotCache.new(100, 10)
	assert_true(c.should_snapshot(0))
	assert_true(c.should_snapshot(100))
	assert_true(c.should_snapshot(300))
	assert_false(c.should_snapshot(1))
	assert_false(c.should_snapshot(99))
	assert_false(c.should_snapshot(150))


func test_should_snapshot_rejects_a_negative_tick() -> void:
	var c := ReplaySnapshotCache.new(100, 10)
	assert_false(c.should_snapshot(-1))


func test_a_non_positive_interval_or_capacity_is_floored_to_one() -> void:
	# Guards a caller-supplied config (e.g. a malformed env-var override) from a modulo-by-
	# zero crash or an unusably empty cache.
	var c := ReplaySnapshotCache.new(0, -5)
	assert_eq(c.interval_ticks, 1)
	assert_eq(c.max_snapshots, 1)


func test_store_and_has() -> void:
	var c := ReplaySnapshotCache.new(100, 10)
	assert_false(c.has(100))
	c.store(100, {"tick": 100})
	assert_true(c.has(100))
	assert_eq(c.size(), 1)


func test_nearest_at_or_before_returns_the_closest_cached_tick_at_or_under() -> void:
	var c := ReplaySnapshotCache.new(100, 10)
	c.store(0, {"marker": "a"})
	c.store(300, {"marker": "b"})
	c.store(600, {"marker": "c"})
	assert_eq(c.nearest_at_or_before(650)["marker"], "c")
	assert_eq(c.nearest_at_or_before(600)["marker"], "c", "exact match counts as at-or-before")
	assert_eq(c.nearest_at_or_before(599)["marker"], "b")
	assert_eq(c.nearest_at_or_before(300)["marker"], "b")
	assert_eq(c.nearest_at_or_before(1)["marker"], "a")


func test_nearest_at_or_before_returns_empty_when_nothing_qualifies() -> void:
	var c := ReplaySnapshotCache.new(100, 10)
	assert_eq(c.nearest_at_or_before(50), {}, "an empty cache has nothing to return")
	c.store(300, {"marker": "b"})
	assert_eq(c.nearest_at_or_before(50), {},
			"every cached snapshot is later than the requested tick -- nothing qualifies")


func test_ticks_lists_every_cached_tick_ascending() -> void:
	var c := ReplaySnapshotCache.new(100, 10)
	c.store(600, {})
	c.store(0, {})
	c.store(300, {})
	assert_eq(c.ticks(), [0, 300, 600])


func test_store_overwrites_an_already_cached_tick_without_growing_size() -> void:
	var c := ReplaySnapshotCache.new(100, 10)
	c.store(100, {"marker": "first"})
	c.store(100, {"marker": "second"})
	assert_eq(c.size(), 1)
	assert_eq(c.nearest_at_or_before(100)["marker"], "second")


func test_clear_empties_the_cache() -> void:
	var c := ReplaySnapshotCache.new(100, 10)
	c.store(0, {})
	c.store(100, {})
	c.clear()
	assert_eq(c.size(), 0)
	assert_eq(c.ticks(), [])


func test_storing_past_capacity_evicts_the_least_recently_used_entry() -> void:
	var c := ReplaySnapshotCache.new(1, 2)   # interval 1 so every tick qualifies; capacity 2
	c.store(0, {})
	c.store(1, {})
	# Neither has been "used" since insertion beyond the store() itself -- tick 0 was
	# inserted first, so it's the least-recently-used and should be the one evicted.
	c.store(2, {})
	assert_eq(c.size(), 2, "capacity is never exceeded")
	assert_false(c.has(0), "the oldest, never-reused entry is evicted")
	assert_true(c.has(1))
	assert_true(c.has(2))


func test_touching_a_snapshot_via_nearest_at_or_before_protects_it_from_eviction() -> void:
	var c := ReplaySnapshotCache.new(1, 2)
	c.store(0, {})
	c.store(1, {})
	# Re-touch tick 0 (a rewind landing back on it), so it's now the MORE recently used of
	# the two -- tick 1 should be evicted instead when a third entry is stored.
	c.nearest_at_or_before(0)
	c.store(2, {})
	assert_true(c.has(0), "a snapshot touched more recently survives eviction")
	assert_false(c.has(1), "the untouched entry is evicted instead")
	assert_true(c.has(2))
