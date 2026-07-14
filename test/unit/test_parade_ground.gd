extends GutTest
## ParadeGround: the main menu -> tactical battle hand-off for a solo drill (#838). The
## scene swap itself isn't unit-tested here (see test_main_menu.gd for the menu button and
## test_battle_drill.gd for Battle honoring the flag) — this covers the holder itself.

const ParadeGround = preload("res://scripts/ParadeGround.gd")


func after_each() -> void:
	ParadeGround.clear()   # don't leak a pending request into a later test


func test_pending_defaults_false() -> void:
	assert_false(ParadeGround.pending, "no drill requested until the menu button sets it")


func test_clear_resets_pending() -> void:
	ParadeGround.pending = true
	ParadeGround.clear()
	assert_false(ParadeGround.pending, "clear() forgets a pending request")
