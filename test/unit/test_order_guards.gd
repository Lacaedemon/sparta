extends GutTest
## Phase 4 of the unified orders-queue design (docs/orders-queue-design.md): OrderGuards'
## bounded, enumerated guard vocabulary. Each guard reads only serialized Unit/sim state
## (position, facing, morale, fatigue, team, state, and the order's own elapsed-tick
## counter) -- no RNG, no wall-clock -- so these are direct node-scene tests (units must
## join the "units" group for the guards that scan it) with no Battle needed.


func _make_unit(uid: int = 1, team: int = 0) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 10
	u.team = team
	add_child_autofree(u)   # _ready() joins the "units" group, seeds soldiers
	u.uid = uid
	return u


# --- ENEMY_IN_RANGE -----------------------------------------------------------

func test_enemy_in_range_true_when_a_living_enemy_is_within_radius() -> void:
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	enemy.position = u.position + Vector2(50, 0)
	assert_true(OrderGuards.enemy_in_range(u, 100.0))


func test_enemy_in_range_false_when_the_only_enemy_is_outside_radius() -> void:
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	enemy.position = u.position + Vector2(500, 0)
	assert_false(OrderGuards.enemy_in_range(u, 100.0))


func test_enemy_in_range_ignores_a_dead_or_routing_enemy() -> void:
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	enemy.position = u.position + Vector2(10, 0)
	enemy.state = Unit.State.DEAD
	assert_false(OrderGuards.enemy_in_range(u, 100.0))


func test_enemy_in_range_falls_back_to_detection_range_when_param_is_non_positive() -> void:
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	enemy.position = u.position + Vector2(Unit.DETECTION_RANGE - 10.0, 0)
	assert_true(OrderGuards.enemy_in_range(u, 0.0))


# --- CONTACT_MADE --------------------------------------------------------------

func test_contact_made_true_when_an_enemy_is_within_melee_contact_distance() -> void:
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	var contact: float = u.attack_range + Unit.RADIUS + enemy.RADIUS
	enemy.position = u.position + Vector2(contact - 1.0, 0)
	assert_true(OrderGuards.contact_made(u))


func test_contact_made_false_when_no_enemy_is_that_close() -> void:
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	enemy.position = u.position + Vector2(1000, 0)
	assert_false(OrderGuards.contact_made(u))


# --- MORALE_BELOW ---------------------------------------------------------------

func test_morale_below_true_once_morale_drops_under_the_threshold() -> void:
	var u := _make_unit()
	u.morale = 10.0
	assert_true(OrderGuards.morale_below(u, 25.0))


func test_morale_below_false_while_morale_is_at_or_above_the_threshold() -> void:
	var u := _make_unit()
	u.morale = 50.0
	assert_false(OrderGuards.morale_below(u, 25.0))


# --- ALLY_EXHAUSTED --------------------------------------------------------------

func test_ally_exhausted_true_once_the_named_allys_fatigue_meets_the_threshold() -> void:
	var u := _make_unit(1, 0)
	var ally := _make_unit(2, 0)
	ally.fatigue = 90.0
	assert_true(OrderGuards.ally_exhausted(u, ally.uid, 80.0))


func test_ally_exhausted_false_while_the_named_allys_fatigue_is_under_the_threshold() -> void:
	var u := _make_unit(1, 0)
	var ally := _make_unit(2, 0)
	ally.fatigue = 20.0
	assert_false(OrderGuards.ally_exhausted(u, ally.uid, 80.0))


func test_ally_exhausted_false_when_no_uid_is_given() -> void:
	var u := _make_unit(1, 0)
	assert_false(OrderGuards.ally_exhausted(u, -1, 80.0))


func test_ally_exhausted_false_when_the_named_ally_cannot_be_resolved() -> void:
	var u := _make_unit(1, 0)
	assert_false(OrderGuards.ally_exhausted(u, 999, 0.0))


# --- TICKS_ELAPSED ---------------------------------------------------------------

func test_ticks_elapsed_false_before_the_count_is_reached() -> void:
	var o := Order.new_move(Vector2.ZERO)
	o._guard_ticks = 5
	assert_false(OrderGuards.ticks_elapsed(o, 10.0))


func test_ticks_elapsed_true_once_the_count_is_reached() -> void:
	var o := Order.new_move(Vector2.ZERO)
	o._guard_ticks = 10
	assert_true(OrderGuards.ticks_elapsed(o, 10.0))


func test_ticks_elapsed_false_for_a_non_positive_parameter() -> void:
	var o := Order.new_move(Vector2.ZERO)
	o._guard_ticks = 100
	assert_false(OrderGuards.ticks_elapsed(o, 0.0))


# --- FLANKED ---------------------------------------------------------------------

func test_flanked_true_when_a_living_enemy_stands_in_the_flank_arc() -> void:
	var u := _make_unit(1, 0)
	u.facing = Vector2.DOWN
	var enemy := _make_unit(2, 1)
	# Directly to the unit's side (perpendicular to facing) -- flank_multiplier > 1.0 there.
	enemy.position = u.position + Vector2(30, 0)
	assert_true(OrderGuards.flanked(u, 100.0))


func test_flanked_false_when_the_only_enemy_is_dead_ahead() -> void:
	var u := _make_unit(1, 0)
	u.facing = Vector2.DOWN
	var enemy := _make_unit(2, 1)
	enemy.position = u.position + Vector2(0, 30)   # straight ahead: frontal, multiplier 1.0
	assert_false(OrderGuards.flanked(u, 100.0))


func test_flanked_false_while_in_the_anti_cavalry_square() -> void:
	var u := _make_unit(1, 0)
	u.facing = Vector2.DOWN
	u.set_formation(Unit.FORMATION_SQUARE)
	var enemy := _make_unit(2, 1)
	enemy.position = u.position + Vector2(30, 0)   # would flank a normal formation
	assert_false(OrderGuards.flanked(u, 100.0), "the square has no exploitable flank")


func test_flanked_false_when_the_flanking_enemy_is_outside_radius() -> void:
	var u := _make_unit(1, 0)
	u.facing = Vector2.DOWN
	var enemy := _make_unit(2, 1)
	enemy.position = u.position + Vector2(500, 0)
	assert_false(OrderGuards.flanked(u, 100.0))


# --- ENGAGED_FRACTION_ABOVE ------------------------------------------------------

## A controllable "N% of the line is engaged" fixture: frontage_override fixes the file
## count directly (rather than relying on the sqrt-based auto width), so
## `engaged_ranks() * files` -- the front-rank cutoff engaged_soldier_indices() selects --
## lands on an exact, predictable fraction of `total`. Pin Tight so a bare Unit's
## attack_range 26.0 / rank_pitch 9.0wu yields engaged_ranks() == 3 (see test_unit.gd's
## test_engaged_ranks_matches_the_old_flat_default_for_a_bare_units_default_reach) --
## `files` is chosen against that fixed depth. Default Normal pyknosis is 18 wu.
func _make_engaged_unit(total: int, files: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = total
	add_child_autofree(u)
	u.soldiers = total
	u.set_formation(Unit.FORMATION_TIGHT)
	u.frontage_override = files
	u.seed_sim_soldiers()
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.0)   # arm the engaged latch so engaged_soldier_indices() isn't empty
	return u


func test_engaged_fraction_above_false_below_the_threshold() -> void:
	# 3 files * 3 engaged ranks = 9 of 100 soldiers engaged (9%), under a 10% threshold.
	var u := _make_engaged_unit(100, 3)
	assert_false(OrderGuards.engaged_fraction_above(u, 0.10))


func test_engaged_fraction_above_true_at_or_above_the_threshold() -> void:
	# 4 files * 3 engaged ranks = 12 of 100 soldiers engaged (12%), over a 10% threshold.
	var u := _make_engaged_unit(100, 4)
	assert_true(OrderGuards.engaged_fraction_above(u, 0.10))


func test_engaged_fraction_above_false_when_the_unit_is_not_engaged_at_all() -> void:
	# is_engaged() (the whole-regiment binary latch) gates engaged_soldier_indices() --
	# a unit that was never fighting reads as 0% engaged regardless of its formation.
	var u: Unit = Unit.new()
	u.max_soldiers = 100
	add_child_autofree(u)
	u.soldiers = 100
	u.frontage_override = 4
	u.seed_sim_soldiers()
	assert_false(OrderGuards.engaged_fraction_above(u, 0.10))


func test_engaged_fraction_above_false_with_no_living_soldiers() -> void:
	var u := _make_unit()
	u.soldiers = 0
	assert_false(OrderGuards.engaged_fraction_above(u, 0.10))


func test_current_engaged_fraction_returns_the_raw_ratio() -> void:
	# 4 files * 3 engaged ranks = 12 of 100 soldiers engaged -- 0.12, not just "above 0.10".
	var u := _make_engaged_unit(100, 4)
	assert_almost_eq(OrderGuards.current_engaged_fraction(u), 0.12, 0.001)


func test_current_engaged_fraction_zero_when_not_engaged() -> void:
	var u := _make_unit()
	u.soldiers = 10
	assert_eq(OrderGuards.current_engaged_fraction(u), 0.0)


func test_current_engaged_fraction_measures_real_per_soldier_contact_with_enemy_unit() -> void:
	# Unit u (40 spearmen) facing down at (500, 300)
	var u: Unit = Unit.new()
	u.uid = 1
	u.team = 0
	u.max_soldiers = 40
	add_child_autofree(u)
	u.soldiers = 40
	u.position = Vector2(500, 300)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.0)

	# Enemy unit placed directly facing u in close melee contact, derived from combat reach and body radii
	var enemy: Unit = Unit.new()
	enemy.uid = 2
	enemy.team = 1
	enemy.max_soldiers = 40
	add_child_autofree(enemy)
	enemy.soldiers = 40
	var contact_reach: float = u.soldier_body_radius() + enemy.soldier_body_radius() + maxf(u.soldier_reach(), enemy.soldier_reach())
	enemy.position = u.position + Vector2(0, contact_reach * 0.8)
	enemy.facing = Vector2.UP
	enemy.seed_sim_soldiers()
	enemy.state = Unit.State.FIGHTING
	enemy.tick_engaged(0.0)

	# With opposing front ranks in contact, a significant fraction is engaged (>= 10%)
	var frac: float = OrderGuards.current_engaged_fraction(u)
	assert_true(frac >= 0.10, "front rank contact engages a substantial fraction of the unit")
	assert_true(OrderGuards.engaged_fraction_above(u, 0.10))


func test_current_engaged_fraction_low_on_light_flank_graze() -> void:
	# Unit u (100 soldiers) at (500, 300), 10 files wide
	var u: Unit = Unit.new()
	u.uid = 1
	u.team = 0
	u.max_soldiers = 100
	add_child_autofree(u)
	u.soldiers = 100
	u.frontage_override = 10
	u.position = Vector2(500, 300)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.0)

	# A small 2-soldier enemy placed at the far right corner of u's line
	var enemy: Unit = Unit.new()
	enemy.uid = 2
	enemy.team = 1
	enemy.max_soldiers = 2
	add_child_autofree(enemy)
	enemy.soldiers = 2
	# Place enemy near the rightmost front-rank soldier of u, derived from combat reach and body radii
	var contact_reach: float = u.soldier_body_radius() + enemy.soldier_body_radius() + maxf(u.soldier_reach(), enemy.soldier_reach())
	var right_idx: int = mini(u.formation_front_files() - 1, u._sim_soldier_pos.size() - 1)
	var right_soldier_pos: Vector2 = u._sim_soldier_pos[right_idx]
	enemy.position = right_soldier_pos + Vector2(0, contact_reach * 0.7)
	enemy.facing = Vector2.UP
	enemy.seed_sim_soldiers()
	if not enemy._sim_soldier_pos.is_empty():
		enemy._sim_soldier_pos[0] = right_soldier_pos + Vector2(0, contact_reach * 0.5)
	enemy.state = Unit.State.FIGHTING
	enemy.tick_engaged(0.0)

	# Only 1-2 soldiers of u are within reach of the small enemy (< 5% of 100 soldiers)
	var frac: float = OrderGuards.current_engaged_fraction(u)
	assert_true(frac > 0.0, "flank graze detects real soldier contact")
	assert_true(frac < 0.10, "light graze is below the 10% heavy threshold")
	assert_false(OrderGuards.engaged_fraction_above(u, 0.10))


# --- move_target_occupied_by_enemy ------------------------------------------------

func test_move_target_occupied_by_enemy_true_within_the_enemys_footprint() -> void:
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	enemy.position = Vector2(500, 500)
	var reach: float = enemy.separation_radius + enemy.soldier_block_extent()
	var dest: Vector2 = enemy.position + Vector2(reach - 1.0, 0)
	assert_true(OrderGuards.move_target_occupied_by_enemy(u, dest))


func test_move_target_occupied_by_enemy_true_within_the_combined_footprint_but_outside_the_enemys_alone() -> void:
	# Regression test: an earlier version of this check summed only the ENEMY's own
	# footprint, missing `u`'s own -- a destination just past the enemy's own reach but
	# still inside the two units' COMBINED reach read as falsely "clear", even though u's
	# own block will physically occupy that ground too once it arrives.
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	enemy.position = Vector2(500, 500)
	var enemy_only_reach: float = enemy.separation_radius + enemy.soldier_block_extent()
	var combined_reach: float = u.separation_radius + u.soldier_block_extent() + enemy_only_reach
	var dest: Vector2 = enemy.position + Vector2(combined_reach - 1.0, 0)
	assert_true(dest.distance_to(enemy.position) > enemy_only_reach,
		"sanity: dest is genuinely outside the enemy-only reach this test targets")
	assert_true(OrderGuards.move_target_occupied_by_enemy(u, dest))


func test_move_target_occupied_by_enemy_false_well_clear_of_any_enemy() -> void:
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	enemy.position = Vector2(500, 500)
	assert_false(OrderGuards.move_target_occupied_by_enemy(u, enemy.position + Vector2(1000, 0)))


func test_move_target_occupied_by_enemy_ignores_a_routing_enemy() -> void:
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	enemy.position = Vector2(500, 500)
	enemy.state = Unit.State.ROUTING
	assert_false(OrderGuards.move_target_occupied_by_enemy(u, enemy.position))


func test_move_target_occupied_by_enemy_ignores_a_dead_enemy() -> void:
	var u := _make_unit(1, 0)
	var enemy := _make_unit(2, 1)
	enemy.position = Vector2(500, 500)
	enemy.state = Unit.State.DEAD
	assert_false(OrderGuards.move_target_occupied_by_enemy(u, enemy.position))


func test_move_target_occupied_by_enemy_ignores_a_friendly() -> void:
	var u := _make_unit(1, 0)
	var friendly := _make_unit(2, 0)
	friendly.position = Vector2(500, 500)
	assert_false(OrderGuards.move_target_occupied_by_enemy(u, friendly.position))


# --- satisfied() dispatch ---------------------------------------------------------

func test_satisfied_is_false_for_an_unguarded_order() -> void:
	var u := _make_unit()
	var o := Order.new_move(Vector2.ZERO)
	assert_false(OrderGuards.satisfied(u, o))


func test_satisfied_dispatches_to_the_named_guard() -> void:
	var u := _make_unit(1, 0)
	u.morale = 5.0
	var o := Order.new_move(Vector2.ZERO).with_guard(Order.Guard.MORALE_BELOW, 25.0)
	assert_true(OrderGuards.satisfied(u, o))


func test_satisfied_falls_back_to_false_for_an_unmapped_guard_value() -> void:
	var u := _make_unit()
	var o := Order.new_move(Vector2.ZERO)
	o.guard = 99
	assert_false(OrderGuards.satisfied(u, o))


func test_satisfied_never_fires_for_engaged_fraction_above_even_when_heavily_engaged() -> void:
	# ENGAGED_FRACTION_ABOVE deliberately never self-terminates via satisfied() -- the
	# disengage-time decision lives in Unit._resolve_disengage_move_order() instead. A unit
	# heavily engaged well past the threshold must still read unsatisfied here.
	var u := _make_engaged_unit(100, 4)   # 12% engaged, well over a 10% threshold
	var o := Order.new_move(Vector2.ZERO).with_guard(Order.Guard.ENGAGED_FRACTION_ABOVE, 0.10)
	assert_false(OrderGuards.satisfied(u, o))
