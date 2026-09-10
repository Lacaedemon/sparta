extends GutTest
## A unit shoots with its own missile profile (docs/longer-range-missile-design.md, phase
## 2), not a global constant: an unprofiled unit reproduces today's RANGED_* numbers
## exactly, equipping the bow profile is a no-op, equipping the pilum widens its reach,
## its detection, and its kite distance, the accuracy falloff makes the same volley land
## lighter at range, and the rally radius and rout margin no longer follow the reach.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")
const BattleRef = preload("res://scripts/Battle.gd")
const SEED: int = 1234567
const TOL: float = 0.000001

var _saved_field: ProjectileField = null


func before_each() -> void:
	Replay.rng.seed = SEED
	# A Battle test earlier in the suite can leave its field published; the fieldless path
	# is the one whose casualties land immediately, which is what these tests read.
	_saved_field = ProjectileField.active
	ProjectileField.active = null


func after_each() -> void:
	ProjectileField.active = _saved_field


func _unit(uid: int, team: int, pos: Vector2, face: Vector2 = Vector2.DOWN, n: int = 20) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = face
	return u


# --- defaults and equipping -------------------------------------------------------

func test_an_unprofiled_unit_reproduces_the_pre_profile_constants_exactly() -> void:
	var u := _unit(1, 0, Vector2.ZERO)
	assert_eq(u.missile_range, Unit.RANGED_RANGE, "range")
	assert_eq(u.missile_interval, Unit.RANGED_INTERVAL, "cadence")
	assert_eq(u.missile_damage_factor, Unit.RANGED_DAMAGE_FACTOR, "damage factor")
	assert_eq(u.missile_accuracy_at_max, 1.0, "no falloff")
	assert_eq(u.missile_launch_angle, ProjectilePhysics.ANGLE_ARCED, "lobbed volleys")
	assert_eq(u.skirmish_kite_distance, Unit.SKIRMISH_KITE_DISTANCE, "kite distance")
	assert_eq(u.detection_range, Unit.DETECTION_RANGE, "detection")
	for d in [0.0, 80.0, 160.0]:
		assert_eq(u.missile_accuracy(d), 1.0, "exactly 1.0 at %s wu" % str(d))


func test_the_kite_fraction_reproduces_the_long_standing_kite_distance() -> void:
	assert_almost_eq(Unit.RANGED_RANGE * Unit.SKIRMISH_KITE_FRACTION,
		Unit.SKIRMISH_KITE_DISTANCE, TOL,
		"160 wu * 0.625 is the 100 wu an unprofiled skirmisher always kited at")


func test_equipping_the_bow_profile_changes_nothing() -> void:
	var u := _unit(1, 0, Vector2.ZERO)
	assert_true(u.equip_missile(LoadoutRegistry.MISSILE_BOW), "the bow is a known profile")
	assert_eq(u.missile_type_id, LoadoutRegistry.MISSILE_BOW, "it is now the named type")
	assert_eq(u.missile_range, Unit.RANGED_RANGE, "same range")
	assert_eq(u.missile_interval, Unit.RANGED_INTERVAL, "same cadence")
	assert_eq(u.missile_damage_factor, Unit.RANGED_DAMAGE_FACTOR, "same damage factor")
	assert_eq(u.missile_accuracy_at_max, 1.0, "same (absent) falloff")
	for d in [0.0, 80.0, 160.0]:
		assert_eq(u.missile_accuracy(d), 1.0,
			"accuracy pinned to 1.0 at %s wu" % str(d))
	assert_eq(u.missile_launch_angle, ProjectilePhysics.ANGLE_ARCED, "same lob")
	assert_eq(u.detection_range, Unit.DETECTION_RANGE, "detection untouched")
	assert_almost_eq(u.skirmish_kite_distance, Unit.SKIRMISH_KITE_DISTANCE, TOL,
		"kite distance untouched")


func test_equipping_the_pilum_takes_its_own_range_cadence_and_falloff() -> void:
	var u := _unit(1, 0, Vector2.ZERO)
	var p: MissileProfile = LoadoutRegistry.missile(LoadoutRegistry.MISSILE_PILUM)
	assert_true(u.equip_missile(LoadoutRegistry.MISSILE_PILUM), "the pilum is a known profile")
	assert_eq(u.missile_range, p.range_wu, "the profile's range, not the global one")
	assert_eq(u.missile_range, 15.0 * WorldScaleRef.WU_PER_M, "which is 15 m")
	assert_eq(u.missile_interval, p.interval_s, "its cadence")
	assert_eq(u.missile_damage_factor, p.damage_factor, "its damage factor")
	assert_eq(u.missile_accuracy_at_max, p.accuracy_at_max, "its falloff")
	assert_almost_eq(u.missile_accuracy(0.0), 1.0, TOL,
		"point-blank accuracy pinned to 1.0")
	assert_almost_eq(u.missile_accuracy(p.range_wu * 0.5),
		0.5 * (1.0 + p.accuracy_at_max), TOL,
		"mid-range accuracy scales linearly")
	assert_almost_eq(u.missile_accuracy(p.range_wu), p.accuracy_at_max, TOL,
		"max-range accuracy reaches floor")
	assert_eq(u.missile_launch_angle, ProjectilePhysics.ANGLE_FLAT, "thrown flat")
	assert_almost_eq(u.skirmish_kite_distance, p.range_wu * Unit.SKIRMISH_KITE_FRACTION, TOL,
		"a longer-ranged skirmisher kites proportionally further")


func test_equipping_a_profile_past_the_detection_default_raises_detection_to_it() -> void:
	var u := _unit(1, 0, Vector2.ZERO)
	assert_gt(15.0 * WorldScaleRef.WU_PER_M, Unit.DETECTION_RANGE,
		"precondition: the pilum out-reaches the 190-wu detection default")
	u.equip_missile(LoadoutRegistry.MISSILE_PILUM)
	assert_eq(u.detection_range, u.missile_range,
		"detection is widened to the missile range, so the unit can acquire what it can hit")


func test_equipping_never_narrows_a_wider_detection() -> void:
	var u := _unit(1, 0, Vector2.ZERO)
	u.detection_range = 1000.0
	u.equip_missile(LoadoutRegistry.MISSILE_PILUM)
	assert_eq(u.detection_range, 1000.0, "a scenario that widened detection keeps it")


func test_an_unknown_profile_id_is_refused_and_changes_nothing() -> void:
	var u := _unit(1, 0, Vector2.ZERO)
	assert_false(u.equip_missile(4999), "no such profile")
	assert_false(u.equip_missile(LoadoutRegistry.WEAPON_PILUM),
		"a melee-weapon id is the wrong namespace, not a missile profile")
	assert_eq(u.missile_type_id, LoadoutRegistry.MISSILE_BOW, "type unchanged")
	assert_eq(u.missile_range, Unit.RANGED_RANGE, "range unchanged")
	assert_eq(u.detection_range, Unit.DETECTION_RANGE, "detection unchanged")


# --- acquisition at the profile's range ---------------------------------------------

func test_a_pilum_unit_acquires_a_target_past_the_detection_default() -> void:
	var dist: float = 14.5 * WorldScaleRef.WU_PER_M   # 290 wu: past 190, inside 300
	var shooter := _unit(1, 0, Vector2.ZERO)
	var enemy := _unit(2, 1, Vector2(0.0, dist), Vector2.UP)
	assert_null(UnitTargeting.nearest_enemy(shooter),
		"unprofiled, the enemy at %s wu is beyond the 190-wu detection default" % str(dist))
	shooter.equip_missile(LoadoutRegistry.MISSILE_PILUM)
	assert_eq(UnitTargeting.nearest_enemy(shooter), enemy,
		"with the pilum, the same enemy is inside detection and is acquired")


func test_a_pilum_unit_acquires_a_target_at_exact_maximum_missile_range() -> void:
	var shooter := _unit(3, 0, Vector2.ZERO)
	assert_true(shooter.equip_missile(LoadoutRegistry.MISSILE_PILUM), "pilum equipped")
	var enemy := _unit(4, 1, Vector2(0.0, shooter.missile_range), Vector2.UP)
	assert_eq(UnitTargeting.nearest_enemy(shooter), enemy,
		"a target sitting exactly at the profile's advertised maximum reach is acquired")


func test_equidistant_candidates_preserve_first_match_tie_in_nearest_enemy() -> void:
	var shooter := _unit(5, 0, Vector2.ZERO)
	var first := _unit(6, 1, Vector2(100.0, 0.0), Vector2.LEFT)
	var second := _unit(7, 1, Vector2(-100.0, 0.0), Vector2.RIGHT)
	assert_eq(UnitTargeting.nearest_enemy(shooter), first,
		"equidistant candidates retain first-match tie behavior")


func test_a_pilum_unit_acquires_routing_enemy_at_exact_maximum_missile_range() -> void:
	var shooter := _unit(8, 0, Vector2.ZERO)
	assert_true(shooter.equip_missile(LoadoutRegistry.MISSILE_PILUM), "pilum equipped")
	var router := _unit(9, 1, Vector2(0.0, shooter.missile_range), Vector2.UP)
	router.state = Unit.State.ROUTING
	router.add_to_group("routers")
	assert_eq(UnitTargeting.nearest_routing_enemy(shooter), router,
		"a routing enemy sitting exactly at the profile's advertised reach is acquired")


func test_equidistant_routing_enemies_preserve_first_match_tie() -> void:
	var shooter := _unit(10, 0, Vector2.ZERO)
	assert_true(shooter.equip_missile(LoadoutRegistry.MISSILE_PILUM), "pilum equipped")
	var router1 := _unit(11, 1, Vector2(150.0, 0.0), Vector2.LEFT)
	router1.state = Unit.State.ROUTING
	router1.add_to_group("routers")
	var router2 := _unit(12, 1, Vector2(-150.0, 0.0), Vector2.RIGHT)
	router2.state = Unit.State.ROUTING
	router2.add_to_group("routers")
	assert_eq(UnitTargeting.nearest_routing_enemy(shooter), router1,
		"equidistant routers retain first-match tie behavior")


func test_firing_cadence_distinguishes_pilum_two_second_interval_from_bow_one_second() -> void:
	Replay.rng.seed = SEED
	var target_pilum := _unit(30, 1, Vector2(0.0, 100.0), Vector2.UP, 60)
	target_pilum.seed_sim_soldiers()
	var shooter_pilum := _unit(31, 0, Vector2.ZERO, Vector2.DOWN, 20)
	shooter_pilum.is_ranged = true
	shooter_pilum.attack = 40
	assert_true(shooter_pilum.equip_missile(LoadoutRegistry.MISSILE_PILUM), "pilum equipped")

	var target_bow := _unit(32, 1, Vector2(500.0, 100.0), Vector2.UP, 60)
	target_bow.seed_sim_soldiers()
	var shooter_bow := _unit(33, 0, Vector2(500.0, 0.0), Vector2.DOWN, 20)
	shooter_bow.is_ranged = true
	shooter_bow.attack = 40

	# First volley fires at t=0
	shooter_pilum._think(0.1)
	shooter_bow._think(0.1)
	var pilum_after_first: int = target_pilum.soldiers
	var bow_after_first: int = target_bow.soldiers
	assert_lt(pilum_after_first, 60, "pilum fired first volley")
	assert_lt(bow_after_first, 60, "bow fired first volley")
	assert_almost_eq(shooter_pilum._attack_cd, 2.0, 0.001, "pilum cooldown is 2.0s")
	assert_almost_eq(shooter_bow._attack_cd, 1.0, 0.001, "bow cooldown is 1.0s")

	# Advance 1.1s (11 ticks of 0.1s): bow (1.0s) has cooled down and fires volley 2;
	# pilum (2.0s) has 0.9s remaining and must not fire.
	for _i in range(11):
		shooter_pilum._attack_cd = max(0.0, shooter_pilum._attack_cd - 0.1)
		shooter_bow._attack_cd = max(0.0, shooter_bow._attack_cd - 0.1)
		shooter_pilum._think(0.1)
		shooter_bow._think(0.1)

	assert_lt(target_bow.soldiers, bow_after_first, "bow fired its second volley after 1.0s")
	assert_eq(target_pilum.soldiers, pilum_after_first, "pilum held fire at 1.1s (cooldown still active)")
	assert_almost_eq(shooter_pilum._attack_cd, 0.9, 0.001, "pilum cooldown still has ~0.9s left")

	# Advance another 1.0s (10 ticks of 0.1s, reaching 2.1s total): pilum now fires volley 2.
	for _i in range(10):
		shooter_pilum._attack_cd = max(0.0, shooter_pilum._attack_cd - 0.1)
		shooter_pilum._think(0.1)

	assert_lt(target_pilum.soldiers, pilum_after_first, "pilum fired its second volley after 2.0s")


# --- the falloff in the damage formula ----------------------------------------------

## Casualties one volley inflicts on a fresh 60-man target `dist` wu straight ahead of a
## shooter carrying `profile`. Reseeds the stream first so every call rolls the same
## volley: the distance and the profile are the only things that differ between calls.
## Each call stages in its own column (`column` wu along x): autofreed nodes live until the
## test ends, so a second call at the same origin would put the first call's shooter in the
## new volley's flight path and friendly_interceptor would hand it the whole volley.
func _volley_kills(profile: int, dist: float, column: float,
		uid_offset: int = 0) -> int:
	Replay.rng.seed = SEED
	var target := _unit(20 + int(dist) + uid_offset, 1,
			Vector2(column, 0.0), Vector2.UP, 60)
	target.state = Unit.State.FIGHTING
	target.seed_sim_soldiers()
	var shooter := _unit(10 + int(dist) + uid_offset, 0,
			Vector2(column, -dist), Vector2.DOWN, 10)
	shooter.is_ranged = true
	shooter.attack = 40
	target.defense = 0
	if profile != 0:
		assert_true(shooter.equip_missile(profile), "the profile equips")
	UnitCombat.shoot(shooter, target)
	return 60 - target.soldiers


func test_the_same_volley_lands_lighter_at_the_edge_of_a_falloff_profiles_reach() -> void:
	var near: int = _volley_kills(LoadoutRegistry.MISSILE_PILUM, 30.0, 0.0)
	var far: int = _volley_kills(LoadoutRegistry.MISSILE_PILUM, 285.0, 600.0)
	assert_gt(near, 0, "the volley at 30 wu kills someone")
	assert_gt(far, 0, "and the volley at 285 wu still reaches the target (not zero, not intercepted)")
	assert_lt(far, near,
		"the identical volley (same roll) kills fewer men at 285 of 300 wu than at 30 wu")


func test_a_profile_without_falloff_lands_the_same_volley_at_any_distance() -> void:
	# The control that proves the test above is reading the falloff and not the geometry:
	# the bow's curve is flat, so distance alone must change nothing.
	var near: int = _volley_kills(LoadoutRegistry.MISSILE_BOW, 30.0, 0.0)
	var far: int = _volley_kills(LoadoutRegistry.MISSILE_BOW, 150.0, 600.0)
	assert_gt(near, 0, "the volley kills someone")
	assert_eq(far, near, "with no falloff the same roll kills the same count at 150 wu")
	var unprofiled_near: int = _volley_kills(0, 30.0, 1200.0, 500)
	var unprofiled_far: int = _volley_kills(0, 150.0, 1800.0, 500)
	assert_eq(unprofiled_near, near, "unprofiled unit matches bow near")
	assert_eq(unprofiled_far, far, "unprofiled unit matches bow far")


func test_the_shooters_own_damage_factor_scales_the_volley() -> void:
	# Bit-for-bit the pre-profile formula for the default factor; a halved instance factor
	# halves the volley (to within rounding), which the fieldless path exposes as kills.
	var baseline: int = _volley_kills(LoadoutRegistry.MISSILE_BOW, 30.0, 0.0)
	Replay.rng.seed = SEED
	var target := _unit(90, 1, Vector2(600.0, 0.0), Vector2.UP, 60)   # its own column, as above
	target.state = Unit.State.FIGHTING
	target.seed_sim_soldiers()
	var shooter := _unit(91, 0, Vector2(600.0, -30.0), Vector2.DOWN, 10)
	shooter.is_ranged = true
	shooter.attack = 40
	target.defense = 0
	shooter.missile_damage_factor = Unit.RANGED_DAMAGE_FACTOR * 0.5
	UnitCombat.shoot(shooter, target)
	var halved: int = 60 - target.soldiers
	assert_lt(halved, baseline, "half the damage factor kills fewer men")
	assert_true(absi(halved * 2 - baseline) <= 1,
		"about half of them (%d vs %d), within rounding" % [halved, baseline])


# --- the constants that stopped following the reach ---------------------------------

func test_rally_contact_radius_stays_at_the_pre_profile_reach() -> void:
	assert_eq(Unit.RALLY_CONTACT_RADIUS, 8.0 * WorldScaleRef.WU_PER_M,
		"a router breaks contact at 8 m, whatever profile the nearest enemy carries")
	var u := _unit(1, 0, Vector2.ZERO)
	u.equip_missile(LoadoutRegistry.MISSILE_PILUM)
	assert_lt(Unit.RALLY_CONTACT_RADIUS, u.missile_range,
		"so a pilum unit's reach exceeds it without moving it")


func test_rout_margin_follows_detection_alone() -> void:
	assert_eq(BattleRef.ROUT_MARGIN, Unit.DETECTION_RANGE,
		"the rout margin is the default detection range, not the longest missile reach")


func test_equipped_pilum_volley_launches_with_flat_flight_timing_under_active_field() -> void:
	var field := ProjectileField.new()
	ProjectileField.active = field
	var shooter := _unit(1, 0, Vector2(0, 0), Vector2.DOWN, 10)
	shooter.is_ranged = true
	shooter.attack = 40
	assert_true(shooter.equip_missile(LoadoutRegistry.MISSILE_PILUM), "equips pilum")
	var target := _unit(2, 1, Vector2(0, 200), Vector2.UP, 60)
	target.state = Unit.State.FIGHTING
	target.seed_sim_soldiers()
	UnitCombat.shoot(shooter, target)
	assert_eq(field.count(), 1, "the volley launched one projectile into the active field")
	assert_almost_eq(field._angle[0], ProjectilePhysics.ANGLE_FLAT, TOL,
			"the volley launched at the pilum's flat angle")
	var expected_flat: float = ProjectilePhysics.solve_launch(
			200.0, ProjectileField.GRAVITY, ProjectilePhysics.ANGLE_FLAT)["flight_time"]
	var expected_arced: float = ProjectilePhysics.solve_launch(
			200.0, ProjectileField.GRAVITY, ProjectilePhysics.ANGLE_ARCED)["flight_time"]
	assert_almost_eq(field._flight[0], expected_flat, 0.001,
			"flight time matches the flat solver timing, not the lobbed default")
	assert_true(field._flight[0] < expected_arced,
			"flat volley lands significantly faster than an arced lob")
	ProjectileField.active = null

