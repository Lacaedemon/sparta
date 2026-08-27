extends GutTest
## Disengage with sacrifice's rearguard: a live-Battle proof that the sacrificed
## soldiers become a genuine, separate Unit -- spawned, fighting for real, eventually
## removed -- rather than the earlier flat pursuit-speed multiplier. The Unit-level
## contract (disengage_with_sacrifice's own return value, the retreating unit's own state)
## is covered in test_disengage_with_sacrifice_maneuver.gd; this file is the end-to-end
## wiring through Battle._apply_order_cmd and Battle._spawn_rearguard_detachment.

const BattleScript = preload("res://scripts/Battle.gd")

const SPAWN := Vector2(500, 470)


func after_each() -> void:
	Replay.forced_seed = -1


func _spawn(scenario: Array) -> Node:
	# Deterministic battle seed: Battle._ready() runs Replay.start_recording(),
	# which seeds the shared combat RNG from forced_seed (a plain rng.seed set
	# here would be clobbered by that same call). Pinning it makes each test's
	# battle play the same rolls on every run -- the pursuer-blocked proof below
	# samples real combat outcomes, which are otherwise a fresh random draw per
	# spawn (the same convention test_battle_ai_general.gd uses).
	Replay.forced_seed = 12345
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


## The decisive proof: the pursuer is blocked because it is genuinely fighting a real,
## separate rearguard Unit -- not because of any multiplier, and not merely because two
## already-interpenetrated soldier blocks take a while to physically separate after a
## clash (that alone looks identical whether or not a rearguard exists: stubbing the spawn
## out entirely still left the pursuer reading FIGHTING, near-stationary, and in genuine
## soldier-level contact for most of a fixed sampling window -- the old single-sample and
## whole-window forms of this test both passed on that stubbed build). Asserting on two
## observables that only a real, separate rearguard Unit can produce fixes that: the
## pursuer's own combat target becomes the rearguard (an object-identity check, not a
## state flag or a distance heuristic -- with no rearguard object, it can never be true),
## and the rearguard's own headcount drops from real per-soldier melee casualties (not
## fakeable without a Unit that actually has soldiers to lose).
##
## The dispatch path gives the rearguard the default ~2s lifetime, so the whole proof has
## to happen while that timer runs -- which means the sacrifice must be ordered at MUTUAL
## engagement, not at a fixed early tick. Under the rebalanced close-order density the
## pursuer's own FIGHTING latch lands around tick 31 (the main body latches on tick 1-2;
## the gap is think cadence, not geometry -- it is unchanged at 40/50/60 wu separations),
## so a fixed tick-20 order fires while the pursuer is still IDLE and the pursuit then
## never reaches the rearguard before it expires. Waiting for both latches keeps the
## staging premise ("a clash close enough that the two sides are already engaged") true at
## any pace, and the tick budgets below are derived from Replay.PHYSICS_TPS (seconds, not
## bare tick counts) so a small change to sim pacing (e.g. a soldier body-speed retune)
## doesn't need these literals re-pinned.
func test_pursuer_is_physically_blocked_by_the_rearguard_while_the_main_body_escapes_free() -> void:
	var battle := _spawn(_clash_scenario())
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
	var engage_deadline: int = int(5 * Replay.PHYSICS_TPS)
	while battle.current_tick() < engage_deadline \
			and not (main_body.state == Unit.State.FIGHTING
					and pursuer.state == Unit.State.FIGHTING):
		await get_tree().physics_frame
	assert_eq(main_body.state, Unit.State.FIGHTING, "sanity: the main body engaged")
	assert_eq(pursuer.state, Unit.State.FIGHTING, "sanity: the pursuer engaged too")
	var pursuer_start: Vector2 = pursuer.position

	battle.enqueue_disengage_with_sacrifice([main_body.uid])
	await get_tree().physics_frame

	# Find the rearguard itself -- fail fast and legibly if the spawn never happened,
	# instead of letting the tracking loop below fall through with nothing to track (which
	# is exactly how the previous version's asserts stayed silently satisfied on a stubbed
	# spawn: a loop that never finds a rearguard contributes no evidence either way).
	var rearguard: Unit = null
	var post_order_units := _units_by_uid(battle)
	for uid in post_order_units:
		var u: Unit = post_order_units[uid]
		if u.is_rearguard_detachment:
			rearguard = u
			break
	assert_not_null(rearguard,
			"a real, separate rearguard Unit was spawned to hold the point of contact")
	if rearguard == null:
		return
	var rearguard_uid: int = rearguard.uid
	var initial_rearguard_soldiers: int = rearguard.soldiers

	# Track across the rearguard's whole lifetime (measured ~120 ticks from the dispatch
	# default; capped well past it in case a retune lengthens it). Measured under the
	# rebalanced density with Replay.forced_seed pinned: the pursuer's own target_enemy
	# stays on the (by-then-distant) main body for roughly the first two-thirds of this
	# window -- soldier bodies take time to physically separate, so contact alone isn't
	# proof -- then commits to the rearguard once the pursuit closes back on it, and a
	# rearguard casualty follows shortly after.
	var pursuer_targeted_rearguard: bool = false
	var rearguard_took_casualties: bool = false
	var worst_advance: float = 0.0
	var deadline: int = battle.current_tick() + int(4 * Replay.PHYSICS_TPS)
	while battle.current_tick() < deadline:
		await get_tree().physics_frame
		if not is_instance_valid(pursuer):
			break   # freed mid-window; the asserts below judge what was tracked so far
		if not is_instance_valid(rearguard):
			break   # destroyed or timed out -- the proof window is over
		if pursuer.target_enemy == rearguard:
			pursuer_targeted_rearguard = true
		if rearguard.soldiers < initial_rearguard_soldiers:
			rearguard_took_casualties = true
		worst_advance = maxf(worst_advance,
				pursuer.position.distance_to(pursuer_start))

	assert_true(pursuer_targeted_rearguard,
			"the pursuer's own combat target became the rearguard Unit itself -- a real," \
			+ " separate Unit it actually fought, not a state flag or a distance" \
			+ " coincidence with the retreating main body")
	assert_true(rearguard_took_casualties,
			("the rearguard (uid %d, started with %d soldiers) took real melee" \
			+ " casualties -- something with its own body count actually fought back") \
			% [rearguard_uid, initial_rearguard_soldiers])
	assert_lt(worst_advance, 40.0,
			("and never advanced far from where the clash started while the rearguard" \
			+ " lived (worst %.1f wu) -- blocked, not slowed by a multiplier while" \
			+ " still closing the distance") % worst_advance)
	assert_ne(main_body.state, Unit.State.FIGHTING,
			"meanwhile the main body itself is no longer in that fight -- it got away")
