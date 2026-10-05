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
