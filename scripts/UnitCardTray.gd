class_name UnitCardTray
extends PanelContainer
## Hideable multi-row unit card tray for organizing player units into battle lines.
## Allows adding/removing rows during battle, line-selection clicks, and row-order line placement.

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


## Godot drag-source callback (via set_drag_forwarding) for a card at (row_idx, col_idx).
## Returns null (refuses the drag) for a stale index -- e.g. the row shrank between the
## drag starting and Godot re-querying it -- rather than dragging the wrong unit.
func _get_drag_card_data(_at_position: Vector2, row_idx: int, col_idx: int) -> Variant:
	if row_idx < 0 or row_idx >= _rows.size() or col_idx < 0 or col_idx >= _rows[row_idx].size():
		return null
	var u = _rows[row_idx][col_idx]
	if u == null or not is_instance_valid(u):
		return null
	# set_drag_preview() requires a live Godot drag already in progress (its own precondition,
	# ERR_FAIL_COND(!gui_is_dragging()) internally) -- guarded so this stays callable directly
	# (e.g. from a test) without a real drag/drop event driving it.
	if is_inside_tree() and get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = "%s (%d)" % [u.unit_name, u.soldiers]
		preview.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		set_drag_preview(preview)
	return {"row_idx": row_idx, "col_idx": col_idx}


## Godot drop-target callback: accepts only drag data this tray itself produced.
func _can_drop_card_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("row_idx") and data.has("col_idx")


## Godot drop-target callback for the line at `target_row_idx`'s `cards_hbox`: moves the
## dragged card to whichever position `at_position.x` lands closest to in that line (a
## same-line drop reorders in place; a cross-line drop moves it, matching move_unit_up/down).
func _drop_card_data(at_position: Vector2, data: Variant, target_row_idx: int,
		cards_hbox: HBoxContainer) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var src_row: int = int(data.get("row_idx", -1))
	var src_col: int = int(data.get("col_idx", -1))
	if src_row < 0 or src_row >= _rows.size() or src_col < 0 or src_col >= _rows[src_row].size():
		return
	if target_row_idx < 0 or target_row_idx >= _rows.size():
		return
	var u = _rows[src_row][src_col]
	var insert_at := _drop_index_in_row(cards_hbox, at_position.x)
	_rows[src_row].remove_at(src_col)
	# Removing the dragged card from earlier in its OWN line shifts every later index down
	# by one, including the drop target computed against the pre-removal layout.
	if src_row == target_row_idx and src_col < insert_at:
		insert_at -= 1
	_rows[target_row_idx].insert(clampi(insert_at, 0, _rows[target_row_idx].size()), u)
	_rebuild_ui()


## The index a drop at local x `drop_x` within `cards_hbox` lands at: the first existing
## card whose horizontal center is to the right of `drop_x`, or the line's size if the drop
## is past every card (append at the end). Pure function of the row's current child layout,
## unit-testable without a real drag/drop event.
func _drop_index_in_row(cards_hbox: HBoxContainer, drop_x: float) -> int:
	var idx := 0
	for child in cards_hbox.get_children():
		var c := child as Control
		if c == null:
			continue
		if drop_x < c.position.x + c.size.x * 0.5:
			return idx
		idx += 1
	return idx


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
		# Without SIZE_EXPAND_FILL, an HBoxContainer never grants a child more than its own
		# minimum size (0 width here) -- cards_scroll (and every card inside it) stayed
		# permanently clipped to zero width, regardless of how many layout passes ran.
		cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		row_hbox.add_child(cards_scroll)

		var cards_hbox := HBoxContainer.new()
		cards_hbox.add_theme_constant_override("separation", 4)
		cards_scroll.add_child(cards_hbox)
		# Drag-and-drop is an alternative to the per-card arrow-button nav below, not a
		# replacement -- dropping a card here reorders it within this line or moves it in from
		# another line, landing at whichever position the drop's x-coordinate lands closest to.
		cards_hbox.set_drag_forwarding(Callable(), _can_drop_card_data, _drop_card_data.bind(r_idx, cards_hbox))

		for c_idx in range(_rows[r_idx].size()):
			var u = _rows[r_idx][c_idx]
			if u == null or not is_instance_valid(u) or u.state == UnitRef.State.DEAD:
				continue

			var card_box := PanelContainer.new()
			cards_hbox.add_child(card_box)
			card_box.set_drag_forwarding(_get_drag_card_data.bind(r_idx, c_idx), Callable(), Callable())

			var card_vbox := VBoxContainer.new()
			card_vbox.add_theme_constant_override("separation", 2)
			card_box.add_child(card_vbox)

			var select_card_btn := Button.new()
			select_card_btn.text = "%s (%d)" % [u.unit_name, u.soldiers]
			select_card_btn.pressed.connect(func():
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
