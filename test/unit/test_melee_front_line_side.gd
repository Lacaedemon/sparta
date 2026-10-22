extends GutTest
## MeleeFrontLine's side contact, on bare units: a block whose front faces another block's flank
## or rear meets it at that block's outer file or rank, as two blocks front to front meet at
## their front ranks. The defender is met on whichever side faces the attacker (its outline).
##
## Every unit here is 120 men on 15 files by 8 ranks in the default order: an 18 wu pitch, so
## the front rank stands 63 wu ahead of the centre and the end files 126 wu to either side.

const DEPTH := 63.0
const HALF := 126.0


func _make_unit(pos: Vector2, facing: Vector2, team: int = 0) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 120
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers
	u.set_frontage(15)
	u.position = pos
	u.facing = facing
	u.team = team
	return u


## The engaged floor's whole centre gap for pair (a, b): the capped base plus floor_from.
func _floor(a: Unit, b: Unit) -> float:
	return a._front_depth() + b._front_depth() \
			+ MeleeFrontLine.floor_from(MeleeFrontLine.pair(a, b), a, b)


func test_setup_matches_the_stated_geometry() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	assert_almost_eq(MeleeFrontGeometry.front_rank_depth(a), DEPTH, 0.001, "front-rank depth")
	assert_almost_eq(MeleeFrontGeometry.front_half_width(a), HALF, 0.001, "front half-width")


## a faces DOWN; b stands ahead of it with its back to it. Fails on main, where the fronts
## pointing the same way weigh 0 and the floor is the capped centre-based one.
func test_a_rear_attack_meets_the_defender_rear_rank() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(0.0, 200.0), Vector2.DOWN, 1)
	assert_almost_eq(MeleeFrontLine.weight(a, b), 1.0, 0.0001, "a squarely behind b weighs 1")
	assert_almost_eq(MeleeFrontLine.weight(b, a), 1.0, 0.0001, "symmetric")
	assert_almost_eq(_floor(a, b), 2.0 * DEPTH, 0.001,
		"the floor holds a's front rank on b's rear rank: the two depths apart")
	assert_almost_eq(_floor(b, a), 2.0 * DEPTH, 0.001, "from either side")


## a faces DOWN; b stands ahead of it side-on, its end file toward a.
func test_a_flank_attack_meets_the_defender_end_file() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(0.0, 250.0), Vector2.LEFT, 1)
	assert_almost_eq(MeleeFrontLine.weight(a, b), 1.0, 0.0001, "a squarely on b's flank weighs 1")
	assert_almost_eq(MeleeFrontLine.weight(b, a), 1.0, 0.0001, "symmetric")
	assert_almost_eq(_floor(a, b), DEPTH + HALF, 0.001,
		"the floor holds a's front rank on b's end file: a's depth plus b's half-width")
	# b faces RIGHT instead: its other flank, the same outline.
	b.facing = Vector2.RIGHT
	assert_almost_eq(_floor(a, b), DEPTH + HALF, 0.001, "either flank")


## The contact range reaches the defender's outline too: in contact just inside a's front rank
## plus b's half-width plus the base range, not just outside it.
func test_flank_contact_registers_at_the_defender_end_file() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(0.0, 250.0), Vector2.LEFT, 1)
	var base: float = 2.0 * Unit.RADIUS
	var reach: float = DEPTH + HALF
	b.position = Vector2(0.0, reach - 1.0)
	assert_true(MeleeFrontLine.within_contact(a, b, base, a.position.distance_squared_to(b.position)),
		"in contact with a's front rank at b's end file")
	b.position = Vector2(0.0, reach + 1.0)
	assert_false(MeleeFrontLine.within_contact(a, b, base, a.position.distance_squared_to(b.position)),
		"out of contact just past it")


## The side part adds to a frontal clash only once its fronts are far from opposed: within
## melee_side_contact_max_cos of square, the weight is the frontal part's alone.
func test_a_near_frontal_clash_keeps_its_frontal_weight() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	# 30 degrees off square: cos 0.866, above the 0.75 default.
	var b: Unit = _make_unit(Vector2(0.0, 150.0), Vector2.UP.rotated(deg_to_rad(30.0)), 1)
	var with_side: float = MeleeFrontLine.weight(a, b)
	b.melee_side_contact_max_cos = -1.0
	assert_eq(MeleeFrontLine.weight(a, b), with_side, "no side part at 30 degrees")
	assert_eq(MeleeFrontLine.side_gate(0.866, 0.5, 0.75), 0.0, "the gate reads 0 above its max")


## Past square, the side part ramps in as the frontal part ramps out, so the weight never jumps.
func test_the_side_part_ramps_in_as_the_frontal_part_ramps_out() -> void:
	assert_eq(MeleeFrontLine.side_gate(0.5, 0.5, 0.75), 1.0, "whole at min_cos")
	assert_almost_eq(MeleeFrontLine.side_gate(0.625, 0.5, 0.75), 0.5, 0.0001, "half way")
	assert_eq(MeleeFrontLine.side_gate(-1.0, 0.5, 0.75), 1.0, "a rear attack")
	assert_lte(_largest_step(Unit.MELEE_FRONT_LINE_MIN_COS, Unit.MELEE_SIDE_CONTACT_MAX_COS), 0.05,
		"the default tuning, 1-degree steps")


## b turns on the spot ahead of a in 1-degree steps, from front to front to its back to a, with
## all three units tuned to `min_cos` and `max_cos`: the largest change in the weight from one
## step to the next, after asserting it never passes 1 and never falls below the frontal part.
func _largest_step(min_cos: float, max_cos: float) -> float:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(0.0, 180.0), Vector2.UP, 1)
	var frontal_only: Unit = _make_unit(Vector2(0.0, 180.0), Vector2.UP, 1)
	for u: Unit in [a, b, frontal_only]:
		u.melee_front_line_min_cos = min_cos
		u.melee_side_contact_max_cos = max_cos
	frontal_only.melee_side_contact_max_cos = -1.0
	var last: float = 0.0
	var largest: float = 0.0
	for deg in range(0, 181):
		b.facing = Vector2.UP.rotated(deg_to_rad(float(deg)))
		frontal_only.facing = b.facing
		var w: float = MeleeFrontLine.weight(a, b)
		if deg > 0:
			largest = maxf(largest, absf(w - last))
		assert_lte(w, 1.0 + 0.000001, "never past 1 at %d degrees (%s, %s)" % [deg, min_cos, max_cos])
		assert_gte(w, MeleeFrontLine.weight(a, frontal_only) - 0.000001,
			"never below the frontal part alone at %d degrees" % deg)
		last = w
	# A min cos below -1 never lets the gate reach 1 (it reaches 1 only at the min cos itself).
	if min_cos >= -1.0:
		assert_almost_eq(last, 1.0, 0.0001, "the rear attack weighs 1 (%s, %s)" % [min_cos, max_cos])
	return largest


## The weight steps by no more than 0.05 a degree where the parts hand over: about 41 degrees
## (cos 0.75, where the side part starts) and 60 degrees (cos 0.5, where the frontal part ends).
func test_the_weight_is_continuous_at_the_hand_over_angles() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(0.0, 180.0), Vector2.UP, 1)
	for centre: int in [41, 60]:
		b.facing = Vector2.UP.rotated(deg_to_rad(float(centre - 6)))
		var last: float = MeleeFrontLine.weight(a, b)
		for deg in range(centre - 5, centre + 6):
			b.facing = Vector2.UP.rotated(deg_to_rad(float(deg)))
			var w: float = MeleeFrontLine.weight(a, b)
			assert_lte(absf(w - last), 0.05, "no jump at %d degrees (%.3f to %.3f)" % [deg, last, w])
			last = w


## Tuned values outside the defaults' order: a max cos above 1 (where a head-on pair once
## weighed about 1.67), a min cos at or above the max cos (where the gate was once a step at min
## cos), equal values, a min cos of 1, a min cos above 1 (where a head-on pair once weighed
## about 1.44: the frontal ramp's step read 1 while the gate, ramping down to the uncapped min
## cos, read 0.44) and a min cos below -1. The gate stays continuous in the cosine and, beside
## the frontal ramp, within 1 from a cosine of 1 (head on) to -1; the pair's weight stays
## within 1 at every facing, head on included.
func test_tuned_pairs_keep_the_weight_continuous_and_within_one() -> void:
	var tunings: Array = [[0.5, 1.5], [0.9, 0.75], [0.5, 0.5], [0.0, 1.0], [-0.5, 0.2],
			[0.95, 0.96], [1.0, 0.75], [1.2, 0.75], [1.2, 1.5], [-1.5, 0.75]]
	for t: Array in tunings:
		var lo: float = t[0]
		var hi: float = t[1]
		var last: float = 0.0
		for i in range(0, 2001):
			var c: float = 1.0 - float(i) * 0.001
			var g: float = MeleeFrontLine.side_gate(c, lo, hi)
			assert_lte(g + MeleeFrontGeometry.ramp(c, lo), 1.0 + 0.000001,
				"gate plus ramp within 1 at c %.3f (%s, %s)" % [c, lo, hi])
			# A 0.001 step in the cosine: the steepest tuning here (0.95, 0.96) moves 0.1.
			if i > 0:
				assert_lte(absf(g - last), 0.1 + 0.000001,
					"gate continuous at c %.3f (%s, %s)" % [c, lo, hi])
			last = g
		gut.p("largest 1-degree weight step, min cos %s, max cos %s: %.4f" % [lo, hi,
				_largest_step(lo, hi)])
	# A head-on pair weighs 1, not more, with the max cos tuned above 1.
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(0.0, 150.0), Vector2.UP, 1)
	a.melee_side_contact_max_cos = 1.5
	b.melee_side_contact_max_cos = 1.5
	assert_almost_eq(MeleeFrontLine.weight(a, b), 1.0, 0.0001, "head on, max cos 1.5")
	# And with the min cos tuned above 1 (the frontal ramp a step that is 1 head on).
	for lo_hi: Array in [[1.2, 0.75], [1.2, 1.5]]:
		for u: Unit in [a, b]:
			u.melee_front_line_min_cos = lo_hi[0]
			u.melee_side_contact_max_cos = lo_hi[1]
		assert_eq(MeleeFrontLine.side_gate(1.0, lo_hi[0], lo_hi[1]), 0.0,
			"no side gate head on (%s, %s)" % lo_hi)
		assert_almost_eq(MeleeFrontLine.weight(a, b), 1.0, 0.0001, "head on (%s, %s)" % lo_hi)
	assert_lte(_largest_step(0.9, 0.75), 0.1, "a min cos above the max cos")
	assert_lte(_largest_step(0.5, 1.5), 0.1, "a max cos above 1")
	assert_lte(_largest_step(0.5, 0.5), 0.1, "equal values: the gate spans SIDE_GATE_MIN_SPAN")
	# (1.0, 0.75) steps by about 1 between 0 and 1 degree: a min cos of 1 makes the frontal ramp
	# itself a step at 1 (MeleeFrontGeometry.ramp), which the gate does not change.


## An L-shaped meeting: a's front faces b's flank and b's front faces a's flank at once (b ahead
## of a and to its side, facing across a's front). Both orientations weigh, and each reach is
## their average by weight, between the block's front-rank depth and its half-width.
func test_an_l_shaped_meeting_averages_both_orientations() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(150.0, 150.0), Vector2.LEFT, 1)
	var pa: MeleeFrontProfile = MeleeFrontProfile.of(a)
	var pb: MeleeFrontProfile = MeleeFrontProfile.of(b)
	var fa: Vector2 = MeleeFrontGeometry.grid_front(a)
	var fb: Vector2 = MeleeFrontGeometry.grid_front(b)
	var to_b: Vector2 = b.position - a.position
	var ob: Vector2 = MeleeFrontGeometry.outline(pb, fb, fa)
	var oa: Vector2 = MeleeFrontGeometry.outline(pa, fa, fb)
	var w_ab: float = clampf(to_b.dot(fa) / Unit.RADIUS, 0.0, 1.0) * MeleeFrontGeometry.front_overlap(
			pa.half, ob.y, absf(to_b.dot(fa.orthogonal())))
	var w_ba: float = clampf(-to_b.dot(fb) / Unit.RADIUS, 0.0, 1.0) * MeleeFrontGeometry.front_overlap(
			pb.half, oa.y, absf(to_b.dot(fb.orthogonal())))
	assert_gt(w_ab, 0.0, "setup: a's front bears on b")
	assert_gt(w_ba, 0.0, "setup: b's front bears on a")
	var s: Vector3 = MeleeFrontLine._side_part(pa, pb, fa, fb, to_b)
	assert_almost_eq(s.x, maxf(w_ab, w_ba), 0.0001, "the larger orientation's weight")
	assert_almost_eq(s.y, (w_ab * DEPTH + w_ba * HALF) / (w_ab + w_ba), 0.001,
		"a's reach: its front rank and its end file, averaged by weight")
	assert_almost_eq(s.z, (w_ab * HALF + w_ba * DEPTH) / (w_ab + w_ba), 0.001,
		"b's reach: its end file and its front rank, averaged by weight")
	var p: Vector3 = MeleeFrontLine.pair(a, b)
	assert_almost_eq(p.x, s.x, 0.0001, "fronts at right angles: the side part alone")
	assert_almost_eq(p.y, s.y, 0.001, "pair() carries a's averaged reach")
	assert_almost_eq(p.z, s.z, 0.001, "pair() carries b's averaged reach")
	assert_almost_eq(MeleeFrontLine.floor_from(p, a, b),
		p.x * (maxf(0.0, s.y - a._front_depth()) + maxf(0.0, s.z - b._front_depth())), 0.001,
		"the floor reads the averaged reaches")


## In the oblique band (cosine between the default 0.5 and 0.75) both parts weigh, and
## floor_from reads the reaches averaged by the two parts' weights.
func test_the_oblique_band_blends_both_parts_into_the_floor() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	# 50 degrees off square: cos 0.643, inside the band.
	var b: Unit = _make_unit(Vector2(0.0, 160.0), Vector2.UP.rotated(deg_to_rad(50.0)), 1)
	var fa: Vector2 = MeleeFrontGeometry.grid_front(a)
	var fb: Vector2 = MeleeFrontGeometry.grid_front(b)
	var c: float = -fa.dot(fb)
	assert_between(c, 0.5, 0.75, "setup: inside the band")
	var frontal_only: Unit = _make_unit(b.position, b.facing, 1)
	frontal_only.melee_side_contact_max_cos = -1.0
	var p_f: Vector3 = MeleeFrontLine.pair(a, frontal_only)
	assert_gt(p_f.x, 0.0, "setup: the frontal part weighs")
	var s: Vector3 = MeleeFrontLine._side_part(MeleeFrontProfile.of(a), MeleeFrontProfile.of(b),
			fa, fb, b.position - a.position)
	var w_side: float = MeleeFrontLine.side_gate(c, 0.5, 0.75) * s.x
	assert_gt(w_side, 0.0, "setup: the side part weighs")
	var p: Vector3 = MeleeFrontLine.pair(a, b)
	assert_almost_eq(p.x, p_f.x + w_side, 0.0001, "the weight is the two parts' sum")
	assert_lte(p.x, 1.0, "within 1")
	var ra: float = (p_f.x * p_f.y + w_side * s.y) / p.x
	var rb: float = (p_f.x * p_f.z + w_side * s.z) / p.x
	assert_almost_eq(p.y, ra, 0.001, "a's reach averaged by the parts' weights")
	assert_almost_eq(p.z, rb, 0.001, "b's reach averaged by the parts' weights")
	assert_almost_eq(MeleeFrontLine.floor_from(p, a, b),
		p.x * (maxf(0.0, ra - a._front_depth()) + maxf(0.0, rb - b._front_depth())), 0.001,
		"floor_from reads the blended reaches")
	assert_gt(MeleeFrontLine.floor_from(p, a, b), MeleeFrontLine.floor_from(p_f, a, frontal_only),
		"the side part adds to the frontal floor")


## A routing defender keeps the centre-based range: a pursuer behind a fleeing block, or on its
## flank, does not stop at its rear rank or end file. A router whose own front bears on an
## enemy's flank still meets it at that flank.
func test_a_routing_defender_is_met_centre_to_centre() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(0.0, 200.0), Vector2.DOWN, 1)
	assert_almost_eq(MeleeFrontLine.weight(a, b), 1.0, 0.0001, "setup: a rear attack weighs 1")
	b.state = Unit.State.ROUTING
	assert_eq(MeleeFrontLine.weight(a, b), 0.0, "the routing defender's rear")
	assert_eq(MeleeFrontLine.weight(b, a), 0.0, "from either side")
	b.position = Vector2(0.0, 250.0)
	b.facing = Vector2.LEFT
	assert_eq(MeleeFrontLine.weight(a, b), 0.0, "the routing defender's flank")
	# Now a routs, its front on b's flank: b, the defender, is not routing.
	b.state = Unit.State.IDLE
	a.state = Unit.State.ROUTING
	assert_almost_eq(MeleeFrontLine.weight(a, b), 1.0, 0.0001, "a router's front on a flank")


func test_a_side_contact_max_cos_of_minus_one_turns_it_off() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(0.0, 200.0), Vector2.DOWN, 1)
	b.melee_side_contact_max_cos = -1.0
	assert_eq(MeleeFrontLine.weight(a, b), 0.0, "the stricter unit's value applies")
	assert_eq(MeleeFrontLine.weight(b, a), 0.0, "whichever unit holds it")


func test_cavalry_and_missile_units_keep_the_centre_based_ranges() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(0.0, 200.0), Vector2.DOWN, 1)
	a.is_cavalry = true
	assert_eq(MeleeFrontLine.weight(a, b), 0.0, "a cavalry attacker in the rear")
	a.is_cavalry = false
	b.is_cavalry = true
	assert_eq(MeleeFrontLine.weight(a, b), 0.0, "a cavalry defender")
	b.is_cavalry = false
	b.is_ranged = true
	assert_eq(MeleeFrontLine.weight(a, b), 0.0, "a missile defender")


## Blocks side by side, facing the same way, are not attacking each other: neither lies ahead
## of the other's front.
func test_blocks_side_by_side_do_not_pair() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(260.0, 0.0), Vector2.DOWN, 1)
	assert_eq(MeleeFrontLine.weight(a, b), 0.0, "abreast")
	# Facing opposite ways but abreast: still neither ahead of the other's front.
	b.facing = Vector2.UP
	assert_eq(MeleeFrontLine.weight(a, b), 0.0, "abreast, opposed")


## The extension bound covers the outline: a line's profile reaches its half-diagonal, so the
## contact reject and the neighbourhood lookup cannot drop a flank pair.
func test_the_profile_bound_covers_the_outline() -> void:
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	assert_almost_eq(MeleeFrontGeometry.extension_depth(a), sqrt(DEPTH * DEPTH + HALF * HALF),
		0.001, "the half-diagonal")
	for deg in range(0, 360, 15):
		var axis: Vector2 = Vector2.DOWN.rotated(deg_to_rad(float(deg)))
		var o: Vector2 = MeleeFrontGeometry.outline(MeleeFrontProfile.of(a), Vector2.DOWN, axis)
		assert_lte(o.x, MeleeFrontGeometry.extension_depth(a) + 0.001, "bound at %d degrees" % deg)
