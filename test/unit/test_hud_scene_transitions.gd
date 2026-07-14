extends GutTest
## _on_quit_to_menu's reset prelude, split into its own function specifically so it's testable
## without triggering a real change_scene_to_file against the live GUT runner's scene tree (see
## test_main_menu.gd's own note on why that's avoided here).

const HUDScript = preload("res://scripts/HUD.gd")


func _hud() -> HUDScript:
	var h := HUDScript.new()
	add_child_autofree(h)
	return h


func after_each() -> void:
	Replay.reset()   # Replay is a global autoload -- don't leak RECORD/PLAYBACK into later tests
	get_tree().paused = false


func test_reset_for_quit_to_menu_drops_the_recording_and_unpauses() -> void:
	var h := _hud()
	Replay.mode = Replay.Mode.RECORD
	get_tree().paused = true

	h._reset_for_quit_to_menu()

	assert_eq(Replay.mode, Replay.Mode.IDLE, "drops the in-progress recording like a restart")
	assert_false(get_tree().paused, "unpauses so the next scene starts unpaused")
