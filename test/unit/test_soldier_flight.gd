extends GutTest
## SoldierFlight and SoldierFlightStep: where one routed man runs and how he moves, on bare units
## outside a battle. The live battle stagings are in test_close_tier_rout_speed.gd.

const TICK := 1.0 / 60.0


func after_each() -> void:
	SoldierFlight.perceive_threats = true


func _unit(team: int, at: Vector2, count: int = 24) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	u.team = team
	add_child_autofree(u)
	u.position = at
	u.facing = Vector2.UP if team == 0 else Vector2.DOWN
	u.frontage_override = 6
	u.seed_sim_soldiers()
	return u


func test_the_edge_refuge_is_each_side_s_own_rear_edge() -> void:
	var a := _unit(0, Vector2(500, 500))
	var b := _unit(1, Vector2(500, 900))
	assert_eq(SoldierFlight.refuge_direction(a, a.position), Vector2.UP, "team 0's camp lies north")
	assert_eq(SoldierFlight.refuge_direction(b, b.position), Vector2.DOWN, "team 1's camp lies south")


func test_the_lines_refuge_is_the_nearest_friendly_unit() -> void:
	var a := _unit(0, Vector2(500, 500))
	a.rout_refuge = SoldierFlight.Refuge.LINES
	assert_eq(SoldierFlight.refuge_direction(a, a.position), Vector2.UP,
			"with no friend in play it falls back on the rear edge")
	var near := _unit(0, Vector2(800, 500))
	_unit(0, Vector2(500, 1500))   # farther away
	_unit(1, Vector2(600, 500))    # nearer, but an enemy
	var d: Vector2 = SoldierFlight.refuge_direction(a, a.position)
	assert_almost_eq(d.x, 1.0, 0.0001, "he runs for the nearest friend, east")
	assert_almost_eq(d.y, 0.0, 0.0001, "and only east")
	near.state = Unit.State.DEAD
	assert_almost_eq(SoldierFlight.refuge_direction(a, a.position).y, 1.0, 0.0001,
			"a dead friend is no refuge; the next nearest lies south")


func test_with_perception_off_a_man_runs_for_his_refuge() -> void:
	var a := _unit(0, Vector2(500, 500))
	SoldierFlight.perceive_threats = false
	assert_eq(SoldierFlight.perceived(a, 0, Engine.get_physics_frames())["threat"], Vector2.ZERO, "no threat")
	assert_eq(SoldierFlightWay.choose(a, 0, Vector2.ZERO), Vector2.UP,
			"his own direction is his refuge")


func test_a_man_runs_away_from_a_crowd_of_foes_on_his_refuge_side() -> void:
	var a := _unit(0, Vector2(500, 500), 6)
	var foes := _unit(1, Vector2(500, 440), 60)
	var frame: int = Engine.get_physics_frames() + 1000
	SoldierFlight.prepare(frame, [a, foes], [], null)
	var t: Vector2 = SoldierFlight.perceived(a, 0, frame)["threat"]
	assert_lt(t.y, -1.0, "he perceives the crowd to his north, weighing more than his refuge")
	assert_gt(SoldierFlightWay.choose(a, 0, t).dot(-t.normalized()), 0.7,
			"so he runs away from it, round it toward his refuge, never into it")
	assert_eq(SoldierFlight.perceived(a, 0, frame + 1)["threat"], Vector2.ZERO,
			"a frame nothing prepared perceives nothing")


func test_a_man_who_perceives_nothing_he_can_flee_from_runs_for_his_refuge() -> void:
	var a := _unit(0, Vector2(500, 500))
	a.rout_refuge_weight = 0.0
	SoldierFlight.perceive_threats = false
	assert_eq(SoldierFlightWay.choose(a, 0, Vector2.ZERO), Vector2.UP,
			"a zero pull and no threat still leave him his refuge's direction")


## Man 1 of a two-man unit runs north; man 0 stands `ahead` wu north of him running east.
func _pair_with_mate(ahead: float, follow: int) -> Unit:
	var u := _unit(0, Vector2(500, 500), 2)
	u.rout_follow = follow
	u._sim_soldier_pos[1] = Vector2(500, 500)
	u._sim_soldier_pos[0] = Vector2(500, 500 - ahead)
	u._sim_body_vel[0] = Vector2(80, 0)
	return u


func test_a_man_takes_part_of_his_line_from_a_mate_ahead() -> void:
	var u := _pair_with_mate(100.0, SoldierFlight.Follow.HERD)
	var pitch: float = 50.0
	var d: Vector2 = SoldierFlight.with_mate(u, 1, Vector2.UP, 0, pitch)
	var want: Vector2 = (Vector2.UP * (1.0 - u.rout_herding) + Vector2.RIGHT * u.rout_herding).normalized()
	assert_almost_eq(d.x, want.x, 0.0001, "a full pitch ahead, he mixes in rout_herding of the mate's run")
	assert_almost_eq(d.y, want.y, 0.0001, "both components")
	var half := _pair_with_mate(25.0, SoldierFlight.Follow.HERD)
	var dh: Vector2 = SoldierFlight.with_mate(half, 1, Vector2.UP, 0, pitch)
	assert_gt(dh.x, 0.0, "half a pitch ahead, still some")
	assert_lt(dh.x, d.x, "but less")
	var behind := _pair_with_mate(-30.0, SoldierFlight.Follow.HERD)
	assert_eq(SoldierFlight.with_mate(behind, 1, Vector2.UP, 0, pitch), Vector2.UP,
			"a mate behind him lends him no line")


func test_no_line_from_no_mate_a_still_mate_or_the_alone_reading() -> void:
	var u := _pair_with_mate(100.0, SoldierFlight.Follow.HERD)
	assert_eq(SoldierFlight.with_mate(u, 1, Vector2.UP, -1, 50.0), Vector2.UP, "no mate")
	assert_eq(SoldierFlight.with_mate(u, 1, Vector2.UP, 0, 0.0), Vector2.UP, "no pitch")
	var alone := _pair_with_mate(100.0, SoldierFlight.Follow.ALONE)
	assert_eq(SoldierFlight.with_mate(alone, 1, Vector2.UP, 0, 50.0), Vector2.UP, "ALONE")
	u._sim_body_vel[0] = Vector2.ZERO
	assert_eq(SoldierFlight.with_mate(u, 1, Vector2.UP, 0, 50.0), Vector2.UP, "a mate standing still")


func test_the_column_reading_heads_for_the_place_behind_the_mate() -> void:
	var u := _pair_with_mate(100.0, SoldierFlight.Follow.COLUMN)
	u._sim_body_vel[0] = Vector2(0, -80)   # the mate runs north
	u._sim_soldier_pos[0] = Vector2(560, 400)   # a pitch north and 60 wu east of him
	var d: Vector2 = SoldierFlight.with_mate(u, 1, Vector2.UP, 0, 50.0)
	var place := Vector2(560, 450)   # one pitch behind the mate along his run
	var to_place: Vector2 = (place - Vector2(500, 500)).normalized()
	var want: Vector2 = (Vector2.UP * (1.0 - u.rout_herding) + to_place * u.rout_herding).normalized()
	assert_almost_eq(d.x, want.x, 0.0001, "he turns toward his place in the mate's file")
	assert_almost_eq(d.y, want.y, 0.0001, "both components")


func test_a_routed_man_builds_his_run_at_his_own_acceleration_and_faces_it() -> void:
	var u := _unit(0, Vector2(500, 500), 12)
	u._rout()
	SoldierFlight.perceive_threats = false
	var accel: float = maxf(u.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	SoldierFlightStep.step(u, u._sim_soldier_pos.size(), {}, TICK)
	for i in range(u._sim_soldier_pos.size()):
		assert_almost_eq(u._sim_body_vel[i].length(), accel * TICK, 0.001,
				"man %d took one tick of his own acceleration" % i)
		assert_almost_eq(u.soldier_facing(i).y, -1.0, 0.0001, "and faces his run, north")
	for _t in range(2000):
		SoldierFlightStep.step(u, u._sim_soldier_pos.size(), {}, TICK)
	assert_almost_eq(u._sim_body_vel[0].length(), u.flee_speed(), 0.01, "he tops out at his flee pace")


func test_a_man_takes_his_line_from_whichever_file_mate_is_ahead() -> void:
	var u := _unit(0, Vector2(500, 500), 12)
	var mates: Array[PackedInt32Array] = SoldierFileNeighbours.compute(u, 12, 6)
	assert_eq(mates[0][6], 0, "man 6's file-mate in front is man 0")
	assert_eq(mates[1][0], 6, "and man 0's behind him is man 6")
	u._sim_soldier_pos[6] = u._sim_soldier_pos[0] + Vector2(0, -40)   # man 6 runs out in front
	assert_eq(SoldierFlightStep._mate_ahead(u, 0, Vector2.UP, mates), 6, "man 0 now follows man 6")
	assert_eq(SoldierFlightStep._mate_ahead(u, 6, Vector2.UP, mates), -1, "and man 6 follows nobody")


func test_a_routed_man_looks_round_once_a_reaction_time_on_a_tick_of_his_own() -> void:
	var u := _unit(0, Vector2(500, 500), 12)
	u._rout()
	SoldierFlight.perceive_threats = false
	var period: int = u.rout_reaction_ticks()
	assert_eq(period, roundi(Unit.ROUT_REACTION_TIME * Engine.physics_ticks_per_second),
			"his reaction time at the physics rate")
	u._sim_flight_dir.resize(12)
	u._sim_flight_dir.fill(Vector2.RIGHT)   # each man still runs the way he last chose
	SoldierFlightStep.step(u, 12, {}, TICK)
	var frame: int = Engine.get_physics_frames()
	var looked: int = 0
	for i in range(12):
		if (frame + i) % period == 0:
			looked += 1
			assert_eq(u._sim_flight_dir[i], Vector2.UP, "man %d looked round: his refuge" % i)
		else:
			assert_eq(u._sim_flight_dir[i], Vector2.RIGHT, "man %d keeps his last choice" % i)
	assert_eq(looked, ceili(12.0 / period) if 12 % period != 0 else 12 / period,
			"the men look round on ticks of their own, spread across the period")
