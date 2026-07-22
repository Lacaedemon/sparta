extends GutTest
## Faction system unit tests (#875).

const UnitScript = preload("res://scripts/Unit.gd")


func test_faction_names_and_rosters() -> void:
	assert_eq(Faction.get_faction_name(Faction.Type.SPARTA), "Sparta (Laconian)")
	assert_eq(Faction.get_faction_name(Faction.Type.ROME), "Rome (Latin / Roman)")

	var sparta_roster: Array = Faction.get_roster(Faction.Type.SPARTA)
	assert_false(sparta_roster.is_empty())
	assert_true(sparta_roster.has("Spartan Hoplites"))

	var rome_roster: Array = Faction.get_roster(Faction.Type.ROME)
	assert_true(rome_roster.has("Hastati"))


func test_faction_formation_display_names() -> void:
	var plain := "Checkerboard formation"
	var latin_name := Faction.get_formation_display_name(
			Faction.Type.ROME, UnitScript.FORMATION_SQUARE, plain)
	assert_eq(latin_name, "Checkerboard formation (agmen quadratum)")

	var spartan_name := Faction.get_formation_display_name(
			Faction.Type.SPARTA, UnitScript.FORMATION_TIGHT, "Tight formation")
	assert_eq(spartan_name, "Tight formation (synaspismos)")
