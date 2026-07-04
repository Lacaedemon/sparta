extends GutTest
## Isolated regression guard for the morale-RECOVERY half of the rout mechanic: a single
## already-routing ("broken") unit, with NO enemies anywhere on the field, recovers morale
## purely from _process_rout's baseline recovery and rallies back under control --- nothing
## else in play to interfere (no pursuit, no casualties, no contact to keep it "broken").
##
## This isolates the phenomenon the old two-cavalry rout-then-rally demo used to show.
## test_rout_annihilation_demo_scenario.gd's scenario now demonstrates the OPPOSITE outcome
## under pursuit instead: routing units are valid combat targets (broken/shattered units can
## be attacked --- see UnitTargeting.nearest_enemy's include_routing), and a pursuer fast
## enough to keep catching a fleeing unit can run it down before it ever recovers. Demo
## scenarios should generally be built to isolate the phenomenon they're meant to show,
## rather than layering it onto a combat arc whose outcome depends on relative unit speeds.


var _battle: Node = null


func after_each() -> void:
	# Free THIS test's battle before the next test spawns, so its unit doesn't linger in the
	# shared "units"/"routers" groups and pollute a later test's group scan.
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _spawn_lone_unit_battle() -> Node:
	_battle = load("res://scenes/Battle.tscn").instantiate()
	# drill_mode: _check_victory() treats "no enemies" as never a win in drill mode, so the
	# battle doesn't instantly declare Victory (and pause the tree, stalling every later
	# `await physics_frame` in this test forever) the moment it sees team 1 has zero units.
	_battle.drill_mode = true
	# No team-1 entry at all: this team-0 unit is the only body on the field, so nothing can
	# ever be "in contact" with it and nothing can strike it while it recovers.
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 500},
	]
	add_child(_battle)
	return _battle


func _team_unit(team: int) -> Unit:
	for g in ["units", "routers"]:
		for u in get_tree().get_nodes_in_group(g):
			var unit: Unit = u as Unit
			if unit != null and unit.team == team:
				return unit
	return null


func test_a_broken_unit_recovers_and_rallies_with_no_enemies_present() -> void:
	var battle := _spawn_lone_unit_battle()
	await get_tree().physics_frame   # _ready spawns the scenario unit

	var mine: Unit = _team_unit(0)
	assert_not_null(mine, "the lone unit deployed")
	if mine == null:
		return

	# Break it directly, deep in the collapse --- there's no enemy to have caused this, but
	# the point is isolating recovery, not the break itself (covered by other tests).
	mine.morale = 1.0
	mine._rout()
	assert_eq(mine.state, Unit.State.ROUTING, "the unit is routing")
	assert_false(mine._shattered, "starts \"broken\": recoverable")

	# Nothing to interfere: no enemy exists anywhere, so _can_rally() is trivially satisfied
	# the moment morale crosses the threshold (or the timer expires, whichever comes first ---
	# both lead to a rally here, never a shatter). Tick until it rallies, bounded by ROUT_TIME
	# plus generous slack for the asymptotic climb and the test loop's own granularity.
	var budget: int = int(ceil(Unit.ROUT_TIME * Replay.PHYSICS_TPS)) + 120
	var rallied_tick: int = -1
	while battle.current_tick() < budget:
		await get_tree().physics_frame
		var unit: Unit = _team_unit(0)
		assert_not_null(unit, "the unit stays on the field --- nothing here can kill or remove it")
		if unit == null:
			return
		assert_false(unit._shattered,
			"with no enemy ever in range it's never gutted past reforming or run down --- always recoverable")
		if unit.state == Unit.State.IDLE:
			rallied_tick = battle.current_tick()
			break

	assert_true(rallied_tick >= 0, "the broken unit rallies within the budget, with nothing to interfere")
	var rallied: Unit = _team_unit(0)
	assert_not_null(rallied, "the rallied unit is still on the field")
	if rallied != null:
		assert_true(rallied.is_in_group("units"), "the rallied unit rejoins the fightable units")
		assert_true(rallied.morale >= Unit.RALLY_MORALE,
			"it reforms at or above the fragile rally floor, having recovered from the collapse")
