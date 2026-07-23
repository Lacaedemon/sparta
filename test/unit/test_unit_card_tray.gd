extends GutTest
## Unit card tray unit tests: the fixed rows x columns grid, add/remove row/column, cell
## shifting and drag-and-drop swapping, and sync_units()'s placement rule.

const UnitScript = preload("res://scripts/Unit.gd")


func _tray() -> UnitCardTray:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	return tray


func _named_unit(n: String) -> Unit:
	var u: Unit = UnitScript.new()
	u.unit_name = n
	add_child_autofree(u)
	return u


func test_sync_units_places_new_units_into_the_first_empty_cell_row_major() -> void:
	var tray := _tray()
	assert_eq(tray.columns(), UnitCardTray.DEFAULT_COLUMNS, "starts at the default column count")
	var u1 := _named_unit("Hastati 1")
	var u2 := _named_unit("Principes 1")

	tray.sync_units([u1, u2])

	assert_eq(tray._grid[0][0], u1, "the first unassigned unit lands in the first cell")
	assert_eq(tray._grid[0][1], u2, "...and the second in the next empty cell, row-major")
	assert_eq(tray.get_units_in_tray_order().size(), 2)


func test_sync_units_grows_a_new_row_once_the_grid_is_full() -> void:
	var tray := _tray()
	var units: Array = []
	for i in range(UnitCardTray.DEFAULT_COLUMNS + 1):
		units.append(_named_unit("Unit %d" % i))

	tray.sync_units(units)

	assert_eq(tray._grid.size(), 2, "one row filled exactly, so the overflow unit grows a new row")
	assert_eq(tray._grid[1][0], units[UnitCardTray.DEFAULT_COLUMNS],
			"the overflow unit lands in the first cell of the new row")


func test_add_row_and_remove_row_reflow_displaced_units() -> void:
	var tray := _tray()
	var u1 := _named_unit("Hastati 1")
	var u2 := _named_unit("Principes 1")
	tray.sync_units([u1, u2])

	tray.add_row()
	tray.move_unit(0, 1, 1, 0)   # u2 moves to line 2
	assert_eq(tray._grid[1][0], u2, "precondition: u2 sits alone on line 2")

	tray.remove_row()   # line 2 removed; u2 must reflow, not vanish
	assert_eq(tray.get_units_in_tray_order().size(), 2, "both units survive the removal")
	assert_eq(tray._grid[0][1], u2, "u2 reflows into the first empty cell of the remaining grid")


func test_remove_row_refuses_to_go_below_one_row() -> void:
	var tray := _tray()
	assert_eq(tray._grid.size(), 1)
	tray.remove_row()
	assert_eq(tray._grid.size(), 1, "the last line can't be removed")


func test_add_column_widens_every_row() -> void:
	var tray := _tray()
	tray.add_row()
	var starting_cols: int = tray.columns()

	tray.add_column()

	for r in tray._grid:
		assert_eq(r.size(), starting_cols + 1, "every existing row gains the new column")


func test_remove_column_reflows_displaced_units_and_refuses_below_one() -> void:
	var tray := _tray()
	var units: Array = []
	for i in range(tray.columns()):
		units.append(_named_unit("Unit %d" % i))
	tray.sync_units(units)   # fills every cell in row 0

	var last_col: int = tray.columns() - 1
	var displaced: Unit = tray._grid[0][last_col]
	tray.remove_column()

	assert_eq(tray.columns(), units.size() - 1, "the grid is one column narrower")
	assert_true(tray.get_units_in_tray_order().has(displaced),
			"the unit that was in the removed column survives, reflowed elsewhere")

	while tray.columns() > 1:
		tray.remove_column()
	tray.remove_column()
	assert_eq(tray.columns(), 1, "the last column can't be removed")


func test_shift_unit_right_moves_a_lone_unit_into_an_empty_neighbor_cell() -> void:
	# A lone unit used to have no neighbor to swap with under the old variable-length-row
	# model. On a fixed-width grid it always does (as long as the grid is wider than 1
	# column), even with every other cell empty.
	var tray := _tray()
	var u := _named_unit("Cavalry 1")
	tray.sync_units([u])
	assert_null(tray._grid[0][1], "precondition: the neighbor cell starts empty")

	tray.shift_unit_right(0, 0)

	assert_null(tray._grid[0][0], "the unit's old cell is now empty")
	assert_eq(tray._grid[0][1], u, "...and the unit occupies the (previously empty) neighbor")


func test_shift_unit_left_at_column_zero_is_a_noop() -> void:
	var tray := _tray()
	var u := _named_unit("Cavalry 1")
	tray.sync_units([u])

	tray.shift_unit_left(0, 0)

	assert_eq(tray._grid[0][0], u, "no cell to the left of column 0 -- the unit doesn't move")


func test_shift_unit_down_at_the_last_row_is_a_noop() -> void:
	var tray := _tray()
	var u := _named_unit("Cavalry 1")
	tray.sync_units([u])

	tray.shift_unit_down(0, 0)

	assert_eq(tray._grid[0][0], u, "no row below the last one -- the unit doesn't move")


func test_move_unit_swaps_two_occupied_cells() -> void:
	var tray := _tray()
	var u1 := _named_unit("Hastati 1")
	var u2 := _named_unit("Principes 1")
	tray.sync_units([u1, u2])   # u1 at (0,0), u2 at (0,1)

	tray.move_unit(0, 0, 0, 1)

	assert_eq(tray._grid[0][0], u2, "the two units trade places")
	assert_eq(tray._grid[0][1], u1)


func test_move_unit_ignores_a_stale_endpoint() -> void:
	var tray := _tray()
	var u := _named_unit("Cavalry 1")
	tray.sync_units([u])

	tray.move_unit(0, 0, 5, 0)   # row 5 doesn't exist

	assert_eq(tray._grid[0][0], u, "no-op: the target cell is outside the current grid")


func test_settings_tray_row_order_placement_defaults_off() -> void:
	assert_false(Settings.show_unit_card_tray, "show_unit_card_tray defaults to false")
	assert_false(Settings.tray_row_order_placement, "tray_row_order_placement defaults to false")


## Regression test: cards_scroll (the ScrollContainer holding a line's cells) used to have
## no size_flags_horizontal, so an HBoxContainer parent never granted it more than its own
## 0-width minimum -- every card was permanently invisible (0 width), regardless of how many
## layout passes ran. Caught only by an actual screenshot, not by any prior test, since every
## existing test asserted on _grid (logical state) rather than real rendered size.
func test_cards_scroll_expands_to_fill_the_row_so_cards_are_actually_visible() -> void:
	var tray := _tray()
	tray.custom_minimum_size = Vector2(500, 0)   # matches HUD._build_unit_card_tray's own width
	var u := _named_unit("Infantry 1")
	tray.sync_units([u])

	for i in range(5):
		await get_tree().process_frame

	var row_hbox: HBoxContainer = tray._rows_container.get_child(0)
	var cards_scroll: ScrollContainer = row_hbox.get_child(1)
	assert_gt(cards_scroll.size.x, 100.0,
			"the cards area claims real width instead of collapsing to its 0-width minimum")


# --- drag-and-drop cell swapping ---------------------------------------------------------
# The Godot drag-source/drop-target callbacks (_get_drag_card_data/_can_drop_card_data/
# _drop_card_data) are pure functions wired via set_drag_forwarding() rather than relying
# on Godot's own DND machinery -- exercised directly here, with no real drag/drop event.
# Every cell (occupied or empty) is its own drop target now, so there's no insertion-index
# geometry to test -- a drop always resolves to a single move_unit() swap.

func test_get_drag_card_data_returns_the_dragged_cells_indices() -> void:
	var tray := _tray()
	var u := _named_unit("Infantry 1")
	tray.sync_units([u])

	var data = tray._get_drag_card_data(Vector2.ZERO, 0, 0)

	assert_eq(data, {"row_idx": 0, "col_idx": 0})


func test_get_drag_card_data_refuses_a_stale_index() -> void:
	var tray := _tray()
	assert_null(tray._get_drag_card_data(Vector2.ZERO, 5, 0), "row_idx past the last line")
	assert_null(tray._get_drag_card_data(Vector2.ZERO, 0, 99), "col_idx past the grid's width")


func test_get_drag_card_data_refuses_an_empty_cell() -> void:
	var tray := _tray()
	assert_null(tray._get_drag_card_data(Vector2.ZERO, 0, 0), "nothing to drag from an empty cell")


func test_get_drag_card_data_refuses_a_dead_unit_at_an_otherwise_valid_index() -> void:
	var tray := _tray()
	var u := _named_unit("Infantry 1")
	tray.sync_units([u])
	u.state = UnitScript.State.DEAD

	assert_null(tray._get_drag_card_data(Vector2.ZERO, 0, 0), "a dead unit can't be dragged")


func test_drag_preview_label_shows_the_units_name_and_soldier_count() -> void:
	var tray := _tray()
	var u := _named_unit("Infantry 1")
	u.soldiers = 40   # after _ready() (which sets soldiers = max_soldiers) so the override sticks

	var preview: Label = autofree(tray._drag_preview_label(u))

	assert_eq(preview.text, "Infantry 1 (40)")


func test_can_drop_card_data_accepts_only_the_trays_own_payload_shape() -> void:
	var tray := _tray()
	assert_true(tray._can_drop_card_data(Vector2.ZERO, {"row_idx": 0, "col_idx": 0}))
	assert_false(tray._can_drop_card_data(Vector2.ZERO, "not a drag payload"))
	assert_false(tray._can_drop_card_data(Vector2.ZERO, {"foo": "bar"}))


func test_drop_card_data_ignores_a_non_dictionary_payload() -> void:
	var tray := _tray()
	var u := _named_unit("Infantry 1")
	tray.sync_units([u])

	tray._drop_card_data(Vector2.ZERO, "not a drag payload", 0, 1)

	assert_eq(tray._grid[0][0], u, "no-op: the payload isn't shaped like a drag payload at all")


func test_drop_card_data_moves_a_card_to_an_empty_cell() -> void:
	var tray := _tray()
	var u := _named_unit("Infantry 1")
	tray.sync_units([u])   # u lands at (0, 0)

	tray._drop_card_data(Vector2.ZERO, {"row_idx": 0, "col_idx": 0}, 0, 2)

	assert_null(tray._grid[0][0], "the source cell is now empty")
	assert_eq(tray._grid[0][2], u, "...and the unit landed in the drop target cell")


func test_drop_card_data_onto_an_occupied_cell_swaps_the_two_units() -> void:
	var tray := _tray()
	var u1 := _named_unit("Hastati 1")
	var u2 := _named_unit("Principes 1")
	tray.sync_units([u1, u2])   # u1 at (0,0), u2 at (0,1)

	tray._drop_card_data(Vector2.ZERO, {"row_idx": 0, "col_idx": 0}, 0, 1)

	assert_eq(tray._grid[0][0], u2, "dropping u1 onto u2's cell swaps them")
	assert_eq(tray._grid[0][1], u1)


func test_drop_card_data_ignores_a_target_that_no_longer_exists() -> void:
	var tray := _tray()
	var u := _named_unit("Infantry 1")
	tray.sync_units([u])

	tray._drop_card_data(Vector2.ZERO, {"row_idx": 0, "col_idx": 0}, 9, 0)

	assert_eq(tray._grid[0][0], u, "no-op: the drop target named a row that doesn't exist")


func test_drop_card_data_ignores_a_payload_from_a_stale_cell() -> void:
	var tray := _tray()
	var u := _named_unit("Infantry 1")
	tray.sync_units([u])

	tray._drop_card_data(Vector2.ZERO, {"row_idx": 9, "col_idx": 0}, 0, 1)

	assert_eq(tray._grid[0][0], u, "no-op: the drag payload named a cell that doesn't exist")
