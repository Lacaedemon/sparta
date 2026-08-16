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
		UnitRef.FORMATION_NORMAL: "phalanx",
		UnitRef.FORMATION_TIGHT: "synaspismos",
		UnitRef.FORMATION_LOOSE: "pyknosis",
		UnitRef.FORMATION_SQUARE: "plinthion",
		UnitRef.FORMATION_SCHILTRON: "schiltron",
		UnitRef.FORMATION_SHIELD_WALL: "synaspismos",
		UnitRef.FORMATION_TESTUDO: "testudo",
	},
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


static func get_formation_display_name(faction_id: int, formation_mode: int, plain_name: String) -> String:
	if HISTORICAL_FORMATIONS.has(faction_id):
		var dict: Dictionary = HISTORICAL_FORMATIONS[faction_id]
		if dict.has(formation_mode):
			return "%s (%s)" % [plain_name, dict[formation_mode]]
	return plain_name
