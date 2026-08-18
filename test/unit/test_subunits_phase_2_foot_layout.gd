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

	# Cavalry (80, GROUP)
	var cav := Unit.new()
	cav.max_soldiers = 80
	cav.soldiers = 80
	cav.subunit_structure = Unit.SubunitStructure.GROUP
	cav.subunit_size = 10
	assert_eq(UnitFormation.frontage(cav), UnitFormation._files(80), "Cavalry keeps derived aspect ratio width")


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
	spearmen.subunit_structure = Unit.SubunitStructure.FILE_GROUP
	spearmen.subunit_size = 16

	assert_eq(UnitFormation.files_label_for_unit(spearmen, 9), "9 files (16/file)")
	assert_eq(UnitFormation.files_label_for_unit(spearmen, 1), "1 file (16/file)")

	var infantry := Unit.new()
	infantry.subunit_structure = Unit.SubunitStructure.LATERAL_HALVES

	assert_eq(UnitFormation.files_label_for_unit(infantry, 15), "15 files")
