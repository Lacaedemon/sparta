extends GutTest
## Unit tests for SoldierEnemyContact.accumulate()'s branch coverage beyond what the
## live-battle regression guard (test_enemy_contact_battle.gd) and enemy_contact_impulse's
## own pure-function tests (test_soldier_collision.gd) already exercise: the array-gathering
## guards (dead/empty/mismatched-array units, too few soldiers to pair, same-team pairs) and
## the co-located degenerate fallback.


func _make_unit(uid: int, team: int, pos: Vector2, count: int = 20) -> Unit:
	var u := Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	# soldier_id() = uid * SOLDIER_ID_STRIDE + index -- a bare Unit.new() defaults to
	# uid -1, so two never-spawned units collide on the same soldier id and the pair
	# canonicalization (sgids[b] <= sgids[a]) silently treats them as already-resolved.
	# Real spawned units always get a unique uid from Battle; give these tests one too.
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = Vector2.DOWN if team == 0 else Vector2.UP
	u.seed_sim_soldiers()
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.0)   # arm the engaged latch
	return u


func test_accumulate_is_a_no_op_with_fewer_than_two_engaged_soldiers() -> void:
	var u := _make_unit(1, 0, Vector2.ZERO)
	var before: PackedVector2Array = u._sim_body_vel.duplicate()
	SoldierEnemyContact.accumulate([u], 90001)
	assert_eq(u._sim_body_vel, before, "a single unit's soldiers can't pair with anything")


func test_accumulate_skips_a_dead_unit() -> void:
	var alive := _make_unit(1, 0, Vector2.ZERO)
	var dead := _make_unit(2, 1, Vector2.ZERO)
	dead.state = Unit.State.DEAD
	var before: PackedVector2Array = alive._sim_body_vel.duplicate()
	SoldierEnemyContact.accumulate([alive, dead], 90002)
	assert_eq(alive._sim_body_vel, before, "a DEAD unit contributes no soldiers to pair against")


func test_accumulate_skips_a_unit_with_mismatched_body_arrays() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var b := _make_unit(2, 1, Vector2.ZERO)
	b._sim_body_vel.resize(0)   # force the size mismatch guard -- pos/vel arrays mid-resize
	var before: PackedVector2Array = a._sim_body_vel.duplicate()
	SoldierEnemyContact.accumulate([a, b], 90003)
	assert_eq(a._sim_body_vel, before,
		"a unit whose body-vel array hasn't caught up to its position array is skipped this tick")


func test_accumulate_skips_a_friendly_pair() -> void:
	var a := _make_unit(1, 0, Vector2.ZERO)
	var b := _make_unit(2, 0, Vector2.ZERO)   # same team, exactly overlapping
	var before_a: PackedVector2Array = a._sim_body_vel.duplicate()
	var before_b: PackedVector2Array = b._sim_body_vel.duplicate()
	SoldierEnemyContact.accumulate([a, b], 90004)
	assert_eq(a._sim_body_vel, before_a, "friendlies don't contact-collide here -- SoldierSteering handles them")
	assert_eq(b._sim_body_vel, before_b, "friendlies don't contact-collide here -- SoldierSteering handles them")


func test_accumulate_fans_apart_an_exactly_co_located_enemy_pair() -> void:
	var a := _make_unit(1, 0, Vector2(2000, 2000))   # far apart except for the forced pair below
	var b := _make_unit(2, 1, Vector2(-2000, -2000))
	# Force one soldier from each side onto the exact same point -- the degenerate
	# (d <= 0.01) branch, which resolves via a stable id-keyed fan-apart angle instead
	# of a normal vector division by a (near-)zero distance.
	a._sim_soldier_pos[0] = Vector2(100, 100)
	b._sim_soldier_pos[0] = Vector2(100, 100)
	SoldierEnemyContact.accumulate([a, b], 90005)
	assert_true(a._sim_body_vel[0].length() > 0.0 or b._sim_body_vel[0].length() > 0.0,
		"a co-located enemy pair still resolves to a nonzero separating impulse")


func test_accumulate_caps_a_soldiers_summed_velocity_across_multiple_simultaneous_enemies() -> void:
	# Regression: enemy_contact_impulse's own KNOCKBACK_SPEED_MAX cap is scoped to ONE pair --
	# a soldier touching several enemy bodies at once (e.g. a Square-perimeter defender pressed
	# by more than one attacker from the same side) must not have their individually-capped
	# impulses sum past that cap.
	var a := _make_unit(1, 0, Vector2(2000, 2000))
	var b := _make_unit(2, 1, Vector2(-2000, -2000))
	# Two of b's soldiers overlap the SAME defender soldier from the SAME direction, so their
	# impulses stack instead of partially canceling -- the worst case for the write-back clamp.
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)
	b._sim_soldier_pos[1] = Vector2(5, 0)
	SoldierEnemyContact.accumulate([a, b], 90006)
	assert_true(a._sim_body_vel[0].length() <= SoldierCombat.KNOCKBACK_SPEED_MAX + 0.01,
		"a soldier's summed contact impulse across multiple simultaneous enemies stays capped, not additive")
