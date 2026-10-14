extends GutTest
## MeleeFrontLine's geometry, on bare units: the weight reads the pair's slot grids and how far
## their fronts overlap, not their headings or the bearing between their centres; the depth
## reads a file-major block's deepest file; the contact test matches the full range; and the
## neighbourhood lookup finds a deep partner from a one-rank block's side too.


func _make_unit(max_soldiers: int, pos: Vector2, facing: Vector2, team: int = 0) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers
	u.set_frontage(15)
	u.position = pos
	u.facing = facing
	u.team = team
	return u


func after_each() -> void:
	SpatialHash.reset()


## Headings 150 degrees apart, b straight ahead of a, both 15 files wide (126 wu half-width).
## Opposed: cos 30 = 0.866, ramped from 0.5 to 1 = 0.7321. The front axis splits the two
## headings, 15 degrees off a's, so b stands 150 sin 15 = 38.8 wu off it sideways and the
## fronts overlap over 213.2 of the narrower's 252 wu: 0.8459. Product 0.6193.
func test_an_oblique_clash_weighs_its_opposition_and_overlap() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2(0.0, 150.0), Vector2.UP.rotated(deg_to_rad(30.0)), 1)
	assert_almost_eq(MeleeFrontLine.weight(a, b), 0.6193, 0.001, "opposition times overlap")
	assert_almost_eq(MeleeFrontLine.weight(b, a), 0.6193, 0.001, "symmetric")


## A pair offset sideways keeps the same weight however close the press brings it: the weight
## never reads the distance along the front axis, so it cannot fall as the centres close and
## lower the floor that holds them apart.
func test_an_offset_pair_keeps_its_weight_as_it_closes() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2(90.0, 126.0), Vector2.UP, 1)
	var far: float = MeleeFrontLine.weight(a, b)
	# 15 files, 126 wu half-width each, 90 wu apart sideways: (252 - 90) / 252 overlap.
	assert_almost_eq(far, 162.0 / 252.0, 0.001, "the share of the fronts that overlaps")
	b.position = Vector2(90.0, 62.0)
	assert_almost_eq(MeleeFrontLine.weight(a, b), far, 0.0001, "unchanged as the centres close")


## Each term zeroes the weight on its own, with the other two at 1.
func test_each_term_can_zero_the_weight_alone() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	# Opposed fronts, b ahead, but clear of a's front sideways (300 wu > 252).
	var beside: Unit = _make_unit(120, Vector2(300.0, 20.0), Vector2.UP, 1)
	assert_eq(MeleeFrontLine.weight(a, beside), 0.0, "no front overlap")
	# Opposed and overlapping, but b has passed behind a.
	var passed: Unit = _make_unit(120, Vector2(0.0, -150.0), Vector2.UP, 1)
	assert_eq(MeleeFrontLine.weight(a, passed), 0.0, "not ahead of each other")
	# Ahead and overlapping, but heading the same way (a rear attack).
	var rear: Unit = _make_unit(120, Vector2(0.0, 150.0), Vector2.DOWN, 1)
	assert_eq(MeleeFrontLine.weight(a, rear), 0.0, "fronts not opposed")


## A heading turn the grid absorbs (a router's snap about, folded into grid_fold) leaves its
## men's front rank facing the enemy, so the pair keeps its weight and its ranges.
func test_a_folded_heading_turn_keeps_the_grid_front() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2(0.0, 150.0), Vector2.UP, 1)
	b._face_dir(Vector2.DOWN)   # a turn past FACING_SNAP_ABSORB_THRESHOLD: the grid stays
	assert_eq(b.facing, Vector2.DOWN, "setup: the heading turned about")
	assert_almost_eq(MeleeFrontGeometry.grid_front(b).dot(Vector2.UP), 1.0, 0.0001,
		"setup: the grid still faces a")
	assert_almost_eq(MeleeFrontLine.weight(a, b), 1.0, 0.0001, "the pair still meets front to front")


## A file-major block thinned unevenly keeps its deepest file, and the grid centres on it, so
## its front rank stands further ahead than an even split of the headcount would put it.
func test_a_file_major_block_measures_its_deepest_file() -> void:
	var u: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	u.file_major_reform_mode = Unit.ReformMode.FILE_MAJOR
	u.soldiers = 90
	# 15 files: file 0 still 8 deep, the other 82 men spread over the remaining 14.
	var files := PackedInt32Array()
	for i in 8:
		files.append(0)
	for i in 82:
		files.append(1 + i % 14)
	u._sim_soldier_file = files
	u._sim_soldier_rank = PackedInt32Array()
	u._file_assignment_files = 15
	assert_eq(UnitFormation.ranks_for(90, 15), 6, "setup: an even split is 6 ranks")
	assert_eq(u.live_rank_count(15), 8, "the deepest file is 8")
	assert_almost_eq(MeleeFrontGeometry.front_rank_depth(u), 3.5 * u.rank_pitch_wu(), 0.001,
		"the front rank stands 3.5 rank pitches ahead")


## within_contact gives the same answer as comparing against the full extended range.
func test_within_contact_matches_the_full_range() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2.ZERO, Vector2.UP, 1)
	var base: float = 62.0
	for p in [Vector2(0, 40), Vector2(0, 150), Vector2(0, 152), Vector2(0, 155), Vector2(60, 140),
			Vector2(200, 100), Vector2(0, 400)]:
		b.position = p
		var reach: float = base + MeleeFrontLine.contact_extension(a, b)
		var d_sq: float = a.position.distance_squared_to(b.position)
		assert_eq(MeleeFrontLine.within_contact(a, b, base, d_sq), d_sq <= reach * reach,
			"at %s" % p)


## A one-rank block widens its lookup too, so a deep frontal partner is found from both sides.
func test_a_one_rank_block_finds_a_deep_partner() -> void:
	var a: Unit = Unit.new()
	a.max_soldiers = 10
	add_child_autofree(a)
	a.set_frontage(10)
	var b: Unit = Unit.new()
	b.max_soldiers = 160
	add_child_autofree(b)
	b.set_frontage(8)
	b.team = 1
	a.facing = Vector2.DOWN
	b.facing = Vector2.UP
	a.position = Vector2(64.0, 250.0)
	b.position = Vector2(64.0, 440.0)
	SpatialHash.reset()
	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())
	assert_eq(MeleeFrontGeometry.front_rank_depth(a), 0.0, "setup: a is one rank deep")
	assert_gt(MeleeFrontGeometry.front_rank_depth(b), 150.0, "setup: b is 20 ranks deep")
	assert_false(b in a._separation_candidates(), "setup: the plain lookup misses b")
	assert_true(b in a._separation_candidates(true), "the one-rank side finds the deep block")
	assert_true(a in b._separation_candidates(true), "and the deep side finds it")


## Two blocks front to front, held at their front ranks 144 wu apart, still count each other
## in the morale's local force ratio, which reads a 120 wu radius: the outnumbered one erodes.
func test_a_frontal_enemy_counts_in_the_local_force_ratio() -> void:
	var a: Unit = _make_unit(60, Vector2.ZERO, Vector2.DOWN)
	a.set_frontage(6)   # 10 ranks: 81 wu to its front rank, and b's 8 ranks 63 wu
	var b: Unit = _make_unit(120, Vector2.ZERO, Vector2.UP, 1)
	b.position = Vector2(0.0, MeleeFrontGeometry.front_rank_depth(a) + MeleeFrontGeometry.front_rank_depth(b))
	assert_gt(a.position.distance_to(b.position), UnitMorale.LOCAL_FORCE_RADIUS,
		"setup: the centres stand past the plain radius")
	a.morale = 60.0
	UnitMorale.tick_morale(a, 1.0)
	var frontal: float = a.morale
	b.facing = Vector2.LEFT   # no longer front to front: the plain radius applies
	a.morale = 60.0
	UnitMorale.tick_morale(a, 1.0)
	assert_lt(frontal, a.morale, "the frontal enemy erodes the outnumbered block's morale")
