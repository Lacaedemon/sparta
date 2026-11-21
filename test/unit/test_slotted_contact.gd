extends GutTest
## SoldierBodies.step: in the slotted step, the same-unit contact wins over a man's own drive under
## the speed ceiling (with_contact). Shortening the sum of the two to the ceiling would shorten the
## push with it, and two riders pressed together at the gallop would not part.

const AT := Vector2(500, 500)
const DT := 1.0 / 60.0


func test_riders_pressed_together_at_the_gallop_take_the_whole_push() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = 2
	u.is_cavalry = true
	add_child_autofree(u)
	u.position = AT
	u.seed_sim_soldiers()
	u.state = Unit.State.MOVING
	var r: float = u.soldier_body_radius()
	var cap: float = u.move_speed * u.superphysical_speed_frac
	# Both far off their places (500 wu west of them), side by side and pressed together,
	# galloping east at the ceiling.
	var mid: Vector2 = AT + Vector2(-500, 0)
	u._sim_soldier_pos[0] = mid + Vector2(0, -0.45 * r)
	u._sim_soldier_pos[1] = mid + Vector2(0, 0.45 * r)
	u._sim_body_vel[0] = Vector2(cap, 0)
	u._sim_body_vel[1] = Vector2(cap, 0)
	var sep: PackedVector2Array = SoldierBodies._separate_same_unit(u, 2,
			u.soldier_world_slots(u.soldiers), PackedByteArray([0, 0]), DT)
	assert_gt(sep[1].y, 0.0, "sanity: the contact pushes the pair apart")
	var before: float = u._sim_soldier_pos[1].y - u._sim_soldier_pos[0].y
	SoldierBodies.step(u, DT)
	var opened: float = u._sim_soldier_pos[1].y - u._sim_soldier_pos[0].y - before
	assert_almost_eq(opened, (sep[1].y - sep[0].y) * DT, 0.0005,
			"each takes his whole push, his own drive cut back to fit under the ceiling")
