extends GutTest
## PrebattleMenu: the scene wrapper hosting PrebattleScreen and arming CustomMatchup when the
## player presses "Start Custom Battle". _arm_custom_matchup is tested directly,
## not via the button/signal, so this never triggers a real change_scene_to_file against the
## live GUT runner's scene tree (see test_main_menu.gd's own note on why that's avoided).

const PrebattleMenuScript = preload("res://scripts/PrebattleMenu.gd")
const CustomMatchup = preload("res://scripts/CustomMatchup.gd")


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


func test_back_button_is_present() -> void:
	var menu := _menu()
	var found := false
	for child in menu.get_children():
		if child is Button and child.text == "Back":
			found = true
	assert_true(found, "a 'Back' button returns to the main menu")
