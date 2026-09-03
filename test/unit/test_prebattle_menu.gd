extends GutTest
## PrebattleMenu: the scene wrapper hosting PrebattleScreen and arming CustomMatchup when the
## player presses "Start Custom Battle". _arm_custom_matchup is tested directly,
## not via the button/signal, so this never triggers a real change_scene_to_file against the
## live GUT runner's scene tree (see test_main_menu.gd's own note on why that's avoided).

const PrebattleMenuScript = preload("res://scripts/PrebattleMenu.gd")
const CustomMatchup = preload("res://scripts/CustomMatchup.gd")
const FactionScript = preload("res://scripts/Faction.gd")


func after_each() -> void:
	CustomMatchup.clear()   # don't leak a pending request into a later test


func _menu() -> Control:
	var m: Control = PrebattleMenuScript.new()
	add_child_autofree(m)
	return m


func _find_prebattle_screen(root: Node) -> PrebattleScreen:
	for child in root.get_children():
		if child is PrebattleScreen:
			return child
		var found := _find_prebattle_screen(child)
		if found != null:
			return found
	return null


func test_hosts_a_prebattle_screen() -> void:
	var menu := _menu()
	assert_not_null(_find_prebattle_screen(menu),
		"PrebattleMenu instantiates a PrebattleScreen as a child")


func test_prebattle_screen_start_signal_is_connected() -> void:
	var menu := _menu()
	var screen := _find_prebattle_screen(menu)
	assert_true(screen.start_battle_requested.is_connected(menu._on_start_battle_requested),
		"the screen's start_battle_requested signal reaches the menu's handler")


func test_arm_custom_matchup_sets_pending_rosters_from_the_signal_payload() -> void:
	var menu := _menu()
	menu._arm_custom_matchup(["Spartan Hoplites", "Skiritai"], ["Hastati"])
	assert_eq(CustomMatchup.pending_team_0, ["Spartan Hoplites", "Skiritai"])
	assert_eq(CustomMatchup.pending_team_1, ["Hastati"])
	assert_true(CustomMatchup.pending())


func test_arm_custom_matchup_sets_pending_factions_too() -> void:
	var menu := _menu()
	menu._arm_custom_matchup(["Spartan Hoplites"], ["Hastati"],
			FactionScript.Type.SPARTA, FactionScript.Type.ROME)
	assert_eq(CustomMatchup.pending_faction_0, FactionScript.Type.SPARTA)
	assert_eq(CustomMatchup.pending_faction_1, FactionScript.Type.ROME)


func test_arm_custom_matchup_defaults_the_factions_to_none() -> void:
	# A caller that names only the rosters arms a matchup whose HUD keeps the plain names,
	# rather than inheriting whichever faction a previous battle happened to leave behind.
	CustomMatchup.pending_faction_0 = FactionScript.Type.MACEDON
	var menu := _menu()
	menu._arm_custom_matchup(["Spartan Hoplites"], ["Hastati"])
	assert_eq(CustomMatchup.pending_faction_0, FactionScript.NONE)
	assert_eq(CustomMatchup.pending_faction_1, FactionScript.NONE)


func test_the_screens_start_signal_carries_the_chosen_factions() -> void:
	# The screen owns the faction pickers, so its own start signal is what delivers them --
	# the menu never reads the screen's fields directly. Captured through a local listener
	# rather than through the menu's own handler, which would change_scene_to_file for real.
	var screen := PrebattleScreen.new()
	add_child_autofree(screen)
	screen.team_0_faction = FactionScript.Type.CARTHAGE
	screen.team_1_faction = FactionScript.Type.MACEDON
	screen.team_0_roster = ["Sacred Band"]
	screen.team_1_roster = ["Hypaspists"]
	# Appended into, not reassigned: a GDScript lambda captures a local by value, so an
	# assignment inside it would never reach this scope.
	var seen: Array = []
	screen.start_battle_requested.connect(
			func(_t0: Array, _t1: Array, f0: int, f1: int) -> void: seen.append_array([f0, f1]))
	screen._on_start_pressed()
	assert_eq(seen, [FactionScript.Type.CARTHAGE, FactionScript.Type.MACEDON])


func test_back_button_is_present() -> void:
	var menu := _menu()
	var found := false
	for child in menu.get_children():
		if child is Button and child.text == "Back":
			found = true
	assert_true(found, "a 'Back' button returns to the main menu")
