extends GutTest
## MeleeFrontLine's pair weight and extensions, on bare units: which pairs count as front to
## front, and how far their contact range and engaged floor reach.


func _make_unit(max_soldiers: int, pos: Vector2, facing: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers
	u.set_frontage(15)
	u.position = pos
	u.facing = facing
	return u


## Two 120-man blocks, 15 files by 8 ranks, squarely front to front 150 wu apart.
func _frontal_pair() -> Array:
	return [_make_unit(120, Vector2.ZERO, Vector2.DOWN),
		_make_unit(120, Vector2(0.0, 150.0), Vector2.UP)]


func test_blocks_squarely_front_to_front_weigh_one() -> void:
	var p: Array = _frontal_pair()
	assert_almost_eq(MeleeFrontLine.weight(p[0], p[1]), 1.0, 0.0001, "front to front")
	assert_almost_eq(MeleeFrontLine.weight(p[1], p[0]), 1.0, 0.0001, "symmetric")


func test_the_extensions_reach_the_real_front_ranks() -> void:
	var p: Array = _frontal_pair()
	var a: Unit = p[0]
	var depth: float = MeleeFrontGeometry.front_rank_depth(a)
	assert_almost_eq(depth, 3.5 * a.rank_pitch_wu(), 0.001, "8 ranks: 3.5 rank pitches to the front")
	assert_almost_eq(MeleeFrontLine.contact_extension(a, p[1]), 2.0 * (depth - Unit.RADIUS), 0.001,
		"contact reaches each front rank past Unit.RADIUS")
	assert_almost_eq(a._front_depth() + p[1]._front_depth() + MeleeFrontLine.floor_extension(a, p[1]),
		2.0 * depth, 0.001, "the engaged floor holds the centres two front depths apart")


func test_a_flank_or_rear_attack_weighs_nothing() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var flank: Unit = _make_unit(120, Vector2(150.0, 0.0), Vector2.LEFT)
	assert_eq(MeleeFrontLine.weight(a, flank), 0.0, "an attacker on the flank")
	var rear: Unit = _make_unit(120, Vector2(0.0, -150.0), Vector2.DOWN)
	assert_eq(MeleeFrontLine.weight(a, rear), 0.0, "an attacker behind")
	assert_eq(MeleeFrontLine.contact_extension(a, flank), 0.0, "no extension on a flank")


func test_cavalry_far_tier_and_a_zero_scale_weigh_nothing() -> void:
	# (A square is no longer excluded: it fronts every way. See the geometry tests.)
	var p: Array = _frontal_pair()
	p[1].is_cavalry = true
	assert_eq(MeleeFrontLine.weight(p[0], p[1]), 0.0, "a pair with cavalry")
	p = _frontal_pair()
	p[1].tier = FormationTier.FAR
	assert_eq(MeleeFrontLine.weight(p[0], p[1]), 0.0, "a pair with a far-tier block")
	p = _frontal_pair()
	p[0].melee_front_line_scale = 0.0
	assert_eq(MeleeFrontLine.weight(p[0], p[1]), 0.0, "either unit's scale of 0 turns it off")
	assert_eq(MeleeFrontLine.weight(p[1], p[0]), 0.0, "for both units")
	p = _frontal_pair()
	p[1].is_ranged = true
	assert_eq(MeleeFrontLine.weight(p[0], p[1]), 0.0, "a pair with a missile unit")
	p = _frontal_pair()
	p[0].set_formation(Unit.FORMATION_SQUARE)
	p[1].set_formation(Unit.FORMATION_SQUARE)
	assert_eq(MeleeFrontLine.weight(p[0], p[1]), 0.0, "two squares, neither of which leads")


func test_a_scale_above_one_is_clamped() -> void:
	var p: Array = _frontal_pair()
	p[0].melee_front_line_scale = 5.0
	p[1].melee_front_line_scale = 5.0
	assert_almost_eq(MeleeFrontLine.weight(p[0], p[1]), 1.0, 0.0001,
		"the weight never passes 1, so the floor cannot outgrow the contact range")


## A frontal pair whose engaged floor is wider than SpatialHash.CELL_SIZE still finds each
## other in the widened neighbourhood lookup, wherever the cell boundaries fall. Two 160-man
## blocks on 10 files stand 16 ranks deep, 135 wu centre to front rank, so their floor is
## 270 wu: more than two cells.
func test_the_widened_lookup_finds_a_deep_frontal_partner_across_cells() -> void:
	var a: Unit = Unit.new()
	a.max_soldiers = 160
	add_child_autofree(a)
	a.set_frontage(10)
	var b: Unit = Unit.new()
	b.max_soldiers = 160
	add_child_autofree(b)
	b.set_frontage(10)
	b.team = 1
	a.facing = Vector2.DOWN
	b.facing = Vector2.UP
	# Cells are 128 wu: y = 250 sits in cell 1 and y = 510 in cell 3, two cells apart.
	a.position = Vector2(64.0, 250.0)
	b.position = Vector2(64.0, 510.0)
	SpatialHash.reset()
	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())
	assert_gt(MeleeFrontGeometry.front_rank_depth(a) * 2.0, 260.0, "setup: the floor is past 260 wu")
	assert_false(b in a._separation_candidates(), "setup: the plain 3x3 lookup misses the partner")
	assert_true(b in a._separation_candidates(true), "the widened lookup finds it")
	assert_true(a in b._separation_candidates(true), "from either side")
	SpatialHash.reset()


func test_min_cos_and_scale_are_taken_from_the_stricter_unit() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2(0.0, 150.0), Vector2.UP.rotated(deg_to_rad(30.0)))
	var loose: float = MeleeFrontLine.weight(a, b)
	b.melee_front_line_min_cos = 0.9
	assert_lt(MeleeFrontLine.weight(a, b), loose, "a higher min cos on either unit narrows it")
	b.melee_front_line_min_cos = Unit.MELEE_FRONT_LINE_MIN_COS
	b.melee_front_line_scale = 0.5
	assert_almost_eq(MeleeFrontLine.weight(a, b), loose * 0.5, 0.0001, "the smaller scale applies")
	assert_almost_eq(MeleeFrontLine.weight(b, a), loose * 0.5, 0.0001, "whichever unit holds it")
