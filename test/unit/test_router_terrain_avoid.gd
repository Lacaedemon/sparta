extends GutTest
## SoldierBodies.router_terrain_avoid, the way a routed man veers off impassable terrain he is
## running at: toward the shorter way round to his goal, a point far along his own line of
## flight (SoldierFlightStep), or toward his goal when it lies on his own side of the face.

# Pure-function fixtures for router_terrain_avoid: a rect (already grown by the body radius)
# north of a man running north, and the man's own acceleration.
const FACE_RECT := Rect2(-100.0, -300.0, 300.0, 100.0)   # south face at y = -200
const RUN_SPEED := 200.0
const BODY_ACCEL := 40.0
const TICK := 1.0 / 60.0


## FACE_RECT as the typed rect list router_terrain_avoid takes.
func _face_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = [FACE_RECT]
	return rects


## How far a man running at RUN_SPEED covers while shedding it at BODY_ACCEL, plus one tick.
func _reach() -> float:
	return RUN_SPEED * RUN_SPEED / (2.0 * BODY_ACCEL) + RUN_SPEED * TICK


func test_a_run_that_clears_the_terrain_is_left_alone() -> void:
	# Running north past the rect's west end: his run never meets it.
	var pos := Vector2(FACE_RECT.position.x - 1.0, 0.0)
	var desired := Vector2(0.0, -RUN_SPEED)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, desired, pos + Vector2(0.0, -900.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_eq(out, desired, "a run clear of the terrain keeps its desired velocity")


func test_a_run_beyond_turning_reach_of_the_face_is_left_alone() -> void:
	# The face lies just past the distance he needs to turn his run: not yet his concern.
	var pos := Vector2(0.0, FACE_RECT.end.y + _reach() + 1.0)
	var desired := Vector2(0.0, -RUN_SPEED)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, desired, Vector2(-300.0, -600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_eq(out, desired, "a face beyond his turning reach leaves his desired velocity alone")


func test_a_run_at_a_face_turns_along_it_toward_the_shorter_way_round() -> void:
	# Within turning reach of the south face, running straight at it, with his goal beyond the
	# rect to the north-west: the west end is the shorter way round.
	var pos := Vector2(0.0, FACE_RECT.end.y + _reach() - 1.0)
	var desired := Vector2(0.0, -RUN_SPEED)
	var west: Vector2 = SoldierBodies.router_terrain_avoid(pos, desired, Vector2(-300.0, -600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(west.x, -RUN_SPEED, 0.001, "he runs west along the face at the same speed")
	assert_almost_eq(west.y, 0.0, 0.001, "with nothing left heading into the face")
	# The same run with his goal beyond the rect to the north-east goes round by the east end.
	var east: Vector2 = SoldierBodies.router_terrain_avoid(pos, desired, Vector2(500.0, -600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(east.x, RUN_SPEED, 0.001, "he runs east along the face at the same speed")
	assert_almost_eq(east.y, 0.0, 0.001, "with nothing left heading into the face")


func test_the_way_round_counts_the_far_corner_when_the_straight_way_on_crosses_the_rect() -> void:
	# His goal lies just beyond the rect's north face, over its western half, and he stands
	# near the east end. In straight lines the east end looks shorter (348 wu against 385),
	# but from either end the straight line on to his goal crosses the rect; counted round the
	# far corners, the west end is shorter (409 wu against 422).
	var pos := Vector2(150.0, FACE_RECT.end.y + 50.0)
	var desired := Vector2(0.0, -RUN_SPEED)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, desired, Vector2(-50.0, -320.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(out.x, -RUN_SPEED, 0.001, "he goes round by the west end")
	assert_almost_eq(out.y, 0.0, 0.001, "with nothing left heading into the face")


func test_a_goal_on_his_own_side_turns_him_toward_it() -> void:
	# His run carries him at the face, but his goal is on his own side of it, to the east:
	# he only has to stop running into the rock, so he turns east, toward the goal.
	var pos := Vector2(0.0, FACE_RECT.end.y + 50.0)
	var vel := Vector2(0.0, -RUN_SPEED)
	var desired := Vector2(0.0, -RUN_SPEED)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, vel, Vector2(150.0, -100.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(out.x, RUN_SPEED, 0.001, "he turns east, toward his goal")
	assert_almost_eq(out.y, 0.0, 0.001, "with nothing left heading into the face")


func test_only_the_part_heading_into_the_face_is_turned() -> void:
	# A run carrying him at the face while he already wants to go partly sideways keeps that
	# sideways part and has only the part heading in turned along the face.
	var pos := Vector2(0.0, FACE_RECT.end.y + 50.0)
	var vel := Vector2(0.0, -RUN_SPEED)
	var desired := Vector2(-30.0, -150.0)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, vel, Vector2(-300.0, -600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(out.x, -180.0, 0.001, "sideways part kept, the inward 150 turned west")
	assert_almost_eq(out.y, 0.0, 0.001, "nothing left heading into the face")


func test_a_man_standing_at_the_face_is_turned_too() -> void:
	# Standing still on the face (no run to look along), wanting to go straight into it:
	# where he wants to go this tick meets the face, so that is turned along it.
	var pos := Vector2(0.0, FACE_RECT.end.y)
	var desired := Vector2(0.0, -RUN_SPEED)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, Vector2.ZERO, Vector2(-300.0, -600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_almost_eq(out.x, -RUN_SPEED, 0.001, "he runs west along the face")
	assert_almost_eq(out.y, 0.0, 0.001, "with nothing left heading into the face")


func test_a_man_already_running_away_from_the_face_is_left_alone() -> void:
	# His run still carries him at the face, but he already wants to run away from it.
	var pos := Vector2(0.0, FACE_RECT.end.y + 50.0)
	var vel := Vector2(0.0, -RUN_SPEED)
	var desired := Vector2(0.0, 80.0)
	var out: Vector2 = SoldierBodies.router_terrain_avoid(pos, vel, Vector2(0.0, 600.0),
			desired, _face_rects(), BODY_ACCEL, TICK)
	assert_eq(out, desired, "a man wanting to run away from the face keeps his desired velocity")
