extends GutTest
## Multi-row unit card tray unit tests (#869).

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


func test_settings_tray_row_order_placement_defaults_off() -> void:
	assert_false(Settings.show_unit_card_tray, "show_unit_card_tray defaults to false")
	assert_false(Settings.tray_row_order_placement, "tray_row_order_placement defaults to false")
