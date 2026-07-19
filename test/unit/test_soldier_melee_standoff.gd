extends GutTest
## SoldierMeleeStandoff: the sustained reach-asymmetric melee standoff. These pin: a
## longer-reach soldier NEVER gets a bias (equal-or-longer reach is unconditionally zero --
## the existing landed-strike knockback already does the push-back for that side, see the
## class's own doc comment for why), a shorter-reach soldier presses in at full strength
## until it closes inside its OWN reach, the co-located degenerate case can't crash or NaN,
## accumulate() writes the bias additively into the pressing side's `_sim_steer` only, the
## engaged-tier (not whole-living-battle) candidate scoping, and the query-side pruning that
## skips a unit entirely once its own reach already matches the max reach among ALL of the
## opposing team's engaged units (not just whichever specific enemy happens to be nearest).

const SPEAR_REACH: float = 48.0   # 2.4 m * WORLD_UNITS_PER_METER (20) -- a spear's own weapon reach
const SWORD_REACH: float = 26.0   # 1.3 m * WORLD_UNITS_PER_METER (20) -- a sword's own weapon reach


# --- pure standoff_bias() -------------------------------------------------------------

func test_equal_reach_is_always_zero_regardless_of_distance() -> void:
	for d in [0.0, 1.0, 26.0, 48.0, 500.0]:
		var bias: Vector2 = SoldierMeleeStandoff.standoff_bias(
			Vector2.ZERO, Vector2(d, 0.0), SWORD_REACH, SWORD_REACH)
		assert_almost_eq(bias.length(), 0.0, 1e-4, "equal reach never biases, at d=%s" % d)


func test_longer_reach_is_always_zero_regardless_of_distance() -> void:
	# A soldier that already outreaches its nearest enemy never backs away, no matter how
	# close that enemy has closed -- even fully co-located (d=0). The existing
	# landed-strike knockback is the push-back mechanism for this side; this pass adds
	# nothing on top of it.
	for d in [0.0, 1.0, 26.0, 48.0, 500.0]:
		var bias: Vector2 = SoldierMeleeStandoff.standoff_bias(
			Vector2.ZERO, Vector2(d, 0.0), SPEAR_REACH, SWORD_REACH)
		assert_almost_eq(bias.length(), 0.0, 1e-4, "the longer-reach side never biases, at d=%s" % d)


func test_shorter_reach_presses_in_while_beyond_its_own_reach() -> void:
	# Spear (enemy) at (40, 0) from a sword (mine) at the origin: 40 > SWORD_REACH (26), so
	# the sword presses toward the enemy -- direction should point toward the enemy, +x here.
	var bias: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2.ZERO, Vector2(40.0, 0.0), SWORD_REACH, SPEAR_REACH)
	assert_gt(bias.x, 0.0, "presses toward the enemy (enemy is at +x)")
	assert_almost_eq(bias.length(), SoldierMeleeStandoff.STANDOFF_STRENGTH, 0.01,
		"pressing in is always full strength, no ramp -- the enemy is a threat the whole way")


func test_shorter_reach_is_zero_once_already_within_its_own_reach() -> void:
	var within: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2.ZERO, Vector2(20.0, 0.0), SWORD_REACH, SPEAR_REACH)   # 20 < 26
	assert_almost_eq(within.length(), 0.0, 1e-4, "already close enough to strike back -- no need to press further")
	var at_edge: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2.ZERO, Vector2(SWORD_REACH, 0.0), SWORD_REACH, SPEAR_REACH)
	assert_almost_eq(at_edge.length(), 0.0, 1e-4, "zero right at my own reach edge too")


func test_colocated_pair_does_not_crash_or_nan() -> void:
	# A co-located pair (d=0) can never reach the division inside standoff_bias: d <= my_reach
	# (0 <= any non-negative reach) always returns zero first, on both the equal-or-longer
	# branch (my_reach >= enemy_reach short-circuits before any distance math) and the
	# outreached branch (d=0 <= my_reach is always true). Both directions are covered here.
	var longer: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2(5.0, 5.0), Vector2(5.0, 5.0), SPEAR_REACH, SWORD_REACH)
	assert_false(is_nan(longer.x) or is_nan(longer.y), "longer-reach co-located pair must not NaN")
	assert_almost_eq(longer.length(), 0.0, 1e-4, "and resolves to zero (my_reach >= enemy_reach)")
	var outreached: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2(5.0, 5.0), Vector2(5.0, 5.0), SWORD_REACH, SPEAR_REACH)
	assert_false(is_nan(outreached.x) or is_nan(outreached.y), "outreached co-located pair must not NaN")
	assert_almost_eq(outreached.length(), 0.0, 1e-4, "and resolves to zero (d=0 <= my_reach)")


# --- accumulate() integration -----------------------------------------------------------

func _melee_unit(uid: int, team: int, pos: Vector2, face: Vector2, reach: float) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 1
	add_child_autofree(u)
	u.uid = uid   # bare Unit.new() defaults to uid -1 -- soldier_id() would collide across units
	u.team = team
	u.position = pos
	u.facing = face
	u.attack_range = reach
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)      # latch is_engaged() true
	u.seed_sim_soldiers()    # seed bodies (_sim_soldier_pos/_sim_steer) + full health
	return u


func before_each() -> void:
	SoldierEngagedEnemyProximity.reset()   # frame-keyed static cache -- isolate each test


func test_accumulate_only_presses_the_shorter_reach_side_the_longer_reach_side_never_biases() -> void:
	var spear := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	var sword := _melee_unit(2, 1, Vector2(40.0, 0.0), Vector2.UP, SWORD_REACH)
	SoldierMeleeStandoff.accumulate([spear, sword], 1)
	assert_almost_eq(spear._sim_steer[0].length(), 0.0, 1e-4,
		"the longer-reach spear never biases -- it holds and lets landed-strike knockback do the push-back")
	assert_lt(sword._sim_steer[0].x, 0.0, "the sword presses toward the spear (at lower x), closing the gap")
	assert_almost_eq(sword._sim_steer[0].length(), SoldierMeleeStandoff.STANDOFF_STRENGTH, 0.01,
		"pressing in is always full strength, no ramp")


func test_accumulate_adds_onto_existing_steer_rather_than_overwriting_it() -> void:
	var spear := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	var sword := _melee_unit(2, 1, Vector2(40.0, 0.0), Vector2.UP, SWORD_REACH)
	sword._sim_steer[0] = Vector2(0.0, 7.0)   # pretend SoldierSteering already wrote a bias
	SoldierMeleeStandoff.accumulate([spear, sword], 1)
	assert_almost_eq(sword._sim_steer[0].y, 7.0, 1e-4, "the pre-existing friendly-steering bias survives untouched")
	assert_lt(sword._sim_steer[0].x, 0.0, "the standoff press bias composes additively on top of it")


func test_accumulate_is_a_no_op_when_reach_is_equal() -> void:
	var a := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SWORD_REACH)
	var b := _melee_unit(2, 1, Vector2(20.0, 0.0), Vector2.UP, SWORD_REACH)
	SoldierMeleeStandoff.accumulate([a, b], 1)
	assert_almost_eq(a._sim_steer[0].length(), 0.0, 1e-4, "equal reach -- no standoff to hold")
	assert_almost_eq(b._sim_steer[0].length(), 0.0, 1e-4)


func test_accumulate_skips_a_dead_units_engaged_soldiers_from_the_candidate_pool() -> void:
	# "alive" is the SHORTER-reach side here on purpose: if the dead unit's soldiers were
	# NOT correctly skipped, alive would find the dead spear as a candidate and press toward
	# it (a nonzero bias) -- only the correct skip leaves alive with no candidates at all
	# (zero bias). Using a longer-reach "alive" (whose bias is always zero regardless) would
	# make this assertion pass even with a broken skip, so it has to be the shorter side.
	var alive := _melee_unit(1, 1, Vector2.ZERO, Vector2.UP, SWORD_REACH)
	var dead := _melee_unit(2, 0, Vector2(40.0, 0.0), Vector2.DOWN, SPEAR_REACH)
	dead.state = Unit.State.DEAD
	var before: PackedVector2Array = alive._sim_steer.duplicate()
	SoldierMeleeStandoff.accumulate([alive, dead], 1)
	assert_eq(alive._sim_steer, before, "a DEAD unit contributes no candidates for the shorter-reach side to press toward")


func test_accumulate_is_a_no_op_when_nothing_is_engaged() -> void:
	# Neither unit is FIGHTING/lingering, so neither contributes to pass 1's per-team max
	# reach at all -- accumulate must skip everything (the perf-critical early return)
	# rather than crash on an empty gathered array.
	var a := Unit.new()
	a.max_soldiers = 1
	add_child_autofree(a)
	a.uid = 1
	a.team = 0
	a.attack_range = SPEAR_REACH
	a.seed_sim_soldiers()   # state defaults to IDLE -- never engaged
	var b := Unit.new()
	b.max_soldiers = 1
	add_child_autofree(b)
	b.uid = 2
	b.team = 1
	b.position = Vector2(40.0, 0.0)
	b.attack_range = SWORD_REACH
	b.seed_sim_soldiers()
	var before: PackedVector2Array = a._sim_steer.duplicate()
	SoldierMeleeStandoff.accumulate([a, b], 1)
	assert_eq(a._sim_steer, before, "nothing engaged -- no bias, and no crash from an empty gather")


func test_accumulate_only_considers_the_engaged_tier_not_every_living_soldier() -> void:
	# The spear has two soldiers; only ONE index is flagged engaged (forced directly via the
	# unit's engaged-indices cache, bypassing the real formation-geometry computation, so
	# this test isolates JUST the engaged-tier scoping). Spear soldier 0 (NOT engaged) sits
	# GEOMETRICALLY closer to the sword than spear soldier 1 (engaged) does, but along a
	# DIFFERENT axis -- if the standoff pass still scanned every living soldier (the
	# pre-fix, whole-battle-scan behavior), the sword's nearest-enemy lookup would land on
	# the closer, non-engaged soldier 0 and press along +x; scoped to the engaged tier,
	# soldier 0 is never even a candidate, so the sword presses toward soldier 1 (+y)
	# instead -- distinguishable by DIRECTION, since pressing-in is always full strength
	# regardless of exact distance (no magnitude signal to read).
	var spear := _melee_unit(1, 0, Vector2(1000.0, 1000.0), Vector2.DOWN, SPEAR_REACH)
	spear.max_soldiers = 2
	spear.soldiers = 2   # `soldiers` (not max_soldiers) sizes seed_sim_soldiers' arrays --
	spear.seed_sim_soldiers()   # it's only synced from max_soldiers in _ready(), already past
	spear._sim_soldier_pos[0] = Vector2(28.0, 0.0)   # closer, but NOT engaged
	spear._sim_soldier_pos[1] = Vector2(0.0, 35.0)   # farther, but THIS one is engaged

	var sword := _melee_unit(2, 1, Vector2.ZERO, Vector2.UP, SWORD_REACH)

	var frame: int = Engine.get_physics_frames()
	spear._engaged_indices_cache = PackedInt32Array([1])
	spear._engaged_indices_cache_frame = frame
	spear._engaged_indices_cache_count = 2

	SoldierMeleeStandoff.accumulate([spear, sword], 1)

	assert_almost_eq(sword._sim_steer[0].x, 0.0, 0.05,
		"the sword's bias reflects pairing with the ENGAGED spear soldier at (0, 35), not the closer non-engaged one at (28, 0)")
	assert_gt(sword._sim_steer[0].y, 0.0, "presses toward the engaged spear soldier, along +y")
	assert_almost_eq(sword._sim_steer[0].length(), SoldierMeleeStandoff.STANDOFF_STRENGTH, 0.05)


func test_accumulate_correctly_aggregates_max_reach_across_multiple_units_on_the_same_team() -> void:
	# Regression for the query-side pruning in accumulate()'s pass 1: it must track the
	# MAX reach across every engaged unit of a team, not just whichever one was processed
	# last (a "last write wins" bug would silently drop the max back down whenever a
	# shorter-reach unit of the same team is processed after a longer-reach one). Team 1
	# fields a nearby spear AND a far-away, geometrically-irrelevant sword, in that order --
	# a last-write-wins bug would leave team 1's recorded max at the sword's 26 (processed
	# after the spear's 48), wrongly pruning team 0's sword from ever querying at all, even
	# though the nearby spear is a real, in-range, outreaching enemy.
	var sword_a := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SWORD_REACH)
	var spear_c := _melee_unit(2, 1, Vector2(0.0, 35.0), Vector2.UP, SPEAR_REACH)   # nearby, real threat
	var sword_b := _melee_unit(3, 1, Vector2(9000.0, 9000.0), Vector2.UP, SWORD_REACH)   # far away, irrelevant geometry

	SoldierMeleeStandoff.accumulate([sword_a, spear_c, sword_b], 1)

	assert_almost_eq(sword_a._sim_steer[0].x, 0.0, 0.05,
		"sword_a presses straight toward spear_c (at +y), not sword_b (unreachable, far away)")
	assert_almost_eq(sword_a._sim_steer[0].y, SoldierMeleeStandoff.STANDOFF_STRENGTH, 0.05,
		"sword_a was correctly allowed to query at all -- team 1's max reach (48, from spear_c) " +
		"must survive being processed before the team's own shorter-reach sword_b")


func test_accumulate_still_presses_a_shorter_reach_unit_when_its_own_teams_best_unit_ties_the_enemy() -> void:
	# Regression for pass 1's early-out gate specifically (_any_team_could_be_outreached):
	# it must key off each team's MIN engaged reach, not MAX. Team 0 fields BOTH a spear
	# (48, ties the enemy's own best) AND a sword (26, genuinely outreached) -- team 0's own
	# MAX reach (48) ties team 1's MAX (48), so a MAX-keyed gate would wrongly conclude
	# "nobody could be outreached" and skip the whole pass, silently zeroing team 0's sword's
	# press bias even though it's genuinely outreached by team 1's spear. This is the base
	# game's normal mixed-army composition (a 5v5 battle fields Spearmen/Infantry/Archers/
	# Cavalry per side together), not a rare edge case.
	var spear_0 := _melee_unit(1, 0, Vector2(9000.0, 9000.0), Vector2.DOWN, SPEAR_REACH)   # ties the enemy's max -- far away, geometrically irrelevant
	var sword_0 := _melee_unit(2, 0, Vector2.ZERO, Vector2.DOWN, SWORD_REACH)               # genuinely outreached by spear_1
	var spear_1 := _melee_unit(3, 1, Vector2(0.0, 35.0), Vector2.UP, SPEAR_REACH)           # team 1's only engaged unit

	SoldierMeleeStandoff.accumulate([spear_0, sword_0, spear_1], 1)

	assert_almost_eq(sword_0._sim_steer[0].length(), SoldierMeleeStandoff.STANDOFF_STRENGTH, 0.05,
		"team 0's sword presses toward the enemy spear at full strength -- team 0 fielding a " +
		"48-reach spear elsewhere must not mask its own 26-reach sword from ever being queried")
	assert_gt(sword_0._sim_steer[0].y, 0.0, "presses toward spear_1, along +y")


# --- soldier_reach() / attack_range wiring -----------------------------------------------

func test_soldier_reach_reflects_the_unit_type_specific_attack_range() -> void:
	var spear := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	var sword := _melee_unit(2, 1, Vector2(100.0, 0.0), Vector2.UP, SWORD_REACH)
	assert_almost_eq(spear.soldier_reach(), SPEAR_REACH, 0.001)
	assert_almost_eq(sword.soldier_reach(), SWORD_REACH, 0.001)
	assert_gt(spear.soldier_reach(), sword.soldier_reach(), "the spear genuinely outreaches the sword")


# --- pure give_ground_bias() --------------------------------------------------------------
#
# GIVE_GROUND is an explicit player-facing withdrawal: unlike standoff_bias, it never gates
# on reach comparison at all -- it always backs away from the nearest enemy at a constant
# rate. These tests pin: the direction is always "away from the enemy", the magnitude is
# always full GIVE_GROUND_STRENGTH (no ramp, no "already far enough" cutoff, no "already
# outreach them" zero), and the co-located degenerate case can't crash or NaN.

func test_give_ground_bias_backs_away_regardless_of_reach() -> void:
	# Same three reach pairings standoff_bias treats very differently (outreaching, matching,
	# outreached) -- give_ground_bias must treat all three identically: back straight away
	# from the enemy at full strength every time.
	var cases: Array = [
		["give-ground outreaches the enemy", SPEAR_REACH, SWORD_REACH],
		["give-ground matches the enemy's reach", SWORD_REACH, SWORD_REACH],
		["give-ground is outreached by the enemy", SWORD_REACH, SPEAR_REACH],
	]
	for c in cases:
		# The distance argument to give_ground_bias itself doesn't take a reach parameter --
		# reach is irrelevant to it entirely -- so these are really just direction/magnitude
		# checks; the reach values above document the SCENARIOS this must hold across, even
		# though give_ground_bias's own signature never reads them.
		var bias: Vector2 = SoldierMeleeStandoff.give_ground_bias(Vector2.ZERO, Vector2(30.0, 0.0))
		assert_lt(bias.x, 0.0, "%s: backs away from the enemy (enemy at +x, so bias points -x)" % c[0])
		assert_almost_eq(bias.length(), SoldierMeleeStandoff.GIVE_GROUND_STRENGTH, 0.01,
			"%s: backing away is always full strength, no ramp" % c[0])


func test_give_ground_bias_still_backs_away_even_when_already_far_from_the_enemy() -> void:
	# standoff_bias's press-in branch zeroes out once the soldier has closed inside its own
	# reach ("closing further gains nothing") -- give_ground_bias has no such cutoff: the
	# player ordered a withdrawal, so it keeps backing away regardless of how far apart the
	# pair already is.
	var near: Vector2 = SoldierMeleeStandoff.give_ground_bias(Vector2.ZERO, Vector2(5.0, 0.0))
	var far: Vector2 = SoldierMeleeStandoff.give_ground_bias(Vector2.ZERO, Vector2(500.0, 0.0))
	assert_almost_eq(near.length(), SoldierMeleeStandoff.GIVE_GROUND_STRENGTH, 0.01,
		"backs away at full strength even when the enemy is already close")
	assert_almost_eq(far.length(), SoldierMeleeStandoff.GIVE_GROUND_STRENGTH, 0.01,
		"backs away at full strength even when the enemy is already far away")


func test_give_ground_bias_points_directly_away_from_the_enemy() -> void:
	var bias: Vector2 = SoldierMeleeStandoff.give_ground_bias(Vector2(10.0, 10.0), Vector2(10.0, 40.0))
	# Enemy is due +y from pos, so backing away points -y.
	assert_almost_eq(bias.x, 0.0, 0.01, "no lateral component when the enemy is due +y")
	assert_lt(bias.y, 0.0, "backs away along -y, directly opposite the enemy")


func test_give_ground_bias_colocated_pair_does_not_crash_or_nan() -> void:
	var bias: Vector2 = SoldierMeleeStandoff.give_ground_bias(Vector2(5.0, 5.0), Vector2(5.0, 5.0))
	assert_false(is_nan(bias.x) or is_nan(bias.y), "a co-located pair must not NaN")
	assert_almost_eq(bias.length(), SoldierMeleeStandoff.GIVE_GROUND_STRENGTH, 0.01,
		"falls back to a fixed direction at full strength rather than dividing by zero")


# --- accumulate() integration: GIVE_GROUND overrides standoff_bias, ignores reach --------

func test_accumulate_give_ground_backs_away_even_when_outreaching_the_enemy() -> void:
	# The spear here would NORMALLY get zero bias (standoff_bias's equal-or-longer-reach
	# branch) -- give-ground must override that and back it away anyway.
	var spear := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	spear.order_mode = Unit.ORDER_GIVE_GROUND
	var sword := _melee_unit(2, 1, Vector2(40.0, 0.0), Vector2.UP, SWORD_REACH)
	SoldierMeleeStandoff.accumulate([spear, sword], 1)
	assert_lt(spear._sim_steer[0].x, 0.0,
		"the give-ground spear backs away from the sword (at +x), even though it outreaches it")
	assert_almost_eq(spear._sim_steer[0].length(), SoldierMeleeStandoff.GIVE_GROUND_STRENGTH, 0.01)


func test_accumulate_give_ground_backs_away_when_outreached_instead_of_pressing_in() -> void:
	# The sword here would NORMALLY press toward the spear (standoff_bias's outreached
	# branch) -- give-ground must override that and back away instead, proving the
	# explicit order wins the conflict with the passive press-in bias.
	var spear := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	var sword := _melee_unit(2, 1, Vector2(40.0, 0.0), Vector2.UP, SWORD_REACH)
	sword.order_mode = Unit.ORDER_GIVE_GROUND
	SoldierMeleeStandoff.accumulate([spear, sword], 1)
	# The sword sits at +x from the spear, so backing AWAY from the spear means moving
	# further in +x -- the opposite of standoff_bias's press-in result, which would move
	# the sword toward -x (toward the spear).
	assert_gt(sword._sim_steer[0].x, 0.0,
		"the give-ground sword backs away from the spear (further +x), not toward it")
	assert_almost_eq(sword._sim_steer[0].length(), SoldierMeleeStandoff.GIVE_GROUND_STRENGTH, 0.01,
		"give-ground overrides the passive outreached-press bias entirely, not just dampens it")


func test_accumulate_give_ground_backs_away_at_equal_reach_where_standoff_would_be_zero() -> void:
	# Equal reach is standoff_bias's other always-zero case -- give-ground must still apply.
	var a := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SWORD_REACH)
	a.order_mode = Unit.ORDER_GIVE_GROUND
	var b := _melee_unit(2, 1, Vector2(20.0, 0.0), Vector2.UP, SWORD_REACH)
	SoldierMeleeStandoff.accumulate([a, b], 1)
	assert_lt(a._sim_steer[0].x, 0.0, "give-ground backs away even at equal reach")
	assert_almost_eq(a._sim_steer[0].length(), SoldierMeleeStandoff.GIVE_GROUND_STRENGTH, 0.01)


func test_accumulate_give_ground_adds_onto_existing_steer_rather_than_overwriting_it() -> void:
	var spear := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	spear.order_mode = Unit.ORDER_GIVE_GROUND
	spear._sim_steer[0] = Vector2(0.0, 7.0)   # pretend SoldierSteering already wrote a bias
	var sword := _melee_unit(2, 1, Vector2(40.0, 0.0), Vector2.UP, SWORD_REACH)
	SoldierMeleeStandoff.accumulate([spear, sword], 1)
	assert_almost_eq(spear._sim_steer[0].y, 7.0, 1e-4, "the pre-existing friendly-steering bias survives untouched")
	assert_lt(spear._sim_steer[0].x, 0.0, "the give-ground bias composes additively on top of it")


# --- accumulate() perf gate: a give-ground unit must never be pruned by the reach-based ---
# early-out that's correct for standoff_bias alone (regression for the pass-1/pass-2 gates)

func test_accumulate_give_ground_unit_is_not_skipped_by_the_reach_based_early_out_when_it_outreaches() -> void:
	# Both units have EQUAL reach here (so _any_team_could_be_outreached alone would say
	# "nobody could possibly be outreached" and, before the give-ground fix, the whole pass
	# -- including the give-ground unit's own lookup -- would have been skipped by the pass-1
	# early-out). The give-ground unit's reach is not LESS than the enemy's, so the old
	# per-unit could_be_outreached gate would also have excluded it from pass 2's queriers.
	# Both gates must now fire because a give-ground unit is present.
	var a := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	a.order_mode = Unit.ORDER_GIVE_GROUND
	var b := _melee_unit(2, 1, Vector2(30.0, 0.0), Vector2.UP, SPEAR_REACH)   # equal reach, not outreached
	SoldierMeleeStandoff.accumulate([a, b], 1)
	assert_almost_eq(a._sim_steer[0].length(), SoldierMeleeStandoff.GIVE_GROUND_STRENGTH, 0.01,
		"a give-ground unit with reach equal to its enemy's must still get its bias -- " +
		"the reach-based early-out that's correct for standoff_bias alone must not silently skip it")


func test_accumulate_give_ground_unit_is_not_skipped_when_it_outreaches_every_engaged_enemy() -> void:
	# Stronger version of the above: the give-ground unit has STRICTLY LONGER reach than
	# every opposing engaged unit -- exactly the case _any_team_could_be_outreached is
	# designed to prune for standoff_bias's sake (that unit could never be "outreached").
	# The give-ground fix must override that pruning entirely.
	var spear := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	spear.order_mode = Unit.ORDER_GIVE_GROUND
	var sword := _melee_unit(2, 1, Vector2(20.0, 0.0), Vector2.UP, SWORD_REACH)
	SoldierMeleeStandoff.accumulate([spear, sword], 1)
	assert_almost_eq(spear._sim_steer[0].length(), SoldierMeleeStandoff.GIVE_GROUND_STRENGTH, 0.01,
		"a give-ground unit that outreaches every engaged enemy must still back away -- " +
		"the team-level pass-1 early-out must not skip the whole tick just because nobody " +
		"could be OUTREACHED, when somebody is giving ground")
	assert_lt(spear._sim_steer[0].x, 0.0, "backs away from the sword at +x")
