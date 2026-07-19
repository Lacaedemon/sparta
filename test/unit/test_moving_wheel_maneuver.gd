extends GutTest
## A CAVALRY unit's move order sharply off its current heading -- forward-oblique, lateral,
## or rear, any angle, potentially past 180° -- gallops through a single continuous MOVING
## wheel (hinge translating forward the whole swing) straight into the march, rather than
## halting first the way the standing composites (rear-move about-face, lateral-pivot,
## about-face+wheel) do. Foot units are unaffected: this classification is cavalry-only, and
## supersedes those standing composites only for a cavalry unit's own move. Three layers,
## mirroring test_wheel_turn_maneuver.gd: the pure UnitManeuver.is_moving_wheel_turn /
## moving_wheel_turn_angle classifiers (no SceneTree), a unit-level integration exercising
## Unit.begin_moving_wheel/_advance_moving_wheel directly (including a turn past 180°, a
## capability the standing wheel's fixed 90° swing can never exercise), and a Battle-level
## integration confirming _apply_order_cmd picks this path for cavalry and leaves every
## existing infantry classification (rear-move/lateral-pivot/wheel-turn/plain march) unchanged.

const Maneuver = preload("res://scripts/UnitManeuver.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")

const FACING_RIGHT := Vector2.RIGHT
const FACING_DOWN := Vector2.DOWN


# --- pure classifiers -------------------------------------------------------

func test_sharp_forward_oblique_move_is_a_moving_wheel_for_cavalry() -> void:
	# 60° off facing, well past MOVING_WHEEL_MIN_ANGLE_DEG=45.
	var oblique := FACING_RIGHT.rotated(deg_to_rad(60.0)) * 200.0
	assert_true(Maneuver.is_moving_wheel_turn(true, FACING_RIGHT, oblique),
		"a sharp forward-oblique move is a moving wheel for a cavalry unit")


func test_lateral_move_is_a_moving_wheel_for_cavalry() -> void:
	assert_true(Maneuver.is_moving_wheel_turn(true, FACING_RIGHT, Vector2(0, 200)),
		"a pure lateral (90°) move is a moving wheel too -- not scoped to the rear sector")


func test_rear_move_is_a_moving_wheel_for_cavalry() -> void:
	assert_true(Maneuver.is_moving_wheel_turn(true, FACING_RIGHT, Vector2(-200, 0)),
		"a straight rear move (180°) is a moving wheel too -- not scoped to the forward side")


func test_shallow_heading_correction_is_not_a_moving_wheel() -> void:
	# 30° off facing, under the threshold -- the ordinary march's own gradual centre-pivot
	# is still a fine fit for a modest correction like this.
	var shallow := FACING_RIGHT.rotated(deg_to_rad(30.0)) * 200.0
	assert_false(Maneuver.is_moving_wheel_turn(true, FACING_RIGHT, shallow),
		"a shallow heading correction keeps the plain march's own gradual centre-pivot")


func test_moving_wheel_boundary_matches_the_min_angle_threshold() -> void:
	var at_boundary := FACING_RIGHT.rotated(deg_to_rad(45.0)) * 200.0
	var just_under := FACING_RIGHT.rotated(deg_to_rad(44.0)) * 200.0
	assert_true(Maneuver.is_moving_wheel_turn(true, FACING_RIGHT, at_boundary),
		"exactly MOVING_WHEEL_MIN_ANGLE_DEG still arms the moving wheel")
	assert_false(Maneuver.is_moving_wheel_turn(true, FACING_RIGHT, just_under),
		"just under the threshold does not")


func test_moving_wheel_never_fires_for_infantry() -> void:
	# The same geometries that fire for cavalry above -- a straight rear move is the
	# strongest case, since it would otherwise also satisfy is_rear_move/is_wheel_turn.
	assert_false(Maneuver.is_moving_wheel_turn(false, FACING_RIGHT, Vector2(-200, 0)),
		"a foot unit never gets the moving wheel, however sharp the turn")
	assert_false(Maneuver.is_moving_wheel_turn(false, FACING_RIGHT, Vector2(0, 200)),
		"lateral case, still no moving wheel for a foot unit")


func test_degenerate_inputs_are_not_a_moving_wheel_turn() -> void:
	assert_false(Maneuver.is_moving_wheel_turn(true, Vector2.ZERO, Vector2(-100, 0)), "no facing")
	assert_false(Maneuver.is_moving_wheel_turn(true, FACING_RIGHT, Vector2.ZERO), "zero-length move")


func test_moving_wheel_turn_angle_matches_the_signed_angle_to_face_the_destination() -> void:
	# facing RIGHT, destination straight ahead-and-up (a +90° turn in Godot's rotated()
	# convention): facing.rotated(angle) must point exactly at the destination direction.
	var move_vec := Vector2(0, -150)
	var angle: float = Maneuver.moving_wheel_turn_angle(FACING_RIGHT, move_vec)
	assert_true(FACING_RIGHT.rotated(angle).is_equal_approx(move_vec.normalized()),
		"the returned angle rotates facing exactly onto the destination bearing")


func test_moving_wheel_turn_angle_magnitude_is_at_most_pi() -> void:
	# A destination almost exactly opposite facing (179.9°): still <= PI in magnitude --
	# no destination needs more than a half-turn to face it directly.
	var move_vec := FACING_RIGHT.rotated(deg_to_rad(179.9)) * 100.0
	var angle: float = Maneuver.moving_wheel_turn_angle(FACING_RIGHT, move_vec)
	assert_lte(absf(angle), PI + 0.001, "the natural signed angle to a destination never exceeds PI")


func test_moving_wheel_turn_angle_is_zero_for_degenerate_input() -> void:
	assert_eq(Maneuver.moving_wheel_turn_angle(Vector2.ZERO, Vector2(-10, 0)), 0.0)
	assert_eq(Maneuver.moving_wheel_turn_angle(FACING_RIGHT, Vector2.ZERO), 0.0)


# --- unit-level integration (Unit.begin_moving_wheel / _advance_moving_wheel) ------------

func _make_seeded_unit(cavalry: bool = true) -> Unit:
	var u: Unit = UnitScript.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.is_cavalry = cavalry
	u.position = Vector2.ZERO
	u.facing = FACING_DOWN
	u.seed_sim_soldiers()
	return u


func _step_wheel(u: Unit, max_ticks: int = 600) -> int:
	var ticks := 0
	while u.is_wheeling() and ticks < max_ticks:
		u._think(1.0 / 60.0)
		ticks += 1
	return ticks


func test_begin_moving_wheel_refuses_before_seeding() -> void:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.is_cavalry = true
	u.facing = FACING_DOWN
	var o := Order.new_move(Vector2(200, 0))
	u.set_current_order(o)
	assert_false(u.begin_moving_wheel(o, 1, deg_to_rad(90.0)),
		"with no seeded soldier bodies the moving wheel refuses instead of arming")


func test_begin_moving_wheel_refuses_while_fighting() -> void:
	var u := _make_seeded_unit()
	u.state = UnitScript.State.FIGHTING
	var o := Order.new_move(Vector2(200, 0))
	u.set_current_order(o)
	assert_false(u.begin_moving_wheel(o, 1, deg_to_rad(90.0)),
		"a fighting unit can't arm a moving wheel -- plain march instead")


func test_begin_moving_wheel_refuses_with_zero_dir() -> void:
	var u := _make_seeded_unit()
	var o := Order.new_move(Vector2(200, 0))
	u.set_current_order(o)
	assert_false(u.begin_moving_wheel(o, 0, deg_to_rad(90.0)),
		"dir=0 has no flank to hinge toward")


func test_begin_moving_wheel_builds_a_two_child_wheel_then_march_tree() -> void:
	var u := _make_seeded_unit()
	var dest := Vector2(200, 0)
	var o := Order.new_move(dest)
	u.set_current_order(o)
	u.has_move_target = false
	assert_true(u.begin_moving_wheel(o, 1, deg_to_rad(90.0)), "the moving wheel armed")
	assert_eq(o.children.size(), 2, "a wheel leaf then a march leaf -- no about-face phase")
	assert_eq(o.children[0].type, Order.Type.WHEEL)
	assert_true(o.children[0].is_moving_wheel, "the wheel leaf is tagged as a moving wheel")
	assert_eq(o.children[1].type, Order.Type.MOVE)
	assert_eq(o.children[1].target_pos, dest, "the march leg carries the original destination")
	assert_eq(o._active_child, 0, "the wheel phase runs first")
	assert_true(u.is_wheeling(), "the unit reads as mid-wheel immediately")


func test_moving_wheel_starts_from_the_current_facing_no_about_face() -> void:
	var u := _make_seeded_unit()
	var start_facing: Vector2 = u.facing
	var o := Order.new_move(Vector2(200, 0))
	u.set_current_order(o)
	u.has_move_target = false
	u.begin_moving_wheel(o, 1, deg_to_rad(90.0))
	# Unlike the about-face+wheel composite, the wheel starts RIGHT AWAY from the pre-turn
	# facing -- no 180° reversal happens first.
	assert_true(u.facing.is_equal_approx(start_facing),
		"facing has not jumped anywhere yet -- the wheel eases it, it doesn't snap")
	assert_almost_eq(u.active_leaf().wheel_turn_remaining, deg_to_rad(90.0), 0.001)


func test_moving_wheel_reads_as_moving_not_idle_while_swinging() -> void:
	var u := _make_seeded_unit()
	var o := Order.new_move(Vector2(200, 0))
	u.set_current_order(o)
	u.has_move_target = false
	u.begin_moving_wheel(o, 1, deg_to_rad(90.0))
	u._think(1.0 / 60.0)
	assert_eq(u.state, UnitScript.State.MOVING,
		"a moving wheel keeps the unit's state at MOVING -- unlike the standing wheel's IDLE, " +
		"it never stops advancing")


func test_moving_wheel_ends_at_the_requested_bearing_then_hands_off_to_the_march() -> void:
	var u := _make_seeded_unit()
	var dest := Vector2(300, -50)
	var o := Order.new_move(dest)
	u.set_current_order(o)
	u.has_move_target = false
	var start_facing: Vector2 = u.facing
	var turn_angle: float = deg_to_rad(72.0)
	u.begin_moving_wheel(o, 1, turn_angle)
	_step_wheel(u)
	assert_false(u.is_wheeling(), "the swing completed within budget")
	assert_true(u.facing.is_equal_approx(start_facing.rotated(turn_angle)),
		"facing lands exactly on the requested bearing, not a fixed 90°")
	assert_true(u.has_move_target, "the march leg took over once the wheel finished")
	assert_eq(u.move_target, dest, "marching to the original destination")
	assert_false(u._reform_on_arrival,
		"no about-face happened, so there's nothing to reform -- unlike the about-face+wheel " +
		"composite's own forced reform-on-arrival")


func test_moving_wheel_rate_ceiling_is_looser_than_the_standing_wheels() -> void:
	# MOVING_WHEEL_TURN_RATE (PI rad/s) is deliberately double WHEEL_TURN_RATE (PI/2) -- a
	# cavalry unit galloping through a continuous wheel is meaningfully brisker than a foot
	# drill's stately pace. Pin a single tick's progress directly to the constant: a small
	# block (tiny outer radius) with the unit standing still (_current_speed=0, so the
	# gait-rate formula's other input -- move_speed minus that -- is large) makes the RATE
	# CEILING the binding term, not the radius-derived one, so wheel_turn_remaining should
	# shrink by very close to MOVING_WHEEL_TURN_RATE * delta in exactly one tick -- roughly
	# double what the standing wheel's own WHEEL_TURN_RATE would produce for the identical
	# turn_angle and geometry.
	var u: Unit = UnitScript.new()
	u.max_soldiers = 4   # tiny block -- outer radius stays small enough for the rate
	                      # ceiling (not the gait/radius ratio) to bind
	add_child_autofree(u)
	u.is_cavalry = true
	u.position = Vector2.ZERO
	u.facing = FACING_DOWN
	u.seed_sim_soldiers()
	u._current_speed = 0.0
	var o := Order.new_move(Vector2(200, 0))
	u.set_current_order(o)
	u.has_move_target = false
	var turn_angle: float = deg_to_rad(90.0)
	u.begin_moving_wheel(o, 1, turn_angle)
	var leaf: Order = u.active_leaf()
	var delta := 1.0 / 60.0
	u._think(delta)
	var moving_wheel_step: float = turn_angle - absf(leaf.wheel_turn_remaining)
	assert_almost_eq(moving_wheel_step, UnitScript.MOVING_WHEEL_TURN_RATE * delta, 0.01,
		"one tick's progress matches the MOVING_WHEEL_TURN_RATE ceiling directly")
	assert_almost_eq(UnitScript.MOVING_WHEEL_TURN_RATE, UnitScript.WHEEL_TURN_RATE * 2.0, 0.001,
		"the moving wheel's own ceiling is exactly double the standing wheel's")


func test_moving_wheel_sweeps_past_180_degrees_in_one_continuous_swing() -> void:
	# The standing wheel (Unit.wheel) can only ever swing a fixed 90°; begin_moving_wheel's
	# own turn_angle is not capped this way. Sweep 200° -- past what any "turn to face a
	# destination" ever naturally asks for (that's bounded at 180°, moving_wheel_turn_angle's
	# own contract) -- to prove the underlying stepping mechanism (wheel_turn_remaining, not
	# a goal-vector proximity check) genuinely completes a turn beyond a half-circle instead
	# of being mistaken for "arrived" the moment facing first passes near the goal from the
	# wrong side.
	var u := _make_seeded_unit()
	var o := Order.new_move(Vector2(100, 100))
	u.set_current_order(o)
	u.has_move_target = false
	var start_facing: Vector2 = u.facing
	var turn_angle: float = deg_to_rad(200.0)
	assert_true(u.begin_moving_wheel(o, 1, turn_angle), "a >180° moving wheel arms")
	var leaf: Order = u.active_leaf()
	# Run until the sweep has covered at least 180° (i.e. no more than 20° of the requested
	# 200° remains) -- at this point a goal-vector-proximity check would already read facing
	# as having reached (or passed near) the destination bearing corresponding to the SHORT
	# way around. The genuine, remaining-angle-tracked sweep must still be running.
	var ticks := 0
	while absf(leaf.wheel_turn_remaining) > deg_to_rad(20.0) and ticks < 2000:
		u._think(1.0 / 60.0)
		ticks += 1
	assert_true(u.is_wheeling(),
		"still mid-swing after 180° of a 200° sweep -- it must not stop early")
	_step_wheel(u, 2000)
	assert_false(u.is_wheeling(), "the full 200° sweep completed within budget")
	assert_true(u.facing.is_equal_approx(start_facing.rotated(turn_angle)),
		"facing lands on the actual >180° bearing requested, not the short way's complement")


func test_moving_wheel_hinge_is_the_standing_flank_front_corner_same_as_the_standing_wheel() -> void:
	# begin_moving_wheel reuses _wheel_pivot_point exactly like the standing wheel -- the
	# geometry of "which corner is the hinge" doesn't change for the moving case.
	var u := _make_seeded_unit()
	var o := Order.new_move(Vector2(200, 0))
	u.set_current_order(o)
	u.has_move_target = false
	var expected_pivot: Vector2 = u._wheel_pivot_point(1)
	u.begin_moving_wheel(o, 1, deg_to_rad(90.0))
	assert_true(u.active_leaf().pivot.is_equal_approx(expected_pivot),
		"the moving wheel's initial hinge matches _wheel_pivot_point(dir)")


func test_moving_wheel_hinge_translates_forward_along_the_pre_wheel_facing() -> void:
	var u := _make_seeded_unit()
	u._current_speed = 60.0
	var o := Order.new_move(Vector2(300, 0))
	u.set_current_order(o)
	u.has_move_target = false
	var start_facing: Vector2 = u.facing
	u.begin_moving_wheel(o, 1, deg_to_rad(90.0))
	var leaf: Order = u.active_leaf()
	assert_true(leaf.wheel_translate_dir.is_equal_approx(start_facing),
		"the hinge's translation direction is captured as the pre-wheel facing")
	var hinge_before: Vector2 = leaf.pivot
	u._think(1.0 / 60.0)
	var expected_step: Vector2 = start_facing * (60.0 / 60.0)   # _current_speed * delta
	assert_true(leaf.pivot.is_equal_approx(hinge_before + expected_step),
		"the hinge advances by _current_speed * delta along the captured facing each tick")


# --- Battle-level integration ------------------------------------------------

func _unit(uid: int, pos: Vector2, cavalry: bool) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = uid
	u.position = pos
	u.max_soldiers = 60
	u.facing = FACING_DOWN
	u.is_cavalry = cavalry
	u.seed_sim_soldiers()
	u.reform_before_move = false
	return u


func _battle(units: Array) -> Node:
	var b = BattleScript.new()
	autofree(b)
	for u in units:
		b._by_uid[u.uid] = u
	return b


func test_sharp_lateral_move_arms_a_moving_wheel_for_cavalry() -> void:
	var u := _unit(1, Vector2.ZERO, true)
	var b := _battle([u])
	var dest: Vector2 = Vector2(300, 0)   # 90° lateral, well past the min-angle threshold
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1})
	assert_true(u.is_wheeling(), "the moving wheel armed immediately")
	assert_eq(u.current_order.children.size(), 2,
		"wheel then march -- no about-face, no reform hold")
	assert_true(u.current_order.children[0].is_moving_wheel)
	assert_false(u.current_order.reform, "a moving wheel never reforms before marching")


func test_sharp_rear_move_arms_a_moving_wheel_for_cavalry_instead_of_the_wheel_turn_composite() -> void:
	# The same oblique rear-sector geometry test_wheel_turn_maneuver.gd's
	# test_oblique_rear_move_arms_a_wheel_turn_composite exercises for infantry (140° off
	# facing) -- for CAVALRY it must instead arm the single-phase moving wheel.
	var u := _unit(1, Vector2.ZERO, true)
	var b := _battle([u])
	var dest: Vector2 = FACING_DOWN.rotated(deg_to_rad(140.0)) * 200.0
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1})
	assert_true(u.is_wheeling(), "a single continuous wheel armed, not the about-face+wheel composite")
	assert_eq(u.current_order.children.size(), 2,
		"two phases (wheel, march) -- not the infantry composite's three (about-face, wheel, march)")


func test_fighting_cavalry_unit_does_not_arm_a_moving_wheel() -> void:
	var u := _unit(1, Vector2.ZERO, true)
	u.state = UnitScript.State.FIGHTING
	var b := _battle([u])
	var dest: Vector2 = Vector2(300, 0)
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1})
	assert_false(u.is_wheeling(), "a fighting unit can't turn in place -- plain march instead")
	assert_true(u.has_move_target, "and marches immediately instead")


func test_form_up_face_command_never_arms_a_moving_wheel_even_for_cavalry() -> void:
	# A form-up commands its own facing via the "face" key -- like side-step/rear-move/
	# lateral-pivot above it, the moving wheel is excluded from that path entirely.
	var u := _unit(1, Vector2.ZERO, true)
	var b := _battle([u])
	var dest: Vector2 = Vector2(300, 0)
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1,
			"face": (Vector2.RIGHT).angle()})
	assert_false(u.is_wheeling(), "a drag-to-form-up move never arms a moving wheel")


# --- infantry regression: existing classification is completely unaffected --------------

func test_infantry_oblique_rear_move_still_arms_the_wheel_turn_composite_unchanged() -> void:
	# The exact scenario test_wheel_turn_maneuver.gd's own
	# test_oblique_rear_move_arms_a_wheel_turn_composite covers -- repeated here with an
	# explicit is_cavalry=false unit, right next to the cavalry version above, so the two
	# outcomes sit side by side as the direct proof that only the unit type differs.
	var u := _unit(1, Vector2.ZERO, false)
	var b := _battle([u])
	var dest: Vector2 = FACING_DOWN.rotated(deg_to_rad(140.0)) * 200.0
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1})
	assert_true(u.is_order_turning(), "the about-face armed, exactly as before this PR")
	assert_false(u.has_move_target, "the march is parked until the whole composite completes")
	assert_eq(u.current_order.children.size(), 3,
		"about-face, wheel, and march -- the infantry composite is unaffected")
	assert_eq(u.current_order.children[1].type, Order.Type.WHEEL)
	assert_false(u.current_order.children[1].is_moving_wheel,
		"the infantry wheel-turn's own wheel leaf is a STANDING wheel, not a moving one")


func test_infantry_lateral_move_still_arms_the_lateral_pivot_unchanged() -> void:
	var u := _unit(1, Vector2.ZERO, false)
	var b := _battle([u])
	var dest: Vector2 = Vector2(300, 0)   # same geometry the cavalry lateral test above uses
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1})
	assert_true(u.is_order_turning(), "a quarter-turn armed (lateral-pivot), exactly as before")
	assert_false(u.is_wheeling(), "not a wheel at all")
	assert_eq(u.current_order.type, Order.Type.MOVE)
	assert_eq(u.current_order.children.size(), 2, "quarter-turn then march (the lateral-pivot's " +
		"own opening two children -- the return turn is appended later on arrival)")


func test_infantry_moderate_oblique_move_still_gets_the_plain_gradual_pivot_march() -> void:
	# 60° off facing: for a foot unit this has never been any drilled maneuver's territory
	# (below is_lateral_pivot's ~63° onset, and nowhere near the rear sector) -- it just
	# marches with _move_to's own gradual centre-pivot. For CAVALRY the identical geometry
	# now arms a moving wheel (see test_sharp_forward_oblique_move_is_a_moving_wheel_for_cavalry
	# above) -- this is the direct side-by-side proof that only cavalry gets the new path.
	var u := _unit(1, Vector2.ZERO, false)
	var b := _battle([u])
	var dest: Vector2 = FACING_DOWN.rotated(deg_to_rad(60.0)) * 200.0
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1})
	assert_false(u.is_wheeling(), "no moving wheel for a foot unit")
	assert_false(u.is_order_turning(), "no in-place turn either")
	assert_true(u.current_order.children.is_empty(), "a plain, unphased march order")
	assert_true(u.has_move_target, "marching immediately, gradual centre-pivot en route")


func test_cavalry_same_moderate_oblique_move_arms_a_moving_wheel() -> void:
	# The cavalry counterpart to the infantry test directly above, same geometry.
	var u := _unit(1, Vector2.ZERO, true)
	var b := _battle([u])
	var dest: Vector2 = FACING_DOWN.rotated(deg_to_rad(60.0)) * 200.0
	b._apply_order_cmd({"units": [1], "x": dest.x, "y": dest.y, "target": -1})
	assert_true(u.is_wheeling(), "cavalry gets the moving wheel for the identical geometry")
