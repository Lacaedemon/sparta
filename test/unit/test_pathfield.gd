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


func test_is_leg_blocked_false_on_a_clear_line() -> void:
	var pf := PathField.new(FIELD)
	assert_false(pf.is_leg_blocked(Vector2(50, 50), Vector2(600, 50)),
		"an unobstructed straight line needs no detour")


func test_is_leg_blocked_true_when_a_wall_crosses_the_line() -> void:
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(300, 0, 64, 480))
	assert_true(pf.is_leg_blocked(Vector2(50, 50), Vector2(600, 50)),
		"a wall crossing the straight line forces a detour")


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


func test_string_pull_candidates_must_clear_the_full_margin() -> void:
	# A string-pull candidate is a synthetic A* cell centre, not a commanded
	# destination: the room-available cap must NOT apply to it, or every
	# corner-adjacent sightline silently shrinks to whatever room that cell
	# centre happens to have -- letting a unit wider than that room steer its
	# flank into the terrain at corners. Candidates are judged at the FULL
	# margin (cap_to false); the room cap stays for real endpoints only.
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(126, 64, 100, 128))   # east edge lands 30 wu into a cell
	var from := Vector2(450, 128)             # far outside a 70-wu margin
	var near_centre := Vector2(288, 128)      # open cell centre, only 62 wu off the rect
	assert_false(pf._segment_blocked(from, near_centre, 70.0),
		"judged as a real endpoint, the 62-wu-out point is reachable (room-capped)")
	assert_true(pf._segment_blocked(from, near_centre, 70.0, false),
		"judged as a candidate, it must clear the full 70-wu margin -- and cannot")


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


func test_funnel_steers_for_the_grown_corner_not_the_cell_lane() -> void:
	# Mid-detour beside a long wall, the waypoint is the clearance-grown rect's own
	# corner -- the drawn terrain plus exactly this unit's margin (plus the tangent
	# standoff) -- not a coarse A* cell centre on the corridor lane, which sits up to
	# a cell wider out regardless of the unit's own width.
	var pf := PathField.new(FIELD)
	var wall := Rect2(300, 100, 64, 400)
	pf.block_rect(wall)
	var clearance := 20.0
	var step: Vector2 = pf.next_step(Vector2(240, 300), Vector2(450, 600), clearance)
	assert_eq(step, Vector2(wall.position.x - clearance - PathField.CORNER_STANDOFF,
			wall.end.y + clearance + PathField.CORNER_STANDOFF),
		"the waypoint is the grown south-west corner, tangent to this unit's own lane")


func test_funnel_lane_scales_with_the_units_own_clearance() -> void:
	# The issue's exact complaint: units of very different widths used to converge
	# onto the same cell-corridor lane. Each must round on its OWN grown boundary.
	var pf := PathField.new(FIELD)
	var wall := Rect2(300, 100, 64, 400)
	pf.block_rect(wall)
	var from := Vector2(240, 300)
	var to := Vector2(450, 600)
	var narrow: Vector2 = pf.next_step(from, to, 10.0)
	var wide: Vector2 = pf.next_step(from, to, 40.0)
	assert_almost_eq(narrow.x, wall.position.x - 10.0 - PathField.CORNER_STANDOFF, 0.001,
		"a narrow unit's lane hugs at its own small margin")
	assert_almost_eq(wide.x, wall.position.x - 40.0 - PathField.CORNER_STANDOFF, 0.001,
		"a wide unit's lane rounds farther out, at its own larger margin")
	assert_ne(narrow.x, wide.x, "the two widths walk two different lanes")


func test_funnel_walk_hugs_the_boundary_without_ratcheting_inward() -> void:
	# Walk a whole two-corner detour in small steps, re-querying next_step each leg
	# like a real mover: over the wall's top-west corner, straight down the west
	# face, around the bottom corner, and on to the goal (the east side is sealed so
	# the route genuinely must round the west face). Three properties at once: the
	# walk arrives, the between-corners leg HUGS the grown boundary (not the old
	# cell-corridor lane a cell width farther out), and the margin NEVER erodes
	# below the clearance -- the inward-ratchet spiral a probe-capped tangent
	# scheme produces on exactly this long straightaway.
	var pf := PathField.new(FIELD)
	var wall := Rect2(300, 100, 64, 400)
	pf.block_rect(wall)
	pf.block_rect(Rect2(384, 100, 256, 400))   # seals the east side: the corridor goes west
	var clearance := 20.0
	var lane_x: float = wall.position.x - clearance - PathField.CORNER_STANDOFF   # 278
	var to := Vector2(330, 600)
	var pos := Vector2(330, 40)
	var beside_face_min_x: float = INF
	var beside_face_max_x: float = -INF
	for i in range(300):
		var step: Vector2 = pf.next_step(pos, to, clearance)
		pos = pos.move_toward(step, 8.0)
		var standoff: float = pos.distance_to(Vector2(
				clampf(pos.x, wall.position.x, wall.end.x),
				clampf(pos.y, wall.position.y, wall.end.y)))
		assert_gt(standoff, clearance - 0.5,
			"the walked margin never erodes below the unit's clearance (no ratchet spiral)")
		if pos.y > 150.0 and pos.y < 450.0:
			beside_face_min_x = minf(beside_face_min_x, pos.x)
			beside_face_max_x = maxf(beside_face_max_x, pos.x)
		if pos.distance_to(to) < 12.0:
			break
	assert_lt(pos.distance_to(to), 12.0, "the walk actually rounds the wall and arrives")
	assert_almost_eq(beside_face_min_x, lane_x, 2.0,
		"the between-corners leg walks the grown boundary lane, not the cell lane (~224)")
	assert_almost_eq(beside_face_max_x, lane_x, 2.0,
		"and holds that lane the whole way down the face -- no drift out or in")


func test_funnel_follows_the_corridors_side_around() -> void:
	# The corner must round the side the A* corridor chose -- which can be the
	# geometrically LONGER way when another obstacle blocks the short one -- not
	# whichever corner a raw distance comparison favors.
	var pf := PathField.new(FIELD)
	var wall := Rect2(300, 100, 64, 400)
	pf.block_rect(wall)
	pf.block_rect(Rect2(200, 0, 300, 80))   # seals the north gap: the corridor must go south
	var clearance := 20.0
	var step: Vector2 = pf.next_step(Vector2(240, 300), Vector2(450, 300), clearance)
	assert_almost_eq(step.y, wall.end.y + clearance + PathField.CORNER_STANDOFF, 0.001,
		"with the north gap sealed, the funnel rounds the south corner despite symmetric distance")


func test_funnel_from_inside_the_rect_falls_back_to_the_corridor() -> void:
	# A walker shoved fully inside the drawn rect has no visible grown corner at
	# all (every corner sightline starts inside the rect); the funnel must yield
	# INF and next_step keep the A* corridor candidate, the room-capped path that
	# already handles escaping.
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(300, 200, 64, 64))
	var from := Vector2(330, 230)   # inside the drawn rect
	var to := Vector2(500, 232)
	var corner: Vector2 = pf._funnel_corner(from, to, pf.find_path(from, to), 0.0)
	assert_false(corner.is_finite(), "no grown corner is visible from inside the rect")
	var step: Vector2 = pf.next_step(from, to, 0.0)
	assert_ne(step, to, "next_step still detours via the corridor candidate")


func test_funnel_corner_is_deterministic() -> void:
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(300, 100, 64, 400))
	var a: Vector2 = pf.next_step(Vector2(240, 300), Vector2(450, 600), 20.0)
	var b: Vector2 = pf.next_step(Vector2(240, 300), Vector2(450, 600), 20.0)
	assert_eq(a, b, "the funnel waypoint is a pure function of its inputs")


func test_segment_rect_entry_orders_rects_along_the_segment() -> void:
	# The entry parameter is what picks WHICH rect a detour rounds first.
	var near := Rect2(150, 100, 50, 50)
	var far := Rect2(400, 100, 50, 50)
	var t_near: float = PathField.segment_rect_entry(Vector2(0, 125), Vector2(600, 125), near)
	var t_far: float = PathField.segment_rect_entry(Vector2(0, 125), Vector2(600, 125), far)
	assert_lt(t_near, t_far, "the nearer rect enters at the smaller t")
	assert_eq(PathField.segment_rect_entry(Vector2(0, 0), Vector2(600, 0), near), INF,
		"a segment that misses the rect has no entry")
	assert_eq(PathField.segment_rect_entry(Vector2(160, 110), Vector2(600, 125), near), 0.0,
		"a segment starting inside enters at t=0")


func test_funnel_corner_with_no_blocking_rect_returns_inf() -> void:
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(300, 100, 64, 400))
	# from->to here never touches the registered rect, so _first_blocking_rect_index
	# finds none: _funnel_corner must take its early-return branch, not walk into a
	# grown-rect corner computation with no rect to grow.
	var corner: Vector2 = pf._funnel_corner(Vector2(50, 50), Vector2(200, 50), PackedVector2Array(), 10.0)
	assert_false(corner.is_finite(), "no blocking rect on this leg -- INF, not a rect-derived corner")


func test_funnel_corner_route_side_is_stable_under_sub_unit_position_drift() -> void:
	# Regression for a wide single-rank formation's facing whipsawing while
	# pivoting onto a new bearing. Root cause: an extreme-aspect-ratio formation's
	# Unit.terrain_clearance() (Unit._pivot_radius() derived) can be large enough that
	# a routing rect hundreds of world units away still "blocks" a from->to leg once
	# room-capped -- and _funnel_corner's route_side used to read the sign of
	# (to - from).cross(nearest_path_point - rect_centre). When `from`, the rect
	# centre, and the nearest path point sit close to collinear, that cross product is
	# a near-cancellation of two large terms, so the routine sub-world-unit position
	# drift every live Unit accrues tick to tick (soldier-body coupling) flips its
	# sign -- flipping which corner of the rect the funnel steers for, and therefore
	# the unit's facing, every tick. Geometry below is the exact repro: the game's own
	# default-map hill terrain, and two `from` values differing by a fraction of a
	# world unit -- one live tick's worth of drift, captured from a per-tick dump of
	# a 30-file single-rank Cavalry block marching near the default hill.
	var pf := PathField.new(Rect2(0, 0, 1600, 1200))
	var hill := Rect2(1150, 380, 250, 200)   # Battle.TERRAIN's hill patch
	pf.block_rect(hill)
	var to := Vector2(650.0, 730.0)
	var clearance := 590.0   # Unit._pivot_radius() + soldier_body_radius() for a 30-file single-rank Cavalry
	var from_a := Vector2(510.2562, 789.3583)
	var from_b := Vector2(510.2556, 789.3166)   # one physics tick's worth of position drift from from_a
	assert_lt(from_a.distance_to(from_b), 0.1,
		"sanity: the two `from` values differ by well under one world unit")
	var step_a: Vector2 = pf.next_step(from_a, to, clearance)
	var step_b: Vector2 = pf.next_step(from_b, to, clearance)
	assert_eq(step_a, step_b,
		"a sub-world-unit change in the querying unit's own position must not flip which corner the funnel steers for")
	# Not just consistent -- consistently CORRECT. Both `from` and `to` sit south of
	# the hill (hill spans y 380-580; from.y and to.y are both well past 580), so the
	# funnel must steer for a SOUTH corner (y > hill's centre y = 480), never a north
	# one -- a route_side/side pair measured on two different axes (this bug's actual
	# defect: _funnel_corner's per-candidate `side` used to classify each corner
	# against `heading`, a different axis than the one route_side itself now uses)
	# stays perfectly self-consistent tick to tick while silently picking the WRONG
	# corner every time, which the equality assert above alone cannot catch. The exact
	# expected corner (558.0, 1172.0) is hand-derived from the same grown-rect corner
	# geometry _funnel_corner itself computes: the south-west corner of
	# hill.grow(clearance + PathField.CORNER_STANDOFF), the cheaper of the two
	# south-side candidates by straight-line detour cost (from->corner->to) since both
	# `from` and `to` sit west of the hill.
	var expected_corner := Vector2(
		hill.position.x - clearance - PathField.CORNER_STANDOFF,
		hill.end.y + clearance + PathField.CORNER_STANDOFF)
	assert_eq(step_a, expected_corner,
		"the funnel must steer for the south-west corner, not the (side-inverted) north one")
	assert_gt(step_a.y, hill.get_center().y,
		"the chosen corner is on the correct (south) side of the rect the route passes on")


func test_funnel_corner_route_side_does_not_flip_across_an_axis_switch_boundary() -> void:
	# Regression for the fix that immediately preceded this one: an intermediate design
	# (introduced to fix the bug above, then found by review to break
	# test_funnel_walk_hugs_the_boundary_without_ratcheting_inward) switched between
	# `heading` (to - from) and a fixed `to - centre` axis once `heading` grew close
	# enough to collinear with the nearest path point (a sin-of-angle threshold). The
	# two axes can classify a corner on OPPOSITE sides, so a `from` value crossing that
	# threshold -- itself just a couple of world units, well under one tick of real
	# movement -- flipped the chosen corner exactly like the original whipsaw, just
	# relocated to wherever the threshold happened to sit.
	#
	# Geometry below reconstructs that failure exactly: a rect centred at (500,500), a
	# hand-supplied corridor whose nearest-to-rect point is (500,300), and
	# `to=(750,900)` -- verified by hand against the old (heading-vs-fixed-axis)
	# formula: from.x=789 lands at sin=0.04869 (just inside the old 0.05 threshold, so
	# it used the fixed axis), from.x=791 at sin=0.05118 (just outside it, so it used
	# `heading`) -- the exact straddle the review that requested this test measured.
	var pf := PathField.new(Rect2(0, 0, 2000, 2000))
	# A wide rect (not the earlier tests' narrow wall) so the near-vertical
	# from->to leg actually crosses its clearance-grown margin -- get_center()
	# is still (500, 500).
	var rect := Rect2(200, 400, 600, 200)
	pf.block_rect(rect)
	var to := Vector2(750.0, 900.0)
	var clearance := 20.0
	# Farther from the rect than (500, 300), so it never contests "nearest" --
	# only its DIRECTION from (500, 300) matters, fixing corridor_axis.
	var path := PackedVector2Array([Vector2(100, 300), Vector2(500, 300)])
	var first_corner: Vector2 = pf._funnel_corner(Vector2(785.0, 100.0), to, path, clearance)
	assert_true(first_corner.is_finite(), "sanity: this leg is expected to detour")
	var from_x := 785.0
	while from_x <= 795.0:
		var corner: Vector2 = pf._funnel_corner(Vector2(from_x, 100.0), to, path, clearance)
		assert_eq(corner, first_corner,
			("a `from` value (x=%.1f) swept smoothly across the old axis-switch boundary " +
					"must not flip the chosen corner") % from_x)
		from_x += 0.5


func test_funnel_corner_with_empty_path_has_no_side_preference() -> void:
	# An empty `path` (today's only caller, next_step, never passes one -- its own
	# `path.size() < 2` guard returns before calling _funnel_corner at all -- but a
	# direct call, as every test in this file makes, still can) must not read an
	# arbitrary corner's side as though it were a real corridor point. route_side stays
	# at its initialised 0.0 ("no preference": the `for p in path` search never runs),
	# so every corner clears the side filter and the cheapest one by straight-line
	# detour cost wins on cost alone.
	#
	# `from`/`to` sit off-centre (y=220, 80 above the wall's y=300 centre-line, not
	# on it) so the north (top) corner is STRICTLY cheaper than the south (bottom)
	# one by straight-line detour cost -- at y=300 (this wall spans y 100..500, so
	# y=300 is exactly its vertical centre) both corners cost exactly the same, which
	# pins whichever corner an implementation's tie-break happens to favour rather
	# than actually exercising cost comparison (the earlier, since-fixed version of
	# this test made exactly that mistake -- see the mirrored companion test below,
	# which catches an implementation that always returns that same fixed corner
	# regardless of which side is actually cheaper).
	var pf := PathField.new(Rect2(0, 0, 640, 640))
	var wall := Rect2(300, 100, 64, 400)
	pf.block_rect(wall)
	var corner: Vector2 = pf._funnel_corner(Vector2(240, 220), Vector2(450, 220),
			PackedVector2Array(), 20.0)
	assert_true(corner.is_finite(), "every corner clears an unset (0.0) route_side's filter")
	var expected := Vector2(wall.position.x - 20.0 - PathField.CORNER_STANDOFF,
			wall.position.y - 20.0 - PathField.CORNER_STANDOFF)
	assert_eq(corner, expected,
		"with no corridor to prefer a side, the cheapest (here: north/top) corner by cost wins")


func test_funnel_corner_with_empty_path_picks_the_cheaper_corner_from_the_other_side() -> void:
	# Mirror of the test above, `from`/`to` moved to y=380 (80 below the wall's y=300
	# centre-line) so the south (bottom) corner is now the strictly cheaper one. An
	# implementation that always returns a fixed corner (e.g. always north, as the
	# unmirrored test alone could not tell apart from a genuine cost comparison) fails
	# exactly one of this pair; only a real per-call cost comparison passes both.
	var pf := PathField.new(Rect2(0, 0, 640, 640))
	var wall := Rect2(300, 100, 64, 400)
	pf.block_rect(wall)
	var corner: Vector2 = pf._funnel_corner(Vector2(240, 380), Vector2(450, 380),
			PackedVector2Array(), 20.0)
	assert_true(corner.is_finite(), "every corner clears an unset (0.0) route_side's filter")
	var expected := Vector2(wall.position.x - 20.0 - PathField.CORNER_STANDOFF,
			wall.end.y + 20.0 + PathField.CORNER_STANDOFF)
	assert_eq(corner, expected,
		"with no corridor to prefer a side, the cheapest (here: south/bottom) corner by cost wins")


func test_funnel_corner_live_corridor_with_a_collinear_nearest_point_still_steers() -> void:
	# Regression for a review finding: a reachable corridor case can lose its
	# side preference under the endpoint-axis design above. A LIVE
	# next_step() query (not a direct _funnel_corner call with a hand-built
	# path) can indeed drive route_side's OLD "always use the nearest
	# point" logic to exactly 0.0 -- this from/to/rect triple is a genuine
	# corridor find_path() itself returns:
	#   path == [(32,32), (96,96)]  (adjacent diagonal cells, world-space
	#   cell centres), corridor_axis == (64,64), and rect's own centre
	#   (160,160) sits EXACTLY on the infinite line through those two cell
	#   centres -- so BOTH path points read cross == 0 against it, not just
	#   whichever one happens to be nearest.
	#
	# That "both points, not just the nearest" is not a coincidence of this
	# example: in EXACT arithmetic, for ANY 2-point path, cross(axis,
	# last-centre) MINUS cross(axis, first-centre) == cross(axis, last-first)
	# == cross(axis, axis) == 0 -- the two are always numerically identical,
	# whichever one a "nearest point" search happens to land on. (This
	# specific example's coordinates are exact powers of two, so float32
	# actually hits the identity precisely, cross == 0.0 on both points, with
	# no rounding drift to illustrate -- a less tidy geometry could instead
	# land the two points a tiny float-rounding residual apart, which is
	# exactly what PathField.ROUTE_SIDE_COLLINEAR_EPS's world-unit tolerance
	# is for, not what this identity itself claims.) So a 2-point corridor
	# (the common case for a short, adjacent-cell detour) can never exhibit
	# "the nearest point alone is degenerate while another path point still
	# carries a real side" -- if route_side reads 0.0 (or below the
	# tolerance) here, the corridor's own two defining endpoints are BOTH
	# axis-aligned with centre, a fully degenerate corridor with no side to
	# prefer, not a side the nearest-point search merely failed to find.
	# This test pins that a live query hitting exactly that case still
	# returns a finite, deterministic corner (cost alone, matching the
	# empty-path premise's "no preference" semantics) rather than
	# misbehaving.
	var pf := PathField.new(Rect2(0, 0, 320, 320))
	var rect := Rect2(150, 150, 20, 20)   # centre (160,160)
	pf.block_rect(rect)
	var from := Vector2(32, 32)     # cell (0,0) centre
	var to := Vector2(96, 96)       # cell (1,1) centre -- diagonal neighbour
	var clearance := 60.0
	var path := pf.find_path(from, to)
	assert_eq(path.size(), 2, "sanity: a clean 2-cell diagonal corridor")
	assert_eq(path[0], from, "sanity: path[0] is exactly the from-cell centre")
	assert_eq(path[1], to, "sanity: path[1] is exactly the to-cell centre")
	var corner: Vector2 = pf._funnel_corner(from, to, path, clearance)
	assert_true(corner.is_finite(),
		"a fully axis-degenerate live corridor still returns a real corner, not INF")
	var step: Vector2 = pf.next_step(from, to, clearance)
	assert_eq(step, corner, "next_step surfaces the same funnel corner for this live query")


func test_funnel_corner_prefers_a_farther_nonzero_side_over_a_degenerate_nearest_point() -> void:
	# The fixable shape of the Copilot finding above: a hand-built 3-point
	# path (direct _funnel_corner call, same pattern
	# test_funnel_corner_route_side_does_not_flip_across_an_axis_switch_boundary
	# already uses) where the NEAREST point to the rect is a coincidental fluke
	# -- collinear with centre, cross == 0 -- while the path's own endpoints
	# (which fix corridor_axis) are NOT, and carry a real, informative side.
	# Before the fix, route_side read from "whichever point is nearest" alone,
	# so this exact geometry zeroed it and dropped the side filter entirely
	# (every corner became a candidate). After the fix, route_side skips the
	# degenerate nearest point and reads the correct side from the path's own
	# endpoint instead.
	var pf := PathField.new(Rect2(0, 0, 640, 640))
	var rect := Rect2(300, 100, 64, 400)   # centre (332,300)
	pf.block_rect(rect)
	# The corridor (fixes corridor_axis and, post-fix, route_side) is
	# deliberately NOT the same from/to the funnel actually costs the
	# corners against below -- test_funnel_corner_route_side_does_not_flip_across_an_axis_switch_boundary
	# already establishes that _funnel_corner's `path` argument is
	# independent of its `from`/`to` cost inputs.
	var corridor_start := Vector2(100, 100)   # path[0]: cross(axis, p - centre) == -7200 (nonzero)
	var corridor_mid := Vector2(282, 260)     # nearest to rect (distance 18); cross == 0
	var corridor_end := Vector2(600, 500)     # path[2]: cross(axis, p - centre) == -7200 (nonzero)
	var path := PackedVector2Array([corridor_start, corridor_mid, corridor_end])
	# Straddles the wall close to its south edge (y=480, within the rect's own
	# 100..500 span) so the south corners are both far cheaper by raw cost
	# than the north ones -- the WRONG side for this corridor's own
	# north-reading axis.
	var from := Vector2(240, 480)
	var to := Vector2(450, 480)
	var clearance := 20.0
	var corner: Vector2 = pf._funnel_corner(from, to, path, clearance)
	assert_true(corner.is_finite(), "sanity: this leg is expected to detour")
	# The correct side (from the corridor endpoints' shared, nonzero cross
	# sign) keeps only the north corners (NW/NE) as candidates, even though
	# a south corner is far cheaper by raw cost alone. Before the fix, the
	# degenerate nearest corridor point (corridor_mid, cross == 0) zeroed
	# route_side and let that south corner win regardless; after the fix,
	# route_side reads the correct (north) side from a farther, nonzero
	# corridor point instead.
	assert_lt(corner.y, rect.get_center().y,
		"the correct (north) side wins even though a south corner is far cheaper by cost alone, " +
		"and even though the nearest corridor point is itself degenerate")


func test_funnel_corner_near_collinear_two_point_path_reads_no_preference() -> void:
	# Regression for a review finding: the 2-point endpoint identity
	# (test_funnel_corner_live_corridor_with_a_collinear_nearest_point_still_steers'
	# own comment) holds exactly only in real-number arithmetic. Independent
	# float32 subtractions (`p - centre` computed separately for each of the
	# two endpoints) do not have to agree: this from/to/centre triple is a
	# genuinely near-collinear corridor -- found by simulating Godot's own
	# float32 Vector2 arithmetic (struct.pack('f', ...) round-tripping,
	# matching real_t's single-precision default build) rather than by hand
	# -- whose two endpoints read OPPOSITE-SIGN, both-tiny cross values
	# (0.5 and -2.0) even though the true (real-number) side is a single,
	# well-defined value near zero for both. An exact `cross == 0.0` test
	# would have called both endpoints "informative" with contradictory
	# signs, so whichever one happened to be nearest would set route_side
	# from pure rounding noise. Both endpoints' perpendicular distance to
	# the axis line are microscopic (under 3e-5 wu, five orders of
	# magnitude below PathField.ROUTE_SIDE_COLLINEAR_EPS's 1e-3 wu
	# tolerance), so both are correctly read as degenerate and route_side
	# stays 0.0, "no preference" -- not a coin flip between +1 and -1.
	var pf := PathField.new(Rect2(0, 0, 2000, 100000))
	# Positioned so its own centre lands exactly on the near-collinear axis
	# below (within the same float32 rounding this whole test exercises):
	# centre == Vector2(1053.5672607421875, 13595.935546875).
	var rect_centre := Vector2(1053.5672607421875, 13595.935546875)
	var rect := Rect2(rect_centre - Vector2(50.0, 600.0), Vector2(100.0, 1200.0))
	pf.block_rect(rect)
	var p0 := Vector2(1000.8522338867188, 360.21466064453125)
	var p1 := Vector2(1342.4677734375, 86133.2578125)
	var path := PackedVector2Array([p0, p1])
	var corner: Vector2 = pf._funnel_corner(p0, p1, path, 20.0)
	assert_true(corner.is_finite(), "sanity: this leg is expected to detour")
	# With route_side correctly at 0.0 ("no preference"), the side filter at
	# _funnel_corner's own comment ("route_side != 0.0 and side != 0.0 and
	# side != route_side") never trips, so the cheapest corner by cost alone
	# wins -- the same "no preference" semantics the empty-path tests above
	# pin intentionally, just reached here through near-collinear rounding
	# noise instead of an empty path.
	var expected := Vector2(rect.position.x - 20.0 - PathField.CORNER_STANDOFF,
			rect.position.y - 20.0 - PathField.CORNER_STANDOFF)
	assert_eq(corner, expected,
		"a near-collinear (not exact) 2-point corridor reads no preference, not a side from rounding noise")


func test_funnel_corner_a_bulging_nonzero_nearest_point_agrees_with_the_old_logic() -> void:
	# Review finding on this same round: on a BENDING 3+ point path, "prefer
	# the nearest point with a nonzero cross" can supposedly pick the wrong
	# side. Geometry from the review: path [A, B, C] with B bulging out to
	# the far side of the rect and landing nearest it. Pinned here: B's
	# cross is already nonzero (-120000), so this is NOT a case the
	# nearest-nonzero change alters -- the pre-fix code (which used
	# whichever point was nearest, full stop) and the post-fix code (which
	# uses the nearest point among those with a NONZERO -- now
	# above-tolerance -- cross) agree, both reading route_side from B. And
	# B's side IS the side this corridor actually rounds the rect on: A and
	# C sit on the near/west face (x=100, both well below the rect's own
	# x-span), while B swings out past it (x=500, past the rect's far/east
	# edge) specifically to clear the obstacle -- the path's closest
	# approach to the rect is exactly the point where it is rounding the
	# rect, not an arbitrary bulge.
	var pf := PathField.new(Rect2(0, 0, 640, 640))
	var rect_centre := Vector2(300.0, 300.0)
	# Wide and short (not the small square this test first tried), so the
	# east/west corners the review's vertical axis actually discriminates
	# between sit far enough apart, and far enough from a vertical from/to
	# straddling the rect's own vertical centre, for a clean unobstructed
	# sightline to the correct-side corner to exist at all.
	var rect := Rect2(rect_centre - Vector2(100.0, 20.0), Vector2(200.0, 40.0))
	pf.block_rect(rect)
	var a := Vector2(100.0, 0.0)
	var b := Vector2(500.0, 300.0)
	var c := Vector2(100.0, 600.0)
	var path := PackedVector2Array([a, b, c])
	var axis: Vector2 = c - a
	# Sanity-pin the review's own numbers before trusting the behavioural
	# assertion below: B is nearest the rect, and its cross is a clear,
	# above-tolerance -120000, not a rounding-noise artifact like the test
	# above's near-collinear pair.
	assert_true(pf._distance_to_rect(b, rect) < pf._distance_to_rect(a, rect),
		"sanity: B is nearer the rect than A, per the review's own geometry")
	assert_true(pf._distance_to_rect(b, rect) < pf._distance_to_rect(c, rect),
		"sanity: B is nearer the rect than C, per the review's own geometry")
	assert_eq(axis.cross(b - rect_centre), -120000.0,
		"sanity: B's cross matches the review's own -120000")
	# The corridor (path, above) is deliberately NOT the same from/to the
	# funnel actually costs the corners against -- same decoupling
	# test_funnel_corner_prefers_a_farther_nonzero_side_over_a_degenerate_nearest_point
	# already uses. A straight line from A to C never comes near this rect
	# at all (both sit at x=100, far west of the rect's own 200..400
	# x-span), and the review's own path is only for pinning what route_side
	# reads, not a real leg to detour -- a real detour needs its own from/to
	# straddling the rect. A vertical line straight through the rect's own
	# centre keeps both candidate east corners' sightlines clear of the
	# rect itself (each stays entirely on one side of the rect's y-span
	# until it reaches the corner), which the review's original small
	# square rect did not.
	var from := Vector2(300.0, 150.0)
	var to := Vector2(300.0, 450.0)
	var corner: Vector2 = pf._funnel_corner(from, to, path, 20.0)
	assert_true(corner.is_finite(), "sanity: this leg is expected to detour")
	# B's side (negative -- east of centre, matching the rect's east/far
	# edge, its own corner.x > centre.x) is the side that wins; a corner on
	# A/C's side (west, corner.x < centre.x) would mean the nearest-nonzero
	# change picked the wrong signal for a bending path.
	assert_gt(corner.x, rect_centre.x,
		"the nearest point's (B's) side wins, matching the side the corridor actually rounds the rect on")
