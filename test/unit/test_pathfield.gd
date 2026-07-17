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


func test_next_step_looks_ahead_to_the_farthest_visible_path_point() -> void:
	# String-pulling: with a detour forced, next_step steers for the FARTHEST route
	# point still in direct line of sight -- the corridor's real direction -- not the
	# adjacent cell centre, whose bearing zigzags in coarse per-cell quanta and whipsaws
	# a formation off its true heading (the pre-contact blobbing of a shallow detour).
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(300, 0, 64, 480))   # vertical wall, gap along the bottom
	var from := Vector2(50, 50)
	var step: Vector2 = pf.next_step(from, Vector2(600, 50))
	assert_gt(from.distance_to(step), PathField.CELL * 1.5,
		"the returned waypoint reaches beyond the adjacent cell")
	# The whole from->step segment stays out of the wall (it is genuinely visible).
	var samples: int = int(ceil(from.distance_to(step) / (PathField.CELL * 0.25)))
	for i in range(samples + 1):
		var p: Vector2 = from.lerp(step, float(i) / float(samples))
		assert_false(pf.is_blocked(p), "the lookahead waypoint is in direct line of sight")
	# The wall spans the upper field, so the corridor runs down toward the gap: the
	# lookahead bearing must head down at least as much as it heads right, where the
	# adjacent-cell bearing from the start cell barely descends at all.
	var dir: Vector2 = (step - from).normalized()
	assert_gt(dir.y, 0.5, "the lookahead steers along the corridor toward the gap")


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


func test_sliver_overlap_does_not_block_the_rest_of_the_cell() -> void:
	# A rect that spills 2 wu into a routing cell used to block the whole 64-wu
	# cell, inflating the routed footprint by up to 62 wu on a side. Blocking is
	# exact now: a point (and a straight lane) inside that cell but clear of the
	# drawn rect stays open.
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(126, 64, 68, 128))   # spills 2 wu into the col-1 cells (x 64..128)
	assert_false(pf.is_blocked(Vector2(100, 90)),
		"a point in the clipped cell but outside the drawn rect is not blocked")
	var target := Vector2(100, 600)
	assert_eq(pf.next_step(Vector2(100, 20), target), target,
		"a straight lane through the clipped cell, clear of the drawn rect, needs no detour")


func test_clearance_grows_the_blocked_footprint_for_wide_units() -> void:
	# The same lane that a point-sized walker passes straight down must detour for
	# a unit whose own half-extent overlaps the rect: clearance grows the obstacle
	# by the querying unit's real geometry, replacing the old incidental cell
	# inflation with an explicit, per-unit margin.
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(126, 64, 68, 128))
	var clearance := 30.0
	assert_true(pf.is_blocked(Vector2(100, 90), clearance),
		"the same point is blocked once grown by the unit's clearance")
	var from := Vector2(100, 20)
	var target := Vector2(100, 600)
	var step: Vector2 = pf.next_step(from, target, clearance)
	assert_ne(step, target, "the lane detours for a unit whose clearance overlaps the rect")
	# The waypoint it steers for is genuinely clear at that clearance: every sample
	# along the segment keeps the unit's margin off the drawn rect.
	var samples: int = int(ceil(from.distance_to(step) / (PathField.CELL * 0.25)))
	for i in range(samples + 1):
		var p: Vector2 = from.lerp(step, float(i) / float(maxi(1, samples)))
		assert_false(pf.is_blocked(p, clearance),
			"the chosen waypoint keeps the whole clearance margin clear")


func test_start_in_a_sliver_blocked_cell_still_routes() -> void:
	# A unit can legitimately stand on the clear ground of a cell an obstacle
	# only clips (footprints are exact; cells block conservatively). A* must
	# still route around from there -- a blocked START cell is passable to
	# leave, not a dead end whose empty path makes next_step fall back to a
	# straight step through the terrain.
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(126, 64, 68, 128))   # clips the col-1 cells by 2 wu
	var from := Vector2(70, 128)   # inside a clipped cell, outside the drawn rect
	var to := Vector2(260, 128)    # straight line crosses the rect
	assert_false(pf.is_blocked(from), "the start point itself is clear ground")
	assert_ne(pf.next_step(from, to, 20.0), to,
		"a detour is still produced from a sliver-blocked start cell")


func test_clearance_caps_at_the_room_actually_available() -> void:
	# A unit already inside its own margin (spawned or shoved there) must keep
	# pathing by exact sightlines at the standoff it actually has -- not have
	# every test fail where it stands, which would degrade steering back to the
	# per-cell whipsaw the string-pulled lookahead exists to prevent. Likewise a
	# leg whose DESTINATION sits inside the margin (a commanded move to the
	# obstacle's edge) is judged at the room the destination leaves, so the unit
	# can go where it was ordered, hugging as needed.
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(300, 200, 64, 64))
	var near := Vector2(280, 232)   # 20 wu west of the rect, inside a 50-wu margin
	var far := Vector2(50, 232)
	assert_eq(pf.next_step(near, far, 50.0), far,
		"a unit inside its own margin still sees the outward sightline")
	assert_eq(pf.next_step(far, near, 50.0), near,
		"a commanded destination inside the margin stays reachable, hugging as needed")


func test_segment_intersects_rect_geometry() -> void:
	var r := Rect2(100, 100, 50, 50)
	assert_true(PathField.segment_intersects_rect(Vector2(0, 125), Vector2(300, 125), r),
		"a segment crossing the rect intersects")
	assert_true(PathField.segment_intersects_rect(Vector2(125, 125), Vector2(300, 300), r),
		"a segment starting inside the rect intersects")
	assert_false(PathField.segment_intersects_rect(Vector2(0, 0), Vector2(300, 0), r),
		"a parallel segment outside the rect misses")
	assert_false(PathField.segment_intersects_rect(Vector2(0, 160), Vector2(90, 100), r),
		"a segment ending short of the rect misses")
	assert_true(PathField.segment_intersects_rect(Vector2(125, 125), Vector2(125, 125), r),
		"a degenerate point inside the rect intersects")
	assert_false(PathField.segment_intersects_rect(Vector2(0, 0), Vector2(0, 0), r),
		"a degenerate point outside the rect misses")


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


func test_speed_zone_footprint_is_exact_not_cell_inflated() -> void:
	# Same footprint exactness as blocking: a zone that clips a routing cell by a
	# sliver used to slow the whole cell; now only ground inside the drawn rect slows.
	var pf := PathField.new(FIELD)
	pf.set_speed_rect(Rect2(126, 64, 68, 128), 0.6)   # spills 2 wu into the col-1 cells
	assert_almost_eq(pf.speed_at(Vector2(100, 90)), 1.0, 0.001,
		"a point in the clipped cell but outside the drawn zone keeps full speed")
	assert_almost_eq(pf.speed_at(Vector2(130, 90)), 0.6, 0.001,
		"a point inside the drawn zone slows")


func test_overlapping_speed_zones_last_registered_wins() -> void:
	var pf := PathField.new(FIELD)
	pf.set_speed_rect(Rect2(100, 100, 100, 100), 0.6)
	pf.set_speed_rect(Rect2(150, 100, 100, 100), 0.8)
	assert_almost_eq(pf.speed_at(Vector2(175, 150)), 0.8, 0.001,
		"where zones overlap, the last-registered scale wins")
