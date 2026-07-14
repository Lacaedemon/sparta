extends GutTest
## AllTeamsControl: the main menu -> tactical battle hand-off for the debug/testing "control
## every team" mode. The scene swap itself isn't unit-tested here (see test_main_menu.gd for
## the menu button and test_battle_all_teams_control.gd for Battle honoring the flag) — this
## covers the holder itself.

const AllTeamsControl = preload("res://scripts/AllTeamsControl.gd")


func after_each() -> void:
	AllTeamsControl.clear()   # don't leak a pending request into a later test


func test_pending_defaults_false() -> void:
	assert_false(AllTeamsControl.pending, "all-teams control isn't requested until the menu button sets it")


func test_clear_resets_pending() -> void:
	AllTeamsControl.pending = true
	AllTeamsControl.clear()
	assert_false(AllTeamsControl.pending, "clear() forgets a pending request")
