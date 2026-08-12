extends Control
## Title screen / entry point. Lets the player pick the self-contained tactical
## battle (M1) or the campaign map (M2); the campaign now also launches the
## tactical battle for province clashes (M3). UI built in code, matching the
## rest of the project's HUDs.

const Campaigns = preload("res://scripts/campaign/Campaigns.gd")
const CampaignBattle = preload("res://scripts/campaign/CampaignBattle.gd")
const ParadeGround = preload("res://scripts/ParadeGround.gd")
const AllTeamsControl = preload("res://scripts/AllTeamsControl.gd")
const CustomMatchup = preload("res://scripts/CustomMatchup.gd")


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Reaching the main menu ends any campaign->battle hand-off, so a later
	# standalone "Tactical Battle" isn't mistaken for a campaign clash.
	CampaignBattle.clear()
	ParadeGround.clear()
	AllTeamsControl.clear()
	CustomMatchup.clear()

	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-160, -150)
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var title := Label.new()
	title.text = "SPARTA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "grand strategy × real-time tactics"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	box.add_child(subtitle)

	box.add_child(_spacer(16))

	var battle_btn := _menu_button("Tactical Battle")
	battle_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Battle.tscn"))
	box.add_child(battle_btn)

	# Solo maneuver practice: the player's own army, no enemy, no auto-end — see
	# Battle.drill_mode and ParadeGround.
	var drill_btn := _menu_button("Parade Ground")
	drill_btn.pressed.connect(func():
		ParadeGround.pending = true
		get_tree().change_scene_to_file("res://scenes/Battle.tscn"))
	box.add_child(drill_btn)

	# Debug/testing: a normal two-army battle, but the player commands BOTH sides (no AI
	# on team 1) — for rehearsing or verifying combat mechanics deterministically without
	# an opponent's own decisions in the way. See AllTeamsControl and Battle.all_teams_control.
	var all_teams_btn := _menu_button("All-Teams Control")
	all_teams_btn.pressed.connect(func():
		AllTeamsControl.pending = true
		get_tree().change_scene_to_file("res://scenes/Battle.tscn"))
	box.add_child(all_teams_btn)

	# Pick each side's roster from any of the four factions, then launch a battle with
	# that exact matchup instead of the default line — see PrebattleMenu/CustomMatchup.
	var custom_btn := _menu_button("Custom Battle")
	custom_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/Prebattle.tscn"))
	box.add_child(custom_btn)

	# One button per registered campaign: selecting it records the map path,
	# then opens the shared campaign scene which loads that data file.
	for c in Campaigns.LIST:
		var path: String = c["path"]
		var btn := _menu_button("Campaign: %s" % c["name"])
		btn.pressed.connect(func(): _start_campaign(path))
		box.add_child(btn)

	var quit_btn := _menu_button("Quit")
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)


func _start_campaign(path: String) -> void:
	Campaigns.selected_path = path
	get_tree().change_scene_to_file("res://scenes/Campaign.tscn")


func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 44)
	b.add_theme_font_size_override("font_size", 18)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
