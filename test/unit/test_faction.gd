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
	assert_eq(carthage_name, "Shield Wall (surs)")

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


func test_none_is_outside_the_type_enums_own_value_range() -> void:
	# NONE marks a side with no faction; a battle carries it for both teams unless a
	# prebattle choice named one, so it must never collide with a real Type value.
	assert_false(Faction.ALL_TYPES.has(Faction.NONE))
	for f_id in Faction.ALL_TYPES:
		assert_ne(f_id, Faction.NONE)


func test_none_renders_the_plain_name_through_every_display_helper() -> void:
	assert_eq(Faction.get_formation_display_name(
			Faction.NONE, UnitScript.FORMATION_NORMAL, "0.45 m"), "0.45 m")
	assert_eq(Faction.get_form_up_display_name(Faction.NONE, 4, "Checkerboard"), "Checkerboard")
	assert_eq(Faction.get_strategy_name(Faction.NONE), "Standard Doctrine")


func test_all_types_covers_every_named_faction() -> void:
	assert_eq(Faction.ALL_TYPES.size(), Faction.FACTION_NAMES.size(),
			"ALL_TYPES enumerates exactly the factions FACTION_NAMES names")
	for f_id in Faction.ALL_TYPES:
		assert_true(Faction.FACTION_NAMES.has(f_id))


func test_type_from_name_accepts_the_full_and_the_bare_display_name() -> void:
	for f_id in Faction.ALL_TYPES:
		var full: String = Faction.get_faction_name(f_id)
		assert_eq(Faction.type_from_name(full), f_id, "the full name resolves")
		assert_eq(Faction.type_from_name(full.split(" (")[0]), f_id, "the bare name resolves")


func test_type_from_name_is_case_and_whitespace_insensitive() -> void:
	assert_eq(Faction.type_from_name("  sPaRtA  "), Faction.Type.SPARTA)
	assert_eq(Faction.type_from_name("ROME (LATIN / ROMAN)"), Faction.Type.ROME)


func test_type_from_name_returns_none_for_an_unclaimed_name() -> void:
	assert_eq(Faction.type_from_name("Atlantis"), Faction.NONE)
	assert_eq(Faction.type_from_name(""), Faction.NONE)
	assert_eq(Faction.type_from_name("   "), Faction.NONE)
	# A prefix that isn't the whole bare name is NOT a match -- a data file naming "Spar"
	# is a typo, and resolving it silently would record a clip claiming a faction nobody wrote.
	assert_eq(Faction.type_from_name("Spar"), Faction.NONE)


func test_another_factions_gloss_is_replaced_rather_than_doubled() -> void:
	# HUD.gd's form-up menu label and SelectionManager.FORM_UP_DIST_NAMES both spell the
	# checkerboard "Checkerboard (quincunx)" -- and quincunx is ROME's own name for the mode,
	# so every other side must read its own term INSTEAD of Rome's, not after it.
	assert_eq(Faction.get_form_up_display_name(
			Faction.Type.ROME, 4, "Checkerboard (quincunx)"), "Checkerboard (quincunx)")
	assert_eq(Faction.get_form_up_display_name(
			Faction.Type.CARTHAGE, 4, "Checkerboard (quincunx)"), "Checkerboard (shatranj)")
	assert_eq(Faction.get_form_up_display_name(
			Faction.Type.SPARTA, 4, "Checkerboard (quincunx)"), "Checkerboard (epallax)")


func test_a_parenthetical_no_faction_claims_survives() -> void:
	# "(right leads)" is a disambiguator, not a historical gloss: no faction's echelon entry
	# spells it, so it must stay. Dropping it would leave Macedon's two echelon modes both
	# reading "Echelon (loxe phalanx)", with nothing left to tell right from left.
	assert_eq(Faction.get_form_up_display_name(
			Faction.Type.MACEDON, 5, "Echelon (right leads)"),
			"Echelon (right leads) (loxe phalanx)")
	assert_eq(Faction.get_form_up_display_name(
			Faction.Type.MACEDON, 6, "Echelon (left leads)"),
			"Echelon (left leads) (loxe phalanx)")


func test_a_gloss_is_only_stripped_when_it_names_the_same_mode() -> void:
	# "phalanx" is Sparta's SHIELD_WALL name, so the tables do claim the term -- but not for
	# the checkerboard, so a plain label ending in it is left alone rather than rewritten.
	assert_eq(Faction.get_form_up_display_name(
			Faction.Type.SPARTA, 4, "Wedge (phalanx)"), "Wedge (phalanx) (epallax)")


func test_a_formation_caption_is_never_rewritten() -> void:
	# Formation captions carry no parenthetical of their own (interval, "x", unit, stance
	# word), so the gloss rule can never eat part of one -- pin the shapes the HUD passes in.
	assert_eq(Faction.get_formation_display_name(
			Faction.Type.SPARTA, UnitScript.FORMATION_TIGHT, "0.45 m locked"),
			"0.45 m locked (synaspismos)")
	assert_eq(Faction.get_formation_display_name(
			Faction.Type.ROME, UnitScript.FORMATION_NORMAL, "1.2 m x 0.9 m"),
			"1.2 m x 0.9 m (acies)")
