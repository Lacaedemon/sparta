extends GutTest
## Live-battle regression for the caracole-vs-fleeing-target arc: the cycle-charge
## recharge peel used to strand its pursuer for good the first time a target routed away
## mid-cycle. The peel galloped through the standoff turn-around at full sprint (its
## re-planted goal always sits inside the sprint window), the soldier bodies then coasted
## far past the standoff dragging the coupled regiment with them, and the walk-pace
## re-approach never closed on a router fleeing at nearly the same speed -- an endless
## recede while the unit still reported an active attack on the target.
##
## Stages the fix's own reproduction (demos/inputs/cycle-charge-flee.json, drawn in): a
## lone cycle-charge cavalry against a brittle infantry that routs on the first impact
## strike and flees. The loop is proven by the SECOND strike landing -- peel out at a
## trot, brake and turn at the standoff, canter back in, sprint the last stretch, and hit
## the target again. Budgets are bounded on Battle.current_tick() (real sim ticks), not
## await-iterations, so coverage instrumentation cannot drift them.

## Ticks for the opening charge to land from ~200 wu out: the sprint window opens
## immediately, so contact is one accel ramp away (~2.5 s) -- budgeted with wide headroom.
const FIRST_STRIKE_BUDGET: int = 600
## Ticks from the first strike to the second: peel ~280 wu at a trot (~4 s), brake and
## turn (~2 s), then re-close the standoff plus the router's lead at the canter-vs-flee
## closure rate (~11 s), and sprint the last stretch -- roughly 700 ticks in practice,
## budgeted at about double for headroom.
const SECOND_STRIKE_BUDGET: int = 1500


func test_cycle_charge_lands_a_second_strike_after_the_target_routs_away() -> void:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.all_teams_control = true   # keep team 1's battle AI from re-ordering the infantry
	battle.terrain = []               # flat field: pathfinding must not shape this arc
	battle.scenario = [
		{"team": 0, "type": "Cavalry", "x": 500, "y": 600, "count": 24},
		{"team": 1, "type": "Infantry", "x": 700, "y": 600, "count": 70, "morale": 2.0},
	]
	add_child_autofree(battle)

	var cav: Unit = null
	var inf: Unit = null
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u == null:
			continue
		if u.team == 0:
			cav = u
		else:
			inf = u
	assert_not_null(cav, "the scenario spawns the player cavalry")
	assert_not_null(inf, "and the enemy infantry")
	if cav == null or inf == null:
		return

	# The player gesture (arm the J stance, right-click the enemy) reduces to the stance
	# plus the explicit target; _think drives the whole caracole loop from these.
	cav.order_mode = Unit.ORDER_CYCLE_CHARGE
	cav.target_enemy = inf
	var start_count: int = inf.soldiers

	while battle.current_tick() < FIRST_STRIKE_BUDGET and inf.soldiers >= start_count:
		await get_tree().physics_frame
	assert_lt(inf.soldiers, start_count, "the opening charge lands within its budget")
	# The strike flips the charger into its recharge peel; the peel lasts whole seconds,
	# so this read cannot race the flip.
	assert_true(cav._cycle_recharging, "and flips the charger into the recharge peel")
	var after_first: int = inf.soldiers
	assert_eq(inf.state, Unit.State.ROUTING, "the brittle infantry breaks on the impact")

	var second_deadline: int = battle.current_tick() + SECOND_STRIKE_BUDGET
	while battle.current_tick() < second_deadline and inf.soldiers >= after_first:
		await get_tree().physics_frame
	assert_lt(inf.soldiers, after_first,
		"the caracole re-engages the target that routed away and lands a second strike")
