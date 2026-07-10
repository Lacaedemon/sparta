extends GutTest
## PathField: deterministic grid A* routing. With no obstacles the
## path is a straight line (movement unchanged); with a wall, units route around.

const FIELD := Rect2(0, 0, 640, 640)


func test_clear_line_steps_straight_to_target() -> void:
	var pf := PathField.new(FIELD)
	var target := Vector2(600, 50)
	assert_eq(pf.next_step(Vector2(50, 50), target), target,
		"with no obstacles the next step is the target itself")


func test_find_path_returns_a_route_between_distinct_cells() -> void:
	var pf := PathField.new(FIELD)
	# find_path always computes an A* route; the straight-line shortcut lives in
	# next_step(), so units skip A* when the line is clear (tested above).
	assert_gt(pf.find_path(Vector2(50, 50), Vector2(600, 50)).size(), 0,
		"A* returns a cell route between two distinct free cells")


func test_cell_aligned_wall_blocks_only_its_own_cell() -> void:
	# A wall sized exactly to one cell (CELL=64) must not spill into neighbours:
	# rect.end is exclusive, so the floor mapping must stay inside the wall.
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(64, 0, 64, 64))
	assert_true(pf.is_blocked(Vector2(70, 10)), "the wall's own cell is blocked")
	assert_false(pf.is_blocked(Vector2(140, 10)), "the cell to the right is clear")
	assert_false(pf.is_blocked(Vector2(70, 80)), "the cell below is clear")


func test_routes_around_a_wall_with_a_gap() -> void:
	var pf := PathField.new(FIELD)
	# A vertical wall across the upper field, leaving a gap along the bottom.
	pf.block_rect(Rect2(300, 0, 64, 480))
	var from := Vector2(50, 50)
	var to := Vector2(600, 50)
	# The straight line is blocked, so the next step must deviate from the target.
	assert_ne(pf.next_step(from, to), to, "a blocked line forces a detour")
	var path := pf.find_path(from, to)
	assert_gt(path.size(), 0, "an A* route around the wall exists")
	# Every waypoint avoids the wall.
	for p in path:
		assert_false(pf.is_blocked(p), "no waypoint sits inside the wall")


func test_path_is_deterministic() -> void:
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(300, 0, 64, 480))
	var a := pf.find_path(Vector2(50, 50), Vector2(600, 50))
	var b := pf.find_path(Vector2(50, 50), Vector2(600, 50))
	assert_eq(a, b, "the same query yields the same route (replay-safe)")


func test_blocked_goal_falls_back_to_target() -> void:
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(560, 0, 80, 120))   # the goal cell is inside terrain
	var to := Vector2(600, 50)
	# No reachable cell route; next_step falls back to the raw target rather than
	# stalling, so callers always make progress.
	assert_eq(pf.next_step(Vector2(50, 50), to), to,
		"an unreachable goal falls back to a straight step")


func test_has_path_true_on_a_clear_line() -> void:
	var pf := PathField.new(FIELD)
	assert_true(pf.has_path(Vector2(50, 50), Vector2(600, 50)),
		"an unobstructed straight line is a genuine route")


func test_has_path_true_when_a_detour_exists() -> void:
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(300, 0, 64, 480))   # a wall with a gap along the bottom
	assert_true(pf.has_path(Vector2(50, 50), Vector2(600, 50)),
		"blocked straight line but A* finds a route around -- still a real path")


func test_has_path_false_when_the_goal_is_unreachable() -> void:
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(560, 0, 80, 120))   # fully encloses the goal cell
	# Unlike next_step() (which falls back to the raw target either way), has_path()
	# must tell this apart from the clear-line case above.
	assert_false(pf.has_path(Vector2(50, 50), Vector2(600, 50)),
		"an unreachable goal is correctly reported as no path")


func test_has_escape_route_true_on_open_ground_toward_each_quadrant() -> void:
	# Regression: an unclipped 1000-unit-out target lands outside this FIELD (640x640)
	# in every one of these directions, which used to always read as "no path" even on
	# fully open ground -- has_escape_route() must clip the target to the grid's own
	# bounds first. Each direction below exercises a different sign combination in
	# _clip_to_bounds()'s per-axis clamp.
	var pf := PathField.new(FIELD)
	var origin := Vector2(320, 320)   # the field's centre
	for direction in [Vector2(1, -1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1),
			Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		assert_true(pf.has_escape_route(origin, direction),
			"open ground toward %s is a genuine escape route" % direction)


func test_has_escape_route_false_when_fully_boxed_in() -> void:
	# A one-cell-thick ring of blocked cells surrounds the centre cell -- which itself
	# stays open, matching a routing unit standing on passable ground that's walled in
	# on every side (not a unit whose own position is somehow inside the terrain).
	var pf := PathField.new(FIELD)
	var centre_cell := Vector2i(5, 5)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var c: Vector2i = centre_cell + Vector2i(dx, dy)
			pf.block_rect(Rect2(c.x * 64.0, c.y * 64.0, 64.0, 64.0))
	var centre := Vector2((centre_cell.x + 0.5) * 64.0, (centre_cell.y + 0.5) * 64.0)
	for direction in [Vector2(1, -1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		assert_false(pf.has_escape_route(centre, direction),
			"every direction is blocked, so no escape route exists toward %s" % direction)


func test_next_step_fleeing_routes_around_a_wall_with_a_gap() -> void:
	# Regression: next_step_fleeing() used to hand next_step() an unclipped point
	# 1000 units out in the flee direction, which lands off this FIELD (640x640) --
	# an unreachable goal find_path() can never resolve regardless of terrain, so a
	# fleeing unit facing a wall with a gap silently got no detour at all (identical
	# to no pathfinding). Clipping the target to the grid first (mirroring
	# has_escape_route()) is what makes A* able to find the real route around.
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(300, 0, 64, 480))   # a vertical wall, gap along the bottom
	var from := Vector2(50, 50)
	var direction := Vector2(1, 0)
	var step := pf.next_step_fleeing(from, direction)
	assert_ne(step, from + direction * 1000.0,
		"a blocked flee line detours instead of heading straight for the unreachable raw target")
	assert_false(pf.is_blocked(step), "the next step itself never lands inside the wall")


func test_next_step_fleeing_stays_within_field_bounds_on_open_ground() -> void:
	# With nothing to route around, the returned step must still be the clipped,
	# in-bounds point -- not the raw 1000-unit-out target, which sits far outside
	# this FIELD (640x640) and would leave next_step_fleeing() indistinguishable
	# from an unclipped, always-off-grid caller.
	var pf := PathField.new(FIELD)
	var from := Vector2(320, 320)
	var direction := Vector2(0, -1)
	var step := pf.next_step_fleeing(from, direction)
	assert_true(FIELD.grow(1.0).has_point(step),
		"the fleeing step lands within (or right at the edge of) the field, not 1000 units out")


func test_speed_rect_returns_configured_scale() -> void:
	var pf := PathField.new(FIELD)
	pf.set_speed_rect(Rect2(200, 200, 128, 128), 0.6)
	var inside := Vector2(264, 264)   # centre of the rect
	assert_almost_eq(pf.speed_at(inside), 0.6, 0.001,
		"a cell inside a speed zone returns the configured scale")


func test_speed_at_returns_one_outside_any_zone() -> void:
	var pf := PathField.new(FIELD)
	pf.set_speed_rect(Rect2(200, 200, 128, 128), 0.6)
	var outside := Vector2(50, 50)
	assert_almost_eq(pf.speed_at(outside), 1.0, 0.001,
		"a cell with no speed zone returns full speed (1.0)")


func test_speed_zone_does_not_block_movement() -> void:
	var pf := PathField.new(FIELD)
	pf.set_speed_rect(Rect2(200, 200, 128, 128), 0.6)
	var inside := Vector2(264, 264)
	assert_false(pf.is_blocked(inside),
		"a speed zone does not block movement (units can enter)")
