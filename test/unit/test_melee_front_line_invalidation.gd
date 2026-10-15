extends GutTest
## MeleeFrontLine's cached inputs and their invalidation, on bare units: an order's change to a
## block is read in the same frame, a real file-assignment writer re-reads the rank count, the
## frontal candidate memo follows its cell and its ring count, the anchored gap moves with the
## weight, and a square's depth is its file pitch. Also the SWEEP_ROUTERS contact fallback.


func _make_unit(max_soldiers: int, pos: Vector2, facing: Vector2, team: int = 0,
		files: int = 15) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers
	u.set_frontage(files)
	u.position = pos
	u.facing = facing
	u.team = team
	return u


func after_each() -> void:
	SpatialHash.reset()


# 120 men on 15 files with one man dealt to a ninth rank: dealt ranks read 9, even ranks 8.
func _deal_a_ninth_rank(u: Unit) -> void:
	var files := PackedInt32Array()
	var ranks := PackedInt32Array()
	for i in u.soldiers:
		files.append(i % 15)
		ranks.append(floori(i / 15.0))
	ranks[0] = 8
	u.install_file_assignment(files, ranks, 15, 15)


## The reform mode is set by an order command, which playback applies after the frame's first
## read: the profile reads the change at once, so live and playback measure the same depth.
func test_a_reform_mode_change_is_read_in_the_same_frame() -> void:
	var u: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	u.file_major_reform_mode = Unit.ReformMode.FILE_MAJOR
	_deal_a_ninth_rank(u)
	var pitch: float = u.rank_pitch_wu()
	assert_almost_eq(MeleeFrontGeometry.front_rank_depth(u), 4.0 * pitch, 0.001, "dealt: 9 ranks")
	u.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	assert_almost_eq(MeleeFrontGeometry.front_rank_depth(u), 3.5 * pitch, 0.001,
		"row-major in the same frame: the even 8 ranks")


## A formation order in the same frame changes the profile too.
func test_a_formation_change_is_read_in_the_same_frame() -> void:
	var u: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var before: float = MeleeFrontGeometry.extension_depth(u)
	u.set_formation(Unit.FORMATION_SQUARE)
	assert_true(u.in_square(), "setup: the square formed")
	assert_ne(MeleeFrontGeometry.extension_depth(u), before, "the square's extent is read at once")


## install_file_assignment, a real writer, bumps the generation: a re-deal at the same
## headcount and file count, in the same frame, is read at once.
func test_a_real_writer_re_deals_the_rank_count() -> void:
	var u: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	u.file_major_reform_mode = Unit.ReformMode.FILE_MAJOR
	_deal_a_ninth_rank(u)
	assert_eq(u.live_rank_count(15), 9, "setup: the deepest dealt rank plus one")
	var ranks: PackedInt32Array = u._sim_soldier_rank.duplicate()
	ranks[0] = 0
	u.install_file_assignment(u._sim_soldier_file.duplicate(), ranks, 15, 15)
	assert_eq(u.live_rank_count(15), 8, "the writer's re-deal is read in the same frame")


## The frontal candidate memo is keyed on the unit's cell: a unit that moves cells within the
## frame queries afresh.
func test_the_candidate_memo_follows_the_cell() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2(300.0, 0.0), Vector2.UP, 1)
	a.melee_front_line_scale = 0.0   # one ring: the query radius is one cell
	b.melee_front_line_scale = 0.0
	SpatialHash.reset()
	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())
	assert_false(a._separation_candidates(true).has(b), "setup: b is two cells away")
	a.position = Vector2(200.0, 0.0)
	assert_true(a._separation_candidates(true).has(b), "one cell away once a moves")


## ... and on its ring count: a block that turns eligible within the frame widens its query.
func test_the_candidate_memo_follows_the_ring_count() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2(300.0, 0.0), Vector2.UP, 1)
	a.melee_front_line_scale = 0.0
	b.melee_front_line_scale = 0.0
	SpatialHash.reset()
	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())
	assert_false(a._separation_candidates(true).has(b), "setup: one ring misses b")
	a.melee_front_line_scale = 1.0
	var radius: float = MeleeFrontGeometry.query_radius(a, SpatialHash.max_extension_depth())
	assert_gt(radius, SpatialHash.CELL_SIZE, "setup: the widened radius spans two rings")
	assert_true(a._separation_candidates(true).has(b), "the wider query finds b")


## An anchored frontage stands its men off the position. The measured gap moves from the
## positions (weight 0) to the men's centres (weight 1) with the weight, never in a jump.
func test_the_anchored_gap_moves_with_the_weight() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	a.set_frontage(15, 100.0)
	var men: Vector2 = a.men_centre_offset()
	var b: Unit = _make_unit(120, men + Vector2(0.0, 150.0), Vector2.UP, 1)
	var positions: Vector2 = b.position - a.position
	for scale in [1.0, 0.5, 0.001]:
		a.melee_front_line_scale = scale
		var w: float = MeleeFrontLine.weight(a, b)
		assert_almost_eq(w, scale, 0.0001, "setup: the weight is the scale")
		var gap: Vector2 = MeleeFrontLine.toward(a, b)
		assert_almost_eq(gap.distance_to(positions - men * w), 0.0, 0.001,
			"at weight %.3f the gap is the positions' plus that share of the men's shift" % w)
	a.melee_front_line_scale = 0.0
	assert_eq(MeleeFrontLine.toward(a, b), positions, "weight 0: the positions")


## A square's depth is its file pitch on both axes, not its rank pitch.
func test_a_squares_depth_is_its_file_pitch() -> void:
	var u: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	u.rank_pitch = 2.0 * u.file_pitch
	u.set_formation(Unit.FORMATION_SQUARE)
	assert_true(u.in_square(), "setup: the square formed")
	assert_ne(u.rank_pitch_wu(), u.file_pitch_wu(), "setup: the pitches differ")
	assert_eq(u.formation_files(u.soldiers), 11, "setup: an 11-file square")
	assert_almost_eq(MeleeFrontGeometry.front_rank_depth(u), 5.0 * u.file_pitch_wu(), 0.001,
		"five file pitches to the outer rank")


## SWEEP_ROUTERS (any selection can take it) finds a router held at its front rank past the
## detection radius, and only when no router inside the radius qualifies.
func test_sweep_routers_finds_a_router_in_frontal_contact() -> void:
	var a: Unit = _make_unit(160, Vector2.ZERO, Vector2.DOWN, 0, 10)
	var b: Unit = _make_unit(160, Vector2(0.0, 270.0), Vector2.UP, 1, 10)
	b.state = Unit.State.ROUTING
	b.remove_from_group("units")
	b.add_to_group("routers")
	assert_gt(a.position.distance_to(b.position), a.detection_range, "setup: past detection")
	assert_eq(UnitTargeting.nearest_routing_enemy(a), b, "in contact at the front ranks")
	var near: Unit = _make_unit(30, Vector2(150.0, 0.0), Vector2.UP, 1, 10)
	near.state = Unit.State.ROUTING
	near.remove_from_group("units")
	near.add_to_group("routers")
	assert_eq(UnitTargeting.nearest_routing_enemy(a), near, "a router inside the radius first")
	near.position = Vector2(5000.0, 0.0)
	b.facing = Vector2.LEFT
	assert_null(UnitTargeting.nearest_routing_enemy(a), "not when not frontal")
