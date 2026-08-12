extends GutTest
## Custom battle prebattle unit selection screen tests.

const PrebattleScreenScript = preload("res://scripts/PrebattleScreen.gd")
const FactionScript = preload("res://scripts/Faction.gd")


func test_prebattle_screen_roster_configuration() -> void:
	var screen := PrebattleScreenScript.new()
	add_child_autofree(screen)

	assert_eq(screen.team_0_faction, FactionScript.Type.SPARTA)
	assert_eq(screen.team_1_faction, FactionScript.Type.ROME)

	assert_false(screen.team_0_roster.is_empty(), "team 0 roster starts populated")
	assert_false(screen.team_1_roster.is_empty(), "team 1 roster starts populated")

	var orig_size := screen.team_0_roster.size()
	screen.add_team_0_unit()
	assert_eq(screen.team_0_roster.size(), orig_size + 1)

	screen.remove_team_0_unit(0)
	assert_eq(screen.team_0_roster.size(), orig_size)


func test_start_button_disables_when_a_roster_empties_and_reenables_when_refilled() -> void:
	# A battle with one side already empty ends on its very first tick (Battle._check_victory
	# sees that side never had anything in play) -- the Start button must not be pressable
	# in that state.
	var screen := PrebattleScreenScript.new()
	add_child_autofree(screen)

	assert_false(screen._start_btn.disabled, "both rosters start populated, so Start is enabled")

	while not screen.team_0_roster.is_empty():
		screen.remove_team_0_unit(0)
	assert_true(screen._start_btn.disabled, "Start disables once team 0's roster is emptied")

	screen.add_team_0_unit()
	assert_false(screen._start_btn.disabled, "Start re-enables once team 0 has a unit again")

	while not screen.team_1_roster.is_empty():
		screen.remove_team_1_unit(0)
	assert_true(screen._start_btn.disabled, "Start disables once team 1's roster is emptied too")
