extends GutTest
## Faction system unit tests.

const UnitScript = preload("res://scripts/Unit.gd")
const BattleScript = preload("res://scripts/Battle.gd")


func test_faction_names_and_rosters() -> void:
	assert_eq(Faction.get_faction_name(Faction.Type.SPARTA), "Sparta (Laconian)")
	assert_eq(Faction.get_faction_name(Faction.Type.ROME), "Rome (Latin / Roman)")

	var sparta_roster: Array = Faction.get_roster(Faction.Type.SPARTA)
	assert_false(sparta_roster.is_empty())
	assert_true(sparta_roster.has("Spartan Hoplites"))

	var rome_roster: Array = Faction.get_roster(Faction.Type.ROME)
	assert_true(rome_roster.has("Hastati"))


func test_every_roster_entry_resolves_to_a_real_spawnable_unit_type() -> void:
	# The historical roster name is flavor; Faction.get_unit_type() must map every one of
	# them to a real Battle._default_loadout() entry name, or a custom battle built from
	# Faction.get_roster() spawns nothing for that slot (Battle._loadout_for_type() matches
	# on this exact "name" field).
	var b := BattleScript.new()
	autofree(b)
	var real_types: Array = []
	for d in b._default_loadout():
		real_types.append(str(d["name"]))
	assert_false(real_types.is_empty(), "sanity: the default loadout isn't itself empty")

	for faction_id in [Faction.Type.SPARTA, Faction.Type.ROME, Faction.Type.CARTHAGE, Faction.Type.MACEDON]:
		for roster_name in Faction.get_roster(faction_id):
			var resolved: String = Faction.get_unit_type(roster_name)
			assert_true(real_types.has(resolved),
					"'%s' resolves to a real loadout type, got '%s'" % [roster_name, resolved])


func test_get_unit_type_returns_empty_for_an_unknown_roster_name() -> void:
	assert_eq(Faction.get_unit_type("Not A Real Unit"), "")


func test_faction_formation_display_names() -> void:
	var plain := "Checkerboard formation"
	var latin_name := Faction.get_formation_display_name(
			Faction.Type.ROME, UnitScript.FORMATION_SQUARE, plain)
	assert_eq(latin_name, "Checkerboard formation (agmen quadratum)")

	var spartan_name := Faction.get_formation_display_name(
			Faction.Type.SPARTA, UnitScript.FORMATION_TIGHT, "Tight formation")
	assert_eq(spartan_name, "Tight formation (synaspismos)")
