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


## Per-faction historical names for the live formation modes, keyed by UnitRef.FORMATION_*.
## Every faction carries all seven keys, so a caller may index any faction's row with any mode.
##
## The four languages are not equally documented, so the table follows an explicit sourcing
## rule rather than a uniform one:
##
##   * Latin (Rome) and Greek (Sparta, Macedon) tactical vocabulary is attested directly, in
##     Caesar and Livy and in the Greek tacticians -- Asclepiodotus, Tactica 4, "The Intervals
##     between the Soldiers", gives the three densities the LOOSE/NORMAL/TIGHT keys stand for
##     (four cubits a man, then two, then one with shields locked).
##   * Punic (Carthage) tactical vocabulary is NOT attested. No Carthaginian drill manual
##     survives, and the Phoenician-Punic lexicon records no formation names at all. So
##     Carthage's row mixes two kinds of entry, marked per line below:
##       (Pu) an attested Phoenician or Punic noun, transparently vocalized from its
##            consonantal spelling, naming the object the formation is shaped like -- which is
##            how the Latin and Greek rows are built too (orbis, testudo, plinthion, chelone).
##       (Gr) the Greek term, because Greek is the language Carthaginian armies were actually
##            described in: Polybius is the primary narrative source for their deployments.
##
## Nothing here is coined. Where Greek has exactly one word for a concept, two factions carry
## the same string (synaspismos, kyklos, araios) rather than one of them getting an invented
## synonym. Punic entries cite Krahmalkov, Phoenician-Punic Dictionary (Studia Phoenicia XV,
## Leuven 2000) by headword, together with the inscription that attests the word.
##
## An earlier revision of this table gave Carthage Classical Arabic words. Arabic postdates
## Punic by roughly a millennium and is not evidence for it, so none of them survive here.
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
		# (Pu) mhnt, "army" -- Krahmalkov s.v. MHNT; Punic CIS i 5866 's mhnt, "a member of
		# the army", and Neo-Punic KAI 120.1 rb mhnt, "head of the army". The word is the
		# host itself, not a named order; it is the closest the Punic lexicon comes.
		UnitRef.FORMATION_NORMAL: "mahanet",
		# (Gr) shields locked at a one-cubit interval -- Asclepiodotus, Tactica 4.
		UnitRef.FORMATION_TIGHT: "synaspismos",
		# (Gr) the opened-out order, four cubits a man -- Asclepiodotus, Tactica 4.
		UnitRef.FORMATION_LOOSE: "araios",
		# (Gr) an oblong body of troops -- LSJ s.v. plaision, on Thucydides' en plaisio.
		# Distinct from the tacticians' plinthion, the brick, which Sparta and Macedon carry.
		UnitRef.FORMATION_SQUARE: "plaision",
		# (Gr) troops formed in a ring -- LSJ s.v. kyklos.
		UnitRef.FORMATION_SCHILTRON: "kyklos",
		# (Pu) mgn, "shield" -- Krahmalkov s.v. MGN II; Phoenician KAI 26 A I 6/8 mgn 'l mgn,
		# "shield upon shield", which is a shield wall in the source's own words.
		UnitRef.FORMATION_SHIELD_WALL: "magen",
		# (Pu) gg, "roof" -- Krahmalkov s.v. GG; Punic IFPCO p. 109 hgg 'l 'mdm, "the roof
		# resting on columns". A testudo is a roof of shields, as chelone and testudo are
		# both the animal that carries one.
		UnitRef.FORMATION_TESTUDO: "gag",
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

## Per-faction historical names for the drag-line form-up distributions, keyed by
## Settings.FORM_UP_DIST_CHECKERBOARD/ECHELON_RIGHT/ECHELON_LEFT (4-6). Same sourcing rule as
## HISTORICAL_FORMATIONS above, and the same three keys for every faction.
##
## No ancient language has a single word for an echeloned form-up, so the two echelon entries
## name the DIRECTION instead, and each faction names it in its own idiom. The two must stay
## distinct: a caller shows these to tell the player which of the two modes is active, so one
## label serving both directions is the same defect as an empty entry.
const HISTORICAL_FORM_UP := {
	Type.ROME: {
		4: "quincunx",
		5: "acies obliqua dextra",
		6: "acies obliqua sinistra",
	},
	Type.SPARTA: {
		4: "epallax",
		# The wing that leads the staggered line. keras is an army's wing (LSJ s.v. keras),
		# and Thucydides 5.67 puts the Skiritai on the Lacedaemonian left wing, a post he
		# says is theirs alone. dexion is the right wing, euonymon the left -- the ordinary
		# Greek pair, euonymon being the euphemism ("of good name") for the unlucky side.
		# lophos, which stood here before, is a crest or ridge: a helmet plume, not a wing.
		5: "dexion keras",
		6: "euonymon keras",
	},
	Type.CARTHAGE: {
		# (Gr) crosswise, alternately -- LSJ s.v. epallax. The Arabic shatranj that stood
		# here means chess, borrowed from Sanskrit caturanga long after Carthage fell.
		4: "epallax",
		# (Gr) the leading wing, as for Sparta above. Polybius 3.113-3.114 sets out the
		# Carthaginian line at Cannae with a wing on each flank; Punic records no word for
		# either direction, so Greek carries both entries here.
		5: "dexion keras",
		6: "euonymon keras",
	},
	Type.MACEDON: {
		4: "epallax",
		# The oblique phalanx (loxe phalanx, Asclepiodotus, Tactica), refusing one wing and
		# leading with the other, with the direction given by the phalanx's own drill words
		# for its two sides: epi doru, "to the spear", is the right, and ep' aspida, "to the
		# shield", is the left (Asclepiodotus, Tactica 12.11; Xenophon, Cyropaedia 7.5.6).
		# Both entries previously read "loxe phalanx", leaving the two modes indistinguishable.
		5: "loxe phalanx epi doru",
		6: "loxe phalanx ep' aspida",
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
## mode a faction's entry doesn't list. No caller resolves a battle side's Faction.Type today
## (Battle.gd only reads FACTION_ROSTERS' flavor names at prebattle time -- see
## Faction.get_unit_type()'s doc comment); wiring HUD.gd's formation label/menu through this
## once a side's faction is tracked at runtime is tracked separately.
static func get_formation_display_name(faction_id: int, formation_mode: int, plain_name: String) -> String:
	if HISTORICAL_FORMATIONS.has(faction_id):
		var dict: Dictionary = HISTORICAL_FORMATIONS[faction_id]
		if dict.has(formation_mode):
			return "%s (%s)" % [plain_name, dict[formation_mode]]
	return plain_name


## Same contract as get_formation_display_name(), for a multi-unit drag-line form-up
## distribution mode (Settings.gd's FORM_UP_DIST_CHECKERBOARD/ECHELON_RIGHT/ECHELON_LEFT,
## 4-6 -- SelectionManager._issue_form_up's own cycle) instead of a live formation mode.
static func get_form_up_display_name(faction_id: int, form_up_dist: int, plain_name: String) -> String:
	if HISTORICAL_FORM_UP.has(faction_id):
		var dict: Dictionary = HISTORICAL_FORM_UP[faction_id]
		if dict.has(form_up_dist):
			return "%s (%s)" % [plain_name, dict[form_up_dist]]
	return plain_name


## The faction's named historical doctrine/strategy, or "Standard Doctrine" for a faction
## FACTION_STRATEGIES doesn't list. No AI strategy code reads this yet -- it's the display
## label for whatever doctrine a future battle-AI faction profile picks, not itself a
## behavioral switch.
static func get_strategy_name(faction_id: int) -> String:
	return FACTION_STRATEGIES.get(faction_id, "Standard Doctrine")
