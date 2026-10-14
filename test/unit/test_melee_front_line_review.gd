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
	assert_gt(p.z, 0.0, "the square reaches its outer rank")
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
	assert_eq(UnitTargeting.nearest_enemy_to(a, a.position, a.detection_range), b, "found in contact")
	b.facing = Vector2.LEFT
	assert_null(UnitTargeting.nearest_enemy_to(a, a.position, a.detection_range), "not when not frontal")


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
	var before: float = SpatialHash.max_extension_depth()
	a.set_frontage(5)   # 24 ranks
	assert_eq(SpatialHash.max_extension_depth(), before, "setup: the rebuild's reading is stale")
	SpatialHash.refresh_extension_depth(get_tree())
	assert_almost_eq(SpatialHash.max_extension_depth(), MeleeFrontGeometry.extension_depth(a), 0.001,
		"the refresh reads the deepened block")
	assert_gt(SpatialHash.max_extension_depth(), before, "deeper than before")


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
	assert_eq(u.live_rank_count(15), 9, "the deepest dealt rank plus one")
	ranks[0] = 0
	u._sim_soldier_rank = ranks
	assert_eq(u.live_rank_count(15), 6, "the re-deal is read in the same frame")
