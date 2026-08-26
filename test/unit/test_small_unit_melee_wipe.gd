extends GutTest
## Opening melee of a small close-tier clash must resolve per-soldier, not through the
## regiment damage formula. That formula subtracts an absolute soldier count calibrated
## for a full regiment, so a 10-man cavalry unit vanished in one tick at regiment-circle
## range -- often a rear or deep-formation contact whose facing-front ranks were out of
## weapon reach -- while the other side took no losses. These pin the two ingredients of
## the fix: the opening blow takes the per-soldier path (FIGHTING counts as engaged),
## and a hit can land on whichever living soldiers are actually in reach, not only the
## defender's facing-front engaged selection.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")
const SEED: int = 40002
## Ticks for the issue's 10-cavalry vs 10-cavalry AI-close to enter FIGHTING. The
## enemy marches from 150 wu; regiment-circle contact is ~66 wu. Budgeted with room.
const FIRST_CONTACT_BUDGET: int = 400
## After contact, a few seconds of grinding must produce SOME wound -- not a 10-man
## wipe, and not a silent stall with full HP on both sides.
const POST_CONTACT_BUDGET: int = 180


func before_each() -> void:
	Replay.rng.seed = SEED


func _min_hp(u: Unit) -> float:
	if u._sim_soldier_hp.is_empty():
		return 0.0
	var lowest: float = u._sim_soldier_hp[0]
	for i in range(1, u._sim_soldier_hp.size()):
		lowest = minf(lowest, u._sim_soldier_hp[i])
	return lowest


func _cavalry(uid: int, team: int, n: int, pos: Vector2, face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = face
	u.is_cavalry = true
	u.attack = 16
	u.defense = 5
	u.attack_range = 1.5 * WorldScaleRef.WU_PER_M
	u.file_pitch = 1.0 * WorldScaleRef.WU_PER_M
	u.rank_pitch = 3.0 * WorldScaleRef.WU_PER_M
	u.file_major_reform = false
	u.seed_sim_soldiers()
	return u


# --- opening blow is per-soldier, not a regiment-formula wipe ----------------

func test_opening_strike_does_not_wipe_a_small_cavalry_unit() -> void:
	# Attacker has just entered FIGHTING (linger not armed -- the opening-tick hole);
	# defender has not thought yet. Pre-fix, strike() fell through to the formula and
	# deleted the whole 10-man roster (cavalry 16-vs-5 is about 7-15 men, so a low
	# roll can leave a handful of survivors -- soldiers > 0 would still pass). Both
	# have a soldier layer, so the blow must resolve per-soldier: one cadence against
	# full-HP cavalry does not delete a man.
	var attacker := _cavalry(1, 0, 10, Vector2(0, -66), Vector2.DOWN)
	attacker.state = Unit.State.FIGHTING
	var defender := _cavalry(2, 1, 10, Vector2(0, 0), Vector2.DOWN)
	assert_true(attacker.is_engaged(), "FIGHTING counts as engaged on the opening tick")
	assert_false(defender.is_engaged(), "the defender has not entered FIGHTING yet")
	UnitCombat.strike(attacker, defender)
	assert_eq(defender.soldiers, 10, "a 10-man cavalry unit keeps its roster through the opening blow")
	assert_eq(attacker.soldiers, 10, "the attacker is not deleted either")


func test_rear_contact_wounds_soldiers_actually_in_reach() -> void:
	# Same facing, attacker approaching from behind: the defender's facing-front rank
	# sits a mounted rank-pitch on the far side of the horse, outside spatha reach.
	# Hitting "the engaged front" would land no wounds; hitting whoever is nearest
	# must draw blood over a few cadences without annihilating the block.
	var attacker := _cavalry(1, 0, 10, Vector2(0, -50), Vector2.DOWN)
	attacker.state = Unit.State.FIGHTING
	attacker.tick_engaged(0.1)
	var defender := _cavalry(2, 1, 10, Vector2(0, 0), Vector2.DOWN)
	defender.state = Unit.State.FIGHTING
	defender.tick_engaged(0.1)
	var full: float = _min_hp(defender)
	for _k in range(24):
		UnitCombat.strike(attacker, defender)
		if _min_hp(defender) < full - 0.01:
			break
	assert_lt(_min_hp(defender), full - 0.01,
		"a rear blow wounds soldiers who are actually in reach")
	assert_gt(defender.soldiers, 0, "without wiping the 10-man unit in the process")


# --- live Battle: the issue's own 10v10 cavalry close ------------------------

func test_issue_repro_does_not_one_tick_wipe_at_regiment_range() -> void:
	Replay.forced_seed = SEED
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true   # set before add_child so _check_victory cannot pause the tree
	battle.terrain = []
	battle.scenario = [
		{"team": 0, "type": "Cavalry", "x": 500, "y": 400, "count": 10},
		{"team": 1, "type": "Cavalry", "x": 500, "y": 250, "count": 10},
	]
	add_child_autofree(battle)

	var player: Unit = null
	var enemy: Unit = null
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u == null:
			continue
		if u.team == 0:
			player = u
		else:
			enemy = u
	assert_not_null(player, "the scenario spawns the player cavalry")
	assert_not_null(enemy, "and the enemy cavalry")
	if player == null or enemy == null:
		return

	while battle.current_tick() < FIRST_CONTACT_BUDGET \
			and player.state != Unit.State.FIGHTING \
			and enemy.state != Unit.State.FIGHTING \
			and is_instance_valid(player) and is_instance_valid(enemy) \
			and player.soldiers > 0 and enemy.soldiers > 0:
		await get_tree().physics_frame

	assert_true(is_instance_valid(player) and is_instance_valid(enemy),
		"both regiments are still on the field at first contact")
	if not (is_instance_valid(player) and is_instance_valid(enemy)):
		return
	assert_gt(player.soldiers, 0, "the player unit is not annihilated on contact")
	assert_gt(enemy.soldiers, 0, "the enemy unit is not annihilated on contact")
	var gap: float = player.position.distance_to(enemy.position)
	# The reported wipe sat at ~65-70 wu (regiment-circle contact). Surviving that
	# tick with both rosters intact is the bug. They may close further afterward.
	assert_gt(player.soldiers + enemy.soldiers, 10,
		"contact at gap %.1f does not leave one side as a lone full-strength survivor" % gap)

	var start_hp_p: float = _min_hp(player)
	var start_hp_e: float = _min_hp(enemy)
	var start_count_p: int = player.soldiers
	var start_count_e: int = enemy.soldiers
	var deadline: int = battle.current_tick() + POST_CONTACT_BUDGET
	while battle.current_tick() < deadline \
			and is_instance_valid(player) and is_instance_valid(enemy) \
			and player.soldiers == start_count_p and enemy.soldiers == start_count_e \
			and _min_hp(player) >= start_hp_p - 0.01 and _min_hp(enemy) >= start_hp_e - 0.01:
		await get_tree().physics_frame

	assert_true(is_instance_valid(player) and is_instance_valid(enemy),
		"neither side is deleted during the post-contact grind")
	if not (is_instance_valid(player) and is_instance_valid(enemy)):
		return
	var wounded: bool = _min_hp(player) < start_hp_p - 0.01 \
			or _min_hp(enemy) < start_hp_e - 0.01 \
			or player.soldiers < start_count_p or enemy.soldiers < start_count_e
	assert_true(wounded, "once in contact, per-soldier melee actually lands wounds")
	assert_gt(player.soldiers, 0, "the player unit still has men after the grind")
	assert_gt(enemy.soldiers, 0, "the enemy unit still has men after the grind")


# --- engaged-indices cache must miss when FIGHTING starts on the same tick ----

func test_engaged_indices_cache_misses_when_fighting_starts_same_tick() -> void:
	# Render / idle callers populate the (frame, count) cache with an empty set while
	# the unit is still idle. The opening blow of a fresh contact then enters FIGHTING
	# later in the SAME physics frame. The cache key includes the engaged bit so that
	# strike does not reuse the idle empty set.
	var u := _cavalry(1, 0, 10, Vector2.ZERO, Vector2.DOWN)
	var n: int = u._sim_soldier_pos.size()
	var idle: PackedInt32Array = u.engaged_soldier_indices(n)
	assert_eq(idle.size(), 0, "idle: no engaged selection")
	u.state = Unit.State.FIGHTING
	var fighting: PackedInt32Array = u.engaged_soldier_indices(n)
	assert_gt(fighting.size(), 0,
		"FIGHTING on the same physics tick does not reuse the idle empty cache")
