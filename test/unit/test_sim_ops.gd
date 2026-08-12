extends GutTest
## The per-tick work counters (scripts/SimOps.gd) a backend-only performance PR graphs before
## and after its change. Every test restores `enabled` to false in teardown: the flag is a
## static on a global class, so leaving it on would silently make every later test in the run
## accumulate counts (and pay for them).


func after_each() -> void:
	SimOps.enabled = false
	SimOps.reset()
	# The hash is a frame-keyed static shared with every other test in the run.
	SoldierSpatialHash.reset()


func test_counting_is_off_by_default_so_a_normal_tick_records_nothing() -> void:
	SimOps.reset()
	SimOps.add(SimOps.GRID_CANDIDATE, 400)
	SimOps.bump(SimOps.UNIT_THINK)
	assert_eq(SimOps.peek(SimOps.GRID_CANDIDATE), 0, "disabled add is dropped")
	assert_eq(SimOps.peek(SimOps.UNIT_THINK), 0, "disabled bump is dropped")


func test_add_and_bump_accumulate_per_bucket_when_enabled() -> void:
	SimOps.enabled = true
	SimOps.add(SimOps.GRID_CANDIDATE, 400)
	SimOps.add(SimOps.GRID_CANDIDATE, 60)
	SimOps.bump(SimOps.UNIT_THINK)
	SimOps.bump(SimOps.UNIT_THINK)
	assert_eq(SimOps.peek(SimOps.GRID_CANDIDATE), 460, "adds sum within the tick")
	assert_eq(SimOps.peek(SimOps.UNIT_THINK), 2, "bump is add(bucket, 1)")
	assert_eq(SimOps.peek(SimOps.BODY_STEP), 0, "an untouched bucket stays at zero")


func test_non_positive_batches_are_ignored() -> void:
	SimOps.enabled = true
	SimOps.add(SimOps.STEER_PAIR, 0)
	SimOps.add(SimOps.STEER_PAIR, -5)
	assert_eq(SimOps.peek(SimOps.STEER_PAIR), 0,
		"an empty or nonsensical batch size never moves a counter")


func test_take_tick_reports_every_bucket_plus_a_total_and_then_drains() -> void:
	SimOps.enabled = true
	SimOps.add(SimOps.CONTACT_PAIR, 7)
	SimOps.add(SimOps.SQRT_EVAL, 3)
	var tick: Dictionary = SimOps.take_tick()
	assert_eq(tick["contact_pair"], 7)
	assert_eq(tick["sqrt_eval"], 3)
	assert_eq(tick["total"], 10, "total sums every bucket")
	for name in SimOps.BUCKET_NAMES:
		assert_true(tick.has(name), "every bucket is reported, including the empty ones: %s" % name)
	assert_eq(SimOps.take_tick()["total"], 0,
		"draining leaves the next tick starting from zero, not a running total")


func test_take_tick_reports_zeros_rather_than_an_empty_dictionary_when_disabled() -> void:
	var tick: Dictionary = SimOps.take_tick()
	assert_eq(tick.size(), SimOps.BUCKET_NAMES.size() + 1,
		"a consumer's schema does not change with the flag")
	assert_eq(tick["total"], 0)


func test_reset_clears_a_partially_counted_tick() -> void:
	SimOps.enabled = true
	SimOps.add(SimOps.MELEE_CHECK, 99)
	SimOps.reset()
	assert_eq(SimOps.peek(SimOps.MELEE_CHECK), 0)


func test_a_real_pass_reports_the_work_it_actually_did() -> void:
	# Wiring check, not just arithmetic: the soldier broadphase runs once per tick and must
	# report every body it bucketed, since that count stands in for the whole rebuild loop.
	SimOps.enabled = true
	SoldierSpatialHash.reset()
	var positions := PackedVector2Array([
		Vector2.ZERO, Vector2(1.0, 0.0), Vector2(2.0, 1.0), Vector2(900.0, 900.0)])
	SoldierSpatialHash.rebuild(positions, 987654)
	assert_eq(SimOps.peek(SimOps.GRID_INSERT), positions.size(),
		"every bucketed body is counted once")


func test_the_per_soldier_query_does_not_count_from_inside_itself() -> void:
	# query() runs once per soldier, so a SimOps call inside it would be paid thousands of
	# times a tick -- measurably, on every ordinary game tick, for a number the two callers
	# already tally into a local and report once per pass. Guard that it stays out.
	SimOps.enabled = true
	SoldierSpatialHash.reset()
	SoldierSpatialHash.rebuild(PackedVector2Array([Vector2.ZERO, Vector2(1.0, 0.0)]), 987655)
	SimOps.reset()
	var candidates: PackedInt32Array = SoldierSpatialHash.query(Vector2.ZERO)
	assert_gt(candidates.size(), 0, "the neighbourhood around a clustered body is not empty")
	assert_eq(SimOps.take_tick()["total"], 0,
		"the per-soldier query counts nothing; its callers report the pass total instead")


func test_bucket_ids_are_unique_and_index_their_own_names() -> void:
	# The ids are array indices into BUCKET_NAMES; a duplicate or an off-by-one would make two
	# call sites silently share a counter, which a recorded series has no way to show.
	var ids: Array = [SimOps.GRID_INSERT, SimOps.GRID_CANDIDATE, SimOps.STEER_PAIR,
		SimOps.CONTACT_PAIR, SimOps.BODY_STEP, SimOps.MELEE_CHECK, SimOps.REGIMENT_CHECK,
		SimOps.UNIT_THINK, SimOps.SQRT_EVAL]
	assert_eq(ids.size(), SimOps.BUCKET_NAMES.size(), "one id per name")
	var seen: Dictionary = {}
	for id in ids:
		assert_false(seen.has(id), "duplicate bucket id %d" % id)
		seen[id] = true
		assert_true(id >= 0 and id < SimOps.BUCKET_NAMES.size(), "id %d is in range" % id)

	# And each id names the bucket it is meant to: count one, read it back by name.
	SimOps.enabled = true
	for id in ids:
		SimOps.reset()
		SimOps.add(id, 1)
		assert_eq(SimOps.take_tick()[SimOps.BUCKET_NAMES[id]], 1,
			"id %d counts into '%s'" % [id, SimOps.BUCKET_NAMES[id]])
