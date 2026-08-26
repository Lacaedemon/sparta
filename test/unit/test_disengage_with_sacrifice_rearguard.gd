extends GutTest
## Disengage with sacrifice's rearguard: a live-Battle proof that the sacrificed
## soldiers become a genuine, separate Unit -- spawned, fighting for real, eventually
## removed -- rather than the earlier flat pursuit-speed multiplier. The Unit-level
## contract (disengage_with_sacrifice's own return value, the retreating unit's own state)
## is covered in test_disengage_with_sacrifice_maneuver.gd; this file is the end-to-end
## wiring through Battle._apply_order_cmd and Battle._spawn_rearguard_detachment.

const BattleScript = preload("res://scripts/Battle.gd")

const SPAWN := Vector2(500, 470)


func _spawn(scenario: Array) -> Node:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	battle.scenario = scenario
	add_child_autofree(battle)
	return battle


func _units_by_uid(battle: Node) -> Dictionary:
	var out: Dictionary = {}
	for group in ["units", "routers"]:
		for node in get_tree().get_nodes_in_group(group):
			var u: Unit = node as Unit
			if u != null:
				out[u.uid] = u
	return out


## A clash close enough that the two sides are already engaged (target_enemy set,
## state FIGHTING) within a handful of ticks -- disengage_with_sacrifice only acts on a
## FIGHTING unit.
func _clash_scenario() -> Array:
	return [
		{"team": 0, "type": "Infantry", "x": SPAWN.x, "y": SPAWN.y, "count": 100,
				"facing": [0, 1], "formation": Unit.FORMATION_TIGHT},
		{"team": 1, "type": "Infantry", "x": SPAWN.x, "y": SPAWN.y + 60, "count": 100,
				"facing": [0, -1], "formation": Unit.FORMATION_TIGHT},
	]


func test_disengage_with_sacrifice_spawns_a_real_rearguard_unit() -> void:
	var battle := _spawn(_clash_scenario())
	while battle.current_tick() < 20:
		await get_tree().physics_frame
	var units := _units_by_uid(battle)
	var main_body: Unit = null
	for uid in units:
		if units[uid].team == 0:
			main_body = units[uid]
			break
	assert_not_null(main_body, "the team-0 unit engaged")
	if main_body == null:
		return
	assert_eq(main_body.state, Unit.State.FIGHTING, "sanity: the two sides are engaged")
	var before_soldiers: int = main_body.soldiers
	var before_uid_count: int = units.size()

	battle.enqueue_disengage_with_sacrifice([main_body.uid])

	var after := _units_by_uid(battle)
	assert_eq(after.size(), before_uid_count + 1,
			"a genuine new Unit exists -- not just a state flag on the retreating one")
	assert_lt(main_body.soldiers, before_soldiers,
			"the retreating unit's own headcount dropped by the sacrifice")

	var rearguard: Unit = null
	for uid in after:
		if uid != main_body.uid and after[uid].team == main_body.team:
			rearguard = after[uid]
			break
	assert_not_null(rearguard, "the new unit shares the parent's team")
	if rearguard == null:
		return
	assert_true(rearguard.is_rearguard_detachment, "flagged as a rearguard detachment")
	assert_eq(rearguard.soldiers, before_soldiers - main_body.soldiers,
			"holds exactly the sacrificed headcount")
	assert_almost_eq(rearguard.position.x, main_body.position.x, 0.5,
			"spawns at the point of contact, not wherever the main body ends up")
	assert_almost_eq(rearguard.position.y, main_body.position.y, 0.5)
	assert_eq(rearguard.order_mode, BattleScript.OrderMode.HOLD, "never chases")
	assert_eq(rearguard.state, Unit.State.FIGHTING, "spawns already fighting, not idle")


func test_rearguard_is_removed_after_its_lifetime_if_not_destroyed_first() -> void:
	# A lone rearguard with no enemy nearby: nothing kills it in real combat, so only the
	# timeout should remove it.
	var battle := _spawn([
		{"team": 0, "type": "Infantry", "x": SPAWN.x, "y": SPAWN.y, "count": 100, "facing": [0, 1]},
	])
	battle.drill_mode = true
	while battle.current_tick() < 5:
		await get_tree().physics_frame
	var units := _units_by_uid(battle)
	var main_body: Unit = units.values()[0]
	# _spawn_rearguard_detachment has no FIGHTING/target_enemy guard of its own -- that
	# guard lives on disengage_with_sacrifice, already covered by
	# test_disengage_with_sacrifice_maneuver.gd -- so this test drives the spawn function
	# directly to isolate the timeout-removal behaviour from the order-dispatch guard.
	var rearguard: Unit = battle._spawn_rearguard_detachment(main_body, 10, 0.2)

	assert_true(is_instance_valid(rearguard), "spawned and alive")
	var deadline: int = battle.current_tick() + 60   # well past 0.2s at 60 ticks/s
	while is_instance_valid(rearguard) and rearguard.state != Unit.State.DEAD \
			and battle.current_tick() < deadline:
		await get_tree().physics_frame

	assert_true(not is_instance_valid(rearguard) or rearguard.state == Unit.State.DEAD,
			"removed once its lifetime timer expires, with nothing left to kill it first")


func test_rearguard_round_trips_through_snapshot_restore() -> void:
	var battle := _spawn(_clash_scenario())
	while battle.current_tick() < 20:
		await get_tree().physics_frame
	var before := _units_by_uid(battle)
	var main_body: Unit = null
	for uid in before:
		if before[uid].team == 0:
			main_body = before[uid]
			break
	if main_body == null:
		fail_test("no team-0 unit found")
		return
	battle.enqueue_disengage_with_sacrifice([main_body.uid])

	var after_spawn := _units_by_uid(battle)
	var rearguard_uid: int = -1
	for uid in after_spawn:
		if after_spawn[uid].is_rearguard_detachment:
			rearguard_uid = uid
			break
	assert_ne(rearguard_uid, -1, "sanity: a rearguard was spawned")

	var snap: Dictionary = battle.capture_snapshot()
	while battle.current_tick() < 60:
		await get_tree().physics_frame   # let state diverge before restoring

	battle.restore_snapshot(snap)

	var restored := _units_by_uid(battle)
	assert_true(restored.has(rearguard_uid), "the rearguard survives a snapshot round-trip")
	if restored.has(rearguard_uid):
		assert_true(restored[rearguard_uid].is_rearguard_detachment,
				"and keeps its rearguard identity after the restore")


## The decisive proof: the pursuer is slowed because it is genuinely blocked and fighting a
## real Unit, not because of any multiplier. Give the rearguard a long lifetime (well past
## this test's own window) so only real combat, not the timeout, can end the engagement.
func test_pursuer_is_physically_blocked_by_the_rearguard_while_the_main_body_escapes_free() -> void:
	var battle := _spawn(_clash_scenario())
	while battle.current_tick() < 20:
		await get_tree().physics_frame
	var units := _units_by_uid(battle)
	var main_body: Unit = null
	var pursuer: Unit = null
	for uid in units:
		if units[uid].team == 0:
			main_body = units[uid]
		else:
			pursuer = units[uid]
	assert_not_null(main_body, "team-0 unit found")
	assert_not_null(pursuer, "team-1 unit found")
	if main_body == null or pursuer == null:
		return
	var pursuer_start: Vector2 = pursuer.position

	battle.enqueue_disengage_with_sacrifice([main_body.uid])
	for _k in range(90):   # 1.5s -- long enough for contact/engagement to settle
		await get_tree().physics_frame

	assert_eq(pursuer.state, Unit.State.FIGHTING,
			"the pursuer is still fighting -- something real is in its way")
	assert_lt(pursuer.position.distance_to(pursuer_start), 40.0,
			"and hasn't advanced far from where the clash started -- it's blocked, not slowed" \
			+ " by a multiplier while still closing the distance")
	assert_ne(main_body.state, Unit.State.FIGHTING,
			"meanwhile the main body itself is no longer in that fight -- it got away")
