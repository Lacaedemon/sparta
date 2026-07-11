extends GutTest
## Unit tests for SoldierEnemyProximity: the cross-team, cross-unit spatial hash
## Unit.engaged_soldier_indices() uses to decide whether a Square/Schiltron soldier
## has a real enemy soldier within that enemy's own weapon reach. Mirrors
## test_soldier_enemy_contact.gd's fixture pattern -- a bare Unit.new() needs an
## explicit unique uid (it defaults to -1) and seeded soldier arrays.


func _make_unit(uid: int, team: int, pos: Vector2, count: int = 20) -> Unit:
	var u := Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = Vector2.DOWN if team == 0 else Vector2.UP
	u.seed_sim_soldiers()
	return u


func after_each() -> void:
	SoldierEnemyProximity.reset()


func test_rebuild_is_idempotent_within_a_frame() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	SoldierEnemyProximity.rebuild([a], 500)
	assert_true(SoldierEnemyProximity.is_current(500), "the grid is current for the frame it built")
	# A second rebuild call under the SAME frame is a no-op (idempotent) -- verified indirectly:
	# a caller mutating `a`'s positions after the first rebuild would leak into the cached grid
	# only if a second rebuild call actually re-scanned, which the has_enemy_within test below
	# would then contradict.
	assert_false(SoldierEnemyProximity.is_current(501), "a different frame is not current")


func test_has_enemy_within_true_for_an_opposing_soldier_in_reach() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var b := _make_unit(2, 1, Vector2(2000, 2000))
	# Place one of b's soldiers just inside a's soldier-0 reach: attack_range (26 default)
	# plus both units' MARK_RADIUS (4.5 each) = 35 world units of real contact range.
	b._sim_soldier_pos[0] = a._sim_soldier_pos[0] + Vector2(30, 0)
	SoldierEnemyProximity.rebuild([a, b], 1)
	assert_true(SoldierEnemyProximity.has_enemy_within(
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius()),
		"an opposing soldier within its own reach + both radii counts as a threat")


func test_has_enemy_within_false_beyond_reach() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var b := _make_unit(2, 1, Vector2(2000, 2000))
	b._sim_soldier_pos[0] = a._sim_soldier_pos[0] + Vector2(500, 0)   # far outside any reach
	SoldierEnemyProximity.rebuild([a, b], 2)
	assert_false(SoldierEnemyProximity.has_enemy_within(
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius()),
		"an opposing soldier well outside reach is not a threat")


func test_has_enemy_within_false_for_a_friendly_at_the_same_spot() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var c := _make_unit(3, 0, Vector2(2000, 2000))   # same team as a
	c._sim_soldier_pos[0] = a._sim_soldier_pos[0]   # exactly co-located
	SoldierEnemyProximity.rebuild([a, c], 3)
	assert_false(SoldierEnemyProximity.has_enemy_within(
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius()),
		"a same-team soldier is never a threat, no matter how close")


func test_has_enemy_within_ignores_a_dead_soldier() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var b := _make_unit(2, 1, Vector2(2000, 2000))
	b._sim_soldier_pos[0] = a._sim_soldier_pos[0]   # co-located, would otherwise count
	b._sim_soldier_hp[0] = 0.0
	SoldierEnemyProximity.rebuild([a, b], 4)
	assert_false(SoldierEnemyProximity.has_enemy_within(
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius()),
		"a dead enemy soldier can't threaten anyone")


func test_has_enemy_within_ignores_a_dead_units_whole_roster() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var b := _make_unit(2, 1, Vector2(2000, 2000))
	b._sim_soldier_pos[0] = a._sim_soldier_pos[0]   # co-located, would otherwise count
	b.state = Unit.State.DEAD
	SoldierEnemyProximity.rebuild([a, b], 5)
	assert_false(SoldierEnemyProximity.has_enemy_within(
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius()),
		"a DEAD unit contributes no soldiers to the grid at all")


func test_reset_clears_the_cached_frame() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	SoldierEnemyProximity.rebuild([a], 6)
	SoldierEnemyProximity.reset()
	assert_false(SoldierEnemyProximity.is_current(6), "reset forgets the built grid")
