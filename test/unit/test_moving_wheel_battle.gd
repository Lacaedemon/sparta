extends GutTest
## Moving wheel (Unit.begin_moving_wheel) in a LIVE battle: instantiate the real Battle scene,
## march a spawned cavalry unit to build real cruising speed, then order it onto a sharply
## off-heading destination mid-march and step it tick by tick through the resulting moving
## wheel (Battle._physics_process -> units -> _on_soldier_tick, with steering + couple),
## exactly as a player's own click would. Confirms the physical claim the issue is actually
## about: the standing-flank ("hinge") file's speed holds at the unit's own march pace
## throughout the swing, the far/outer file measurably runs faster (bounded by the gait-rate
## cap) while the swing is live, and both settle back down together once the wheel hands off
## to the plain march leg. The isolated-unit kinematics (hinge geometry, tree structure, the
## >180° sweep) live in test_moving_wheel_maneuver.gd; this is the full-scene, no-teleport,
## real-physics companion, mirroring test_wheel_battle.gd's own relationship to test_wheel.gd.


func _speed(before: Vector2, after: Vector2, delta: float) -> float:
	return before.distance_to(after) / delta


func test_moving_wheel_hinge_holds_pace_while_outer_file_runs_faster_then_settles() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true   # player line only -- isolates the maneuver from enemy AI
	add_child_autofree(battle)
	for _k in range(40):                       # spawn the army and let the bodies settle
		await get_tree().physics_frame

	# Pick the LEFTMOST team-0 cavalry unit specifically -- the default map's hill
	# (Battle.TERRAIN, rect x:[1150,1400]) sits directly south of the OTHER cavalry
	# regiment's spawn point, and a straight-ahead march for that one would need to route
	# around it (a real, correct PathField detour, not a bug) -- which would confound this
	# test's own "a straight march needs no turn" sanity check with unrelated terrain noise.
	var target: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0 and unit.is_cavalry \
				and (target == null or unit.position.x < target.position.x):
			target = unit
	assert_not_null(target, "found a team-0 cavalry unit")
	if target == null:
		return

	# First order: a plain march straight ahead (along the unit's own spawn facing), so the
	# unit is genuinely CRUISING -- not starting from a dead stop -- by the time the sharp
	# turn below arrives. Matches the issue's own framing: "a unit already marching ... can
	# wheel while continuing to advance."
	battle._apply_order_cmd({"units": [target.uid], "x": target.position.x,
			"y": target.position.y + 400.0, "target": -1})
	var start_facing: Vector2 = target.facing
	for _k in range(90):
		await get_tree().physics_frame
	var cruise_speed: float = target.current_speed
	assert_gt(cruise_speed, 5.0, "the cavalry unit is genuinely cruising before the turn (%.1f wu/s)"
			% cruise_speed)
	# A straight-ahead march can still pick up a few degrees of centre-pivot correction from
	# ordinary soldier-body settling noise (coupling/steering nudge position a hair off the
	# exact line right after spawn) -- not a turn this test is about. It stays well short of
	# MOVING_WHEEL_MIN_ANGLE_DEG=45°, which is all that actually matters for what follows.
	assert_gt(target.facing.dot(start_facing), 0.9,
		"a straight-ahead march stays close to its start facing (only minor settling noise)")

	# Second order: a sharp lateral turn (90° off the current heading), mid-march -- must
	# arm a moving wheel rather than any of the standing composites or a plain re-aim.
	var turn_dest: Vector2 = target.position + Vector2(320, 0)
	battle._apply_order_cmd({"units": [target.uid], "x": turn_dest.x, "y": turn_dest.y,
			"target": -1})
	assert_true(target.is_wheeling(), "the sharp mid-march turn armed a moving wheel")
	var leaf: Order = target.active_leaf()
	assert_true(leaf.is_moving_wheel, "and it is the MOVING variant, not a standing one")

	# Identify the hinge-nearest and farthest soldier bodies from the armed wheel's own
	# hinge, exactly as test_wheel_battle.gd does for the standing wheel.
	var pivot: Vector2 = leaf.pivot
	var near_hinge := 0
	var far := 0
	var dn := INF
	var df := -INF
	for i in range(target._sim_soldier_pos.size()):
		var d: float = target._sim_soldier_pos[i].distance_to(pivot)
		if d < dn:
			dn = d; near_hinge = i
		if d > df:
			df = d; far = i

	var hinge_pos: Vector2 = target._sim_soldier_pos[near_hinge]
	var far_pos: Vector2 = target._sim_soldier_pos[far]
	var delta := 1.0 / 60.0
	var worst_hinge_speed := 0.0
	var worst_far_speed := 0.0
	var swing_ticks := 0
	while target.is_wheeling() and swing_ticks < 900:
		await get_tree().physics_frame
		var new_hinge_pos: Vector2 = target._sim_soldier_pos[near_hinge]
		var new_far_pos: Vector2 = target._sim_soldier_pos[far]
		worst_hinge_speed = maxf(worst_hinge_speed, _speed(hinge_pos, new_hinge_pos, delta))
		worst_far_speed = maxf(worst_far_speed, _speed(far_pos, new_far_pos, delta))
		hinge_pos = new_hinge_pos
		far_pos = new_far_pos
		swing_ticks += 1
	assert_false(target.is_wheeling(), "the moving wheel completed within budget")
	# Capture facing the INSTANT the swing itself finishes, before the march leg's own
	# gradual centre-pivot (and the same soldier-body settling noise the straight march
	# above picked up) has a chance to nudge it any further -- this isolates the WHEEL's
	# own accuracy from unrelated post-wheel march dynamics.
	var facing_at_wheel_end: Vector2 = target.facing

	# The far/outer file ran meaningfully faster than the hinge file at some point during
	# the swing -- the issue's own "outer ranks accelerate temporarily" -- but never past the
	# unit's own sprint (move_speed), the gait-rate cap's whole point (10% headroom over the
	# cap, matching test_wheel.gd's own convention for the standing wheel's jog cap).
	assert_gt(worst_far_speed, cruise_speed * 1.15,
		"the outer file measurably outran the cruising pace during the swing (far %.1f vs cruise %.1f)"
			% [worst_far_speed, cruise_speed])
	assert_lt(worst_far_speed, target.move_speed * 1.1,
		"the outer file never outruns the unit's own sprint (far %.1f vs move_speed %.1f)"
			% [worst_far_speed, target.move_speed])
	# The hinge file, meanwhile, never got artificially sped up by the wheel itself -- its
	# worst tick stays within the same ballpark as the cruise pace it was already holding
	# (some headroom for soldier-body coupling noise), well under what the outer file hit.
	assert_lt(worst_hinge_speed, cruise_speed * 1.5,
		"the hinge file's pace isn't inflated by the wheel (hinge %.1f vs cruise %.1f)"
			% [worst_hinge_speed, cruise_speed])
	assert_lt(worst_hinge_speed, worst_far_speed * 0.85,
		"the hinge file stayed well below the outer file's peak swing speed (hinge %.1f vs far %.1f)"
			% [worst_hinge_speed, worst_far_speed])

	# Once the wheel hands off to the plain march leg, the differential settles back out:
	# sample a few more ticks and confirm the far file's pace has come back down near the
	# hinge file's, instead of still running at the swing's outer pace.
	for _k in range(30):
		await get_tree().physics_frame
	var post_hinge_pos: Vector2 = target._sim_soldier_pos[near_hinge]
	var post_far_pos: Vector2 = target._sim_soldier_pos[far]
	var settle_ticks := 20
	var post_far_speed := 0.0
	var post_hinge_speed := 0.0
	for _k in range(settle_ticks):
		await get_tree().physics_frame
		var new_hinge_pos: Vector2 = target._sim_soldier_pos[near_hinge]
		var new_far_pos: Vector2 = target._sim_soldier_pos[far]
		post_hinge_speed = maxf(post_hinge_speed, _speed(post_hinge_pos, new_hinge_pos, delta))
		post_far_speed = maxf(post_far_speed, _speed(post_far_pos, new_far_pos, delta))
		post_hinge_pos = new_hinge_pos
		post_far_pos = new_far_pos
	assert_lt(post_far_speed, worst_far_speed * 0.6,
		"the outer file's pace drops back down once the wheel hands off to the plain march " +
		"(post %.1f vs peak swing %.1f)" % [post_far_speed, worst_far_speed])
	# And it settles back to a pace comparable to the hinge file's own -- both files
	# marching the same regiment at the same pace again, not just the outer file's own
	# peak having dropped in isolation.
	assert_lt(absf(post_far_speed - post_hinge_speed), cruise_speed * 0.5,
		"hinge and outer file settle back onto a comparable pace together (hinge %.1f vs far %.1f)"
			% [post_hinge_speed, post_far_speed])

	# The wheel itself ended up genuinely facing the ordered destination's own bearing --
	# computed straight from the move vector, not asserted as a fixed 90° turn from the
	# start facing -- checked at the moment the swing completed, ahead of any further march
	# leg drift.
	assert_gt(facing_at_wheel_end.dot(Vector2.RIGHT), 0.99,
		"the wheel's own final facing matches the actual bearing to the ordered destination " +
		"(due east, the direction turn_dest was placed in) -- got (%.4f, %.4f)"
			% [facing_at_wheel_end.x, facing_at_wheel_end.y])


## A genuine >180° sweep in the SAME live-battle context as the test above -- real soldier
## bodies, real steering/coupling every tick -- rather than only the bare-unit version in
## test_moving_wheel_maneuver.gd. Calls begin_moving_wheel directly with an explicit 200°
## turn_angle: as UnitManeuver.moving_wheel_turn_angle's own doc notes, "turn to face a
## destination" can never itself ask for more than 180° (the shortest angle to any bearing
## is at most a half-turn), so a genuine >180° sweep is a capability of the primitive
## itself, not something a plain move order's classification can trigger on its own --
## exercised directly here, with the real per-tick orchestration (steering, coupling,
## separation) a bare Unit.new() fixture never runs through.
func test_moving_wheel_sweeps_past_180_degrees_in_a_live_battle() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	add_child_autofree(battle)
	for _k in range(40):
		await get_tree().physics_frame

	var target: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0 and unit.is_cavalry \
				and (target == null or unit.position.x < target.position.x):
			target = unit
	assert_not_null(target, "found a team-0 cavalry unit")
	if target == null:
		return

	var start_facing: Vector2 = target.facing
	var turn_angle: float = deg_to_rad(200.0)
	var o := Order.new_move(target.position + Vector2(100, 100))
	target.set_current_order(o)
	target.has_move_target = false
	assert_true(target.begin_moving_wheel(o, 1, turn_angle),
		"a >180° moving wheel arms on a real spawned unit")
	var leaf: Order = target.active_leaf()

	# Confirm it doesn't stop early: after covering at least 180° of the requested 200°,
	# the sweep must still be running (a goal-vector-proximity check would have already
	# read this as "arrived" the short way).
	var ticks := 0
	while absf(leaf.wheel_turn_remaining) > deg_to_rad(20.0) and ticks < 1200:
		await get_tree().physics_frame
		ticks += 1
	assert_true(target.is_wheeling(), "still mid-swing after 180° of a 200° sweep")

	while target.is_wheeling() and ticks < 1200:
		await get_tree().physics_frame
		ticks += 1
	assert_false(target.is_wheeling(), "the full 200° sweep completed within budget")
	assert_gt(target.facing.dot(start_facing.rotated(turn_angle)), 0.99,
		"facing lands on the actual >180° bearing requested, not the short way's complement")
