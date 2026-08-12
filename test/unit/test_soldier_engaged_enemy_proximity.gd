extends GutTest
## Unit tests for SoldierEngagedEnemyProximity: the reach-scoped spatial hash
## SoldierMeleeStandoff.accumulate() builds fresh each tick from ONLY the engaged tier (both
## teams), as opposed to SoldierEnemyProximity's whole-battle scan (see that class's own
## test file, test_soldier_enemy_proximity.gd, for the SQUARE-mode has_enemy_within tests).
## rebuild() here takes flat parallel arrays directly (not a list of Unit nodes) since
## SoldierMeleeStandoff.accumulate is the one that gathers the engaged tier and hands the
## flat arrays in -- these tests build those arrays by hand instead of spawning real Units.


func after_each() -> void:
	SoldierEngagedEnemyProximity.reset()


func test_rebuild_is_idempotent_within_a_frame() -> void:
	var pos := PackedVector2Array([Vector2.ZERO])
	var team := PackedInt32Array([0])
	var radius := PackedFloat32Array([4.5])
	var reach := PackedFloat32Array([26.0])
	SoldierEngagedEnemyProximity.rebuild(pos, team, radius, reach, 500)
	assert_true(SoldierEngagedEnemyProximity.is_current(500), "the grid is current for the frame it built")
	assert_false(SoldierEngagedEnemyProximity.is_current(501), "a different frame is not current")


func test_nearest_enemy_returns_the_closer_of_two_in_range_candidates() -> void:
	# Querier at the origin (team 0); two team-1 candidates, both within the querier's own
	# reach (26) plus both radii (4.5 each) = 35 world units -- the closer one should win.
	var pos := PackedVector2Array([Vector2.ZERO, Vector2(30, 0), Vector2(34, 0)])
	var team := PackedInt32Array([0, 1, 1])
	var radius := PackedFloat32Array([4.5, 4.5, 4.5])
	var reach := PackedFloat32Array([26.0, 26.0, 26.0])
	SoldierEngagedEnemyProximity.rebuild(pos, team, radius, reach, 8)
	var enemy: Dictionary = SoldierEngagedEnemyProximity.nearest_enemy(pos[0], 0, radius[0], reach[0])
	assert_almost_eq(enemy["position"].x, 30.0, 0.01, "the closer of two in-range enemy candidates wins")


func test_nearest_enemy_ignores_a_same_team_candidate_even_when_closer() -> void:
	# A same-team candidate sits closest; a real (team-1) enemy is farther but still in range.
	var pos := PackedVector2Array([Vector2.ZERO, Vector2(5, 0), Vector2(30, 0)])
	var team := PackedInt32Array([0, 0, 1])
	var radius := PackedFloat32Array([4.5, 4.5, 4.5])
	var reach := PackedFloat32Array([26.0, 26.0, 26.0])
	SoldierEngagedEnemyProximity.rebuild(pos, team, radius, reach, 9)
	var enemy: Dictionary = SoldierEngagedEnemyProximity.nearest_enemy(pos[0], 0, radius[0], reach[0])
	assert_almost_eq(enemy["position"].x, 30.0, 0.01,
		"a same-team candidate is skipped no matter how close, so the real enemy wins")


func test_nearest_enemy_returns_empty_dict_when_nothing_is_in_range() -> void:
	var pos := PackedVector2Array([Vector2.ZERO, Vector2(500, 0)])   # far outside any reach
	var team := PackedInt32Array([0, 1])
	var radius := PackedFloat32Array([4.5, 4.5])
	var reach := PackedFloat32Array([26.0, 26.0])
	SoldierEngagedEnemyProximity.rebuild(pos, team, radius, reach, 10)
	var enemy: Dictionary = SoldierEngagedEnemyProximity.nearest_enemy(pos[0], 0, radius[0], reach[0])
	assert_true(enemy.is_empty(), "nothing in range -- an empty Dictionary, not a crash")


func test_nearest_enemy_reports_the_candidates_own_reach() -> void:
	# A spear (reach 48) sits 30 units from the querier -- report the SPEAR's own reach back.
	var pos := PackedVector2Array([Vector2.ZERO, Vector2(30, 0)])
	var team := PackedInt32Array([0, 1])
	var radius := PackedFloat32Array([4.5, 4.5])
	var reach := PackedFloat32Array([26.0, 48.0])
	SoldierEngagedEnemyProximity.rebuild(pos, team, radius, reach, 11)
	var enemy: Dictionary = SoldierEngagedEnemyProximity.nearest_enemy(pos[0], 0, radius[0], reach[0])
	assert_almost_eq(float(enemy["reach"]), 48.0, 0.001,
		"the returned reach is the CANDIDATE's own (so a caller can compare both sides' reach)")


func test_nearest_enemy_counts_the_querying_soldiers_own_longer_reach() -> void:
	# Regression: a long-reach querier (a spear, reach 48) must still see a shorter-reach
	# enemy (a sword, reach 26) as a threat when it's beyond the ENEMY's own reach but still
	# within the QUERIER's -- mirrors SoldierEnemyProximity's own equivalent regression test.
	var pos := PackedVector2Array([Vector2.ZERO, Vector2(40, 0)])
	var team := PackedInt32Array([0, 1])
	var radius := PackedFloat32Array([4.5, 4.5])
	var reach := PackedFloat32Array([48.0, 26.0])
	SoldierEngagedEnemyProximity.rebuild(pos, team, radius, reach, 12)
	var enemy: Dictionary = SoldierEngagedEnemyProximity.nearest_enemy(pos[0], 0, radius[0], reach[0])
	assert_false(enemy.is_empty(),
		"the querier's own longer reach must count, not just the candidate enemy's")


func test_reset_clears_the_cached_frame() -> void:
	var pos := PackedVector2Array([Vector2.ZERO])
	var team := PackedInt32Array([0])
	var radius := PackedFloat32Array([4.5])
	var reach := PackedFloat32Array([26.0])
	SoldierEngagedEnemyProximity.rebuild(pos, team, radius, reach, 6)
	SoldierEngagedEnemyProximity.reset()
	assert_false(SoldierEngagedEnemyProximity.is_current(6), "reset forgets the built grid")
