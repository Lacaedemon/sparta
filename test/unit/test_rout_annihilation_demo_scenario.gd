extends GutTest
## Regression guard for the rout->annihilation demo (demos/inputs/rout-rally-recover.json,
## kept under its original name): staging this matchup in a live Battle produces a visible
## rout FOLLOWED BY the routed unit being run down and destroyed. The lone low-morale
## infantry block breaks (enters ROUTING, drawn faded); routing units are still valid combat
## targets (broken/shattered units can be attacked --- see UnitTargeting.nearest_enemy's
## include_routing), and the two cavalry are faster than the fleeing infantry (8.5 vs 4.0
## sprint_mps), so pursuit is relentless: they catch it, and the casualties from being caught
## erode morale faster than _process_rout's baseline recovery, so it never rallies. It is
## eventually ANNIHILATED (soldiers reach zero) rather than escaping the map or rallying. A
## second, safe player unit keeps the battle from declaring defeat (and freezing) the instant
## the infantry routs -- the same reason the demo scenario includes one. This pins the demo's
## determinism: if a balance change ever stops the unit routing, or lets it escape the pursuit
## instead, this fails instead of the demo silently going stale.
##
## For a clean demonstration of a successful RALLY (recoverable "broken" state) in isolation,
## see test_morale_recovery_demo_scenario.gd --- a single already-routing unit with no enemies
## on the field, so nothing interferes with its recovery. Demo scenarios should generally be
## built to isolate the phenomenon they're meant to show, rather than layering it onto a
## combat arc that can go a different way depending on relative unit speeds.

# Budget the arc in SIM ticks (Battle.current_tick()), not in await iterations. Under coverage
# instrumentation an `await physics_frame` no longer maps one-to-one onto a sim tick, so counting
# loop iterations against a fixed clip length races the interpreter's speed. Reading the battle's
# own tick counter measures sim progress directly, and the budget comes from the sim's own timing
# constants (with generous margin) rather than the demo's presentation clip length.
#
# A two-cavalry charge onto a morale-1 block routs it; the faster cavalry then run it down within
# ROUT_TIME (observed annihilation around tick ~230 once the soldier bodies correctly keep
# stepping/coupling while routing --- see Battle._on_soldier_tick). ROUT_ONSET_BUDGET covers
# the charge-in and break; ROUT_TIME plus margin covers the chase-and-catch. The onset budget is
# deliberately generous so a physics retune (e.g. a change to the soldier-body arrival dynamics)
# that shifts *when* the block breaks doesn't push the arc past the budget: the onset has been
# observed anywhere from ~tick 100 to ~tick 365 depending on the body physics, and the whole arc
# still lands well inside this total.
const ROUT_ONSET_BUDGET := 600   # ticks allowed for the block to break and start routing
const CHASE_MARGIN := 240        # slack past ROUT_TIME for the pursuit to catch and finish it


var _battle: Node = null


func _rout_time_ticks() -> int:
	# The sim's fixed step rate, from the canonical autoload constant, so the tick budget tracks
	# the real step rate if it ever changes rather than a duplicated literal.
	return int(ceil(Unit.ROUT_TIME * Replay.PHYSICS_TPS))


func _spawn_rout_rally_battle() -> void:
	# Seed the battle deterministically, exactly as the demo does (rout-rally-recover.json
	# carries seed "12345"). Battle._ready() calls Replay.start_recording(), which consumes
	# forced_seed into the RNG stream. Without this the scenario's combat rolls draw from
	# whatever RNG state earlier tests left, so the arc varies run to run and can flake.
	# Seeding pins it.
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	_battle = battle
	# The exact matchup from demos/inputs/rout-rally-recover.json.
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 430, "count": 140, "morale": 1.0},
		{"team": 0, "type": "Spearmen", "x": 300, "y": 300, "count": 140, "morale": 100.0},
		{"team": 1, "type": "Cavalry", "x": 740, "y": 560},
		{"team": 1, "type": "Cavalry", "x": 860, "y": 560},
	]
	add_child_autofree(battle)


## The infantry regiment (the one that routs), by name -- so we don't pick up the standing
## spearmen. Still routing, it's in "routers"; once annihilated it's in neither group.
func _infantry() -> Unit:
	for g in ["units", "routers"]:
		for u in get_tree().get_nodes_in_group(g):
			var unit: Unit = u as Unit
			if unit != null and unit.team == 0 and str(unit.unit_name).begins_with("Infantry"):
				return unit
	return null


func test_scenario_routs_then_is_annihilated_under_pursuit() -> void:
	_spawn_rout_rally_battle()
	await get_tree().physics_frame

	assert_not_null(_infantry(), "the low-morale infantry unit spawns")
	if _infantry() == null:
		return

	# Tick budget derived from the sim's own timing constants: onset headroom, the rout timer, and
	# slack for the pursuit to catch and finish it. Independent of interpreter speed.
	var budget: int = ROUT_ONSET_BUDGET + _rout_time_ticks() + CHASE_MARGIN

	var routed_tick: int = -1
	var soldiers_at_rout: int = -1
	var last_soldiers: int = -1
	var last_state: int = -1
	var last_y: float = 0.0
	var annihilated_tick: int = -1
	while _battle.current_tick() < budget:
		await get_tree().physics_frame
		var tick: int = _battle.current_tick()
		var unit: Unit = _infantry()
		if unit == null:
			annihilated_tick = tick
			break
		if unit.state == Unit.State.ROUTING and routed_tick < 0:
			routed_tick = tick
			soldiers_at_rout = unit.soldiers
		last_soldiers = unit.soldiers
		last_state = unit.state
		last_y = unit.position.y

	assert_true(routed_tick >= 0, "the weak unit breaks and ROUTS within the budget")
	assert_true(annihilated_tick > routed_tick,
		"the relentlessly-pursued router is run down and destroyed within the budget " +
		"(rout tick %d, gone by tick %d)" % [routed_tick, annihilated_tick])
	# It was still routing (never rallied), had taken further casualties since breaking (not merely
	# spawned dead), and was nowhere near the retreat margin's outer edge --- annihilated by combat,
	# not escaped off the map or removed some other way.
	assert_eq(last_state, Unit.State.ROUTING,
		"still fleeing (never rallied) right up to the moment it's destroyed")
	assert_true(last_soldiers < soldiers_at_rout,
		"took further casualties while routing, run down by the pursuit (started rout at %d, last seen at %d)"
			% [soldiers_at_rout, last_soldiers])
	assert_true(last_y > -100.0,
		"nowhere near the retreat margin's outer edge when it was destroyed (last y=%.1f) --- annihilated, not escaped"
			% last_y)
