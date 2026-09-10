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
	assert_eq(StaminaFlow.band_for_speed(0.0, 45.0, 67.5, 1.0), StaminaFlow.BAND_REST)
	assert_eq(StaminaFlow.band_for_speed(1.0, 45.0, 67.5, 1.0), StaminaFlow.BAND_REST)


func test_band_walk_from_the_epsilon_up_to_halfway_to_the_jog() -> void:
	assert_eq(StaminaFlow.band_for_speed(1.01, 45.0, 67.5, 1.0), Unit.GAIT_WALK)
	assert_eq(StaminaFlow.band_for_speed(45.0, 45.0, 67.5, 1.0), Unit.GAIT_WALK)
	assert_eq(StaminaFlow.band_for_speed(56.25, 45.0, 67.5, 1.0), Unit.GAIT_WALK,
			"the walk/jog boundary (the midpoint) still reads as a walk")


func test_band_jog_is_symmetric_about_the_jog_pace() -> void:
	# Walk 45, jog 67.5: the jog band is (56.25, 78.75], one half-step either side.
	assert_eq(StaminaFlow.band_for_speed(56.26, 45.0, 67.5, 1.0), Unit.GAIT_JOG)
	assert_eq(StaminaFlow.band_for_speed(67.5, 45.0, 67.5, 1.0), Unit.GAIT_JOG)
	assert_eq(StaminaFlow.band_for_speed(78.75, 45.0, 67.5, 1.0), Unit.GAIT_JOG)


func test_band_sprint_above_the_jog_band() -> void:
	assert_eq(StaminaFlow.band_for_speed(78.76, 45.0, 67.5, 1.0), Unit.GAIT_SPRINT)
	assert_eq(StaminaFlow.band_for_speed(90.0, 45.0, 67.5, 1.0), Unit.GAIT_SPRINT)


func test_band_a_jog_no_faster_than_the_walk_bills_walk_then_jog_and_never_sprint() -> void:
	# A degenerate pace order (loud via push_error) collapses the jog band, so the halfway
	# boundaries would otherwise bill every jog as a walk or a sprint. The explicit
	# fallback bills up to the walk pace as a walk and anything faster as a jog; the
	# sprint band has no jog pace to sit above. Both the equal and the inverted case.
	for jog in [45.0, 40.0]:
		assert_eq(StaminaFlow.band_for_speed(0.5, 45.0, jog, 1.0), StaminaFlow.BAND_REST,
			"rest is unaffected, jog_speed %s" % jog)
		assert_eq(StaminaFlow.band_for_speed(45.0, 45.0, jog, 1.0), Unit.GAIT_WALK,
			"at the walk pace, jog_speed %s" % jog)
		assert_push_error("is not above walk_speed")
		assert_eq(StaminaFlow.band_for_speed(45.01, 45.0, jog, 1.0), Unit.GAIT_JOG,
			"just above the walk pace, jog_speed %s" % jog)
		assert_push_error("is not above walk_speed")
		assert_eq(StaminaFlow.band_for_speed(200.0, 45.0, jog, 1.0), Unit.GAIT_JOG,
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
	u.stamina_jog_drain_per_s = 1.5
	u.current_order = Order.new_move(Vector2(0, 500), 0, Unit.GAIT_JOG)
	var rec := FarTierFormation.from_unit(u)
	assert_eq(rec.gait, Unit.GAIT_JOG)
	assert_almost_eq(rec.jog_speed, 60.0, TOL)
	assert_almost_eq(rec.stamina, 70.0, TOL)
	assert_almost_eq(rec.max_stamina, u.combat_profile()["max_stamina"], TOL)
	assert_almost_eq(rec.stamina_jog_drain_per_s, 1.5, TOL)
	assert_almost_eq(rec.stamina_rest_regen_per_s, SoldierCombat.RHO_STAMINA, TOL)


func test_gait_for_ordered_collapses_to_walk_or_jog() -> void:
	assert_eq(FarTierFormation.gait_for_ordered(-1), Unit.GAIT_WALK, "AUTO marches at the walk")
	assert_eq(FarTierFormation.gait_for_ordered(Unit.GAIT_WALK), Unit.GAIT_WALK)
	assert_eq(FarTierFormation.gait_for_ordered(Unit.GAIT_JOG), Unit.GAIT_JOG)
	assert_eq(FarTierFormation.gait_for_ordered(Unit.GAIT_RUN), Unit.GAIT_JOG,
			"a run's sustained leg is a jog")
	assert_eq(FarTierFormation.gait_for_ordered(Unit.GAIT_SPRINT), Unit.GAIT_JOG,
			"the sprint burst is below the far tier's resolution")


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


func test_tick_recovery_rests_the_pool_back_up() -> void:
	var rec := _rec()
	rec.stamina = 50.0
	FarTierRules.tick_recovery(rec, 1.0)
	assert_almost_eq(rec.stamina, 50.0 + SoldierCombat.RHO_STAMINA, TOL)
	rec.stamina = rec.max_stamina - 1.0
	FarTierRules.tick_recovery(rec, 1.0)
	assert_almost_eq(rec.stamina, rec.max_stamina, TOL, "capped at full")


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
