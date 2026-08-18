extends GutTest
## Unit tests for Subunits Phase 3: stop laying cavalry out as line-infantry files.
##
## Under the interim approach (does not block on the future leader model):
## - Cavalry derives its frontage from cavalry_files (Asclepiodotus 7.4 square/oblong squadron:
##   ceil(sqrt(n))) instead of line-infantry FORMATION_ASPECT _files(n).
## - Cavalry declares itself structureless (NONE, size 0).
## - Cavalry reflows row-major as a cohesive block, without persistent per-soldier file identity
##   (_sim_soldier_file / _sim_soldier_rank stay empty).

const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")


func test_cavalry_files_aspect() -> void:
	# Asclepiodotus 7.4 square/oblong squadron: ceil(sqrt(n))
	assert_eq(UnitFormation.cavalry_files(80), 9, "80 cavalry = 9 files (ceil(sqrt(80))) vs 12 from line foot _files()")
	assert_eq(UnitFormation.cavalry_files(64), 8, "64 cavalry = 8 files (ceil(sqrt(64)))")
	assert_eq(UnitFormation.cavalry_files(30), 6, "30 cavalry (Roman turma) = 6 files (ceil(sqrt(30)))")
	assert_eq(UnitFormation.cavalry_files(10), 4, "10 cavalry (dekas) = 4 files (ceil(sqrt(10)))")
	assert_eq(UnitFormation.cavalry_files(1), 1, "1 cavalry = 1 file")
	assert_eq(UnitFormation.cavalry_files(0), 1, "0 cavalry floors at 1 file")


func test_cavalry_full_strength_frontage() -> void:
	var u := UnitScript.new()
	u.is_cavalry = true
	u.max_soldiers = 80
	add_child_autofree(u)
	u.soldiers = 80

	assert_eq(UnitFormation.frontage(u), 9, "80-man Cavalry auto frontage is 9 files")


func test_cavalry_ranks_closed_narrows_frontage() -> void:
	var u := UnitScript.new()
	u.is_cavalry = true
	u.max_soldiers = 80
	add_child_autofree(u)
	u.soldiers = 40

	u._ranks_closed = UnitFormation.should_close_ranks(u._ranks_closed, u.soldiers, u.max_soldiers)
	assert_true(u._ranks_closed, "40 / 80 soldiers (50%) triggers _ranks_closed")
	assert_eq(UnitFormation.frontage(u), 4, "Narrowed frontage for 9 files is 4 files (narrowed_files(9) = 4)")


func test_cavalry_frontage_override_wins() -> void:
	var u := UnitScript.new()
	u.is_cavalry = true
	u.max_soldiers = 80
	add_child_autofree(u)
	u.soldiers = 80
	u.frontage_override = 12

	assert_eq(UnitFormation.frontage(u), 12, "Player frontage_override wins over auto cavalry frontage")


func test_cavalry_effective_file_major_reform_is_always_false() -> void:
	var u := UnitScript.new()
	u.is_cavalry = true
	u.disciplined = true
	u.file_major_reform_mode = UnitScript.ReformMode.FILE_MAJOR
	add_child_autofree(u)

	assert_false(u._effective_file_major_reform(),
		"Cavalry is structureless and always returns false for _effective_file_major_reform()")


func test_cavalry_formation_slots_does_not_populate_file_identity() -> void:
	var u := UnitScript.new()
	u.is_cavalry = true
	u.max_soldiers = 80
	add_child_autofree(u)
	u.soldiers = 80

	var slots: PackedVector2Array = u.formation_slots(u.soldiers)
	assert_eq(slots.size(), 80, "Generates 80 slots for 80 cavalry")
	assert_eq(u._sim_soldier_file.size(), 0, "Cavalry does not populate _sim_soldier_file")
	assert_eq(u._sim_soldier_rank.size(), 0, "Cavalry does not populate _sim_soldier_rank")


func test_cavalry_half_width_for_soldiers() -> void:
	var spacing: float = 20.0   # 1.0 m at 20 wu/m
	var hw: float = UnitFormation.half_width_for_soldiers(80, spacing, 0, 0, true)
	var expected_hw: float = (9 - 1) * 0.5 * spacing   # 8 * 10 = 80 wu
	assert_eq(hw, expected_hw, "half_width for 80 cavalry at 20 wu spacing = 80 wu (width 160 wu)")


func test_cavalry_spawned_from_default_loadout() -> void:
	var b := BattleScript.new()
	autofree(b)
	var loadout: Array = b._default_loadout()
	for d in loadout:
		if str(d["name"]) == "Cavalry":
			assert_false(d.has("subunit_structure"), "Cavalry declares no subunit_structure (structureless)")
			assert_false(d.has("subunit_size"), "Cavalry declares no subunit_size")
			assert_false(bool(d.get("file_major_reform_default", true)), "Cavalry file_major_reform_default is false")
