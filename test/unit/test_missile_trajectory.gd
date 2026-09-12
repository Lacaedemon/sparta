extends GutTest
## Phase 4 acceptance tests: dynamic trajectory selection, height-aware friendly
## interception, and per-profile gravity (docs/longer-range-missile-design.md, phase 4).

const WorldScaleRef = preload("res://scripts/WorldScale.gd")
const TOL: float = 0.0001


func _unit(uid: int, team: int, pos: Vector2, n: int = 20) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.position = pos
	return u


# --- lower solving angle and height-at-fraction ballistics ---------------------------

func test_lower_solving_angle_monotonic_and_bounded() -> void:
	var max_r: float = 200.0
	assert_almost_eq(ProjectilePhysics.lower_solving_angle(0.0, max_r), 0.0, TOL,
		"zero distance gives zero angle")
	var angle_half: float = ProjectilePhysics.lower_solving_angle(100.0, max_r)
	var expected_half: float = 0.5 * asin(0.5)
	assert_almost_eq(angle_half, expected_half, TOL, "half range gives 0.5 * asin(0.5)")

	var angle_full: float = ProjectilePhysics.lower_solving_angle(200.0, max_r)
	assert_almost_eq(angle_full, PI / 4.0, TOL, "max range gives 45 degrees (PI/4)")

	var angle_over: float = ProjectilePhysics.lower_solving_angle(300.0, max_r)
	assert_almost_eq(angle_over, PI / 4.0, TOL, "over-max distance clamped to 45 degrees")

	# Monotonicity check across sample distances
	var prev_angle: float = -1.0
	for d in [0.0, 40.0, 80.0, 120.0, 160.0, 200.0]:
		var a: float = ProjectilePhysics.lower_solving_angle(d, max_r)
		assert_true(a >= prev_angle, "angle monotonic with distance")
		prev_angle = a

	assert_eq(ProjectilePhysics.lower_solving_angle(0.0, 100.0), 0.0, "zero distance returns zero angle")
	assert_eq(ProjectilePhysics.lower_solving_angle(50.0, 0.0), 0.0, "zero max_range returns zero angle")


func test_height_at_fraction_parabolic_profile() -> void:
	var dist: float = 200.0
	var gravity: float = 90.0
	var angle: float = ProjectilePhysics.ANGLE_ARCED

	assert_almost_eq(ProjectilePhysics.height_at_fraction(dist, gravity, angle, 0.0), 0.0, TOL,
		"height at launch fraction 0 is zero")
	assert_almost_eq(ProjectilePhysics.height_at_fraction(dist, gravity, angle, 1.0), 0.0, TOL,
		"height at landing fraction 1 is zero")
	assert_eq(ProjectilePhysics.height_at_fraction(0.0, gravity, angle, 0.5), 0.0,
		"degenerate zero distance yields zero height")

	var sol: Dictionary = ProjectilePhysics.solve_launch(dist, gravity, angle)
	var peak_h: float = ProjectilePhysics.peak_height(sol["speed"], angle, gravity)
	var mid_h: float = ProjectilePhysics.height_at_fraction(dist, gravity, angle, 0.5)
	assert_almost_eq(mid_h, peak_h, 0.05, "height at fraction 0.5 matches apex peak height")

	# Symmetry: height at f = 0.25 matches height at f = 0.75
	var h_quarter: float = ProjectilePhysics.height_at_fraction(dist, gravity, angle, 0.25)
	var h_three_quarters: float = ProjectilePhysics.height_at_fraction(dist, gravity, angle, 0.75)
	assert_almost_eq(h_quarter, h_three_quarters, TOL,
		"height arc is symmetric around midpoint on level ground")


# --- solve_launch profile bounds ----------------------------------------------------

func test_solve_launch_profile_bounds() -> void:
	# Verify that across all registered profiles, maximum-range launches produce peak heights
	# well below battlefield depth and flight times within historical/practical limits (< 15s).
	var max_field_height_bound: float = 600.0
	var max_flight_time_bound: float = 15.0

	for type_id in [LoadoutRegistry.MISSILE_BOW, LoadoutRegistry.MISSILE_PILUM]:
		var profile: MissileProfile = LoadoutRegistry.missile(type_id)
		assert_not_null(profile, "profile exists in registry")
		var sol: Dictionary = ProjectilePhysics.solve_launch(profile.range_wu, profile.gravity, profile.launch_angle)
		assert_gt(sol["speed"], 0.0, "valid launch speed")
		assert_gt(sol["flight_time"], 0.0, "valid flight time")
		assert_lt(sol["flight_time"], max_flight_time_bound,
			"flight time within bound at max range for profile id %d" % type_id)

		var peak_h: float = ProjectilePhysics.peak_height(sol["speed"], profile.launch_angle, profile.gravity)
		assert_gt(peak_h, 0.0, "positive peak height")
		assert_lt(peak_h, max_field_height_bound,
			"peak height within vertical bound for profile id %d" % type_id)


# --- trajectory angle selection -----------------------------------------------------

func test_volley_angle_selection_flat_inside_fraction_solving_beyond() -> void:
	var shooter := _unit(1, 0, Vector2.ZERO)
	shooter.missile_range = 200.0
	shooter.missile_launch_angle = ProjectilePhysics.ANGLE_ARCED

	var target := _unit(2, 1, Vector2(50, 0))   # dist 50 <= 0.5 * 200 (flat zone)
	var angle_short: float = UnitCombat._volley_angle(shooter, target)
	assert_almost_eq(angle_short, ProjectilePhysics.ANGLE_FLAT, TOL,
		"inside TRAJECTORY_FLAT_FRACTION uses ANGLE_FLAT")

	target.position = Vector2(160, 0)   # dist 160 > 100 (solving zone)
	var angle_long: float = UnitCombat._volley_angle(shooter, target)
	var expected_angle: float = ProjectilePhysics.lower_solving_angle(160.0, 200.0)
	assert_almost_eq(angle_long, expected_angle, TOL,
		"beyond TRAJECTORY_FLAT_FRACTION uses lower solving angle")

	# Flat weapon profile (e.g. pilum) always remains flat regardless of distance
	shooter.equip_missile(LoadoutRegistry.MISSILE_PILUM)
	var angle_pilum: float = UnitCombat._volley_angle(shooter, target)
	assert_almost_eq(angle_pilum, ProjectilePhysics.ANGLE_FLAT, TOL,
		"weapon with flat launch angle stays flat even at long range")

	# Custom launch angle override (e.g. 0.5 rad) is honored directly
	shooter.missile_launch_angle = 0.5
	var angle_custom: float = UnitCombat._volley_angle(shooter, target)
	assert_almost_eq(angle_custom, 0.5, TOL,
		"explicit missile_launch_angle override is honored directly")

	# Degenerate target or distance returns shooter.missile_launch_angle
	shooter.missile_launch_angle = ProjectilePhysics.ANGLE_ARCED
	assert_eq(UnitCombat._volley_angle(shooter, null), ProjectilePhysics.ANGLE_ARCED,
		"null target returns missile_launch_angle")
	var same_pos := _unit(3, 1, Vector2.ZERO)
	assert_eq(UnitCombat._volley_angle(shooter, same_pos), ProjectilePhysics.ANGLE_ARCED,
		"zero distance returns missile_launch_angle")
	shooter.missile_range = 0.0
	assert_eq(UnitCombat._volley_angle(shooter, target), ProjectilePhysics.ANGLE_ARCED,
		"zero range returns missile_launch_angle")


# --- height-aware friendly interception ---------------------------------------------

func test_lobbed_volley_clears_friendly_line_while_flat_intercepts() -> void:
	var shooter := _unit(1, 0, Vector2.ZERO)
	shooter.is_ranged = true
	shooter.missile_range = 300.0

	var blocker := _unit(2, 0, Vector2(100, 0))
	blocker.separation_radius = 18.0

	var enemy := _unit(3, 1, Vector2(250, 0))

	# Lobbed trajectory (ANGLE_ARCED = 55 deg): peak arc is high (~85 wu at x=100),
	# so it easily clears INTERCEPTION_CLEARANCE_HEIGHT (40 wu / 2.0 m).
	var lob_interceptor: Unit = UnitCombat.friendly_interceptor(shooter, enemy, ProjectilePhysics.ANGLE_ARCED)
	assert_null(lob_interceptor,
		"lobbed shot clears friendly line overhead without interception")

	# Flat trajectory (ANGLE_FLAT = 20 deg): height at x=100 is ~21 wu <= 40 wu,
	# so the shot is blocked by the friendly line.
	var flat_interceptor: Unit = UnitCombat.friendly_interceptor(shooter, enemy, ProjectilePhysics.ANGLE_FLAT)
	assert_not_null(flat_interceptor,
		"flat shot at 20 degrees intercepts the friendly unit")
	assert_eq(flat_interceptor, blocker,
		"blocker was correctly identified as the interceptor")


func test_shoot_resolves_overhead_or_intercepts_by_trajectory() -> void:
	var shooter := _unit(1, 0, Vector2.ZERO)
	shooter.is_ranged = true
	shooter.missile_range = 300.0

	var blocker := _unit(2, 0, Vector2(100, 0))
	var enemy := _unit(3, 1, Vector2(250, 0))

	# Case 1: shooter with ANGLE_FLAT launches flat. Blocker intercepts and takes damage;
	# enemy remains untouched.
	shooter.missile_launch_angle = ProjectilePhysics.ANGLE_FLAT
	var enemy_hp_before: int = enemy.soldiers
	var blocker_hp_before: int = blocker.soldiers
	UnitCombat.shoot(shooter, enemy)
	assert_eq(enemy.soldiers, enemy_hp_before, "enemy unharmed when flat shot is intercepted")
	assert_lt(blocker.soldiers, blocker_hp_before, "blocker takes damage from intercepted flat shot")

	# Case 2: shooter with custom clearance or lobbed angle clearing blocker.
	# Clear blocker back to full and let shooter fire with clear overhead.
	blocker.soldiers = blocker.max_soldiers
	shooter.missile_launch_angle = ProjectilePhysics.ANGLE_ARCED
	# At clearance_height = 10.0, even a lower angle clears overhead:
	var interceptor: Unit = UnitCombat.friendly_interceptor(shooter, enemy, ProjectilePhysics.ANGLE_ARCED, 10.0)
	assert_null(interceptor, "clearing height threshold returns null interceptor")


# --- snapshot and persistence -------------------------------------------------------

func test_unit_snapshot_preserves_missile_gravity() -> void:
	var u := _unit(1, 0, Vector2.ZERO)
	u.missile_gravity = 125.0
	var snap: Dictionary = u.to_snapshot_dict()
	assert_true(snap.has("missile_gravity"), "snapshot contains missile_gravity key")
	assert_eq(snap["missile_gravity"], 125.0, "snapshot recorded modified gravity")

	var u2 := _unit(2, 0, Vector2.ZERO)
	u2.apply_snapshot_dict(snap)
	assert_eq(u2.missile_gravity, 125.0, "restore reconstructed missile_gravity")


func test_projectile_field_snapshot_preserves_gravity() -> void:
	var field: ProjectileField = ProjectileField.new()
	field.launch(Vector2.ZERO, Vector2(100, 0), 1, 2, 10, 1.0, ProjectilePhysics.ANGLE_ARCED, 120.0)

	var snap: Dictionary = field.to_snapshot_dict()
	assert_true(snap.has("gravity"), "field snapshot contains gravity parallel array")
	assert_eq(snap["gravity"], [120.0], "field snapshot recorded custom gravity")

	var field2: ProjectileField = ProjectileField.new()
	field2.apply_snapshot_dict(snap)
	assert_almost_eq(field2._gravity[0], 120.0, TOL, "field restored custom gravity")
	assert_almost_eq(field2.height_of(0), field.height_of(0), TOL, "height computation matches")

	# Legacy snapshot without gravity key restores to default GRAVITY
	var legacy_snap: Dictionary = snap.duplicate(true)
	legacy_snap.erase("gravity")
	var field3: ProjectileField = ProjectileField.new()
	field3.apply_snapshot_dict(legacy_snap)
	assert_almost_eq(field3._gravity[0], ProjectileField.GRAVITY, TOL,
		"legacy snapshot without gravity restores to default GRAVITY")
