extends GutTest
## Test ROLL_THE_LINE attack order mode: when a target routs or dies, the unit
## automatically re-targets the next closest enemy.

func test_roll_the_line_retargets_on_rout() -> void:
	# Setup: two allied units attacking an enemy. When the first enemy routs,
	# the attacker should automatically re-target the next-closest enemy.
	var battle: Battle = Battle.new()
	battle.add_child(battle)
	await get_tree().process_frame

	# Force a deterministic seed for replay consistency.
	Replay.forced_seed = 12345

	# Manually spawn units to control their positions and teams.
	var attacker: Unit = _spawn_unit(battle, 100, 300, team=0)
	var target1: Unit = _spawn_unit(battle, 400, 300, team=1)  # Primary target
	var target2: Unit = _spawn_unit(battle, 450, 300, team=1)  # Next-closest

	# Order the attacker to roll-the-line attack the first target.
	var cmd: Dictionary = {
		"units": [attacker.uid],
		"target": target1.uid,
		"x": float(target1.position.x),
		"y": float(target1.position.y),
		"mode": Battle.OrderMode.ROLL_THE_LINE,
	}
	battle._apply_order_cmd(cmd)

	# Tick forward to let the unit reach and engage the target.
	for _ in range(150):
		battle._physics_process(1.0 / 60.0)

	# At this point the attacker should have target1 as its target.
	assert_eq(attacker.target_enemy, target1, "Attacker should have primary target")

	# Force target1 to rout by setting its morale to 0.
	target1.morale = 0.0
	target1._rout()

	# Tick once more to trigger re-targeting.
	battle._physics_process(1.0 / 60.0)

	# The attacker should now have target2 as its new target (the next-closest enemy).
	assert_eq(attacker.target_enemy, target2,
			"After primary target routs, attacker should re-target next-closest enemy")

	battle.queue_free()


func test_roll_the_line_finds_next_closest_by_distance() -> void:
	# Verify that ROLL_THE_LINE re-targets the geometrically next-closest enemy,
	# not just any other enemy.
	var battle: Battle = Battle.new()
	battle.add_child(battle)
	await get_tree().process_frame

	Replay.forced_seed = 12345

	var attacker: Unit = _spawn_unit(battle, 100, 300, team=0)
	var target1: Unit = _spawn_unit(battle, 400, 300, team=1)  # Primary, will rout
	var close_target: Unit = _spawn_unit(battle, 410, 300, team=1)  # Closest (10 units away)
	var far_target: Unit = _spawn_unit(battle, 500, 300, team=1)  # Farthest (100 units away)

	# Order roll-the-line attack on target1.
	var cmd: Dictionary = {
		"units": [attacker.uid],
		"target": target1.uid,
		"x": float(target1.position.x),
		"y": float(target1.position.y),
		"mode": Battle.OrderMode.ROLL_THE_LINE,
	}
	battle._apply_order_cmd(cmd)

	# Tick forward to engage.
	for _ in range(150):
		battle._physics_process(1.0 / 60.0)

	assert_eq(attacker.target_enemy, target1, "Should target primary")

	# Rout the primary target.
	target1.morale = 0.0
	target1._rout()

	battle._physics_process(1.0 / 60.0)

	# Should re-target the closest remaining enemy (close_target).
	assert_eq(attacker.target_enemy, close_target,
			"Should re-target the closest remaining enemy, not a farther one")

	battle.queue_free()


# Helper to spawn a unit at a specific position for testing.
func _spawn_unit(battle: Battle, x: float, y: float, team: int = 0) -> Unit:
	var u: Unit = Unit.new()
	u.uid = battle._next_uid
	battle._next_uid += 1
	u.team = team
	u.position = Vector2(x, y)
	u.current_speed = Unit.JOG_SPEED
	u.state = Unit.State.IDLE
	u.morale = 100.0

	var group = "units" if u.state != Unit.State.ROUTING else "routers"
	battle.add_child(u)
	u.add_to_group(group)

	return u
