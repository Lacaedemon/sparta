class_name PrebattleScreen
extends PanelContainer
## Unit selection prebattle setup screen for custom battle (non-campaign) modes.

signal start_battle_requested(team_0_roster: Array, team_1_roster: Array)

const FactionRef = preload("res://scripts/Faction.gd")

var team_0_faction: int = FactionRef.Type.SPARTA
var team_1_faction: int = FactionRef.Type.ROME

var team_0_roster: Array[String] = []
var team_1_roster: Array[String] = []

var _t0_faction_option: OptionButton
var _t1_faction_option: OptionButton
var _t0_roster_vbox: VBoxContainer
var _t1_roster_vbox: VBoxContainer
var _start_btn: Button


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(main_vbox)

	var title := Label.new()
	title.text = "Custom Battle Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	main_vbox.add_child(title)

	var teams_hbox := HBoxContainer.new()
	teams_hbox.add_theme_constant_override("separation", 24)
	main_vbox.add_child(teams_hbox)

	# Team 0 column
	var t0_vbox := VBoxContainer.new()
	t0_vbox.custom_minimum_size = Vector2(240, 0)
	teams_hbox.add_child(t0_vbox)

	var t0_lbl := Label.new()
	t0_lbl.text = "Player Army (Team 0)"
	t0_lbl.add_theme_font_size_override("font_size", 14)
	t0_vbox.add_child(t0_lbl)

	_t0_faction_option = OptionButton.new()
	_populate_faction_option(_t0_faction_option)
	_t0_faction_option.select(team_0_faction)
	_t0_faction_option.item_selected.connect(_on_t0_faction_selected)
	t0_vbox.add_child(_t0_faction_option)

	_t0_roster_vbox = VBoxContainer.new()
	t0_vbox.add_child(_t0_roster_vbox)

	var add_t0_btn := Button.new()
	add_t0_btn.text = "+ Add Unit"
	add_t0_btn.pressed.connect(add_team_0_unit)
	t0_vbox.add_child(add_t0_btn)

	# Team 1 column
	var t1_vbox := VBoxContainer.new()
	t1_vbox.custom_minimum_size = Vector2(240, 0)
	teams_hbox.add_child(t1_vbox)

	var t1_lbl := Label.new()
	t1_lbl.text = "Enemy Army (Team 1)"
	t1_lbl.add_theme_font_size_override("font_size", 14)
	t1_vbox.add_child(t1_lbl)

	_t1_faction_option = OptionButton.new()
	_populate_faction_option(_t1_faction_option)
	_t1_faction_option.select(team_1_faction)
	_t1_faction_option.item_selected.connect(_on_t1_faction_selected)
	t1_vbox.add_child(_t1_faction_option)

	_t1_roster_vbox = VBoxContainer.new()
	t1_vbox.add_child(_t1_roster_vbox)

	var add_t1_btn := Button.new()
	add_t1_btn.text = "+ Add Unit"
	add_t1_btn.pressed.connect(add_team_1_unit)
	t1_vbox.add_child(add_t1_btn)

	# Default initial rosters
	_reset_default_rosters()
	_rebuild_rosters_ui()

	_start_btn = Button.new()
	_start_btn.text = "⚔ Start Custom Battle"
	_start_btn.custom_minimum_size = Vector2(200, 40)
	_start_btn.pressed.connect(_on_start_pressed)
	main_vbox.add_child(_start_btn)


func add_team_0_unit() -> void:
	var roster: Array = FactionRef.get_roster(team_0_faction)
	if not roster.is_empty():
		team_0_roster.append(roster[0])
		_rebuild_rosters_ui()


func add_team_1_unit() -> void:
	var roster: Array = FactionRef.get_roster(team_1_faction)
	if not roster.is_empty():
		team_1_roster.append(roster[0])
		_rebuild_rosters_ui()


func remove_team_0_unit(idx: int) -> void:
	if idx >= 0 and idx < team_0_roster.size():
		team_0_roster.remove_at(idx)
		_rebuild_rosters_ui()


func remove_team_1_unit(idx: int) -> void:
	if idx >= 0 and idx < team_1_roster.size():
		team_1_roster.remove_at(idx)
		_rebuild_rosters_ui()


func _populate_faction_option(opt: OptionButton) -> void:
	opt.clear()
	for f_id in [FactionRef.Type.SPARTA, FactionRef.Type.ROME, FactionRef.Type.CARTHAGE, FactionRef.Type.MACEDON]:
		opt.add_item(FactionRef.get_faction_name(f_id), f_id)


func _on_t0_faction_selected(idx: int) -> void:
	team_0_faction = idx
	_reset_default_rosters_for_team(0)
	_rebuild_rosters_ui()


func _on_t1_faction_selected(idx: int) -> void:
	team_1_faction = idx
	_reset_default_rosters_for_team(1)
	_rebuild_rosters_ui()


func _reset_default_rosters() -> void:
	_reset_default_rosters_for_team(0)
	_reset_default_rosters_for_team(1)


func _reset_default_rosters_for_team(team: int) -> void:
	var f_id: int = team_0_faction if team == 0 else team_1_faction
	var roster: Array = FactionRef.get_roster(f_id)
	if team == 0:
		team_0_roster.clear()
		for u in roster:
			team_0_roster.append(str(u))
	else:
		team_1_roster.clear()
		for u in roster:
			team_1_roster.append(str(u))


func _rebuild_rosters_ui() -> void:
	if _t0_roster_vbox == null or _t1_roster_vbox == null:
		return
	for c in _t0_roster_vbox.get_children():
		c.queue_free()
	for c in _t1_roster_vbox.get_children():
		c.queue_free()

	for idx in range(team_0_roster.size()):
		var u_name: String = team_0_roster[idx]
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = u_name
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var del := Button.new()
		del.text = "✕"
		del.pressed.connect(remove_team_0_unit.bind(idx))
		row.add_child(del)
		_t0_roster_vbox.add_child(row)

	for idx in range(team_1_roster.size()):
		var u_name: String = team_1_roster[idx]
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = u_name
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var del := Button.new()
		del.text = "✕"
		del.pressed.connect(remove_team_1_unit.bind(idx))
		row.add_child(del)
		_t1_roster_vbox.add_child(row)


func _on_start_pressed() -> void:
	start_battle_requested.emit(team_0_roster.duplicate(), team_1_roster.duplicate())
