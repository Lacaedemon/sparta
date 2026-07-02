extends GutTest
## Unit's general orders queue (docs/orders-queue-design.md phases 1-2): the
## append/replace/retire/clear queue operations, the maneuver execution state that lives on
## the Order (turn_target / phase / parked rear march), the interrupt semantics of replacing
## the queue, and _update_current_order's retirement bookkeeping for each order kind. These
## are bare-Unit, node-only tests -- no Battle scene needed; see test_wheel_battle.gd /
## test_file_doubling_battle.gd / test_nudge_maneuver.gd / test_reform_battle.gd for the
## full-scene tick-by-tick sim behaviour.


func _make_unit(uid: int = 1) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 10
	add_child_autofree(u)   # _ready() joins groups, seeds soldiers
	u.uid = uid
	return u


func test_a_fresh_unit_has_no_current_order() -> void:
	var u := _make_unit()
	assert_null(u.current_order)
	assert_true(u.orders.is_empty())


func test_set_current_order_replaces_the_queue_and_becomes_current() -> void:
	var u := _make_unit()
	var o := Order.new_wheel(1)
	u.set_current_order(o)
	assert_eq(u.current_order, o)
	assert_eq(u.orders.size(), 1)
	assert_eq(u.orders[0], o)


func test_set_current_order_drops_any_previously_queued_orders() -> void:
	var u := _make_unit()
	u.append_order(Order.new_move(Vector2(1, 1)))
	u.append_order(Order.new_move(Vector2(2, 2)))
	var fresh := Order.new_attack(9)
	u.set_current_order(fresh)
	assert_eq(u.orders.size(), 1)
	assert_eq(u.current_order, fresh)


func test_set_current_order_null_clears_the_queue() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_wheel(1))
	u.set_current_order(null)
	assert_null(u.current_order)
	assert_true(u.orders.is_empty())


func test_append_order_becomes_current_when_the_unit_is_idle() -> void:
	var u := _make_unit()
	var o := Order.new_move(Vector2(3, 3))
	u.append_order(o)
	assert_eq(u.current_order, o)
	assert_eq(u.orders.size(), 1)


func test_append_order_queues_behind_an_existing_current_order() -> void:
	var u := _make_unit()
	var first := Order.new_move(Vector2(1, 1))
	var second := Order.new_move(Vector2(2, 2))
	u.set_current_order(first)
	u.append_order(second)
	assert_eq(u.current_order, first)   # unchanged -- still marching the first leg
	assert_eq(u.orders.size(), 2)
	assert_eq(u.orders[1], second)


func test_waypoint_legs_retire_their_move_orders_in_lockstep() -> void:
	# Waypoint legs and queued MOVE orders are appended 1:1, so finishing a leg retires its
	# order and promotes the next -- the queue reports the leg actually marching.
	var u := _make_unit()
	u.seed_sim_soldiers()
	var first := Order.new_move(Vector2(10, 0))
	var second := Order.new_move(Vector2(20, 0))
	u.set_current_order(first)
	u.move_target = Vector2(10, 0)
	u.has_move_target = true
	u.append_order(second)
	u.waypoints.append(Vector2(20, 0))
	u.position = Vector2(10, 0)   # arrived at the first leg
	u._think(1.0 / 60.0)
	assert_eq(u.current_order, second, "the finished leg's order retired; the next leg is current")
	assert_eq(u.move_target, Vector2(20, 0), "and the march rolls on to the next point")


func test_retire_current_order_promotes_the_next_queued_order() -> void:
	var u := _make_unit()
	var first := Order.new_move(Vector2(1, 1))
	var second := Order.new_move(Vector2(2, 2))
	u.set_current_order(first)
	u.orders.append(second)
	u.retire_current_order()
	assert_eq(u.current_order, second)
	assert_eq(u.orders.size(), 1)


func test_retire_current_order_on_the_last_queued_order_clears_current() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_wheel(1))
	u.retire_current_order()
	assert_null(u.current_order)
	assert_true(u.orders.is_empty())


func test_retire_current_order_on_an_empty_queue_is_a_no_op() -> void:
	var u := _make_unit()
	u.retire_current_order()   # nothing queued -- must not error
	assert_null(u.current_order)


func test_clear_orders_empties_the_queue_and_current_order() -> void:
	var u := _make_unit()
	u.append_order(Order.new_move(Vector2(1, 1)))
	u.append_order(Order.new_move(Vector2(2, 2)))
	u.clear_orders()
	assert_null(u.current_order)
	assert_true(u.orders.is_empty())


# --- _update_current_order: retirement / phase bookkeeping ------------------

func test_update_current_order_is_a_no_op_when_idle() -> void:
	var u := _make_unit()
	u._update_current_order()   # must not error with no current order
	assert_null(u.current_order)


func test_move_order_retires_on_arrival() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_move(Vector2(10, 10)))
	u.has_move_target = false   # arrived; no queued waypoint leg
	u._update_current_order()
	assert_null(u.current_order)


func test_move_order_stays_current_while_still_marching() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_move(Vector2(10, 10)))
	u.has_move_target = true
	u._update_current_order()
	assert_not_null(u.current_order)
	assert_eq(u.current_order.type, Order.Type.MOVE)


## Regression for a real bug caught in review: a reform-before-move hold (Battle._apply_order_cmd
## sets _reform_timer and leaves has_move_target false for its duration) reads identically to
## "arrived" if the retire check only looks at has_move_target/waypoints/conversio/pending-march
## -- so an ordinary move order (reform_before_move defaults to true) retired current_order one
## tick after being issued, before the march it describes had even started.
func test_move_order_survives_a_reform_before_move_hold() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_move(Vector2(10, 10)))
	u.has_move_target = false   # parked: Battle._apply_order_cmd's reform branch, not arrival
	u._reform_target = Vector2(10, 10)
	u._reform_timer = 1.0
	u._update_current_order()
	assert_not_null(u.current_order)
	assert_eq(u.current_order.type, Order.Type.MOVE)


func test_move_order_retires_once_the_reform_hold_expires_and_the_unit_has_arrived() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_move(Vector2(10, 10)))
	u._reform_timer = 0.0   # hold expired and the resulting march has since arrived
	u.has_move_target = false
	u._update_current_order()
	assert_null(u.current_order)


## Install a rear-move composite the way Battle._apply_order_cmd does: a MOVE order with
## the reform choice, made current, then the about-face TURN phase armed on it. The unit
## gets a PARTIAL last rank (10 men at 4 files = 2 full ranks + 2), so a completed flip has
## something to bring forward and the drilled variant's reform_ranks() actually runs -- a
## full grid is centre-symmetric and would no-op straight to the march.
func _stage_rear_move(u: Unit, dest: Vector2, reform: bool) -> Order:
	u.facing = Vector2.DOWN
	u.frontage_override = 4
	u.seed_sim_soldiers()
	var o := Order.new_move(dest)
	o.reform = reform
	u.set_current_order(o)
	u.has_move_target = false
	assert_true(u.begin_about_face(o), "the about-face arms on a seeded idle unit")
	return o


func test_phased_move_order_transitions_turn_to_march_once_the_about_face_hands_off() -> void:
	var u := _make_unit()
	var o := _stage_rear_move(u, Vector2(10, 10), false)   # hasty: no reform phase
	assert_eq(o.phase, Order.Phase.TURN)
	assert_true(u.is_order_turning())
	# The turn completes (mirrors _think()'s order-turn block on arrival).
	u.facing = o.turn_target
	u._settle_order_turn()
	u._finish_order_turn()
	assert_eq(o.phase, Order.Phase.MARCH)
	assert_true(u.has_move_target, "the parked march committed on the handoff")
	assert_eq(u.move_target, Vector2(10, 10), "toward the destination parked on the order")
	assert_true(u._reform_on_arrival, "the hasty variant defers its reform to arrival")


func test_phased_move_order_stays_in_turn_phase_while_the_about_face_is_still_running() -> void:
	var u := _make_unit()
	var o := _stage_rear_move(u, Vector2(10, 10), false)
	u._update_current_order()
	assert_eq(o.phase, Order.Phase.TURN)
	assert_not_null(u.current_order)   # not retired mid-turn


func test_phased_move_order_enters_reform_when_the_about_face_hands_off_to_the_hold() -> void:
	# Mirrors _think()'s reform-before-march handoff: timer armed, march parked in
	# _reform_target while the countermarch brings a full rank forward.
	var u := _make_unit()
	var o := _stage_rear_move(u, Vector2(10, 10), true)
	u.facing = o.turn_target
	u._settle_order_turn()
	u._finish_order_turn()
	assert_eq(o.phase, Order.Phase.REFORM)
	assert_gt(u._reform_timer, 0.0, "the reform hold armed")
	assert_eq(u._reform_target, Vector2(10, 10), "with the march parked behind it")
	assert_false(u.has_move_target, "the march holds until the ranks re-form")
	u._update_current_order()
	assert_not_null(u.current_order)   # not retired mid-reform


func test_phased_move_order_transitions_reform_to_march_once_the_hold_commits() -> void:
	var u := _make_unit()
	var o := _stage_rear_move(u, Vector2(10, 10), true)
	u.facing = o.turn_target
	u._settle_order_turn()
	u._finish_order_turn()
	assert_eq(o.phase, Order.Phase.REFORM)
	# The hold commits the parked march.
	u._commit_pending_reform()
	assert_eq(o.phase, Order.Phase.MARCH)
	assert_true(u.has_move_target)
	assert_not_null(u.current_order)   # marching, not retired


func test_interrupting_a_turning_move_order_drops_the_parked_rear_march() -> void:
	# The stale-march regression the migration fixes at the root: under the old parallel
	# flags, an attack order issued mid-about-face left the parked rear destination behind
	# (nothing cleared _pending_march_target), so the unit resumed marching to it after the
	# fight. The march now lives on the replaced order and dies with it.
	var u := _make_unit()
	var o := _stage_rear_move(u, Vector2(10, 10), false)
	u.facing = u.facing.rotated(0.5)   # partway through the reversal
	u.set_current_order(Order.new_attack(9))
	u.target_enemy = _make_unit(9)
	assert_eq(u.current_order.type, Order.Type.ATTACK)
	assert_eq(o.turn_target, Vector2.ZERO, "the interrupted turn settled")
	assert_false(u.has_move_target, "no stale rear march survives the replaced order")
	# The fight resolves; nothing resurrects the old rear destination.
	u.target_enemy = null
	u._update_current_order()
	assert_null(u.current_order)
	assert_false(u.has_move_target)


func test_replacing_a_turning_order_folds_the_partial_rotation() -> void:
	# An interrupt mid-turn must settle the partial rotation into _formation_angle (the
	# same fold the in-tick interrupt does), so the bodies never surge to reorganised slots.
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.quarter_turn(1)
	var turned: float = PI * 0.25
	u.facing = u.facing.rotated(turned)   # partway through the 90°
	u.set_current_order(Order.new_move(Vector2(50, 50)))
	assert_almost_eq(u._formation_angle, wrapf(-turned, -PI, PI), 0.0001,
		"the partial rotation folded into the formation angle")
	assert_false(u.is_order_turning(), "and nothing is left turning")


func test_attack_order_retires_once_the_target_enemy_is_cleared() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_attack(2))
	u.target_enemy = null
	u._update_current_order()
	assert_null(u.current_order)


func test_attack_order_stays_current_while_a_target_enemy_is_set() -> void:
	var u := _make_unit()
	var enemy := _make_unit(2)
	u.set_current_order(Order.new_attack(2))
	u.target_enemy = enemy
	u._update_current_order()
	assert_not_null(u.current_order)


## Regression for a real bug caught in review: UnitRelief.begin can resolve the primary
## reliever's foe to null (the tired unit had no target_enemy and UnitTargeting.nearest_enemy
## found none either), in which case it instead advances the reliever onto the tired unit's slot
## (has_move_target = true) rather than leaving target_enemy set. A retire check keyed on
## target_enemy alone can't tell that apart from "relief is done" and retired the order
## immediately, before the unit had even reached the slot.
func test_relief_order_survives_a_null_foe_while_still_advancing_into_position() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_relief(3))
	u.target_enemy = null
	u.has_move_target = true   # UnitRelief.begin's "truly no foe: advance onto its slot" path
	u._update_current_order()
	assert_not_null(u.current_order)
	assert_eq(u.current_order.type, Order.Type.RELIEF)


func test_relief_order_retires_once_arrived_with_no_foe_to_fight() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_relief(3))
	u.target_enemy = null
	u.has_move_target = false   # arrived at the slot; still nothing to fight
	u._update_current_order()
	assert_null(u.current_order)


func test_support_order_retires_once_the_ward_is_cleared() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_support(3))
	u.support_target = null
	u._update_current_order()
	assert_null(u.current_order)


func test_wheel_arms_its_own_order_with_the_swing_state() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.wheel(1)
	assert_not_null(u.current_order)
	assert_eq(u.current_order.type, Order.Type.WHEEL)
	assert_true(u.is_wheeling())
	assert_true(u.current_order.turn_target.is_equal_approx(u.facing.rotated(PI * 0.5)),
		"the swing goal is 90° right of the start heading")
	assert_ne(u.current_order.pivot, Vector2.ZERO, "the hinge is captured on the order")


func test_wheel_order_retires_once_the_swing_settles() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.wheel(1)
	u.current_order.turn_target = Vector2.ZERO   # the swing completed (mirrors _think)
	u._update_current_order()
	assert_null(u.current_order)


func test_wheel_order_stays_current_while_the_wheel_is_still_swinging() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.wheel(1)
	u._update_current_order()
	assert_not_null(u.current_order)


func test_wheel_is_refused_while_a_move_order_is_live() -> void:
	# A refused drill leaves the queue -- and the order the march runs off -- untouched.
	var u := _make_unit()
	u.seed_sim_soldiers()
	var move := Order.new_move(Vector2(100, 100))
	u.set_current_order(move)
	u.has_move_target = true
	u.move_target = Vector2(100, 100)
	u.wheel(1)
	assert_eq(u.current_order, move, "the wheel does not clobber a live move order")


func test_formation_order_retires_immediately() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_formation(1))
	u._update_current_order()
	assert_null(u.current_order)


func test_frontage_order_retires_immediately() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_frontage(4))
	u._update_current_order()
	assert_null(u.current_order)


# --- Teardown: death and rout drop every in-progress order -------------------

func test_rout_clears_the_orders_queue() -> void:
	var u := _make_unit()
	u.append_order(Order.new_move(Vector2(1, 1)))
	u.append_order(Order.new_move(Vector2(2, 2)))
	u._rout()
	assert_null(u.current_order)
	assert_true(u.orders.is_empty())
