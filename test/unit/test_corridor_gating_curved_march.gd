extends GutTest
## Verifies that a soldier body's arrival target (SoldierBodies.arrival_target) uses the
## wider MARCHING_CORRIDOR_PROXIMITY_MULT at full march speed (a straight march, a
## held-facing retreat, or a lateral side-step), and falls back to standard
## CORRIDOR_PROXIMITY_MULT while stationary. A TURNING march keeps
## the wide band whatever the block's depth: a deep 80-mount cavalry block (depth ratio ~2.81
## -- see Unit.FORMED_TURN_DEPTH_RATIO_REF's own doc comment) and a shallow 60-man infantry
## line alike.
## On extreme lag the code still tests the wide band first and, when a body is too far behind
## for even that band to cover, falls through to perimeter routing directly -- it never
## recomputes against the narrow multiplier.

var _unit: Unit = null


func before_each() -> void:
	_unit = Unit.new()
	_unit.max_soldiers = 30
	add_child_autofree(_unit)
	_unit.facing = Vector2.DOWN
	_unit.position = Vector2(500, 500)
	_unit.seed_sim_soldiers()


## A 60-man infantry line, matching test_wheel_turn_maneuver.gd's own shallow fixture --
## its depth ratio stays well under FORMED_TURN_FREE_DEPTH_RATIO, so its formed turn is not
## derated (Unit._formed_turn_gait_frac is 1.0).
func _make_shallow_infantry_60(pos: Vector2 = Vector2(500, 500)) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = pos
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	return u


## An 80-mount cavalry block, matching test_wheel_turn_maneuver.gd's own
## _make_cavalry_80 -- the exact fixture FORMED_TURN_DEPTH_RATIO_REF is calibrated against
## (pivot radius 505.9644 wu, depth ratio 2.810913), so its formed turn is derated
## (Unit._formed_turn_gait_frac under 1.0).
func _make_deep_cavalry_80(pos: Vector2 = Vector2(500, 500)) -> Unit:
	var u: Unit = Unit.new()
	u.is_cavalry = true
	u.max_soldiers = 80
	u.soldiers = 80
	u.position = pos
	u.facing = Vector2.UP
	u.file_pitch = 20.0
	u.rank_pitch = 60.0
	u.walk_speed = 34.0
	u.jog_speed = 70.0
	u.move_speed = 170.0
	u.accel = 40.0
	u.decel = 40.0
	add_child_autofree(u)
	u.seed_sim_soldiers()
	return u


func test_straight_march_uses_wide_proximity_for_direct_arrival() -> void:
	# Straight march down: approach velocity aligned with facing, not turning
	_unit.facing = Vector2.DOWN
	_unit._approach_velocity = Vector2(0, 100)
	_unit.state = Unit.State.MOVING

	var spacing: float = _unit.file_pitch_wu()
	var slot_pos: Vector2 = _unit._sim_soldier_pos[0]
	# Place soldier at distance 3.0 * spacing (between 1.5 and 4.5) across ranks and files
	var soldier_pos: Vector2 = slot_pos + Vector2(spacing * 2.0, spacing * 2.0)
	_unit._sim_soldier_pos[0] = soldier_pos

	var target_vec: Vector2 = SoldierBodies.arrival_target(_unit, 0, slot_pos, _unit.soldiers, SoldierBodies.march_target_frac(_unit), not _unit.is_turning())
	var expected_direct: Vector2 = slot_pos - soldier_pos
	assert_almost_eq(target_vec.x, expected_direct.x, 1e-3, "straight march allows direct arrival within wide threshold (x)")
	assert_almost_eq(target_vec.y, expected_direct.y, 1e-3, "straight march allows direct arrival within wide threshold (y)")


func test_held_facing_retreat_uses_wide_proximity() -> void:
	# Disengage / relief retreat: stepping straight back while holding facing to enemy
	_unit.facing = Vector2.DOWN
	_unit._approach_velocity = Vector2(0, -100)   # moving backward (-facing)
	_unit.state = Unit.State.MOVING

	var spacing: float = _unit.file_pitch_wu()
	var slot_pos: Vector2 = _unit._sim_soldier_pos[0]
	var soldier_pos: Vector2 = slot_pos + Vector2(spacing * 2.0, spacing * 2.0)
	_unit._sim_soldier_pos[0] = soldier_pos

	var target_vec: Vector2 = SoldierBodies.arrival_target(_unit, 0, slot_pos, _unit.soldiers, SoldierBodies.march_target_frac(_unit), not _unit.is_turning())
	var expected_direct: Vector2 = slot_pos - soldier_pos
	assert_almost_eq(target_vec.x, expected_direct.x, 1e-3, "held-facing retreat allows direct arrival (x)")
	assert_almost_eq(target_vec.y, expected_direct.y, 1e-3, "held-facing retreat allows direct arrival (y)")


func test_held_facing_lateral_sidestep_uses_wide_proximity() -> void:
	# Lateral side-step: moving sideways while holding facing forward
	_unit.facing = Vector2.DOWN
	_unit._approach_velocity = Vector2(100, 0)   # moving right perpendicular to facing
	_unit.state = Unit.State.MOVING

	var spacing: float = _unit.file_pitch_wu()
	var slot_pos: Vector2 = _unit._sim_soldier_pos[0]
	var soldier_pos: Vector2 = slot_pos + Vector2(spacing * 2.0, spacing * 2.0)
	_unit._sim_soldier_pos[0] = soldier_pos

	var target_vec: Vector2 = SoldierBodies.arrival_target(_unit, 0, slot_pos, _unit.soldiers, SoldierBodies.march_target_frac(_unit), not _unit.is_turning())
	var expected_direct: Vector2 = slot_pos - soldier_pos
	assert_almost_eq(target_vec.x, expected_direct.x, 1e-3, "lateral sidestep allows direct arrival (x)")
	assert_almost_eq(target_vec.y, expected_direct.y, 1e-3, "lateral sidestep allows direct arrival (y)")


func test_deep_turning_march_uses_wide_proximity_for_direct_arrival() -> void:
	# Curved march / active rotation on a DEEP block (80-mount cavalry, depth ratio 2.81):
	# the wide marching corridor proximity holds through the turn, not just while marching
	# straight -- see MARCHING_CORRIDOR_PROXIMITY_MULT's own doc comment.
	var deep_unit: Unit = _make_deep_cavalry_80()
	deep_unit._approach_velocity = Vector2(100, 100)
	deep_unit.state = Unit.State.MOVING
	# Simulate active turn steering
	deep_unit._rotate_facing_toward(Vector2.RIGHT, 0.016, 2.0)
	assert_true(deep_unit.is_turning(), "unit reports is_turning while rotating facing")
	assert_lt(deep_unit._formed_turn_gait_frac(), 1.0,
		"80-mount cavalry block is deep enough to derate its corner-slot pace")

	var spacing: float = deep_unit.file_pitch_wu()
	var slot_pos: Vector2 = deep_unit._sim_soldier_pos[0]
	# Place soldier at distance 2.83 * spacing (between 1.5 and 4.5) across ranks and files
	var soldier_pos: Vector2 = slot_pos + Vector2(spacing * 2.0, spacing * 2.0)
	deep_unit._sim_soldier_pos[0] = soldier_pos

	var target_vec: Vector2 = SoldierBodies.arrival_target(deep_unit, 0, slot_pos, deep_unit.soldiers, SoldierBodies.march_target_frac(deep_unit), not deep_unit.is_turning())
	var expected_direct: Vector2 = slot_pos - soldier_pos
	assert_almost_eq(target_vec.x, expected_direct.x, 1e-3, "deep block's curved march allows direct arrival within wide threshold (x)")
	assert_almost_eq(target_vec.y, expected_direct.y, 1e-3, "deep block's curved march allows direct arrival within wide threshold (y)")


func test_shallow_turning_march_uses_wide_proximity_for_direct_arrival() -> void:
	# Curved march / active rotation on a SHALLOW block (60-man infantry line, far below
	# FORMED_TURN_FREE_DEPTH_RATIO): its formed turn is never derated, and it keeps the wide
	# marching band through the turn all the same. A combat re-face can turn a marching
	# block's whole slot grid in one tick, leaving its end men ranks across and files along
	# from their slots; with the narrow band each was sent round the perimeter corridor while
	# the block kept turning, and the block did not re-form (the support clip's archers, see
	# SoldierBodies.march_target_frac's doc comment for the measurement).
	var shallow_unit: Unit = _make_shallow_infantry_60()
	shallow_unit._approach_velocity = Vector2(100, 100)
	shallow_unit.state = Unit.State.MOVING
	shallow_unit._rotate_facing_toward(Vector2.RIGHT, 0.016, 2.0)
	assert_true(shallow_unit.is_turning(), "unit reports is_turning while rotating facing")
	assert_eq(shallow_unit._formed_turn_gait_frac(), 1.0,
		"60-man infantry line is not deep enough to derate its corner-slot pace")

	var spacing: float = shallow_unit.file_pitch_wu()
	var slot_pos: Vector2 = shallow_unit._sim_soldier_pos[0]
	# Place soldier at distance 2.83 * spacing -- beyond the narrow CORRIDOR_PROXIMITY_MULT
	# (1.5x) band but well within the wide MARCHING_CORRIDOR_PROXIMITY_MULT (4.5x) band, so
	# this walks direct only if the shallow turning march uses the wide band.
	var soldier_pos: Vector2 = slot_pos + Vector2(spacing * 2.0, spacing * 2.0)
	shallow_unit._sim_soldier_pos[0] = soldier_pos

	var target_vec: Vector2 = SoldierBodies.arrival_target(shallow_unit, 0, slot_pos, shallow_unit.soldiers, SoldierBodies.march_target_frac(shallow_unit), not shallow_unit.is_turning())
	var expected_direct: Vector2 = slot_pos - soldier_pos
	assert_almost_eq(target_vec.x, expected_direct.x, 1e-3, "shallow block's curved march walks direct within the wide band (x)")
	assert_almost_eq(target_vec.y, expected_direct.y, 1e-3, "shallow block's curved march walks direct within the wide band (y)")


func test_turning_march_extreme_lag_falls_back_to_perimeter_corridor() -> void:
	# Curved march with lag exceeding the wide threshold (hypot = 4.95 * spacing > 4.5), on
	# the deep cavalry fixture so the wide band is actually in play to fall back from.
	var deep_unit: Unit = _make_deep_cavalry_80()
	deep_unit._approach_velocity = Vector2(100, 100)
	deep_unit.state = Unit.State.MOVING
	deep_unit._rotate_facing_toward(Vector2.RIGHT, 0.016, 2.0)
	assert_true(deep_unit.is_turning(), "unit reports is_turning while rotating facing")
	assert_lt(deep_unit._formed_turn_gait_frac(), 1.0,
		"80-mount cavalry block is deep enough to derate its corner-slot pace")

	var spacing: float = deep_unit.file_pitch_wu()
	var slot_pos: Vector2 = deep_unit._sim_soldier_pos[0]
	var soldier_pos: Vector2 = slot_pos + Vector2(spacing * 3.5, spacing * 3.5)
	deep_unit._sim_soldier_pos[0] = soldier_pos

	var target_vec: Vector2 = SoldierBodies.arrival_target(deep_unit, 0, slot_pos, deep_unit.soldiers, SoldierBodies.march_target_frac(deep_unit), not deep_unit.is_turning())
	var direct_vec: Vector2 = slot_pos - soldier_pos
	var diff_len_sq: float = (target_vec - direct_vec).length_squared()
	assert_gt(diff_len_sq, 1.0, "curved march routes through perimeter corridor when exceeding wide threshold")


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

	var target_vec: Vector2 = SoldierBodies.arrival_target(_unit, 0, slot_pos, _unit.soldiers, SoldierBodies.march_target_frac(_unit), not _unit.is_turning())
	var direct_vec: Vector2 = slot_pos - soldier_pos
	var diff_len_sq: float = (target_vec - direct_vec).length_squared()
	assert_gt(diff_len_sq, 1.0, "stationary unit routes through corridor at distance 3.0 * pitch")
