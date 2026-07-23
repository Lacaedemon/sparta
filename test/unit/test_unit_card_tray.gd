extends GutTest
## Multi-row unit card tray unit tests.

const UnitScript = preload("res://scripts/Unit.gd")


func test_unit_card_tray_rows_and_shifting() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)

	var u1 := UnitScript.new()
	u1.unit_name = "Hastati 1"
	add_child_autofree(u1)

	var u2 := UnitScript.new()
	u2.unit_name = "Principes 1"
	add_child_autofree(u2)

	tray.sync_units([u1, u2])
	assert_eq(tray.get_units_in_tray_order().size(), 2)

	# Add row and move u2 to line 2
	tray.add_row()
	tray.move_unit_down(0, 1)

	var ordered: Array = tray.get_units_in_tray_order()
	assert_eq(ordered.size(), 2)
	assert_eq(ordered[0], u1)
	assert_eq(ordered[1], u2)

	# Remove row restores u2 to row 0
	tray.remove_row()
	assert_eq(tray.get_units_in_tray_order().size(), 2)


## Regression test: cards_scroll (the ScrollContainer holding a line's unit cards) used to
## have no size_flags_horizontal, so an HBoxContainer parent never granted it more than its
## own 0-width minimum -- every card was permanently invisible (0 width), regardless of how
## many layout passes ran. Caught only by an actual screenshot, not by any prior test, since
## every existing test asserted on _rows (logical state) rather than real rendered size.
func test_cards_scroll_expands_to_fill_the_row_so_cards_are_actually_visible() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	tray.custom_minimum_size = Vector2(500, 0)   # matches HUD._build_unit_card_tray's own width
	var u := UnitScript.new()
	u.unit_name = "Infantry 1"
	add_child_autofree(u)
	tray.sync_units([u])

	for i in range(5):
		await get_tree().process_frame

	var row_hbox: HBoxContainer = tray._rows_container.get_child(0)
	var cards_scroll: ScrollContainer = row_hbox.get_child(1)
	assert_gt(cards_scroll.size.x, 100.0,
			"the cards area claims real width instead of collapsing to its 0-width minimum")


func test_settings_tray_row_order_placement_defaults_off() -> void:
	assert_false(Settings.show_unit_card_tray, "show_unit_card_tray defaults to false")
	assert_false(Settings.tray_row_order_placement, "tray_row_order_placement defaults to false")


# --- drag-and-drop card reordering -----------------------------------------------------
# The Godot drag-source/drop-target callbacks (_get_drag_card_data/_can_drop_card_data/
# _drop_card_data) are pure functions wired via set_drag_forwarding() rather than relying
# on Godot's own DND machinery -- exercised directly here, with no real drag/drop event.

func test_get_drag_card_data_returns_the_dragged_cards_indices() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var u := UnitScript.new()
	add_child_autofree(u)
	tray.sync_units([u])

	var data = tray._get_drag_card_data(Vector2.ZERO, 0, 0)

	assert_eq(data, {"row_idx": 0, "col_idx": 0})


func test_get_drag_card_data_refuses_a_stale_index() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	assert_null(tray._get_drag_card_data(Vector2.ZERO, 5, 0), "row_idx past the last line")
	assert_null(tray._get_drag_card_data(Vector2.ZERO, 0, 5), "col_idx past an empty line")


func test_get_drag_card_data_refuses_a_dead_unit_at_an_otherwise_valid_index() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var u := UnitScript.new()
	add_child_autofree(u)
	tray.sync_units([u])
	u.state = UnitScript.State.DEAD

	assert_null(tray._get_drag_card_data(Vector2.ZERO, 0, 0), "a dead unit can't be dragged")


func test_drag_preview_label_shows_the_units_name_and_soldier_count() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var u := UnitScript.new()
	u.unit_name = "Infantry 1"
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers -- override only after this
	u.soldiers = 40

	var preview: Label = autofree(tray._drag_preview_label(u))

	assert_eq(preview.text, "Infantry 1 (40)")


func test_can_drop_card_data_accepts_only_the_trays_own_payload_shape() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	assert_true(tray._can_drop_card_data(Vector2.ZERO, {"row_idx": 0, "col_idx": 0}))
	assert_false(tray._can_drop_card_data(Vector2.ZERO, "not a drag payload"))
	assert_false(tray._can_drop_card_data(Vector2.ZERO, {"foo": "bar"}))


func test_drop_card_data_ignores_a_non_dictionary_payload() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var u := UnitScript.new()
	add_child_autofree(u)
	tray.sync_units([u])

	tray._drop_card_data(Vector2.ZERO, "not a drag payload", 0, autofree(HBoxContainer.new()))

	assert_eq(tray._rows[0], [u], "no-op: the payload isn't shaped like a drag payload at all")


func test_drop_card_data_ignores_a_target_line_that_no_longer_exists() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var u := UnitScript.new()
	add_child_autofree(u)
	tray.sync_units([u])   # only row 0 exists

	tray._drop_card_data(Vector2.ZERO, {"row_idx": 0, "col_idx": 0}, 3, autofree(HBoxContainer.new()))

	assert_eq(tray._rows[0], [u], "no-op: the drop target named a line that no longer exists")


## Three placeholder Controls at x=0/60/120, width 50 (centers at 25/85/145) -- NOT added to
## the scene tree, so nothing auto-repositions them; purely for exercising the geometry math.
func _three_card_positions_hbox() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	for i in range(3):
		var c := Control.new()
		c.position = Vector2(i * 60, 0)
		c.size = Vector2(50, 40)
		hbox.add_child(c)
	return hbox


func test_drop_index_in_row_finds_the_closest_gap() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var hbox: HBoxContainer = autofree(_three_card_positions_hbox())

	assert_eq(tray._drop_index_in_row(hbox, -10.0), 0, "before every card's center -> index 0")
	assert_eq(tray._drop_index_in_row(hbox, 100.0), 2, "between card 1 and 2's centers -> index 2")
	assert_eq(tray._drop_index_in_row(hbox, 1000.0), 3, "past every card -> appended at the end")


func test_drop_index_in_row_skips_a_non_control_child() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var hbox: HBoxContainer = autofree(_three_card_positions_hbox())
	# A stray non-Control child (e.g. a bookkeeping Node some other caller left behind) has
	# no position/size to compare against and must be skipped, not miscounted as a card.
	hbox.add_child(autofree(Node.new()))

	assert_eq(tray._drop_index_in_row(hbox, -10.0), 0, "still finds the first real card's gap")


func test_drop_card_data_moves_a_card_to_a_different_line() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var u1 := UnitScript.new()
	add_child_autofree(u1)
	var u2 := UnitScript.new()
	add_child_autofree(u2)
	tray.sync_units([u1, u2])   # both land in row 0
	tray.add_row()              # row 1 now exists, empty

	tray._drop_card_data(Vector2.ZERO, {"row_idx": 0, "col_idx": 0}, 1, autofree(HBoxContainer.new()))

	assert_eq(tray._rows[0], [u2], "u1 left row 0")
	assert_eq(tray._rows[1], [u1], "...and landed in row 1")


func test_drop_card_data_reorders_within_the_same_line() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var u1 := UnitScript.new()
	add_child_autofree(u1)
	var u2 := UnitScript.new()
	add_child_autofree(u2)
	var u3 := UnitScript.new()
	add_child_autofree(u3)
	tray.sync_units([u1, u2, u3])   # row 0: [u1, u2, u3]
	var hbox: HBoxContainer = autofree(_three_card_positions_hbox())

	# Drag u3 (col 2) to drop near card 0's position -> lands at the front of its own line.
	tray._drop_card_data(Vector2(-10.0, 0), {"row_idx": 0, "col_idx": 2}, 0, hbox)

	assert_eq(tray._rows[0], [u3, u1, u2], "u3 moved to the front of its own line")


func test_drop_card_data_shifts_the_target_index_when_dragging_forward_in_the_same_line() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var u1 := UnitScript.new()
	add_child_autofree(u1)
	var u2 := UnitScript.new()
	add_child_autofree(u2)
	var u3 := UnitScript.new()
	add_child_autofree(u3)
	tray.sync_units([u1, u2, u3])   # row 0: [u1, u2, u3]
	var hbox: HBoxContainer = autofree(_three_card_positions_hbox())

	# Drag u1 (col 0) to drop near card 2's position (index 2 in the PRE-removal layout) --
	# removing col 0 first shifts that target back by one, landing u1 just before u3.
	tray._drop_card_data(Vector2(100.0, 0), {"row_idx": 0, "col_idx": 0}, 0, hbox)

	assert_eq(tray._rows[0], [u2, u1, u3], "u1 moved forward, ending up just before u3")


func test_drop_card_data_ignores_a_payload_from_a_stale_line() -> void:
	var tray := UnitCardTray.new()
	add_child_autofree(tray)
	var u := UnitScript.new()
	add_child_autofree(u)
	tray.sync_units([u])   # only row 0 exists

	tray._drop_card_data(Vector2.ZERO, {"row_idx": 3, "col_idx": 0}, 0, autofree(HBoxContainer.new()))

	assert_eq(tray._rows[0], [u], "no-op: the drag payload named a line that no longer exists")
