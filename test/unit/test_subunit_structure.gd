extends GutTest
## Phase 1 of docs/subunit-structure-design.md: a unit type DECLARES the subunit its doctrine
## organises it into, and nothing reads the declaration for layout.
##
## Two things these tests are shaped around, both of which a looser test would miss.
##
## First, Battle._default_loadout() is an ARMY ROSTER walked `loadout[i % size]`, not a type
## registry -- it holds two byte-identical Cavalry entries, which is why the default battle is
## 5v5 with two cavalry regiments. Every assertion below reaches the roster array or the
## SPAWNED regiments directly and is keyed by index or uid; none goes through
## Battle._loadout_for_type(), whose first-match lookup answers from the first Cavalry entry
## and would report a declaration missing from the second as present.
##
## Second, "inert" is the actual claim of this phase, so it is asserted rather than assumed:
## test_the_declaration_is_inert_for_layout pins that a unit's frontage is unchanged by any
## declared value.

const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")
const DemoStateScript = preload("res://tools/demo/DemoState.gd")

var _battle: Node = null


func after_each() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


# --- the roster's own declarations ----------------------------------------

func test_every_loadout_entry_declares_a_subunit_or_deliberately_declares_none() -> void:
	# Indexed rather than name-keyed: the two Cavalry entries share a name, so a by-name
	# check would collapse them and pass on a key set on only one of the two.
	var b := BattleScript.new()
	autofree(b)
	var loadout: Array = b._default_loadout()
	assert_eq(loadout.size(), 5, "sanity: the roster is spearmen/infantry/archers/cav/cav")

	var expected := [
		{"name": "Spearmen", "structure": "file_group", "size": 16},
		{"name": "Infantry", "structure": "lateral_halves", "size": 0},
		{"name": "Archers", "structure": null, "size": 0},
		{"name": "Cavalry", "structure": "group", "size": 10},
		{"name": "Cavalry", "structure": "group", "size": 10},
	]
	for i in range(expected.size()):
		var entry: Dictionary = loadout[i]
		var want: Dictionary = expected[i]
		assert_eq(str(entry["name"]), str(want["name"]),
			"roster slot %d is %s" % [i, want["name"]])
		if want["structure"] == null:
			# Archers declare nothing, and that is the declaration -- the design note's
			# "pattern of silences" says the record supports no number for light troops.
			assert_false(entry.has("subunit_structure"),
				"roster slot %d (%s) leaves the subunit undeclared" % [i, want["name"]])
		else:
			assert_eq(str(entry.get("subunit_structure", "")), str(want["structure"]),
				"roster slot %d (%s) declares its subunit kind" % [i, want["name"]])
		assert_eq(int(entry.get("subunit_size", 0)), int(want["size"]),
			"roster slot %d (%s) declares its subunit size" % [i, want["name"]])


func test_the_two_cavalry_roster_entries_stay_identical() -> void:
	# The default battle fields two cavalry regiments off two entries that must not drift.
	# Comparing the whole dicts (not just the new keys) is deliberate: this is the guard that
	# catches the NEXT per-type key being added to only one of them.
	var b := BattleScript.new()
	autofree(b)
	var loadout: Array = b._default_loadout()
	var cav: Array = []
	for d in loadout:
		if str(d["name"]) == "Cavalry":
			cav.append(d)
	assert_eq(cav.size(), 2, "the roster fields two cavalry regiments")
	assert_eq(cav[0], cav[1], "both Cavalry roster entries are identical")


# --- parsing --------------------------------------------------------------

func test_parse_maps_every_declared_spelling() -> void:
	assert_eq(BattleScript._parse_subunit_structure("none"),
		UnitScript.SubunitStructure.NONE)
	assert_eq(BattleScript._parse_subunit_structure("file_group"),
		UnitScript.SubunitStructure.FILE_GROUP)
	assert_eq(BattleScript._parse_subunit_structure("lateral_halves"),
		UnitScript.SubunitStructure.LATERAL_HALVES)
	assert_eq(BattleScript._parse_subunit_structure("group"),
		UnitScript.SubunitStructure.GROUP)
	assert_eq(BattleScript._parse_subunit_structure("FILE_GROUP"),
		UnitScript.SubunitStructure.FILE_GROUP, "spelling is case-insensitive")


func test_parse_falls_back_to_undeclared_for_anything_it_does_not_know() -> void:
	# NONE is a valid declaration ("this type organises into no subunit"), so an unrecognised
	# value degrades to it rather than aborting a spawn -- but it warns, so a scenario typo is
	# visible instead of silently reading as a deliberate non-declaration.
	assert_eq(BattleScript._parse_subunit_structure("phalanx_wedge"),
		UnitScript.SubunitStructure.NONE, "an unknown name is undeclared")
	assert_eq(BattleScript._parse_subunit_structure(null),
		UnitScript.SubunitStructure.NONE, "a non-string is undeclared")
	assert_eq(BattleScript._parse_subunit_structure(16),
		UnitScript.SubunitStructure.NONE, "a bare number is undeclared, not a size")


func test_every_enum_member_has_a_spelling_and_a_dump_name() -> void:
	# Both tables mirror Unit.SubunitStructure by hand. Without this, a member added to the
	# enum is silently unreachable from a loadout entry and silently dumps as
	# "SUBUNIT_STRUCTURE(n)" -- neither of which fails anything on its own.
	for name in UnitScript.SubunitStructure.keys():
		var value: int = UnitScript.SubunitStructure[name]
		assert_true(BattleScript.SUBUNIT_STRUCTURE_NAMES.values().has(value),
			"Battle can parse a spelling for SubunitStructure.%s" % name)
		assert_true(DemoStateScript.SUBUNIT_STRUCTURE_NAMES.has(value),
			"DemoState names SubunitStructure.%s in the dump" % name)
	assert_eq(BattleScript.SUBUNIT_STRUCTURE_NAMES.size(),
		UnitScript.SubunitStructure.size(),
		"no spelling maps to a value the enum no longer has")


# --- what actually reaches a spawned regiment -----------------------------

func test_every_spawned_regiment_carries_its_types_declaration() -> void:
	# Keyed by uid, one assertion per regiment: this is the check the issue's implementation
	# trap is about, and collapsing the two Cavalry regiments by name would defeat it.
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(_battle)
	await get_tree().physics_frame

	var expected := {
		"Spearmen": [UnitScript.SubunitStructure.FILE_GROUP, 16],
		"Infantry": [UnitScript.SubunitStructure.LATERAL_HALVES, 0],
		"Archers": [UnitScript.SubunitStructure.NONE, 0],
		"Cavalry": [UnitScript.SubunitStructure.GROUP, 10],
	}
	var cavalry_seen := 0
	var checked := 0
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u == null:
			continue
		var type_name: String = u.unit_name.split(" ")[0]
		if not expected.has(type_name):
			continue
		var want: Array = expected[type_name]
		assert_eq(u.subunit_structure, int(want[0]),
			"uid %d (%s) spawned with its type's declared subunit kind" % [u.uid, type_name])
		assert_eq(u.subunit_size, int(want[1]),
			"uid %d (%s) spawned with its type's declared subunit size" % [u.uid, type_name])
		checked += 1
		if type_name == "Cavalry":
			cavalry_seen += 1
	# Both halves matter: 10 regiments proves nothing was skipped, and 4 cavalry (two a side)
	# proves the assertions above ran against the SECOND Cavalry roster entry too.
	assert_eq(checked, 10, "every regiment in the default 5v5 was checked")
	assert_eq(cavalry_seen, 4, "both cavalry regiments on both teams were checked")


func test_the_declaration_is_inert_for_layout() -> void:
	# The phase's actual claim. Two otherwise-identical units differing only in their declared
	# subunit lay out identically -- frontage still comes from UnitFormation, which reads
	# neither field.
	var plain: Unit = UnitScript.new()
	add_child_autofree(plain)
	plain.max_soldiers = 120
	plain.soldiers = 120

	var declared: Unit = UnitScript.new()
	add_child_autofree(declared)
	declared.max_soldiers = 120
	declared.soldiers = 120
	declared.subunit_structure = UnitScript.SubunitStructure.FILE_GROUP
	declared.subunit_size = 16

	assert_eq(UnitFormation.frontage(declared), UnitFormation.frontage(plain),
		"a declared subunit does not move the frontage -- nothing reads it for layout yet")
	assert_eq(declared.formation_slots(declared.soldiers).size(),
		plain.formation_slots(plain.soldiers).size(),
		"...nor the slot layout")


# --- overrides ------------------------------------------------------------

func test_a_scenario_spec_can_override_both_the_kind_and_the_size() -> void:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": 400.0, "y": 400.0, "count": 40,
			"subunit_structure": "group", "subunit_size": 8},
	]
	add_child(_battle)

	var u: Unit = _first_team_0_unit()
	assert_not_null(u, "the scenario spawned a unit")
	assert_eq(u.subunit_structure, UnitScript.SubunitStructure.GROUP,
		"the spec's kind wins over Spearmen's own file_group")
	assert_eq(u.subunit_size, 8, "the spec's size wins over Spearmen's own 16")


func test_a_size_only_override_keeps_the_types_declared_kind() -> void:
	# The shape a roster override actually uses: a Spartan enomotia and a Macedonian file are
	# both file_group, differing only in headcount. A spec that had to restate the kind would
	# make every size override a chance to get the kind wrong.
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": 400.0, "y": 400.0, "count": 40,
			"subunit_size": 32},
	]
	add_child(_battle)

	var u: Unit = _first_team_0_unit()
	assert_not_null(u, "the scenario spawned a unit")
	assert_eq(u.subunit_structure, UnitScript.SubunitStructure.FILE_GROUP,
		"the type's declared kind survives a size-only override")
	assert_eq(u.subunit_size, 32, "the spec's size applies")


func test_a_roster_name_override_reaches_the_spawn_spec() -> void:
	# Faction.ROSTER_UNIT_TYPES maps five roster names onto "Spearmen", so the type name the
	# spec carries has already thrown away which roster it came from -- the override has to be
	# merged in while the roster name is still in hand.
	var b := BattleScript.new()
	autofree(b)
	b.field = Rect2(Vector2.ZERO, Vector2(2000, 2000))
	b.spawn_line_ys = [1600, 400]
	var specs: Array = b._custom_matchup_scenario(
		["Spartan Hoplites", "Pezhetairoi Phalanx"], ["Hastati"])

	var by_type_and_size := []
	for s in specs:
		by_type_and_size.append([str(s["type"]), s.get("subunit_size", null)])
	assert_eq(by_type_and_size[0], ["Spearmen", 32],
		"Spartan Hoplites carry the enomotia override (Thucydides 5.68.3)")
	assert_eq(by_type_and_size[1], ["Spearmen", null],
		"Pezhetairoi Phalanx keep the Spearmen type default -- no override entry")
	assert_eq(by_type_and_size[2], ["Infantry", null],
		"a roster name with no override adds no key at all")


func test_the_roster_override_table_is_not_mutable_through_its_getter() -> void:
	# GDScript's `const` freezes the binding, not the dictionary, so a caller that merged into
	# the returned dict would edit the table for every later spawn.
	var first: Dictionary = Faction.get_subunit_override("Spartan Hoplites")
	first["subunit_size"] = 999
	first["injected"] = true
	var second: Dictionary = Faction.get_subunit_override("Spartan Hoplites")
	assert_eq(int(second.get("subunit_size", -1)), 32, "the table still reads 32")
	assert_false(second.has("injected"), "a caller's key did not leak into the table")


func test_an_unknown_roster_name_has_no_override() -> void:
	assert_eq(Faction.get_subunit_override("Sarmatian Cataphracts"), {},
		"a name outside the roster tables overrides nothing")


# --- persistence ----------------------------------------------------------

func test_the_declaration_survives_a_snapshot_round_trip() -> void:
	# Per-unit state set once at spawn: a restore that re-derived it would silently reset every
	# unit to the class default and lose the type declaration.
	var src: Unit = UnitScript.new()
	add_child_autofree(src)
	src.subunit_structure = UnitScript.SubunitStructure.FILE_GROUP
	src.subunit_size = 32

	var dst: Unit = UnitScript.new()
	add_child_autofree(dst)
	assert_eq(dst.subunit_structure, UnitScript.SubunitStructure.NONE,
		"precondition: the destination starts at the class default...")
	assert_eq(dst.subunit_size, 0, "...on both fields, so a no-op restore could not pass")

	dst.apply_snapshot_dict(src.to_snapshot_dict())
	assert_eq(dst.subunit_structure, UnitScript.SubunitStructure.FILE_GROUP,
		"the declared kind rides the snapshot")
	assert_eq(dst.subunit_size, 32, "the declared size rides the snapshot")


# --- the state dump -------------------------------------------------------

func test_the_dump_names_the_declaration() -> void:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = 7
	u.subunit_structure = UnitScript.SubunitStructure.LATERAL_HALVES
	u.subunit_size = 0

	var rec: Dictionary = DemoStateScript.unit_record(u, {}, 1.0, false)
	assert_eq(str(rec.get("subunit_structure", "")), "LATERAL_HALVES",
		"the dump names the kind rather than printing its ordinal")
	assert_eq(int(rec.get("subunit_size", -1)), 0, "the dump carries the size")


func _first_team_0_unit() -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u != null and u.team == 0:
			return u
	return null
