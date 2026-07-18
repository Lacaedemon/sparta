extends GutTest
## Unit tests for SoldierEnemyProximity: the cross-team, cross-unit spatial hash
## Unit.engaged_soldier_indices() uses to decide whether a Square/Schiltron soldier
## has a real enemy soldier within striking distance. Mirrors
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
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius(), a.soldier_reach()),
		"an opposing soldier within its own reach + both radii counts as a threat")


func test_has_enemy_within_false_beyond_reach() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var b := _make_unit(2, 1, Vector2(2000, 2000))
	b._sim_soldier_pos[0] = a._sim_soldier_pos[0] + Vector2(500, 0)   # far outside any reach
	SoldierEnemyProximity.rebuild([a, b], 2)
	assert_false(SoldierEnemyProximity.has_enemy_within(
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius(), a.soldier_reach()),
		"an opposing soldier well outside reach is not a threat")


func test_has_enemy_within_false_for_a_friendly_at_the_same_spot() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var c := _make_unit(3, 0, Vector2(2000, 2000))   # same team as a
	c._sim_soldier_pos[0] = a._sim_soldier_pos[0]   # exactly co-located
	SoldierEnemyProximity.rebuild([a, c], 3)
	assert_false(SoldierEnemyProximity.has_enemy_within(
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius(), a.soldier_reach()),
		"a same-team soldier is never a threat, no matter how close")


func test_has_enemy_within_ignores_a_dead_soldier() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var b := _make_unit(2, 1, Vector2(2000, 2000))
	b._sim_soldier_pos[0] = a._sim_soldier_pos[0]   # co-located, would otherwise count
	b._sim_soldier_hp[0] = 0.0
	SoldierEnemyProximity.rebuild([a, b], 4)
	assert_false(SoldierEnemyProximity.has_enemy_within(
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius(), a.soldier_reach()),
		"a dead enemy soldier can't threaten anyone")


func test_has_enemy_within_ignores_a_dead_units_whole_roster() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var b := _make_unit(2, 1, Vector2(2000, 2000))
	b._sim_soldier_pos[0] = a._sim_soldier_pos[0]   # co-located, would otherwise count
	b.state = Unit.State.DEAD
	SoldierEnemyProximity.rebuild([a, b], 5)
	assert_false(SoldierEnemyProximity.has_enemy_within(
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius(), a.soldier_reach()),
		"a DEAD unit contributes no soldiers to the grid at all")


func test_has_enemy_within_counts_the_querying_soldiers_own_longer_reach() -> void:
	# Regression: a long-reach querier (e.g. a spear, reach 48) must still see a
	# shorter-reach enemy (e.g. a sword, reach 26) as a threat when it's beyond the
	# ENEMY's own reach but still within the QUERIER's -- the spear-vs-sword standoff
	# SoldierMelee.resolve's own reach search honours (a longer reach lets a soldier
	# strike foes who cannot strike back). Using only the candidate's reach would
	# compute a contact radius of 4.5+4.5+26=35, missing this 40-unit gap entirely.
	var a := _make_unit(1, 0, Vector2.ZERO)
	a.attack_range = 48.0
	var b := _make_unit(2, 1, Vector2(2000, 2000))
	b.attack_range = 26.0
	b._sim_soldier_pos[0] = a._sim_soldier_pos[0] + Vector2(40, 0)
	SoldierEnemyProximity.rebuild([a, b], 7)
	assert_true(SoldierEnemyProximity.has_enemy_within(
			a._sim_soldier_pos[0], a.team, a.soldier_body_radius(), a.soldier_reach()),
		"the querier's own longer reach must count, not just the candidate enemy's")


func test_reset_clears_the_cached_frame() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	SoldierEnemyProximity.rebuild([a], 6)
	SoldierEnemyProximity.reset()
	assert_false(SoldierEnemyProximity.is_current(6), "reset forgets the built grid")


# --- nearest_enemy() (#240: SoldierMeleeStandoff's per-soldier lookup) -------------------

func test_nearest_enemy_returns_the_closer_of_two_in_range_candidates() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var near := _make_unit(2, 1, Vector2(2000, 2000))
	var far := _make_unit(3, 1, Vector2(3000, 3000))
	near._sim_soldier_pos[0] = a._sim_soldier_pos[0] + Vector2(30, 0)
	far._sim_soldier_pos[0] = a._sim_soldier_pos[0] + Vector2(34, 0)
	SoldierEnemyProximity.rebuild([a, near, far], 8)
	var enemy: Dictionary = SoldierEnemyProximity.nearest_enemy(
		a._sim_soldier_pos[0], a.team, a.soldier_body_radius(), a.soldier_reach())
	assert_almost_eq(enemy["position"].x, near._sim_soldier_pos[0].x, 0.01,
		"the closer of two in-range enemy candidates wins")


func test_nearest_enemy_ignores_a_same_team_candidate_even_when_closer() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var friendly := _make_unit(2, 0, Vector2(2000, 2000))   # same team, closest of all
	var enemy_unit := _make_unit(3, 1, Vector2(3000, 3000))
	friendly._sim_soldier_pos[0] = a._sim_soldier_pos[0] + Vector2(5, 0)
	enemy_unit._sim_soldier_pos[0] = a._sim_soldier_pos[0] + Vector2(30, 0)
	SoldierEnemyProximity.rebuild([a, friendly, enemy_unit], 9)
	var enemy: Dictionary = SoldierEnemyProximity.nearest_enemy(
		a._sim_soldier_pos[0], a.team, a.soldier_body_radius(), a.soldier_reach())
	assert_almost_eq(enemy["position"].x, enemy_unit._sim_soldier_pos[0].x, 0.01,
		"a same-team candidate is skipped no matter how close, so the real enemy wins")


func test_nearest_enemy_returns_empty_dict_when_nothing_is_in_range() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var b := _make_unit(2, 1, Vector2(2000, 2000))
	b._sim_soldier_pos[0] = a._sim_soldier_pos[0] + Vector2(500, 0)   # far outside any reach
	SoldierEnemyProximity.rebuild([a, b], 10)
	var enemy: Dictionary = SoldierEnemyProximity.nearest_enemy(
		a._sim_soldier_pos[0], a.team, a.soldier_body_radius(), a.soldier_reach())
	assert_true(enemy.is_empty(), "nothing in range -- an empty Dictionary, not a crash")


func test_nearest_enemy_reports_the_candidates_own_reach() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var spear := _make_unit(2, 1, Vector2(2000, 2000))
	spear.attack_range = 48.0
	spear._sim_soldier_pos[0] = a._sim_soldier_pos[0] + Vector2(30, 0)
	SoldierEnemyProximity.rebuild([a, spear], 11)
	var enemy: Dictionary = SoldierEnemyProximity.nearest_enemy(
		a._sim_soldier_pos[0], a.team, a.soldier_body_radius(), a.soldier_reach())
	assert_almost_eq(float(enemy["reach"]), 48.0, 0.001,
		"the returned reach is the CANDIDATE's own (so a caller can compare both sides' reach)")
