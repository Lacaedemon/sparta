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
	var men: Vector2 = a.men_centre_offset()
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
	var men: Vector2 = u.men_centre_offset()
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
	b.position = a.men_centre_offset() - b.men_centre_offset() + Vector2(0.0, base - 1.0)
	var d_sq: float = a.position.distance_squared_to(b.position)
	assert_true(MeleeFrontLine.within_contact(a, b, base, d_sq), "setup: the men are in contact")
	var deepest: float = MeleeFrontGeometry.query_extension(b)
	var slack: float = SpatialHash.CELL_SIZE - base   # what the cell leaves past the base range
	assert_lt(sqrt(d_sq), MeleeFrontGeometry.query_radius(a, deepest) - slack,
		"the radius covers the positions' gap with no help from the cell's slack")
