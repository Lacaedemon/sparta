extends GutTest
## Unit routing with terrain awareness: units should path around impassable terrain,
## and fight to the death if trapped with no viable escape route.


func test_routing_unit_uses_pathfield_when_available() -> void:
	# A routing unit should consult PathField for escape direction (like _move_to does).
	var battle: Node = await _spawn_battle()
	var unit: Unit = _first_team0_unit(battle)
	assert_not_null(unit, "expected at least one spawned team-0 unit")
	unit._rout()  # sets state + _rout_timer together, unlike a bare state assignment

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


func test_trapped_routing_unit_fights_instead_of_fleeing() -> void:
	# A unit trapped by terrain with no escape route should stop routing and fight.
	var battle: Node = await _spawn_battle()
	var unit: Unit = _first_team0_unit(battle)
	assert_not_null(unit, "expected at least one spawned team-0 unit")
	unit._rout()  # sets state + _rout_timer together, unlike a bare state assignment
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


func test_routing_unit_with_open_escape_continues_fleeing() -> void:
	# A unit with an open escape path should keep routing.
	var battle: Node = await _spawn_battle()
	var unit: Unit = _first_team0_unit(battle)
	assert_not_null(unit, "expected at least one spawned team-0 unit")
	unit._rout()  # sets state + _rout_timer together, unlike a bare state assignment
	unit.position = Vector2(640, 360)
	# Below RALLY_MORALE_THRESHOLD: _rout() leaves morale untouched, and a fresh unit
	# spawns at full morale (100) -- which would otherwise rally on this very first
	# _process_rout() call (broken contact + morale already past the threshold) before
	# this test gets to observe it still routing. See the one-tick-rout note on
	# _process_rout's own rally check.
	unit.morale = 20.0

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


func test_escape_path_blocked_detects_cone_around_flee_direction() -> void:
	# _is_escape_path_blocked checks a 90-degree cone (45 deg each side).
	var battle: Node = await _spawn_battle()
	var unit: Unit = _first_team0_unit(battle)
	assert_not_null(unit, "expected at least one spawned team-0 unit")
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


func _spawn_battle() -> Node:
	# Minimal battle setup for routing tests. Battle.gd has no class_name (it's
	# preloaded elsewhere to avoid depending on one -- see the file's own header
	# comment), so the return/local types here stay the untyped `Node` other
	# tests already use for the same scene (e.g. test_battle_spawn_no_overlap.gd).
	var scene := load("res://scenes/Battle.tscn") as PackedScene
	var battle: Node = scene.instantiate()
	add_child_autofree(battle)
	await get_tree().process_frame
	return battle


## The first team-0 unit spawned into `battle`, or null if none spawned (each
## call site asserts non-null so a regression here fails loudly). `_units`
## (Battle's Unit container node) isn't an array, so this walks the spawned
## units by group membership instead of indexing `battle._units[0]`.
func _first_team0_unit(battle: Node) -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		var unit: Unit = node as Unit
		if unit != null and unit.team == 0:
			return unit
	return null
