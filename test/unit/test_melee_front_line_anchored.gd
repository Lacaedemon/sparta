extends GutTest
## MeleeFrontLine with a flank-anchored frontage, whose men stand off the unit's position: the
## router anchor test keeps the positions' base range, the engaged floor pushes along the
## measured gap, the flank bearing and the contact facing read that gap, and the neighbourhood
## query covers the whole anchor shift.


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


## A routed block whose enemy's positions are within the base contact range keeps its anchor
## contact even when the enemy's anchored men stand further off than that range.
func test_a_router_keeps_anchor_contact_within_the_base_range() -> void:
	var a: Unit = _make_unit(30, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(30, Vector2(0.0, 50.0), Vector2.UP, 1)
	b.set_frontage(15, 60.0)
	a.state = Unit.State.ROUTING
	var c_dist: float = maxf(a.attack_range, b.attack_range) + 2.0 * Unit.RADIUS
	assert_lt(50.0, c_dist, "setup: the positions are within the base range")
	var reach: float = c_dist + MeleeFrontLine.contact_extension(a, b)
	assert_gt(MeleeFrontLine.toward(a, b).length(), reach, "setup: the men's gap is not")
	a._refresh_enemy_contact()
	assert_true(a._in_enemy_contact, "in contact")
	assert_true(a._router_anchor_contact, "and anchored, as within_contact reads it")


## Two engaged anchored blocks front to front, closer than their floor: _separate pushes along
## the reversed measured gap, and not at all once that gap reaches the floor.
func test_the_engaged_floor_pushes_along_the_measured_gap() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	a.set_frontage(15, 100.0)
	var men: Vector2 = _men(a)
	var b: Unit = _make_unit(120, men + Vector2(20.0, 60.0), Vector2.UP, 1)
	a.state = Unit.State.FIGHTING
	b.state = Unit.State.FIGHTING
	var p: Vector3 = MeleeFrontLine.pair(a, b)
	assert_gt(p.x, 0.5, "setup: frontal")
	var gap: Vector2 = MeleeFrontLine.toward(a, b)
	var min_dist: float = a._front_depth() + b._front_depth() + MeleeFrontLine.floor_from(p, a, b)
	assert_lt(gap.length(), min_dist, "setup: inside the floor")
	var before: Vector2 = a.position
	a._separate(1.0 / 60.0)
	var moved: Vector2 = a.position - before
	assert_gt(moved.length(), 0.0, "pushed")
	assert_almost_eq(moved.normalized().dot(-gap.normalized()), 1.0, 0.0001,
		"along the reversed measured gap, not the positions' gap")
	assert_lt(absf((b.position - a.position).normalized().dot(-gap.normalized())), 0.999,
		"setup: the positions' gap points elsewhere")
	b.position = a.position + men + Vector2(20.0, min_dist + 20.0)
	assert_gt(MeleeFrontLine.toward(a, b).length(), min_dist, "setup: the gap is past the floor")
	before = a.position
	a._separate(1.0 / 60.0)
	assert_eq(a.position, before, "no push at the floor")


## A head-on enemy before an anchored block's men is frontal, not a flank, though it stands
## well to the side of the block's position; the contact facing points at it the same way.
func test_the_flank_bearing_reads_the_measured_gap() -> void:
	var u: Unit = _make_unit(60, Vector2.ZERO, Vector2.DOWN)
	u.set_frontage(15, 150.0)
	var men: Vector2 = _men(u)
	var other: Unit = _make_unit(60, men + Vector2(0.0, 54.0), Vector2.UP, 1)
	assert_almost_eq(MeleeFrontLine.weight(u, other), 1.0, 0.0001, "setup: front to front")
	assert_lt(u.facing.dot((other.position - u.position).normalized()), 0.35,
		"setup: the positions alone would read a flank")
	assert_eq(UnitCombat.flank_multiplier(u, other), 1.0, "frontal")
	var to_point: Vector2 = (u.contact_point(other) - u.position).normalized()
	assert_almost_eq(to_point.dot(u.facing), 1.0, 0.0001, "the contact point is straight ahead")


## The neighbourhood query covers the whole anchor shift: two shallow blocks whose men meet
## at the base range, with anchors carrying their positions apart, stay within it.
func test_the_query_radius_covers_the_anchor_shift() -> void:
	var a: Unit = _make_unit(15, Vector2.ZERO, Vector2.DOWN)
	a.set_frontage(15, 20.0)
	var b: Unit = _make_unit(15, Vector2.ZERO, Vector2.UP, 1)
	b.set_frontage(15, 20.0)
	var base: float = maxf(a.attack_range, b.attack_range) + 2.0 * Unit.RADIUS
	b.position = _men(a) - _men(b) + Vector2(0.0, base - 1.0)
	var d_sq: float = a.position.distance_squared_to(b.position)
	assert_true(MeleeFrontLine.within_contact(a, b, base, d_sq), "setup: the men are in contact")
	var deepest: float = MeleeFrontGeometry.query_extension(b)
	var slack: float = SpatialHash.CELL_SIZE - base   # what the cell leaves past the base range
	assert_lt(sqrt(d_sq), MeleeFrontGeometry.query_radius(a, deepest) - slack,
		"the radius covers the positions' gap with no help from the cell's slack")


## A router re-entering contact counts its anchor only within router_contact_reentry_frac of
## the range, on the positions' branch as on the gap's.
func test_a_reentering_router_uses_the_shrunk_range() -> void:
	var a: Unit = _make_unit(30, Vector2.ZERO, Vector2.DOWN)
	var b: Unit = _make_unit(30, Vector2(0.0, 50.0), Vector2.UP, 1)
	a.state = Unit.State.ROUTING
	a._router_left_contact = true
	a.router_contact_reentry_frac = 0.5
	var c_dist: float = maxf(a.attack_range, b.attack_range) + 2.0 * Unit.RADIUS
	assert_almost_eq(MeleeFrontLine.contact_extension(a, b), 0.0, 0.0001, "setup: shallow blocks")
	assert_gt(50.0, 0.5 * c_dist, "setup: past the shrunk range")
	a._refresh_enemy_contact()
	assert_true(a._in_enemy_contact, "in contact at the full range")
	assert_false(a._router_anchor_contact, "but not anchored past the shrunk range")
	b.position = Vector2(0.0, 0.5 * c_dist - 1.0)
	a._refresh_enemy_contact()
	assert_true(a._router_anchor_contact, "anchored within it")


## within_contact with a current grid agrees with the full test for an anchored pair too.
func test_within_contact_matches_for_an_anchored_pair_with_a_current_hash() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	a.set_frontage(15, 60.0)
	var b: Unit = _make_unit(120, Vector2(0.0, 100.0), Vector2.UP, 1)
	SpatialHash.reset()
	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())
	var base: float = 62.0
	for x in [-80.0, -40.0, 0.0, 40.0]:
		for y in [40.0, 120.0, 150.0, 180.0, 300.0]:
			b.position = Vector2(x, y)
			var d_sq: float = a.position.distance_squared_to(b.position)
			var reach: float = base + MeleeFrontLine.contact_extension(a, b)
			var gap_sq: float = MeleeFrontLine.toward(a, b).length_squared()
			var want: bool = d_sq <= base * base or (MeleeFrontLine.weight(a, b) > 0.0
					and gap_sq <= reach * reach)
			assert_eq(MeleeFrontLine.within_contact(a, b, base, d_sq), want,
				"at (%.0f, %.0f)" % [x, y])


## A shield wall keeps its frontal cover against an attacker whose anchored men stand before it,
## though the attacker's position lies behind its front.
func test_a_shield_wall_keeps_its_front_against_anchored_men() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.UP)
	a.set_formation(Unit.FORMATION_SHIELD_WALL)
	var b: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN.rotated(deg_to_rad(30.0)), 1)
	b.set_frontage(15, 150.0)
	b.position = Vector2(0.0, -60.0) - _men(b)
	assert_lt(a.facing.dot(b.position - a.position), 0.0, "setup: the position is behind a's front")
	assert_gt(MeleeFrontLine.weight(a, b), 0.0, "setup: the men meet a's front")
	assert_almost_eq(a.melee_defense_factor(b), 1.0 - Unit.SHIELD_WALL_MELEE_DEFENSE, 0.0001,
		"the shield wall's frontal cover holds")


## The support stance's search finds a threat pressing its ward's front past the guard radius,
## and the ward's contact, not the supporter's, decides it.
func test_support_finds_a_threat_in_contact_with_the_ward() -> void:
	var ward: Unit = _make_unit(160, Vector2.ZERO, Vector2.DOWN, 0, 10)
	var e: Unit = _make_unit(160, Vector2(0.0, 260.0), Vector2.UP, 1, 10)
	var s: Unit = _make_unit(60, Vector2(0.0, -200.0), Vector2.DOWN)
	var r: float = Unit.SUPPORT_GUARD_RADIUS
	assert_gt(ward.position.distance_to(e.position), r, "setup: past the guard radius")
	assert_null(UnitTargeting.nearest_enemy_to(s, ward.position, r), "a hard radius misses it")
	assert_eq(UnitTargeting.nearest_enemy_to(s, ward.position, r, false, false, Callable(), true,
		ward), e, "the ward's frontal contact finds it")


## A block deepened mid-tick reports itself, so a lookup after it widens to find it.
func test_a_mid_tick_deepening_is_noted() -> void:
	var a: Unit = _make_unit(120, Vector2.ZERO, Vector2.DOWN)
	SpatialHash.reset()
	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())
	var before: float = SpatialHash.max_query_extension()
	a.set_frontage(5)   # 24 ranks, with no rebuild
	assert_eq(SpatialHash.max_query_extension(), before, "setup: stale")
	a.note_front_depth()
	assert_almost_eq(SpatialHash.max_query_extension(), MeleeFrontGeometry.query_extension(a), 0.001,
		"the noted depth")
