extends GutTest
## ReinforceLayout: the pure interleave bookkeeping for reinforcement insertion (doubling by
## number). No scene tree -- these run on bare id arrays and prove the slot assignment: which
## file/rank each host man and each reserve man ends on, and that no two men share a slot.

const Layout = preload("res://scripts/ReinforceLayout.gd")
const Formation = preload("res://scripts/UnitFormation.gd")


## A host of `count` men over `files` files in index order, with explicit ranks.
func _host(count: int, files: int) -> Dictionary:
	var file_ids: PackedInt32Array = Formation.file_ids_in_index_order(
			Formation.file_capacities(count, files))
	var ranks := PackedInt32Array()
	var seen: Dictionary = {}
	for fid in file_ids:
		ranks.push_back(int(seen.get(fid, 0)))
		seen[fid] = ranks[-1] + 1
	return {"file_ids": file_ids, "ranks": ranks}


## Reserve bodies laid out on a grid in the host's slot frame: `files` across, x increasing
## with the file, y increasing with the rank, so lateral order and depth are unambiguous.
func _reserve_grid(count: int, files: int, pitch: float = 10.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(count):
		out.push_back(Vector2(float(i % files) * pitch, float(i / files) * pitch))
	return out


## Every (file, rank) pair is unique across the combined arrays.
func _assert_no_shared_slot(result: Dictionary, label: String) -> void:
	var seen: Dictionary = {}
	var file_ids: PackedInt32Array = result["file_ids"]
	var ranks: PackedInt32Array = result["ranks"]
	assert_eq(ranks.size(), file_ids.size(), "%s: ranks index-align with file ids" % label)
	for i in range(file_ids.size()):
		var key := Vector2i(file_ids[i], ranks[i])
		assert_false(seen.has(key), "%s: slot %s is held by exactly one man" % [label, key])
		seen[key] = true
		assert_true(file_ids[i] >= 0 and file_ids[i] < int(result["files"]),
				"%s: file id %d lies inside the new frontage" % [label, file_ids[i]])


func test_full_files_insertion_alternates_host_and_reserve() -> void:
	var host := _host(8, 4)   # 4 files x 2 ranks
	var result: Dictionary = Layout.interleave_files(host["file_ids"], host["ranks"], 4,
			_reserve_grid(8, 4))
	assert_eq(int(result["files"]), 8, "frontage doubles when the reserve fills every gap")
	var file_ids: PackedInt32Array = result["file_ids"]
	var ranks: PackedInt32Array = result["ranks"]
	for i in range(8):
		assert_eq(file_ids[i], 2 * host["file_ids"][i], "host man %d keeps an even file" % i)
		assert_eq(ranks[i], host["ranks"][i], "host man %d keeps his rank" % i)
	for i in range(8):
		assert_eq(file_ids[8 + i] % 2, 1, "reserve man %d lands on an odd file" % i)
	_assert_no_shared_slot(result, "full files")


func test_reserve_lateral_order_is_preserved_across_inserted_files() -> void:
	var host := _host(8, 4)
	var reserve := _reserve_grid(8, 4)
	var result: Dictionary = Layout.interleave_files(host["file_ids"], host["ranks"], 4, reserve)
	var file_ids: PackedInt32Array = result["file_ids"]
	# Reserve bodies 0..3 are the front rank left to right: their inserted files must rise
	# with x, and body 4 (directly behind body 0) shares body 0's file one rank deeper.
	assert_eq(file_ids[8], 1, "leftmost reserve man takes the leftmost inserted file")
	assert_eq(file_ids[9], 3, "second reserve man takes the next inserted file")
	assert_eq(file_ids[10], 5, "third reserve man takes the third inserted file")
	assert_eq(file_ids[11], 7, "rightmost reserve man takes the rightmost inserted file")
	assert_eq(file_ids[12], file_ids[8], "the man behind the leftmost joins the same file")
	assert_eq(result["ranks"][12], 1, "and stands one rank deeper in it")


func test_partial_reserve_inserts_one_centred_file() -> void:
	var host := _host(8, 4)   # 2 deep, so a 2-man reserve is one file at the host's density
	var result: Dictionary = Layout.interleave_files(host["file_ids"], host["ranks"], 4,
			_reserve_grid(2, 1))
	assert_eq(int(result["files"]), 5, "one file inserted")
	var file_ids: PackedInt32Array = result["file_ids"]
	# h_0 = floor(0.5 * 4 / 1) = 2: the inserted file follows host file 2, so it is id 3 and
	# host file 3 shifts to 4 while files 0..2 hold.
	assert_eq(file_ids[8], 3, "the inserted file sits right of host file 2")
	assert_eq(file_ids[9], 3, "both reserve men share the inserted file")
	assert_eq(file_ids[7], 4, "host file 3 steps right to make room")
	assert_eq(file_ids[0], 0, "host file 0 holds")
	_assert_no_shared_slot(result, "partial files")


func test_surplus_reserve_caps_inserted_files_at_host_frontage() -> void:
	var host := _host(8, 4)
	var result: Dictionary = Layout.interleave_files(host["file_ids"], host["ranks"], 4,
			_reserve_grid(16, 4))   # 4 deep against a 2-deep host
	assert_eq(int(result["files"]), 8, "never more inserted files than host files")
	var ranks: PackedInt32Array = result["ranks"]
	var deepest: int = 0
	for i in range(8, 24):
		deepest = maxi(deepest, ranks[i])
	assert_eq(deepest, 3, "the inserted files run deeper than the host's")
	_assert_no_shared_slot(result, "surplus files")


func test_equal_strength_doubles_exactly_over_a_partial_rear_rank() -> void:
	# 40 men over 9 files is 4 deep with a 4-man partial rank (deepest file 5): the inserted
	# file count follows the host's density, not its deepest file, so it still doubles.
	var host := _host(40, 9)
	var result: Dictionary = Layout.interleave_files(host["file_ids"], host["ranks"], 9,
			_reserve_grid(40, 9))
	assert_eq(int(result["files"]), 18, "equal strength doubles the frontage")
	_assert_no_shared_slot(result, "partial rear rank")


func test_empty_reserve_or_host_is_a_no_op() -> void:
	var host := _host(8, 4)
	var empty: Dictionary = Layout.interleave_files(host["file_ids"], host["ranks"], 4,
			PackedVector2Array())
	assert_eq(int(empty["files"]), 4, "no reserve: frontage unchanged")
	assert_true((empty["file_ids"] as PackedInt32Array).is_empty(), "no reserve: nothing assigned")
	var no_host: Dictionary = Layout.interleave_files(PackedInt32Array(), PackedInt32Array(), 4,
			_reserve_grid(4, 4))
	assert_true((no_host["file_ids"] as PackedInt32Array).is_empty(), "no host: nothing assigned")


func test_index_order_host_ranks_are_derived_when_the_stored_array_is_empty() -> void:
	var host := _host(8, 4)
	var result: Dictionary = Layout.interleave_files(host["file_ids"], PackedInt32Array(), 4,
			_reserve_grid(8, 4))
	var ranks: PackedInt32Array = result["ranks"]
	for i in range(8):
		assert_eq(ranks[i], host["ranks"][i], "host man %d's rank is derived from array order" % i)
	_assert_no_shared_slot(result, "derived ranks")


func test_full_ranks_insertion_alternates_ranks_within_each_file() -> void:
	var host := _host(8, 4)   # 2 deep
	var result: Dictionary = Layout.interleave_ranks(host["file_ids"], host["ranks"], 4,
			_reserve_grid(8, 4))
	assert_eq(int(result["files"]), 4, "frontage holds on the ranks axis")
	var file_ids: PackedInt32Array = result["file_ids"]
	var ranks: PackedInt32Array = result["ranks"]
	for i in range(8):
		assert_eq(file_ids[i], host["file_ids"][i], "host man %d keeps his file" % i)
		assert_eq(ranks[i], 2 * host["ranks"][i], "host man %d lands on an even rank" % i)
	for i in range(8):
		assert_eq(ranks[8 + i] % 2, 1, "reserve man %d lands on an odd rank" % i)
	_assert_no_shared_slot(result, "full ranks")


func test_partial_and_surplus_ranks_insertion() -> void:
	var host := _host(8, 4)   # 2 deep
	# 2 men over 4 files: file_capacities(2, 4) centres them on files 1 and 2.
	var partial: Dictionary = Layout.interleave_ranks(host["file_ids"], host["ranks"], 4,
			_reserve_grid(2, 2))
	var p_ranks: PackedInt32Array = partial["ranks"]
	var p_files: PackedInt32Array = partial["file_ids"]
	for i in range(8):
		var m: int = 1 if (host["file_ids"][i] == 1 or host["file_ids"][i] == 2) else 0
		assert_eq(p_ranks[i], host["ranks"][i] + mini(host["ranks"][i], m),
				"host man %d shifts back only in a file that received a man" % i)
	assert_eq(p_files[8], 1, "leftmost reserve man takes the leftmost dealt file")
	assert_eq(p_ranks[8], 1, "and slots in behind its front rank")
	_assert_no_shared_slot(partial, "partial ranks")
	# 16 men over 4 files: 4 deep against 2 host ranks -- alternation, then a surplus tail.
	var surplus: Dictionary = Layout.interleave_ranks(host["file_ids"], host["ranks"], 4,
			_reserve_grid(16, 4))
	var s_ranks: PackedInt32Array = surplus["ranks"]
	assert_eq(s_ranks[8], 1, "reserve rank 0 -> 1")
	assert_eq(s_ranks[12], 3, "reserve rank 1 -> 3")
	assert_eq(s_ranks[16], 4, "reserve rank 2 continues at the rear (D_f + i)")
	assert_eq(s_ranks[20], 5, "reserve rank 3 continues at the rear")
	_assert_no_shared_slot(surplus, "surplus ranks")


func test_rear_anchor_shift_is_half_the_added_depth() -> void:
	assert_almost_eq(Layout.rear_anchor_shift(2, 4, 10.0), 10.0, 0.0001,
			"two added ranks push the centre back by one pitch")
	assert_almost_eq(Layout.rear_anchor_shift(3, 3, 10.0), 0.0, 0.0001, "no growth, no shift")


func test_interleave_files_respects_max_files_capacity() -> void:
	var host := _host(20, 40)
	var reserve_local := _reserve_grid(1, 1)
	var unbounded: Dictionary = Layout.interleave_files(host["file_ids"], host["ranks"], 40, reserve_local)
	assert_eq(int(unbounded["files"]), 42, "unbounded layout yields 42 files for k=2")
	var bounded: Dictionary = Layout.interleave_files(host["file_ids"], host["ranks"], 40, reserve_local, 41)
	assert_eq(int(bounded["files"]), 41, "bounded layout caps frontage at max_files")
	_assert_no_shared_slot(bounded, "bounded files")
