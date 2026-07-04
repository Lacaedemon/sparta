extends GutTest
## OfficerRank.title_for: pure function of a unit's type flags + max_soldiers.
## Covers every branch of the dispatch (cavalry, ranged, senior/junior foot) and
## confirms the choice is stable across casualties (keyed on max_soldiers, not the
## live soldiers count).

const UnitScript = preload("res://scripts/Unit.gd")


func _unit(is_cavalry: bool, anti_cavalry: bool, is_ranged: bool, max_soldiers: int) -> Unit:
	var u := UnitScript.new()
	autofree(u)
	u.is_cavalry = is_cavalry
	u.anti_cavalry = anti_cavalry
	u.is_ranged = is_ranged
	u.max_soldiers = max_soldiers
	return u


func test_cavalry_is_decurion() -> void:
	var u := _unit(true, false, false, 80)
	assert_eq(OfficerRank.title_for(u), "Decurion")


func test_ranged_is_centurion_sagittariorum() -> void:
	var u := _unit(false, false, true, 90)
	assert_eq(OfficerRank.title_for(u), "Centurion (Sagittariorum)")


func test_large_anti_cavalry_foot_is_primus_pilus() -> void:
	var u := _unit(false, true, false, 140)
	assert_eq(OfficerRank.title_for(u), "Primus Pilus")


func test_large_line_infantry_is_pilus_prior() -> void:
	var u := _unit(false, false, false, 140)
	assert_eq(OfficerRank.title_for(u), "Pilus Prior")


func test_small_foot_unit_is_plain_centurion() -> void:
	var u := _unit(false, false, false, 120)
	assert_eq(OfficerRank.title_for(u), "Centurion")


func test_rank_is_keyed_on_max_soldiers_not_current_casualties() -> void:
	var u := _unit(false, false, false, 140)
	u.soldiers = 10   # heavily depleted
	assert_eq(OfficerRank.title_for(u), "Pilus Prior",
		"the officer title reflects the unit's intended strength, not casualty state")


func test_cavalry_beats_anti_cavalry_flag() -> void:
	# is_cavalry and anti_cavalry are not expected to both be true in practice, but
	# the dispatch order should still be well-defined: cavalry is checked first.
	var u := _unit(true, true, false, 140)
	assert_eq(OfficerRank.title_for(u), "Decurion")
