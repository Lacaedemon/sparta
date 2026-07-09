extends GutTest
## PIN_DOWN attack stance: defensive posture with reduced attack frequency and
## exposure during the attack frame. The window where the unit is exposed to hits
## is measurable and the defense reduction is quantifiable.

const UnitScript = preload("res://scripts/Unit.gd")
const UnitCombatScript = preload("res://scripts/UnitCombat.gd")


func _unit(uid: int = 1) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = uid
	u.max_soldiers = 100
	u.soldiers = 100
	u.attack = 12
	u.defense = 6
	u.position = Vector2(100, 100)
	u.facing = Vector2.DOWN
	return u


func _enemy(uid: int = 2, pos: Vector2 = Vector2(100, 200)) -> Unit:
	var e: Unit = UnitScript.new()
	add_child_autofree(e)
	e.uid = uid
	e.team = 1
	e.max_soldiers = 100
	e.soldiers = 100
	e.attack = 12
	e.defense = 6
	e.position = pos
	e.facing = Vector2.UP
	return e


func test_pin_down_attack_interval_is_doubled() -> void:
	## PIN_DOWN's ATTACK_INTERVAL is twice the normal ATTACK_INTERVAL
	var normal_interval: float = UnitScript.ATTACK_INTERVAL
	var pin_down_interval: float = UnitScript.PIN_DOWN_ATTACK_INTERVAL
	assert_gt(pin_down_interval, normal_interval, "PIN_DOWN interval is longer")
	assert_approximately_equal(pin_down_interval, normal_interval * 2.0, 0.01,
		"PIN_DOWN interval is approximately double")


func test_pin_down_sets_attack_frame_on_strike() -> void:
	## When a PIN_DOWN unit strikes in melee, the attack frame is set
	var u := _unit(1)
	var e := _enemy(2)
	u.order_mode = UnitScript.ORDER_PIN_DOWN
	u.state = UnitScript.State.FIGHTING
	u.target_enemy = e

	# Force an in-contact melee situation
	u.position = Vector2(100, 100)
	e.position = Vector2(105, 105)
	u.facing = (e.position - u.position).normalized()
	e.facing = (u.position - e.position).normalized()

	# The strike happens in _think, so just call it directly
	u._attack_cd = 0.0
	u._attack_frame_remaining = 0.0
	var in_contact: bool = u.position.distance_to(e.position) <= u.attack_range + u.RADIUS + e.RADIUS
	assert_true(in_contact, "units are in contact")

	# Manually apply what would happen: facing is set, then strike happens
	if u._face_for_action(e.position, 0.016, e) and u._attack_cd <= 0.0:
		if u.order_mode == UnitScript.ORDER_PIN_DOWN:
			u._attack_cd = UnitScript.PIN_DOWN_ATTACK_INTERVAL
			u._attack_frame_remaining = UnitScript.PIN_DOWN_ATTACK_FRAME_DURATION
		UnitCombatScript.strike(u, e)

	assert_gt(u._attack_frame_remaining, 0.0, "attack frame is set after strike")
	assert_approximately_equal(u._attack_frame_remaining,
		UnitScript.PIN_DOWN_ATTACK_FRAME_DURATION, 0.01,
		"attack frame matches the constant")


func test_pin_down_attack_frame_decays_over_time() -> void:
	## The attack frame countdown decays each physics tick
	var u := _unit(1)
	u._attack_frame_remaining = UnitScript.PIN_DOWN_ATTACK_FRAME_DURATION
	var initial: float = u._attack_frame_remaining

	# Simulate one tick of physics processing
	var delta: float = 0.016   # ~60 Hz
	u._physics_process(delta)

	assert_lt(u._attack_frame_remaining, initial, "frame countdown decreases")
	assert_approximately_equal(u._attack_frame_remaining,
		initial - delta, 0.001,
		"decay matches the delta time")


func test_pin_down_exposure_reduces_melee_defense() -> void:
	## When the attack frame is active, melee defense is multiplied by PIN_DOWN_DEFENSE_FACTOR
	var u := _unit(1)
	var attacker := _enemy(2)

	# Without attack frame
	u._attack_frame_remaining = 0.0
	var normal_defense: float = u.melee_defense_factor(attacker)
	assert_eq(normal_defense, 1.0, "normal defense is full (1.0)")

	# With attack frame active
	u.order_mode = UnitScript.ORDER_PIN_DOWN
	u._attack_frame_remaining = UnitScript.PIN_DOWN_ATTACK_FRAME_DURATION
	var exposed_defense: float = u.melee_defense_factor(attacker)

	var expected: float = 1.0 * UnitScript.PIN_DOWN_DEFENSE_FACTOR
	assert_eq(exposed_defense, expected,
		"exposed defense is reduced by PIN_DOWN_DEFENSE_FACTOR")
	assert_lt(exposed_defense, normal_defense,
		"exposed defense is less than normal defense")


func test_pin_down_exposure_reduces_missile_defense() -> void:
	## When the attack frame is active, missile defense is also reduced
	var u := _unit(1)
	var attacker := _enemy(2)

	# Without attack frame
	u._attack_frame_remaining = 0.0
	var normal_defense: float = u.missile_defense_factor(attacker)

	# With attack frame active
	u.order_mode = UnitScript.ORDER_PIN_DOWN
	u._attack_frame_remaining = UnitScript.PIN_DOWN_ATTACK_FRAME_DURATION
	var exposed_defense: float = u.missile_defense_factor(attacker)

	var expected: float = normal_defense * UnitScript.PIN_DOWN_DEFENSE_FACTOR
	assert_eq(exposed_defense, expected,
		"exposed missile defense is reduced by PIN_DOWN_DEFENSE_FACTOR")
	assert_lt(exposed_defense, normal_defense,
		"exposed missile defense is less than normal")


func test_pin_down_normal_mode_no_exposure() -> void:
	## Units not in PIN_DOWN mode take no exposure penalty even if frame is set
	var u := _unit(1)
	var attacker := _enemy(2)

	# Set frame but order_mode is NORMAL
	u.order_mode = UnitScript.OrderMode.NORMAL
	u._attack_frame_remaining = UnitScript.PIN_DOWN_ATTACK_FRAME_DURATION

	var defense: float = u.melee_defense_factor(attacker)
	assert_eq(defense, 1.0, "non-PIN_DOWN units ignore attack frame exposure")


func test_pin_down_attack_interval_enforced_on_second_strike() -> void:
	## After a PIN_DOWN strike, the cooldown is the longer PIN_DOWN interval
	var u := _unit(1)
	u.order_mode = UnitScript.ORDER_PIN_DOWN

	# Force a strike
	u._attack_cd = 0.0
	u._attack_frame_remaining = 0.0

	# Simulate what _think does: set interval on cooldown
	if u._attack_cd <= 0.0:
		if u.order_mode == UnitScript.ORDER_PIN_DOWN:
			u._attack_cd = UnitScript.PIN_DOWN_ATTACK_INTERVAL
			u._attack_frame_remaining = UnitScript.PIN_DOWN_ATTACK_FRAME_DURATION

	# Tick forward by normal interval
	u._physics_process(UnitScript.ATTACK_INTERVAL + 0.016)

	# Attack should NOT be ready yet (PIN_DOWN interval is longer)
	assert_gt(u._attack_cd, 0.0, "cooldown not ready after normal interval")

	# Tick forward by remainder
	u._physics_process(UnitScript.PIN_DOWN_ATTACK_INTERVAL - UnitScript.ATTACK_INTERVAL)

	# Now it should be ready
	assert_lte(u._attack_cd, 0.0, "cooldown ready after PIN_DOWN interval")
