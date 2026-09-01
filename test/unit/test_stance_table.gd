extends GutTest

## Unit tests for StanceTable and order-mode orthogonal flags table (#956).

func test_stance_table_flags_sanity() -> void:
	# Check normal stance
	var normal_flags := StanceTable.get_flags(0)
	assert_true(normal_flags.target_visible_enemies, "normal acquires visible enemies")
	assert_true(normal_flags.auto_advance, "normal auto-advances")
	assert_true(normal_flags.allow_intermixing, "normal allows intermixing")
	assert_false(normal_flags.respond_chase, "normal does not relentless chase")
	assert_false(normal_flags.can_give_ground, "normal does not give ground")

	# Check hold stance
	var hold_flags := StanceTable.get_flags(1)
	assert_false(hold_flags.target_visible_enemies, "hold does not proactively acquire distant enemies")
	assert_false(hold_flags.auto_advance, "hold does not auto advance")
	assert_false(hold_flags.allow_intermixing, "hold does not allow intermixing")
	assert_true(hold_flags.respond_hold_ground, "hold responds hold ground")

	# Check brace stance
	var brace_flags := StanceTable.get_flags(18)
	assert_false(brace_flags.target_visible_enemies, "brace does not proactively acquire distant enemies")
	assert_false(brace_flags.auto_advance, "brace does not auto advance")
	assert_false(brace_flags.allow_intermixing, "brace does not allow intermixing")

	# Check give ground and push
	assert_true(StanceTable.is_giving_ground(14), "14 is give ground")
	assert_true(StanceTable.is_pushing(15), "15 is push")
	assert_true(StanceTable.has_multi_engage_reflow(16), "16 has multi engage reflow")
	assert_true(StanceTable.has_flank_wrap(19), "19 has flank wrap")
	assert_true(StanceTable.is_march_to_contact(17), "17 is march to contact")

func test_unit_held_position_and_leash_initialization() -> void:
	var u := Unit.new()
	add_child_autofree(u)
	u.position = Vector2(500, 300)
	u.order_mode = Unit.ORDER_PIN_DOWN
	assert_eq(u.held_position, Vector2(500, 300), "setting stance sets held position if zero")
	assert_gt(u.leash_radius, 0.0, "pin down sets positive default leash radius")

func test_order_forced_tag_defaults() -> void:
	var o := Order.new_move(Vector2(100, 200), 0)
	assert_true(o.forced, "move order is forced by default")
	var o_atk := Order.new_attack(1, 0)
	assert_true(o_atk.forced, "attack order is forced by default")
