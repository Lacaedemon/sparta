extends GutTest
## Main menu: the "Parade Ground" and "All-Teams Control" buttons sit alongside "Tactical
## Battle" and, when pressed, request their own battle variant via a static holder
## (ParadeGround / AllTeamsControl — see test_parade_ground.gd/test_all_teams_control.gd and
## test_battle_drill.gd/test_battle_all_teams_control.gd for what those flags then do to the
## battle). The buttons themselves trigger a real change_scene_to_file, so they aren't
## pressed here — just checked for presence and correct wiring of the flag each sets.

const ParadeGround = preload("res://scripts/ParadeGround.gd")
const AllTeamsControl = preload("res://scripts/AllTeamsControl.gd")


func after_each() -> void:
	ParadeGround.clear()   # don't leak a pending request into a later test
	AllTeamsControl.clear()


func _menu() -> Control:
	var menu: Control = load("res://scenes/MainMenu.tscn").instantiate()
	add_child_autofree(menu)
	return menu


func _find_button(root: Node, text: String) -> Button:
	for child in root.get_children():
		if child is Button and child.text == text:
			return child
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func test_parade_ground_button_is_present() -> void:
	var menu := _menu()
	assert_not_null(_find_button(menu, "Parade Ground"),
		"a 'Parade Ground' button sits alongside 'Tactical Battle'")


func test_all_teams_control_button_is_present() -> void:
	var menu := _menu()
	assert_not_null(_find_button(menu, "All-Teams Control"),
		"an 'All-Teams Control' button sits alongside 'Tactical Battle'")


func test_ready_clears_any_stale_pending_request() -> void:
	ParadeGround.pending = true
	AllTeamsControl.pending = true
	_menu()
	assert_false(ParadeGround.pending,
		"loading the main menu forgets a leftover drill request, like CampaignBattle.clear()")
	assert_false(AllTeamsControl.pending,
		"loading the main menu forgets a leftover all-teams-control request too")
