extends GutTest
## The routed and rallied unit's per-man rules and readouts, on bare units outside a battle:
## the escape once every man has left the field (Unit._fled_clear), the far tier's aggregate
## flight (Unit._far_flight), the stamina a routed man is billed at his own pace
## (Unit.man_stamina_flow_per_s), the pull-up of a rallied unit's men still running
## (SoldierBodies.pull_up_rallied), the state dump's readout of it (Unit.shedding_flight), and the
## rally's deal from where the men stand in each layout (Unit.deal_slots_where_men_stand).

const TICK := 1.0 / 60.0


func _unit(count: int = 24) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = Vector2(500, 500)
	u.facing = Vector2.UP
	u.frontage_override = 6
	u.seed_sim_soldiers()
	return u


func test_a_router_has_fled_clear_only_once_every_man_has_left_the_field() -> void:
	var u := _unit(4)
	u.retreat_bounds = Rect2(0, 0, 1000, 1000)
	assert_false(u._fled_clear(), "men on the field")
	for i in range(4):
		u._sim_soldier_pos[i] = Vector2(500, -10.0 - i)
	assert_true(u._fled_clear(), "every man past the edge")
	u._sim_soldier_pos[2] = Vector2(500, 5)
	assert_false(u._fled_clear(), "one man still on the field keeps the unit in play")
	u._sim_soldier_pos = PackedVector2Array()
	u.position = Vector2(500, -20)
	assert_true(u._fled_clear(), "a unit with no men reads its position")


func test_a_far_tier_router_runs_toward_its_refuge_and_escapes_past_the_edge() -> void:
	var u := _unit(4)
	u.tier = FormationTier.FAR
	u.retreat_bounds = Rect2(0, 0, 1000, 1000)
	u._far_flee_pace = u.flee_speed()
	assert_true(u._far_flight(TICK), "a step inside the field")
	assert_almost_eq(u.position.y, 500.0 - u.flee_speed() * TICK, 0.0001, "north at flee pace")
	u.position = Vector2(500, 0.5)
	u._rout()
	u._far_flee_pace = u.flee_speed()
	assert_false(u._far_flight(TICK), "a step past the edge escapes")
	assert_eq(u.state, Unit.State.DEAD, "and the unit leaves play")


func test_a_routed_man_is_billed_stamina_at_his_own_pace() -> void:
	var u := _unit(2)
	u._sim_body_vel[0] = Vector2.ZERO
	u._sim_body_vel[1] = Vector2(0, -u.move_speed)
	assert_eq(u.man_stamina_flow_per_s(0), StaminaFlow.flow_per_s(StaminaFlow.BAND_REST,
			u.stamina_rest_regen_per_s, u.stamina_walk_regen_per_s, u.stamina_jog_drain_per_s,
			u.stamina_sprint_drain_per_s), "a man standing still rests")
	assert_eq(u.man_stamina_flow_per_s(1), StaminaFlow.flow_per_s(Unit.GAIT_SPRINT,
			u.stamina_rest_regen_per_s, u.stamina_walk_regen_per_s, u.stamina_jog_drain_per_s,
			u.stamina_sprint_drain_per_s), "a man at a sprint pays a sprint")
	assert_eq(u.man_stamina_flow_per_s(7), u.man_stamina_flow_per_s(0), "no body reads as resting")


func test_a_rallied_unit_s_men_pull_up_on_their_own_then_it_re_forms() -> void:
	var u := _unit(2)
	u._rout()
	u._formation_angle = 0.5
	u._rally()
	assert_true(u._rally_pending, "a rally waits for its men to pull up")
	assert_true(u.shedding_flight(), "and the dump reads them as shedding their flight")
	u._sim_body_vel[0] = Vector2(0, -u.jog_speed * 2.0)   # still running north
	u._sim_body_vel[1] = Vector2(u.jog_speed * 0.5, 0)    # already down to a walk
	var before: Vector2 = u._sim_soldier_pos[0]
	assert_true(SoldierBodies.pull_up_rallied(u, 2, 60.0, TICK), "a man still faster than a jog")
	assert_almost_eq(u._sim_body_vel[0].length(), u.jog_speed * 2.0 - 1.0, 0.0001,
			"slows by one tick of the rate along his run")
	assert_almost_eq(before.distance_to(u._sim_soldier_pos[0]), u._sim_body_vel[0].length() * TICK,
			0.0001, "and runs on at what he kept")
	assert_almost_eq(u.soldier_facing(0).y, -1.0, 0.0001, "facing his run")
	assert_almost_eq(u._sim_body_vel[1].length(), u.jog_speed * 0.5 - 1.0, 0.0001,
			"the walking man slows too")
	u._sim_body_vel[0] = Vector2(0, -u.jog_speed)
	assert_false(SoldierBodies.pull_up_rallied(u, 2, 60.0, TICK), "none above a jog: they have pulled up")
	u.step_sim_soldiers(TICK)
	assert_false(u._rally_pending, "so the step lays the grid out where they stand")
	assert_eq(u._formation_angle, 0.0, "square to their heading")
	assert_eq(u._last_redeal_tick, Engine.get_physics_frames(), "stamped as a re-deal for the dump")
	assert_false(u.shedding_flight(), "and nothing is shed any more")


func test_shedding_flight_is_a_rallying_unit_only() -> void:
	var u := _unit(2)
	assert_false(u.shedding_flight(), "a unit that never routed is not shedding a flight")
	u._rout()
	assert_false(u.shedding_flight(), "nor a router")
	u._rally()
	assert_true(u.shedding_flight(), "a rallied unit whose men are pulling up is")


func test_a_rallying_unit_stays_in_the_close_tier_until_its_men_have_pulled_up() -> void:
	var u := _unit(2)
	u._rout()
	u._rally()
	assert_false(TierTransition.can_demote(u), "its men are still running on their own")
	u._reform_where_men_stand()
	assert_true(TierTransition.can_demote(u), "once re-formed it may demote like any idle unit")


func test_an_order_re_forms_a_rallying_unit_at_once() -> void:
	var u := _unit(2)
	u._rout()
	u._rally()
	u.set_current_order(null)
	assert_false(u._rally_pending, "the order lays the grid out where the men stand")


func test_a_rally_marks_a_square_and_a_file_major_block_to_deal_from_the_bodies() -> void:
	var sq := _unit(36)
	sq.set_formation(Unit.FORMATION_SQUARE)
	sq.formation_slots(sq.soldiers, false)
	assert_ne(sq._square_slot_files, -1, "setup: the square holds a pairing")
	sq.deal_slots_where_men_stand()
	assert_eq(sq._square_slot_files, -1, "the square's next query deals from the bodies")
	var fm := _unit(36)
	fm.file_major_reform_mode = Unit.ReformMode.FILE_MAJOR
	fm.formation_slots(fm.soldiers, false)
	assert_ne(fm._file_assignment_files, -1, "setup: the file-major block holds an assignment")
	fm.deal_slots_where_men_stand()
	assert_eq(fm._file_assignment_files, -1, "its next query deals from the bodies")
	var bare: Unit = Unit.new()
	bare.max_soldiers = 6
	add_child_autofree(bare)
	var held: PackedInt32Array = bare._sim_soldier_row_slot.duplicate()
	bare.deal_slots_where_men_stand()
	assert_eq(bare._sim_soldier_row_slot, held, "a unit with no bodies keeps its layout")
