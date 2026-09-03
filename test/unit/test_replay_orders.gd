extends GutTest
## Tests for ReplayOrders: order stream storage, cursor advancement,
## rewind repositioning, and boundary-inclusive pulse and form-up queries.

const HelperScript = preload("res://scripts/ReplayOrders.gd")


func _fresh() -> HelperScript:
	var h := HelperScript.new()
	return h


func test_reset_and_append() -> void:
	var o := _fresh()
	assert_true(o.orders.is_empty(), "starts with empty orders")
	assert_eq(o.play_index, 0, "starts at play_index 0")
	o.append({"tick": 10, "x": 1.0, "y": 2.0})
	assert_eq(o.orders.size(), 1, "order appended")
	o.play_index = 1
	o.reset()
	assert_true(o.orders.is_empty(), "reset clears orders")
	assert_eq(o.play_index, 0, "reset clears play_index")


func test_orders_for_tick_stepping_and_rewind() -> void:
	var o := _fresh()
	o.append({"tick": 10, "val": "first"})
	o.append({"tick": 10, "val": "second"})
	o.append({"tick": 20, "val": "third"})
	assert_true(o.orders_for_tick(5).is_empty(), "tick before any orders returns empty")
	assert_eq(o.play_index, 0, "play_index does not advance when tick is before next order")
	var due_10: Array = o.orders_for_tick(10)
	assert_eq(due_10.size(), 2, "returns both orders due at tick 10")
	assert_eq(str(due_10[0]["val"]), "first", "first order matches record order")
	assert_eq(str(due_10[1]["val"]), "second", "second order matches record order")
	assert_eq(o.play_index, 2, "play_index advanced past tick 10")
	var due_10_again: Array = o.orders_for_tick(10)
	assert_true(due_10_again.is_empty(), "subsequent call at same tick returns empty")
	o.rewind_cursor_to_tick(10)
	assert_eq(o.play_index, 0, "rewind to tick 10 repositions cursor to first order")
	var due_rewound: Array = o.orders_for_tick(10)
	assert_eq(due_rewound.size(), 2, "orders at tick 10 replay cleanly after rewind")
	o.rewind_cursor_to_tick(15)
	assert_eq(o.play_index, 2, "rewind to tick 15 lands before tick 20")
	var due_20: Array = o.orders_for_tick(20)
	assert_eq(due_20.size(), 1, "tick 20 order returns")
	assert_eq(str(due_20[0]["val"]), "third", "returns third order")


func test_pulses_for_tick_window_boundary_inclusivity() -> void:
	var o := _fresh()
	o.append({"tick": 10, "x": 100.0, "y": 200.0})
	o.append({"tick": 20, "x": 300.0, "y": 400.0})
	o.append({"tick": 30, "x": 500.0, "y": 600.0})
	var pulses_early: Array = o.pulses_for_tick(5, 5)
	assert_true(pulses_early.is_empty(), "no pulses when tick is before all orders")
	# At tick 20 with window 10:
	# ot=10: tick - ot = 20 - 10 = 10 <= 10 (exact inclusive boundary match)
	# ot=20: tick - ot = 20 - 20 = 0 <= 10 (inside window)
	# ot=30: ot > tick -> break
	var pulses_boundary: Array = o.pulses_for_tick(20, 10)
	assert_eq(pulses_boundary.size(), 2, "includes order exactly at window boundary")
	assert_eq(pulses_boundary[0]["age"], 10, "first order has age 10")
	assert_eq(pulses_boundary[0]["x"], 100.0, "first order x matches")
	assert_eq(pulses_boundary[0]["y"], 200.0, "first order y matches")
	assert_eq(pulses_boundary[1]["age"], 0, "second order has age 0")
	assert_eq(pulses_boundary[1]["x"], 300.0, "second order x matches")
	assert_eq(pulses_boundary[1]["y"], 400.0, "second order y matches")
	# At tick 21 with window 10:
	# ot=10: tick - ot = 21 - 10 = 11 > 10 (past window boundary, dropped)
	# ot=20: tick - ot = 21 - 20 = 1 <= 10 (inside window)
	var pulses_outside: Array = o.pulses_for_tick(21, 10)
	assert_eq(pulses_outside.size(), 1, "order outside window is dropped")
	assert_eq(pulses_outside[0]["age"], 1, "retained order has age 1")
	assert_eq(pulses_outside[0]["x"], 300.0, "retained order x matches")
	assert_eq(pulses_outside[0]["y"], 400.0, "retained order y matches")


func test_form_ups_for_tick_window_boundary_inclusivity() -> void:
	var o := _fresh()
	# Order without "face" is skipped.
	o.append({"tick": 10, "x": 10.0, "y": 20.0, "units": [42]})
	# Order with "face" and frontage.
	o.append({"tick": 10, "x": 30.0, "y": 40.0, "face": 1.5, "frontage": 8, "units": [99]})
	# Order with "face", empty units, and no frontage.
	o.append({"tick": 20, "x": 50.0, "y": 60.0, "face": 0.0, "units": []})
	# Future order.
	o.append({"tick": 35, "x": 70.0, "y": 80.0, "face": 0.5, "units": [42]})
	# At tick 20 with window 10:
	# ot=10: tick - ot = 10 <= 10 (exact boundary). Non-face skipped; face included.
	# ot=20: tick - ot = 0 <= 10. Face included, frontage defaulted to 1, uid -1.
	# ot=35: ot > tick -> break.
	var fu: Array = o.form_ups_for_tick(20, 10)
	assert_eq(fu.size(), 2, "exact boundary included and non-face skipped")
	assert_eq(fu[0]["x"], 30.0, "fu 0 x")
	assert_eq(fu[0]["y"], 40.0, "fu 0 y")
	assert_eq(fu[0]["face"], 1.5, "fu 0 face")
	assert_eq(fu[0]["frontage"], 8, "fu 0 frontage")
	assert_eq(fu[0]["age"], 10, "fu 0 age")
	assert_eq(fu[0]["uid"], 99, "fu 0 uid")
	assert_eq(fu[1]["x"], 50.0, "fu 1 x")
	assert_eq(fu[1]["y"], 60.0, "fu 1 y")
	assert_eq(fu[1]["face"], 0.0, "fu 1 face")
	assert_eq(fu[1]["frontage"], 1, "fu 1 defaulted frontage")
	assert_eq(fu[1]["age"], 0, "fu 1 age")
	assert_eq(fu[1]["uid"], -1, "fu 1 empty units yield -1 uid")
	# At tick 21 with window 10:
	# ot=10 has tick - ot = 11 > 10 (outside window)
	var fu_outside: Array = o.form_ups_for_tick(21, 10)
	assert_eq(fu_outside.size(), 1, "order outside window is excluded")
	assert_eq(fu_outside[0]["age"], 1, "fu age is 1")
	assert_eq(fu_outside[0]["uid"], -1, "fu uid is -1")
