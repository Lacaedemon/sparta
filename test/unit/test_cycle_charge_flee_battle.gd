extends GutTest
## Live-battle regression for the caracole-vs-fleeing-target arc: the cycle-charge
## recharge peel used to strand its pursuer for good the first time a target routed away
## mid-cycle. The peel galloped through the standoff turn-around at full sprint (its
## re-planted goal always sits inside the sprint window), the soldier bodies then coasted
## far past the standoff dragging the coupled regiment with them, and the walk-pace
## re-approach never closed on a router fleeing at nearly the same speed -- an endless
## recede while the unit still reported an active attack on the target.
##
## Stages the catalog clip's matchup (demos/inputs/cycle-charge-flee.json, drawn in
## closer): a lone cycle-charge cavalry against a brittle infantry line. Opening
## melee is per-soldier, so the first blow no longer deletes 70 men; the loop is
## proven by a SECOND strike() cadence -- peel out at a trot, brake and turn at the
## standoff, canter back in, and strike again. Cycle charge peels after strike()
## runs, not after a wound: a single opposed-roll cadence can miss even when the
## fronts are in reach, so this test treats the peel flag as the landed-cadence
## signal. Formula-wipe vs per-soldier is pinned by test_small_unit_melee_wipe.gd.
## Budgets are bounded on Battle.current_tick() (real sim ticks), not
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
	var start_hp: float = _min_hp(inf)
	var peeled := false

	while battle.current_tick() < FIRST_STRIKE_BUDGET:
		if cav._cycle_recharging:
			peeled = true
		# Peel is the cadence signal: strike() arms _cycle_recharging even when
		# that one opposed-roll cadence misses. A wound also counts. Either is
		# enough to start the recede half.
		if inf.soldiers < start_count or _min_hp(inf) < start_hp - 0.01 or peeled:
			break
		await get_tree().physics_frame
	if cav._cycle_recharging:
		peeled = true
	assert_true(inf.soldiers < start_count or _min_hp(inf) < start_hp - 0.01 or peeled,
		"the opening charge lands a strike cadence within its budget")
	# The strike flips the charger into its recharge peel; the peel lasts whole seconds,
	# so this read cannot race the flip. Tracked across the wait because the unit may
	# already have opened the standoff again by the assert tick.
	assert_true(peeled, "and flips the charger into the recharge peel")
	# Per-soldier impact no longer deletes a 70-man line in one cadence, so a morale-2
	# regiment may still be standing after the first blow. The caracole-vs-fleeing
	# arc this test guards needs a routed target; stage that break here if combat
	# itself has not already routed them.
	if inf.state != Unit.State.ROUTING:
		inf._rout()
	var after_first: int = inf.soldiers
	var after_first_hp: float = _min_hp(inf)
	# The caracole's own proof is a SECOND peel: recharge drops at the standoff, then
	# strike() arms it again when the charger re-closes. Per-soldier blows against a
	# fleeing line may wound without dropping the roster, so a head-count gate would
	# miss a real second impact.
	var opened := false
	var second_peel := false

	var second_deadline: int = battle.current_tick() + SECOND_STRIKE_BUDGET
	while battle.current_tick() < second_deadline:
		if not cav._cycle_recharging:
			opened = true
		elif opened:
			second_peel = true
			break
		if inf.soldiers < after_first or _min_hp(inf) < after_first_hp - 0.01:
			break
		await get_tree().physics_frame
	assert_true(second_peel or inf.soldiers < after_first or _min_hp(inf) < after_first_hp - 0.01,
		"the caracole re-engages the target that routed away and lands a second strike")


func _min_hp(u: Unit) -> float:
	if u._sim_soldier_hp.is_empty():
		return 0.0
	var lowest: float = u._sim_soldier_hp[0]
	for i in range(1, u._sim_soldier_hp.size()):
		lowest = minf(lowest, u._sim_soldier_hp[i])
	return lowest
