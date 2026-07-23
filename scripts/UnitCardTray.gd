class_name UnitCardTray
extends PanelContainer
## Hideable multi-row unit card tray for organizing player units into battle lines.
## Lines are a fixed-size grid (rows x columns) rather than a variable-length list, so a
## line can hold an intentional empty cell mid-line (e.g. for a quincunx/checkerboard
## relative offset between lines), and a lone unit always has an empty neighbor cell to
## shift into. Allows adding/removing rows and columns during battle, line-selection
## clicks, drag-and-drop cell swapping, and row-order line placement.

## Emitted when the player changes which control group the tray is scoped to
## (the header's group selector). HUD listens and resyncs immediately with
## that group's own members, rather than waiting for the periodic refresh.
signal group_changed(n: int)

const UnitRef = preload("res://scripts/Unit.gd")
const DEFAULT_COLUMNS := 4
const _EMPTY_CELL_SIZE := Vector2(90.0, 40.0)
const MAX_GROUP := 9

var _grid: Array = []   # Array[Array]; _grid[r][c] is a Unit, or null for an empty cell.
var current_group: int = 0
var _rows_container: VBoxContainer
var _header_box: HBoxContainer
var _tray_toggle_btn: Button
var _add_row_btn: Button
var _rem_row_btn: Button
var _add_col_btn: Button
var _rem_col_btn: Button
var _row_placement_check: CheckBox
var _group_selector: SpinBox
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

	_add_col_btn = Button.new()
	_add_col_btn.text = "+ Column"
	_add_col_btn.pressed.connect(add_column)
	_header_box.add_child(_add_col_btn)

	_rem_col_btn = Button.new()
	_rem_col_btn.text = "- Column"
	_rem_col_btn.pressed.connect(remove_column)
	_header_box.add_child(_rem_col_btn)

	_row_placement_check = CheckBox.new()
	_row_placement_check.text = "Tray order line placement"
	_row_placement_check.toggled.connect(_on_placement_toggled)
	_header_box.add_child(_row_placement_check)

	var group_label := Label.new()
	group_label.text = "Group:"
	group_label.add_theme_font_size_override("font_size", 13)
	_header_box.add_child(group_label)

	_group_selector = SpinBox.new()
	_group_selector.min_value = 0
	_group_selector.max_value = MAX_GROUP
	_group_selector.step = 1
	_group_selector.value = current_group
	_group_selector.tooltip_text = (
			"Scope the tray to one control group (Ctrl+0-9) at a time. " +
			"A group that's never been bound shows every own-team unit.")
	_group_selector.value_changed.connect(_on_group_selector_changed)
	_header_box.add_child(_group_selector)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 4)
	main_vbox.add_child(_rows_container)

	if _grid.is_empty():
		add_row()


func set_selection_manager(sm) -> void:
	_sel_mgr = sm


## The grid's current column count -- every row shares it. Falls back to DEFAULT_COLUMNS
## for an empty grid (no rows yet), so a fresh add_row()/_place_unit() has a sane width.
func columns() -> int:
	return _grid[0].size() if not _grid.is_empty() else DEFAULT_COLUMNS


func add_row() -> void:
	var new_row: Array = []
	new_row.resize(columns())
	_grid.append(new_row)
	_rebuild_ui()


func remove_row() -> void:
	if _grid.size() <= 1:
		return
	var removed: Array = _grid.pop_back()
	for u in removed:
		if u != null and is_instance_valid(u):
			_place_unit(u)
	_rebuild_ui()


func add_column() -> void:
	for r in _grid:
		r.append(null)
	_rebuild_ui()


## Refuses to go below 1 column, same as remove_row() refuses to go below 1 row. Units in
## the removed column are reflowed via _place_unit(), same as remove_row()'s displaced units.
func remove_column() -> void:
	if columns() <= 1:
		return
	var col: int = columns() - 1
	var displaced: Array = []
	for r in _grid:
		var u = r[col]
		if u != null and is_instance_valid(u):
			displaced.append(u)
		r.remove_at(col)
	for u in displaced:
		_place_unit(u)
	_rebuild_ui()


## Places `u` into the first empty cell, row-major scan; grows a new row (at the grid's
## current column count) if every existing cell is occupied. The shared placement rule
## behind sync_units() (a newly-unassigned unit) and remove_row()/remove_column() (a unit
## displaced by shrinking the grid).
func _place_unit(u) -> void:
	for r in _grid:
		for i in range(r.size()):
			if r[i] == null:
				r[i] = u
				return
	var new_row: Array = []
	new_row.resize(columns())
	new_row[0] = u
	_grid.append(new_row)


func sync_units(all_friendly_units: Array) -> void:
	# Prune dead/freed units -- clear their cell (keeps the grid's shape) rather than
	# removing it the way a variable-length row used to.
	for r in _grid:
		for i in range(r.size()):
			var u = r[i]
			if u != null and (not is_instance_valid(u) or u.state == UnitRef.State.DEAD):
				r[i] = null

	var assigned: Dictionary = {}
	for r in _grid:
		for u in r:
			if u != null:
				assigned[u.get_instance_id()] = true

	for u in all_friendly_units:
		if u != null and is_instance_valid(u) and u.state != UnitRef.State.DEAD:
			if not assigned.has(u.get_instance_id()):
				_place_unit(u)

	_rebuild_ui()


func get_units_in_tray_order() -> Array:
	var res: Array = []
	for r in _grid:
		for u in r:
			if u != null and is_instance_valid(u) and u.state != UnitRef.State.DEAD:
				res.append(u)
	return res


func _valid_cell(r: int, c: int) -> bool:
	return r >= 0 and r < _grid.size() and c >= 0 and c < _grid[r].size()


## Swaps the contents of two cells (a Unit, or null for an empty cell) -- the sole mutation
## primitive shift_unit_*/drag-and-drop both funnel through. A no-op if either endpoint is
## outside the current grid (a true edge, or a stale index from before a
## remove_row()/remove_column()) -- including a target cell that's empty, which is exactly
## how a unit moves INTO a gap.
func move_unit(from_r: int, from_c: int, to_r: int, to_c: int) -> void:
	if not _valid_cell(from_r, from_c) or not _valid_cell(to_r, to_c):
		return
	var tmp = _grid[to_r][to_c]
	_grid[to_r][to_c] = _grid[from_r][from_c]
	_grid[from_r][from_c] = tmp
	_rebuild_ui()


func shift_unit_left(r: int, c: int) -> void:
	move_unit(r, c, r, c - 1)


func shift_unit_right(r: int, c: int) -> void:
	move_unit(r, c, r, c + 1)


func shift_unit_up(r: int, c: int) -> void:
	move_unit(r, c, r - 1, c)


func shift_unit_down(r: int, c: int) -> void:
	move_unit(r, c, r + 1, c)


## Godot drag-source callback (via set_drag_forwarding) for the cell at (row_idx, col_idx).
## Returns null (refuses the drag) for a stale or empty cell -- e.g. the grid shrank between
## the drag starting and Godot re-querying it -- rather than dragging nothing/the wrong unit.
func _get_drag_card_data(_at_position: Vector2, row_idx: int, col_idx: int) -> Variant:
	if not _valid_cell(row_idx, col_idx):
		return null
	var u = _grid[row_idx][col_idx]
	if u == null or not is_instance_valid(u) or u.state == UnitRef.State.DEAD:
		return null
	# set_drag_preview() requires a live Godot drag already in progress (its own precondition,
	# ERR_FAIL_COND(!gui_is_dragging()) internally) -- guarded so this stays callable directly
	# (e.g. from a test) without a real drag/drop event driving it.
	if is_inside_tree() and get_viewport().gui_is_dragging():
		set_drag_preview(_drag_preview_label(u))
	return {"row_idx": row_idx, "col_idx": col_idx}


## The preview Control shown beside the cursor while dragging a card -- a pure function of
## the unit, kept separate from set_drag_preview() itself so it stays directly testable
## without a live Godot drag/drop event (set_drag_preview() alone requires one).
func _drag_preview_label(u) -> Label:
	var preview := Label.new()
	preview.text = "%s (%d)" % [u.unit_name, u.soldiers]
	preview.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	return preview


## Godot drop-target callback: accepts only drag data this tray itself produced.
func _can_drop_card_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("row_idx") and data.has("col_idx")


## Godot drop-target callback for the cell at (target_row_idx, target_col_idx): every cell
## is its own drop target now (empty cells included), so a drop always resolves to a single
## swap via move_unit() -- landing on another card trades the two units' places, landing on
## an empty cell moves the dragged unit into the gap. No more insertion-position geometry.
func _drop_card_data(_at_position: Vector2, data: Variant, target_row_idx: int, target_col_idx: int) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	move_unit(int(data.get("row_idx", -1)), int(data.get("col_idx", -1)), target_row_idx, target_col_idx)


func _on_placement_toggled(pressed: bool) -> void:
	Settings.tray_row_order_placement = pressed


## The selected group changed -- the tray's own line/grid layout doesn't carry over (a
## different group's units don't belong in the previous group's arrangement), so the grid
## resets here; group_changed lets HUD immediately push the new group's own member list
## instead of waiting for the periodic once-a-second refresh.
func _on_group_selector_changed(value: float) -> void:
	current_group = int(value)
	_grid.clear()
	_rebuild_ui()
	group_changed.emit(current_group)


## Discards the current grid layout and rebuilds fresh from `units` -- used whenever the
## unit SET the tray should show changes identity (a group switch), as opposed to
## sync_units()'s incremental prune-dead-then-place-new-arrivals update for the same group.
func reset_and_sync(units: Array) -> void:
	_grid.clear()
	sync_units(units)


func _select_row_line(row_idx: int) -> void:
	if row_idx < 0 or row_idx >= _grid.size():
		return
	var line_units: Array = []
	for u in _grid[row_idx]:
		if u != null and is_instance_valid(u) and u.state != UnitRef.State.DEAD:
			line_units.append(u)
	if not line_units.is_empty():
		if _sel_mgr != null and _sel_mgr.has_method("select_units"):
			_sel_mgr.select_units(line_units)


## A blank placeholder occupying an empty grid cell -- keeps the row's visual layout aligned
## to the grid (so a gap reads as a real gap instead of every later card shifting left), and
## still accepts a drop: a dragged card can land in it via the shared _drop_card_data path.
func _build_empty_cell(r_idx: int, c_idx: int) -> Control:
	var placeholder := Control.new()
	placeholder.custom_minimum_size = _EMPTY_CELL_SIZE
	placeholder.set_drag_forwarding(Callable(), _can_drop_card_data, _drop_card_data.bind(r_idx, c_idx))
	return placeholder


func _build_card_cell(u, r_idx: int, c_idx: int, cols: int) -> Control:
	var card_box := PanelContainer.new()
	card_box.set_drag_forwarding(
			_get_drag_card_data.bind(r_idx, c_idx), _can_drop_card_data, _drop_card_data.bind(r_idx, c_idx))

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

	# Mini shift buttons. The grid's column/row count is the same for every row now, so
	# (unlike the old variable-length rows) a lone unit still has an empty neighbor cell to
	# shift into whenever the grid is wider/taller than 1x1 -- these conditions render the
	# button whenever such a neighbor cell exists, occupied or not.
	var nav_hbox := HBoxContainer.new()
	nav_hbox.add_theme_constant_override("separation", 2)
	card_vbox.add_child(nav_hbox)

	if c_idx > 0:
		var btn_l := Button.new()
		btn_l.text = "◄"
		btn_l.pressed.connect(shift_unit_left.bind(r_idx, c_idx))
		nav_hbox.add_child(btn_l)

	if c_idx < cols - 1:
		var btn_r := Button.new()
		btn_r.text = "►"
		btn_r.pressed.connect(shift_unit_right.bind(r_idx, c_idx))
		nav_hbox.add_child(btn_r)

	if r_idx > 0:
		var btn_u := Button.new()
		btn_u.text = "▲"
		btn_u.pressed.connect(shift_unit_up.bind(r_idx, c_idx))
		nav_hbox.add_child(btn_u)

	if r_idx < _grid.size() - 1:
		var btn_d := Button.new()
		btn_d.text = "▼"
		btn_d.pressed.connect(shift_unit_down.bind(r_idx, c_idx))
		nav_hbox.add_child(btn_d)

	return card_box


func _rebuild_ui() -> void:
	if _rows_container == null:
		return
	for c in _rows_container.get_children():
		c.queue_free()

	if _row_placement_check != null:
		_row_placement_check.set_pressed_no_signal(Settings.tray_row_order_placement)

	var cols: int = columns()
	for r_idx in range(_grid.size()):
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

		for c_idx in range(cols):
			var u = _grid[r_idx][c_idx]
			var cell: Control
			if u == null or not is_instance_valid(u) or u.state == UnitRef.State.DEAD:
				cell = _build_empty_cell(r_idx, c_idx)
			else:
				cell = _build_card_cell(u, r_idx, c_idx, cols)
			cards_hbox.add_child(cell)
