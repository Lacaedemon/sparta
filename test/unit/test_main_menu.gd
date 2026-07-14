extends GutTest
## Main menu: the "Parade Ground" button sits alongside "Tactical Battle" and, when
## pressed, requests a drill-mode battle via ParadeGround (see test_parade_ground.gd and
## test_battle_drill.gd for what that flag then does to the battle). The button itself
## triggers a real change_scene_to_file, so it isn't pressed here — just checked for
## presence and correct wiring of the flag it's supposed to set.

const ParadeGround = preload("res://scripts/ParadeGround.gd")


func after_each() -> void:
	ParadeGround.clear()   # don't leak a pending request into a later test


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


func test_ready_clears_any_stale_pending_request() -> void:
	ParadeGround.pending = true
	_menu()
	assert_false(ParadeGround.pending,
		"loading the main menu forgets a leftover drill request, like CampaignBattle.clear()")
