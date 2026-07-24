extends GutTest
## Unit tests for SoldierEncirclementProximity: the reach-scoped spatial hash
## SoldierEncirclement.accumulate() builds fresh each tick from the engaged tier (both teams).
## Distinct from SoldierEngagedEnemyProximity (test_soldier_engaged_enemy_proximity.gd), which
## answers "the NEAREST enemy" -- this class answers "EVERY contacting enemy", since
## SoldierEncirclement needs the full set of contact directions to measure the angular arc
## they span, not just the closest one. rebuild() takes flat parallel arrays directly (not a
## list of Unit nodes), matching SoldierEngagedEnemyProximity's own test-fixture style.


func after_each() -> void:
	SoldierEncirclementProximity.reset()


func test_rebuild_is_idempotent_within_a_frame() -> void:
	var pos := PackedVector2Array([Vector2.ZERO])
	var team := PackedInt32Array([0])
	var radius := PackedFloat32Array([4.5])
	var reach := PackedFloat32Array([26.0])
	SoldierEncirclementProximity.rebuild(pos, team, radius, reach, 500)
	assert_true(SoldierEncirclementProximity.is_current(500), "the grid is current for the frame it built")
	assert_false(SoldierEncirclementProximity.is_current(501), "a different frame is not current")


func test_enemies_within_returns_every_in_range_candidate_not_just_the_nearest() -> void:
	# Querier at the origin (team 0); TWO team-1 candidates, both within the querier's own
	# reach (26) plus both radii (4.5 each) = 35 world units -- unlike a nearest-only query,
	# both must come back.
	var pos := PackedVector2Array([Vector2.ZERO, Vector2(30, 0), Vector2(0, 34)])
	var team := PackedInt32Array([0, 1, 1])
	var radius := PackedFloat32Array([4.5, 4.5, 4.5])
	var reach := PackedFloat32Array([26.0, 26.0, 26.0])
	SoldierEncirclementProximity.rebuild(pos, team, radius, reach, 8)
	var enemies: PackedVector2Array = SoldierEncirclementProximity.enemies_within(pos[0], 0, radius[0], reach[0])
	assert_eq(enemies.size(), 2, "both in-range enemy candidates come back, not just the closer one")


func test_enemies_within_ignores_a_same_team_candidate_even_when_closer() -> void:
	var pos := PackedVector2Array([Vector2.ZERO, Vector2(5, 0), Vector2(30, 0)])
	var team := PackedInt32Array([0, 0, 1])
	var radius := PackedFloat32Array([4.5, 4.5, 4.5])
	var reach := PackedFloat32Array([26.0, 26.0, 26.0])
	SoldierEncirclementProximity.rebuild(pos, team, radius, reach, 9)
	var enemies: PackedVector2Array = SoldierEncirclementProximity.enemies_within(pos[0], 0, radius[0], reach[0])
	assert_eq(enemies.size(), 1, "a same-team candidate is skipped no matter how close")
	assert_almost_eq(enemies[0].x, 30.0, 0.01, "the real enemy is the only one returned")


func test_enemies_within_returns_empty_array_when_nothing_is_in_range() -> void:
	var pos := PackedVector2Array([Vector2.ZERO, Vector2(500, 0)])   # far outside any reach
	var team := PackedInt32Array([0, 1])
	var radius := PackedFloat32Array([4.5, 4.5])
	var reach := PackedFloat32Array([26.0, 26.0])
	SoldierEncirclementProximity.rebuild(pos, team, radius, reach, 10)
	var enemies: PackedVector2Array = SoldierEncirclementProximity.enemies_within(pos[0], 0, radius[0], reach[0])
	assert_true(enemies.is_empty(), "nothing in range -- an empty array, not a crash")


func test_enemies_within_counts_the_querying_soldiers_own_longer_reach() -> void:
	# Regression: a long-reach querier (a spear, reach 48) must still see a shorter-reach
	# enemy (a sword, reach 26) as a threat when it's beyond the ENEMY's own reach but still
	# within the QUERIER's -- mirrors SoldierEngagedEnemyProximity's own equivalent regression.
	var pos := PackedVector2Array([Vector2.ZERO, Vector2(40, 0)])
	var team := PackedInt32Array([0, 1])
	var radius := PackedFloat32Array([4.5, 4.5])
	var reach := PackedFloat32Array([48.0, 26.0])
	SoldierEncirclementProximity.rebuild(pos, team, radius, reach, 12)
	var enemies: PackedVector2Array = SoldierEncirclementProximity.enemies_within(pos[0], 0, radius[0], reach[0])
	assert_false(enemies.is_empty(),
		"the querier's own longer reach must count, not just the candidate enemy's")


func test_enemies_within_reports_the_candidates_own_positions() -> void:
	var pos := PackedVector2Array([Vector2.ZERO, Vector2(0, 30), Vector2(-25, 0)])
	var team := PackedInt32Array([0, 1, 1])
	var radius := PackedFloat32Array([4.5, 4.5, 4.5])
	var reach := PackedFloat32Array([26.0, 26.0, 26.0])
	SoldierEncirclementProximity.rebuild(pos, team, radius, reach, 13)
	var enemies: PackedVector2Array = SoldierEncirclementProximity.enemies_within(pos[0], 0, radius[0], reach[0])
	assert_eq(enemies.size(), 2)
	var xs: Array = [enemies[0].x, enemies[1].x]
	xs.sort()
	assert_almost_eq(xs[0], -25.0, 0.01)
	assert_almost_eq(xs[1], 0.0, 0.01)


func test_reset_clears_the_cached_frame() -> void:
	var pos := PackedVector2Array([Vector2.ZERO])
	var team := PackedInt32Array([0])
	var radius := PackedFloat32Array([4.5])
	var reach := PackedFloat32Array([26.0])
	SoldierEncirclementProximity.rebuild(pos, team, radius, reach, 6)
	SoldierEncirclementProximity.reset()
	assert_false(SoldierEncirclementProximity.is_current(6), "reset forgets the built grid")
