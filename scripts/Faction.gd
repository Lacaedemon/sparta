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


static func get_formation_display_name(faction_id: int, formation_mode: int, plain_name: String) -> String:
	if HISTORICAL_FORMATIONS.has(faction_id):
		var dict: Dictionary = HISTORICAL_FORMATIONS[faction_id]
		if dict.has(formation_mode):
			return "%s (%s)" % [plain_name, dict[formation_mode]]
	return plain_name
