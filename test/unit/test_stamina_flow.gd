extends GutTest
## Per-gait stamina flow (docs/combat-model.md "Posture", stamina column): the pool
## regenerates at rest, holds at a walk, drains slowly at a jog and fast at a sprint,
## read off the regiment's live pace. Pins StaminaFlow's band and rate math, the Unit
## fields that configure it, the per-body application in SoldierBodies.step, the far
## tier's aggregate pool on both the live unit and the isolated FarTierFormation record,
## and the loadout override path through Battle._spawn_unit.

const TICK := 1.0 / 60.0
const TOL := 1e-4


func _make_unit(uid: int = 1, max_soldiers: int = 12) -> Unit:
	var u: Unit = Unit.new()
	u.uid = uid
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() seeds soldiers = max_soldiers
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


## A seeded close-tier unit cruising at `speed` with its pool at `stamina`.
func _cruising_unit(uid: int, speed: float, stamina: float = -1.0) -> Unit:
	var u := _make_unit(uid)
	u.seed_sim_soldiers()
	u._current_speed = speed
	if stamina >= 0.0:
		u._sim_soldier_stamina.fill(stamina)
	return u


func _step_seconds(u: Unit, seconds: float) -> void:
	for _i in range(roundi(seconds / TICK)):
		SoldierBodies.step(u, TICK)


# --- StaminaFlow: bands ------------------------------------------------------------------


func test_band_rest_at_or_below_the_rest_epsilon() -> void:
	assert_eq(StaminaFlow.band_for_speed(0.0, 45.0, 67.5, 90.0, 1.0), StaminaFlow.BAND_REST)
	assert_eq(StaminaFlow.band_for_speed(1.0, 45.0, 67.5, 90.0, 1.0), StaminaFlow.BAND_REST)


func test_band_walk_from_the_epsilon_up_to_halfway_to_the_jog() -> void:
	assert_eq(StaminaFlow.band_for_speed(1.01, 45.0, 67.5, 90.0, 1.0), Unit.GAIT_WALK)
	assert_eq(StaminaFlow.band_for_speed(45.0, 45.0, 67.5, 90.0, 1.0), Unit.GAIT_WALK)
	assert_eq(StaminaFlow.band_for_speed(56.25, 45.0, 67.5, 90.0, 1.0), Unit.GAIT_WALK,
			"the walk/jog boundary (the midpoint) still reads as a walk")


func test_band_jog_is_symmetric_about_the_jog_pace() -> void:
	# Walk 45, jog 67.5, sprint 90: the jog band is (56.25, 78.75], one half-step either side.
	assert_eq(StaminaFlow.band_for_speed(56.26, 45.0, 67.5, 90.0, 1.0), Unit.GAIT_JOG)
	assert_eq(StaminaFlow.band_for_speed(67.5, 45.0, 67.5, 90.0, 1.0), Unit.GAIT_JOG)
	assert_eq(StaminaFlow.band_for_speed(78.75, 45.0, 67.5, 90.0, 1.0), Unit.GAIT_JOG)


func test_band_sprint_above_the_jog_band() -> void:
	assert_eq(StaminaFlow.band_for_speed(78.76, 45.0, 67.5, 90.0, 1.0), Unit.GAIT_SPRINT)
	assert_eq(StaminaFlow.band_for_speed(90.0, 45.0, 67.5, 90.0, 1.0), Unit.GAIT_SPRINT)


func test_band_cavalry_paces_use_jog_to_sprint_midpoint() -> void:
	# Cavalry loadout: walk 1.7, jog 3.5, sprint 8.5 m/s. The midpoint between jog and sprint
	# is (3.5 + 8.5) * 0.5 = 6.0 m/s. An extrapolated boundary from the walk/jog step would sit
	# at 3.5 + (3.5 - 1.7) * 0.5 = 4.4 m/s and misclassify 5.0 m/s as sprint.
	var walk: float = 1.7
	var jog: float = 3.5
	var sprint: float = 8.5
	var eps: float = 0.05
	assert_eq(StaminaFlow.band_for_speed(2.6, walk, jog, sprint, eps), Unit.GAIT_WALK,
			"walk/jog midpoint is (1.7 + 3.5) / 2 = 2.6")
	assert_eq(StaminaFlow.band_for_speed(2.61, walk, jog, sprint, eps), Unit.GAIT_JOG)
	assert_eq(StaminaFlow.band_for_speed(5.0, walk, jog, sprint, eps), Unit.GAIT_JOG,
			"5.0 m/s is below the 6.0 midpoint to actual sprint pace")
	assert_eq(StaminaFlow.band_for_speed(6.0, walk, jog, sprint, eps), Unit.GAIT_JOG,
			"the midpoint itself reads as a jog")
	assert_eq(StaminaFlow.band_for_speed(6.01, walk, jog, sprint, eps), Unit.GAIT_SPRINT,
			"above 6.0 m/s flips to sprint")


func test_band_a_sprint_no_faster_than_the_jog_bills_jog_then_sprint() -> void:
	# Degenerate pace order: sprint <= jog (push_error). Up to jog pace bills jog, above bills sprint.
	for sprint in [67.5, 60.0]:
		assert_eq(StaminaFlow.band_for_speed(67.5, 45.0, 67.5, sprint, 1.0), Unit.GAIT_JOG,
				"at or below jog pace bills jog, sprint_speed %s" % sprint)
		assert_push_error("is not above jog_speed")
		assert_eq(StaminaFlow.band_for_speed(67.51, 45.0, 67.5, sprint, 1.0), Unit.GAIT_SPRINT,
				"above jog pace bills sprint, sprint_speed %s" % sprint)
		assert_push_error("is not above jog_speed")


func test_band_a_jog_no_faster_than_the_walk_bills_walk_then_jog_and_never_sprint() -> void:
	# A degenerate pace order (loud via push_error) collapses the jog band, so the halfway
	# boundaries would otherwise bill every jog as a walk or a sprint. The explicit
	# fallback bills up to the walk pace as a walk and anything faster as a jog; the
	# sprint band has no jog pace to sit above. Both the equal and the inverted case.
	for jog in [45.0, 40.0]:
		assert_eq(StaminaFlow.band_for_speed(0.5, 45.0, jog, 90.0, 1.0), StaminaFlow.BAND_REST,
			"rest is unaffected, jog_speed %s" % jog)
		assert_eq(StaminaFlow.band_for_speed(45.0, 45.0, jog, 90.0, 1.0), Unit.GAIT_WALK,
			"at the walk pace, jog_speed %s" % jog)
		assert_push_error("is not above walk_speed")
		assert_eq(StaminaFlow.band_for_speed(45.01, 45.0, jog, 90.0, 1.0), Unit.GAIT_JOG,
			"just above the walk pace, jog_speed %s" % jog)
		assert_push_error("is not above walk_speed")
		assert_eq(StaminaFlow.band_for_speed(200.0, 45.0, jog, 90.0, 1.0), Unit.GAIT_JOG,
			"no sprint band without a jog pace to set it against, jog_speed %s" % jog)
		assert_push_error("is not above walk_speed")


# --- StaminaFlow: rates ------------------------------------------------------------------


func test_flow_signs_follow_the_posture_table() -> void:
	assert_almost_eq(StaminaFlow.flow_per_s(StaminaFlow.BAND_REST, 6.0, 0.0, 1.0, 5.0), 6.0, TOL)
	assert_almost_eq(StaminaFlow.flow_per_s(Unit.GAIT_WALK, 6.0, 0.0, 1.0, 5.0), 0.0, TOL)
	assert_almost_eq(StaminaFlow.flow_per_s(Unit.GAIT_JOG, 6.0, 0.0, 1.0, 5.0), -1.0, TOL)
	assert_almost_eq(StaminaFlow.flow_per_s(Unit.GAIT_SPRINT, 6.0, 0.0, 1.0, 5.0), -5.0, TOL)


func test_flow_reads_the_callers_own_rates_not_the_defaults() -> void:
	assert_almost_eq(StaminaFlow.flow_per_s(Unit.GAIT_JOG, 6.0, 2.0, 3.5, 5.0), -3.5, TOL)
	assert_almost_eq(StaminaFlow.flow_per_s(Unit.GAIT_WALK, 6.0, 2.0, 3.5, 5.0), 2.0, TOL)


func test_flow_unknown_band_reports_error_and_returns_zero() -> void:
	assert_almost_eq(StaminaFlow.flow_per_s(99, 6.0, 0.0, 1.0, 5.0), 0.0, TOL)
	assert_push_error("unknown band 99")


func test_apply_clamps_the_pool_to_its_range() -> void:
	assert_almost_eq(StaminaFlow.apply(99.0, 6.0, 1.0, 100.0), 100.0, TOL, "capped at max")
	assert_almost_eq(StaminaFlow.apply(2.0, -5.0, 1.0, 100.0), 0.0, TOL, "floored at zero")
	assert_almost_eq(StaminaFlow.apply(50.0, -5.0, 0.5, 100.0), 47.5, TOL, "scaled by delta")


# --- Unit: the pace-derived band and its configurable rates ------------------------------


func test_unit_defaults_are_the_combat_models_posture_rates() -> void:
	var u := _make_unit()
	assert_almost_eq(u.stamina_rest_regen_per_s, SoldierCombat.RHO_STAMINA, TOL)
	assert_almost_eq(u.stamina_walk_regen_per_s, SoldierCombat.RHO_STAMINA_WALK, TOL)
	assert_almost_eq(u.stamina_jog_drain_per_s, SoldierCombat.KAPPA_JOG, TOL)
	assert_almost_eq(u.stamina_sprint_drain_per_s, SoldierCombat.KAPPA_SPRINT, TOL)


func test_unit_band_reads_its_own_live_pace() -> void:
	var u := _make_unit()
	assert_eq(u.stamina_band(), StaminaFlow.BAND_REST, "a fresh unit is stationary")
	u._current_speed = u.walk_speed
	assert_eq(u.stamina_band(), Unit.GAIT_WALK)
	u._current_speed = u.jog_speed
	assert_eq(u.stamina_band(), Unit.GAIT_JOG)
	u._current_speed = u.move_speed
	assert_eq(u.stamina_band(), Unit.GAIT_SPRINT)
	u.state = Unit.State.FIGHTING
	assert_eq(u.stamina_band(), StaminaFlow.BAND_REST, "a fighting unit stands and rests")


func test_unit_flow_uses_the_instance_rates_so_a_caller_can_retune_one() -> void:
	var u := _make_unit()
	u._current_speed = u.jog_speed
	assert_almost_eq(u.stamina_flow_per_s(), -SoldierCombat.KAPPA_JOG, TOL)
	u.stamina_jog_drain_per_s = 2.5
	assert_almost_eq(u.stamina_flow_per_s(), -2.5, TOL)


# --- SoldierBodies.step: the flow applied per body ---------------------------------------


func test_rest_regenerates_at_the_rest_rate() -> void:
	var u := _cruising_unit(1, 0.0, 50.0)
	SoldierBodies.step(u, 1.0)
	assert_almost_eq(u._sim_soldier_stamina[0], 50.0 + SoldierCombat.RHO_STAMINA, 1e-3)


func test_walk_is_neutral() -> void:
	var u := _cruising_unit(1, 0.0, 50.0)
	u._current_speed = u.walk_speed
	_step_seconds(u, 2.0)
	assert_almost_eq(u._sim_soldier_stamina[0], 50.0, 1e-3, "a walk neither drains nor restores")


func test_a_sprint_drains_faster_than_a_jog_which_drains_at_all() -> void:
	# The regression the feature exists for: movement used to be free at every pace.
	var jogger := _cruising_unit(1, 0.0)
	jogger._current_speed = jogger.jog_speed
	var sprinter := _cruising_unit(2, 0.0)
	sprinter._current_speed = sprinter.move_speed
	var full: float = jogger.combat_profile()["max_stamina"]
	_step_seconds(jogger, 2.0)
	_step_seconds(sprinter, 2.0)
	assert_lt(jogger._sim_soldier_stamina[0], full, "a jog drains stamina")
	assert_lt(sprinter._sim_soldier_stamina[0], jogger._sim_soldier_stamina[0],
			"a sprint drains faster than a jog over the same time")
	assert_almost_eq(jogger._sim_soldier_stamina[0], full - 2.0 * SoldierCombat.KAPPA_JOG, 1e-2)
	assert_almost_eq(sprinter._sim_soldier_stamina[0], full - 2.0 * SoldierCombat.KAPPA_SPRINT, 1e-2)


func test_every_body_of_a_sprinting_unit_pays_the_same_flow() -> void:
	var u := _cruising_unit(1, 0.0)
	u._current_speed = u.move_speed
	SoldierBodies.step(u, 1.0)
	var full: float = u.combat_profile()["max_stamina"]
	for i in range(u._sim_soldier_stamina.size()):
		assert_almost_eq(u._sim_soldier_stamina[i], full - SoldierCombat.KAPPA_SPRINT, 1e-3)


func test_a_sprint_cannot_drain_below_zero() -> void:
	var u := _cruising_unit(1, 0.0, 1.0)
	u._current_speed = u.move_speed
	SoldierBodies.step(u, 1.0)
	assert_almost_eq(u._sim_soldier_stamina[0], 0.0, TOL)


# --- Battle._spawn_unit: loadout override ------------------------------------------------


func test_spawn_reads_optional_per_gait_rates_from_the_loadout() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame
	var d: Dictionary = battle._default_loadout()[1].duplicate()
	d["stamina_sprint_drain_per_s"] = 9.0
	d["stamina_rest_regen_per_s"] = 8.0
	var u: Unit = battle._spawn_unit(d, 0, Vector2.DOWN, Vector2(400, 400), "Retuned")
	assert_almost_eq(u.stamina_sprint_drain_per_s, 9.0, TOL)
	assert_almost_eq(u.stamina_rest_regen_per_s, 8.0, TOL)
	assert_almost_eq(u.stamina_jog_drain_per_s, SoldierCombat.KAPPA_JOG, TOL,
			"a key the entry omits keeps the Unit default")


# --- Far tier: the live unit's aggregate pool --------------------------------------------


func test_mean_soldier_stamina_reads_the_pool_and_falls_back_to_full() -> void:
	var u := _make_unit()
	assert_almost_eq(u.mean_soldier_stamina(), u.combat_profile()["max_stamina"], TOL,
			"no bodies yet reads as a full pool")
	u.seed_sim_soldiers()
	u._sim_soldier_stamina.fill(40.0)
	u._sim_soldier_stamina[0] = 100.0
	var n: int = u._sim_soldier_stamina.size()
	assert_almost_eq(u.mean_soldier_stamina(), (40.0 * (n - 1) + 100.0) / n, 1e-3)


func test_mean_soldier_stamina_filters_by_hp_and_retains_zero_stamina() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	# 0: hp = 0.0 (fallen), stamina = 100.0 (dead body awaiting reap)
	# 1: hp = 50.0 (living), stamina = 0.0 (spent living soldier)
	# 2: hp = 50.0 (living), stamina = 60.0 (living soldier with stamina)
	u._sim_soldier_hp = PackedFloat32Array([0.0, 50.0, 50.0])
	u._sim_soldier_stamina = PackedFloat32Array([100.0, 0.0, 60.0])
	# Living pool is soldiers 1 and 2: mean = (0.0 + 60.0) / 2 = 30.0.
	# The pre-fix code averaged all entries including the fallen man.
	# A stamina-only filter would wrongly drop the zero-stamina living soldier.
	assert_almost_eq(u.mean_soldier_stamina(), 30.0, TOL,
			"mean stamina excludes wounded-dead awaiting reap and keeps zero-stamina living men")


func test_demote_collapses_the_pool_to_its_mean_and_promote_reseeds_from_it() -> void:
	var u := _make_unit(7)
	u.seed_sim_soldiers()
	u._sim_soldier_stamina.fill(30.0)
	TierTransition.demote(u)
	assert_almost_eq(u.far_stamina, 30.0, TOL, "demotion keeps the mean")
	assert_almost_eq(u.mean_soldier_stamina(), 30.0, TOL, "the aggregate answers while far")
	TierTransition.promote(u, 100, 12345)
	for i in range(u._sim_soldier_stamina.size()):
		assert_almost_eq(u._sim_soldier_stamina[i], 30.0, TOL, "every body reconstructs at the aggregate")
	assert_lt(u.far_stamina, 0.0, "the aggregate is consumed by the promotion")


func test_a_never_demoted_unit_promotes_rested() -> void:
	var u := _make_unit(7)
	u.tier = FormationTier.FAR
	TierTransition.promote(u, 100, 12345)
	var full: float = u.combat_profile()["max_stamina"]
	for i in range(u._sim_soldier_stamina.size()):
		assert_almost_eq(u._sim_soldier_stamina[i], full, TOL)


func test_far_tier_unit_pays_the_jog_flow_per_tick() -> void:
	var u := _make_unit(7)
	u.seed_sim_soldiers()
	TierTransition.demote(u)
	u._current_speed = u.jog_speed
	var full: float = u.combat_profile()["max_stamina"]
	u._tick_far_stamina(1.0)
	assert_almost_eq(u.far_stamina, full - SoldierCombat.KAPPA_JOG, 1e-3)
	u._current_speed = 0.0
	u._tick_far_stamina(1.0)
	assert_almost_eq(u.far_stamina, full, 1e-3, "rest restores it (capped at full)")


func test_far_stamina_tick_is_a_no_op_off_the_far_tier() -> void:
	var u := _make_unit(7)
	u.far_stamina = 50.0
	u._current_speed = u.move_speed
	u._tick_far_stamina(1.0)
	assert_almost_eq(u.far_stamina, 50.0, TOL, "a close-tier unit's bodies own the pool")


func test_unseeded_far_stamina_seeds_from_full_on_far_tier() -> void:
	var u := _make_unit(7)
	u.tier = FormationTier.FAR
	assert_lt(u.far_stamina, 0.0, "starts with unseeded sentinel")
	u._current_speed = u.jog_speed
	var full: float = u.combat_profile()["max_stamina"]
	u._tick_far_stamina(1.0)
	assert_almost_eq(u.far_stamina, full - SoldierCombat.KAPPA_JOG, 1e-3,
		"the unseeded sentinel seeds from the full pool and drains")


func test_far_stamina_round_trips_through_a_snapshot() -> void:
	var u := _make_unit(7)
	u.far_stamina = 42.0
	var d: Dictionary = u.to_snapshot_dict()
	assert_almost_eq(float(d["far_stamina"]), 42.0, TOL)
	d.erase("far_stamina")
	var restored := _make_unit(8)
	restored.apply_snapshot_dict(d)
	assert_almost_eq(restored.far_stamina, -1.0, TOL, "an older snapshot reads as never demoted")


func test_configurable_stamina_rates_round_trip_through_a_snapshot() -> void:
	var u := _make_unit(7)
	u.stamina_rest_regen_per_s = 4.2
	u.stamina_walk_regen_per_s = 1.5
	u.stamina_jog_drain_per_s = 3.3
	u.stamina_sprint_drain_per_s = 7.7
	var d: Dictionary = u.to_snapshot_dict()
	assert_almost_eq(float(d["stamina_rest_regen_per_s"]), 4.2, TOL)
	assert_almost_eq(float(d["stamina_walk_regen_per_s"]), 1.5, TOL)
	assert_almost_eq(float(d["stamina_jog_drain_per_s"]), 3.3, TOL)
	assert_almost_eq(float(d["stamina_sprint_drain_per_s"]), 7.7, TOL)
	d.erase("stamina_rest_regen_per_s")
	d.erase("stamina_walk_regen_per_s")
	d.erase("stamina_jog_drain_per_s")
	d.erase("stamina_sprint_drain_per_s")
	var restored := _make_unit(8)
	restored.apply_snapshot_dict(d)
	assert_almost_eq(restored.stamina_rest_regen_per_s, SoldierCombat.RHO_STAMINA, TOL)
	assert_almost_eq(restored.stamina_walk_regen_per_s, SoldierCombat.RHO_STAMINA_WALK, TOL)
	assert_almost_eq(restored.stamina_jog_drain_per_s, SoldierCombat.KAPPA_JOG, TOL)
	assert_almost_eq(restored.stamina_sprint_drain_per_s, SoldierCombat.KAPPA_SPRINT, TOL)


func test_far_tier_routing_updates_stamina_at_flee_pace() -> void:
	var u := _make_unit(7)
	u.tier = FormationTier.FAR
	u.far_stamina = 50.0
	u.morale = 0.0
	u._rout_timer = 5.0
	u.state = Unit.State.ROUTING
	u.move_speed = 100.0
	u._physics_process(1.0)
	assert_almost_eq(u.far_stamina, 50.0 - SoldierCombat.KAPPA_SPRINT, 1e-2,
			"routing drains at the sprint rate on the far tier")


func test_routing_unit_bills_flee_pace_on_the_tick_it_rallies() -> void:
	var u := _make_unit(7)
	u.tier = FormationTier.FAR
	u.far_stamina = 50.0
	u.morale = u.rally_morale_threshold
	u.state = Unit.State.ROUTING
	u.move_speed = 100.0
	u._rout_timer = 5.0
	u._physics_process(1.0)
	assert_eq(u.state, Unit.State.IDLE, "unit rallied on this tick")
	assert_almost_eq(u.far_stamina, 50.0 - SoldierCombat.KAPPA_SPRINT, 1e-2,
			"routing tick bills flee pace even when the unit rallies on the same tick")


func test_far_tier_coasting_tick_bills_post_decay_speed_matching_close_tier() -> void:
	var far_unit := _make_unit(10)
	far_unit.tier = FormationTier.FAR
	far_unit.far_stamina = 50.0
	var close_unit := _cruising_unit(11, 0.0, 50.0)
	var init_speed: float = 65.0
	far_unit._current_speed = init_speed
	far_unit._approach_velocity = Vector2.DOWN * init_speed
	close_unit._current_speed = init_speed
	close_unit._approach_velocity = Vector2.DOWN * init_speed
	far_unit._physics_process(0.5)
	close_unit._physics_process(0.5)
	SoldierBodies.step(close_unit, 0.5)
	assert_almost_eq(far_unit._current_speed, 50.0, TOL, "both units decayed to walk pace")
	assert_almost_eq(close_unit._current_speed, 50.0, TOL)
	assert_almost_eq(far_unit.far_stamina, close_unit.mean_soldier_stamina(), TOL,
			"far tier and close tier bill the post-decay speed on a coasting tick")


# --- Far tier: the isolated record and its rules -----------------------------------------


func _rec(gait: int = Unit.GAIT_WALK) -> FarTierFormation:
	var rec := FarTierFormation.new()
	rec.count = 120
	rec.max_soldiers = 120
	rec.attack = 12
	rec.defense = 6
	rec.gait = gait
	return rec


func test_record_from_unit_copies_the_gait_pace_pool_and_rates() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u._sim_soldier_stamina.fill(70.0)
	u.jog_speed = 60.0
	u.move_speed = 100.0
	u.stamina_jog_drain_per_s = 1.5
	u.stamina_sprint_drain_per_s = 7.5
	u.current_order = Order.new_move(Vector2(0, 500), 0, Unit.GAIT_JOG)
	var rec := FarTierFormation.from_unit(u)
	assert_eq(rec.gait, Unit.GAIT_JOG)
	assert_almost_eq(rec.jog_speed, 60.0, TOL)
	assert_almost_eq(rec.sprint_speed, 100.0, TOL)
	assert_almost_eq(rec.stamina, 70.0, TOL)
	assert_almost_eq(rec.max_stamina, u.combat_profile()["max_stamina"], TOL)
	assert_almost_eq(rec.stamina_jog_drain_per_s, 1.5, TOL)
	assert_almost_eq(rec.stamina_sprint_drain_per_s, 7.5, TOL)
	assert_almost_eq(rec.stamina_rest_regen_per_s, SoldierCombat.RHO_STAMINA, TOL)


func test_gait_for_ordered_collapses_to_walk_or_jog() -> void:
	assert_eq(FarTierFormation.gait_for_ordered(-1), Unit.GAIT_WALK, "AUTO marches at the walk")
	assert_eq(FarTierFormation.gait_for_ordered(Unit.GAIT_WALK), Unit.GAIT_WALK)
	assert_eq(FarTierFormation.gait_for_ordered(Unit.GAIT_JOG), Unit.GAIT_JOG)
	assert_eq(FarTierFormation.gait_for_ordered(Unit.GAIT_RUN), Unit.GAIT_JOG,
			"a run's sustained leg is a jog")
	assert_eq(FarTierFormation.gait_for_ordered(Unit.GAIT_SPRINT), Unit.GAIT_JOG,
			"the sprint burst is below the far tier's resolution")


func test_from_unit_auto_gait_derives_from_live_speed_band() -> void:
	var u := _make_unit()
	# With no explicit gait order, ordered_gait() reports AUTO (-1).
	assert_eq(u.ordered_gait(), -1)
	# At rest: collapses to GAIT_WALK.
	u._current_speed = 0.0
	assert_eq(FarTierFormation.from_unit(u).gait, Unit.GAIT_WALK)
	# At walk: collapses to GAIT_WALK.
	u._current_speed = u.walk_speed
	assert_eq(FarTierFormation.from_unit(u).gait, Unit.GAIT_WALK)
	# At jog (e.g. under missile fire or in pursuit): collapses to GAIT_JOG.
	u._current_speed = u.jog_speed
	assert_eq(FarTierFormation.from_unit(u).gait, Unit.GAIT_JOG,
			"auto unit moving at jog pace snapshots as GAIT_JOG")
	# At sprint: collapses down to GAIT_JOG.
	u._current_speed = u.move_speed
	assert_eq(FarTierFormation.from_unit(u).gait, Unit.GAIT_JOG,
			"auto unit moving at sprint pace collapses to GAIT_JOG")
	# Explicit walk order overrides live speed band.
	var order := Order.new()
	order.type = Order.Type.MOVE
	order.gait = Unit.GAIT_WALK
	u.current_order = order
	assert_eq(FarTierFormation.from_unit(u).gait, Unit.GAIT_WALK,
			"explicit order overrides live speed")


func test_jog_gait_paces_at_the_jog_and_walk_at_the_march() -> void:
	var rec := _rec(Unit.GAIT_JOG)
	assert_almost_eq(FarTierRules.pace_speed(rec), rec.jog_speed, TOL)
	assert_almost_eq(FarTierRules.effective_speed(rec), rec.jog_speed, TOL)
	rec.gait = Unit.GAIT_WALK
	assert_almost_eq(FarTierRules.effective_speed(rec), rec.march_speed, TOL)


func test_advance_at_a_jog_covers_more_ground_and_drains_the_pool() -> void:
	var walker := _rec(Unit.GAIT_WALK)
	var jogger := _rec(Unit.GAIT_JOG)
	FarTierRules.advance(walker, Vector2(1000.0, 0.0), 1.0)
	FarTierRules.advance(jogger, Vector2(1000.0, 0.0), 1.0)
	assert_gt(jogger.position.x, walker.position.x, "the jog arrives sooner")
	assert_almost_eq(walker.stamina, walker.max_stamina, TOL, "the walk is free")
	assert_almost_eq(jogger.stamina, jogger.max_stamina - SoldierCombat.KAPPA_JOG, TOL,
			"the jog pays its drain per second")


func test_jog_formation_capped_by_stance_bills_walk_band() -> void:
	# A jogged far-tier formation whose effective pace is capped below the walk/jog
	# midpoint by stance (Shield Wall) bills at the walk rate rather than the jog drain,
	# matching the close tier's live-speed classification.
	var rec := _rec(Unit.GAIT_JOG)
	rec.formation_mode = Unit.FORMATION_SHIELD_WALL
	rec.stamina = 50.0
	rec.stamina_walk_regen_per_s = 2.0
	rec.stamina_jog_drain_per_s = 5.0
	# Verify Shield Wall scales speed so effective_speed is well below the walk/jog midpoint.
	var midpoint: float = (rec.march_speed + rec.jog_speed) * 0.5
	assert_lt(FarTierRules.effective_speed(rec), midpoint)
	FarTierRules.advance(rec, Vector2(1000.0, 0.0), 1.0)
	assert_almost_eq(rec.stamina, 50.0 + 2.0, TOL,
			"capped below the midpoint, advance bills the walk band instead of the jog drain")


func test_advance_partial_tick_charges_moving_time_and_recovers_remainder() -> void:
	# 10 wu final leg at jog pace (67.5 wu/s) inside a 1 s tick covers the distance in ~0.15 s,
	# spending jog drain only for that moving fraction and recovering at rest for the remainder.
	var rec := _rec(Unit.GAIT_JOG)
	rec.stamina = 50.0
	rec.stamina_jog_drain_per_s = 6.0
	rec.stamina_rest_regen_per_s = 2.0
	var speed: float = FarTierRules.effective_speed(rec)
	var dist: float = 10.0
	var delta: float = 1.0
	var move_time: float = dist / speed
	var rest_time: float = delta - move_time
	var expected: float = 50.0 - 6.0 * move_time + 2.0 * rest_time
	FarTierRules.advance(rec, Vector2(10.0, 0.0), delta)
	assert_almost_eq(rec.position.x, 10.0, TOL, "formation arrives at target")
	assert_almost_eq(rec.stamina, expected, TOL,
			"partial tick charges moving fraction and recovers during stationary remainder")


func test_advance_zero_effective_speed_guards_division() -> void:
	var rec := _rec(Unit.GAIT_JOG)
	rec.stamina = 50.0
	rec.jog_speed = 0.0
	FarTierRules.advance(rec, Vector2(10.0, 0.0), 1.0)
	assert_almost_eq(rec.position.x, 0.0, TOL, "no movement when speed is zero")
	assert_gt(rec.stamina, 50.0, "rest recovery applies when stationary with zero speed")


func test_unit_flee_speed_shares_flee_multiplier() -> void:
	var u := _make_unit()
	u.move_speed = 100.0
	assert_almost_eq(u.flee_speed(), 100.0 * Unit.FLEE_SPEED_MULTIPLIER, TOL)
	assert_almost_eq(FarTierRules.FLEE_SPEED_MULTIPLIER, Unit.FLEE_SPEED_MULTIPLIER, TOL)


func test_tick_recovery_rests_the_pool_back_up() -> void:
	var rec := _rec()
	rec.stamina = 50.0
	FarTierRules.tick_recovery(rec, 1.0)
	assert_almost_eq(rec.stamina, 50.0 + SoldierCombat.RHO_STAMINA, TOL)
	rec.stamina = rec.max_stamina - 1.0
	FarTierRules.tick_recovery(rec, 1.0)
	assert_almost_eq(rec.stamina, rec.max_stamina, TOL, "capped at full")


func test_tick_rout_drains_stamina_at_sprint_rate() -> void:
	var rec := _rec(Unit.GAIT_JOG)
	var enemy := _rec()
	enemy.position = Vector2(0.0, 100.0)
	rec.stamina = 80.0
	FarTierRules.enter_rout(rec)
	FarTierRules.tick_rout(rec, enemy, 1.0)
	assert_almost_eq(rec.stamina, 80.0 - SoldierCombat.KAPPA_SPRINT, TOL,
			"routing movement applies the sprint rate on the far tier")


func test_tick_rout_bills_custom_sprint_drain_rate() -> void:
	var rec := _rec(Unit.GAIT_JOG)
	rec.stamina_sprint_drain_per_s = 7.5
	var enemy := _rec()
	enemy.position = Vector2(0.0, 100.0)
	rec.stamina = 80.0
	FarTierRules.enter_rout(rec)
	FarTierRules.tick_rout(rec, enemy, 1.0)
	assert_almost_eq(rec.stamina, 80.0 - 7.5, TOL,
			"routing movement applies the custom sprint drain rate")


func test_a_spent_formation_strikes_at_the_stamina_floor() -> void:
	var defender := _rec()
	var attacker := _rec()
	attacker.position = Vector2(0.0, 50.0)
	attacker.facing = Vector2.UP
	var fresh: float = FarTierRules.strike_expectation(attacker, defender)
	attacker.stamina = 0.0
	var spent: float = FarTierRules.strike_expectation(attacker, defender)
	assert_lt(spent, fresh, "a spent formation strikes worse")
	# attack 12 * g(0) 0.4 = 4.8, below the defender's defense 6, so the floor holds.
	assert_almost_eq(spent, 1.0, TOL)
	assert_almost_eq(FarTierRules.stamina_factor(attacker), SoldierCombat.COND_STAMINA_FLOOR, TOL)


# --- HUD readout -------------------------------------------------------------------------


func test_stat_sheet_reports_stamina_per_man() -> void:
	var hud = load("res://scripts/HUD.gd").new()
	add_child_autofree(hud)
	var u := _make_unit()
	hud.show_unit(u, 1)
	assert_string_contains(hud._info.text, "Stamina per man: 100 ±0 of 100",
			"an unseeded unit reads as a full pool")
	u._sim_soldier_hp = PackedFloat32Array([100.0, 100.0])
	u._sim_soldier_stamina = PackedFloat32Array([80.0, 60.0])
	hud.show_unit(u, 1)
	assert_string_contains(hud._info.text, "Stamina per man: 70 ±10 of 100",
			"mean and spread over every body, zero included")


func test_stat_sheet_reports_the_far_tiers_aggregate() -> void:
	var hud = load("res://scripts/HUD.gd").new()
	add_child_autofree(hud)
	var u := _make_unit()
	u.tier = FormationTier.FAR
	u.far_stamina = 35.0
	hud.show_unit(u, 1)
	assert_string_contains(hud._info.text, "Stamina per man: 35 ±0 of 100")


func test_mean_sd_counts_zero_entries() -> void:
	var v: Vector2 = UnitStats.mean_sd(PackedFloat32Array([0.0, 100.0]))
	assert_almost_eq(v.x, 50.0, TOL)
	assert_almost_eq(v.y, 50.0, TOL)
	assert_eq(UnitStats.mean_sd(PackedFloat32Array()), Vector2.ZERO)


func test_stat_sheet_stamina_skips_fallen_and_keeps_zero_stamina() -> void:
	var hud = load("res://scripts/HUD.gd").new()
	add_child_autofree(hud)
	var u := _make_unit()
	# 0: hp = 0.0 (fallen), stamina = 100.0 (dead body awaiting reap)
	# 1: hp = 50.0 (living), stamina = 0.0 (spent living soldier)
	# 2: hp = 50.0 (living), stamina = 60.0 (living soldier with stamina)
	u._sim_soldier_hp = PackedFloat32Array([0.0, 50.0, 50.0])
	u._sim_soldier_stamina = PackedFloat32Array([100.0, 0.0, 60.0])
	hud.show_unit(u, 1)
	# Living pool is 0.0 and 60.0: mean = 30, sd = 30.
	# The pre-fix readout averaged all entries including the fallen soldier (53 +- 41).
	assert_string_contains(hud._info.text, "Stamina per man: 30 ±30 of 100",
			"HUD stat sheet stamina readout excludes fallen soldiers and retains zero-stamina men")


# --- Cached combat profile and max_stamina scalar ---------------------------------------


func test_cached_max_stamina_stays_correct_after_loadout_change() -> void:
	var u := _make_unit(42)
	assert_almost_eq(u.max_stamina, 100.0, TOL, "default infantry max_stamina is 100")
	assert_almost_eq(u.combat_profile()["max_stamina"], 100.0, TOL)

	# Cavalry loadout switch
	u.is_cavalry = true
	assert_almost_eq(u.max_stamina, 120.0, TOL, "cavalry max_stamina is 120")
	assert_almost_eq(u.combat_profile()["max_stamina"], 120.0, TOL)

	# Ranged (archers) loadout switch
	u.is_cavalry = false
	u.is_ranged = true
	assert_almost_eq(u.max_stamina, 90.0, TOL, "ranged max_stamina is 90")
	assert_almost_eq(u.combat_profile()["max_stamina"], 90.0, TOL)

	# Spearmen (anti-cavalry) loadout switch
	u.is_ranged = false
	u.anti_cavalry = true
	assert_almost_eq(u.max_stamina, 100.0, TOL, "spearmen max_stamina is 100")
	assert_almost_eq(u.combat_profile()["max_stamina"], 100.0, TOL)

	# Panoply and training switch
	u.armor_type_id = LoadoutRegistry.ARMOR_SQUAMATA
	var squamata: Armor = LoadoutRegistry.armor(LoadoutRegistry.ARMOR_SQUAMATA)
	assert_almost_eq(u.combat_profile()["armour"], squamata.protection, TOL)
	u.mount_type_id = LoadoutRegistry.MOUNT_WARHORSE
	assert_true(u.combat_profile()["mass"] > 1.0)
	u.training = 0.75
	assert_almost_eq(u.combat_profile()["skill"], 0.75, TOL)
	assert_almost_eq(u.max_stamina, 100.0, TOL)

	# Cache rebuild path when profile is cleared
	u._cached_combat_profile.clear()
	assert_true(u._cached_combat_profile.is_empty())
	var prof: Dictionary = u.combat_profile()
	assert_false(prof.is_empty())
	assert_almost_eq(prof["max_stamina"], 100.0, TOL)


func test_far_tier_hot_paths_use_cached_max_stamina() -> void:
	var u := _make_unit(43)
	u.tier = FormationTier.FAR
	assert_almost_eq(u.mean_soldier_stamina(), 100.0, TOL, "unseeded far tier reads max_stamina")
	u.is_cavalry = true
	assert_almost_eq(u.mean_soldier_stamina(), 120.0, TOL, "unseeded cavalry far tier reads 120")

	u.far_stamina = 50.0
	assert_almost_eq(u.mean_soldier_stamina(), 50.0, TOL, "seeded far tier reads far_stamina")

	# Far-tier tick while unseeded starts from max_stamina
	var unseeded := _make_unit(44)
	unseeded.tier = FormationTier.FAR
	unseeded.current_order = Order.new_move(Vector2(0, 500), 0, Unit.GAIT_JOG)
	unseeded._current_speed = unseeded.jog_speed
	unseeded._tick_far_stamina(1.0)
	assert_almost_eq(unseeded.far_stamina, 100.0 - SoldierCombat.KAPPA_JOG, TOL)

	# Far-tier tick while seeded applies flow to existing pool
	u.current_order = Order.new_move(Vector2(0, 500), 0, Unit.GAIT_JOG)
	u._current_speed = u.jog_speed
	u._tick_far_stamina(1.0)
	assert_almost_eq(u.far_stamina, 50.0 - SoldierCombat.KAPPA_JOG, TOL)

	# Close tier unseeded reads max_stamina
	var close_u := _make_unit(45)
	close_u.tier = FormationTier.CLOSE
	close_u._sim_soldier_stamina.clear()
	assert_almost_eq(close_u.mean_soldier_stamina(), 100.0, TOL)


func test_far_tier_strike_expectation_reads_attacker_max_stamina() -> void:
	var attacker := _make_unit(46)
	var defender := _make_unit(47)
	attacker.tier = FormationTier.FAR
	defender.tier = FormationTier.FAR
	attacker.far_stamina = 100.0
	attacker.attack = 15
	defender.defense = 5
	var rate_inf: float = FarTierRates.strike_expectation(attacker, defender)
	assert_true(rate_inf > 0.0)

	attacker.is_cavalry = true
	attacker.far_stamina = 120.0
	var rate_cav: float = FarTierRates.strike_expectation(attacker, defender)
	assert_true(rate_cav > 0.0)


func test_snapshot_round_trip_preserves_cached_profile() -> void:
	var u := _make_unit(48)
	u.is_cavalry = true
	u.armor_type_id = LoadoutRegistry.ARMOR_SQUAMATA
	var snap: Dictionary = u.to_snapshot_dict()
	var restored := _make_unit(49)
	restored.apply_snapshot_dict(snap)
	assert_eq(restored.is_cavalry, true)
	assert_almost_eq(restored.max_stamina, 120.0, TOL)
	var squamata: Armor = LoadoutRegistry.armor(LoadoutRegistry.ARMOR_SQUAMATA)
	assert_almost_eq(restored.combat_profile()["armour"], squamata.protection, TOL)
