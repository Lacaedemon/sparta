extends GutTest
## An enemy soldier that has got inside a block behind its striking ranks: only the
## near-front ranks strike, so without the interior pass nobody ever strikes him. These pin
## that the block's other men within reach do, and that an enemy pressing on the rear or a
## flank from outside, or one out of everyone's reach, still is not struck by them.
## The fixtures only use API main already has, so on main they fail on their assertions.

const SEED: int = 7654321
const REACH: float = 26.0          # sword reach (1.3 m * 20)
const PITCH: float = 10.0          # fixture's own file and rank spacing, wu
const FILES: int = 4
const RANKS: int = 10
const CADENCES: int = 120


func before_each() -> void:
	Replay.rng.seed = SEED


func _unit(uid: int, team: int, n: int, pos: Vector2, face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = face
	u.training = 0.5
	u.file_major_reform = false
	u.attack_range = REACH
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	u.seed_sim_soldiers()
	return u


## A 4-file, 10-rank block at the origin facing down (+y is its front), its men laid out
## on the fixture's own grid so the geometry does not depend on the spawn spacing.
func _block() -> Unit:
	var a := _unit(1, 0, FILES * RANKS, Vector2.ZERO, Vector2.DOWN)
	var i: int = 0
	for r in range(RANKS):
		for f in range(FILES):
			a._sim_soldier_pos[i] = Vector2((f - (FILES - 1) * 0.5) * PITCH,
					((RANKS - 1) * 0.5 - r) * PITCH)
			i += 1
	return a


## Depth (along the block's front, +y) of the rearmost man of its striking set.
func _front_depth(a: Unit) -> float:
	var depth: float = INF
	for i in a.engaged_soldier_indices(a._sim_soldier_pos.size()):
		depth = minf(depth, a._sim_soldier_pos[i].y)
	return depth


func _lone_enemy_at(p: Vector2) -> Unit:
	var e := _unit(2, 1, 1, p, Vector2.UP)
	e._sim_soldier_pos[0] = p
	return e


func _nearest_striker_distance(a: Unit, p: Vector2) -> float:
	var best: float = INF
	for i in a.engaged_soldier_indices(a._sim_soldier_pos.size()):
		best = minf(best, a._sim_soldier_pos[i].distance_to(p))
	return best


func _nearest_man_distance(a: Unit, p: Vector2) -> float:
	var best: float = INF
	for q in a._sim_soldier_pos:
		best = minf(best, q.distance_to(p))
	return best


## Health the lone enemy lost over CADENCES strikes of `a` (a death counts as all of it).
func _wounds(a: Unit, e: Unit) -> float:
	var full: float = e._sim_soldier_hp[0]
	for _k in range(CADENCES):
		if e.soldiers == 0:
			return full
		a.resolve_soldier_melee(e)
	return full - (e._sim_soldier_hp[0] if e.soldiers > 0 else 0.0)


func test_men_behind_the_striking_ranks_strike_an_enemy_inside_the_block() -> void:
	var a := _block()
	var p := Vector2(0.0, _front_depth(a) - REACH - 4.0)
	assert_gt(p.y, -(RANKS - 1) * 0.5 * PITCH, "precondition: the enemy is inside, ahead of the rear rank")
	var e := _lone_enemy_at(p)
	assert_gt(_nearest_striker_distance(a, p), REACH, "precondition: no man of the striking set reaches him")
	assert_lt(_nearest_man_distance(a, p), REACH, "precondition: a man of the block reaches him")
	assert_gt(_wounds(a, e), 0.0, "the block's men around him strike the enemy inside it")


func test_an_enemy_pressing_on_the_rear_from_outside_is_not_struck_by_the_rear_ranks() -> void:
	var a := _block()
	var p := Vector2(0.0, -(RANKS - 1) * 0.5 * PITCH - 12.0)
	var e := _lone_enemy_at(p)
	assert_lt(_nearest_man_distance(a, p), REACH, "precondition: the rear rank could reach him")
	assert_gt(_nearest_striker_distance(a, p), REACH, "precondition: the striking set cannot")
	assert_eq(_wounds(a, e), 0.0, "a rear attacker outside the block keeps his edge")


func test_an_enemy_on_a_flank_from_outside_is_not_struck_by_the_inner_ranks() -> void:
	var a := _block()
	var p := Vector2((FILES - 1) * 0.5 * PITCH + 12.0, _front_depth(a) - REACH - 4.0)
	var e := _lone_enemy_at(p)
	assert_lt(_nearest_man_distance(a, p), REACH, "precondition: the outer file could reach him")
	assert_gt(_nearest_striker_distance(a, p), REACH, "precondition: the striking set cannot")
	assert_eq(_wounds(a, e), 0.0, "a flank attacker outside the block keeps his edge")


func test_an_enemy_inside_but_out_of_everyones_reach_is_not_struck() -> void:
	var a := _block()
	# Spread the block's men apart behind the striking set, so the gap between two ranks
	# is wider than a sword's reach on both sides.
	var front_depth: float = _front_depth(a)
	for i in range(a._sim_soldier_pos.size()):
		if a._sim_soldier_pos[i].y < front_depth:
			a._sim_soldier_pos[i].y -= 4.0 * REACH
	var p := Vector2(0.0, front_depth - 2.0 * REACH)
	var e := _lone_enemy_at(p)
	assert_gt(_nearest_man_distance(a, p), REACH, "precondition: nobody reaches him")
	assert_eq(_wounds(a, e), 0.0, "an interior strike still needs the striker's reach")


func test_a_striking_rank_man_strikes_once_per_cadence_when_an_enemy_is_inside() -> void:
	# An enemy just behind the striking set, within reach of men on both sides of its rear
	# edge: each man strikes at most once a cadence, so none pays more than one strike's
	# stamina.
	var a := _block()
	var p := Vector2(0.0, _front_depth(a) - 2.0)
	var e := _lone_enemy_at(p)
	e._sim_soldier_hp[0] = 1.0e6   # survives the cadence, so every pass gets its turn at him
	var before := PackedFloat32Array(a._sim_soldier_stamina)
	a.resolve_soldier_melee(e)
	var strikes: int = 0
	for i in range(before.size()):
		var spent: float = before[i] - a._sim_soldier_stamina[i]
		assert_lte(spent, SoldierCombat.KAPPA_A + 0.0001, "soldier %d struck at most once" % i)
		if spent > 0.0:
			strikes += 1
	assert_gt(strikes, 0, "the enemy behind the striking set was struck")


func test_the_footprint_margin_is_a_snapshotted_parameter_that_widens_the_box() -> void:
	var a := _block()
	assert_not_null(a.get("interior_strike_margin"), "the block carries an interior-strike margin")
	if a.get("interior_strike_margin") == null:
		return
	assert_eq(float(a.get("interior_strike_margin")), 0.0, "the default keeps the box to the men's centres")
	# Widened past the rear attacker's distance, the rear ranks count him as inside.
	a.set("interior_strike_margin", 15.0)
	var p := Vector2(0.0, -(RANKS - 1) * 0.5 * PITCH - 12.0)
	var e := _lone_enemy_at(p)
	assert_gt(_wounds(a, e), 0.0, "a widened footprint takes in the man on the rear")
	var restored := Unit.new()
	restored.apply_snapshot_dict(a.to_snapshot_dict())
	assert_eq(float(restored.get("interior_strike_margin")), 15.0, "the margin survives a snapshot round trip")
	var d := a.to_snapshot_dict()
	d.erase("interior_strike_margin")
	var older := Unit.new()
	older.apply_snapshot_dict(d)
	assert_eq(float(older.get("interior_strike_margin")), 0.0, "an older snapshot falls back to the default")
	restored.free()
	older.free()


func test_an_enemy_among_the_striking_ranks_is_left_to_them() -> void:
	# An enemy pressed in among the striking ranks is theirs: the men behind them, though in
	# reach, do not join in, so an ordinary intermixed front keeps its usual striking depth.
	var a := _block()
	var front := a.engaged_soldier_indices(a._sim_soldier_pos.size())
	var p := Vector2(0.0, _front_depth(a) + 3.0)
	var e := _lone_enemy_at(p)
	e._sim_soldier_hp[0] = 1.0e6   # survives the striking ranks' blows this cadence
	var behind_in_reach: int = 0
	for i in range(a._sim_soldier_pos.size()):
		if not front.has(i) and a._sim_soldier_pos[i].distance_to(p) <= REACH:
			behind_in_reach += 1
	assert_gt(behind_in_reach, 0, "precondition: men behind the striking set reach him")
	var before := PackedFloat32Array(a._sim_soldier_stamina)
	a.resolve_soldier_melee(e)
	for i in range(before.size()):
		if not front.has(i):
			assert_eq(a._sim_soldier_stamina[i], before[i], "soldier %d behind the striking set held his blow" % i)
