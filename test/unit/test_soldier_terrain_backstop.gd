extends GutTest
## The soldier body pass keeps bodies out of impassable (`block`) terrain as a hard
## constraint: a body that ends a tick within its own body radius of a block rect is placed
## back on the edge of that margin, dropping the part of its velocity still heading in. A
## body that began the tick inside the terrain itself (a spawn overlapping a hill) is left
## alone. See PathField.push_out_of_block and SoldierBodies._keep_out_of_terrain.

const HILL := Rect2(1150, 380, 250, 200)
const TICK := 1.0 / 60.0

var _old_field: PathField = null


func before_each() -> void:
	_old_field = PathField.active


func after_each() -> void:
	PathField.active = _old_field
	SimOps.enabled = false


func _field_with(rects: Array) -> PathField:
	var f := PathField.new(Rect2(0, 0, 4000, 4000))
	for r in rects:
		f.block_rect(r)
	return f


## A small idle Infantry block centred at `pos`, its bodies seeded on their slots.
func _make_unit(pos: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 12
	add_child_autofree(u)
	u.facing = Vector2.UP
	u.position = pos
	u.seed_sim_soldiers()
	return u


# --- PathField.push_out_of_block ------------------------------------------------------

func test_a_point_inside_a_rect_moves_to_its_nearest_edge() -> void:
	var f := _field_with([HILL])
	var got: Vector2 = f.push_out_of_block(Vector2(1160, 480))
	assert_eq(got, Vector2(1150, 480), "10 wu in from the west edge: out through the west edge")


func test_the_clearance_grows_the_rect() -> void:
	var f := _field_with([HILL])
	var got: Vector2 = f.push_out_of_block(Vector2(1275, 375), 7.0)
	assert_eq(got, Vector2(1275, 373), "5 wu above the top edge, inside the 7 wu margin: pushed to it")


func test_a_clear_point_and_a_point_on_the_edge_are_left_alone() -> void:
	var f := _field_with([HILL])
	assert_eq(f.push_out_of_block(Vector2(1000, 480)), Vector2(1000, 480), "clear ground")
	assert_eq(f.push_out_of_block(Vector2(1150, 480)), Vector2(1150, 480), "on the edge counts as out")


func test_overlapping_rects_push_a_point_clear_of_both() -> void:
	# A's nearest exit (its east edge, 3 wu away) lands inside B, and B's nearest exit (its
	# west edge) lands back inside A; the push takes the nearest exit clear of both instead.
	var f := _field_with([Rect2(0, 0, 100, 100), Rect2(95, 0, 100, 100)])
	var got: Vector2 = f.push_out_of_block(Vector2(97, 40))
	assert_eq(got, Vector2(97, 0), "out through the shared top edge, clear of both rects")


# --- SoldierBodies.step ---------------------------------------------------------------

## Body 0 of `u` placed 1 wu clear of the hill's grown west edge, driven east at `speed`.
func _drive_into_hill(u: Unit, speed: Vector2) -> void:
	var r: float = u.soldier_body_radius()
	u._sim_soldier_pos[0] = Vector2(HILL.position.x - r - 1.0, 480)
	u._sim_body_vel[0] = speed


func test_a_body_driven_into_the_hill_is_put_back_on_its_edge() -> void:
	PathField.active = _field_with([HILL])
	var u := _make_unit(Vector2(900, 480))
	var r: float = u.soldier_body_radius()
	_drive_into_hill(u, Vector2(600, 0))   # 10 wu per tick: well past the edge unchecked
	SoldierBodies.step(u, TICK)
	assert_lte(u._sim_soldier_pos[0].x, HILL.position.x - r + 0.001,
			"the body stands at least its own radius clear of the hill")


func test_a_body_driven_into_the_hill_keeps_no_inward_velocity() -> void:
	PathField.active = _field_with([HILL])
	var u := _make_unit(Vector2(900, 480))
	_drive_into_hill(u, Vector2(600, 40))   # heading east, into the hill, and a little south
	SoldierBodies.step(u, TICK)
	assert_lte(u._sim_body_vel[0].x, 0.0, "the eastward (into-terrain) part is gone")


func test_a_body_already_inside_the_hill_is_left_to_walk_out() -> void:
	# A block spawned overlapping a hill is not ejected wholesale: ejecting every body at once
	# would stack those that differ only along the ejection axis onto one point.
	PathField.active = _field_with([HILL])
	var u := _make_unit(Vector2(900, 480))
	u._sim_soldier_pos[0] = Vector2(1200, 480)   # 50 wu inside the hill
	u._sim_body_vel[0] = Vector2.ZERO
	SoldierBodies.step(u, TICK)
	assert_gt(u._sim_soldier_pos[0].x, HILL.position.x + 40.0, "not snapped to the edge")


func test_a_body_in_the_margin_but_not_the_hill_is_held_at_the_margin_edge() -> void:
	# A rear rank spawned within a body radius of the hill is not exempt: it is placed on the
	# margin's edge (a move of at most one body radius) and can then never be shoved in.
	PathField.active = _field_with([HILL])
	var u := _make_unit(Vector2(900, 480))
	var r: float = u.soldier_body_radius()
	u._sim_soldier_pos[0] = Vector2(HILL.position.x - r * 0.5, 480)
	u._sim_body_vel[0] = Vector2(300, 0)
	SoldierBodies.step(u, TICK)
	assert_lte(u._sim_soldier_pos[0].x, HILL.position.x - r + 0.001, "held a body radius clear")


func test_a_map_with_no_block_terrain_skips_the_pass() -> void:
	# The same body where the hill would be, on a map whose field has no block terrain: the
	# pass does no terrain work at all and the body stays where the integration put it.
	PathField.active = _field_with([])
	var u := _make_unit(Vector2(1100, 480))
	u._sim_soldier_pos[0] = Vector2(1160, 480)
	SimOps.enabled = true
	SimOps.reset()
	SoldierBodies.step(u, TICK)
	var tick: Dictionary = SimOps.take_tick()
	assert_eq(tick["terrain_project"], 0, "no terrain tests on a map with no block terrain")
	assert_gt(u._sim_soldier_pos[0].x, HILL.position.x, "and the body is left in place")


func test_the_pass_is_counted_once_per_body() -> void:
	PathField.active = _field_with([HILL])
	var u := _make_unit(Vector2(900, 480))   # every body clear of the hill
	SimOps.enabled = true
	SimOps.reset()
	SoldierBodies.step(u, TICK)
	var tick: Dictionary = SimOps.take_tick()
	SimOps.enabled = false
	assert_eq(tick["terrain_project"], 2 * u._sim_soldier_pos.size(),
			"one rect test per body before the step and one after (one rect)")


func test_a_hill_flush_with_the_field_edge_pushes_a_point_onto_the_field() -> void:
	# The hill's east face is the field's east edge. Grown by 7 wu, the rect reaches past the
	# field, so the nearest exit for a point on the boundary (east, 7 wu) would leave the field;
	# the push takes the nearest exit that stays on it (north, 7 wu farther).
	var f := PathField.new(Rect2(0, 0, 1000, 1000))
	f.block_rect(Rect2(900, 400, 100, 200))
	var got: Vector2 = f.push_out_of_block(Vector2(1000, 400), 7.0)
	assert_eq(got, Vector2(1000, 393), "out through the north edge, still on the field")


# --- Steady state of a block held against the hill ---------------------------------------

## An idle Infantry block facing UP just south of the hill, placed so its front rank's slots
## lie `intrusion` wu inside the hill's grown margin (0 < intrusion < body radius). Its bodies
## start on those slots.
func _block_held_in_margin(intrusion: float) -> Unit:
	var u := _make_unit(Vector2(HILL.get_center().x, 800))
	var front_y: float = INF
	for s in u.soldier_world_slots(u.soldiers):
		front_y = minf(front_y, s.y)
	u.position.y += HILL.end.y + u.soldier_body_radius() - intrusion - front_y
	u.seed_sim_soldiers()
	return u


## One tick of the body pass and the position coupling, as Unit runs them for a close-tier unit.
func _tick(u: Unit) -> void:
	SoldierBodies.step(u, TICK)
	SoldierBodies.couple(u, TICK)


func test_a_block_held_in_the_margin_settles_and_lets_the_render_idle() -> void:
	PathField.active = _field_with([HILL])
	var u := _block_held_in_margin(_half_body_radius())
	for _t in range(180):
		_tick(u)
	var prev: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var dirty_ticks := 0
	var max_step := 0.0
	for _t in range(60):
		u._render_dirty = false
		_tick(u)
		if u._render_dirty:
			dirty_ticks += 1
		for i in range(prev.size()):
			max_step = maxf(max_step, prev[i].distance_to(u._sim_soldier_pos[i]))
		prev = u._sim_soldier_pos.duplicate()
	assert_lt(max_step, 0.01, "no body jitters at the edge once the block has settled")
	assert_eq(dirty_ticks, 0, "the settled block lets the MultiMesh rewrite idle")
	for p in u._sim_soldier_pos:
		assert_gte(p.y, HILL.end.y + u.soldier_body_radius() - 0.001, "and every man stays clear")


func test_holding_in_the_margin_slides_the_centre_out_by_at_most_the_intrusion() -> void:
	# couple() reads the pressed rank's offset from its slots as drift and moves the unit off
	# the hill. That is bounded by the intrusion (at most one body radius) and stops once the
	# slots clear the margin, so a held block does not creep away.
	PathField.active = _field_with([HILL])
	var intrusion: float = _half_body_radius()
	var u := _block_held_in_margin(intrusion)
	var start: Vector2 = u.position
	for _t in range(240):
		_tick(u)
	var after_240: Vector2 = u.position
	for _t in range(60):
		_tick(u)
	assert_almost_eq(u.position.x, start.x, 0.001, "no sideways drift")
	assert_gt(u.position.y - start.y, intrusion * 0.9, "the centre moves out, away from the hill")
	assert_lte(u.position.y - start.y, intrusion + 0.001, "but never by more than the intrusion")
	assert_almost_eq(u.position.y, after_240.y, 0.01, "and it has stopped")


## Body 0 of an idle block placed `depth` wu inside the hill's grown west margin, at rest,
## then run through the backstop alone (not the integration, which has its own render test).
func _backstop_only(depth: float) -> Unit:
	PathField.active = _field_with([HILL])
	var u := _make_unit(Vector2(900, 480))
	u._sim_soldier_pos[0] = Vector2(HILL.position.x - u.soldier_body_radius() + depth, 480)
	u._sim_body_vel[0] = Vector2.ZERO
	var n: int = u._sim_soldier_pos.size()
	var guard: Dictionary = SoldierBodies._terrain_entry_guard(u, n)
	u._render_dirty = false
	SoldierBodies._keep_out_of_terrain(u, n, guard, TICK)
	return u


func test_a_visible_push_wakes_the_render() -> void:
	var u := _backstop_only(_half_body_radius())
	assert_true(u._render_dirty, "a body put back half a radius is redrawn")


func test_a_creep_far_below_rest_speed_does_not_wake_the_render() -> void:
	var u := _backstop_only(0.001)
	assert_false(u._render_dirty, "a 0.001 wu correction is not a visible move")
	assert_lte(u._sim_soldier_pos[0].x, HILL.position.x - u.soldier_body_radius() + 0.0001,
			"though the body is still held on the margin edge")


## Half a default Infantry body radius: an intrusion well inside the margin.
func _half_body_radius() -> float:
	var probe: Unit = Unit.new()
	probe.max_soldiers = 12
	add_child_autofree(probe)
	return probe.soldier_body_radius() * 0.5
