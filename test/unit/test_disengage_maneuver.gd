extends GutTest
## Disengage and step back (melee maneuver): a FIGHTING unit breaks contact
## and marches DISENGAGE_STEP_DISTANCE straight back, holding facing. Two layers: the pure
## Unit.disengage_offset geometry (no SceneTree), and bare-unit _think() calls proving the
## combat/order-state transitions (mirrors test_chase_order.gd's pattern -- Unit.disengage()
## is order-mode-shaped logic, not something that needs a full live battle to exercise
## correctly). See test_disengage_battle.gd for the live-battle/demo-input coverage.

const BattleScript = preload("res://scripts/Battle.gd")


# --- pure geometry -----------------------------------------------------------

func test_disengage_offset_is_opposite_facing() -> void:
	var back: Vector2 = Unit.disengage_offset(Vector2.UP)
	assert_almost_eq(back.x, 0.0, 0.001, "no lateral component")
	assert_almost_eq(back.y, Unit.DISENGAGE_STEP_DISTANCE, 0.001,
		"steps directly away from facing (down, when facing up)")


func test_disengage_offset_is_fixed_length_and_relative_to_facing() -> void:
	var back: Vector2 = Unit.disengage_offset(Vector2.RIGHT)
	assert_almost_eq(back.x, -Unit.DISENGAGE_STEP_DISTANCE, 0.001, "back is -x when facing right")
	assert_almost_eq(back.y, 0.0, 0.001, "no lateral component")
	assert_almost_eq(back.length(), Unit.DISENGAGE_STEP_DISTANCE, 0.001,
		"the step is always DISENGAGE_STEP_DISTANCE long")


func test_disengage_step_distance_clears_the_gladius_baseline_contact_range() -> void:
	# Design guard: the step should be able to clear the shortest common melee contact
	# range (two RADIUS=18wu bodies plus the ~26wu gladius baseline reach -- see
	# SKIRMISH_KITE_DISTANCE's own "melee contact (~62)" comment) in a single step,
	# not just nudge the unit while it's still trivially in range.
	var baseline_contact: float = 26.0 + 18.0 + 18.0
	assert_gt(Unit.DISENGAGE_STEP_DISTANCE, baseline_contact,
		"a disengage step clears the shortest common melee contact range outright")


# --- isolated unit: combat/order-state transitions --------------------------

func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func test_disengage_is_a_noop_when_not_fighting() -> void:
	var u := _make_unit()
	u.state = Unit.State.IDLE
	var before_pos := u.position
	var before_order := u.current_order
	u.disengage()
	assert_eq(u.position, before_pos, "an idle unit doesn't move")
	assert_eq(u.current_order, before_order, "no order is installed")
	assert_false(u.has_move_target, "no move target is armed")


func test_disengage_is_a_noop_for_a_chase_unit() -> void:
	# CHASE never lets go of its foe (test_chase_order.gd's own contrast test proves a
	# plain move order can't disengage a CHASE unit either); disengage() must refuse the
	# same way rather than parking a stale NUDGE order the chase branch will never let
	# resolve.
	var u := _make_unit()
	u.order_mode = Unit.ORDER_CHASE
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.state = Unit.State.FIGHTING
	u.target_enemy = enemy
	var before_pos := u.position
	var before_order := u.current_order
	u.disengage()
	assert_eq(u.position, before_pos, "a chasing unit is untouched by disengage()")
	assert_eq(u.current_order, before_order, "no order is installed")
	assert_eq(u.target_enemy, enemy, "the chase target is left alone")


func test_disengage_clears_the_target_and_arms_a_backward_move() -> void:
	var u := _make_unit()
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.state = Unit.State.FIGHTING
	u.target_enemy = enemy
	u.support_target = null
	u.disengage()
	assert_null(u.target_enemy, "target_enemy is cleared -- the disengage signal _think() reads")
	assert_true(u.has_move_target, "a move target is armed")
	assert_not_null(u.current_order, "an order is installed")
	assert_eq(u.current_order.type, Order.Type.NUDGE, "reuses the back-step nudge order shape")
	assert_eq(u.current_order.dir, Unit.NUDGE_BACK, "specifically the BACK direction")
	var expected: Vector2 = Vector2.ZERO + Unit.disengage_offset(Vector2.DOWN)
	assert_true(u.move_target.is_equal_approx(expected),
		"move_target is DISENGAGE_STEP_DISTANCE straight behind the unit's own facing")


func test_disengage_holds_facing_and_marches_backward_over_several_ticks() -> void:
	# Per sparta's own "verify maneuvers tick by tick" convention: step a real _think()
	# loop rather than trusting the single-call state-transition test above alone. Scoped
	# to the withdrawal itself (until the step-back order retires): once it's arrived and
	# the unit stands idle again, its ordinary "auto-advance on a detected nearby enemy"
	# default is free to march it back toward the still-close foe -- real, pre-existing AI
	# behaviour this maneuver doesn't (and shouldn't) suppress, not something to assert
	# against here.
	var u := _make_unit()
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.state = Unit.State.FIGHTING
	u.target_enemy = enemy
	u.disengage()
	var start_facing: Vector2 = u.facing
	var farthest_from_enemy := 0.0
	var retired := false
	# Budget: order_response_delay (0.5s = 30 ticks) plus enough runway for a bare, default-
	# stat unit to accelerate from a standstill and cover DISENGAGE_STEP_DISTANCE at its own
	# (modest, un-loadout-tuned) walk pace -- empirically ~190 ticks for the class defaults;
	# 260 leaves headroom without running so long the unit's own post-arrival auto-advance
	# starts marching it back toward the enemy (observed starting well past that point).
	for i in range(260):
		u._think(1.0 / 60.0)
		if u.current_order == null:
			retired = true
			break
		assert_true(u.facing.is_equal_approx(start_facing),
			"tick %d: a disengage step holds facing -- it never pivots toward travel" % i)
		assert_ne(u.state, Unit.State.FIGHTING,
			"tick %d: the unit never re-enters combat while the withdrawal is in flight" % i)
		farthest_from_enemy = maxf(farthest_from_enemy, u.position.distance_to(enemy.position))
	assert_true(retired, "the disengage order retired (arrived) within budget")
	assert_gt(farthest_from_enemy, 30.0 + Unit.DISENGAGE_STEP_DISTANCE * 0.5,
		"the unit actually put real distance between itself and its former opponent")


func test_disengage_uses_a_unique_order_sentinel() -> void:
	# Guard the wiring the way test_chase_order.gd's own registration test does: the
	# sentinel must not collide with any other ORDER_* target value.
	var sentinels: Array = [
		BattleScript.ORDER_APPEND_WAYPOINT, BattleScript.ORDER_FORMATION_ONLY,
		BattleScript.ORDER_FRONTAGE_ONLY, BattleScript.ORDER_WHEEL, BattleScript.ORDER_NUDGE,
		BattleScript.ORDER_STANCE_ONLY, BattleScript.ORDER_COUNTERMARCH,
		BattleScript.ORDER_UNIT_SETTINGS_ONLY,
	]
	assert_false(sentinels.has(BattleScript.ORDER_DISENGAGE),
		"ORDER_DISENGAGE doesn't collide with any existing order-target sentinel")


# --- Battle.enqueue_disengage: the recorded-order path -----------------------
# Mirrors test_countermarch_maneuver.gd's own "Battle.enqueue_countermarch" section:
# a disengage moves the regiment (Unit.disengage() sets position/facing state), so it must
# respect the same playback guard every other recorded order does, called directly here
# since SelectionManager._issue_disengage()'s own playback check short-circuits before ever
# reaching Battle.enqueue_disengage.

func test_enqueue_disengage_noops_during_playback() -> void:
	var b = BattleScript.new()
	autofree(b)
	var u := _make_unit()
	u.uid = 77
	b._by_uid[77] = u
	var prev_mode: int = Replay.mode
	Replay.mode = Replay.Mode.PLAYBACK
	b.enqueue_disengage([77])
	Replay.mode = prev_mode
	assert_true(b._pending_orders.is_empty(), "a disengage command issued during playback is dropped")


func test_enqueue_disengage_noops_with_no_units() -> void:
	var b = BattleScript.new()
	autofree(b)
	b.enqueue_disengage([])
	assert_true(b._pending_orders.is_empty(), "an empty uid list queues nothing")
