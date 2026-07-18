extends GutTest
## Live-battle regression for the reversal-order wedge: a marching regiment ordered
## sharply back the way it came used to keep full-pace momentum through its
## response/reform hold (the momentum exemption was direction-blind) while the hold's
## UNPACED centre-pivot swung the slot grid underneath the still-flying bodies. The
## block scrambled into genuine body overlap (nearest-neighbour distances near a tenth
## of a body diameter), carried tens of units past the turn point, and spent hundreds
## of ticks re-forming before the new march began -- reading, next to an enemy, as a
## unit compressing and drifting toward it with no order to do so.
##
## Stages the wedge directly (no enemy needed -- the drift toward a router in the
## original report was just this momentum carrying on along the old heading): a lone
## cavalry marches east, then is ordered sharply back north-west mid-march. Asserts the
## transition stays formed and bounded. Budgets bound on Battle.current_tick() (real
## sim ticks), so coverage instrumentation cannot drift them.

## Ticks for the eastward march to reach cruising pace (accel ramp plus slack).
const CRUISE_BUDGET: int = 200
## Ticks allowed for the whole come-about: the response/reform hold (~1 s), a
## corner-man-paced ~140 degree pivot (~5 s at the wide cavalry block's bound), and
## enough marching after it to show real westward progress.
const TURN_BUDGET: int = 600
## Eastward overshoot past the point where the reversal was ordered: pre-fix ~59 wu
## (full-pace momentum carried through the hold), post-fix ~41 (the paced moving pivot's
## own arc). The bound splits them. (A nearest-neighbour floor is deliberately NOT
## asserted: the bodies still pinch transiently while the wide grid comes about --
## the depth of that pinch is phase-sensitive to the exact order tick, its pre/post-fix
## ranges overlap, and the residual belongs to the separately tracked formed-turn
## deformation family -- so the load-bearing regressions here are the hold BRAKING,
## the pivot PACING, and the bounded overshoot, each of which separates cleanly.)
const OVERSHOOT_MAX: float = 50.0
## The hold is the brake leg of the reversal: by the time the reform hold commits, the
## column must have shed most of its cruise -- pre-fix it carried the full walk pace
## (34 wu/s for cavalry) through the hold untouched.
const HOLD_BRAKE_FRAC: float = 0.6
## The come-about must pace to the corner man: raw TURN_RATE (PI rad/s) is several
## times what the wide cavalry block's bound allows, so a healthy margin below it
## still cleanly catches an unpaced pivot.
const PIVOT_RATE_MAX: float = PI * 0.5


func test_reversing_move_order_keeps_the_block_formed() -> void:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	battle.terrain = []
	battle.scenario = [
		{"team": 0, "type": "Cavalry", "x": 500, "y": 600, "count": 24},
	]
	add_child_autofree(battle)
	var cav: Unit = null
	for node in get_tree().get_nodes_in_group("units"):
		if node is Unit:
			cav = node
	assert_not_null(cav, "the scenario spawns the cavalry")
	if cav == null:
		return

	battle._apply_order_cmd({"units": [cav.uid], "x": 1200.0, "y": 600.0, "target": -1, "reform": true})
	while battle.current_tick() < CRUISE_BUDGET:
		await get_tree().physics_frame
	assert_gt(cav._current_speed, cav.walk_speed * 0.9, "cruising at pace before the reversal")

	var order_x: float = cav.position.x
	battle._apply_order_cmd({"units": [cav.uid], "x": 420.0, "y": 420.0, "target": -1, "reform": true})
	var deadline: int = battle.current_tick() + TURN_BUDGET
	var max_x: float = cav.position.x
	var hold_end_speed: float = -1.0
	var was_holding: bool = false
	var max_pivot_step: float = 0.0
	var prev_face: float = cav.facing.angle()
	while battle.current_tick() < deadline:
		await get_tree().physics_frame
		max_x = maxf(max_x, cav.position.x)
		var face: float = cav.facing.angle()
		max_pivot_step = maxf(max_pivot_step, absf(angle_difference(prev_face, face)))
		prev_face = face
		var holding: bool = cav._reform_holding() or cav._order_response_timer > 0.0
		if was_holding and not holding and hold_end_speed < 0.0:
			hold_end_speed = cav._current_speed   # first tick after the hold commits
		was_holding = was_holding or holding

	assert_true(was_holding, "the reversal actually ran a response/reform hold")
	assert_gte(hold_end_speed, 0.0, "and the hold committed within the budget")
	assert_lt(hold_end_speed, cav.walk_speed * HOLD_BRAKE_FRAC,
		"the hold brakes the cruising column instead of carrying full pace into the turn")
	assert_lt(max_pivot_step * 60.0, PIVOT_RATE_MAX,
		"the come-about paces to the corner man, well below the raw unpaced TURN_RATE")
	assert_lt(max_x - order_x, OVERSHOOT_MAX,
		"the block does not carry far past the point where the reversal was ordered")
	assert_lt(cav.position.x, order_x - 50.0,
		"and it has made real westward progress toward the new destination")
