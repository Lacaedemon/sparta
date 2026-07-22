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


static func get_formation_display_name(faction_id: int, formation_mode: int, plain_name: String) -> String:
	if HISTORICAL_FORMATIONS.has(faction_id):
		var dict: Dictionary = HISTORICAL_FORMATIONS[faction_id]
		if dict.has(formation_mode):
			return "%s (%s)" % [plain_name, dict[formation_mode]]
	return plain_name
