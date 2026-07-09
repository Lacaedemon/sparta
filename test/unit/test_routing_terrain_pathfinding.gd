extends GutTest
## Unit routing with terrain awareness: units should path around impassable terrain,
## and fight to the death if trapped with no viable escape route.


func test_routing_unit_uses_pathfield_when_available() -> void:
	# A routing unit should consult PathField for escape direction (like _move_to does).
	var battle = _spawn_battle()
	var unit: Unit = battle._units[0]
	unit.state = Unit.State.ROUTING

	# Create a PathField with no obstacles: routing should proceed straight.
	var pf := PathField.new(battle.FIELD)
	var old_pf := PathField.active
	PathField.active = pf

	var old_pos := unit.position
	unit._process_rout(0.016)  # one tick

	# Unit moved in the flee direction (no obstacles).
	assert_gt(unit.position.distance_to(old_pos), 0.0, "unit moves during rout")
	assert_eq(unit.position.y < old_pos.y if unit.team == 0 else unit.position.y > old_pos.y,
		true, "team 0 flees upward; team 1 downward")

	PathField.active = old_pf
	battle.queue_free()


func test_trapped_routing_unit_fights_instead_of_fleeing() -> void:
	# A unit trapped by terrain with no escape route should stop routing and fight.
	var battle = _spawn_battle()
	var unit: Unit = battle._units[0]
	unit.state = Unit.State.ROUTING
	unit.position = Vector2(640, 360)  # middle of the field

	# Create a PathField with a tight cage around the unit.
	var pf := PathField.new(battle.FIELD)
	# Block all escape directions with terrain patches around the unit.
	pf.block_rect(Rect2(600, 300, 30, 30))   # upper-left corner
	pf.block_rect(Rect2(650, 300, 30, 30))   # upper-right corner
	pf.block_rect(Rect2(600, 400, 30, 30))   # lower-left corner
	pf.block_rect(Rect2(650, 400, 30, 30))   # lower-right corner

	var old_pf := PathField.active
	PathField.active = pf

	# Process the rout: the unit should detect the trap and stop routing.
	unit._process_rout(0.016)

	# Unit should transition from ROUTING to IDLE (stopped routing, now fighting).
	assert_eq(unit.state, Unit.State.IDLE, "trapped unit stops routing and fights")
	assert_false(unit.is_in_group("routers"), "unit no longer in routers group")
	assert_true(unit.is_in_group("units"), "unit rejoins regular units for combat")
	assert_true(unit._shattered, "unit marked as shattered (will fight to death)")

	PathField.active = old_pf
	battle.queue_free()


func test_routing_unit_with_open_escape_continues_fleeing() -> void:
	# A unit with an open escape path should keep routing.
	var battle = _spawn_battle()
	var unit: Unit = battle._units[0]
	unit.state = Unit.State.ROUTING
	unit.position = Vector2(640, 360)

	# Create a PathField with a wide-open escape direction (team 0 flees UP).
	var pf := PathField.new(battle.FIELD)
	# Block only one side, leaving escape direction clear.
	if unit.team == 0:
		# Team 0 flees UP, so block south but leave north clear.
		pf.block_rect(Rect2(500, 400, 280, 100))
	else:
		# Team 1 flees DOWN, so block north but leave south clear.
		pf.block_rect(Rect2(500, 300, 280, 50))

	var old_pf := PathField.active
	PathField.active = pf

	var old_pos := unit.position
	unit._process_rout(0.016)

	# Unit should still be routing (not stopped).
	assert_eq(unit.state, Unit.State.ROUTING,
		"unit with open escape path continues routing")
	assert_true(unit.is_in_group("routers"), "unit stays in routers group")
	assert_gt(unit.position.distance_to(old_pos), 0.0, "unit actually moved")

	PathField.active = old_pf
	battle.queue_free()


func test_escape_path_blocked_detects_cone_around_flee_direction() -> void:
	# _is_escape_path_blocked checks a 90-degree cone (45 deg each side).
	var battle = _spawn_battle()
	var unit: Unit = battle._units[0]
	unit.position = Vector2(640, 360)

	var pf := PathField.new(battle.FIELD)
	var old_pf := PathField.active
	PathField.active = pf

	# No obstacles: path not blocked.
	var flee_dir: Vector2 = Vector2.UP if unit.team == 0 else Vector2.DOWN
	assert_false(unit._is_escape_path_blocked(flee_dir),
		"open terrain reports no escape path blocked")

	# Block only the primary direction (dead ahead): should still fail trap check
	# since cone includes 45-degree flanks.
	pf.block_rect(Rect2(620, 200, 40, 100))  # block straight up path (team 0)
	assert_false(unit._is_escape_path_blocked(flee_dir),
		"blocking only primary direction leaves diagonal escapes open")

	# Block a wide arc (all 90 degrees): should detect trap.
	pf.block_rect(Rect2(500, 100, 280, 300))  # wide block covering all escape angles
	assert_true(unit._is_escape_path_blocked(flee_dir),
		"blocking entire escape cone reports path as trapped")

	PathField.active = old_pf
	battle.queue_free()


func _spawn_battle() -> Battle:
	# Minimal battle setup for routing tests.
	var scene := load("res://scenes/Battle.tscn") as PackedScene
	var battle := scene.instantiate() as Battle
	add_child_autofree(battle)
	await get_tree().process_frame
	return battle
