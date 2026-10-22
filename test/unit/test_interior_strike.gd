extends GutTest
## An enemy soldier that has got inside a block behind its striking ranks: only the
## near-front ranks strike, so without the interior pass nobody ever strikes him. These pin
## that the block's other men within reach do, that an enemy block pressing into its rear is
## struck by the rear ranks it has pressed in among, and that an enemy pressing on the rear or
## a flank from outside, or one out of everyone's reach, still is not struck by them.
## On main 2c2955cc this script does not load at all: it names SoldierInteriorStrike and
## Unit.near_front_forward, which main lacks, so GDScript rejects it with a parse error and
## none of its tests runs.

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
## on the fixture's own grid so the geometry does not depend on the spawn spacing. The unit
## is given that grid's file count and pitches, which its footprint is measured by.
func _block() -> Unit:
	var a := _unit(1, 0, FILES * RANKS, Vector2.ZERO, Vector2.DOWN)
	a.frontage_override = FILES
	a.file_pitch = PITCH / a.spacing_scale
	a.rank_pitch = PITCH / a.spacing_scale
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


func test_a_block_pressed_into_the_rear_is_struck_by_the_rear_ranks_it_presses_among() -> void:
	# A 4-file, 3-rank enemy block attacking the rear, its front rank pressed two ranks in past
	# the block's rear rank, as two deep blocks settle in a rear fight. The block's striking set
	# faces the other way, but its rear ranks have the enemy's leading men among them and strike
	# back; the enemy's last rank, still outside the grid, is left alone. So a rear attack does
	# not keep its edge once it presses in (website/tactics.qmd gives the measured figures).
	var a := _block()
	var rear_rank: float = -(RANKS - 1) * 0.5 * PITCH
	var e := _unit(2, 1, FILES * 3, Vector2(0.0, rear_rank + PITCH), Vector2.UP)
	var k: int = 0
	for r in range(3):
		for f in range(FILES):
			# Half a pitch off the block's ranks, so each sits between two of its men.
			e._sim_soldier_pos[k] = Vector2((f - (FILES - 1) * 0.5) * PITCH,
					rear_rank + 1.5 * PITCH - PITCH * r)
			k += 1
	var front := a.engaged_soldier_indices(a._sim_soldier_pos.size())
	for i in range(e._sim_soldier_pos.size()):
		assert_gt(_nearest_striker_distance(a, e._sim_soldier_pos[i]), REACH,
				"precondition: the striking set cannot reach enemy soldier %d" % i)
	var defenders: Array[Unit] = [e]
	var indices: Array[PackedInt32Array] = [PackedInt32Array(range(e._sim_soldier_pos.size()))]
	var found: Array[PackedInt32Array] = SoldierInteriorStrike.inside_candidates(a, front, defenders, indices)
	assert_eq(found.size(), 1, "somebody of the enemy block is inside")
	var inside: PackedInt32Array = found[0] if found.size() == 1 else PackedInt32Array()
	for i in range(e._sim_soldier_pos.size()):
		var in_grid: bool = e._sim_soldier_pos[i].y >= rear_rank
		assert_eq(inside.has(i), in_grid, "enemy soldier %d counts as inside exactly when he is past the rear rank" % i)
	var hp_before: float = 0.0
	for h in e._sim_soldier_hp:
		hp_before += h
	var stam := PackedFloat32Array(a._sim_soldier_stamina)
	a.resolve_soldier_melee(e)
	var behind_strikes: int = 0
	for i in range(stam.size()):
		if not front.has(i) and a._sim_soldier_stamina[i] < stam[i]:
			behind_strikes += 1
	var hp_after: float = 0.0
	for h in e._sim_soldier_hp:
		hp_after += maxf(h, 0.0)
	assert_gt(behind_strikes, 0, "the rear ranks strike the enemy pressed in among them")
	assert_lt(hp_after, hp_before, "the enemy pressed into the rear takes wounds")


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
	var front := a.engaged_soldier_indices(a._sim_soldier_pos.size())
	var strikes: int = 0
	var behind_strikes: int = 0
	for i in range(before.size()):
		var spent: float = before[i] - a._sim_soldier_stamina[i]
		assert_lte(spent, SoldierCombat.KAPPA_A + 0.0001, "soldier %d struck at most once" % i)
		if spent > 0.0:
			strikes += 1
			if not front.has(i):
				behind_strikes += 1
	assert_gt(strikes, 0, "the enemy behind the striking set was struck")
	assert_gt(behind_strikes, 0, "men behind the striking set joined in")


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


func test_a_routing_enemy_inside_the_block_is_left_to_the_striking_ranks() -> void:
	# A router overrun by the block is the pursuit's: the interior pass leaves him alone.
	var a := _block()
	var p := Vector2(0.0, _front_depth(a) - REACH - 4.0)
	var e := _lone_enemy_at(p)
	var front := a.engaged_soldier_indices(a._sim_soldier_pos.size())
	var defenders: Array[Unit] = [e]
	var indices: Array[PackedInt32Array] = [PackedInt32Array([0])]
	assert_false(SoldierInteriorStrike.inside_candidates(a, front, defenders, indices).is_empty(),
			"precondition: while he fights he counts as inside")
	e.state = Unit.State.ROUTING
	assert_true(SoldierInteriorStrike.inside_candidates(a, front, defenders, indices).is_empty(),
			"a routing enemy is never inside")
	assert_eq(_wounds(a, e), 0.0, "nobody behind the striking set strikes the router")


func test_a_routing_block_has_no_interior_pass() -> void:
	var a := _block()
	var p := Vector2(0.0, _front_depth(a) - REACH - 4.0)
	var e := _lone_enemy_at(p)
	var front := a.engaged_soldier_indices(a._sim_soldier_pos.size())
	var defenders: Array[Unit] = [e]
	var indices: Array[PackedInt32Array] = [PackedInt32Array([0])]
	assert_false(SoldierInteriorStrike.inside_candidates(a, front, defenders, indices).is_empty(),
			"precondition: while the block fights the enemy counts as inside")
	a.state = Unit.State.ROUTING
	assert_true(SoldierInteriorStrike.inside_candidates(a, front, defenders, indices).is_empty(),
			"a routing block finds nobody inside it")


## Health the lone enemy at `p` would lose to `a`, after checking he stands outside the
## block's grid, within reach of one of its men and out of reach of its striking set.
func _wounds_outside(a: Unit, p: Vector2, what: String) -> float:
	var e := _lone_enemy_at(p)
	assert_lt(_nearest_man_distance(a, p), REACH, "precondition: a man of the block reaches him " + what)
	assert_gt(_nearest_striker_distance(a, p), REACH, "precondition: the striking set cannot " + what)
	return _wounds(a, e)


func test_a_block_turning_in_place_does_not_take_in_an_enemy_off_its_flank() -> void:
	# Mid-turn the heading has swung 45 degrees while the men still stand on the old grid. The
	# men's extremes along the new heading would bound a diamond reaching far past the grid's
	# flank; the footprint keeps to the grid the men stand on.
	var a := _block()
	a._engage_turn_start_facing = Vector2.DOWN
	a._engage_turn_target = Vector2.DOWN.rotated(deg_to_rad(90.0))
	a.facing = Vector2.DOWN.rotated(deg_to_rad(45.0))
	var p := Vector2(-(FILES - 1) * 0.5 * PITCH - 12.0, -20.0)
	assert_lt((p - a.position).dot(a.near_front_forward()), _front_depth_along(a),
			"precondition: he is behind the striking set along the new heading")
	assert_eq(_wounds_outside(a, p, "off the flank"), 0.0, "a flank attacker outside the turning block keeps his edge")


## The block of the turning tests, mid-turn: its heading has swung 45 degrees while its men
## still stand on the old grid, which faces down.
func _turning_block() -> Unit:
	var a := _block()
	a._engage_turn_start_facing = Vector2.DOWN
	a._engage_turn_target = Vector2.DOWN.rotated(deg_to_rad(90.0))
	a.facing = Vector2.DOWN.rotated(deg_to_rad(45.0))
	return a


## Whether `p` lies in the box the footprint would be if it were built along the block's
## current heading (near_front_forward) instead of its grid: the same depth and half-width,
## about the same centre (the fixture's men centre on the origin).
func _in_heading_box(a: Unit, p: Vector2) -> bool:
	var fwd: Vector2 = a.near_front_forward()
	var prof: MeleeFrontProfile = MeleeFrontProfile.of(a)
	return absf(p.dot(fwd)) <= prof.depth and absf(p.dot(fwd.orthogonal())) <= prof.half


func test_a_turning_block_strikes_an_enemy_inside_its_grid_off_its_new_heading() -> void:
	# Inside the grid the men stand on, near its rear corner, but outside the box the new
	# heading would draw: the footprint is the grid's, so he is inside and is struck.
	var a := _turning_block()
	var p := Vector2(12.0, -40.0)
	assert_lt(absf(p.x), (FILES - 1) * 0.5 * PITCH, "precondition: he is inside the grid's files")
	assert_lt(absf(p.y), (RANKS - 1) * 0.5 * PITCH, "precondition: he is inside the grid's ranks")
	assert_false(_in_heading_box(a, p), "precondition: he is outside the new heading's box")
	assert_lt((p - a.position).dot(a.near_front_forward()), _front_depth_along(a),
			"precondition: he is behind the striking set along the new heading")
	var e := _lone_enemy_at(p)
	assert_lt(_nearest_man_distance(a, p), REACH, "precondition: a man of the block reaches him")
	assert_gt(_nearest_striker_distance(a, p), REACH, "precondition: the striking set cannot")
	assert_gt(_wounds(a, e), 0.0, "an enemy inside the turning block's grid is struck")


func test_a_turning_block_leaves_an_enemy_on_its_new_heading_outside_its_grid() -> void:
	# Inside the box the new heading would draw, behind the striking set, but past the grid's
	# flank: the footprint is the grid's, so he is outside and nobody behind the striking set
	# strikes him.
	var a := _turning_block()
	var p := -40.0 * a.near_front_forward()
	assert_gt(absf(p.x), (FILES - 1) * 0.5 * PITCH, "precondition: he is past the grid's flank")
	assert_true(_in_heading_box(a, p), "precondition: he is inside the new heading's box")
	assert_lt((p - a.position).dot(a.near_front_forward()), _front_depth_along(a),
			"precondition: he is behind the striking set along the new heading")
	assert_eq(_wounds_outside(a, p, "past the grid's flank"), 0.0,
			"an enemy outside the turning block's grid keeps his edge")


func test_one_man_knocked_out_of_the_ranks_does_not_widen_the_footprint() -> void:
	var a := _block()
	var moved: int = (RANKS - 3) * FILES + FILES - 1   # the right-hand file, three ranks from the rear
	a._sim_soldier_pos[moved] += Vector2(40.0, 0.0)
	var p := Vector2((FILES - 1) * 0.5 * PITCH + 12.0, a._sim_soldier_pos[moved].y)
	assert_eq(_wounds_outside(a, p, "off the flank"), 0.0, "one straggler does not move the block's flank")


## Depth (along the block's near_front_forward) of the rearmost man of its striking set.
func _front_depth_along(a: Unit) -> float:
	var fwd: Vector2 = a.near_front_forward()
	var depth: float = INF
	for i in a.engaged_soldier_indices(a._sim_soldier_pos.size()):
		depth = minf(depth, (a._sim_soldier_pos[i] - a.position).dot(fwd))
	return depth


func test_with_nobody_inside_the_pass_draws_nothing_and_changes_nothing() -> void:
	# Two blocks front to front, the enemy's front rank one pitch ahead of the block's: only the
	# striking ranks strike, each strike draws exactly its land and fall rolls, and no man
	# behind the striking set moves, tires or is touched.
	var a := _block()
	var e := _unit(2, 1, FILES * 3, Vector2(0.0, (RANKS - 1) * 0.5 * PITCH + 2.0 * PITCH), Vector2.UP)
	var k: int = 0
	for r in range(3):
		for f in range(FILES):
			e._sim_soldier_pos[k] = Vector2((f - (FILES - 1) * 0.5) * PITCH,
					(RANKS - 1) * 0.5 * PITCH + PITCH * (1 + r))
			k += 1
	var front := a.engaged_soldier_indices(a._sim_soldier_pos.size())
	var defenders: Array[Unit] = [e]
	var indices: Array[PackedInt32Array] = [PackedInt32Array(range(e._sim_soldier_pos.size()))]
	assert_true(SoldierInteriorStrike.inside_candidates(a, front, defenders, indices).is_empty(),
			"precondition: nobody is inside the block")
	var pos := PackedVector2Array(a._sim_soldier_pos)
	var vel := PackedVector2Array(a._sim_body_vel)
	var stam := PackedFloat32Array(a._sim_soldier_stamina)
	var hp := PackedFloat32Array(a._sim_soldier_hp)
	var prone := PackedFloat32Array(a._sim_prone)
	a.resolve_soldier_melee(e)
	var strikes: int = 0
	for i in range(stam.size()):
		if a._sim_soldier_stamina[i] < stam[i]:
			strikes += 1
		if front.has(i):
			continue
		assert_eq(a._sim_soldier_pos[i], pos[i], "soldier %d behind the striking set stood still" % i)
		assert_eq(a._sim_body_vel[i], vel[i], "soldier %d behind the striking set was not shoved" % i)
		assert_eq(a._sim_soldier_stamina[i], stam[i], "soldier %d behind the striking set held his blow" % i)
		assert_eq(a._sim_soldier_hp[i], hp[i], "soldier %d behind the striking set was not hurt" % i)
		assert_eq(a._sim_prone[i], prone[i], "soldier %d behind the striking set kept his feet" % i)
	assert_gt(strikes, 0, "precondition: the striking ranks struck")
	var ref := RandomNumberGenerator.new()
	ref.seed = SEED
	for _d in range(2 * strikes):
		ref.randf()
	assert_eq(Replay.rng.state, ref.state, "the cadence drew exactly two rolls per strike")
