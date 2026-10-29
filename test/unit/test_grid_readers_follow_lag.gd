extends GutTest
## The readers that rank a block's men along its slot grid (grid_front_forward, near_front_forward,
## near_front_reversed, and through them the anchor's near-front ranks and the contact set) read
## the grid's own turn off its heading, grid_fold (the fold plus the lag). Whatever sets a large
## lag in one tick while the grid stands still -- an order's re-square handing the fold to the
## lag, a small heading correction left trailing -- must leave every one of them where it was.

const START := Vector2(500.0, 500.0)
const MEN := 60
const ANGLE_EPS := 0.0001   # solver epsilon
const SLOT_EPS := 0.001   # tuned in wu, float noise on a slot


func _unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = MEN
	add_child_autofree(u)
	u.position = START
	u.facing = Vector2.UP
	u.seed_sim_soldiers()
	return u


## Turn the heading `deg` degrees with the fold compensating, as an engage re-face leaves a
## block, and settle every body on its slot.
func _fold(u: Unit, deg: float) -> void:
	u.facing = u.facing.rotated(deg_to_rad(deg))
	u._formation_angle = wrapf(u._formation_angle - deg_to_rad(deg), -PI, PI)
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]


## Every grid reader at once. The index sets are read in contact, which they gate on.
func _readings(u: Unit) -> Dictionary:
	var was: bool = u._in_enemy_contact
	u._in_enemy_contact = true
	var r := {
		"grid_front": u.grid_front_forward(),
		"near_front": u.near_front_forward(),
		"reversed": u.near_front_reversed(),
		"anchor": u.near_front_soldier_indices(u.soldiers),
		"contact": u.contact_soldier_indices(u.soldiers),
		"slots": u.soldier_world_slots(u.soldiers),
	}
	u._in_enemy_contact = was
	return r


func _assert_unmoved(before: Dictionary, after: Dictionary, what: String) -> void:
	var a: PackedVector2Array = before["slots"]
	var b: PackedVector2Array = after["slots"]
	var worst := 0.0
	for i in range(a.size()):
		worst = maxf(worst, a[i].distance_to(b[i]))
	assert_lt(worst, SLOT_EPS, "%s: sanity, the slot grid stands still" % what)
	for key in ["grid_front", "near_front"]:
		var v0: Vector2 = before[key]
		var v1: Vector2 = after[key]
		assert_almost_eq(v1.x, v0.x, ANGLE_EPS, "%s: %s x holds" % [what, key])
		assert_almost_eq(v1.y, v0.y, ANGLE_EPS, "%s: %s y holds" % [what, key])
	assert_eq(after["reversed"], before["reversed"], "%s: the reversal holds" % what)
	assert_eq(after["anchor"], before["anchor"], "%s: the anchor's near-front ranks hold" % what)
	assert_eq(after["contact"], before["contact"], "%s: the contact set holds" % what)


## An order's re-square of a fold far from a quarter hands it all to the lag in one tick.
func test_an_order_resquare_moves_no_grid_reader() -> void:
	var u := _unit()
	_fold(u, 70.0)
	var before := _readings(u)
	u.set_current_order(Order.new_move(START + Vector2(0.0, -800.0)))
	u.start_order_response()
	assert_almost_eq(u._formation_angle, 0.0, ANGLE_EPS, "sanity: the fold was squared")
	assert_almost_eq(absf(u._grid_lag), deg_to_rad(70.0), ANGLE_EPS, "sanity: all of it is lag")
	_assert_unmoved(before, _readings(u), "order re-square")


## A small heading correction turns the heading at once and leaves the grid as a lag.
func test_a_heading_correction_moves_no_grid_reader() -> void:
	var u := _unit()
	var before := _readings(u)
	u._reface(u.facing.rotated(deg_to_rad(60.0)))
	assert_almost_eq(absf(u._grid_lag), deg_to_rad(60.0), ANGLE_EPS, "sanity: a 60 degree lag")
	_assert_unmoved(before, _readings(u), "heading correction")


## A fold past a quarter-turn handed partly to the lag across the quarter keeps its reversal:
## the men still have the grid's rear rank in front of them.
func test_a_lag_across_the_quarter_keeps_the_reversal() -> void:
	var u := _unit()
	_fold(u, 100.0)
	var before := _readings(u)
	assert_true(before["reversed"], "sanity: a 100 degree fold is past the quarter")
	var handed: float = signf(u._formation_angle) * deg_to_rad(20.0)
	u._formation_angle -= handed
	u._grid_lag += handed
	_assert_unmoved(before, _readings(u), "lag across the quarter")
