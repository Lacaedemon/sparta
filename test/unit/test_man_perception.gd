extends GutTest
## ManPerception: what one soldier perceives of the enemy bodies around him. Every weight
## a test expects is derived from the module's own constants and pure weight functions,
## never typed in by hand.

const ManPerception = preload("res://scripts/ManPerception.gd")
const Perception = preload("res://scripts/Perception.gd")

# Sight radius for the bare test units, world units: a round figure well inside any field.
const SIGHT: float = 300.0
# The observing man stands at the origin, facing +y (Vector2.DOWN in screen axes).
const MAN_POS := Vector2.ZERO
const MAN_FACING := Vector2.DOWN
const EPS: float = 1e-5


func before_each() -> void:
	SpatialHash.reset()


func after_each() -> void:
	SpatialHash.reset()


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


func _perceive(observer: Unit, units: Array, frame: int = 1, seen: Dictionary = {},
		mp: ManPerception = null) -> Dictionary:
	if mp == null:
		mp = ManPerception.new()
	mp.prepare(frame, units, seen)
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
		"square to his side is inside a 107-degree half-field")
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


func test_the_visual_field_constant_is_the_cited_107_degrees() -> void:
	assert_almost_eq(rad_to_deg(ManPerception.VISUAL_FIELD_HALF_ANGLE), 107.0, 1e-4)
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


func test_default_radius_is_the_mans_unit_observer_range() -> void:
	var man := _observer()
	man.state = Unit.State.ROUTING
	var routed_range: float = Perception.observer_range(man)
	assert_lt(routed_range, SIGHT, "precondition: routing cuts the observer range")
	var gap: float = (routed_range + SIGHT) * 0.5   # inside SIGHT, beyond the routing range
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, gap)]))
	assert_eq(_perceive(man, [man, foe])["perceived"], 0, "a fleeing man's sight is cut")
	man.state = Unit.State.IDLE
	assert_eq(_perceive(man, [man, foe], 2)["perceived"], 1, "a formed man sees the full range")


func test_a_caller_can_set_the_sight_radius() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 100.0)]))
	var mp := ManPerception.new()
	mp.sight_radius = 50.0
	assert_eq(_perceive(man, [man, foe], 1, {}, mp)["perceived"], 0)
	var mp2 := ManPerception.new()
	mp2.sight_radius = 400.0
	var r: Dictionary = _perceive(man, [man, foe], 1, {}, mp2)
	assert_almost_eq((r["threat"] as Vector2).y, ManPerception.distance_weight(100.0, 400.0), EPS)


func test_a_caller_can_set_the_arc() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, -100.0)]))
	var mp := ManPerception.new()
	mp.rear_weight = 1.0
	var t: Vector2 = _perceive(man, [man, foe], 1, {}, mp)["threat"]
	assert_almost_eq(t.y, -ManPerception.distance_weight(100.0, SIGHT), EPS,
		"rear weight 1: a foe behind counts in full")
	var side := _unit(3, 1, PackedVector2Array([Vector2(100.0, 0.0)]))
	var narrow := ManPerception.new()
	narrow.visual_field_half_angle = deg_to_rad(45.0)
	var ts: Vector2 = _perceive(man, [man, side], 1, {}, narrow)["threat"]
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


func test_fog_hides_bodies_of_units_the_team_does_not_see() -> void:
	var man := _observer()
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 100.0)]))
	assert_eq(_perceive(man, [man, foe], 1, {0: {}})["perceived"], 0, "unseen unit: no bodies")
	assert_eq(_perceive(man, [man, foe], 1, {0: {2: true}})["perceived"], 1, "seen unit counts")
	assert_eq(_perceive(man, [man, foe], 1, {1: {}})["perceived"], 1,
		"another team's fog does not apply to this man")
	assert_eq(_perceive(man, [man, foe], 1, {0: null})["perceived"], 1, "null: no fog")


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
	mp.prepare(1, [man, foe])
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
	mp.prepare(1, [man, foe])
	var first: Dictionary = mp.perceive(man, 0)
	foe._sim_soldier_pos = PackedVector2Array([Vector2(0.0, -100.0)])
	mp.prepare(1, [man, foe])   # same frame: a no-op
	assert_eq(mp.perceive(man, 0), first, "same frame: the cached answer")
	mp.prepare(2, [man, foe])
	assert_lt((mp.perceive(man, 0)["threat"] as Vector2).y, 0.0, "a new frame recomputes")


func test_a_change_in_body_count_drops_the_units_cache() -> void:
	var man := _unit(1, 0, PackedVector2Array([MAN_POS, Vector2(0.0, -500.0)]))
	var foe := _unit(2, 1, PackedVector2Array([Vector2(0.0, 100.0)]))
	var mp := ManPerception.new()
	mp.prepare(1, [man, foe])
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
	listed.prepare(1, units)
	SpatialHash.rebuild(get_tree(), 7)
	assert_true(SpatialHash.is_current(7))
	var hashed := ManPerception.new()
	hashed.prepare(7, units)
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
	var mp := ManPerception.new()
	mp.prepare(3, [man, wide])
	var r: Dictionary = mp.perceive(man, 0)
	assert_eq(r["perceived"], 1)
	assert_eq(r["nearest_index"], 0)
