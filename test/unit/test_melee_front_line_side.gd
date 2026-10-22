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
	# b turns on the spot ahead of a, from front to front to its back to a.
	var a: Unit = _make_unit(Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(Vector2(0.0, 180.0), Vector2.UP, 1)
	var frontal_only: Unit = _make_unit(Vector2(0.0, 180.0), Vector2.UP, 1)
	frontal_only.melee_side_contact_max_cos = -1.0
	var last: float = MeleeFrontLine.weight(a, b)
	for deg in range(5, 181, 5):
		b.facing = Vector2.UP.rotated(deg_to_rad(float(deg)))
		frontal_only.facing = b.facing
		var w: float = MeleeFrontLine.weight(a, b)
		assert_lte(absf(w - last), 0.2, "no jump at %d degrees (%.3f to %.3f)" % [deg, last, w])
		assert_gte(w, MeleeFrontLine.weight(a, frontal_only),
			"never below the frontal part alone at %d degrees" % deg)
		assert_lte(w, 1.0, "never past 1 at %d degrees" % deg)
		last = w
	assert_almost_eq(last, 1.0, 0.0001, "the rear attack weighs 1")


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
