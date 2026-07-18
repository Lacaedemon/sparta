extends GutTest
## DemoStateHash: the per-tick two-tier state hash and its stream comparison.
## Collector tests build minimal live units in the tree (the collectors walk the same
## "units"/"routers" groups the readable snapshot does); the stream parse/compare tests
## are pure data in, verdict out.


## A tree-registered unit with fully pinned, deterministic per-soldier arrays, so the
## hash input is exactly what the test wrote (no dependence on spawn-path defaults).
func _make_hash_unit(uid: int, pos: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 2
	add_child_autofree(u)
	u.uid = uid
	u.position = pos
	u._sim_soldier_pos = PackedVector2Array([pos + Vector2(1, 1), pos + Vector2(2, 2)])
	u._sim_soldier_facing = PackedVector2Array([Vector2.DOWN, Vector2.DOWN])
	u._sim_soldier_hp = PackedFloat32Array([1.0, 1.0])
	u._sim_prone = PackedFloat32Array([0.0, 0.0])
	u._sim_soldier_stamina = PackedFloat32Array([1.0, 1.0])
	return u


func test_same_state_hashes_identically_on_both_tiers() -> void:
	_make_hash_unit(1, Vector2(100, 100))
	_make_hash_unit(2, Vector2(300, 100))
	assert_eq(DemoStateHash.cheap_tick_hash(get_tree()), DemoStateHash.cheap_tick_hash(get_tree()),
			"unchanged state produces an identical cheap hash")
	assert_eq(DemoStateHash.full_tick_hash(get_tree(), 42), DemoStateHash.full_tick_hash(get_tree(), 42),
			"unchanged state produces an identical full hash")


func test_a_soldier_position_change_changes_the_cheap_hash() -> void:
	var u := _make_hash_unit(1, Vector2(100, 100))
	var before: String = DemoStateHash.cheap_tick_hash(get_tree())
	# The smallest representable nudge still flips the hash: raw float BITS are hashed,
	# not rounded text, so sub-rounding drift -- the thing the stream exists to catch --
	# is never invisible.
	u._sim_soldier_pos[0] += Vector2(0.001, 0.0)
	assert_ne(DemoStateHash.cheap_tick_hash(get_tree()), before,
			"a tiny soldier-position change flips the cheap hash")


func test_morale_changes_only_the_full_tier() -> void:
	var u := _make_hash_unit(1, Vector2(100, 100))
	var cheap_before: String = DemoStateHash.cheap_tick_hash(get_tree())
	var full_before: String = DemoStateHash.full_tick_hash(get_tree(), 42)
	u.morale = 55.5
	assert_eq(DemoStateHash.cheap_tick_hash(get_tree()), cheap_before,
			"morale is not part of the cheap positions tier")
	assert_ne(DemoStateHash.full_tick_hash(get_tree(), 42), full_before,
			"morale is part of the full tier")


func test_rng_state_changes_only_the_full_tier() -> void:
	_make_hash_unit(1, Vector2(100, 100))
	assert_ne(DemoStateHash.full_tick_hash(get_tree(), 1), DemoStateHash.full_tick_hash(get_tree(), 2),
			"the replay RNG state is part of the full tier")


func test_units_hash_in_uid_order_not_group_order() -> void:
	# Group enumeration order follows insertion; the collector must sort by uid so a
	# rout/rally group move can never reorder the hash input.
	_make_hash_unit(7, Vector2(300, 100))
	_make_hash_unit(3, Vector2(100, 100))
	var uids: Array = []
	for u in DemoStateHash.units_by_uid(get_tree()):
		uids.append(u.uid)
	assert_eq(uids, [3, 7], "collector orders by uid, not insertion/group order")


func test_far_tier_unit_hashes_without_soldier_arrays() -> void:
	var u := _make_hash_unit(1, Vector2(100, 100))
	u.tier = FormationTier.FAR
	var before: String = DemoStateHash.cheap_tick_hash(get_tree())
	u._sim_soldier_pos[0] += Vector2(5.0, 0.0)
	assert_eq(DemoStateHash.cheap_tick_hash(get_tree()), before,
			"a FAR-tier record carries no per-soldier payload, matching the readable snapshot")


func test_stream_round_trip_and_full_cadence() -> void:
	var dir: String = OS.get_temp_dir().path_join("sparta_hash_stream_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = DemoHashStream.open_stream(dir)
	assert_not_null(f, "stream file opens")
	DemoHashStream.append_line(f, 19, "aaaa", "")
	DemoHashStream.append_line(f, 20, "bbbb", "ffff")
	f.close()
	var text: String = FileAccess.get_file_as_string(dir.path_join("hash_stream.jsonl"))
	var stream: Array = DemoHashStream.parse_stream(text)
	assert_eq(stream.size(), 2, "both lines parse back")
	assert_false(stream[0].has("full"), "a cheap-only tick has no full field")
	assert_eq(str(stream[1]["full"]), "ffff", "a FULL_EVERY tick carries the full hash")


func test_parse_stream_skips_malformed_lines() -> void:
	var stream: Array = DemoHashStream.parse_stream(
			'{"tick": 1, "cheap": "aa"}\n{"tick": 2, "che\n{"tick": 3, "cheap": "cc"}\n')
	assert_eq(stream.size(), 2, "the truncated middle line is skipped, not fatal")


func test_compare_streams_identical() -> void:
	var a: Array = [{"tick": 1, "cheap": "aa"}, {"tick": 2, "cheap": "bb", "full": "ff"}]
	var b: Array = [{"tick": 1, "cheap": "aa"}, {"tick": 2, "cheap": "bb", "full": "ff"}]
	var v: Dictionary = DemoHashStream.compare_streams(a, b)
	assert_false(v["divergent"], "identical streams are not divergent")
	assert_eq(int(v["compared"]), 2, "both common ticks compared")


func test_compare_streams_reports_first_cheap_divergence() -> void:
	var a: Array = [{"tick": 1, "cheap": "aa"}, {"tick": 2, "cheap": "bb"}, {"tick": 3, "cheap": "cc"}]
	var b: Array = [{"tick": 1, "cheap": "aa"}, {"tick": 2, "cheap": "XX"}, {"tick": 3, "cheap": "YY"}]
	var v: Dictionary = DemoHashStream.compare_streams(a, b)
	assert_true(v["divergent"], "differing streams are divergent")
	assert_eq(int(v["tick"]), 2, "the FIRST divergent tick is reported, not a later one")
	assert_eq(str(v["tier"]), "cheap", "a position-tier divergence names the cheap tier")


func test_compare_streams_full_only_divergence_names_the_full_tier() -> void:
	# Cheap hashes match but the full hashes differ: the divergence is in non-position
	# state (morale, orders, the RNG) -- the tier tells a reader which bracket to dig in.
	var a: Array = [{"tick": 20, "cheap": "aa", "full": "f1"}]
	var b: Array = [{"tick": 20, "cheap": "aa", "full": "f2"}]
	var v: Dictionary = DemoHashStream.compare_streams(a, b)
	assert_true(v["divergent"], "a full-tier mismatch is a divergence")
	assert_eq(str(v["tier"]), "full", "named as the full tier")


func test_compare_streams_counts_uncommon_ticks_without_diverging() -> void:
	# One run quit earlier than the other: the shorter common range still compares, and
	# the extra ticks are reported as coverage, not treated as a divergence.
	var a: Array = [{"tick": 1, "cheap": "aa"}, {"tick": 2, "cheap": "bb"}, {"tick": 3, "cheap": "cc"}]
	var b: Array = [{"tick": 1, "cheap": "aa"}, {"tick": 2, "cheap": "bb"}]
	var v: Dictionary = DemoHashStream.compare_streams(a, b)
	assert_false(v["divergent"], "a length mismatch alone is not a divergence")
	assert_eq(int(v["compared"]), 2, "the common range is what gets compared")
	assert_eq(int(v["only_a"]), 1, "the first stream's extra tick is counted")
	assert_eq(int(v["only_b"]), 0, "the second stream has no extras")
