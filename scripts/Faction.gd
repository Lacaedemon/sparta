class_name Faction
extends RefCounted
## Faction definitions, rosters, AI strategies, and historical names.

const UnitRef = preload("res://scripts/Unit.gd")

enum Type { SPARTA, ROME, CARTHAGE, MACEDON }

const FACTION_NAMES := {
	Type.SPARTA: "Sparta (Laconian)",
	Type.ROME: "Rome (Latin / Roman)",
	Type.CARTHAGE: "Carthage (Punic)",
	Type.MACEDON: "Macedon (Hellenistic)",
}

const FACTION_ROSTERS := {
	Type.SPARTA: ["Spartan Hoplites", "Skiritai", "Hippeis Cavalry", "Cretan Archers"],
	Type.ROME: ["Hastati", "Principes", "Triarii", "Equites Cavalry", "Velites"],
	Type.CARTHAGE: ["Sacred Band", "Libyan Spearmen", "Numidian Cavalry", "Balearic Slingers"],
	Type.MACEDON: ["Pezhetairoi Phalanx", "Companion Cavalry", "Hypaspists", "Agrianian Peltasts"],
}

## Every FACTION_ROSTERS name maps to one of the four spawnable loadout types
## (Battle._default_loadout()'s "Spearmen"/"Infantry"/"Archers"/"Cavalry") -- the historical
## name is flavor, this is what actually determines the unit's stats on the field.
const ROSTER_UNIT_TYPES := {
	"Spartan Hoplites": "Spearmen",
	"Skiritai": "Infantry",
	"Hippeis Cavalry": "Cavalry",
	"Cretan Archers": "Archers",
	"Hastati": "Infantry",
	"Principes": "Infantry",
	"Triarii": "Spearmen",
	"Equites Cavalry": "Cavalry",
	"Velites": "Archers",
	"Sacred Band": "Spearmen",
	"Libyan Spearmen": "Spearmen",
	"Numidian Cavalry": "Cavalry",
	"Balearic Slingers": "Archers",
	"Pezhetairoi Phalanx": "Spearmen",
	"Companion Cavalry": "Cavalry",
	"Hypaspists": "Infantry",
	"Agrianian Peltasts": "Archers",
}

## Roster names whose attested subunit differs from the loadout type's own declaration
## (Battle._default_loadout's "subunit_structure"/"subunit_size"). Keys are the same
## FACTION_ROSTERS names ROSTER_UNIT_TYPES maps; each value is a partial override merged over the
## type's declaration, so an entry naming only "subunit_size" keeps the type's declared kind.
##
## This dict exists because ROSTER_UNIT_TYPES is many-to-one exactly where it matters: five
## roster names (Spartan Hoplites, Triarii, Sacred Band, Libyan Spearmen, Pezhetairoi Phalanx)
## all resolve to "Spearmen", and a Macedonian file and a Spartan enomotia are both attested and
## different. Without a per-name layer the type declaration would flatten that distinction, which
## is precisely what docs/subunit-structure-design.md set out to capture.
##
## Only the one attested divergence is declared. Thucydides 5.68.3 puts the Spartan enomotia at
## four men wide and about eight deep -- roughly 32, a small block of files rather than a single
## file -- and the arithmetic self-checks (7 lochoi x 4 x 4 x 4 = 448, the front-rank total the
## same passage gives). The remaining four Spearmen rosters stay on the type default because the
## design note gives them no number, and inventing one would be the opposite of what the
## deliberately-undeclared Archers row establishes. Triarii is the near miss worth naming: they
## were maniples, and Polybius 6.24 divides every class into companies under two centurions, so
## "lateral_halves" is a real candidate -- but the note stops short of making that call for a
## spear-armed type, so this does too rather than reading an inference in as testimony.
const ROSTER_SUBUNIT_OVERRIDES := {
	"Spartan Hoplites": {"subunit_size": 32},
}


const HISTORICAL_FORMATIONS := {
	Type.ROME: {
		UnitRef.FORMATION_NORMAL: "acies",
		UnitRef.FORMATION_TIGHT: "densata acies",
		UnitRef.FORMATION_LOOSE: "rara acies",
		UnitRef.FORMATION_SQUARE: "agmen quadratum",
		UnitRef.FORMATION_SCHILTRON: "orbis",
		UnitRef.FORMATION_SHIELD_WALL: "scuta undique",
		UnitRef.FORMATION_TESTUDO: "testudo",
	},
	Type.SPARTA: {
		UnitRef.FORMATION_NORMAL: "pyknosis",
		UnitRef.FORMATION_TIGHT: "synaspismos",
		UnitRef.FORMATION_LOOSE: "araios",
		UnitRef.FORMATION_SQUARE: "plinthion",
		UnitRef.FORMATION_SCHILTRON: "kyklos",
		UnitRef.FORMATION_SHIELD_WALL: "phalanx",
		UnitRef.FORMATION_TESTUDO: "chelone",
	},
	Type.CARTHAGE: {
		UnitRef.FORMATION_NORMAL: "sadir",
		UnitRef.FORMATION_TIGHT: "mutabaq",
		UnitRef.FORMATION_LOOSE: "munfasil",
		UnitRef.FORMATION_SQUARE: "murabba",
		UnitRef.FORMATION_SCHILTRON: "halqa",
		UnitRef.FORMATION_SHIELD_WALL: "surs",
		UnitRef.FORMATION_TESTUDO: "muttaka",
	},
	Type.MACEDON: {
		UnitRef.FORMATION_NORMAL: "syntagma",
		UnitRef.FORMATION_TIGHT: "synaspismos",
		UnitRef.FORMATION_LOOSE: "araioma",
		UnitRef.FORMATION_SQUARE: "plinthion",
		UnitRef.FORMATION_SCHILTRON: "kyklos",
		UnitRef.FORMATION_SHIELD_WALL: "phalanx",
		UnitRef.FORMATION_TESTUDO: "chelone",
	},
}

const HISTORICAL_FORM_UP := {
	Type.ROME: {
		4: "quincunx",
		5: "acies obliqua dextra",
		6: "acies obliqua sinistra",
	},
	Type.SPARTA: {
		4: "epallax",
		5: "lophos dexios",
		6: "lophos aristeros",
	},
	Type.CARTHAGE: {
		4: "shatranj",
		5: "junah maymana",
		6: "junah maysara",
	},
	Type.MACEDON: {
		4: "epallax",
		5: "loxe phalanx",
		6: "loxe phalanx",
	},
}

const FACTION_STRATEGIES := {
	Type.ROME: "Manipular Line Rotation (acies triplex)",
	Type.SPARTA: "Phalanx Shock Push (othismos)",
	Type.CARTHAGE: "Double Envelopment (Cannae)",
	Type.MACEDON: "Hammer and Anvil (sarissa and hetairoi)",
}


static func get_faction_name(faction_id: int) -> String:
	return FACTION_NAMES.get(faction_id, "Unknown Faction")


static func get_roster(faction_id: int) -> Array:
	return FACTION_ROSTERS.get(faction_id, [])


## The spawnable loadout type (one of Battle.gd's four default-loadout "name" entries) a
## roster's historical unit name resolves to, or "" if the name isn't a known roster entry --
## e.g. a caller spawning a custom battle from `get_roster()`'s flavor names needs this to look
## up the actual stat block, since Battle._loadout_for_type() matches on the plain type name.
static func get_unit_type(roster_name: String) -> String:
	return str(ROSTER_UNIT_TYPES.get(roster_name, ""))


## The subunit-structure override for a roster name, as a scenario-spec fragment ready to merge
## over the loadout type's own declaration -- empty for a name with no divergence, which is every
## name but one today. Returns a COPY: ROSTER_SUBUNIT_OVERRIDES' values are shared dictionaries
## (GDScript's `const` freezes the binding, not the object), so handing the stored dict straight
## to a caller that merges into it would edit the table for every later spawn.
static func get_subunit_override(roster_name: String) -> Dictionary:
	var d: Dictionary = ROSTER_SUBUNIT_OVERRIDES.get(roster_name, {})
	return d.duplicate()


## "<plain name> (<historical name>)" for a faction/formation pair HISTORICAL_FORMATIONS
## covers, or the bare plain name otherwise -- e.g. a faction with no entry, or a formation
## mode a faction's entry doesn't list. HUD.gd resolves the shown unit's side through
## HUD.faction_for_team() and routes its formation button, formation menu, and info-panel
## Formation line through here; see NONE below for the "no faction configured" id.
static func get_formation_display_name(faction_id: int, formation_mode: int, plain_name: String) -> String:
	return _historicized(HISTORICAL_FORMATIONS, faction_id, formation_mode, plain_name)


## Same contract as get_formation_display_name(), for a multi-unit drag-line form-up
## distribution mode (Settings.gd's FORM_UP_DIST_CHECKERBOARD/ECHELON_RIGHT/ECHELON_LEFT,
## 4-6 -- SelectionManager._issue_form_up's own cycle) instead of a live formation mode.
static func get_form_up_display_name(faction_id: int, form_up_dist: int, plain_name: String) -> String:
	return _historicized(HISTORICAL_FORM_UP, faction_id, form_up_dist, plain_name)


## "<plain name> (<historical name>)" from `table` (HISTORICAL_FORMATIONS or
## HISTORICAL_FORM_UP), or the bare plain name when the faction or the mode has no entry.
## The shared body behind the two public helpers above, so the gloss rule below can never
## reach the formation captions and miss the form-up ones.
static func _historicized(table: Dictionary, faction_id: int, mode: int, plain_name: String) -> String:
	if not table.has(faction_id):
		return plain_name
	var dict: Dictionary = table[faction_id]
	if not dict.has(mode):
		return plain_name
	return "%s (%s)" % [_without_mode_gloss(table, mode, plain_name), str(dict[mode])]


## `plain_name` with its trailing parenthetical dropped when that parenthetical is itself
## SOME faction's name for this very `mode` -- a gloss the caller's own faction supersedes
## rather than sits beside. HUD._FORMUP_ENTRIES and SelectionManager.FORM_UP_DIST_NAMES both
## spell the checkerboard "Checkerboard (quincunx)", and quincunx is ROME's word for that
## mode, so a Spartan menu reads "Checkerboard (epallax)" rather than
## "Checkerboard (quincunx) (epallax)". A parenthetical no faction claims for the mode is a
## disambiguator, not a gloss, and survives untouched: dropping "Echelon (right leads)"'s
## would leave Macedon's two echelon modes both reading "Echelon (loxe phalanx)". The
## formation captions carry no parenthetical at all (Unit.formation_interval_label emits
## digits, "x", a unit, and a stance word), so they are never rewritten either. Matched
## case-insensitively, since the caller's plain name is prose and the table's is not.
static func _without_mode_gloss(table: Dictionary, mode: int, plain_name: String) -> String:
	if not plain_name.ends_with(")"):
		return plain_name
	var open_at: int = plain_name.rfind(" (")
	if open_at <= 0:
		return plain_name
	var gloss: String = plain_name.substr(
			open_at + 2, plain_name.length() - open_at - 3).to_lower()
	for f_id in table:
		var dict: Dictionary = table[f_id]
		if dict.has(mode) and str(dict[mode]).to_lower() == gloss:
			return plain_name.substr(0, open_at)
	return plain_name


## The faction's named historical doctrine/strategy, or "Standard Doctrine" for a faction
## FACTION_STRATEGIES doesn't list. Shown on the HUD info panel's own Doctrine line for a
## side that has a faction; no AI strategy code reads it, so it is the display label for
## whatever doctrine a future battle-AI faction profile picks, not itself a behavioral
## switch (Battle.ai_doctrine is what actually drives the enemy General).
static func get_strategy_name(faction_id: int) -> String:
	return FACTION_STRATEGIES.get(faction_id, "Standard Doctrine")


## Sentinel for "this side fights under no faction identity" -- what Battle.team_factions
## carries for a side no prebattle/custom-matchup choice named, and an id every display helper
## above already falls back on to return the bare plain name. Deliberately outside Type's own
## value range (its members start at 0), so "no faction" can never collide with a real one.
const NONE := -1

## Every Type member, in the order the prebattle picker offers them. Callers that need to walk
## the playable factions (the picker, a name lookup, a test sweep) read this rather than
## repeating the four members inline, so adding a fifth reaches all of them at once.
const ALL_TYPES := [Type.SPARTA, Type.ROME, Type.CARTHAGE, Type.MACEDON]


## The Type whose FACTION_NAMES entry matches `faction_name`, case-insensitively, accepting
## either the full display name ("Sparta (Laconian)") or its bare leading name ("Sparta").
## NONE for anything no faction claims, the empty string included. Lets a data file -- a demo
## input script, a scenario -- name a side's faction in readable text instead of hard-coding
## the enum's integer values, which is the copied-value-list drift demos/README.md warns
## about for the FORMATION_* consts.
static func type_from_name(faction_name: String) -> int:
	var needle: String = faction_name.strip_edges().to_lower()
	if needle == "":
		return NONE
	for f_id in ALL_TYPES:
		var full: String = str(FACTION_NAMES[f_id]).to_lower()
		if needle == full or needle == full.split(" (")[0]:
			return f_id
	return NONE
