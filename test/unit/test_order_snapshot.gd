extends GutTest
## Order.to_dict()/from_dict(): the round-trip a replay state snapshot relies on
## to carry a unit's in-flight orders queue through a capture/restore.


func test_round_trip_preserves_a_simple_leaf_orders_scalar_fields() -> void:
	var o := Order.new_move(Vector2(120, 340), 2, Unit.GAIT_RUN, true)
	o.phase = Order.Phase.MARCH
	o.guard = Order.Guard.CONTACT_MADE
	o.guard_param = 5.0
	o.guard_uid = 7
	o._guard_ticks = 12
	o.reform = true
	o.pivot_return_angle = 0.4

	var r := Order.from_dict(o.to_dict())

	assert_eq(r.type, Order.Type.MOVE)
	assert_eq(r.phase, Order.Phase.MARCH)
	assert_eq(r.target_pos, Vector2(120, 340))
	assert_eq(r.order_mode, 2)
	assert_eq(r.gait, Unit.GAIT_RUN)
	assert_true(r.haste)
	assert_eq(r.guard, Order.Guard.CONTACT_MADE)
	assert_almost_eq(r.guard_param, 5.0, 0.001)
	assert_eq(r.guard_uid, 7)
	assert_eq(r._guard_ticks, 12)
	assert_true(r.reform)
	assert_almost_eq(r.pivot_return_angle, 0.4, 0.001)


func test_round_trip_preserves_maneuver_execution_state() -> void:
	var o := Order.new_wheel(1)
	o.turn_target = Vector2(0, -1)
	o.turn_start_facing = Vector2(1, 0)
	o.pivot = Vector2(500, 500)
	o.countermarch_variant = Unit.CountermarchVariant.LACONIAN

	var r := Order.from_dict(o.to_dict())

	assert_eq(r.type, Order.Type.WHEEL)
	assert_eq(r.dir, 1)
	assert_eq(r.turn_target, Vector2(0, -1))
	assert_eq(r.turn_start_facing, Vector2(1, 0))
	assert_eq(r.pivot, Vector2(500, 500))
	assert_eq(r.countermarch_variant, Unit.CountermarchVariant.LACONIAN)


func test_round_trip_preserves_a_reform_leaf() -> void:
	var o := Order.new_move(Vector2(10, 10))
	o.phase = Order.Phase.REFORM
	o.reform_timer = 0.35
	o.reform_until_settled = true
	o.reform_settle_eps = 4.0

	var r := Order.from_dict(o.to_dict())

	assert_eq(r.phase, Order.Phase.REFORM)
	assert_almost_eq(r.reform_timer, 0.35, 0.001)
	assert_true(r.reform_until_settled)
	assert_almost_eq(r.reform_settle_eps, 4.0, 0.001)


func test_round_trip_preserves_a_composite_orders_children_and_active_child() -> void:
	var parent := Order.new_move(Vector2(50, 50))
	var turn_leaf := Order.new_about_face()
	var march_leaf := Order.new_move(Vector2(50, 50))
	parent.children = [turn_leaf, march_leaf]
	parent._active_child = 1

	var r := Order.from_dict(parent.to_dict())

	assert_eq(r.children.size(), 2)
	assert_eq(r._active_child, 1)
	assert_eq(r.children[0].type, Order.Type.ABOUT_FACE)
	assert_eq(r.children[1].type, Order.Type.MOVE)
	assert_eq(r.children[0].parent, r, "a rebuilt child's parent points back at the rebuilt parent")
	assert_eq(r.active_leaf(), r.children[1], "active_leaf still resolves through the rebuilt tree")


func test_round_trip_a_leaf_order_with_no_children_reports_itself_as_the_active_leaf() -> void:
	var o := Order.new_stance(3, 1)
	var r := Order.from_dict(o.to_dict())
	assert_eq(r.active_leaf(), r)
	assert_true(r.children.is_empty())
