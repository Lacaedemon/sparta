extends GutTest
## _on_quit_to_menu's reset prelude, split into its own function specifically so it's testable
## without triggering a real change_scene_to_file against the live GUT runner's scene tree (see
## test_main_menu.gd's own note on why that's avoided here). Also covers the save-replay prompt
## (_confirm_exit_with_unsaved_replay) those exits now go through first.

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


# --- save-replay-before-exit prompt -------------------------------------------

func test_confirm_exit_resolves_immediately_when_nothing_is_recording() -> void:
	var h := _hud()
	Replay.mode = Replay.Mode.IDLE
	var resolved := {"called": false}
	h._confirm_exit_with_unsaved_replay(func() -> void: resolved["called"] = true)
	assert_true(resolved["called"], "no active recording -- nothing to prompt about")
	assert_false(h._save_replay_dialog.visible, "the dialog never opens")


func test_confirm_exit_resolves_immediately_when_already_auto_saved() -> void:
	var h := _hud()
	Replay.mode = Replay.Mode.RECORD
	Replay.last_saved_path = "user://replays/already_saved.json"
	var resolved := {"called": false}
	h._confirm_exit_with_unsaved_replay(func() -> void: resolved["called"] = true)
	assert_true(resolved["called"],
			"a battle that already reached its formal end auto-saved -- no redundant prompt")
	assert_false(h._save_replay_dialog.visible, "the dialog never opens")
	Replay.last_saved_path = ""   # don't leak into a later test


func test_confirm_exit_prompts_when_a_recording_is_unsaved() -> void:
	var h := _hud()
	Replay.mode = Replay.Mode.RECORD
	Replay.last_saved_path = ""
	var resolved := {"called": false}
	h._confirm_exit_with_unsaved_replay(func() -> void: resolved["called"] = true)
	assert_false(resolved["called"], "waits on the player's choice before exiting")
	assert_true(h._save_replay_dialog.visible,
			"an unsaved mid-battle (or parade-ground) recording gets offered a save")


func test_discard_action_resolves_without_saving() -> void:
	var h := _hud()
	Replay.mode = Replay.Mode.RECORD
	Replay.last_saved_path = ""
	var resolved := {"called": false}
	h._confirm_exit_with_unsaved_replay(func() -> void: resolved["called"] = true)

	h._on_save_replay_custom_action(&"discard")

	assert_true(resolved["called"], "discarding still proceeds with the exit")
	assert_eq(Replay.last_saved_path, "", "...but nothing was written to disk")
	assert_false(h._save_replay_dialog.visible, "the dialog closes")


func test_confirmed_save_resolves_gracefully_with_no_battle_parent() -> void:
	# _hud() parents the HUD directly under the test node, not a real Battle -- exercises the
	# defensive get_parent() as BattleRef null-check rather than crashing.
	var h := _hud()
	Replay.mode = Replay.Mode.RECORD
	Replay.last_saved_path = ""
	var resolved := {"called": false}
	h._confirm_exit_with_unsaved_replay(func() -> void: resolved["called"] = true)

	h._on_save_replay_confirmed()

	assert_true(resolved["called"], "still proceeds with the exit")
	assert_eq(Replay.last_saved_path, "",
			"with no live Battle to read the tick from, there's nothing to save")


func test_confirmed_save_writes_a_replay_file_for_a_live_battle() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)   # _ready() -> Replay.start_recording(): mode=RECORD, path=""
	var battle_hud: HUDScript = battle.get_node("HUD")
	var resolved := {"called": false}
	battle_hud._confirm_exit_with_unsaved_replay(func() -> void: resolved["called"] = true)
	assert_true(battle_hud._save_replay_dialog.visible, "a fresh live battle has nothing saved yet")

	battle_hud._on_save_replay_confirmed()

	assert_true(resolved["called"], "proceeds with the exit after saving")
	assert_ne(Replay.last_saved_path, "", "the recording was written to disk")
	assert_true(FileAccess.file_exists(Replay.last_saved_path), "...and the file is really there")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Replay.last_saved_path))
	Replay.last_saved_path = ""   # don't leak into a later test
