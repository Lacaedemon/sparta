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
