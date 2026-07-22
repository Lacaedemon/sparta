class_name UnitCardTray
extends PanelContainer
## Hideable multi-row unit card tray for organizing player units into battle lines.
## Allows adding/removing rows during battle, line-selection clicks, and row-order line placement.

signal selection_requested(units: Array)

const UnitRef = preload("res://scripts/Unit.gd")

var _rows: Array = []   # Array of Array[Unit]
var _rows_container: VBoxContainer
var _header_box: HBoxContainer
var _tray_toggle_btn: Button
var _add_row_btn: Button
var _rem_row_btn: Button
var _row_placement_check: CheckBox
var _sel_mgr = null


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 4)
	margin.add_child(main_vbox)

	_header_box = HBoxContainer.new()
	_header_box.add_theme_constant_override("separation", 8)
	main_vbox.add_child(_header_box)

	var title := Label.new()
	title.text = "Battle Lines (Unit Tray)"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_header_box.add_child(title)

	_add_row_btn = Button.new()
	_add_row_btn.text = "+ Line"
	_add_row_btn.pressed.connect(add_row)
	_header_box.add_child(_add_row_btn)

	_rem_row_btn = Button.new()
	_rem_row_btn.text = "- Line"
	_rem_row_btn.pressed.connect(remove_row)
	_header_box.add_child(_rem_row_btn)

	_row_placement_check = CheckBox.new()
	_row_placement_check.text = "Tray order line placement"
	_row_placement_check.toggled.connect(_on_placement_toggled)
	_header_box.add_child(_row_placement_check)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 4)
	main_vbox.add_child(_rows_container)

	# Ensure at least 1 row exists
	if _rows.is_empty():
		add_row()


func set_selection_manager(sm) -> void:
	_sel_mgr = sm


func add_row() -> void:
	_rows.append([])
	_rebuild_ui()


func remove_row() -> void:
	if _rows.size() <= 1:
		return
	var last_units: Array = _rows.pop_back()
	# Move units from removed row to previous row
	if not _rows.is_empty():
		for u in last_units:
			if u != null and is_instance_valid(u):
				_rows[_rows.size() - 1].append(u)
	_rebuild_ui()


func sync_units(all_friendly_units: Array) -> void:
	# Prune dead/freed units
	for r in _rows:
		var valid_units: Array = []
		for u in r:
			if u != null and is_instance_valid(u) and u.state != UnitRef.State.DEAD:
				valid_units.append(u)
		r.clear()
		r.append_array(valid_units)

	# Find unassigned friendly units and place in Row 0
	var assigned: Dictionary = {}
	for r in _rows:
		for u in r:
			assigned[u.get_instance_id()] = true

	for u in all_friendly_units:
		if u != null and is_instance_valid(u) and u.state != UnitRef.State.DEAD:
			if not assigned.has(u.get_instance_id()):
				if _rows.is_empty():
					_rows.append([])
				_rows[0].append(u)

	_rebuild_ui()


func get_units_in_tray_order() -> Array:
	var res: Array = []
	for r in _rows:
		for u in r:
			if u != null and is_instance_valid(u) and u.state != UnitRef.State.DEAD:
				res.append(u)
	return res


func move_unit_up(row_idx: int, col_idx: int) -> void:
	if row_idx <= 0 or row_idx >= _rows.size():
		return
	var u = _rows[row_idx][col_idx]
	_rows[row_idx].remove_at(col_idx)
	_rows[row_idx - 1].append(u)
	_rebuild_ui()


func move_unit_down(row_idx: int, col_idx: int) -> void:
	if row_idx < 0 or row_idx >= _rows.size() - 1:
		return
	var u = _rows[row_idx][col_idx]
	_rows[row_idx].remove_at(col_idx)
	_rows[row_idx + 1].append(u)
	_rebuild_ui()


func move_unit_left(row_idx: int, col_idx: int) -> void:
	if col_idx <= 0 or row_idx < 0 or row_idx >= _rows.size():
		return
	var u = _rows[row_idx][col_idx]
	_rows[row_idx].remove_at(col_idx)
	_rows[row_idx].insert(col_idx - 1, u)
	_rebuild_ui()


func move_unit_right(row_idx: int, col_idx: int) -> void:
	if row_idx < 0 or row_idx >= _rows.size() or col_idx >= _rows[row_idx].size() - 1:
		return
	var u = _rows[row_idx][col_idx]
	_rows[row_idx].remove_at(col_idx)
	_rows[row_idx].insert(col_idx + 1, u)
	_rebuild_ui()


func _on_placement_toggled(pressed: bool) -> void:
	Settings.tray_row_order_placement = pressed


func _select_row_line(row_idx: int) -> void:
	if row_idx < 0 or row_idx >= _rows.size():
		return
	var line_units: Array = []
	for u in _rows[row_idx]:
		if u != null and is_instance_valid(u) and u.state != UnitRef.State.DEAD:
			line_units.append(u)
	if not line_units.is_empty():
		selection_requested.emit(line_units)
		if _sel_mgr != null and _sel_mgr.has_method("select_units"):
			_sel_mgr.select_units(line_units)


func _rebuild_ui() -> void:
	if _rows_container == null:
		return
	for c in _rows_container.get_children():
		c.queue_free()

	if _row_placement_check != null:
		_row_placement_check.set_pressed_no_signal(Settings.tray_row_order_placement)

	for r_idx in range(_rows.size()):
		var row_hbox := HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 4)
		_rows_container.add_child(row_hbox)

		var line_btn := Button.new()
		line_btn.text = "Line %d" % (r_idx + 1)
		line_btn.pressed.connect(_select_row_line.bind(r_idx))
		row_hbox.add_child(line_btn)

		var cards_scroll := ScrollContainer.new()
		cards_scroll.custom_minimum_size = Vector2(0, 48)
		cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		row_hbox.add_child(cards_scroll)

		var cards_hbox := HBoxContainer.new()
		cards_hbox.add_theme_constant_override("separation", 4)
		cards_scroll.add_child(cards_hbox)

		for c_idx in range(_rows[r_idx].size()):
			var u = _rows[r_idx][c_idx]
			if u == null or not is_instance_valid(u) or u.state == UnitRef.State.DEAD:
				continue

			var card_box := PanelContainer.new()
			cards_hbox.add_child(card_box)

			var card_vbox := VBoxContainer.new()
			card_vbox.add_theme_constant_override("separation", 2)
			card_box.add_child(card_vbox)

			var select_card_btn := Button.new()
			select_card_btn.text = "%s (%d)" % [u.unit_name, u.soldiers]
			select_card_btn.pressed.connect(func():
				selection_requested.emit([u])
				if _sel_mgr != null and _sel_mgr.has_method("select_units"):
					_sel_mgr.select_units([u])
			)
			card_vbox.add_child(select_card_btn)

			# Mini row-shift buttons
			var nav_hbox := HBoxContainer.new()
			nav_hbox.add_theme_constant_override("separation", 2)
			card_vbox.add_child(nav_hbox)

			if c_idx > 0:
				var btn_l := Button.new()
				btn_l.text = "◄"
				btn_l.pressed.connect(move_unit_left.bind(r_idx, c_idx))
				nav_hbox.add_child(btn_l)

			if c_idx < _rows[r_idx].size() - 1:
				var btn_r := Button.new()
				btn_r.text = "►"
				btn_r.pressed.connect(move_unit_right.bind(r_idx, c_idx))
				nav_hbox.add_child(btn_r)

			if r_idx > 0:
				var btn_u := Button.new()
				btn_u.text = "▲"
				btn_u.pressed.connect(move_unit_up.bind(r_idx, c_idx))
				nav_hbox.add_child(btn_u)

			if r_idx < _rows.size() - 1:
				var btn_d := Button.new()
				btn_d.text = "▼"
				btn_d.pressed.connect(move_unit_down.bind(r_idx, c_idx))
				nav_hbox.add_child(btn_d)
