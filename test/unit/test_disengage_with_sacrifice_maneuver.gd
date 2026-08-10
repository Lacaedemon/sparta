extends GutTest
## Disengage with sacrifice (melee maneuver): a FIGHTING unit leaves a rearguard detachment
## engaged to delay the enemy while the surviving main body steps back.

const BattleScript = preload("res://scripts/Battle.gd")


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func test_disengage_with_sacrifice_is_a_noop_when_not_fighting() -> void:
	var u := _make_unit()
	u.state = Unit.State.IDLE
	var before_pos := u.position
	var before_soldiers := u.soldiers
	u.disengage_with_sacrifice()
	assert_eq(u.position, before_pos, "an idle unit doesn't move")
	assert_eq(u.soldiers, before_soldiers, "no casualties taken when not fighting")
	assert_false(u.has_move_target, "no move target is armed")


func test_disengage_with_sacrifice_takes_rearguard_casualties_and_steps_back() -> void:
	var u := _make_unit(100)
	var enemy := _make_unit(100)
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.state = Unit.State.FIGHTING
	u.target_enemy = enemy

	u.disengage_with_sacrifice()

	assert_eq(u.soldiers, 90, "takes default 10% rearguard sacrifice casualties (10 of 100)")
	assert_null(u.target_enemy, "clears target_enemy")
	assert_true(u.has_move_target, "arms backward move target")
	var expected: Vector2 = Vector2.ZERO + Unit.disengage_offset(Vector2.DOWN)
	assert_true(u.move_target.is_equal_approx(expected), "steps back straight behind facing")


func test_disengage_with_sacrifice_accepts_caller_configured_parameters() -> void:
	var u := _make_unit(100)
	var enemy := _make_unit(100)
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.state = Unit.State.FIGHTING
	u.target_enemy = enemy

	# Override distance to 90.0, sacrifice_frac to 0.20 (20 soldiers), and delay to 3.0s
	var result: Dictionary = u.disengage_with_sacrifice(90.0, 0.20, 3.0)

	assert_eq(u.soldiers, 80, "takes 20% caller-configured rearguard sacrifice casualties (20 of 100)")
	assert_eq(int(result["sacrifice_count"]), 20, "reports the sacrifice headcount for the caller to spawn")
	assert_almost_eq(float(result["delay_sec"]), 3.0, 0.001,
			"reports the custom delay for the caller's rearguard spawn")
	var expected: Vector2 = Vector2.ZERO + Unit.disengage_offset(Vector2.DOWN, 90.0)
	assert_true(u.move_target.is_equal_approx(expected), "steps back custom 90.0 wu distance")


func test_disengage_with_sacrifice_uses_a_unique_order_sentinel() -> void:
	var sentinels: Array = [
		BattleScript.ORDER_APPEND_WAYPOINT, BattleScript.ORDER_FORMATION_ONLY,
		BattleScript.ORDER_FRONTAGE_ONLY, BattleScript.ORDER_WHEEL, BattleScript.ORDER_NUDGE,
		BattleScript.ORDER_STANCE_ONLY, BattleScript.ORDER_COUNTERMARCH,
		BattleScript.ORDER_UNIT_SETTINGS_ONLY, BattleScript.ORDER_DISENGAGE,
	]
	assert_false(sentinels.has(BattleScript.ORDER_DISENGAGE_SACRIFICE),
		"ORDER_DISENGAGE_SACRIFICE doesn't collide with any existing sentinel")


func test_enqueue_disengage_with_sacrifice_noops_during_playback() -> void:
	var b = BattleScript.new()
	autofree(b)
	var u := _make_unit()
	u.uid = 88
	b._by_uid[88] = u
	var prev_mode: int = Replay.mode
	Replay.mode = Replay.Mode.PLAYBACK
	b.enqueue_disengage_with_sacrifice([88])
	Replay.mode = prev_mode
	assert_true(b._pending_orders.is_empty(), "disengage_with_sacrifice during playback is dropped")


func test_enqueue_disengage_with_sacrifice_noops_with_no_units() -> void:
	var b = BattleScript.new()
	autofree(b)
	b.enqueue_disengage_with_sacrifice([])
	assert_true(b._pending_orders.is_empty(), "an empty uid list queues nothing")


func test_enqueue_disengage_with_sacrifice_applies_order_to_units() -> void:
	var b = BattleScript.new()
	autofree(b)
	# Applying the order now spawns a rearguard sub-unit (#1041), which needs a real
	# Units container to add itself to -- a bare, tree-detached Battle never runs _ready()
	# to resolve @onready var _units: Node2D = $Units, so set it directly.
	b._units = Node2D.new()
	autofree(b._units)
	var u := _make_unit(100)
	u.uid = 99
	var enemy := _make_unit(100)
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.state = Unit.State.FIGHTING
	u.target_enemy = enemy
	b._by_uid[99] = u

	b.enqueue_disengage_with_sacrifice([99])

	assert_eq(b._pending_orders.size(), 1, "queues disengage_with_sacrifice command")
	assert_eq(u.soldiers, 90, "applies disengage_with_sacrifice to unit 99")


func test_disengage_with_sacrifice_never_annihilates_a_near_wiped_out_unit() -> void:
	# A unit down to a handful of soldiers still has a "main body" to save -- the sacrifice
	# must never take the last soldier and trigger _die() (that would defeat the whole point
	# of the maneuver: a surviving detachment stepping back to safety).
	var u := _make_unit(3)
	var enemy := _make_unit(100)
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.state = Unit.State.FIGHTING
	u.target_enemy = enemy

	u.disengage_with_sacrifice()

	assert_gt(u.soldiers, 0, "at least one soldier survives to form the main body")
	assert_ne(u.state, Unit.State.DEAD, "the unit is not annihilated by its own rearguard sacrifice")


func test_disengage_with_sacrifice_is_a_noop_with_only_one_soldier_left() -> void:
	var u := _make_unit(1)
	var enemy := _make_unit(100)
	enemy.team = 1
	enemy.position = Vector2(30, 0)
	u.state = Unit.State.FIGHTING
	u.target_enemy = enemy
	var before_soldiers := u.soldiers

	u.disengage_with_sacrifice()

	assert_eq(u.soldiers, before_soldiers, "no rearguard to spare with only one soldier left")
	assert_false(u.has_move_target, "no move target armed; maneuver did nothing")


## The pursuit slowdown itself is no longer a Unit-level property to assert here (#1041
## removed the flat pursuit-speed multiplier this test used to check): a pursuer is now
## slowed because it's physically blocked and fighting a real rearguard Unit, which needs
## an actual Battle to spawn and simulate -- see
## test_disengage_with_sacrifice_rearguard.gd's live-battle proof instead.
func test_disengage_with_sacrifice_no_longer_sets_any_state_on_the_retreating_unit_itself() -> void:
	var u := _make_unit(100)
	var enemy := _make_unit(100)
	enemy.team = 1
	u.state = Unit.State.FIGHTING
	u.target_enemy = enemy

	u.disengage_with_sacrifice()

	assert_false(u.is_rearguard_detachment,
			"the retreating main body is never itself the rearguard detachment")

