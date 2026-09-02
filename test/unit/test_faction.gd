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

## Stand-in for an absent entry, so a .get() miss fails its assertion with a readable
## "(missing)" on the left rather than aborting the test the way indexing a gone key does.
const MISSING := "(missing)"


func test_every_faction_row_carries_exactly_the_expected_keys() -> void:
	# get_formation_display_name()/get_form_up_display_name() fall back to the bare plain name
	# for a mode a faction's row doesn't list, so a dropped key degrades silently into "no
	# historical name for this faction" rather than erroring. Pin the shape instead.
	for faction_id in ALL_FACTIONS:
		# Assert the row exists before indexing it. Indexing a missing key aborts the test with
		# an engine error, which reports a removed faction row as a broken test rather than as
		# the failing assertion it is; .get() with an empty default keeps the size check below
		# as the thing that fails, and it names the faction.
		assert_true(Faction.HISTORICAL_FORMATIONS.has(faction_id),
				"HISTORICAL_FORMATIONS carries a row for faction %d" % faction_id)
		var formations: Dictionary = Faction.HISTORICAL_FORMATIONS.get(faction_id, {})
		assert_eq(formations.keys().size(), EXPECTED_FORMATION_KEYS.size(),
				"faction %d lists exactly the expected formation modes" % faction_id)
		for mode in EXPECTED_FORMATION_KEYS:
			assert_true(formations.has(mode),
					"faction %d names formation mode %d" % [faction_id, mode])

		assert_true(Faction.HISTORICAL_FORM_UP.has(faction_id),
				"HISTORICAL_FORM_UP carries a row for faction %d" % faction_id)
		var form_up: Dictionary = Faction.HISTORICAL_FORM_UP.get(faction_id, {})
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
			# faction_id came out of this table, so the row is present by construction -- no
			# has() guard needed here, unlike the tests that index a row by a named faction.
			var row: Dictionary = table[faction_id]
			for mode in row:
				var label: String = str(row[mode])
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
			# Row present by construction, as above.
			var row: Dictionary = table[faction_id]
			var seen: Dictionary = {}
			for mode in row:
				var label: String = str(row[mode])
				# Double quotes around the label: a single-quoted %s is ambiguous for a label that
				# contains an apostrophe, and one of them does (ep' aspida). Single-quoted GDScript
				# string so the double quotes need no escaping.
				assert_false(seen.has(label),
						'faction %d reuses the label "%s" for mode %d and mode %d'
								% [faction_id, label, mode, int(seen.get(label, -1))])
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
	assert_true(Faction.HISTORICAL_FORM_UP.has(Faction.Type.SPARTA),
			"HISTORICAL_FORM_UP carries a Sparta row")
	var sparta: Dictionary = Faction.HISTORICAL_FORM_UP.get(Faction.Type.SPARTA, {})
	assert_eq(sparta.get(5, MISSING), "dexion keras")
	assert_eq(sparta.get(6, MISSING), "euonymon keras")


func test_carthage_names_are_punic_or_greek_not_arabic() -> void:
	# Punic where the Phoenician-Punic lexicon has a word (mahanet, magen, gag), Greek where it
	# has none. The Classical Arabic set this row once carried is a different language with no
	# bearing on the usage of a Carthaginian army, which ended with the city in 146 BC. All
	# seven are pinned, so reverting any one of them is a test failure rather than a silent
	# regression.
	assert_true(Faction.HISTORICAL_FORMATIONS.has(Faction.Type.CARTHAGE),
			"HISTORICAL_FORMATIONS carries a Carthage row")
	var carthage: Dictionary = Faction.HISTORICAL_FORMATIONS.get(Faction.Type.CARTHAGE, {})
	assert_eq(carthage.get(UnitScript.FORMATION_NORMAL, MISSING), "mahanet")
	assert_eq(carthage.get(UnitScript.FORMATION_TIGHT, MISSING), "synaspismos")
	assert_eq(carthage.get(UnitScript.FORMATION_LOOSE, MISSING), "araios")
	assert_eq(carthage.get(UnitScript.FORMATION_SQUARE, MISSING), "plaision")
	assert_eq(carthage.get(UnitScript.FORMATION_SCHILTRON, MISSING), "kyklos")
	assert_eq(carthage.get(UnitScript.FORMATION_SHIELD_WALL, MISSING), "magen")
	assert_eq(carthage.get(UnitScript.FORMATION_TESTUDO, MISSING), "gag")

	assert_true(Faction.HISTORICAL_FORM_UP.has(Faction.Type.CARTHAGE),
			"HISTORICAL_FORM_UP carries a Carthage row")
	var form_up: Dictionary = Faction.HISTORICAL_FORM_UP.get(Faction.Type.CARTHAGE, {})
	assert_eq(form_up.get(4, MISSING), "epallax")
	assert_eq(form_up.get(5, MISSING), "dexion keras")
	assert_eq(form_up.get(6, MISSING), "euonymon keras")


## The label strings HISTORICAL_FORMATIONS repeats across faction rows, and the number of rows
## each stands in. The doc block above that table states this same set in prose, so the two
## have to move together; this constant pins the derived side of that pair.
const EXPECTED_CROSS_FACTION_SHARED_LABELS := {
	"synaspismos": 3,
	"kyklos": 3,
	"plinthion": 2,
	"phalanx": 2,
	"chelone": 2,
	"araios": 2,
}

## The same, for HISTORICAL_FORM_UP. Kept as its own constant because the two tables are
## counted separately: the doc block states one inventory per table, and a label shared in
## one of them says nothing about the other.
const EXPECTED_CROSS_FACTION_SHARED_FORM_UP_LABELS := {
	"epallax": 3,
	"dexion keras": 2,
	"euonymon keras": 2,
}


## Sorted "label=count" rows. Compared as a string rather than by Dictionary equality so the
## assertion means the same thing on any engine version and a mismatch prints both sides.
func _shared_label_summary(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var rows := PackedStringArray()
	for k in keys:
		rows.append("%s=%d" % [str(k), int(counts[k])])
	return ", ".join(rows)


## Every label a table uses in more than one faction row, mapped to the number of rows it
## stands in. Counted per ROW rather than per entry: a label repeated inside a single faction
## is a different defect, and test_a_factions_own_labels_are_all_distinct already forbids it.
func _cross_faction_shared_labels(table: Dictionary) -> Dictionary:
	var row_counts: Dictionary = {}
	for faction_id in table:
		var row: Dictionary = table[faction_id]
		var counted_in_this_row: Dictionary = {}
		for mode in row:
			var label: String = str(row[mode])
			if counted_in_this_row.has(label):
				continue
			counted_in_this_row[label] = true
			row_counts[label] = int(row_counts.get(label, 0)) + 1

	var shared: Dictionary = {}
	for label in row_counts:
		if int(row_counts[label]) > 1:
			shared[label] = row_counts[label]
	return shared


func test_cross_faction_shared_labels_match_the_doc_block() -> void:
	var derived := _cross_faction_shared_labels(Faction.HISTORICAL_FORMATIONS)
	assert_eq(_shared_label_summary(derived),
			_shared_label_summary(EXPECTED_CROSS_FACTION_SHARED_LABELS),
			"Cross-faction shared labels changed in HISTORICAL_FORMATIONS. The doc block above "
					+ "that table in scripts/Faction.gd names this set in prose, with a row count "
					+ "per string -- update the paragraph that opens Six strings repeat in this "
					+ "table, then update this expectation.")


func test_cross_faction_shared_form_up_labels_match_the_doc_block() -> void:
	var derived := _cross_faction_shared_labels(Faction.HISTORICAL_FORM_UP)
	assert_eq(_shared_label_summary(derived),
			_shared_label_summary(EXPECTED_CROSS_FACTION_SHARED_FORM_UP_LABELS),
			"Cross-faction shared labels changed in HISTORICAL_FORM_UP. That table has its own "
					+ "inventory in the doc block above HISTORICAL_FORMATIONS in scripts/Faction.gd "
					+ "-- update the paragraph that opens HISTORICAL_FORM_UP below repeats three "
					+ "strings of its own, then update this expectation.")


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
	# checkerboard with ROME's own name for the mode, so every other side must read its own
	# term INSTEAD of Rome's, not after it. The behaviour under test is that replacement, not
	# any particular lexeme, so both the label and each expectation come from the live table.
	var checkerboard := 4
	var rome_term: String = Faction.HISTORICAL_FORM_UP[Faction.Type.ROME][checkerboard]
	var label := "Checkerboard (%s)" % rome_term
	for faction in [Faction.Type.ROME, Faction.Type.CARTHAGE, Faction.Type.SPARTA]:
		var own_term: String = Faction.HISTORICAL_FORM_UP[faction][checkerboard]
		assert_eq(Faction.get_form_up_display_name(faction, checkerboard, label),
				"Checkerboard (%s)" % own_term,
				"each side reads its own checkerboard term in place of Rome's")


func test_a_parenthetical_no_faction_claims_survives() -> void:
	# "(right leads)" is a disambiguator, not a historical gloss: no faction's echelon entry
	# spells it, so it must stay. Dropping it would leave Macedon's two echelon modes both
	# reading "Echelon (loxe phalanx)", with nothing left to tell right from left.
	assert_eq(Faction.get_form_up_display_name(
			Faction.Type.MACEDON, 5, "Echelon (right leads)"),
			"Echelon (right leads) (loxe phalanx epi doru)")
	assert_eq(Faction.get_form_up_display_name(
			Faction.Type.MACEDON, 6, "Echelon (left leads)"),
			"Echelon (left leads) (loxe phalanx ep' aspida)")


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


func test_a_name_with_no_separator_before_its_parenthesis_is_left_whole() -> void:
	# The gloss scan needs a " (" separator to know where the plain part ends. Without one
	# there is nothing to strip, so the whole name is kept and the term is appended after it.
	assert_eq(Faction.get_form_up_display_name(
			Faction.Type.ROME, 4, "Checkerboard(quincunx)"),
			"Checkerboard(quincunx) (quincunx)")
