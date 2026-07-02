extends GutTest
## Order value type (docs/orders-queue-design.md phases 1-2, #522/#523): pure, node-free tests
## for the enum-name tables, the readable describe() string, and the constructor helpers used
## to build each order kind.


func test_type_name_maps_every_known_type() -> void:
	assert_eq(Order.type_name(Order.Type.MOVE), "MOVE")
	assert_eq(Order.type_name(Order.Type.ATTACK), "ATTACK")
	assert_eq(Order.type_name(Order.Type.RELIEF), "RELIEF")
	assert_eq(Order.type_name(Order.Type.SUPPORT), "SUPPORT")
	assert_eq(Order.type_name(Order.Type.WHEEL), "WHEEL")
	assert_eq(Order.type_name(Order.Type.NUDGE), "NUDGE")
	assert_eq(Order.type_name(Order.Type.FORMATION), "FORMATION")
	assert_eq(Order.type_name(Order.Type.FRONTAGE), "FRONTAGE")
	assert_eq(Order.type_name(Order.Type.ABOUT_FACE), "ABOUT_FACE")
	assert_eq(Order.type_name(Order.Type.QUARTER_TURN), "QUARTER_TURN")


func test_phase_name_maps_every_known_phase() -> void:
	assert_eq(Order.phase_name(Order.Phase.NONE), "NONE")
	assert_eq(Order.phase_name(Order.Phase.TURN), "TURN")
	assert_eq(Order.phase_name(Order.Phase.MARCH), "MARCH")
	assert_eq(Order.phase_name(Order.Phase.REFORM), "REFORM")


func test_type_name_falls_back_for_an_unmapped_value() -> void:
	assert_eq(Order.type_name(99), "TYPE(99)")


func test_phase_name_falls_back_for_an_unmapped_value() -> void:
	assert_eq(Order.phase_name(99), "PHASE(99)")


func test_describe_omits_the_phase_when_unphased() -> void:
	var o := Order.new_wheel(1)
	assert_eq(o.describe(), "WHEEL")


func test_describe_includes_the_phase_when_phased() -> void:
	var o := Order.new_move(Vector2(1, 2))
	o.phase = Order.Phase.TURN
	assert_eq(o.describe(), "MOVE:TURN")


func test_new_move_defaults_to_unphased() -> void:
	var o := Order.new_move(Vector2(5, 5))
	assert_eq(o.type, Order.Type.MOVE)
	assert_eq(o.phase, Order.Phase.NONE)
	assert_eq(o.target_pos, Vector2(5, 5))


func test_new_move_starts_with_idle_maneuver_state() -> void:
	# The maneuver execution state (phase 2) is armed by Unit.begin_about_face / the drill
	# methods, never by the constructor.
	var o := Order.new_move(Vector2(5, 5))
	assert_eq(o.turn_target, Vector2.ZERO)
	assert_eq(o.pivot, Vector2.ZERO)
	assert_false(o.reform)


func test_new_about_face_and_new_quarter_turn_carry_their_kind() -> void:
	assert_eq(Order.new_about_face().type, Order.Type.ABOUT_FACE)
	var q := Order.new_quarter_turn(-1)
	assert_eq(q.type, Order.Type.QUARTER_TURN)
	assert_eq(q.dir, -1)


func test_new_attack_carries_target_uid_and_mode() -> void:
	var o := Order.new_attack(7, 2)
	assert_eq(o.type, Order.Type.ATTACK)
	assert_eq(o.target_uid, 7)
	assert_eq(o.order_mode, 2)


func test_new_relief_and_new_support_carry_target_uid() -> void:
	assert_eq(Order.new_relief(3).target_uid, 3)
	assert_eq(Order.new_support(4).target_uid, 4)


func test_new_wheel_and_new_nudge_carry_direction() -> void:
	assert_eq(Order.new_wheel(-1).dir, -1)
	assert_eq(Order.new_nudge(2).dir, 2)


func test_new_formation_and_new_frontage_carry_their_value() -> void:
	assert_eq(Order.new_formation(3).formation, 3)
	assert_eq(Order.new_frontage(6).frontage, 6)
