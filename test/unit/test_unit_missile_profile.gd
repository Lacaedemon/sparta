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


# --- the falloff in the damage formula ----------------------------------------------

## Casualties one volley inflicts on a fresh 60-man target `dist` wu straight ahead of a
## shooter carrying `profile`. Reseeds the stream first so every call rolls the same
## volley: the distance and the profile are the only things that differ between calls.
func _volley_kills(profile: int, dist: float) -> int:
	Replay.rng.seed = SEED
	var target := _unit(20 + int(dist), 1, Vector2.ZERO, Vector2.UP, 60)
	target.state = Unit.State.FIGHTING
	target.seed_sim_soldiers()
	var shooter := _unit(10 + int(dist), 0, Vector2(0.0, -dist), Vector2.DOWN, 10)
	shooter.is_ranged = true
	shooter.attack = 40
	target.defense = 0
	assert_true(shooter.equip_missile(profile), "the profile equips")
	UnitCombat.shoot(shooter, target)
	return 60 - target.soldiers


func test_the_same_volley_lands_lighter_at_the_edge_of_a_falloff_profiles_reach() -> void:
	var near: int = _volley_kills(LoadoutRegistry.MISSILE_PILUM, 30.0)
	var far: int = _volley_kills(LoadoutRegistry.MISSILE_PILUM, 285.0)
	assert_gt(near, 0, "the volley at 30 wu kills someone")
	assert_lt(far, near,
		"the identical volley (same roll) kills fewer men at 285 of 300 wu than at 30 wu")


func test_a_profile_without_falloff_lands_the_same_volley_at_any_distance() -> void:
	# The control that proves the test above is reading the falloff and not the geometry:
	# the bow's curve is flat, so distance alone must change nothing.
	var near: int = _volley_kills(LoadoutRegistry.MISSILE_BOW, 30.0)
	var far: int = _volley_kills(LoadoutRegistry.MISSILE_BOW, 150.0)
	assert_gt(near, 0, "the volley kills someone")
	assert_eq(far, near, "with no falloff the same roll kills the same count at 150 wu")


func test_the_shooters_own_damage_factor_scales_the_volley() -> void:
	# Bit-for-bit the pre-profile formula for the default factor; a halved instance factor
	# halves the volley (to within rounding), which the fieldless path exposes as kills.
	var baseline: int = _volley_kills(LoadoutRegistry.MISSILE_BOW, 30.0)
	Replay.rng.seed = SEED
	var target := _unit(90, 1, Vector2.ZERO, Vector2.UP, 60)
	target.state = Unit.State.FIGHTING
	target.seed_sim_soldiers()
	var shooter := _unit(91, 0, Vector2(0.0, -30.0), Vector2.DOWN, 10)
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
