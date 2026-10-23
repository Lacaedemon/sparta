extends GutTest
## An infantry block attacking another block's flank or rear stops at that block's outer file
## or rank (MeleeFrontLine's side contact), instead of walking its front ranks deep into it.
##
## The staging: two 120-man Infantry blocks, 15 files by 8 ranks at the default 18 wu pitch, so
## each front rank stands 63 wu ahead of its centre and each end file 126 wu to its side. The
## defender (team 0) stands with its back (rear) or a flank (flank) toward the attacker
## (team 1), which is ordered to attack it. On main 2c2955cc such a pair weighs 0, so contact
## and the engaged floor are the centre-based ones: the attacker closes to the capped floor with
## dozens of men several ranks inside the defender. The battle test reads only what main
## already has, so it fails there on the measurements rather than on a missing symbol.

const SEED := 5151
const BLOCK := {"type": "Infantry", "count": 120, "frontage": 15}
const DEFENDER := Vector2(800.0, 500.0)
const ATTACKER_GAP := 330.0
# Ticks watched after the pair first reads in contact.
const WATCH_TICKS := 300
const CONTACT_BUDGET_TICKS := 600

var _battle: Node = null


func after_each() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


## Spawn the defender facing `defender_facing` and the attacker ATTACKER_GAP below it, facing
## it (up). Returns [defender, attacker].
func _start(defender_facing: Vector2) -> Array:
	Replay.forced_seed = SEED
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	var d: Dictionary = BLOCK.duplicate()
	d.merge({"team": 0, "x": DEFENDER.x, "y": DEFENDER.y,
		"facing": [defender_facing.x, defender_facing.y]})
	var a: Dictionary = BLOCK.duplicate()
	a.merge({"team": 1, "x": DEFENDER.x, "y": DEFENDER.y + ATTACKER_GAP, "facing": [0, -1]})
	_battle.scenario = [d, a]
	add_child(_battle)
	await get_tree().physics_frame
	var by_team := {}
	for u in get_tree().get_nodes_in_group("units"):
		by_team[(u as Unit).team] = u
	return [by_team.get(0), by_team.get(1)]


## How many of `enemy`'s live men stand more than one rank inside the rectangle `u`'s own live
## men cover (along and across the way they face), measured from its nearest edge, whichever
## side that is: the men a flank or rear attack should never put inside a block. The men, not
## the slots: while the defender turns about in place its slots swing but its men stand fast.
func _men_deeper_than_a_rank(u: Unit, enemy: Unit) -> int:
	var fwd: Vector2 = MeleeFrontGeometry.grid_front(u)
	var side: Vector2 = fwd.orthogonal()
	var front: float = -INF
	var rear: float = INF
	var lo: float = INF
	var hi: float = -INF
	for j in u._sim_soldier_pos.size():
		if j < u._sim_soldier_hp.size() and u._sim_soldier_hp[j] <= 0.0:
			continue
		var rel: Vector2 = u._sim_soldier_pos[j] - u.position
		front = maxf(front, rel.dot(fwd))
		rear = minf(rear, rel.dot(fwd))
		lo = minf(lo, rel.dot(side))
		hi = maxf(hi, rel.dot(side))
	var pitch: float = u.rank_pitch_wu()
	var n: int = 0
	for i in enemy._sim_soldier_pos.size():
		if i < enemy._sim_soldier_hp.size() and enemy._sim_soldier_hp[i] <= 0.0:
			continue
		var rel: Vector2 = enemy._sim_soldier_pos[i] - u.position
		var along: float = rel.dot(fwd)
		var across: float = rel.dot(side)
		var inside: float = minf(minf(front - along, along - rear), minf(across - lo, hi - across))
		if inside > pitch:
			n += 1
	return n


## Run the attack: the centre gap at first contact, and over the watch the smallest centre gap
## and the most attacker men more than a rank inside the defender.
func _attack(defender_facing: Vector2) -> Dictionary:
	var pair: Array = await _start(defender_facing)
	var d: Unit = pair[0]
	var a: Unit = pair[1]
	assert_not_null(d, "setup: the defender deployed")
	assert_not_null(a, "setup: the attacker deployed")
	if d == null or a == null:
		return {}
	a.target_enemy = d
	var out := {"contact_tick": -1, "contact_gap": -1.0, "min_gap": INF, "deep": 0,
		"defender_lost": 0, "attacker_lost": 0}
	var tick: int = 0
	while tick < CONTACT_BUDGET_TICKS + WATCH_TICKS:
		await get_tree().physics_frame
		tick += 1
		if not (is_instance_valid(a) and is_instance_valid(d)):
			break
		var gap: float = a.position.distance_to(d.position)
		if out["contact_tick"] < 0:
			if a._in_enemy_contact:
				out["contact_tick"] = tick
				out["contact_gap"] = gap
			elif tick >= CONTACT_BUDGET_TICKS:
				break
			continue
		if tick > out["contact_tick"] + WATCH_TICKS:
			break
		out["min_gap"] = minf(out["min_gap"], gap)
		out["deep"] = maxi(out["deep"], _men_deeper_than_a_rank(d, a))
	out["defender_lost"] = 120 - (d.soldiers if is_instance_valid(d) else 0)
	out["attacker_lost"] = 120 - (a.soldiers if is_instance_valid(a) else 0)
	return out


## The attacker's front rank stops on the defender's rear rank: the centres hold the two
## front-rank depths (126 wu) apart, give or take half a rank.
func test_a_rear_attack_stops_at_the_defender_rear_rank() -> void:
	var run: Dictionary = await _attack(Vector2.UP)
	if run.is_empty():
		return
	print("[side contact, rear] %s" % run)
	assert_gt(int(run["contact_tick"]), 0, "setup: the attacker came into contact")
	assert_gte(float(run["contact_gap"]), 126.0,
		"contact registers before the attacker's front rank passes the defender's rear rank")
	assert_gte(float(run["min_gap"]), 126.0 - 9.0,
		"the press stops at the rear rank (closest gap %.1f)" % run["min_gap"])
	assert_lte(int(run["deep"]), 4,
		"at most a handful of attackers ever stand more than a rank inside (%d)" % run["deep"])
	assert_gt(int(run["defender_lost"]), 0, "the attacker strikes the rear rank")


## The attacker's front rank stops on the defender's end file: the centres hold the attacker's
## front-rank depth plus the defender's front half-width (63 + 126 = 189 wu) apart.
func test_a_flank_attack_stops_at_the_defender_end_file() -> void:
	var run: Dictionary = await _attack(Vector2.LEFT)
	if run.is_empty():
		return
	print("[side contact, flank] %s" % run)
	assert_gt(int(run["contact_tick"]), 0, "setup: the attacker came into contact")
	assert_gte(float(run["contact_gap"]), 189.0,
		"contact registers before the attacker's front rank passes the defender's end file")
	assert_gte(float(run["min_gap"]), 189.0 - 9.0,
		"the press stops at the end file (closest gap %.1f)" % run["min_gap"])
	assert_lte(int(run["deep"]), 4,
		"at most a handful of attackers ever stand more than a rank inside (%d)" % run["deep"])
	assert_gt(int(run["defender_lost"]), 0, "the attacker strikes the end file")
