extends GutTest
## Verifies that _corridor_to_slot uses the wider MARCHING_CORRIDOR_PROXIMITY_MULT
## only during straight-line marching, and falls back to standard CORRIDOR_PROXIMITY_MULT
## when the unit is turning, wheeling, or curving around terrain.

var _unit: Unit = null


func before_each() -> void:
	_unit = Unit.new()
	_unit.max_soldiers = 30
	add_child_autofree(_unit)
	_unit.facing = Vector2.DOWN
	_unit.position = Vector2(500, 500)
	_unit.seed_sim_soldiers()


func test_straight_march_uses_wide_proximity_for_direct_arrival() -> void:
	# Straight march down: approach velocity aligned with facing
	_unit.facing = Vector2.DOWN
	_unit._approach_velocity = Vector2(0, 100)
	_unit.state = Unit.State.MOVING

	var spacing: float = _unit.file_pitch_wu()
	var slot_pos: Vector2 = _unit._sim_soldier_pos[0]
	# Place soldier at distance 3.0 * spacing (between 1.5 and 4.5) across ranks and files
	var soldier_pos: Vector2 = slot_pos + Vector2(spacing * 2.0, spacing * 2.0)
	_unit._sim_soldier_pos[0] = soldier_pos

	var target_vec: Vector2 = SoldierBodies._corridor_to_slot(_unit, 0, slot_pos, _unit.soldiers)
	var expected_direct: Vector2 = slot_pos - soldier_pos
	assert_almost_eq(target_vec.x, expected_direct.x, 1e-3, "straight march allows direct arrival within wide threshold (x)")
	assert_almost_eq(target_vec.y, expected_direct.y, 1e-3, "straight march allows direct arrival within wide threshold (y)")


func test_turning_march_falls_back_to_perimeter_corridor() -> void:
	# Curved march / turning: approach velocity angled relative to facing (e.g. 45 degrees)
	_unit.facing = Vector2.DOWN
	_unit._approach_velocity = Vector2(100, 100).normalized() * 100.0   # dot with DOWN is ~0.707 < 0.95
	_unit.state = Unit.State.MOVING

	var spacing: float = _unit.file_pitch_wu()
	var slot_pos: Vector2 = _unit._sim_soldier_pos[0]
	# Place soldier at distance 3.0 * spacing across ranks and files
	var soldier_pos: Vector2 = slot_pos + Vector2(spacing * 2.0, spacing * 2.0)
	_unit._sim_soldier_pos[0] = soldier_pos

	var target_vec: Vector2 = SoldierBodies._corridor_to_slot(_unit, 0, slot_pos, _unit.soldiers)
	var direct_vec: Vector2 = slot_pos - soldier_pos
	# When falling back to standard corridor, target vector must NOT equal direct vector
	var diff_len_sq: float = (target_vec - direct_vec).length_squared()
	assert_gt(diff_len_sq, 1.0, "curved march routes through perimeter corridor instead of cutting across files")


func test_stationary_unit_uses_standard_proximity() -> void:
	# Stationary unit: approach velocity zero
	_unit.facing = Vector2.DOWN
	_unit._approach_velocity = Vector2.ZERO
	_unit.state = Unit.State.IDLE

	var spacing: float = _unit.file_pitch_wu()
	var slot_pos: Vector2 = _unit._sim_soldier_pos[0]
	# Place soldier at distance 3.0 * spacing across ranks and files
	var soldier_pos: Vector2 = slot_pos + Vector2(spacing * 2.0, spacing * 2.0)
	_unit._sim_soldier_pos[0] = soldier_pos

	var target_vec: Vector2 = SoldierBodies._corridor_to_slot(_unit, 0, slot_pos, _unit.soldiers)
	var direct_vec: Vector2 = slot_pos - soldier_pos
	var diff_len_sq: float = (target_vec - direct_vec).length_squared()
	assert_gt(diff_len_sq, 1.0, "stationary unit routes through corridor at distance 3.0 * pitch")
