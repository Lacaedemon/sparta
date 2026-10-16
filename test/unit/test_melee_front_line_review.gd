extends GutTest
## MeleeFrontLine round-2 review cases, on bare units: a square meets a line at its outer rank,
## an in-place turn keeps the men's front, a flank-anchored frontage measures overlap from its
## men, a pursuer reaches a router's front rank, a contact past the detection radius is still
## acquired, the rally check sees a frontal press, the hash re-reads a deepened block, and the
## rank count follows the dealt ranks and any re-deal.


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


# The offset of `u`'s men's centre from its position, at the angle its men face.
func _men(u: Unit) -> Vector2:
	return MeleeFrontGeometry.men_offset(u, MeleeFrontGeometry.grid_front(u))


func after_each() -> void:
	SpatialHash.reset()


## A line attacking a square frontally meets its outer rank: the square fronts every way.
func test_a_line_meets_a_square_at_its_outer_rank() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2(0.0, 150.0), Vector2.LEFT, 1)
	b.set_formation(Unit.FORMATION_SQUARE)
	assert_true(b.in_square(), "setup: b formed a square")
	var p: Vector3 = MeleeFrontLine.pair(a, b)
	assert_almost_eq(p.x, 1.0, 0.0001, "the square faces any front squarely")
	assert_almost_eq(p.y, MeleeFrontGeometry.front_rank_depth(a), 0.001, "the line reaches its front rank")
	# 120 men square on 11 files by 11 ranks, both axes at its file pitch: five pitches centre
	# to outer rank either way. Facing LEFT, it meets a's axis (DOWN) side-on.
	assert_eq(b.formation_files(b.soldiers), 11, "setup: an 11-file square")
	assert_almost_eq(p.z, 5.0 * b.file_pitch_wu(), 0.001, "the square reaches its outer rank")
	b.position = Vector2(0.0, -150.0)
	assert_eq(MeleeFrontLine.weight(a, b), 0.0, "a square behind the line is not in front of it")


## An engage turn in progress leaves the men where they stood: the pair keeps its weight.
func test_an_engage_turn_in_progress_keeps_the_front() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2(0.0, 150.0), Vector2.UP, 1)
	a._engage_turn_start_facing = Vector2.DOWN
	a._engage_turn_target = Vector2.RIGHT
	a.facing = Vector2.DOWN.rotated(deg_to_rad(70.0))   # partway through the turn
	assert_almost_eq(MeleeFrontLine.weight(a, b), 1.0, 0.0001, "the men still face b")
	a._engage_turn_target = Vector2.ZERO
	assert_lt(MeleeFrontLine.weight(a, b), 0.5, "a settled-less heading turn would have dropped it")


## A frontage anchored to one flank shifts the men sideways off the unit's position; the
## overlap is measured from the men.
func test_overlap_is_measured_from_the_men() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	a.set_frontage(15, 100.0)
	var shift: Vector2 = a.block_centre_offset()
	assert_gt(shift.length(), 90.0, "setup: the men stand off the unit's position")
	var b: Unit = _make_unit(120, shift + Vector2(0.0, 150.0), Vector2.UP, 1)
	assert_almost_eq(MeleeFrontLine.weight(a, b), 1.0, 0.0001, "b stands squarely before a's men")


## A pursuer's base range against a router leaves its own radius out, so the extension adds
## its whole front-rank depth: contact at front ranks within reach, not a radius short.
func test_a_pursuer_reaches_a_routers_front_rank() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2.ZERO, Vector2.UP, 1)
	b.state = Unit.State.ROUTING
	assert_eq(UnitTargeting.melee_contact_attacker_radius(Unit.RADIUS, b), 0.0, "setup: radius left out")
	var base: float = UnitTargeting.melee_contact_distance(a.attack_range, Unit.RADIUS, b)
	var fronts: float = MeleeFrontGeometry.front_rank_depth(a) + MeleeFrontGeometry.front_rank_depth(b)
	b.position = Vector2(0.0, fronts + a.attack_range - 1.0)   # front ranks just within reach
	var d_sq: float = a.position.distance_squared_to(b.position)
	assert_true(MeleeFrontLine.within_contact(a, b, base, d_sq, 0.0), "in contact at front ranks")
	assert_false(MeleeFrontLine.within_contact(a, b, base, d_sq), "a radius short if it were subtracted")


## Two deep blocks held at their front ranks stand further apart than the detection radius;
## the nearest-enemy search still finds the one in contact, and only when nothing is closer.
func test_a_frontal_contact_past_the_search_radius_is_found() -> void:
	var a: Unit = _make_unit(160, Vector2.ZERO, Vector2.DOWN, 0, 10)
	var b: Unit = _make_unit(160, Vector2(0.0, 260.0), Vector2.UP, 1, 10)
	assert_gt(a.position.distance_to(b.position), a.detection_range, "setup: past detection")
	var r: float = a.detection_range
	assert_eq(UnitTargeting.nearest_enemy(a), b, "auto-acquisition finds it in contact")
	assert_eq(UnitTargeting.nearest_enemy_to(a, a.position, r, false, false, Callable(), true), b,
		"with the fallback")
	assert_null(UnitTargeting.nearest_enemy_to(a, a.position, r), "a caller radius is a hard bound")
	assert_false(OrderGuards.enemy_in_range(a, 100.0), "so is a positive guard range")
	assert_true(OrderGuards.enemy_in_range(a, 0.0), "the default guard range acquires it")
	var near: Unit = _make_unit(30, Vector2(150.0, 0.0), Vector2.UP, 1, 10)
	assert_eq(UnitTargeting.nearest_enemy(a), near, "an enemy inside the radius comes first")
	near.position = Vector2(5000.0, 0.0)
	b.facing = Vector2.LEFT
	assert_null(UnitTargeting.nearest_enemy(a), "not when not frontal")


## A routed deep block pressed at its front rank by a frontal enemy past RALLY_CONTACT_RADIUS
## has not broken contact; turned away, the same enemy no longer holds it.
func test_the_rally_check_sees_a_frontal_press() -> void:
	var a: Unit = _make_unit(160, Vector2.ZERO, Vector2.DOWN, 0, 10)
	var b: Unit = _make_unit(160, Vector2(0.0, 250.0), Vector2.UP, 1, 10)
	assert_gt(250.0, Unit.RALLY_CONTACT_RADIUS, "setup: past the rally radius")
	a.state = Unit.State.ROUTING
	assert_false(a._can_rally(), "still in the press")
	b.facing = Vector2.LEFT
	assert_true(a._can_rally(), "contact broken once b no longer meets it frontally")


## A block deepened after the hash was built is read once Battle refreshes the deepest depth.
func test_refresh_reads_a_block_deepened_after_the_rebuild() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	SpatialHash.reset()
	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())
	var before: float = SpatialHash.max_query_extension()
	a.frontage_override = 5   # 24 ranks, written past the setters (which note it)
	assert_eq(SpatialHash.max_query_extension(), before, "setup: the rebuild's reading is stale")
	SpatialHash.refresh_query_extension(get_tree())
	assert_almost_eq(SpatialHash.max_query_extension(), MeleeFrontGeometry.query_extension(a), 0.001,
		"the refresh reads the deepened block")
	assert_gt(SpatialHash.max_query_extension(), before, "deeper than before")


## With dealt ranks, the count is the deepest rank plus one; a re-deal at the same headcount
## and file count, in the same frame, is read at once.
func test_the_rank_count_follows_dealt_ranks_and_a_re_deal() -> void:
	var u: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	u.file_major_reform_mode = Unit.ReformMode.FILE_MAJOR
	u.soldiers = 90
	var files := PackedInt32Array()
	var ranks := PackedInt32Array()
	for i in 90:
		files.append(i % 15)
		ranks.append(floori(i / 15.0))
	ranks[0] = 8   # one man dealt to the ninth rank of his file
	u._sim_soldier_file = files
	u._sim_soldier_rank = ranks
	u._file_assignment_files = 15
	u.note_file_assignment_changed()
	assert_eq(u.live_rank_count(15), 9, "the deepest dealt rank plus one")
	ranks[0] = 0
	u._sim_soldier_rank = ranks
	u.note_file_assignment_changed()   # every writer of the assignment calls it
	assert_eq(u.live_rank_count(15), 6, "the re-deal is read in the same frame")


## An order's in-place turn (an about-face) in progress leaves the men where they stood.
func test_an_order_turn_in_progress_keeps_the_front() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2(0.0, 150.0), Vector2.UP, 1)
	var turn: Order = Order.new_about_face()
	a.set_current_order(turn)
	turn.turn_start_facing = Vector2.DOWN
	turn.turn_target = Vector2.UP
	a.facing = Vector2.DOWN.rotated(deg_to_rad(120.0))   # partway through the about-face
	assert_true(a.is_order_turning(), "setup: the order turn is in progress")
	assert_almost_eq(MeleeFrontLine.weight(a, b), 1.0, 0.0001, "the men still face b")


## The square as `a`: the pair is symmetric, the line's reach then on the z side.
func test_a_square_on_either_side_pairs_the_same() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.LEFT)
	a.set_formation(Unit.FORMATION_SQUARE)
	var b: Unit = _make_unit(120, Vector2(0.0, 150.0), Vector2.UP, 1)
	var ab: Vector3 = MeleeFrontLine.pair(a, b)
	var ba: Vector3 = MeleeFrontLine.pair(b, a)
	assert_almost_eq(ab.x, 1.0, 0.0001, "the square meets the line")
	assert_almost_eq(ab.x, ba.x, 0.0001, "symmetric")
	assert_almost_eq(ab.y, ba.z, 0.001, "each side reads the same reach")
	assert_almost_eq(ab.z, MeleeFrontGeometry.front_rank_depth(b), 0.001, "the line's front rank")


## A flank-anchored frontage stands its men off its position: contact is measured between the
## men's centres, so a block squarely before the men is in contact though the positions are
## further apart than the frontal range.
func test_contact_is_measured_between_the_mens_centres() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	a.set_frontage(15, 100.0)
	var b: Unit = _make_unit(120, _men(a) + Vector2(0.0, 150.0), Vector2.UP, 1)
	var base: float = a.attack_range + 2.0 * Unit.RADIUS
	var reach: float = base + MeleeFrontLine.contact_extension(a, b)
	var d_sq: float = a.position.distance_squared_to(b.position)
	assert_gt(d_sq, reach * reach, "setup: the positions are past the frontal range")
	assert_true(MeleeFrontLine.within_contact(a, b, base, d_sq), "the men are in contact")


## within_contact matches the full range with a current hash too, and with the attacker's
## radius left out of the base (a pursuer against a router).
func test_within_contact_matches_with_a_current_hash() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(120, Vector2(0.0, 100.0), Vector2.UP, 1)
	SpatialHash.reset()
	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())
	for ra in [Unit.RADIUS, 0.0]:
		for y in [40.0, 120.0, 140.0, 150.0, 160.0, 300.0]:
			b.position = Vector2(0.0, y)
			var base: float = 62.0
			var reach: float = base + MeleeFrontLine.contact_extension(a, b, ra)
			var d_sq: float = y * y
			assert_eq(MeleeFrontLine.within_contact(a, b, base, d_sq, ra), d_sq <= reach * reach,
				"at %.0f with ra %.0f" % [y, ra])
