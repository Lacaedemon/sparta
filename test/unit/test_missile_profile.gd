extends GutTest
## The interned missile-profile type (docs/longer-range-missile-design.md, phase 2): its
## metre->world-unit conversion happens once at construction, its range-accuracy falloff is
## a pure linear curve with a 1.0 default that changes nothing, and its launch angle fixes
## the flight time -- a flat throw lands sooner than a lob to the same distance.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")
const TOL: float = 0.000001


func test_make_converts_the_authored_range_once_and_exactly() -> void:
	var p: MissileProfile = MissileProfile.make(999, "Test", 12.5, 1.5, 0.8, 0.6,
			ProjectilePhysics.ANGLE_FLAT)
	assert_eq(p.id, 999, "the profile knows its own id")
	assert_eq(p.display_name, "Test", "and its name")
	assert_eq(p.range_m, 12.5, "the authored metres are kept verbatim")
	assert_eq(p.range_wu, WorldScaleRef.m_to_wu(12.5),
		"range_wu is the same float m_to_wu produces (bit-exact, converted once)")
	assert_eq(p.range_wu, 12.5 * WorldScaleRef.WU_PER_M,
		"and equals the parse-time <metres> * WU_PER_M form the convention authors in")
	assert_eq(p.interval_s, 1.5, "cadence")
	assert_eq(p.damage_factor, 0.8, "damage factor")
	assert_eq(p.accuracy_at_max, 0.6, "accuracy at maximum range")
	assert_eq(p.launch_angle, ProjectilePhysics.ANGLE_FLAT, "launch angle")


# --- the range-accuracy curve -------------------------------------------------------

func test_accuracy_is_full_at_point_blank_and_accuracy_at_max_at_the_range() -> void:
	assert_almost_eq(MissileProfile.accuracy_at(0.0, 300.0, 0.5), 1.0, TOL, "point blank")
	assert_almost_eq(MissileProfile.accuracy_at(300.0, 300.0, 0.5), 0.5, TOL, "at max range")


func test_accuracy_falls_linearly_between_them() -> void:
	assert_almost_eq(MissileProfile.accuracy_at(150.0, 300.0, 0.5), 0.75, TOL, "halfway")
	assert_almost_eq(MissileProfile.accuracy_at(75.0, 300.0, 0.5), 0.875, TOL, "a quarter in")
	assert_almost_eq(MissileProfile.accuracy_at(225.0, 300.0, 0.5), 0.625, TOL, "three quarters")


func test_accuracy_is_monotonically_non_increasing_with_distance() -> void:
	var prev: float = 2.0
	for i in range(0, 41):
		var a: float = MissileProfile.accuracy_at(float(i) * 10.0, 300.0, 0.5)
		assert_true(a <= prev + TOL, "accuracy never rises with distance (sample %d)" % i)
		prev = a


func test_accuracy_holds_at_the_floor_past_maximum_range() -> void:
	assert_almost_eq(MissileProfile.accuracy_at(900.0, 300.0, 0.5), 0.5, TOL,
		"past the range the curve clamps at accuracy_at_max rather than going negative")


func test_accuracy_at_max_of_one_is_exactly_one_everywhere() -> void:
	# The bit-identity an unprofiled unit relies on: 1.0 - (1.0 - 1.0) * f is exactly 1.0.
	for d in [0.0, 1.0, 79.5, 160.0, 500.0]:
		assert_eq(MissileProfile.accuracy_at(d, 160.0, 1.0), 1.0,
			"no falloff means exactly 1.0 at %s wu" % str(d))


func test_non_positive_range_reads_as_point_blank() -> void:
	assert_eq(MissileProfile.accuracy_at(50.0, 0.0, 0.5), 1.0, "zero range has no curve")
	assert_eq(MissileProfile.accuracy_at(50.0, -10.0, 0.5), 1.0, "nor does a negative one")


func test_instance_accuracy_uses_the_profiles_own_range() -> void:
	var p: MissileProfile = LoadoutRegistry.missile(LoadoutRegistry.MISSILE_PILUM)
	assert_almost_eq(p.accuracy(p.range_wu), p.accuracy_at_max, TOL,
		"the instance curve reaches its floor at this type's own range")
	assert_almost_eq(p.accuracy(p.range_wu * 0.5), 0.5 * (1.0 + p.accuracy_at_max), TOL,
		"and is halfway down at half of it")


# --- flight time --------------------------------------------------------------------

func test_a_flat_throw_lands_sooner_than_a_lob_at_the_same_distance() -> void:
	var pilum: MissileProfile = LoadoutRegistry.missile(LoadoutRegistry.MISSILE_PILUM)
	var bow: MissileProfile = LoadoutRegistry.missile(LoadoutRegistry.MISSILE_BOW)
	var dist: float = 160.0
	var t_flat: float = pilum.flight_time(dist, ProjectileField.GRAVITY)
	var t_lob: float = bow.flight_time(dist, ProjectileField.GRAVITY)
	assert_gt(t_flat, 0.0, "a flat throw takes real time")
	assert_lt(t_flat, t_lob, "and lands before a lob to the same spot")


func test_flight_time_matches_the_ballistics_solver_at_the_profiles_angle() -> void:
	var p: MissileProfile = LoadoutRegistry.missile(LoadoutRegistry.MISSILE_BOW)
	var expected: float = ProjectilePhysics.solve_launch(200.0, ProjectileField.GRAVITY,
			p.launch_angle)["flight_time"]
	assert_eq(p.flight_time(200.0, ProjectileField.GRAVITY), expected,
		"the profile's flight time is the solver's, at its own angle")


func test_degenerate_distance_has_zero_flight_time() -> void:
	var p: MissileProfile = LoadoutRegistry.missile(LoadoutRegistry.MISSILE_BOW)
	assert_eq(p.flight_time(0.0, ProjectileField.GRAVITY), 0.0, "same as the solver")
