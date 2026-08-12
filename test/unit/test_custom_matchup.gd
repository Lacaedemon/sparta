extends GutTest
## PrebattleScreen -> Battle hand-off: the CustomMatchup static holder, the shared line-spacing
## helpers it reuses from Battle._spawn_line, and the scenario it builds for a configured
## custom matchup.

const BattleScript = preload("res://scripts/Battle.gd")
const CustomMatchupScript = preload("res://scripts/CustomMatchup.gd")
const FactionScript = preload("res://scripts/Faction.gd")


# CustomMatchup is a static holder (like PathField.active/Settings) -- its state persists
# across every test in this GUT run, not just within one test function. Save and restore it
# around every test that sets pending_team_0/1 so a later, unrelated test that loads
# Battle.tscn plain doesn't silently inherit a leftover custom matchup instead of spawning the
# default line.
var _saved_team_0: Array[String] = []
var _saved_team_1: Array[String] = []


func before_each() -> void:
	_saved_team_0 = CustomMatchupScript.pending_team_0
	_saved_team_1 = CustomMatchupScript.pending_team_1


func after_each() -> void:
	CustomMatchupScript.pending_team_0 = _saved_team_0
	CustomMatchupScript.pending_team_1 = _saved_team_1


# --- CustomMatchup.pending() / clear() ---------------------------------------

func test_pending_is_false_with_no_rosters_set() -> void:
	CustomMatchupScript.clear()
	assert_false(CustomMatchupScript.pending())


func test_pending_is_true_with_only_team_0_set() -> void:
	CustomMatchupScript.clear()
	CustomMatchupScript.pending_team_0 = ["Spartan Hoplites"]
	assert_true(CustomMatchupScript.pending())


func test_clear_empties_both_rosters() -> void:
	CustomMatchupScript.pending_team_0 = ["Spartan Hoplites"]
	CustomMatchupScript.pending_team_1 = ["Hastati"]
	CustomMatchupScript.clear()
	assert_true(CustomMatchupScript.pending_team_0.is_empty())
	assert_true(CustomMatchupScript.pending_team_1.is_empty())
	assert_false(CustomMatchupScript.pending())


# --- _line_x_offsets (pure, shared with _spawn_line) -------------------------

func test_line_x_offsets_is_empty_for_no_units() -> void:
	var b := BattleScript.new()
	autofree(b)
	assert_eq(b._line_x_offsets([], 1600.0), [])


func test_line_x_offsets_first_offset_is_always_zero() -> void:
	var b := BattleScript.new()
	autofree(b)
	var xs: Array[float] = b._line_x_offsets([20.0, 20.0, 20.0], 1600.0)
	assert_almost_eq(xs[0], 0.0, 0.0001)
	assert_eq(xs.size(), 3)


func test_line_x_offsets_spaces_wider_units_further_apart_than_narrow_ones() -> void:
	var b := BattleScript.new()
	autofree(b)
	var narrow: Array[float] = b._line_x_offsets([10.0, 10.0], 1600.0)
	var wide: Array[float] = b._line_x_offsets([100.0, 100.0], 1600.0)
	assert_gt(wide[1] - wide[0], narrow[1] - narrow[0],
		"two wide blocks need a bigger gap than two narrow ones to stay non-overlapping")


func test_line_x_offsets_shrinks_gaps_to_fit_a_narrow_field() -> void:
	var b := BattleScript.new()
	autofree(b)
	# Half-widths chosen so the raw no-overlap total clearly overflows a tiny field.
	var xs: Array[float] = b._line_x_offsets([500.0, 500.0, 500.0], 300.0)
	assert_lt(xs[xs.size() - 1], 3000.0,
		"the total line width is shrunk to fit the field budget, not left at the raw no-overlap sum")


# --- _custom_matchup_scenario -------------------------------------------------

func test_custom_matchup_scenario_resolves_roster_names_to_real_spawnable_types() -> void:
	var b := BattleScript.new()
	autofree(b)
	var specs: Array = b._custom_matchup_scenario(["Spartan Hoplites"], ["Equites Cavalry"])
	assert_eq(specs.size(), 2)
	var by_team: Dictionary = {}
	for spec in specs:
		by_team[int(spec["team"])] = spec
	assert_eq(str(by_team[0]["type"]), FactionScript.get_unit_type("Spartan Hoplites"))
	assert_eq(str(by_team[1]["type"]), FactionScript.get_unit_type("Equites Cavalry"))
	assert_eq(str(by_team[0]["type"]), "Spearmen")
	assert_eq(str(by_team[1]["type"]), "Cavalry")


func test_custom_matchup_scenario_assigns_correct_team_and_facing() -> void:
	var b := BattleScript.new()
	autofree(b)
	var specs: Array = b._custom_matchup_scenario(["Hastati"], ["Hastati"])
	var by_team: Dictionary = {}
	for spec in specs:
		by_team[int(spec["team"])] = spec
	assert_eq(by_team[0]["facing"], [0.0, 1.0], "team 0 faces down toward the enemy half")
	assert_eq(by_team[1]["facing"], [0.0, -1.0], "team 1 faces up toward the enemy half")
	assert_almost_eq(float(by_team[0]["y"]), float(b.spawn_line_ys[0]), 0.0001)
	assert_almost_eq(float(by_team[1]["y"]), float(b.spawn_line_ys[1]), 0.0001)


func test_custom_matchup_scenario_skips_an_unrecognized_roster_name() -> void:
	var b := BattleScript.new()
	autofree(b)
	var specs: Array = b._custom_matchup_scenario(["Not A Real Unit"], [])
	assert_eq(specs.size(), 0, "an unrecognized roster name is skipped, not spawned with no stats")


func test_custom_matchup_scenario_lines_up_multiple_units_without_collapsing_to_one_point() -> void:
	var b := BattleScript.new()
	autofree(b)
	var specs: Array = b._custom_matchup_scenario(
		["Spartan Hoplites", "Skiritai", "Hippeis Cavalry"], [])
	assert_eq(specs.size(), 3)
	var xs: Array[float] = []
	for spec in specs:
		xs.append(float(spec["x"]))
	assert_ne(xs[0], xs[1], "distinct units land at distinct x positions")
	assert_ne(xs[1], xs[2], "distinct units land at distinct x positions")


# --- Full spawn integration: Battle._ready() reads a pending custom matchup -----

func test_battle_spawns_a_pending_custom_matchup_instead_of_the_default_line() -> void:
	CustomMatchupScript.pending_team_0 = ["Hippeis Cavalry"]
	CustomMatchupScript.pending_team_1 = ["Balearic Slingers"]
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame   # one tick to let _ready()'s spawn run

	var team_0_types: Array[String] = []
	var team_1_types: Array[String] = []
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit == null:
			continue
		var type_name: String = unit.unit_name.split(" ")[0]
		if unit.team == 0:
			team_0_types.append(type_name)
		else:
			team_1_types.append(type_name)

	assert_eq(team_0_types, ["Cavalry"], "team 0 spawns exactly the configured Hippeis Cavalry, as Cavalry")
	assert_eq(team_1_types, ["Archers"], "team 1 spawns exactly the configured Balearic Slingers, as Archers")
