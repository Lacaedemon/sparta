extends GutTest
## Regression guard: an infantry block that survives a cavalry charge with per-
## soldier melee (no formula wipe, no rout) used to never re-spread to its commanded pitch
## afterward. A knocked-back soldier's arrival target (_corridor_to_slot, SoldierBodies.gd)
## snapped between "go direct" and a full flank-and-rear corridor detour every time its
## distance to its own slot hovered right at the direct-arrival radius -- which a body
## catching up to a MARCHING (not stationary) formation does easily, since the target itself
## keeps drifting. Each flip flung the straggler a formation's-width away right as it was
## about to land, so a handful of front-rank soldiers never rejoined the block for the whole
## clip. See MARCHING_CORRIDOR_PROXIMITY_MULT's own doc comment for the fix.
##
## Stages the same matchup as the website catalog's cycle_charge_flee clip
## (demos/inputs/cycle-charge-flee.json): a 24-horse cycle-charge cavalry against a 70-man,
## morale-2 infantry line. At this seed the infantry survives the opening charge outright (no
## rout), which is what exercises the reform-while-marching path this test guards -- a routed
## unit has no formation to re-spread and is exempt below, matching the demo analyzer's own
## judged_mask() (see .claude/skills/verify-via-state-dump/SKILL.md).

## Ticks to clear the opening charge, its per-soldier melee exchange, and the subsequent
## re-spread while the (still-engaged) infantry tracks/pursues the peeling cavalry. Measured
## empirically on this exact matchup/seed: melee ends by ~t420, and with the fix the settle
## streak completes by ~t1000. Deliberately NOT a generous multiple of that -- the whole
## point of this regression is that the pre-fix block eventually staggers back into spacing
## too (measured ~t1290), just far too slowly, so a loose budget would pass on the broken
## code by simply waiting it out. 1150 sits with real margin over the fixed settle time and
## well under the broken one.
const REFORM_BUDGET: int = 1150
## Once the worst (minimum) pairwise nearest-neighbour distance first reaches the settle
## floor, it must HOLD there for this many consecutive judged ticks before counting as
## "re-spread" -- not just a transient peak on its way back down (the exact oscillation this
## regression produces: a straggler can pass through the correct spacing while the gap is
## still growing, then fall back out of it several times before finally landing).
const SETTLE_STREAK_TICKS: int = 90
## Fraction of the unit's own commanded file pitch the worst pairwise gap must close to
## count as "re-spread". Not 1.0: two adjacent soldiers settle onto their arrival targets
## under bounded acceleration, so the very last sliver of approach is still in flight at any
## single sampled tick even once the block is genuinely done reforming.
const SETTLE_PITCH_FRACTION: float = 0.85


func test_infantry_block_respreads_after_melee_exit() -> void:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.all_teams_control = true   # keep team 1's battle AI from re-ordering the infantry
	battle.terrain = []               # flat field: pathfinding must not shape this arc
	battle.scenario = [
		{"team": 0, "type": "Cavalry", "x": 500, "y": 600, "count": 24},
		{"team": 1, "type": "Infantry", "x": 800, "y": 600, "count": 70, "morale": 2.0},
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

	# The player gesture (arm the J stance, right-click the enemy) reduces to the stance plus
	# the explicit target; _think drives the whole caracole loop from these (matches
	# test_cycle_charge_flee_battle.gd's own setup for the identical matchup).
	cav.order_mode = Unit.ORDER_CYCLE_CHARGE
	cav.target_enemy = inf

	var pitch: float = inf.file_pitch_wu()
	assert_gt(pitch, 0.0, "the infantry has a real commanded formation pitch to re-spread to")
	var settle_floor: float = pitch * SETTLE_PITCH_FRACTION

	var settled_streak: int = 0
	var reached := false
	var ever_in_melee := false
	var ever_judged := false
	var deadline: int = battle.current_tick() + REFORM_BUDGET
	while battle.current_tick() < deadline:
		await get_tree().physics_frame
		if inf.state == Unit.State.ROUTING:
			# A routed block has no formation left to re-spread -- this regression is
			# specifically about a block that SURVIVES the charge and holds. At this seed
			# it does; a rout here would mean the seed/matchup drifted, not that the fix
			# works, so surface that distinctly rather than passing or failing on it.
			pending("infantry routed instead of holding formation -- scenario no longer exercises the reform-while-marching path this test guards")
			return
		if inf.soldiers < 2:
			pending("infantry lost enough soldiers that nearest-neighbour distance is undefined")
			return
		# Mirror the demo analyzer's judged_mask(): don't judge spacing while genuinely in
		# melee or fresh contact -- a pressed formation is SUPPOSED to be compressed then.
		var judged: bool = not inf.is_engaged() and not inf._in_enemy_contact
		if not judged:
			# The regression this test guards against only shows up AFTER melee ends --
			# before the charge lands, an untouched block is trivially at full spacing, so
			# the settle streak must not start counting until a real contact happened.
			ever_in_melee = true
		else:
			ever_judged = true
		if ever_in_melee and judged and _min_nnd(inf) >= settle_floor:
			settled_streak += 1
			if settled_streak >= SETTLE_STREAK_TICKS:
				reached = true
				break
		else:
			settled_streak = 0
	if not ever_in_melee:
		# The cavalry never even landed a melee cadence within the budget -- combat
		# itself never started, so this scenario never got anywhere near the
		# reform-while-marching path this test guards. A DIFFERENT failure than "the
		# block failed to re-spread": surface it distinctly instead of letting the
		# assert below fire with a misleading message.
		assert_true(false,
			"the cavalry never landed a melee cadence against the infantry within %d ticks -- combat never started, so this scenario never exercised the reform-while-marching path" % REFORM_BUDGET)
		return
	if not ever_judged:
		# The cavalry never actually disengaged within the budget (still FIGHTING/in
		# contact at the deadline), so spacing was never once judged -- a real failure,
		# but a DIFFERENT one than "the block failed to re-spread." Surface it as its own
		# distinct signal instead of letting the assert below fail with a misleading
		# "didn't re-spread" message when the true problem is "never got the chance to."
		assert_true(false,
			"infantry (or its attacker) never disengaged within %d ticks -- spacing was never once judged, so this scenario no longer exercises the reform-while-marching path" % REFORM_BUDGET)
		return
	assert_true(reached,
		"infantry block re-spreads to >= %.1f%% of its %.2f wu commanded pitch and holds it for %d straight ticks, within %d ticks of melee start" % [
			SETTLE_PITCH_FRACTION * 100.0, pitch, SETTLE_STREAK_TICKS, REFORM_BUDGET])


## Smallest pairwise distance between any two of `u`'s live soldier bodies -- the same
## "worst offender" metric the issue's own dump used (a block can look reformed on average
## while one straggling pair stays glued together).
func _min_nnd(u: Unit) -> float:
	var n: int = u._sim_soldier_pos.size()
	if n < 2:
		return INF
	var worst: float = INF
	for i in range(n):
		var best: float = INF
		for j in range(n):
			if i == j:
				continue
			var d: float = u._sim_soldier_pos[i].distance_to(u._sim_soldier_pos[j])
			if d < best:
				best = d
		if best < worst:
			worst = best
	return worst
