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
## The bodies may compress somewhat while the grid comes about (the paced pivot still
## asks the flanks for their full gait -- the tracked chase-deformation family), but
## never into deep interpenetration: pre-fix the minimum collapsed to ~1 wu on 20 wu
## mounts; post-fix it bottoms out above 3. The floor splits those with margin.
const NND_FLOOR: float = 2.5
## Eastward overshoot past the point where the reversal was ordered: pre-fix ~59 wu
## (full-pace momentum carried through the hold), post-fix ~41 (the paced moving pivot's
## own arc). The bound splits them.
const OVERSHOOT_MAX: float = 50.0


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
	var min_nnd: float = 1e9
	var probe: int = 0
	while battle.current_tick() < deadline:
		await get_tree().physics_frame
		max_x = maxf(max_x, cav.position.x)
		probe += 1
		if probe % 5 != 0:
			continue   # the compression window lasts seconds; every-5-tick sampling catches it
		var n: int = cav._sim_soldier_pos.size()
		for i in range(n):
			for j in range(i + 1, n):
				var d: float = cav._sim_soldier_pos[i].distance_to(cav._sim_soldier_pos[j])
				if d < min_nnd:
					min_nnd = d

	assert_gt(min_nnd, NND_FLOOR,
		"the bodies never collapse into deep interpenetration while the block comes about")
	assert_lt(max_x - order_x, OVERSHOOT_MAX,
		"the block does not carry far past the point where the reversal was ordered")
	assert_lt(cav.position.x, order_x - 50.0,
		"and it has made real westward progress toward the new destination")
