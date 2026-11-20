extends GutTest
## SoldierFlightWay.choose: the way a routed man chooses never comes to nothing, and with the
## enemy between him and his refuge he runs away from them and round them.

const AT := Vector2(500, 500)


## A one-man unit at `at`, or, with `mate_at`, a second man of it standing there.
func _man(at: Vector2 = AT, mate_at: Variant = null) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 1 if mate_at == null else 2
	u.team = 0   # his refuge lies north (UP)
	add_child_autofree(u)
	u.position = AT
	u.seed_sim_soldiers()
	u._sim_soldier_pos[0] = at
	if mate_at != null:
		u._sim_soldier_pos[1] = mate_at
	return u


func test_no_foe_sends_him_to_his_refuge() -> void:
	assert_eq(SoldierFlightWay.choose(_man(), 0, Vector2.ZERO), Vector2.UP,
			"nothing seen: his refuge")


func test_foes_behind_add_to_his_refuge_pull() -> void:
	var d: Vector2 = SoldierFlightWay.choose(_man(), 0, Vector2(0, 3))   # foes south of him
	assert_almost_eq(d.y, -1.0, 0.0001, "he runs north, away from them and for his refuge")


func test_balanced_pulls_never_stall_him() -> void:
	# Foes straight between him and his refuge, weighing exactly what his refuge pulls: summed,
	# the two would leave him standing.
	var u := _man(AT + Vector2(10, 0), AT)   # a mate at his elbow, west of him
	var d: Vector2 = SoldierFlightWay.choose(u, 0, Vector2(0, -u.rout_refuge_weight))
	assert_almost_eq(d.length(), 1.0, 0.0001, "he always has a way")
	assert_gt(d.y, 0.0, "away from the foes")
	assert_gt(d.x, 0.0, "and round them away from the mate beside him, east")
	var w := _man(AT + Vector2(-10, 0), AT)
	assert_lt(SoldierFlightWay.choose(w, 0, Vector2(0, -1)).x, 0.0,
			"a man with his mate east goes west")
	var far := _man(AT + Vector2(-10, 0), AT + Vector2(-10 + w.sight_range + 10.0, 0))
	far._sim_body_vel[0] = Vector2(-5, 0)   # running west, his mate out of sight beside him
	assert_lt(SoldierFlightWay.choose(far, 0, Vector2(0, -1)).x, 0.0,
		"with no mate at his elbow he keeps the way he is moving")


func test_he_goes_round_on_his_refuge_s_side_where_fewer_foes_stand() -> void:
	# The foes he sees lean west of the line to his refuge, so fewer stand to the east.
	var u := _man(AT + Vector2(-10, 0))
	var d: Vector2 = SoldierFlightWay.choose(u, 0, Vector2(-1, -2))
	assert_gt(d.x, 0.0, "he goes round the east side")
	assert_gt(d.dot(Vector2(1, 2).normalized()), 0.0, "still away from the foes")


func test_rock_on_one_side_sends_him_round_the_other() -> void:
	var u := _man(AT + Vector2(10, 0))   # would go east
	var reach: float = u.soldier_reach()
	var rock: Array[Rect2] = [Rect2(AT + Vector2(10 + reach * 0.5, -20), Vector2(40, 40))]
	var d: Vector2 = SoldierFlightWay.choose(u, 0, Vector2(0, -1), rock)
	assert_lt(d.x, 0.0, "the east is shut by rock, so he goes west")


func test_a_man_who_barely_sees_the_foes_runs_along_them_not_back_out_of_sight() -> void:
	# Foes between him and his refuge, at the edge of his sight: their weight is slight.
	var u := _man(AT + Vector2(10, 0))
	var d: Vector2 = SoldierFlightWay.choose(u, 0, Vector2(0, -0.1))
	assert_gt(d.x, 0.95, "he runs round them, east")
	assert_gt(d.y, 0.0, "edging away from them only as much as he feels them")
	var close: Vector2 = SoldierFlightWay.choose(u, 0, Vector2(0, -3))
	assert_almost_eq(close, Vector2(1, 1).normalized(), Vector2(0.0001, 0.0001),
			"close to them he runs as much away as round")
