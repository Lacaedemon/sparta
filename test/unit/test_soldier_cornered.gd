extends GutTest
## SoldierCornered: a routed man with no way to run turns and fights, and runs again once a
## way opens. Bare units outside a battle, with bodies placed by hand.

const TICK := 1.0 / 60.0
const AT := Vector2(500, 500)


func after_each() -> void:
	SoldierFlight.perceive_threats = true


func _unit(team: int, count: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	u.team = team
	add_child_autofree(u)
	u.position = AT
	u.facing = Vector2.UP
	u.seed_sim_soldiers()
	return u


## A lone router at AT, and an enemy of `offsets.size()` men standing at AT + each offset.
func _router_and_foes(offsets: Array[Vector2]) -> Array:
	var r := _unit(0, 1)
	r._sim_soldier_pos[0] = AT
	var f := _unit(1, offsets.size())
	for k in range(offsets.size()):
		f._sim_soldier_pos[k] = AT + offsets[k]
	f.position = AT
	return [r, f]


func _seen(r: Unit, f: Unit, k: int) -> Dictionary:
	return {"threat": Vector2.ZERO, "nearest_unit": f, "nearest_index": k,
			"nearest_distance": AT.distance_to(f._sim_soldier_pos[k])}


func test_a_man_with_foes_ahead_and_to_each_side_within_reach_is_cornered() -> void:
	var d: float = 20.0
	var pair: Array = _router_and_foes([Vector2(0, -d), Vector2(-d, 0), Vector2(d, 0)])
	var r: Unit = pair[0]
	var f: Unit = pair[1]
	assert_lt(d, r.soldier_reach(), "setup: every foe is within his reach")
	var none: Array[Rect2] = []
	assert_true(SoldierCornered.is_cornered(r, 0, Vector2.UP, _seen(r, f, 0), none),
			"ahead, left and right are shut")
	f._sim_soldier_pos[2] = AT + Vector2(r.soldier_reach() * 3.0, 0)   # the right opens
	assert_false(SoldierCornered.is_cornered(r, 0, Vector2.UP, _seen(r, f, 0), none),
			"a way to one side is a way to run")


func test_ground_shuts_a_way_as_a_foe_does() -> void:
	var pair: Array = _router_and_foes([Vector2(-20, 0)])
	var r: Unit = pair[0]
	var f: Unit = pair[1]
	var reach: float = r.soldier_reach()
	var walls: Array[Rect2] = [Rect2(AT + Vector2(-50, -reach - 5), Vector2(100, 10)),
			Rect2(AT + Vector2(reach - 5, -50), Vector2(10, 100))]
	var seen: Dictionary = _seen(r, f, 0)
	seen["nearest_distance"] = INF   # ground ahead alone opens the check
	assert_true(SoldierCornered.is_cornered(r, 0, Vector2.UP, seen, walls),
			"rock ahead and to his right, a foe to his left")
	var ahead_only: Array[Rect2] = [walls[0]]
	assert_false(SoldierCornered.is_cornered(r, 0, Vector2.UP, seen, ahead_only),
			"with the right open he can still run")


func test_a_man_with_nothing_within_reach_is_not_cornered() -> void:
	var pair: Array = _router_and_foes([Vector2(0, -200)])
	var none: Array[Rect2] = []
	assert_false(SoldierCornered.is_cornered(pair[0], 0, Vector2.UP, _seen(pair[0], pair[1], 0), none),
			"a foe beyond his reach does not corner him")


func test_cornered_men_strike_the_foes_within_reach() -> void:
	var pair: Array = _router_and_foes([Vector2(0, -20), Vector2(-20, 0), Vector2(20, 0)])
	var r: Unit = pair[0]
	var f: Unit = pair[1]
	r._rout()
	r._sim_flight_dir = PackedVector2Array([Vector2.UP])
	assert_false(SoldierCornered.fight(r), "a man still running does not fight")
	r._sim_flight_dir[0] = Vector2.ZERO
	var before: float = 0.0
	for hp in f._sim_soldier_hp:
		before += hp
	var struck: bool = false
	for _k in range(40):
		struck = SoldierCornered.fight(r) or struck
	var after: float = 0.0
	for hp in f._sim_soldier_hp:
		after += hp
	assert_true(struck, "a cornered man stands and fights")
	assert_lt(after, before, "and his blows land on the foes around him")


func test_a_cornered_man_stands_faces_his_foe_and_runs_again_once_a_way_opens() -> void:
	var pair: Array = _router_and_foes([Vector2(0, -20), Vector2(-20, 0), Vector2(20, 0)])
	var r: Unit = pair[0]
	var f: Unit = pair[1]
	r._rout()
	var frame: int = Engine.get_physics_frames()
	SoldierFlight.prepare(frame, [r, f], [], null)
	var period: int = r.rout_reaction_ticks()
	r._sim_flight_dir = PackedVector2Array([Vector2.UP])
	# Step until his own look-round tick comes up (the step reads the engine's frame counter).
	SoldierFlightStep._look_round(r, 0, frame, [] as Array[Rect2])
	assert_eq(r._sim_flight_dir[0], Vector2.ZERO, "hemmed in, he stands to fight")
	assert_gt(r.soldier_facing(0).dot((f._sim_soldier_pos[0] - AT).normalized()), 0.99,
			"facing the foe nearest him")
	SoldierFlightStep.step(r, 1, {}, TICK)
	assert_almost_eq(r._sim_body_vel[0].length(), 0.0, 0.001, "and does not run")
	f._sim_soldier_pos[1] = AT + Vector2(-400, 0)   # the left opens
	SoldierFlightStep._look_round(r, 0, frame, [] as Array[Rect2])
	assert_ne(r._sim_flight_dir[0], Vector2.ZERO, "when he next looks round he runs again")
	assert_gt(period, 0, "sanity: he looks round every %d ticks" % period)


func test_a_dead_man_s_chosen_way_goes_with_him() -> void:
	var r := _unit(0, 3)
	r._rout()
	r._sim_flight_dir = PackedVector2Array([Vector2.UP, Vector2.ZERO, Vector2.LEFT])
	r._sim_soldier_hp[1] = 0.0
	SoldierMelee.reap(r, null)
	assert_eq(r._sim_flight_dir, PackedVector2Array([Vector2.UP, Vector2.LEFT]),
			"each survivor keeps his own way")


func test_a_newly_broken_man_runs_for_his_refuge_until_he_looks_round() -> void:
	var r := _unit(0, 6)
	r._rout()
	SoldierFlight.perceive_threats = false
	SoldierFlightStep.step(r, 6, {}, TICK)
	for i in range(6):
		assert_eq(r._sim_flight_dir[i], Vector2.UP, "man %d heads for his rear edge" % i)
