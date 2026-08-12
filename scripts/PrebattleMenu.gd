extends Control
## Scene wrapper for PrebattleScreen (the custom-battle roster picker): backdrop, a
## centred PrebattleScreen, and a "Back" button, matching MainMenu's look. Kept
## separate from PrebattleScreen itself so that widget stays a pure, standalone-testable
## UI component (see test_prebattle_screen.gd) with no scene-navigation concerns of its
## own -- this script owns the "what happens when the player presses Start" decision.

const CustomMatchup = preload("res://scripts/CustomMatchup.gd")


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var screen := PrebattleScreen.new()
	screen.start_battle_requested.connect(_on_start_battle_requested)
	add_child(screen)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(120, 36)
	back_btn.position = Vector2(16, 16)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	add_child(back_btn)

	# A PanelContainer's natural size isn't known until a layout pass has run over the
	# children just added above -- wait for one, then centre by its actual measured size
	# (a preset anchor computed before that layout pass would centre around (0, 0)). Kept as
	# the LAST step in _ready() so every child above (background, screen, back button) is
	# already present synchronously the instant _ready() is called, not deferred behind this
	# await -- a caller (or test) that doesn't itself wait a frame after add_child still sees
	# every child immediately, just not yet perfectly centred for one frame.
	await get_tree().process_frame
	screen.position = (size - screen.size) * 0.5


func _on_start_battle_requested(team_0_roster: Array, team_1_roster: Array) -> void:
	_arm_custom_matchup(team_0_roster, team_1_roster)
	get_tree().change_scene_to_file("res://scenes/Battle.tscn")


## Sets CustomMatchup's pending rosters from the signal's payload arrays, coercing each
## entry to String (PrebattleScreen's own roster arrays are already Array[String], but the
## signal itself carries plain Array, per its declared signature). Split out from
## _on_start_battle_requested so it's directly testable without triggering a real
## change_scene_to_file against the live GUT runner's scene tree (see
## test_main_menu.gd/test_hud_scene_transitions.gd for the same convention).
func _arm_custom_matchup(team_0_roster: Array, team_1_roster: Array) -> void:
	var t0: Array[String] = []
	for u in team_0_roster:
		t0.append(str(u))
	var t1: Array[String] = []
	for u in team_1_roster:
		t1.append(str(u))
	CustomMatchup.pending_team_0 = t0
	CustomMatchup.pending_team_1 = t1
