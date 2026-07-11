extends GutTest
## A charging cavalry regiment is genuinely ARRESTED by physical contact with a braced
## anti-cavalry SQUARE, not just slowed by the regiment-circle's flat hard-block rule.
## Regression guard for the "combat-only velocity" gap SoldierEnemyContact.accumulate fixes:
## before it, soldier-level bodies had no enemy-vs-enemy repulsion at all outside a landed
## strike, so nothing but the regiment circle's kinematic push_share stood between a charge
## and interpenetration. Live-battle, tick by tick, per this repo's own convention of
## verifying maneuver/collision physics against real body positions rather than eyeballing
## demo frames -- see .claude/memories/sparta.md.
##
## Team 0 (Infantry, set to SQUARE) is stationary per the repo's own default; team 1
## (Cavalry) is the enemy AI, which auto-advances and auto-targets without an explicit
## order -- mirrors demos/inputs/anti-cav-square.json's own team assignment.


var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _team_unit(team: int) -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == team:
			return unit
	return null


func test_charge_decelerates_sharply_after_contact_with_a_braced_square() -> void:
	Replay.forced_seed = 424242
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 500, "count": 120},
		{"team": 1, "type": "Cavalry", "x": 800, "y": 200},
	]
	add_child(_battle)
	await get_tree().physics_frame

	var defender: Unit = _team_unit(0)
	var charger: Unit = _team_unit(1)
	assert_not_null(defender, "the infantry defender deployed")
	assert_not_null(charger, "the cavalry charger deployed")
	if defender == null or charger == null:
		return
	defender.set_formation(Unit.FORMATION_SQUARE)

	var prev_pos: Vector2 = charger.position
	var free_charge_step: float = 0.0    # per-tick displacement while still approaching
	var settled_step: float = 0.0        # per-tick displacement once well into contact
	var contact_tick: int = -1

	for tick in range(600):
		await get_tree().physics_frame
		var step: float = prev_pos.distance_to(charger.position)
		prev_pos = charger.position
		if charger.state != Unit.State.FIGHTING:
			# Sample the free-charge rate on a tick that's clearly mid-sprint (past the
			# initial accel ramp, well before contact), so it reflects real charge speed.
			if tick > 30 and tick < 100:
				free_charge_step = maxf(free_charge_step, step)
		elif contact_tick == -1:
			contact_tick = tick

	assert_gt(contact_tick, -1, "the charge made contact with the braced square within the window")
	assert_gt(free_charge_step, 0.0, "captured a real free-charge displacement rate before contact")
	if contact_tick == -1 or free_charge_step <= 0.0:
		return

	# Re-run the last 60 ticks' worth of settled displacement isn't available after the
	# loop above already consumed them -- sample directly by continuing the same battle a
	# further half-second and measuring displacement over that window instead.
	prev_pos = charger.position
	for _k in range(30):
		await get_tree().physics_frame
	settled_step = prev_pos.distance_to(charger.position) / 30.0

	assert_lt(settled_step, free_charge_step * 0.5,
		"once settled into contact with a braced square, the charger's per-tick advance drops to well under half its free-charge rate (contact tick %d, free-charge step %.3f, settled step %.3f)"
			% [contact_tick, free_charge_step, settled_step])
