extends GutTest

const SPAWN := Vector2(600, 420)
var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func test_fold_flank_to_rear_preserves_retained_files() -> void:
	var count := 80
	var old_files := 5
	var new_files := 4
	var old_capacities: PackedInt32Array = UnitFormation.file_capacities(count, old_files)
	var initial_files: PackedInt32Array = UnitFormation.file_ids_in_index_order(old_capacities)
	var initial_ranks: PackedInt32Array = PackedInt32Array()
	initial_ranks.resize(count)
	var seen := {}
	for i in range(count):
		var f: int = initial_files[i]
		var d: int = int(seen.get(f, 0))
		seen[f] = d + 1
		initial_ranks[i] = d

	var res: Dictionary = UnitFormation.fold_flank_to_rear(initial_files, initial_ranks, new_files)
	var out_files: PackedInt32Array = res["file_ids"]
	var out_ranks: PackedInt32Array = res["ranks"]

	assert_eq(out_files.size(), count)
	assert_eq(out_ranks.size(), count)

	var unchanged_count := 0
	for i in range(count):
		if initial_files[i] < new_files and initial_ranks[i] < 20:
			if out_files[i] == initial_files[i] and out_ranks[i] == initial_ranks[i]:
				unchanged_count += 1
	assert_eq(unchanged_count, 64, "all 64 men in retained files 0..3 stay in their exact file and rank")

	var counts := [0, 0, 0, 0]
	for i in range(count):
		var f: int = out_files[i]
		assert_lt(f, new_files)
		counts[f] += 1
	assert_eq(counts, [20, 20, 20, 20], "each of the 4 files now holds exactly 20 soldiers")


func test_peel_rear_to_flank_preserves_retained_files() -> void:
	var count := 80
	var old_files := 4
	var new_files := 5
	var old_capacities: PackedInt32Array = UnitFormation.file_capacities(count, old_files)
	var initial_files: PackedInt32Array = UnitFormation.file_ids_in_index_order(old_capacities)
	var initial_ranks: PackedInt32Array = PackedInt32Array()
	initial_ranks.resize(count)
	var seen := {}
	for i in range(count):
		var f: int = initial_files[i]
		var d: int = int(seen.get(f, 0))
		seen[f] = d + 1
		initial_ranks[i] = d

	var res: Dictionary = UnitFormation.peel_rear_to_flank(initial_files, initial_ranks, new_files)
	var out_files: PackedInt32Array = res["file_ids"]
	var out_ranks: PackedInt32Array = res["ranks"]

	assert_eq(out_files.size(), count)
	assert_eq(out_ranks.size(), count)

	var unchanged_count := 0
	for i in range(count):
		if initial_files[i] < old_files and initial_ranks[i] < 16:
			if out_files[i] == initial_files[i] and out_ranks[i] == initial_ranks[i]:
				unchanged_count += 1
	assert_eq(unchanged_count, 64, "all 64 men in ranks 0..15 stay in their exact file and rank")

	var counts := [0, 0, 0, 0, 0]
	for i in range(count):
		var f: int = out_files[i]
		assert_lt(f, new_files)
		counts[f] += 1
	assert_eq(counts, [16, 16, 16, 16, 16], "each of the 5 files now holds exactly 16 soldiers")


func test_file_disruption_improvement_over_whole_block_relabel() -> void:
	var count := 80
	var old_files := 9
	var new_files := 8
	var spacing := 20.0

	var old_capacities: PackedInt32Array = UnitFormation.file_capacities(count, old_files)
	var initial_files: PackedInt32Array = UnitFormation.file_ids_in_index_order(old_capacities)
	var initial_ranks: PackedInt32Array = PackedInt32Array()
	initial_ranks.resize(count)
	var seen := {}
	for i in range(count):
		var f: int = initial_files[i]
		var d: int = int(seen.get(f, 0))
		seen[f] = d + 1
		initial_ranks[i] = d

	var old_slots: PackedVector2Array = UnitFormation.file_major_block_slots(
			initial_files, old_files, spacing, -1.0, initial_ranks)

	# 1. Whole-block relabel
	var new_capacities: PackedInt32Array = UnitFormation.file_capacities(count, new_files)
	var relabel_files: PackedInt32Array = UnitFormation.deal_file_ids_by_lateral_order(old_slots, new_capacities)

	# 2. Subunit reform
	var subunit_res: Dictionary = UnitFormation.subunit_reform_files(
			initial_files, initial_ranks, new_files)
	var sub_files: PackedInt32Array = subunit_res["file_ids"]

	var files_changed_relabel := 0
	var files_changed_subunit := 0
	for i in range(count):
		if initial_files[i] != relabel_files[i]:
			files_changed_relabel += 1
		if initial_files[i] != sub_files[i]:
			files_changed_subunit += 1

	assert_lt(files_changed_subunit, files_changed_relabel,
			"subunit reform changes far fewer soldier file assignments (%d vs %d)" % [files_changed_subunit, files_changed_relabel])
	assert_eq(files_changed_subunit, 8, "exactly 8 soldiers in the folded flank file change file assignment")
	assert_gt(files_changed_relabel, 30, "whole-block relabel disrupts most soldiers in the formation")


func test_live_spearmen_unit_narrowing_preserves_file_identity() -> void:
	Replay.forced_seed = 912
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y,
			"count": 80, "facing": [0, 1]}
	]
	add_child_autofree(_battle)
	for _i in range(10):
		await get_tree().physics_frame

	var u: Unit = _battle._units.get_child(0)
	assert_true(u.unit_name.begins_with("Spearmen"))
	const UnitScript = preload("res://scripts/Unit.gd")
	assert_eq(u.subunit_structure, UnitScript.SubunitStructure.FILE_GROUP)
	var initial_files_count: int = UnitFormation.frontage(u)
	assert_eq(initial_files_count, 5, "80 spearmen on 16-man files default to 5 files")

	var _initial_slots: PackedVector2Array = u.formation_slots(u.soldiers)
	var files_before: PackedInt32Array = u._sim_soldier_file.duplicate()
	var ranks_before: PackedInt32Array = u._sim_soldier_rank.duplicate()
	if ranks_before.is_empty():
		var seen := {}
		ranks_before.resize(u.soldiers)
		for i in range(u.soldiers):
			var f: int = files_before[i]
			var d: int = int(seen.get(f, 0))
			seen[f] = d + 1
			ranks_before[i] = d

	u.set_frontage(4)
	var _new_slots: PackedVector2Array = u.formation_slots(u.soldiers)
	var files_after: PackedInt32Array = u._sim_soldier_file
	var ranks_after: PackedInt32Array = u._sim_soldier_rank

	var retained_unchanged := 0
	for i in range(u.soldiers):
		if files_before[i] < 4 and ranks_before[i] < 20:
			if files_after[i] == files_before[i] and ranks_after[i] == ranks_before[i]:
				retained_unchanged += 1

	assert_eq(retained_unchanged, 64, "all 64 men in retained files 0..3 preserved their exact file and rank")
