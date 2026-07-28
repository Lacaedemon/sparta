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


func test_accumulate_resolves_contact_for_a_disengaged_but_proximate_pair() -> void:
	# The core fix: accumulate() gathers via Unit.contact_soldier_indices (proximity-gated),
	# not the combat-state-gated engaged_soldier_indices -- a "disengaging" unit's soldiers
	# (a plain move order with no attack target; see Unit._think()'s own disengage comment)
	# still physically resist an enemy's bodies, even though neither unit ever became
	# is_engaged(). Built without _make_unit's FIGHTING/tick_engaged() setup, since that's
	# exactly the combat state this test deliberately withholds.
	var a := Unit.new()
	a.max_soldiers = 20
	add_child_autofree(a)
	a.uid = 1
	a.team = 0
	a.position = Vector2.ZERO
	a.facing = Vector2.DOWN
	a.seed_sim_soldiers()
	a._in_enemy_contact = true
	var b := Unit.new()
	b.max_soldiers = 20
	add_child_autofree(b)
	b.uid = 2
	b.team = 1
	b.position = Vector2.ZERO
	b.facing = Vector2.UP
	b.seed_sim_soldiers()
	b._in_enemy_contact = true
	assert_false(a.is_engaged() or b.is_engaged(), "sanity: neither unit is combat-engaged")
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)   # well within raw body-radius contact
	SoldierEnemyContact.accumulate([a, b], 90200)
	assert_true(a._sim_body_vel[0].length() > 0.0 or b._sim_body_vel[0].length() > 0.0,
		"contact resolves even though neither unit is combat-engaged")


func test_accumulate_fans_apart_an_exactly_co_located_enemy_pair() -> void:
	# Single-soldier units: engaged_soldier_indices' live-position front selection
	# (UnitFormation.live_front_indices) always includes the whole unit when count == 1
	# (target_count >= n is the trivial "return everything" case), so the forced soldier
	# below stays selected regardless of how far the override below moves it from
	# `position` -- a multi-soldier unit would instead need the forced soldier to also be
	# the geometrically most-forward one, which isn't what this test is about.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)   # far apart except for the forced pair below
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)
	# Force one soldier from each side onto the exact same point -- the degenerate
	# (d <= 0.01) branch, which resolves via a stable id-keyed fan-apart angle instead
	# of a normal vector division by a (near-)zero distance.
	a._sim_soldier_pos[0] = Vector2(100, 100)
	b._sim_soldier_pos[0] = Vector2(100, 100)
	SoldierEnemyContact.accumulate([a, b], 90005)
	assert_true(a._sim_body_vel[0].length() > 0.0 or b._sim_body_vel[0].length() > 0.0,
		"a co-located enemy pair still resolves to a nonzero separating impulse")


func test_accumulate_conserves_total_momentum_when_one_body_needs_trimming_and_its_partners_dont() -> void:
	# Regression for the melee-lock swirl: D (a single-soldier defender) is pressed by FIVE
	# attacker soldiers from the same unit, all overlapping the exact same point, so their
	# impulses stack instead of partially canceling -- the same "worst case" geometry as
	# test_accumulate_caps_a_soldiers_summed_velocity_across_multiple_simultaneous_enemies above,
	# just with enough attackers that D's raw summed delta clears its own isolated cap by a wide
	# margin (verified against the pre-fix baseline: this exact setup produced a real 6.7 wu/s
	# residual before this fix). Each attacker only touches D, so every attacker's own raw
	# (single-pair) delta is comfortably under ITS isolated cap and needs no trimming at all.
	#
	# Trimming D's summed delta independently of the attackers' own deltas (the pre-fix approach)
	# leaves the attackers receiving their FULL untrimmed share while D receives only a FRACTION
	# of its matching share -- a residual net force on this cluster with no opposing reaction
	# anywhere in the system, i.e. non-conservation of momentum. All units share the same type
	# (equal mass/brace), so each pair's two impulses are exactly equal and opposite
	# (SoldierCollision.enemy_contact_impulse), making mass-weighted momentum conservation reduce
	# to a plain sum of velocity deltas.
	const ATTACKER_COUNT := 5
	var d := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var attacker := _make_unit(2, 1, Vector2(-2000, -2000), ATTACKER_COUNT)
	d._sim_soldier_pos[0] = Vector2.ZERO
	for i in range(ATTACKER_COUNT):
		attacker._sim_soldier_pos[i] = Vector2(5, 0)
	var before_d: Vector2 = d._sim_body_vel[0]
	var before_attacker: Array = []
	for i in range(ATTACKER_COUNT):
		before_attacker.append(attacker._sim_body_vel[i])

	SoldierEnemyContact.accumulate([d, attacker], 90007)

	var delta_d: Vector2 = d._sim_body_vel[0] - before_d
	assert_true(delta_d.length() > 0.0, "sanity: the forced overlaps actually produced an impulse")
	assert_true(delta_d.length() <= SoldierCombat.KNOCKBACK_SPEED_MAX + 0.01,
		"sanity: D's own summed delta is genuinely being trimmed by this scenario")
	var total: Vector2 = delta_d
	for i in range(ATTACKER_COUNT):
		total += attacker._sim_body_vel[i] - (before_attacker[i] as Vector2)
	assert_almost_eq(total.x, 0.0, 0.05, "trimming a pair must not leave a net x-momentum residual")
	assert_almost_eq(total.y, 0.0, 0.05, "trimming a pair must not leave a net y-momentum residual")


func test_body_trim_scale_is_one_for_a_zero_delta() -> void:
	assert_eq(SoldierEnemyContact.body_trim_scale(Vector2(10, 0), Vector2.ZERO), 1.0,
		"nothing to trim -- the body's velocity is untouched")


func test_body_trim_scale_is_one_when_the_delta_alone_stays_under_the_cap() -> void:
	var scale: float = SoldierEnemyContact.body_trim_scale(Vector2.ZERO, Vector2(1.0, 0.0))
	assert_almost_eq(scale, 1.0, 0.001, "a tiny delta never needs trimming")


func test_body_trim_scale_shrinks_a_delta_that_alone_exceeds_the_cap() -> void:
	# A delta far larger than any realistic cap forces capped_knockback_velocity to clamp hard,
	# so the scale factor must land well below 1.0.
	var scale: float = SoldierEnemyContact.body_trim_scale(
		Vector2.ZERO, Vector2(10.0 * SoldierCombat.KNOCKBACK_SPEED_MAX, 0.0))
	assert_true(scale > 0.0 and scale < 0.2,
		"a wildly oversized delta must be trimmed down close to what the cap alone allows")


# --- formation_containment_margin widens the contact test (melee-intermixing depth) --

func test_shield_wall_containment_margin_triggers_contact_before_raw_radii_overlap() -> void:
	# A pair placed OUTSIDE raw-radius contact (d > sum of body radii) but still inside
	# the shield-wall-class containment margin still resolves to a nonzero impulse --
	# the formation holds the line before the bodies would actually touch.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)
	a.set_formation(Unit.FORMATION_SHIELD_WALL)
	b.set_formation(Unit.FORMATION_SHIELD_WALL)
	var raw: float = a.soldier_body_radius() + b.soldier_body_radius()
	var margin: float = a.formation_containment_margin()
	var d: float = raw + margin   # > raw (not touching by body radius alone), < raw + 2*margin
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(d, 0)
	SoldierEnemyContact.accumulate([a, b], 90101)
	assert_true(a._sim_body_vel[0].length() > 0.0 or b._sim_body_vel[0].length() > 0.0,
		"a shield-wall-class pair not yet touching by raw radius is still pushed apart")


func test_loose_formation_has_no_containment_margin_at_the_same_distance() -> void:
	# Control for the test above: the identical separation with LOOSE formation (zero
	# margin) produces NO impulse, since raw body radii alone don't overlap.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)
	a.set_formation(Unit.FORMATION_LOOSE)
	b.set_formation(Unit.FORMATION_LOOSE)
	var raw: float = a.soldier_body_radius() + b.soldier_body_radius()
	# Reuse a SHIELD_WALL unit's margin just to compute the same test distance -- LOOSE's
	# own margin is zero, which is exactly the behaviour under test.
	var shield_wall_ref := _make_unit(3, 0, Vector2.ZERO, 1)
	shield_wall_ref.set_formation(Unit.FORMATION_SHIELD_WALL)
	var d: float = raw + shield_wall_ref.formation_containment_margin()
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(d, 0)
	SoldierEnemyContact.accumulate([a, b], 90102)
	assert_eq(a._sim_body_vel[0], Vector2.ZERO, "no formation discipline -- no containment push")
	assert_eq(b._sim_body_vel[0], Vector2.ZERO, "no formation discipline -- no containment push")


func test_normal_formation_containment_margin_triggers_contact_before_raw_radii_overlap() -> void:
	# A pair placed OUTSIDE raw-radius contact (d > sum of body radii) but still inside
	# NORMAL's own (smaller-than-shield-wall-class) containment margin still resolves to a
	# nonzero impulse -- "a couple of ranks deep" still means SOME resistance, not none.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)   # default FORMATION_NORMAL
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)  # default FORMATION_NORMAL
	assert_eq(a.formation_mode, Unit.FORMATION_NORMAL, "sanity: default formation is NORMAL")
	var raw: float = a.soldier_body_radius() + b.soldier_body_radius()
	var margin: float = a.formation_containment_margin()
	assert_gt(margin, 0.0, "sanity: NORMAL contributes a nonzero containment margin")
	var d: float = raw + margin   # > raw (not touching by body radius alone), < raw + 2*margin
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(d, 0)
	SoldierEnemyContact.accumulate([a, b], 90103)
	assert_true(a._sim_body_vel[0].length() > 0.0 or b._sim_body_vel[0].length() > 0.0,
		"a NORMAL pair not yet touching by raw radius is still pushed apart, within its margin")


func test_normal_formation_containment_margin_is_flat_regardless_of_prone_state() -> void:
	# Regression guard: NORMAL's margin is a FLAT, unconditional value -- an earlier version
	# gave NORMAL a per-soldier, prone-gated margin instead; that measurably reintroduced the
	# melee-lock-swirl regression on CI (see Unit.formation_containment_margin's doc comment).
	# So the same pair, at the same distance, must resolve identically whether or not the
	# defender happens to be prone.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)   # default FORMATION_NORMAL
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)  # default FORMATION_NORMAL
	var raw: float = a.soldier_body_radius() + b.soldier_body_radius()
	var d: float = raw + a.formation_containment_margin() * 0.5   # inside the margin band
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(d, 0)
	SoldierEnemyContact.accumulate([a, b], 90104)
	var standing_delta: float = a._sim_body_vel[0].length()
	assert_gt(standing_delta, 0.0, "sanity: this distance is inside the margin band")

	a._sim_body_vel[0] = Vector2.ZERO
	b._sim_body_vel[0] = Vector2.ZERO
	b._sim_prone[0] = 1.0
	SoldierEnemyContact.accumulate([a, b], 90105)
	assert_almost_eq(a._sim_body_vel[0].length(), standing_delta, 0.01,
		"a prone NORMAL defender contributes the identical margin -- unaffected by prone state")


func test_normal_formation_pair_well_outside_the_containment_margin_is_unaffected() -> void:
	# Control: a pair placed past raw radius PLUS both margins never triggers contact --
	# NORMAL still allows genuine standoff distance, it's not an unbounded block either.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)
	var raw: float = a.soldier_body_radius() + b.soldier_body_radius()
	var d: float = raw + a.formation_containment_margin() + b.formation_containment_margin() + 0.5
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(d, 0)
	SoldierEnemyContact.accumulate([a, b], 90106)
	assert_eq(a._sim_body_vel[0], Vector2.ZERO,
		"a NORMAL pair past raw radius plus both margins stays out of contact")
	assert_eq(b._sim_body_vel[0], Vector2.ZERO,
		"a NORMAL pair past raw radius plus both margins stays out of contact")


func test_accumulate_caps_a_soldiers_summed_velocity_across_multiple_simultaneous_enemies() -> void:
	# Regression: enemy_contact_impulse's own KNOCKBACK_SPEED_MAX cap is scoped to ONE pair --
	# a soldier touching several enemy bodies at once (e.g. a Square-perimeter defender pressed
	# by more than one attacker from the same side) must not have their individually-capped
	# impulses sum past that cap.
	# Sized to exactly the soldiers this test forces (a: 1, b: 2): engaged_soldier_indices'
	# live-position front selection always includes the whole unit when count <= its engaged
	# budget (the trivial "return everything" case in UnitFormation.live_front_indices), so
	# every forced soldier below stays selected regardless of how far the overrides move them
	# from `position` -- see the co-located-pair test above for the same pattern.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 2)
	# Two of b's soldiers overlap the SAME defender soldier from the SAME direction, so their
	# impulses stack instead of partially canceling -- the worst case for the write-back clamp.
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)
	b._sim_soldier_pos[1] = Vector2(5, 0)
	SoldierEnemyContact.accumulate([a, b], 90006)
	assert_true(a._sim_body_vel[0].length() > 0.0,
		"sanity: the forced overlap actually produced an impulse, not a vacuous pass below")
	assert_true(a._sim_body_vel[0].length() <= SoldierCombat.KNOCKBACK_SPEED_MAX + 0.01,
		"a soldier's summed contact impulse across multiple simultaneous enemies stays capped, not additive")
