extends GutTest
## A plain NORMAL-stance MOVE order marches off immediately once issued -- it does NOT pause
## while the unit is State.FIGHTING (Unit._think()'s melee-contact gate treats a null
## target_enemy as a disengage command). What happens once the unit's own lingering-engagement
## latch decays out (is_engaged() finally false) is either a resume toward the original
## destination or a cancel outright -- Order.Guard.ENGAGED_FRACTION_ABOVE marks which moves opt
## into this policy, and Unit._resolve_disengage_move_order() makes the actual call: resume
## when the fight never crossed the guard's threshold, or when it did but the destination is
## still clear of any living enemy; cancel only when it crossed the threshold AND the
## destination now sits inside a living enemy's own footprint (see Battle
## .ENGAGED_FRACTION_CANCELS_MOVE's own doc comment for the full policy, and Order.gd's enum
## comment for why this guard doesn't self-terminate via the generic satisfied() dispatch the
## way every other one does).
##
## Two things are covered here:
## - Battle._apply_order_cmd's two Order.new_move call sites (a fresh plain move, and an
##   appended waypoint leg): a NORMAL-stance plain move gets the guard attached, with the
##   unit's peak-engaged-fraction tracker reset to 0.0 at that same issue-time moment;
##   HOLD/CHASE/MARCH_TO_CONTACT and an explicit ATTACK order (already a committed decision
##   to fight) get neither.
## - _resolve_disengage_move_order() itself: the three resume-vs-cancel cases above, driven
##   directly (no live Battle needed for these -- see test_order_guards.gd for the pure guard
##   math, and test_orders_queue.gd for confirming this guard no longer retires via the
##   generic per-tick dispatch).
## Mirrors test_give_ground_order.gd's own "Battle._apply_order_cmd" section: a Battle
## exercised directly via the script, units registered by uid, no live scene needed.

const BattleScript = preload("res://scripts/Battle.gd")


func _make_unit(max_soldiers: int = 100) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers, joins "units"
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _battle(units: Array) -> Node:
	var b = BattleScript.new()
	autofree(b)
	for u in units:
		b._by_uid[u.uid] = u
	return b


# --- A plain NORMAL move gets the guard --------------------------------------------------

func test_a_plain_normal_move_is_issued_with_the_engaged_fraction_guard() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.current_order.type, Order.Type.MOVE)
	assert_eq(u.current_order.guard, Order.Guard.ENGAGED_FRACTION_ABOVE)
	assert_eq(u.current_order.guard_param, BattleScript.ENGAGED_FRACTION_CANCELS_MOVE)


func test_a_fresh_guarded_move_resets_the_peak_engaged_fraction_at_issue_time() -> void:
	var u := _make_unit()
	u.uid = 1
	u._move_order_peak_engaged_fraction = 0.5   # stale reading from whatever came before
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u._move_order_peak_engaged_fraction, 0.0,
		"a fresh guarded order must not inherit a stale peak reading")


func test_an_appended_waypoint_leg_also_carries_the_engaged_fraction_guard() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0,
		"target": BattleScript.ORDER_APPEND_WAYPOINT, "mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.current_order.type, Order.Type.MOVE)
	assert_eq(u.current_order.guard, Order.Guard.ENGAGED_FRACTION_ABOVE)
	assert_eq(u.current_order.guard_param, BattleScript.ENGAGED_FRACTION_CANCELS_MOVE)


func test_an_appended_waypoint_leg_also_resets_the_peak_engaged_fraction() -> void:
	var u := _make_unit()
	u.uid = 1
	u._move_order_peak_engaged_fraction = 0.5
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0,
		"target": BattleScript.ORDER_APPEND_WAYPOINT, "mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u._move_order_peak_engaged_fraction, 0.0)


func test_appending_a_waypoint_behind_a_still_busy_order_does_not_clobber_its_peak() -> void:
	# Regression test: an earlier version reset the peak unconditionally on append, even when
	# the leg does NOT become current (a busy unit just queues it) -- clobbering the unrelated,
	# still-current order's own unconsumed reading, which belongs to a real fight in progress.
	var u := _make_unit()
	u.uid = 1
	var enemy := _make_unit()
	enemy.uid = 2
	enemy.team = 1
	var current := Order.new_move(Vector2(1000, 0)).with_guard(
			Order.Guard.ENGAGED_FRACTION_ABOVE, BattleScript.ENGAGED_FRACTION_CANCELS_MOVE)
	u.set_current_order(current)
	u.has_move_target = true
	u.move_target = Vector2(1000, 0)
	u._move_order_peak_engaged_fraction = 0.6   # a real fight already happened under this order
	var b := _battle([u, enemy])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0,
		"target": BattleScript.ORDER_APPEND_WAYPOINT, "mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.current_order, current,
		"the unit is still busy with its original order -- the appended leg only queues")
	assert_eq(u._move_order_peak_engaged_fraction, 0.6,
		"the still-current order's own unconsumed peak must survive an unrelated append")
	# Promoting the queued leg (the original order finishing/being interrupted) does NOT reset
	# the peak: the 0.6 was a real fight that happened while this leg waited queued, and the
	# field's own contract is that such a fight "still counts once the leg is promoted" -- an
	# ATTACK order chasing a routed enemy can run well past the fight's own end before the
	# target finally dies and this leg promotes, so the peak must survive that gap too.
	u.retire_current_order()
	assert_eq(u.current_order.type, Order.Type.MOVE)
	assert_ne(u.current_order, current)
	assert_eq(u._move_order_peak_engaged_fraction, 0.6,
		"a fight that happened while this leg was only queued still counts once it's promoted")


# --- Already-committed stances keep their own behavior, no auto-cancel guard -------------

func test_a_hold_stance_move_does_not_get_the_engaged_fraction_guard() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.HOLD})
	assert_eq(u.current_order.type, Order.Type.MOVE)
	assert_eq(u.current_order.guard, Order.Guard.NONE,
		"HOLD is an already-committed stance -- it keeps its own behavior, not the auto-cancel")


func test_a_chase_stance_move_does_not_get_the_engaged_fraction_guard() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.CHASE})
	assert_eq(u.current_order.guard, Order.Guard.NONE,
		"CHASE never lets go of its quarry -- the auto-cancel default would fight that")


func test_a_march_to_contact_move_does_not_get_the_engaged_fraction_guard() -> void:
	var u := _make_unit()
	u.uid = 1
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.MARCH_TO_CONTACT})
	assert_eq(u.current_order.guard, Order.Guard.NONE,
		"MARCH_TO_CONTACT already has its own stop/resume contract around a plain move")


# --- An explicit attack target is never a guarded plain move -----------------------------

func test_an_explicit_attack_order_is_unaffected() -> void:
	var u := _make_unit()
	u.uid = 1
	var enemy := _make_unit()
	enemy.uid = 2
	enemy.team = 1
	var b := _battle([u, enemy])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0, "target": 2,
		"mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.current_order.type, Order.Type.ATTACK,
		"an explicit attack target makes this an ATTACK order, never a guarded plain move")
	assert_eq(u.current_order.guard, Order.Guard.NONE)


# --- _resolve_disengage_move_order: resume vs. cancel at the disengage transition -------

func _guarded_move_unit(peak_fraction: float, dest: Vector2) -> Unit:
	var u := _make_unit()
	u.uid = 1
	var o := Order.new_move(dest).with_guard(Order.Guard.ENGAGED_FRACTION_ABOVE,
			BattleScript.ENGAGED_FRACTION_CANCELS_MOVE)
	u.set_current_order(o)
	u.has_move_target = true
	u.move_target = dest
	u._move_order_peak_engaged_fraction = peak_fraction
	# is_engaged() reads false by default (a fresh Unit's _engaged_linger starts at 0) --
	# the fight has genuinely ended, matching the tick this function is meant to be called.
	return u


func test_resolve_disengage_resumes_when_the_fight_never_crossed_the_threshold() -> void:
	var u := _guarded_move_unit(0.05, Vector2(1000, 0))   # never reached 10%
	assert_false(u._resolve_disengage_move_order())
	assert_not_null(u.current_order)
	assert_true(u.has_move_target)


func test_resolve_disengage_resumes_when_crossed_but_destination_is_clear() -> void:
	var u := _guarded_move_unit(0.15, Vector2(1000, 0))   # crossed 10%, nothing near dest
	assert_false(u._resolve_disengage_move_order())
	assert_not_null(u.current_order)
	assert_true(u.has_move_target)


func test_resolve_disengage_cancels_when_crossed_and_destination_is_now_enemy_held() -> void:
	var dest := Vector2(1000, 0)
	var u := _guarded_move_unit(0.15, dest)
	var enemy := _make_unit()
	enemy.uid = 2
	enemy.team = 1
	enemy.position = dest
	assert_true(u._resolve_disengage_move_order())
	assert_null(u.current_order, "the destination is now held -- cancel rather than march in")
	assert_false(u.has_move_target)


func test_resolve_disengage_is_a_noop_while_still_engaged() -> void:
	var u := _guarded_move_unit(0.15, Vector2(1000, 0))
	var enemy := _make_unit()
	enemy.uid = 2
	enemy.team = 1
	enemy.position = u.move_target   # destination would be stale, IF the decision ran now
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.0)   # arm the linger latch -- is_engaged() now true
	assert_false(u._resolve_disengage_move_order(), "still fighting -- no decision yet")
	assert_not_null(u.current_order)


func test_resolve_disengage_decides_only_once() -> void:
	var u := _guarded_move_unit(0.15, Vector2(1000, 0))   # crossed 10%, destination clear
	assert_false(u._resolve_disengage_move_order(), "first call: resumes, consumes the peak")
	assert_eq(u._move_order_peak_engaged_fraction, 0.0)
	# A later heavy engagement can't retroactively cancel the same order once the peak has
	# already been consumed -- the decision fires exactly once per order.
	var enemy := _make_unit()
	enemy.uid = 2
	enemy.team = 1
	enemy.position = u.move_target
	assert_false(u._resolve_disengage_move_order(),
		"peak already consumed by the first call -- nothing left to decide")
	assert_not_null(u.current_order)
