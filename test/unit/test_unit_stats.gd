extends GutTest
## UnitStats: the pure aggregate math behind the HUD's selected-unit stat sheet.
## Everything here is plain arrays in, plain numbers out -- no nodes, no RNG.


func test_mean_sd_positive_of_known_values() -> void:
	# 100 and 80 average to 90; each sits 10 away, so the population sd is exactly 10.
	var out: Vector2 = UnitStats.mean_sd_positive(PackedFloat32Array([100.0, 80.0]))
	assert_almost_eq(out.x, 90.0, 0.001, "mean of the living")
	assert_almost_eq(out.y, 10.0, 0.001, "population sd of the living")


func test_mean_sd_positive_skips_the_fallen() -> void:
	# A soldier can sit at hp <= 0 for the ticks between the wound and the reap;
	# those entries must not drag the living's average down.
	var out: Vector2 = UnitStats.mean_sd_positive(PackedFloat32Array([100.0, 80.0, 0.0, -5.0]))
	assert_almost_eq(out.x, 90.0, 0.001, "zeros and negatives do not count")
	assert_almost_eq(out.y, 10.0, 0.001, "nor do they widen the spread")


func test_mean_sd_positive_of_nothing_alive_is_zero() -> void:
	assert_eq(UnitStats.mean_sd_positive(PackedFloat32Array()), Vector2.ZERO,
			"an empty array has no living mean")
	assert_eq(UnitStats.mean_sd_positive(PackedFloat32Array([0.0, -1.0])), Vector2.ZERO,
			"all-fallen has no living mean either")


func test_mean_sd_positive_of_a_uniform_block_has_zero_spread() -> void:
	var out: Vector2 = UnitStats.mean_sd_positive(PackedFloat32Array([110.0, 110.0, 110.0]))
	assert_almost_eq(out.x, 110.0, 0.001, "uniform mean is the value itself")
	assert_almost_eq(out.y, 0.0, 0.001, "uniform values have zero sd")


func test_mean_body_speed_averages_the_living_magnitudes() -> void:
	# |(3,4)| = 5 and |(0,0)| = 0 average to 2.5 across two living soldiers.
	var vels := PackedVector2Array([Vector2(3, 4), Vector2.ZERO])
	var hp := PackedFloat32Array([1.0, 1.0])
	assert_almost_eq(UnitStats.mean_body_speed(vels, hp), 2.5, 0.001)


func test_mean_body_speed_skips_the_fallen() -> void:
	# The dead soldier's residual velocity must not count toward the block's pace.
	var vels := PackedVector2Array([Vector2(3, 4), Vector2(100, 0)])
	var hp := PackedFloat32Array([1.0, 0.0])
	assert_almost_eq(UnitStats.mean_body_speed(vels, hp), 5.0, 0.001)


func test_mean_body_speed_of_nothing_alive_is_zero() -> void:
	assert_eq(UnitStats.mean_body_speed(PackedVector2Array(), PackedFloat32Array()), 0.0,
			"no bodies, no speed")
	assert_eq(UnitStats.mean_body_speed(
			PackedVector2Array([Vector2(9, 9)]), PackedFloat32Array([0.0])), 0.0,
			"all-fallen reads zero")


func test_mean_body_speed_bounds_to_the_shorter_array() -> void:
	# Index alignment can slip transiently mid-tick; the helper must read only pairs
	# both arrays actually have instead of erroring or inventing entries.
	var vels := PackedVector2Array([Vector2(3, 4), Vector2(6, 8)])
	var hp := PackedFloat32Array([1.0])
	assert_almost_eq(UnitStats.mean_body_speed(vels, hp), 5.0, 0.001,
			"only the first pair exists in both arrays")
