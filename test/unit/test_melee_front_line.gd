extends GutTest
## Two blocks fighting front to front meet at their front ranks (MeleeFrontLine), instead of
## each grid being ordered most of its depth into the other.
##
## The staging: two 120-man Infantry blocks, 15 files by 8 ranks at a 0.9 m rank pitch, so each
## front rank stands 63 wu ahead of its centre. They start 220 wu apart, centre to centre, and
## attack each other. Before the fix, contact (reach plus Unit.RADIUS a side, 62 wu) registered
## only after the front ranks had walked about 64 wu into each other, and the press then closed
## the centres to the capped engaged floor of 26 wu, with dozens of men of each block standing
## more than a rank inside the other. The battle test reads only what main already has, so it
## fails there for that reason rather than on a missing symbol.

const SEED := 4242
const BLOCK := {"type": "Infantry", "count": 120, "frontage": 15}
const TEAM0_Y := 600.0
const TEAM1_Y := 820.0
const CLASH_X := 800.0
# Ticks watched after the pair first reads in contact: the press reaches its floor in well
# under a second, and the window runs on into the casualties.
const WATCH_TICKS := 300
const CONTACT_BUDGET_TICKS := 400

var _battle: Node = null


func after_each() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


func _start() -> Array:
	Replay.forced_seed = SEED
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	var a: Dictionary = BLOCK.duplicate()
	a.merge({"team": 0, "x": CLASH_X, "y": TEAM0_Y, "facing": [0, 1]})
	var b: Dictionary = BLOCK.duplicate()
	b.merge({"team": 1, "x": CLASH_X, "y": TEAM1_Y, "facing": [0, -1]})
	_battle.scenario = [a, b]
	add_child(_battle)
	await get_tree().physics_frame
	var by_team := {}
	for u in get_tree().get_nodes_in_group("units"):
		by_team[(u as Unit).team] = u
	return [by_team.get(0), by_team.get(1)]


## The distance from `u`'s centre to its front rank on its current grid, in wu.
func _front_rank_depth(u: Unit) -> float:
	var files: int = maxi(1, u.formation_files(u.soldiers))
	var ranks: int = UnitFormation.ranks_for(u.soldiers, files)
	return float(maxi(0, ranks - 1)) * 0.5 * u.rank_pitch_wu()


## How many of `enemy`'s live men stand more than one rank behind `u`'s ordered front rank,
## between its outermost files: the men an ordinary frontal melee should never put inside a
## block.
func _men_deeper_than_a_rank(u: Unit, enemy: Unit) -> int:
	var fwd: Vector2 = u.facing
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	var front: float = -INF
	var rear: float = INF
	var lo: float = INF
	var hi: float = -INF
	for s in u.soldier_world_slots(u.soldiers):
		var rel: Vector2 = s - u.position
		front = maxf(front, rel.dot(fwd))
		rear = minf(rear, rel.dot(fwd))
		lo = minf(lo, rel.dot(side))
		hi = maxf(hi, rel.dot(side))
	var n: int = 0
	for i in enemy._sim_soldier_pos.size():
		if i < enemy._sim_soldier_hp.size() and enemy._sim_soldier_hp[i] <= 0.0:
			continue
		var rel: Vector2 = enemy._sim_soldier_pos[i] - u.position
		var depth: float = rel.dot(fwd)
		var lateral: float = rel.dot(side)
		if depth < front - u.rank_pitch_wu() and depth >= rear and lateral >= lo and lateral <= hi:
			n += 1
	return n


## Run the clash with `scale` written to both units' melee_front_line_scale (no field on a tree
## that lacks it): the centre gap when the pair first reads in contact, and, over the watch,
## the smallest centre gap and the most enemy men either block has more than a rank inside it.
func _clash(scale: float = -1.0) -> Dictionary:
	var pair: Array = await _start()
	var a: Unit = pair[0]
	var b: Unit = pair[1]
	assert_not_null(a, "setup: team 0 deployed")
	assert_not_null(b, "setup: team 1 deployed")
	if a == null or b == null:
		return {}
	if scale >= 0.0:
		a.set("melee_front_line_scale", scale)
		b.set("melee_front_line_scale", scale)
	a.target_enemy = b
	b.target_enemy = a
	var out := {"contact_tick": -1, "contact_gap": -1.0, "min_gap": INF, "deep": 0,
		"fighting_tick": -1, "fronts": _front_rank_depth(a) + _front_rank_depth(b),
		"reach": maxf(a.attack_range, b.attack_range)}
	var tick: int = 0
	while tick < CONTACT_BUDGET_TICKS + WATCH_TICKS:
		await get_tree().physics_frame
		tick += 1
		if not (is_instance_valid(a) and is_instance_valid(b)):
			break
		var gap: float = a.position.distance_to(b.position)
		if out["contact_tick"] < 0:
			if a._in_enemy_contact and b._in_enemy_contact:
				out["contact_tick"] = tick
				out["contact_gap"] = gap
			elif tick >= CONTACT_BUDGET_TICKS:
				break
			continue
		if tick > out["contact_tick"] + WATCH_TICKS:
			break
		out["min_gap"] = minf(out["min_gap"], gap)
		if out["fighting_tick"] < 0 and a.state == Unit.State.FIGHTING \
				and b.state == Unit.State.FIGHTING:
			out["fighting_tick"] = tick
		var deep: int = maxi(_men_deeper_than_a_rank(a, b), _men_deeper_than_a_rank(b, a))
		out["deep"] = maxi(out["deep"], deep)
	out["men"] = (a.soldiers if is_instance_valid(a) else 0) + (b.soldiers if is_instance_valid(b) else 0)
	return out


func test_frontal_blocks_meet_at_their_front_ranks() -> void:
	var run: Dictionary = await _clash()
	if run.is_empty():
		return
	print("[front line] %s" % run)
	assert_gt(int(run["contact_tick"]), 0, "setup: the blocks came into contact")
	var fronts: float = run["fronts"]
	# Contact starts before the front ranks pass each other: the centres are still at least the
	# two front depths apart.
	assert_gte(float(run["contact_gap"]), fronts,
		"contact registers before the front ranks overlap (gap %.1f, front depths %.1f)"
			% [run["contact_gap"], fronts])
	# ...and no sooner than the front ranks come within weapon reach: an extension that
	# overshot would put the blocks in contact with empty air between them.
	assert_lte(float(run["contact_gap"]), fronts + float(run["reach"]) + 1.0,
		"contact registers only within reach of the front ranks (gap %.1f, reach %.1f)"
			% [run["contact_gap"], run["reach"]])
	# Both blocks fight as soon as they are in contact, rather than going on closing until the
	# centre-based range is reached. Measured: 1 tick here; with the extension left out of
	# _think's own contact test they never fight inside the watch.
	assert_between(int(run["fighting_tick"]) - int(run["contact_tick"]), 0, 30,
		"both blocks fight within half a second of contact (contact %d, fighting %d)"
			% [run["contact_tick"], run["fighting_tick"]])
	# The press stops with the front ranks on one line: the centres never close more than half a
	# rank (9 wu) past the two front depths. Without the engaged floor's extension the body
	# contact alone lets them close to 110.5 here.
	assert_gte(float(run["min_gap"]), fronts - 9.0,
		"the press stops at the front line (closest gap %.1f, front depths %.1f)"
			% [run["min_gap"], fronts])
	# ...and does close to it, rather than holding the blocks apart past the front line.
	assert_lte(float(run["min_gap"]), fronts + 9.0,
		"the press closes to the front line (closest gap %.1f)" % run["min_gap"])
	# The front ranks reach each other: men fall on the watch.
	assert_lt(int(run["men"]), 240, "the front ranks trade blows (%d men left)" % run["men"])
	# Measured: 0 here, 75 on main a3714751 and with the scale at 0.
	assert_lte(int(run["deep"]), 4,
		"at most a handful of enemy men ever stand more than a rank inside a block (%d)"
			% run["deep"])


func test_a_scale_of_zero_keeps_the_centre_based_ranges() -> void:
	var run: Dictionary = await _clash(0.0)
	if run.is_empty():
		return
	print("[front line, scale 0] %s" % run)
	assert_gt(int(run["contact_tick"]), 0, "setup: the blocks came into contact")
	# With the extension off the blocks interpenetrate as they did before it: contact only once
	# the fronts overlap, and the press then closes the centres to the capped floor. Measured:
	# contact at a 59.2 wu gap against front depths of 126, and 75 men more than a rank inside.
	assert_lt(float(run["contact_gap"]), float(run["fronts"]),
		"with scale 0, contact registers only after the fronts overlap")
	assert_gt(int(run["deep"]), 20, "with scale 0, dozens of enemy men stand more than a rank inside")
