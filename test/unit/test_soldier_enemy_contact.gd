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


# --- collision damage (SoldierCombat.collision_damage wired into accumulate) ---

func test_accumulate_applies_collision_damage_for_a_fast_closing_pair() -> void:
	# Two single-soldier units, in contact, closing on each other above
	# COLLISION_DAMAGE_MIN_SPEED but not so hard it kills either soldier outright --
	# this test is about damage being applied, not about the reap/death path
	# (see test_accumulate_reaps_a_soldier_killed_by_collision_damage below for that).
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)   # within raw body-radius contact
	var closing: float = SoldierCombat.COLLISION_DAMAGE_MIN_SPEED * 0.7
	a._sim_body_vel[0] = Vector2(closing, 0.0)   # closing on b
	b._sim_body_vel[0] = Vector2(-closing, 0.0)  # closing on a
	var hp_a_before: float = a._sim_soldier_hp[0]
	var hp_b_before: float = b._sim_soldier_hp[0]
	SoldierEnemyContact.accumulate([a, b], 90007)
	assert_lt(a._sim_soldier_hp[0], hp_a_before, "a fast closing impact damages side a")
	assert_lt(b._sim_soldier_hp[0], hp_b_before, "a fast closing impact damages side b")


func test_accumulate_applies_no_collision_damage_below_the_speed_threshold() -> void:
	# Same contact geometry, but both bodies at rest -- the pair is merely interpenetrating
	# (the synthetic overlap-correction term still resolves a velocity impulse), which must
	# cause zero collision damage on its own.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)
	var hp_a_before: float = a._sim_soldier_hp[0]
	var hp_b_before: float = b._sim_soldier_hp[0]
	SoldierEnemyContact.accumulate([a, b], 90008)
	assert_almost_eq(a._sim_soldier_hp[0], hp_a_before, 1e-4,
		"ordinary low-speed contact (overlap correction only) causes no collision damage")
	assert_almost_eq(b._sim_soldier_hp[0], hp_b_before, 1e-4,
		"ordinary low-speed contact (overlap correction only) causes no collision damage")


func test_accumulate_reaps_a_soldier_killed_by_collision_damage() -> void:
	# A soldier already at the brink of death, hit by a hard enough collision, should be
	# reaped (compacted out and counted as a casualty) the same tick -- proving the damage
	# path is wired all the way through to SoldierMelee.reap()/UnitCombat.register_casualties,
	# not just subtracting HP into a vacuum.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 3)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)
	a._sim_soldier_hp[0] = 0.01   # one hard hit away from death
	a._sim_body_vel[0] = Vector2(200.0, 0.0)
	b._sim_body_vel[0] = Vector2(-200.0, 0.0)
	var soldiers_before: int = a.soldiers
	SoldierEnemyContact.accumulate([a, b], 90009)
	assert_lt(a.soldiers, soldiers_before, "the killed soldier is reaped out of the regiment count")


func test_accumulate_caps_a_soldiers_collision_damage_across_multiple_simultaneous_enemies() -> void:
	# Regression: an earlier version of collision damage summed each pair's independently
	# computed damage with no cap, so a soldier touching several fast-closing enemies at once
	# was billed for a "complete stop" once per pair even though it only has one real velocity
	# to lose. Deriving damage from the soldier's ACTUAL, already-capped velocity change (this
	# function's design) bounds total collision damage the same way the velocity pipeline
	# already bounds total knockback -- mirrors
	# test_accumulate_caps_a_soldiers_summed_velocity_across_multiple_simultaneous_enemies above.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 2)
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)
	b._sim_soldier_pos[1] = Vector2(5, 0)
	var closing: float = SoldierCombat.COLLISION_DAMAGE_MIN_SPEED * 2.0
	a._sim_body_vel[0] = Vector2(closing, 0.0)
	b._sim_body_vel[0] = Vector2(-closing, 0.0)
	b._sim_body_vel[1] = Vector2(-closing, 0.0)
	var hp_a_before: float = a._sim_soldier_hp[0]
	SoldierEnemyContact.accumulate([a, b], 90010)
	var damage_a: float = hp_a_before - a._sim_soldier_hp[0]
	var max_possible_damage: float = SoldierCombat.collision_damage(Vector2(SoldierCombat.KNOCKBACK_SPEED_MAX, 0.0))
	assert_true(damage_a <= max_possible_damage + 0.01,
		"total collision damage across simultaneous enemies stays bounded by what a's own capped velocity change could produce, not additive per pair")


func test_accumulate_collision_damage_does_not_recharge_full_ke_every_tick_during_a_multi_tick_arrest() -> void:
	# Regression: an earlier version recomputed the COMPLETE inelastic-stop kinetic energy from
	# the current closing speed every tick, with no memory of prior ticks -- overcounting total
	# damage for a fast pair that takes more than one tick to fully arrest
	# (enemy_contact_impulse's own effective_closing_speed cap is KNOCKBACK_SPEED_MAX per tick).
	# Deriving damage from each tick's ACTUAL velocity change (this function's design) can't
	# overcount this way: every tick only ever charges for the real velocity change that tick,
	# never a hypothetical full stop from the current speed. Verified by comparing the actual
	# two-tick total against what the old, buggy per-tick-full-recompute formula would have
	# produced for the identical sequence.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)
	var closing: float = SoldierCombat.CHARGE_REFERENCE_SPEED   # exceeds KNOCKBACK_SPEED_MAX,
			# so a single tick's contact resolution can't fully arrest it -- takes 2+ ticks.
	a._sim_body_vel[0] = Vector2(closing, 0.0)

	var hp_before_tick1: float = a._sim_soldier_hp[0]
	SoldierEnemyContact.accumulate([a, b], 90011)
	var actual_tick1: float = hp_before_tick1 - a._sim_soldier_hp[0]

	# The real closing speed remaining after tick 1, read from the units' own post-tick state --
	# used both to drive tick 2 and to compute what the old buggy formula would have charged.
	var closing_speed_tick2: float = maxf(0.0, -(a._sim_body_vel[0] - b._sim_body_vel[0]).dot(Vector2(-1.0, 0.0)))
	var hp_before_tick2: float = a._sim_soldier_hp[0]
	SoldierEnemyContact.accumulate([a, b], 90012)
	var actual_tick2: float = hp_before_tick2 - a._sim_soldier_hp[0]
	var actual_total: float = actual_tick1 + actual_tick2

	# The old formula: SCALE * 0.5 * mu * closing_speed^2, recomputed from scratch each tick --
	# mu = 0.5 for these two default-profile (equal, unbraced) units.
	var mu: float = 0.5
	var buggy_tick1: float = SoldierCombat.COLLISION_DAMAGE_SCALE * 0.5 * mu * closing * closing
	var buggy_tick2: float = SoldierCombat.COLLISION_DAMAGE_SCALE * 0.5 * mu * closing_speed_tick2 * closing_speed_tick2
	var buggy_total: float = buggy_tick1 + buggy_tick2

	assert_lt(actual_total, buggy_total,
		"deriving damage from the actual per-tick velocity change avoids the old formula's cross-tick overcounting")


func test_accumulate_no_damage_when_a_soldiers_net_velocity_change_cancels_to_zero() -> void:
	# Covers the actual_delta_v == Vector2.ZERO branch: a soldier flagged damage-eligible (real
	# closing speed against BOTH neighbors individually clears the threshold) whose two contacts
	# push in exactly opposite directions, netting zero actual velocity change -- should take
	# zero damage, since damage derives from the real resulting delta, not from mere eligibility.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 2)
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)    # b's soldier 0 to the right of a
	b._sim_soldier_pos[1] = Vector2(-5, 0)   # b's soldier 1 to the left of a, symmetric
	var closing: float = SoldierCombat.COLLISION_DAMAGE_MIN_SPEED * 2.0
	a._sim_body_vel[0] = Vector2.ZERO
	b._sim_body_vel[0] = Vector2(-closing, 0.0)   # closing on a from the right
	b._sim_body_vel[1] = Vector2(closing, 0.0)    # closing on a from the left, symmetric
	var hp_a_before: float = a._sim_soldier_hp[0]
	SoldierEnemyContact.accumulate([a, b], 90013)
	assert_almost_eq(a._sim_soldier_hp[0], hp_a_before, 1e-3,
		"symmetric opposing contacts cancel a's net velocity change, so it takes no damage even though it was contact-eligible")


func test_accumulate_caps_a_resting_soldier_pressed_by_multiple_fast_closing_enemies() -> void:
	# Regression: the multi-pair cap test above drives its impulses purely from OVERLAP (every
	# body in it starts at rest), so it never exercises enemy_contact_impulse's other input --
	# the real CLOSING-SPEED term. A report that first line-to-line contact briefly shoves
	# bodies past KNOCKBACK_SPEED_MAX blamed exactly that term, on the grounds that the overlap
	# term already targets a steady separating speed instead of re-injecting a full impulse
	# every tick. This pins the closing-speed path under the worst case that report describes:
	# a rank arriving at melee range still carrying full charge speed, with several attackers
	# on the same defender from the same side so their impulses stack rather than cancel.
	#
	# THREE attackers, not two, and the count is load-bearing. Each pair's own
	# effective_closing_speed saturates at KNOCKBACK_SPEED_MAX (60) and splits evenly between
	# the two equal effective masses, so each pair contributes exactly 30 to the defender. Two
	# attackers therefore sum to exactly 60 -- precisely AT the ceiling, where body_trim_scale
	# and the final capped_knockback_velocity clamp both compute a no-op ratio of 1.0, so the
	# assertion below would pass identically with the whole multi-pair capping mechanism
	# deleted and replaced by an unconditional `+=`. Three sum to a raw 90, genuinely over the
	# ceiling, so the trim has to bind for this test to pass.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 3)
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)
	b._sim_soldier_pos[1] = Vector2(5, 0)
	b._sim_soldier_pos[2] = Vector2(5, 0)
	# a stands still, so its own ceiling is exactly KNOCKBACK_SPEED_MAX -- capped_knockback_
	# velocity raises it only for a body that was ALREADY faster (see the test below).
	a._sim_body_vel[0] = Vector2.ZERO
	b._sim_body_vel[0] = Vector2(-SoldierCombat.CHARGE_REFERENCE_SPEED, 0.0)
	b._sim_body_vel[1] = Vector2(-SoldierCombat.CHARGE_REFERENCE_SPEED, 0.0)
	b._sim_body_vel[2] = Vector2(-SoldierCombat.CHARGE_REFERENCE_SPEED, 0.0)
	# Headroom so the collision damage this contact also deals cannot reap a's only soldier
	# mid-test: a capped 60 wu/s delta bills COLLISION_DAMAGE_SCALE * 60^2 = 108 against a
	# default max_health of 110, a ~2 HP margin that a retune of either constant would close --
	# and a reaped soldier would splice the arrays, turning the read below into an
	# out-of-bounds crash rather than a clean failure. This test is about the velocity ceiling,
	# so decouple it from collision-damage tuning entirely.
	a._sim_soldier_hp[0] = 10000.0
	SoldierEnemyContact.accumulate([a, b], 90014)
	assert_true(a._sim_body_vel[0].length() > 0.0,
		"sanity: the forced fast-closing overlap actually produced an impulse, not a vacuous pass below")
	assert_true(a._sim_body_vel[0].length() <= SoldierCombat.KNOCKBACK_SPEED_MAX + 0.01,
		"a resting soldier pressed by several fast-closing enemies at once stays within the knockback ceiling")
	# Pin the exact expected value, not just the ceiling: three pairs at 30 each trim to
	# precisely the cap, so a lower bound here also catches a subtler vacuity than the
	# two-attacker case did -- if some pairs silently stopped resolving (a stale spatial-hash
	# grid, a narrowed contact selection), the surviving impulses would land UNDER the cap and
	# the upper bound alone would still pass. Robust to a retune: the raw sum is always 1.5x
	# whatever the ceiling is, so the trimmed result sits exactly at it.
	assert_true(a._sim_body_vel[0].length() >= SoldierCombat.KNOCKBACK_SPEED_MAX - 0.01,
		"all three contacts actually resolved and the summed impulse reached the ceiling before being trimmed to it")


func test_accumulate_never_accelerates_a_body_already_above_the_knockback_ceiling() -> void:
	# The other half of the same ceiling contract: capped_knockback_velocity bounds a body at
	# max(its own current speed, KNOCKBACK_SPEED_MAX), so a body that arrives already faster
	# than the ceiling (a charge at CHARGE_REFERENCE_SPEED, nearly 3x it) keeps that speed
	# rather than being clamped down to it -- contact may only ever slow it, never drive it
	# faster. Comparing a charging body's raw speed against the flat ceiling therefore reads a
	# violation that isn't one; this per-body relative bound is the actual invariant.
	var a := _make_unit(1, 0, Vector2(2000, 2000), 1)
	var b := _make_unit(2, 1, Vector2(-2000, -2000), 1)
	a._sim_soldier_pos[0] = Vector2.ZERO
	b._sim_soldier_pos[0] = Vector2(5, 0)
	var charge: float = SoldierCombat.CHARGE_REFERENCE_SPEED
	a._sim_body_vel[0] = Vector2(charge, 0.0)
	b._sim_body_vel[0] = Vector2(-charge, 0.0)
	var pre_a: float = a._sim_body_vel[0].length()
	var pre_b: float = b._sim_body_vel[0].length()
	# Same headroom as the test above, and for a sharper reason here: if capped_knockback_
	# velocity ever regressed to a flat cap, a would drop 170 -> 60 in one tick, and that
	# 110 wu/s delta bills COLLISION_DAMAGE_SCALE * 110^2 = 363 against 110 max HP -- reaping
	# the only soldier and splicing the arrays, so the assertions below would die with an
	# out-of-bounds read instead of reporting the ceiling violation they exist to catch.
	# (Verified: without these two lines, that regression fails as a crash, not a message.)
	a._sim_soldier_hp[0] = 10000.0
	b._sim_soldier_hp[0] = 10000.0
	SoldierEnemyContact.accumulate([a, b], 90015)
	assert_true(a._sim_body_vel[0].length() < pre_a,
		"sanity: the head-on contact actually arrested some of a's closing speed, not a vacuous pass below")
	# The LOWER bound is what actually pins max(current, cap) against a flat cap, and it has to
	# be asserted explicitly: with pre_a (170) already above the ceiling, maxf(pre_a, 60)
	# collapses to pre_a, so the upper bounds below reduce to "slower than it arrived" -- which
	# the sanity assertion above already implies. Regress capped_knockback_velocity to an
	# unconditional limit_length(KNOCKBACK_SPEED_MAX) and a would come out at exactly 60
	# instead of 140, satisfying every upper bound here while breaking the documented
	# semantics. Only a lower bound catches that.
	assert_true(a._sim_body_vel[0].length() > SoldierCombat.KNOCKBACK_SPEED_MAX + 0.01,
		"a body that arrived above the ceiling stays above it; a flat cap would clamp it to exactly the ceiling")
	assert_true(a._sim_body_vel[0].length() <= maxf(pre_a, SoldierCombat.KNOCKBACK_SPEED_MAX) + 0.01,
		"a head-on charge contact never leaves the charging body faster than it arrived")
	assert_true(b._sim_body_vel[0].length() > SoldierCombat.KNOCKBACK_SPEED_MAX + 0.01,
		"the same flat-cap regression guard holds for the opposing body in the pair")
	assert_true(b._sim_body_vel[0].length() <= maxf(pre_b, SoldierCombat.KNOCKBACK_SPEED_MAX) + 0.01,
		"the same per-body ceiling holds for the opposing body in the pair")
