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
