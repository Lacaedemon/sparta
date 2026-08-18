extends GutTest
## Unit tests for Subunits Phase 2: making declared subunit size the layout input for foot types (Spearmen).


func test_auto_files_for_subunit_size() -> void:
	assert_eq(UnitFormation.auto_files_for_subunit_size(140, 16), 9, "140 soldiers at size 16 = 9 files")
	assert_eq(UnitFormation.auto_files_for_subunit_size(70, 16), 5, "70 soldiers at size 16 = 5 files")
	assert_eq(UnitFormation.auto_files_for_subunit_size(16, 16), 1, "16 soldiers at size 16 = 1 file")
	assert_eq(UnitFormation.auto_files_for_subunit_size(0, 16), 1, "0 soldiers floors at 1 file")
	assert_eq(UnitFormation.auto_files_for_subunit_size(140, 0), 1, "0 size floors at 1 file")


func test_spearmen_full_strength_frontage() -> void:
	var u := Unit.new()
	u.max_soldiers = 140
	u.soldiers = 140
	u.subunit_structure = Unit.SubunitStructure.FILE_GROUP
	u.subunit_size = 16

	assert_eq(UnitFormation.frontage(u), 9, "Spearmen (140, size 16) has auto frontage of 9 files (ceil(140/16))")


func test_spearmen_no_per_casualty_churn() -> void:
	var u := Unit.new()
	u.max_soldiers = 140
	u.soldiers = 140
	u.subunit_structure = Unit.SubunitStructure.FILE_GROUP
	u.subunit_size = 16

	var full_frontage: int = UnitFormation.frontage(u)
	assert_eq(full_frontage, 9)

	# Single casualty does not change frontage or trigger churn
	u.soldiers = 139
	assert_eq(UnitFormation.frontage(u), 9, "Casualty from 140 to 139 keeps stable frontage of 9 files")

	u.soldiers = 128
	assert_eq(UnitFormation.frontage(u), 9, "Casualty to exactly 128 keeps stable frontage of 9 files while _ranks_closed is false")


func test_spearmen_ranks_closed_narrows_frontage() -> void:
	var u := Unit.new()
	u.max_soldiers = 140
	u.soldiers = 70
	u.subunit_structure = Unit.SubunitStructure.FILE_GROUP
	u.subunit_size = 16

	u._ranks_closed = UnitFormation.should_close_ranks(u._ranks_closed, u.soldiers, u.max_soldiers)
	assert_true(u._ranks_closed, "70 / 140 soldiers (50%) triggers _ranks_closed")
	assert_eq(UnitFormation.frontage(u), 5, "70 soldiers (50% strength) at size 16 narrows to 5 files (ceil(70/16))")

	# Single discrete step-down: losses below 50% strength do NOT continuously narrow frontage during melee
	u.soldiers = 64
	assert_eq(UnitFormation.frontage(u), 5, "64 soldiers keeps single discrete step-down frontage of 5 files")
	u.soldiers = 48
	assert_eq(UnitFormation.frontage(u), 5, "48 soldiers keeps single discrete step-down frontage of 5 files")
	u.soldiers = 32
	assert_eq(UnitFormation.frontage(u), 5, "32 soldiers keeps single discrete step-down frontage of 5 files")
	u.soldiers = 16
	assert_eq(UnitFormation.frontage(u), 5, "16 soldiers keeps single discrete step-down frontage of 5 files")


func test_other_types_keep_derived_width() -> void:
	# Infantry (120, LATERAL_HALVES)
	var inf := Unit.new()
	inf.max_soldiers = 120
	inf.soldiers = 120
	inf.subunit_structure = Unit.SubunitStructure.LATERAL_HALVES
	inf.subunit_size = 0
	assert_eq(UnitFormation.frontage(inf), UnitFormation._files(120), "Infantry keeps derived aspect ratio width")

	# Archers (90, NONE)
	var arch := Unit.new()
	arch.max_soldiers = 90
	arch.soldiers = 90
	arch.subunit_structure = Unit.SubunitStructure.NONE
	arch.subunit_size = 0
	assert_eq(UnitFormation.frontage(arch), UnitFormation._files(90), "Archers keeps derived aspect ratio width")

	# Cavalry (80, is_cavalry)
	var cav := Unit.new()
	cav.is_cavalry = true
	cav.max_soldiers = 80
	cav.soldiers = 80
	assert_eq(UnitFormation.frontage(cav), UnitFormation.cavalry_files(80), "Cavalry derives squadron frontage (9 files)")


func test_frontage_override_wins_over_subunit_size() -> void:
	var u := Unit.new()
	u.max_soldiers = 140
	u.soldiers = 140
	u.subunit_structure = Unit.SubunitStructure.FILE_GROUP
	u.subunit_size = 16
	u.frontage_override = 14

	assert_eq(UnitFormation.frontage(u), 14, "frontage_override wins over auto subunit frontage")


func test_half_width_for_soldiers_with_subunit_size() -> void:
	var spacing: float = 4.5
	var hw_spear: float = UnitFormation.half_width_for_soldiers(140, spacing, Unit.SubunitStructure.FILE_GROUP, 16)
	var expected_hw: float = (9 - 1) * 0.5 * spacing # 8 * 2.25 = 18.0
	assert_eq(hw_spear, expected_hw, "half_width for 140 Spearmen (size 16) = (9-1)/2 * 4.5 = 18.0")


func test_files_label_for_unit() -> void:
	var spearmen := Unit.new()
	spearmen.max_soldiers = 140
	spearmen.soldiers = 140
	spearmen.subunit_structure = Unit.SubunitStructure.FILE_GROUP
	spearmen.subunit_size = 16

	assert_eq(UnitFormation.files_label_for_unit(spearmen, 9), "9 files (16/file)")

	# Player frontage override suppresses per-file suffix
	spearmen.frontage_override = 12
	assert_eq(UnitFormation.files_label_for_unit(spearmen, 12), "12 files", "Overridden frontage omits (16/file)")

	# Ranks closed suppresses per-file suffix
	spearmen.frontage_override = 0
	spearmen._ranks_closed = true
	assert_eq(UnitFormation.files_label_for_unit(spearmen, 5), "5 files", "Narrowed ranks frontage omits (16/file)")

	var infantry := Unit.new()
	infantry.subunit_structure = Unit.SubunitStructure.LATERAL_HALVES

	assert_eq(UnitFormation.files_label_for_unit(infantry, 15), "15 files")



func test_scenario_frontage_parsing() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Spearmen", "count": 140, "subunit_structure": "file_group", "subunit_size": 16, "frontage": 12, "x": 400, "y": 400},
		{"team": 1, "type": "Spearmen", "count": 140, "subunit_structure": "file_group", "subunit_size": 16, "frontage_override": 14, "x": 400, "y": 600}
	]

	add_child_autofree(battle)
	await get_tree().physics_frame

	var units := get_tree().get_nodes_in_group("units")
	assert_gt(units.size(), 0)
	for u_node in units:
		var u = u_node as Unit
		if u == null:
			continue
		if u.team == 0:
			assert_eq(u.frontage_override, 12, "frontage key parsed into frontage_override")
		elif u.team == 1:
			assert_eq(u.frontage_override, 14, "frontage_override key parsed into frontage_override")

