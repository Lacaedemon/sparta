extends GutTest
## ManPerception: what one soldier perceives of the enemy bodies around him. Every weight
## a test expects is derived from the module's own constants and pure weight functions,
## never typed in by hand.

const ManPerception = preload("res://scripts/ManPerception.gd")
const PathField = preload("res://scripts/PathField.gd")
const Perception = preload("res://scripts/Perception.gd")

# Sight radius for the bare test units, world units: a round figure well inside any field.
const SIGHT: float = 300.0
# The observing man stands at the origin, facing +y (Vector2.DOWN in screen axes).
const MAN_POS := Vector2.ZERO
const MAN_FACING := Vector2.DOWN
const EPS: float = 1e-5


var _saved_active_field: Object = null


func before_each() -> void:
	SpatialHash.reset()
	# Perception.perceives falls back to the global sight field when given neither terrain
	# nor a field; isolate these tests from whatever field another script left there.
	_saved_active_field = PathField.active
	PathField.active = null


func after_each() -> void:
	SpatialHash.reset()
	PathField.active = _saved_active_field


## A bare (out-of-tree) unit carrying the given bodies, all facing `body_facing`.
func _unit(uid: int, team: int, bodies: PackedVector2Array,
		body_facing: Vector2 = MAN_FACING) -> Unit:
	var u: Unit = autofree(Unit.new())
	_dress(u, uid, team, bodies, body_facing)
	return u


func _dress(u: Unit, uid: int, team: int, bodies: PackedVector2Array, body_facing: Vector2) -> void:
	u.uid = uid
	u.team = team
	u.sight_range = SIGHT
	u.facing = body_facing
	u.state = Unit.State.IDLE
	var centre := Vector2.ZERO
	for p in bodies:
		centre += p
	u.position = centre / maxf(1.0, float(bodies.size()))
	u._sim_soldier_pos = bodies
	var facings := PackedVector2Array()
	for _p in bodies:
		facings.push_back(body_facing)
	u._sim_soldier_facing = facings
	u.soldiers = bodies.size()


## The observing man alone in his own unit (team 0).
func _observer() -> Unit:
	return _unit(1, 0, PackedVector2Array([MAN_POS]))


func _perceive(observer: Unit, units: Array, frame: int = 1, terrain: Array = [],
		mp: ManPerception = null) -> Dictionary:
	if mp == null:
		mp = ManPerception.new()
	mp.prepare(frame, units, terrain, null)
	return mp.perceive(observer, 0)


# --- the acceptance case ----------------------------------------------------------------


func test_an_enemy_behind_and_none_ahead_gives_a_backward_threat() -> void:
	var man := _observer()
	var behind := Vector2(0.0, -100.0)   # straight behind a man facing +y
	var foe := _unit(2, 1, PackedVector2Array([behind]))
	var r: Dictionary = _perceive(man, [man, foe])
	var t: Vector2 = r["threat"]
	var expected: float = ManPerception.distance_weight(100.0, SIGHT) * ManPerception.REAR_WEIGHT
	assert_almost_eq(t.x, 0.0, EPS, "no sideways component")
	assert_almost_eq(t.y, -expected, EPS,
		"the threat points backward, weighted by distance and the rear weight")
	assert_lt(t.dot(MAN_FACING), 0.0, "backward: against the man's facing")
	assert_eq(r["perceived"], 1)


func test_a_foe_ahead_outweighs_the_same_foe_behind() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 100.0), Vector2(0.0, -100.0)]))
	var t: Vector2 = _perceive(man, [man, foe])["threat"]
	var dw: float = ManPerception.distance_weight(100.0, SIGHT)
	assert_almost_eq(t.x, 0.0, EPS)
	assert_almost_eq(t.y, dw * (1.0 - ManPerception.REAR_WEIGHT), EPS,
		"the foe in his visual field counts in full, the one behind him at the rear weight")


# --- the weights ---------------------------------------------------------------------


func test_arc_weight_is_full_in_the_visual_field_and_falls_to_the_rear_weight() -> void:
	var half: float = ManPerception.VISUAL_FIELD_HALF_ANGLE
	var rear: float = ManPerception.REAR_WEIGHT
	assert_eq(ManPerception.arc_weight(MAN_FACING, MAN_FACING, half, rear), 1.0, "straight ahead")
	assert_eq(ManPerception.arc_weight(MAN_FACING, Vector2.RIGHT, half, rear), 1.0,
		"square to his side is inside the visual field")
	assert_almost_eq(ManPerception.arc_weight(MAN_FACING, MAN_FACING.rotated(half - 1e-4), half, rear),
		1.0, EPS, "just inside the field edge")
	assert_almost_eq(ManPerception.arc_weight(MAN_FACING, -MAN_FACING, half, rear), rear, EPS,
		"directly behind")
	var mid: float = (half + PI) * 0.5
	assert_almost_eq(ManPerception.arc_weight(MAN_FACING, MAN_FACING.rotated(mid), half, rear),
		lerpf(1.0, rear, 0.5), EPS, "halfway from the field edge to directly behind")
	assert_almost_eq(ManPerception.arc_weight(MAN_FACING, MAN_FACING.rotated(-mid), half, rear),
		lerpf(1.0, rear, 0.5), EPS, "the same on his other side")


func test_arc_weight_is_continuous_at_the_field_edge() -> void:
	var half: float = ManPerception.VISUAL_FIELD_HALF_ANGLE
	var rear: float = ManPerception.REAR_WEIGHT
	var outside: float = ManPerception.arc_weight(MAN_FACING, MAN_FACING.rotated(half + 1e-4), half, rear)
	assert_almost_eq(outside, 1.0, 1e-3, "no step at the edge of the visual field")
	assert_lt(outside, 1.0, "past the edge the weight has begun to fall")


func test_the_rear_weight_default_lies_between_none_and_full() -> void:
	assert_gt(ManPerception.REAR_WEIGHT, 0.0, "a foe behind a man must still register")
	assert_lt(ManPerception.REAR_WEIGHT, 1.0, "and weigh less than one he can see")


func test_distance_weight_falls_linearly_to_zero_at_the_edge_of_sight() -> void:
	assert_eq(ManPerception.distance_weight(0.0, SIGHT), 1.0)
	assert_almost_eq(ManPerception.distance_weight(SIGHT * 0.25, SIGHT), 0.75, EPS)
	assert_eq(ManPerception.distance_weight(SIGHT, SIGHT), 0.0)
	assert_eq(ManPerception.distance_weight(SIGHT * 2.0, SIGHT), 0.0)
	assert_eq(ManPerception.distance_weight(1.0, 0.0), 0.0, "no sight, no weight")


func test_a_nearer_foe_weighs_more() -> void:
	var man := _observer()
	var near := _unit(2, 1, PackedVector2Array([Vector2(0.0, 50.0)]))
	var far := _unit(3, 1, PackedVector2Array([Vector2(0.0, 200.0)]))
	var near_t: Vector2 = _perceive(man, [man, near])["threat"]
	var far_t: Vector2 = _perceive(man, [man, far])["threat"]
	assert_gt(near_t.length(), far_t.length())
	assert_almost_eq(near_t.y, ManPerception.distance_weight(50.0, SIGHT), EPS)
	assert_almost_eq(far_t.y, ManPerception.distance_weight(200.0, SIGHT), EPS)


# --- sight radius ----------------------------------------------------------------------


func test_a_foe_beyond_sight_is_not_perceived() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, SIGHT + 1.0)]))
	var r: Dictionary = _perceive(man, [man, foe])
	assert_eq(r["perceived"], 0)
	assert_eq(r["threat"], Vector2.ZERO)
	assert_null(r["nearest_unit"])
	assert_eq(r["nearest_index"], -1)
	assert_eq(r["nearest_distance"], INF)


func test_a_foe_on_the_edge_of_sight_is_perceived_with_no_weight() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, SIGHT)]))
	var r: Dictionary = _perceive(man, [man, foe])
	assert_eq(r["perceived"], 1, "inclusive at the boundary, as Perception.perceives is")
	assert_eq(r["threat"], Vector2.ZERO)
	assert_almost_eq(float(r["nearest_distance"]), SIGHT, EPS)


func test_default_radius_is_the_mans_unit_sight_range() -> void:
	var man := _observer()
	var inside := _unit(2, 1, PackedVector2Array([Vector2(0.0, SIGHT - 1.0)]))
	var beyond := _unit(3, 1, PackedVector2Array([Vector2(0.0, -(SIGHT + 1.0))]))
	assert_eq(_perceive(man, [man, inside, beyond])["perceived"], 1, "out to his unit's sight_range")
	man.sight_range = SIGHT * 0.5
	assert_eq(_perceive(man, [man, inside, beyond], 2)["perceived"], 0, "it follows the unit's range")
	man.sight_range = SIGHT
	man.state = Unit.State.ROUTING
	assert_eq(_perceive(man, [man, inside, beyond], 3)["perceived"], 1,
		"a fleeing man still sees: where he looks is his facing, not a cut radius")


func test_a_caller_can_set_the_sight_radius() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 100.0)]))
	var mp := ManPerception.new()
	mp.sight_radius = 50.0
	assert_eq(_perceive(man, [man, foe], 1, [], mp)["perceived"], 0)
	var mp2 := ManPerception.new()
	mp2.sight_radius = 400.0
	var r: Dictionary = _perceive(man, [man, foe], 1, [], mp2)
	assert_almost_eq((r["threat"] as Vector2).y, ManPerception.distance_weight(100.0, 400.0), EPS)


func test_a_caller_can_set_the_arc() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, -100.0)]))
	var mp := ManPerception.new()
	mp.rear_weight = 1.0
	var t: Vector2 = _perceive(man, [man, foe], 1, [], mp)["threat"]
	assert_almost_eq(t.y, -ManPerception.distance_weight(100.0, SIGHT), EPS,
		"rear weight 1: a foe behind counts in full")
	var side := _unit(3, 1, PackedVector2Array([Vector2(100.0, 0.0)]))
	var narrow := ManPerception.new()
	narrow.visual_field_half_angle = deg_to_rad(45.0)
	var ts: Vector2 = _perceive(man, [man, side], 1, [], narrow)["threat"]
	var expected: float = ManPerception.distance_weight(100.0, SIGHT) \
		* ManPerception.arc_weight(MAN_FACING, Vector2.RIGHT, deg_to_rad(45.0), ManPerception.REAR_WEIGHT)
	assert_almost_eq(ts.x, expected, EPS, "a narrow helmet field puts a side foe in the falloff")
	assert_lt(ts.x, ManPerception.distance_weight(100.0, SIGHT))


# --- the man's own facing -----------------------------------------------------------------


func test_the_arc_follows_the_mans_own_facing_not_his_units() -> void:
	var man := _observer()
	man.facing = MAN_FACING
	man._sim_soldier_facing = PackedVector2Array([-MAN_FACING])   # he alone has turned about
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, -100.0)]))
	var t: Vector2 = _perceive(man, [man, foe])["threat"]
	assert_almost_eq(t.y, -ManPerception.distance_weight(100.0, SIGHT), EPS,
		"the foe is in front of the man himself, so it counts in full")


# --- who counts -------------------------------------------------------------------------


func test_friends_and_the_dead_are_not_threats() -> void:
	var man := _observer()
	var friend := _unit(2, 0, PackedVector2Array([Vector2(0.0, 40.0)]))
	var dead := _unit(3, 1, PackedVector2Array([Vector2(0.0, 60.0)]))
	dead.state = Unit.State.DEAD
	var r: Dictionary = _perceive(man, [man, friend, dead])
	assert_eq(r["perceived"], 0)
	assert_eq(r["threat"], Vector2.ZERO)


func test_occluding_terrain_hides_a_foe_from_the_man() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 100.0)]))
	var wall := {"rect": Rect2(-50.0, 40.0, 100.0, 20.0), "kind": "block", "sight": "block"}
	assert_eq(_perceive(man, [man, foe], 1, [wall])["perceived"], 0, "behind the wall: unseen")
	var aside := {"rect": Rect2(200.0, 40.0, 100.0, 20.0), "kind": "block", "sight": "block"}
	assert_eq(_perceive(man, [man, foe], 1, [aside])["perceived"], 1, "a wall off his line: seen")


func test_screening_terrain_shortens_the_mans_sight() -> void:
	var man := _observer()
	var screen := {"rect": Rect2(-50.0, 40.0, 100.0, 20.0), "kind": "slow", "sight": "screen"}
	var factor: float = Unit.SIGHT_SCREEN_FACTOR
	var near := _unit(2, 1, PackedVector2Array([Vector2(0.0, SIGHT * factor - 1.0)]))
	var far := _unit(3, 1, PackedVector2Array([Vector2(0.0, SIGHT * factor + 1.0)]))
	assert_eq(_perceive(man, [man, near], 1, [screen])["perceived"], 1, "inside the screened range")
	assert_eq(_perceive(man, [man, far], 1, [screen])["perceived"], 0, "beyond the screened range")


func test_a_foe_at_his_elbow_is_seen_though_its_units_centre_is_far() -> void:
	# A wide enemy line whose centre is far beyond the man's sight: its near wing still
	# stands at his elbow, and he sees that man himself.
	var man := _observer()
	var line := _unit(2, 1, PackedVector2Array([Vector2(0.0, 20.0), Vector2(4000.0, 20.0)]))
	assert_gt(line.position.length(), SIGHT * 2.0, "precondition: the unit centre is far away")
	var r: Dictionary = _perceive(man, [man, line])
	assert_eq(r["perceived"], 1)
	assert_eq(r["nearest_index"], 0)


func test_nearest_foe_ignores_the_arc() -> void:
	var man := _observer()
	var ahead := _unit(2, 1, PackedVector2Array([Vector2(0.0, 120.0)]))
	var behind := _unit(3, 1, PackedVector2Array([Vector2(5.0, -30.0), Vector2(0.0, -80.0)]))
	var r: Dictionary = _perceive(man, [man, ahead, behind])
	assert_eq(r["nearest_unit"], behind, "the foe at his back is nearest")
	assert_eq(r["nearest_index"], 0)
	assert_almost_eq(float(r["nearest_distance"]), Vector2(5.0, -30.0).length(), EPS)
	assert_eq(r["perceived"], 3)


func test_threat_sums_every_perceived_foe() -> void:
	var man := _observer()
	var bodies := PackedVector2Array([Vector2(60.0, 80.0), Vector2(-150.0, 0.0), Vector2(0.0, -90.0)])
	var foe := _unit(2, 1, bodies)
	var expected := Vector2.ZERO
	for b in bodies:
		var d: float = b.length()
		expected += b / d * ManPerception.distance_weight(d, SIGHT) * ManPerception.arc_weight(
			MAN_FACING, b, ManPerception.VISUAL_FIELD_HALF_ANGLE, ManPerception.REAR_WEIGHT)
	var t: Vector2 = _perceive(man, [man, foe])["threat"]
	assert_almost_eq(t.x, expected.x, EPS)
	assert_almost_eq(t.y, expected.y, EPS)


func test_a_man_without_a_body_perceives_nothing() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 50.0)]))
	var mp := ManPerception.new()
	mp.prepare(1, [man, foe], [], null)
	assert_eq(mp.perceive(man, 5)["perceived"], 0, "out-of-range index")
	assert_eq(mp.perceive(man, -1)["perceived"], 0, "negative index")
	var far_tier := _unit(3, 0, PackedVector2Array())
	assert_eq(mp.perceive(far_tier, 0)["perceived"], 0, "a far-tier unit has no bodies")


func test_a_foe_on_the_mans_own_spot_is_nearest_but_has_no_direction() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([MAN_POS]))
	var r: Dictionary = _perceive(man, [man, foe])
	assert_eq(r["perceived"], 1)
	assert_eq(r["nearest_distance"], 0.0)
	assert_eq(r["threat"], Vector2.ZERO)


# --- caching and read-only -------------------------------------------------------------


func test_the_answer_is_cached_for_the_frame() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 100.0)]))
	var mp := ManPerception.new()
	mp.prepare(1, [man, foe], [], null)
	var first: Dictionary = mp.perceive(man, 0)
	foe._sim_soldier_pos = PackedVector2Array([Vector2(0.0, -100.0)])
	mp.prepare(1, [man, foe], [], null)   # same frame: a no-op
	assert_eq(mp.perceive(man, 0), first, "same frame: the cached answer")
	mp.prepare(2, [man, foe], [], null)
	assert_lt((mp.perceive(man, 0)["threat"] as Vector2).y, 0.0, "a new frame recomputes")


func test_a_change_in_body_count_drops_the_units_cache() -> void:
	var man := _unit(1, 0, PackedVector2Array([MAN_POS, Vector2(0.0, -500.0)]))
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 100.0)]))
	var mp := ManPerception.new()
	mp.prepare(1, [man, foe], [], null)
	assert_eq(mp.perceive(man, 0)["perceived"], 1, "man 0 sees the foe")
	assert_eq(mp.perceive(man, 1)["perceived"], 0, "man 1 stands out of sight")
	# Man 0 falls and the arrays re-pack: index 0 now names the man who stood at index 1.
	man._sim_soldier_pos = PackedVector2Array([Vector2(0.0, -500.0)])
	man._sim_soldier_facing = PackedVector2Array([MAN_FACING])
	assert_eq(mp.perceive(man, 0)["perceived"], 0, "index 0 is answered for the man now there")


func test_the_query_writes_nothing_back() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(10.0, 100.0), Vector2(0.0, -40.0)]))
	var before := [man.position, man.facing, man.state, man._sim_soldier_pos, man._sim_soldier_facing,
		foe.position, foe.facing, foe.state, foe._sim_soldier_pos, foe._sim_soldier_facing]
	_perceive(man, [man, foe])
	var after := [man.position, man.facing, man.state, man._sim_soldier_pos, man._sim_soldier_facing,
		foe.position, foe.facing, foe.state, foe._sim_soldier_pos, foe._sim_soldier_facing]
	assert_eq(after, before)


# --- the spatial hash path ---------------------------------------------------------------


func _tree_unit(uid: int, team: int, bodies: PackedVector2Array) -> Unit:
	var u: Unit = Unit.new()
	add_child_autofree(u)
	_dress(u, uid, team, bodies, MAN_FACING)
	return u


func test_the_hash_path_matches_the_list_path_bit_for_bit() -> void:
	var man := _tree_unit(1, 0, PackedVector2Array([Vector2(1000.0, 1000.0), Vector2(1010.0, 990.0)]))
	var a := _tree_unit(2, 1, PackedVector2Array([Vector2(1000.0, 1150.0), Vector2(1030.0, 1160.0)]))
	var b := _tree_unit(3, 1, PackedVector2Array([Vector2(820.0, 1000.0), Vector2(1000.0, 880.0)]))
	var far := _tree_unit(4, 1, PackedVector2Array([Vector2(3000.0, 3000.0)]))
	var units: Array = [man, a, b, far]
	var listed := ManPerception.new()
	listed.prepare(1, units, [], null)
	SpatialHash.rebuild(get_tree(), 7)
	assert_true(SpatialHash.is_current(7))
	var hashed := ManPerception.new()
	hashed.prepare(7, units, [], null)
	for i in range(2):
		var l: Dictionary = listed.perceive(man, i)
		var h: Dictionary = hashed.perceive(man, i)
		assert_eq(h["threat"], l["threat"], "man %d: same threat" % i)
		assert_eq(h["nearest_unit"], l["nearest_unit"])
		assert_eq(h["nearest_index"], l["nearest_index"])
		assert_eq(h["perceived"], l["perceived"])
		assert_gt(int(h["perceived"]), 0, "precondition: man %d perceives someone" % i)


func test_the_hash_path_reaches_a_wide_blocks_far_bodies() -> void:
	# The block's centre sits far outside the man's sight, but one of its bodies stands
	# inside it: the query must still find that body through the hash.
	var man := _tree_unit(1, 0, PackedVector2Array([Vector2(0.0, 0.0)]))
	var wide := _tree_unit(2, 1, PackedVector2Array([Vector2(0.0, 100.0), Vector2(2000.0, 100.0)]))
	assert_gt(wide.position.distance_to(Vector2.ZERO), SIGHT + SpatialHash.CELL_SIZE,
		"precondition: the block's centre is beyond sight plus the hash pad")
	SpatialHash.rebuild(get_tree(), 3)
	assert_true(SpatialHash.is_current(3), "precondition: the hash path runs")
	var mp := ManPerception.new()
	mp.prepare(3, [man, wide], [], null)
	var r: Dictionary = mp.perceive(man, 0)
	assert_eq(r["perceived"], 1)
	assert_eq(r["nearest_index"], 0)


func test_the_hash_path_finds_a_unit_that_moved_since_the_rebuild() -> void:
	# The hash buckets positions at the start of the frame. A foe that has since stepped
	# into the man's sight from a cell just past his query ring must still be found.
	var cell: float = SpatialHash.CELL_SIZE
	var rings: int = 3
	var radius: float = rings * cell                   # the query ring spans exactly 3 cells
	var man_pos := Vector2(0.0, cell - 1.0)            # the far edge of his own cell
	var start := Vector2(0.0, (rings + 1) * cell + 8.0)   # first cell past the ring
	var moved := Vector2(0.0, man_pos.y + radius - 1.0)   # just inside his sight
	assert_lt(start.y - moved.y, cell, "precondition: the foe moved less than one cell")
	var man := _tree_unit(1, 0, PackedVector2Array([man_pos]))
	var foe := _tree_unit(2, 1, PackedVector2Array([start]))
	SpatialHash.rebuild(get_tree(), 5)
	assert_true(SpatialHash.is_current(5), "precondition: the hash path runs")
	foe.position = moved
	foe._sim_soldier_pos = PackedVector2Array([moved])
	assert_false(SpatialHash.query(man_pos, radius).has(foe),
		"precondition: an unpadded query of the stale grid misses it")
	var mp := ManPerception.new()
	mp.sight_radius = radius
	mp.prepare(5, [man, foe], [], null)
	assert_eq(mp.perceive(man, 0)["perceived"], 1)


func test_a_reaped_foe_drops_a_cached_nearest_index() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 300.0) * 0.1, Vector2(0.0, 60.0)]))
	var mp := ManPerception.new()
	mp.prepare(1, [man, foe], [], null)
	assert_eq(mp.perceive(man, 0)["nearest_index"], 0, "the foe at 30 is nearest")
	# The nearest foe falls and the arrays re-pack: index 0 now names the man at 60.
	foe._sim_soldier_pos = PackedVector2Array([Vector2(0.0, 60.0)])
	foe._sim_soldier_facing = PackedVector2Array([MAN_FACING])
	var r: Dictionary = mp.perceive(man, 0)
	assert_eq(r["nearest_index"], 0)
	assert_almost_eq(float(r["nearest_distance"]), 60.0, EPS, "recomputed for the man now there")
	assert_eq(r["perceived"], 1)


func test_a_unit_that_gains_bodies_mid_frame_is_perceived() -> void:
	var man := _observer()
	var promoted := _unit(2, 1, PackedVector2Array())   # far tier: no bodies yet
	var other := _unit(3, 0, PackedVector2Array([Vector2(500.0, 500.0)]))
	var mp := ManPerception.new()
	mp.prepare(1, [man, promoted, other], [], null)
	assert_eq(mp.perceive(other, 0)["perceived"], 0, "first query of the frame: nothing near")
	promoted._sim_soldier_pos = PackedVector2Array([Vector2(0.0, 80.0)])
	promoted._sim_soldier_facing = PackedVector2Array([MAN_FACING])
	promoted.position = Vector2(0.0, 80.0)
	assert_eq(mp.perceive(man, 0)["perceived"], 1, "promoted later in the frame: seen")


func test_out_of_range_parameters_are_reported_and_refused() -> void:
	var mp := ManPerception.new()
	mp.rear_weight = 0.0
	assert_push_error("rear_weight")
	assert_eq(mp.rear_weight, ManPerception.REAR_WEIGHT, "a zero rear weight is refused")
	mp.rear_weight = 1.5
	assert_push_error("rear_weight")
	assert_eq(mp.rear_weight, ManPerception.REAR_WEIGHT, "above 1 is refused")
	mp.visual_field_half_angle = 4.0
	assert_push_error("visual_field_half_angle")
	assert_eq(mp.visual_field_half_angle, ManPerception.VISUAL_FIELD_HALF_ANGLE)
	mp.visual_field_half_angle = -0.1
	assert_push_error("visual_field_half_angle")
	assert_eq(mp.visual_field_half_angle, ManPerception.VISUAL_FIELD_HALF_ANGLE)
	mp.rear_weight = 0.25
	assert_eq(mp.rear_weight, 0.25, "an in-range value passes through")
	mp.visual_field_half_angle = PI
	assert_eq(mp.visual_field_half_angle, PI, "the closed bound is allowed")


# --- the compiled sight rule matches Perception.perceives ---------------------------------


# Terrain with two overlapping screens of different factors and a block, so the factor
# product, its order and the occlusion all show up in a grid of sightlines.
func _mixed_terrain() -> Array:
	return [
		{"rect": Rect2(-120.0, 60.0, 140.0, 40.0), "kind": "slow", "sight": "screen", "screen_factor": 0.7},
		{"rect": Rect2(-40.0, 80.0, 200.0, 60.0), "kind": "slow", "sight": "screen"},
		{"rect": Rect2(60.0, -140.0, 50.0, 90.0), "kind": "block"},
		{"rect": Rect2(-200.0, -60.0, 30.0, 30.0), "kind": "block", "sight": "screen", "screen_factor": 0.3},
	]


func _sightline_grid() -> Array:
	var out: Array = []
	for gx in range(-12, 13):
		for gy in range(-12, 13):
			out.append(Vector2(gx * 25.0 + 3.0, gy * 25.0 - 7.0))
	return out


func _assert_matches_perceives(terrain: Array, path_field: Object, label: String) -> void:
	var o := Vector2(5.0, 2.0)
	var rule: Dictionary = ManPerception.sight_rule(terrain, path_field)
	var seen := 0
	var hidden := 0
	for t in _sightline_grid():
		if o.distance_squared_to(t) > SIGHT * SIGHT:
			continue
		var expected: bool = Perception.perceives(o, SIGHT, t, terrain, path_field)
		assert_eq(ManPerception.line_of_sight(o, SIGHT, t, rule), expected, "%s: %s" % [label, t])
		if expected:
			seen += 1
		else:
			hidden += 1
	assert_gt(seen, 0, "%s: precondition: some sightlines are open" % label)
	assert_gt(hidden, 0, "%s: precondition: some sightlines are cut" % label)


func test_line_of_sight_matches_perceives_from_terrain() -> void:
	_assert_matches_perceives(_mixed_terrain(), null, "terrain")


func test_line_of_sight_matches_perceives_with_a_sight_field() -> void:
	var terrain := _mixed_terrain()
	var field := PathField.new(Rect2(-1000.0, -1000.0, 2000.0, 2000.0))
	field.block_rect(Rect2(-90.0, -150.0, 40.0, 60.0))   # a block only the field knows
	_assert_matches_perceives(terrain, field, "field")


func test_line_of_sight_matches_perceives_on_the_global_field() -> void:
	var field := PathField.new(Rect2(-1000.0, -1000.0, 2000.0, 2000.0))
	field.block_rect(Rect2(60.0, -140.0, 50.0, 90.0))
	PathField.active = field
	_assert_matches_perceives([], null, "global")


func test_a_far_wall_is_left_out_of_the_mans_sightlines() -> void:
	# Only terrain inside the box around his sight disc can cut a sightline; a wall far off
	# changes nothing, and one across his line still hides the foe.
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 100.0)]))
	var far_wall := {"rect": Rect2(-50.0, 2000.0, 100.0, 20.0), "kind": "block"}
	assert_eq(_perceive(man, [man, foe], 1, [far_wall])["perceived"], 1)
	var near_wall := {"rect": Rect2(-50.0, 40.0, 100.0, 20.0), "kind": "block"}
	assert_eq(_perceive(man, [man, foe], 1, [far_wall, near_wall])["perceived"], 0)


func test_a_host_that_gains_a_distant_body_mid_frame_is_remeasured() -> void:
	var man := _unit(1, 0, PackedVector2Array([Vector2.ZERO, Vector2(1.0, 0.0)]))
	var host := _unit(2, 1, PackedVector2Array([Vector2(0.0, 1000.0)]))
	var mp := ManPerception.new()
	mp.prepare(1, [man, host], [], null)
	assert_eq(mp.perceive(man, 0)["perceived"], 0, "the host stands far out of sight")
	# A newcomer is inserted into the host near the man; the host's centre stays put.
	host._sim_soldier_pos = PackedVector2Array([Vector2(0.0, 1000.0), Vector2(0.0, 250.0)])
	host._sim_soldier_facing = PackedVector2Array([MAN_FACING, MAN_FACING])
	assert_eq(mp.perceive(man, 1)["perceived"], 1, "the newcomer at 250 is seen")
