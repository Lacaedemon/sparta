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


func test_fold_flank_to_rear_maps_nearest_rear_ranks_first() -> void:
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

	# Check the 16 soldiers from folded file 4:
	# File 4 ranks 12..15 (already near rear) should map to adjacent File 3 ranks 16..19
	for i in range(count):
		if initial_files[i] != 4:
			continue
		var old_r: int = initial_ranks[i]
		var new_f: int = out_files[i]
		var new_r: int = out_ranks[i]
		if old_r >= 12:
			assert_eq(new_f, 3, "file 4 rank %d maps to adjacent file 3" % old_r)
			assert_eq(new_r, 16 + (old_r - 12), "file 4 rank %d maps to file 3 rank %d" % [old_r, 16 + (old_r - 12)])
		elif old_r >= 8:
			assert_eq(new_f, 2, "file 4 rank %d maps to file 2" % old_r)
			assert_eq(new_r, 16 + (old_r - 8), "file 4 rank %d maps to file 2 rank %d" % [old_r, 16 + (old_r - 8)])
		elif old_r >= 4:
			assert_eq(new_f, 1, "file 4 rank %d maps to file 1" % old_r)
			assert_eq(new_r, 16 + (old_r - 4), "file 4 rank %d maps to file 1 rank %d" % [old_r, 16 + (old_r - 4)])
		else:
			assert_eq(new_f, 0, "file 4 rank %d maps to file 0" % old_r)
			assert_eq(new_r, 16 + old_r, "file 4 rank %d maps to file 0 rank %d" % [old_r, 16 + old_r])


func test_live_spearmen_reform_routes_around_formation_block() -> void:
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
	var spacing: float = u.file_pitch_wu()
	var depth: float = u.rank_pitch_wu()
	if depth < 0.0:
		depth = spacing
	var rx_min_retained: float = -(4 - 1) * 0.5 * spacing
	var rx_max_retained: float = (4 - 1) * 0.5 * spacing
	var y_rear_pre_reform: float = (16 - 1) * 0.5 * depth
	var folded_soldier_indices: Array[int] = []
	for i in range(u.soldiers):
		if u._sim_soldier_file[i] == 4:
			folded_soldier_indices.push_back(i)
	assert_eq(folded_soldier_indices.size(), 16, "exactly 16 soldiers in folded file 4")

	u.set_frontage(4)

	# Track all 16 soldiers from the folded flank file during reform
	for _frame in range(120):
		await get_tree().physics_frame
		var ang: float = u.soldier_block_world_angle()
		for i in folded_soldier_indices:
			var pos: Vector2 = u._sim_soldier_pos[i]
			var p_local: Vector2 = (pos - u.position).rotated(-ang)
			# If the soldier's lateral position enters the retained files interior (files 0..3):
			# the soldier must be entering via the rear corridor / rear ranks,
			# never cutting through the interior front/mid ranks (ranks 0..14 of the original block)!
			if p_local.x >= rx_min_retained + spacing * 0.2 and p_local.x <= rx_max_retained - spacing * 0.2:
				assert_gte(p_local.y, y_rear_pre_reform - depth * 1.5,
						"soldier %d during reform routes around rear corridor instead of penetrating interior (y=%.1f, y_rear=%.1f)" % [i, p_local.y, y_rear_pre_reform])

