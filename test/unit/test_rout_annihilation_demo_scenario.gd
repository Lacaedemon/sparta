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
# A two-squadron charge onto a morale-1 block routs it; the faster cavalry then run it
# down. ROUT_ONSET_BUDGET covers the charge-in and break; ROUT_TIME plus CHASE_MARGIN
# covers the chase-and-catch. The squadrons are shallow (12 horses): an 80-horse column's
# facing-front sits a mounted rank-pitch past regiment-circle contact, so per-soldier melee
# would land no blows and the block would never break. Twelve horses (three ranks) put that
# front on the infantry at contact, and the 12-man morale-1 line still crumples on the first
# deaths (morale erosion is a fraction of max strength). The squadrons spawn close so the
# onset is a charge into contact, not a long approach, and the onset budget stays generous so
# a physics retune that shifts *when* the block breaks doesn't push the arc past the budget.
#
# Budgets re-measured under the close-order density rebalance (an intended pace change)
# at the tall-field deep-south staging: the block breaks around tick 1200 locally and the
# pursuit grinds it to the last man by around tick 2830 locally. The observed local/CI
# divergence factors on this arc's earlier staging were ~1.45x on the rout onset and
# ~1.9x on the chase length, so the onset budget carries ~1.8x over the local reading and
# the total budget (~6160 ticks) carries ~1.3x over a CI arc extrapolated at those
# factors (~4830). A 12v12-plus-cavalry chase is squarely in the chaotic regime where
# local and CI runs of one seed diverge, which is what all that headroom is for.
const ROUT_ONSET_BUDGET := 2200  # ticks allowed for the block to break and start routing
const CHASE_MARGIN := 3600       # slack past ROUT_TIME for the pursuit to catch and finish it


var _battle: Node = null
# Set by _on_infantry_escaped: the tracked router crossed the retreat margin and left
# play alive. The removal itself cannot carry this -- annihilation and escape tear the
# groups down identically, and under the rebalanced (slower) pace the pursuit can
# legally finish the router within a couple of world units of the escape line, so no
# position threshold separates the two outcomes either. Unit.escaped does, exactly.
var _escaped := false


func _on_infantry_escaped() -> void:
	_escaped = true


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
	# The exact matchup and map from demos/inputs/rout-rally-recover.json: a tall flat
	# field with the whole scene staged in the deep south, so the flee lane north is
	# ~1800 wu -- roughly 5x the locally measured flight -- and a slower platform's
	# longer chase still ends in a kill, not an escape (the default 1200-tall field
	# measured an ESCAPE on CI under the rebalanced pace). The translation moves every
	# actor by exactly +1200 INCLUDING the safe spearmen anchor: the cavalry AI's
	# target scoring sees that anchor's relative position, and re-staging it (measured
	# across 8 seeds) flips the arc from a clean chase to an enveloped kill-in-place
	# with no observable pursuit casualties.
	battle.field = Rect2(0, 0, 1600, 2400)
	battle.terrain = []
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 1630, "count": 12, "morale": 1.0},
		{"team": 0, "type": "Spearmen", "x": 300, "y": 1500, "count": 140, "morale": 100.0},
		{"team": 1, "type": "Cavalry", "x": 740, "y": 1700, "count": 12},
		{"team": 1, "type": "Cavalry", "x": 860, "y": 1700, "count": 12},
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
	_escaped = false
	_spawn_rout_rally_battle()
	await get_tree().physics_frame

	assert_not_null(_infantry(), "the low-morale infantry unit spawns")
	if _infantry() == null:
		return
	_infantry().escaped.connect(_on_infantry_escaped)

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
	# It was still routing (never rallied), had taken further casualties since breaking (not
	# merely spawned dead), and never crossed the retreat margin --- annihilated by combat, not
	# escaped. The escape check listens to Unit.escaped rather than thresholding the final
	# position: under the rebalanced pace the chase runs long, and one CI run measured the
	# kill 1.6 wu inside the escape line -- close enough that no position cut separates
	# "caught at the margin's edge" from "got away".
	assert_eq(last_state, Unit.State.ROUTING,
		"still fleeing (never rallied) right up to the moment it's destroyed")
	assert_true(last_soldiers < soldiers_at_rout,
		"took further casualties while routing, run down by the pursuit (started rout at %d, last seen at %d)"
			% [soldiers_at_rout, last_soldiers])
	assert_false(_escaped,
		"annihilated by combat, not escaped past the retreat margin (last y=%.1f)" % last_y)


## The bite proof for the escape discriminator above: drive the one arc the pursuit test
## must never see -- a router that genuinely gets away -- and require Unit.escaped to
## fire. A shattered router never rallies, so with nothing on the field to catch it, its
## flight deterministically crosses the retreat margin.
func test_shattered_router_escapes_and_reports_it() -> void:
	_escaped = false
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true   # the sim must not auto-end when the last router leaves
	battle.terrain = []
	# Spawned near the north field edge so the flight to the margin is short.
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 120, "count": 12},
	]
	_battle = battle
	add_child_autofree(battle)
	await get_tree().physics_frame

	var unit: Unit = _infantry()
	assert_not_null(unit, "the infantry unit spawns")
	if unit == null:
		return
	unit.escaped.connect(_on_infantry_escaped)
	unit._rout()
	unit._shatter()

	var deadline: int = 900   # flight is ~310 wu at flee pace; generous margin
	while _battle.current_tick() < deadline and _infantry() != null:
		await get_tree().physics_frame

	assert_null(_infantry(), "the shattered router left play within the budget")
	assert_true(_escaped,
		"and it reported the escape -- removed by crossing the margin, not by combat")
