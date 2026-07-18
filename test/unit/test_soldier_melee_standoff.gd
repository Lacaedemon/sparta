extends GutTest
## SoldierMeleeStandoff: the sustained reach-asymmetric melee standoff that makes a
## longer-reach weapon's opening-strike advantage hold up once both sides are locked in
## melee, instead of collapsing to a common distance once SoldierEnemyContact and
## Unit._separate()'s reach-independent front-depth floor settle the regiments together.
## These pin: a longer-reach soldier backs away once its shorter-reach foe closes inside its
## reach (scaling with how far closed), a shorter-reach soldier presses in until it closes
## inside its OWN reach, equal reach never biases, the co-located degenerate case doesn't
## crash or NaN, and accumulate() writes the bias additively into both sides' `_sim_steer`.

const SPEAR_REACH: float = 48.0   # 2.4 m * WORLD_UNITS_PER_METER (20) -- a spear's own weapon reach
const SWORD_REACH: float = 26.0   # 1.3 m * WORLD_UNITS_PER_METER (20) -- a sword's own weapon reach


# --- pure standoff_bias() -------------------------------------------------------------

func test_equal_reach_is_always_zero_regardless_of_distance() -> void:
	for d in [0.0, 1.0, 26.0, 48.0, 500.0]:
		var bias: Vector2 = SoldierMeleeStandoff.standoff_bias(
			Vector2.ZERO, Vector2(d, 0.0), SWORD_REACH, SWORD_REACH)
		assert_almost_eq(bias.length(), 0.0, 1e-4, "equal reach never biases, at d=%s" % d)


func test_longer_reach_is_zero_when_enemy_is_at_or_beyond_its_own_reach() -> void:
	# The enemy hasn't even closed inside MY reach yet -- nothing to hold.
	var at_edge: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2.ZERO, Vector2(SPEAR_REACH, 0.0), SPEAR_REACH, SWORD_REACH)
	assert_almost_eq(at_edge.length(), 0.0, 1e-4, "zero right at my own reach edge")
	var beyond: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2.ZERO, Vector2(SPEAR_REACH + 20.0, 0.0), SPEAR_REACH, SWORD_REACH)
	assert_almost_eq(beyond.length(), 0.0, 1e-4, "zero well beyond my own reach")


func test_longer_reach_backs_away_once_the_enemy_has_closed_inside_its_reach() -> void:
	# Sword (enemy) at (40, 0) from a spear (mine) at the origin: 40 < SPEAR_REACH (48), so
	# the spear backs away -- direction should point away from the enemy, i.e. -x here.
	var bias: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2.ZERO, Vector2(40.0, 0.0), SPEAR_REACH, SWORD_REACH)
	assert_lt(bias.x, 0.0, "backs away from the enemy (enemy is at +x, so away is -x)")
	assert_almost_eq(bias.y, 0.0, 1e-4, "no lateral component for a head-on pair")


func test_longer_reach_backing_off_scales_with_how_far_the_enemy_has_closed() -> void:
	# Two distances, both inside the spear's own reach (48) but the second much closer to
	# the sword's own reach (26) -- the closer one should back away harder.
	var shallow: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2.ZERO, Vector2(46.0, 0.0), SPEAR_REACH, SWORD_REACH)   # barely inside my reach
	var deep: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2.ZERO, Vector2(30.0, 0.0), SPEAR_REACH, SWORD_REACH)   # much closer to the enemy's own reach
	assert_gt(deep.length(), shallow.length(),
		"the enemy closer to ITS OWN reach (a real reciprocal threat) backs me off harder")


func test_longer_reach_backing_off_is_full_strength_right_at_the_enemys_own_reach() -> void:
	# Exactly at the sword's own reach edge (26): closed_frac == 1.0 by construction.
	var bias: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2.ZERO, Vector2(SWORD_REACH, 0.0), SPEAR_REACH, SWORD_REACH)
	assert_almost_eq(bias.length(), SoldierMeleeStandoff.STANDOFF_STRENGTH, 0.01,
		"right at the enemy's own reach the bias is exactly full strength (closed_frac == 1)")


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
	var bias: Vector2 = SoldierMeleeStandoff.standoff_bias(
		Vector2(5.0, 5.0), Vector2(5.0, 5.0), SPEAR_REACH, SWORD_REACH)
	assert_false(is_nan(bias.x) or is_nan(bias.y), "a co-located pair must not divide by zero into NaN")
	assert_true(bias.length() < INF, "and must stay finite")


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
	SoldierEnemyProximity.reset()   # frame-keyed static cache -- isolate each test


func test_accumulate_backs_the_spear_off_and_presses_the_sword_in() -> void:
	# Spear at x=0, sword at x=40 -- both biases point toward -x here: the spear backs AWAY
	# from the sword (at +x, so away is -x) while the sword presses TOWARD the spear (at
	# lower x than itself, so toward it is also -x) -- opposite physical intents that happen
	# to share a sign in this particular left-right layout.
	var spear := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	var sword := _melee_unit(2, 1, Vector2(40.0, 0.0), Vector2.UP, SWORD_REACH)
	SoldierMeleeStandoff.accumulate([spear, sword], 1)
	assert_lt(spear._sim_steer[0].x, 0.0, "the spear backs away from the closing sword")
	assert_lt(sword._sim_steer[0].x, 0.0, "the sword presses toward the spear, closing the gap")
	assert_almost_eq(sword._sim_steer[0].length(), SoldierMeleeStandoff.STANDOFF_STRENGTH, 0.01,
		"sanity: pressing in has no ramp, so the sword's bias is full strength")
	assert_lt(spear._sim_steer[0].length(), SoldierMeleeStandoff.STANDOFF_STRENGTH,
		"sanity: backing off ramps with closed_frac, so the spear's bias (40 short of the sword's own 26 reach) is partial")


func test_accumulate_adds_onto_existing_steer_rather_than_overwriting_it() -> void:
	var spear := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	var sword := _melee_unit(2, 1, Vector2(40.0, 0.0), Vector2.UP, SWORD_REACH)
	spear._sim_steer[0] = Vector2(0.0, 7.0)   # pretend SoldierSteering already wrote a bias
	SoldierMeleeStandoff.accumulate([spear, sword], 1)
	assert_almost_eq(spear._sim_steer[0].y, 7.0, 1e-4, "the pre-existing friendly-steering bias survives untouched")
	assert_lt(spear._sim_steer[0].x, 0.0, "the standoff bias composes additively on top of it")


func test_accumulate_is_a_no_op_when_reach_is_equal() -> void:
	var a := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SWORD_REACH)
	var b := _melee_unit(2, 1, Vector2(20.0, 0.0), Vector2.UP, SWORD_REACH)
	SoldierMeleeStandoff.accumulate([a, b], 1)
	assert_almost_eq(a._sim_steer[0].length(), 0.0, 1e-4, "equal reach -- no standoff to hold")
	assert_almost_eq(b._sim_steer[0].length(), 0.0, 1e-4)


func test_accumulate_skips_a_dead_unit() -> void:
	var alive := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	var dead := _melee_unit(2, 1, Vector2(40.0, 0.0), Vector2.UP, SWORD_REACH)
	dead.state = Unit.State.DEAD
	var before: PackedVector2Array = alive._sim_steer.duplicate()
	SoldierMeleeStandoff.accumulate([alive, dead], 1)
	assert_eq(alive._sim_steer, before, "a DEAD unit contributes no enemy soldiers to bias against")


# --- soldier_reach() / attack_range wiring -----------------------------------------------

func test_soldier_reach_reflects_the_unit_type_specific_attack_range() -> void:
	var spear := _melee_unit(1, 0, Vector2.ZERO, Vector2.DOWN, SPEAR_REACH)
	var sword := _melee_unit(2, 1, Vector2(100.0, 0.0), Vector2.UP, SWORD_REACH)
	assert_almost_eq(spear.soldier_reach(), SPEAR_REACH, 0.001)
	assert_almost_eq(sword.soldier_reach(), SWORD_REACH, 0.001)
	assert_gt(spear.soldier_reach(), sword.soldier_reach(), "the spear genuinely outreaches the sword")
