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

	var carthage_name := Faction.get_formation_display_name(
			Faction.Type.CARTHAGE, UnitScript.FORMATION_SHIELD_WALL, "Shield Wall")
	assert_eq(carthage_name, "Shield Wall (magen)")

	var macedon_name := Faction.get_formation_display_name(
			Faction.Type.MACEDON, UnitScript.FORMATION_NORMAL, "Normal formation")
	assert_eq(macedon_name, "Normal formation (syntagma)")


func test_faction_form_up_and_strategy_names() -> void:
	var quincunx := Faction.get_form_up_display_name(Faction.Type.ROME, 4, "Checkerboard")
	assert_eq(quincunx, "Checkerboard (quincunx)")

	var strategy_rome := Faction.get_strategy_name(Faction.Type.ROME)
	assert_true(strategy_rome.contains("acies triplex"))

	var strategy_sparta := Faction.get_strategy_name(Faction.Type.SPARTA)
	assert_true(strategy_sparta.contains("othismos"))

	var strategy_carthage := Faction.get_strategy_name(Faction.Type.CARTHAGE)
	assert_true(strategy_carthage.contains("Cannae"))

	var strategy_macedon := Faction.get_strategy_name(Faction.Type.MACEDON)
	assert_true(strategy_macedon.contains("sarissa"))


func test_get_form_up_display_name_falls_back_to_plain_name_for_an_unlisted_mode() -> void:
	# HISTORICAL_FORM_UP only covers the CHECKERBOARD/ECHELON_RIGHT/ECHELON_LEFT modes (4-6);
	# any other form-up distribution (or an unknown faction) must return the bare plain name,
	# same fallback contract as get_formation_display_name().
	var plain := "Equal depth"
	assert_eq(Faction.get_form_up_display_name(Faction.Type.ROME, 0, plain), plain)


func test_get_strategy_name_falls_back_to_standard_doctrine_for_an_unknown_faction() -> void:
	assert_eq(Faction.get_strategy_name(-1), "Standard Doctrine")


const ALL_FACTIONS: Array = [
	Faction.Type.SPARTA, Faction.Type.ROME, Faction.Type.CARTHAGE, Faction.Type.MACEDON,
]

## The formation modes every faction's HISTORICAL_FORMATIONS row must cover, and the form-up
## distributions (Settings.FORM_UP_DIST_CHECKERBOARD/ECHELON_RIGHT/ECHELON_LEFT) every
## HISTORICAL_FORM_UP row must cover. Pinned here rather than read back off the table so a
## row that silently loses a key fails instead of shrinking the expectation with it.
const EXPECTED_FORMATION_KEYS: Array = [
	UnitScript.FORMATION_NORMAL,
	UnitScript.FORMATION_TIGHT,
	UnitScript.FORMATION_LOOSE,
	UnitScript.FORMATION_SQUARE,
	UnitScript.FORMATION_SCHILTRON,
	UnitScript.FORMATION_SHIELD_WALL,
	UnitScript.FORMATION_TESTUDO,
]
const EXPECTED_FORM_UP_KEYS: Array = [4, 5, 6]


func test_every_faction_row_carries_exactly_the_expected_keys() -> void:
	# get_formation_display_name()/get_form_up_display_name() fall back to the bare plain name
	# for a mode a faction's row doesn't list, so a dropped key degrades silently into "no
	# historical name for this faction" rather than erroring. Pin the shape instead.
	for faction_id in ALL_FACTIONS:
		var formations: Dictionary = Faction.HISTORICAL_FORMATIONS[faction_id]
		assert_eq(formations.keys().size(), EXPECTED_FORMATION_KEYS.size(),
				"faction %d lists exactly the expected formation modes" % faction_id)
		for mode in EXPECTED_FORMATION_KEYS:
			assert_true(formations.has(mode),
					"faction %d names formation mode %d" % [faction_id, mode])

		var form_up: Dictionary = Faction.HISTORICAL_FORM_UP[faction_id]
		assert_eq(form_up.keys().size(), EXPECTED_FORM_UP_KEYS.size(),
				"faction %d lists exactly the expected form-up modes" % faction_id)
		for dist in EXPECTED_FORM_UP_KEYS:
			assert_true(form_up.has(dist),
					"faction %d names form-up distribution %d" % [faction_id, dist])


func test_no_historical_name_is_blank() -> void:
	# An empty (or whitespace-only) entry renders as "Tight formation ()", which reads as a
	# bug rather than as a missing translation -- catch it here instead of on screen.
	var tables: Array = [Faction.HISTORICAL_FORMATIONS, Faction.HISTORICAL_FORM_UP]
	for table in tables:
		for faction_id in table:
			for mode in table[faction_id]:
				var label: String = str(table[faction_id][mode])
				assert_false(label.strip_edges().is_empty(),
						"faction %d mode %d has a non-blank historical name" % [faction_id, mode])

	for faction_id in ALL_FACTIONS:
		assert_false(Faction.get_strategy_name(faction_id).strip_edges().is_empty(),
				"faction %d has a non-blank strategy name" % faction_id)
		assert_false(Faction.get_faction_name(faction_id).strip_edges().is_empty(),
				"faction %d has a non-blank display name" % faction_id)


func test_a_factions_own_labels_are_all_distinct() -> void:
	# Within one faction, every mode must be tellable from every other: these strings exist to
	# say WHICH mode is active, so a label serving two modes is as useless as a blank one.
	# Macedon carried one string for both echelon directions before this check existed.
	# Across factions the strings may repeat -- Greek has one word for locked shields, and
	# Sparta, Carthage and Macedon all use it.
	var tables: Array = [Faction.HISTORICAL_FORMATIONS, Faction.HISTORICAL_FORM_UP]
	for table in tables:
		for faction_id in table:
			var seen: Dictionary = {}
			for mode in table[faction_id]:
				var label: String = str(table[faction_id][mode])
				assert_false(seen.has(label),
						"faction %d reuses the label '%s' for mode %d and mode %s"
								% [faction_id, label, mode, str(seen.get(label, ""))])
				seen[label] = mode


func test_macedon_echelon_directions_have_distinct_labels() -> void:
	# The oblique phalanx refuses one wing; which wing is the whole content of the mode, so
	# each direction names it with the phalanx's own drill word for that side.
	var right := Faction.get_form_up_display_name(Faction.Type.MACEDON, 5, "Echelon right")
	var left := Faction.get_form_up_display_name(Faction.Type.MACEDON, 6, "Echelon left")
	assert_eq(right, "Echelon right (loxe phalanx epi doru)")
	assert_eq(left, "Echelon left (loxe phalanx ep' aspida)")
	assert_ne(right, left)


func test_sparta_echelon_labels_name_the_wing_not_the_helmet_crest() -> void:
	# keras is an army's wing; lophos, which stood here before, is a crest or ridge.
	assert_eq(Faction.HISTORICAL_FORM_UP[Faction.Type.SPARTA][5], "dexion keras")
	assert_eq(Faction.HISTORICAL_FORM_UP[Faction.Type.SPARTA][6], "euonymon keras")


func test_carthage_names_are_punic_or_greek_not_arabic() -> void:
	# Punic where the Phoenician-Punic lexicon has a word (mahanet, magen, gag), Greek where it
	# has none. The Classical Arabic set this row once carried is a different language with no
	# bearing on the usage of a Carthaginian army, which ended with the city in 146 BC. All
	# seven are pinned, so reverting any one of them is a test failure rather than a silent
	# regression.
	var carthage: Dictionary = Faction.HISTORICAL_FORMATIONS[Faction.Type.CARTHAGE]
	assert_eq(carthage[UnitScript.FORMATION_NORMAL], "mahanet")
	assert_eq(carthage[UnitScript.FORMATION_TIGHT], "synaspismos")
	assert_eq(carthage[UnitScript.FORMATION_LOOSE], "araios")
	assert_eq(carthage[UnitScript.FORMATION_SQUARE], "plaision")
	assert_eq(carthage[UnitScript.FORMATION_SCHILTRON], "kyklos")
	assert_eq(carthage[UnitScript.FORMATION_SHIELD_WALL], "magen")
	assert_eq(carthage[UnitScript.FORMATION_TESTUDO], "gag")

	var form_up: Dictionary = Faction.HISTORICAL_FORM_UP[Faction.Type.CARTHAGE]
	assert_eq(form_up[4], "epallax")
	assert_eq(form_up[5], "dexion keras")
	assert_eq(form_up[6], "euonymon keras")
