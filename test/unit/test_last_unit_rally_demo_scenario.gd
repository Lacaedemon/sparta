extends GutTest
## Regression guard for the last-unit-rally demo (demos/inputs/last-unit-rally.json): staging
## that exact matchup in a live Battle produces a visible rout, without the battle instantly
## declaring defeat. Team 0 fields a single full-strength (120) but jittery (morale 15)
## infantry block against an enemy infantry of equal size; contact breaks its brittle morale
## and it flees (drawn faded) while barely bloodied. Losing its last fightable unit must NOT
## end the battle outright -- the sim stays live while the router is still on the field, per
## #495. This pins the demo's determinism against the #529 morale retune: if a balance change
## ever stops the unit routing (or breaks the "still in the fight while routing" invariant),
## this fails instead of the demo silently going stale.
##
## This does NOT assert the router eventually RALLIES: with roughly equal-speed combatants,
## the pursuer can keep pace and repeatedly re-catch it (routing units are valid combat
## targets -- see UnitTargeting.nearest_enemy's include_routing), so this matchup grinds
## through a long war of attrition before it resolves one way or another (observed: gutted
## to a fraction of its strength over ~2000 ticks before finally escaping the pursuit) --
## not the clean, bounded rally the two-cavalry / single-infantry demos show. Asserting a
## specific resolution here would just be pinning one RNG-sensitive outcome among several
## plausible ones. See test_rout_annihilation_demo_scenario.gd and
## test_morale_recovery_demo_scenario.gd for the two demos that isolate a single, clean
## outcome each; this one only guards the #495 invariant for this specific matchup.

const ROUT_ONSET_BUDGET := 900   # ticks allowed for the block to break and start routing
const STAYS_LIVE_MARGIN := 300   # further ticks to confirm the battle doesn't end while routing


var _battle: Node = null


func _spawn_last_unit_rally_battle() -> void:
	# Seed deterministically, exactly as the demo does (last-unit-rally.json carries seed
	# "12345"); see test_rout_annihilation_demo_scenario.gd for why this matters.
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	_battle = battle
	# The exact matchup from demos/inputs/last-unit-rally.json.
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 440, "count": 120, "morale": 15.0},
		{"team": 1, "type": "Infantry", "x": 800, "y": 560, "count": 120},
	]
	add_child_autofree(battle)


func _team0_infantry() -> Unit:
	for g in ["units", "routers"]:
		for u in get_tree().get_nodes_in_group(g):
			var unit: Unit = u as Unit
			if unit != null and unit.team == 0:
				return unit
	return null


func test_scenario_routs_without_the_battle_ending() -> void:
	_spawn_last_unit_rally_battle()
	await get_tree().physics_frame

	assert_not_null(_team0_infantry(), "the lone jittery infantry unit spawns")
	if _team0_infantry() == null:
		return

	var routed_tick: int = -1
	while _battle.current_tick() < ROUT_ONSET_BUDGET:
		await get_tree().physics_frame
		var unit: Unit = _team0_infantry()
		assert_not_null(unit, "team 0's last unit stays in play through the onset")
		if unit == null:
			return
		if unit.state == Unit.State.ROUTING:
			routed_tick = _battle.current_tick()
			break

	assert_true(routed_tick >= 0, "the jittery unit breaks and ROUTS within the budget")
	assert_false(_battle._ended, "the battle hasn't ended the instant its last unit routs")

	# Confirm the #495 invariant holds for a further stretch of routing: the battle must NOT
	# end while this unit is still on the field (whether it's ultimately headed for a rally,
	# an escape, or an annihilated-eventually grind -- any of which can take a very long time
	# under relentless pursuit, so this only samples a bounded window rather than waiting for
	# a final resolution).
	var stay_until: int = routed_tick + STAYS_LIVE_MARGIN
	while _battle.current_tick() < stay_until:
		await get_tree().physics_frame
		var unit: Unit = _team0_infantry()
		if unit == null:
			# Escaped or annihilated already -- either way, that's a real removal from play,
			# not the battle wrongly ending while the unit was still routing.
			break
		assert_false(_battle._ended,
			"the battle stays live at tick %d while the last unit is still routing (never merely 'shatters and ends')"
				% _battle.current_tick())
