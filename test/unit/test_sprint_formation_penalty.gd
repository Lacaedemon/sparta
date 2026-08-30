extends GutTest
## Unit tests verifying restrictions and penalties on mid-sprint formation density,
## stance, and frontage transitions.

func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func test_stationary_formation_change_incurs_no_penalty() -> void:
	var u := _make_unit()
	assert_eq(u.current_speed, 0.0)
	var initial_cohesion := u.cohesion
	var initial_fatigue := u.fatigue

	u.set_formation(Unit.FORMATION_TIGHT)

	assert_eq(u.formation_mode, Unit.FORMATION_TIGHT)
	assert_eq(u.cohesion, initial_cohesion, "stationary formation change does not reduce cohesion")
	assert_eq(u.fatigue, initial_fatigue, "stationary formation change does not add fatigue")


func test_mid_sprint_formation_change_drops_speed_and_penalizes_cohesion_and_fatigue() -> void:
	var u := _make_unit()
	u._current_speed = u.move_speed
	u._approach_velocity = Vector2.DOWN * u.move_speed
	u.cohesion = 1.0
	u.fatigue = 0.0

	var order := Order.new_move(Vector2(0, 500))
	order.gait = Unit.GAIT_SPRINT
	u.set_current_order(order)

	u.set_formation(Unit.FORMATION_TIGHT)

	assert_eq(u.formation_mode, Unit.FORMATION_TIGHT)
	assert_almost_eq(u.current_speed, u.walk_speed, 0.01, "speed drops to walk_speed")
	assert_almost_eq(u.cohesion, 1.0 - Unit.SPRINT_RESHAPE_COHESION_PENALTY, 0.01, "cohesion suffers transient penalty")
	assert_almost_eq(u.fatigue, Unit.SPRINT_RESHAPE_FATIGUE_PENALTY, 0.01, "fatigue increases")
	assert_eq(u.current_order.gait, Unit.GAIT_WALK, "order gait drops to walk")
	assert_almost_eq(u._approach_velocity.length(), u.walk_speed, 0.01, "approach velocity scales to walk speed")


func test_mid_sprint_frontage_change_penalizes_unit() -> void:
	var u := _make_unit(120)
	u._current_speed = u.move_speed
	u._approach_velocity = Vector2.DOWN * u.move_speed
	u.cohesion = 1.0
	u.fatigue = 10.0

	var old_files := UnitFormation.frontage(u)
	u.set_frontage(old_files + 4)

	assert_almost_eq(u.current_speed, u.walk_speed, 0.01, "frontage reshape drops speed to walk_speed")
	assert_almost_eq(u.cohesion, 1.0 - Unit.SPRINT_RESHAPE_COHESION_PENALTY, 0.01, "cohesion penalty applied")
	assert_almost_eq(u.fatigue, 10.0 + Unit.SPRINT_RESHAPE_FATIGUE_PENALTY, 0.01, "fatigue penalty applied")


func test_same_formation_reapply_is_noop() -> void:
	var u := _make_unit()
	u._current_speed = u.move_speed
	u._approach_velocity = Vector2.DOWN * u.move_speed
	u.cohesion = 1.0
	u.fatigue = 0.0
	u.formation_mode = Unit.FORMATION_TIGHT

	u.set_formation(Unit.FORMATION_TIGHT)

	assert_almost_eq(u.current_speed, u.move_speed, 0.01, "re-applying same formation mode does not drop speed")
	assert_eq(u.cohesion, 1.0, "cohesion unchanged")
	assert_eq(u.fatigue, 0.0, "fatigue unchanged")
