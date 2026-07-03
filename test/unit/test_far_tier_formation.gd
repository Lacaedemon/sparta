extends GutTest
## FarTierFormation (docs/large-scale-simulation-design.md phase 1): tests for the aggregate
## far-tier record in isolation — sane defaults, field round-trips, and the from_unit()
## snapshot reduction (pure, read-only, a value copy rather than a live view). No sim
## behavior is exercised; phase 1 wires none.


func _make_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 10
	add_child_autofree(u)   # _ready() joins groups, seeds soldiers = max_soldiers
	return u


func test_defaults_match_a_fresh_full_strength_formation() -> void:
	var rec := FarTierFormation.new()
	assert_eq(rec.count, 0)
	assert_eq(rec.morale, 100.0)
	assert_eq(rec.position.x, 0.0)
	assert_eq(rec.position.y, 0.0)
	assert_eq(rec.facing.x, Vector2.DOWN.x)
	assert_eq(rec.facing.y, Vector2.DOWN.y)
	assert_eq(rec.casualties, 0)
	assert_eq(rec.formation_mode, Unit.FORMATION_NORMAL)
	assert_eq(rec.spacing_scale, 1.0)
	assert_eq(rec.order_mode, 0)
	assert_eq(rec.max_soldiers, 0)
	assert_eq(rec.attack, 0)
	assert_eq(rec.defense, 0)
	assert_eq(rec.attack_range, 26.0)   # Unit.attack_range default (gladius baseline)
	assert_eq(rec.march_speed, 45.0)    # Unit.walk_speed default
	assert_eq(rec.casualty_carry, 0.0)
	assert_false(rec.is_ranged)         # Unit.is_ranged default
	assert_false(rec.routing)           # Unit.State.ROUTING default (fresh formations fight)
	assert_eq(rec.rout_timer, 0.0)


func test_fields_round_trip() -> void:
	var rec := FarTierFormation.new()
	rec.count = 87
	rec.morale = 42.5
	rec.position = Vector2(120.0, -340.0)
	rec.facing = Vector2.RIGHT
	rec.casualties = 13
	rec.formation_mode = Unit.FORMATION_TESTUDO
	rec.spacing_scale = 0.85
	rec.order_mode = Unit.ORDER_SKIRMISH
	assert_eq(rec.count, 87)
	assert_eq(rec.morale, 42.5)
	assert_eq(rec.position.x, 120.0)
	assert_eq(rec.position.y, -340.0)
	assert_eq(rec.facing.x, 1.0)
	assert_eq(rec.facing.y, 0.0)
	assert_eq(rec.casualties, 13)
	assert_eq(rec.formation_mode, Unit.FORMATION_TESTUDO)
	assert_eq(rec.spacing_scale, 0.85)
	assert_eq(rec.order_mode, Unit.ORDER_SKIRMISH)


func test_from_unit_copies_every_aggregate_field() -> void:
	var u := _make_unit()
	u.soldiers = 7
	u.morale = 62.5
	u.position = Vector2(150.0, 300.0)
	u.facing = Vector2.UP
	u.formation_mode = Unit.FORMATION_SQUARE
	u.spacing_scale = 0.9
	u.order_mode = Unit.ORDER_HOLD
	var rec := FarTierFormation.from_unit(u)
	assert_eq(rec.count, 7)
	assert_eq(rec.morale, 62.5)
	assert_eq(rec.position.x, 150.0)
	assert_eq(rec.position.y, 300.0)
	assert_eq(rec.facing.x, 0.0)
	assert_eq(rec.facing.y, -1.0)
	assert_eq(rec.formation_mode, Unit.FORMATION_SQUARE)
	assert_eq(rec.spacing_scale, 0.9)
	assert_eq(rec.order_mode, Unit.ORDER_HOLD)


func test_from_unit_copies_the_durable_regiment_stats() -> void:
	var u := _make_unit()
	u.attack = 15
	u.defense = 8
	u.attack_range = 48.0   # spear reach
	u.walk_speed = 40.0
	var rec := FarTierFormation.from_unit(u)
	assert_eq(rec.max_soldiers, 10)
	assert_eq(rec.attack, 15)
	assert_eq(rec.defense, 8)
	assert_eq(rec.attack_range, 48.0)
	assert_eq(rec.march_speed, 40.0)   # the sustained AUTO pace is the walk
	assert_eq(rec.casualty_carry, 0.0)


func test_from_unit_copies_is_ranged() -> void:
	var u := _make_unit()
	u.is_ranged = true
	var rec := FarTierFormation.from_unit(u)
	assert_true(rec.is_ranged)


func test_from_unit_copies_routing_state() -> void:
	var u := _make_unit()
	u.state = Unit.State.ROUTING
	u._rout_timer = 2.5
	var rec := FarTierFormation.from_unit(u)
	assert_true(rec.routing)
	assert_almost_eq(rec.rout_timer, 2.5, 0.0001)


func test_from_unit_reports_not_routing_for_a_fighting_unit() -> void:
	var u := _make_unit()
	u.state = Unit.State.FIGHTING
	var rec := FarTierFormation.from_unit(u)
	assert_false(rec.routing)
	assert_eq(rec.rout_timer, 0.0)


func test_from_unit_derives_casualties_from_losses_so_far() -> void:
	var u := _make_unit()
	u.soldiers = 7
	var rec := FarTierFormation.from_unit(u)
	assert_eq(rec.casualties, 3)   # max_soldiers 10, 7 living


func test_from_unit_reports_zero_casualties_at_full_strength() -> void:
	var u := _make_unit()
	var rec := FarTierFormation.from_unit(u)
	assert_eq(rec.count, 10)
	assert_eq(rec.casualties, 0)


func test_from_unit_does_not_mutate_the_unit() -> void:
	var u := _make_unit()
	u.soldiers = 7
	u.morale = 62.5
	u.formation_mode = Unit.FORMATION_TIGHT
	FarTierFormation.from_unit(u)
	assert_eq(u.soldiers, 7)
	assert_eq(u.morale, 62.5)
	assert_eq(u.formation_mode, Unit.FORMATION_TIGHT)
	assert_eq(u.position.x, 0.0)
	assert_eq(u.position.y, 0.0)


func test_from_unit_snapshots_values_rather_than_tracking_the_unit() -> void:
	var u := _make_unit()
	u.soldiers = 8
	var rec := FarTierFormation.from_unit(u)
	u.soldiers = 2
	u.position = Vector2(999.0, 999.0)
	assert_eq(rec.count, 8)
	assert_eq(rec.position.x, 0.0)
	assert_eq(rec.position.y, 0.0)


func test_from_unit_is_deterministic() -> void:
	# The design doc's tier-boundary invariant: the reduction is a pure function of the
	# unit's fields — two snapshots of the same state agree on every field.
	var u := _make_unit()
	u.soldiers = 5
	u.morale = 33.0
	u.position = Vector2(-40.0, 80.0)
	var a := FarTierFormation.from_unit(u)
	var b := FarTierFormation.from_unit(u)
	assert_eq(a.count, b.count)
	assert_eq(a.morale, b.morale)
	assert_eq(a.position.x, b.position.x)
	assert_eq(a.position.y, b.position.y)
	assert_eq(a.facing.x, b.facing.x)
	assert_eq(a.facing.y, b.facing.y)
	assert_eq(a.casualties, b.casualties)
	assert_eq(a.formation_mode, b.formation_mode)
	assert_eq(a.spacing_scale, b.spacing_scale)
	assert_eq(a.order_mode, b.order_mode)
