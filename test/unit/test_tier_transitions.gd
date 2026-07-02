extends GutTest
## TierTransition (docs/large-scale-simulation-design.md phase 3): the tier boundary in
## isolation. Demotion is a pure, RNG-free reduction — it drops the per-soldier arrays and
## leaves the unit's aggregate fields untouched. Promotion is a pure function of the
## aggregate state plus a deterministic seed hashed from already-serialized data (uid,
## promotion tick, battle seed): the same inputs always reconstruct the identical soldier
## layout, different inputs get an unrelated one, and the shared Replay.rng stream is never
## touched. The live-battle wiring (Battle._tick_tier_transitions) is covered separately in
## test_tier_transition_battle.


func _make_unit(unit_uid: int = 7) -> Unit:
	var u: Unit = Unit.new()
	u.uid = unit_uid
	u.max_soldiers = 10
	add_child_autofree(u)   # _ready() joins groups, seeds soldiers = max_soldiers
	return u


## A close-tier unit with its soldier bodies seeded, as a live pre-demotion unit would have.
func _make_seeded_unit(unit_uid: int = 7) -> Unit:
	var u := _make_unit(unit_uid)
	u.seed_sim_soldiers()
	return u


# --- can_demote ------------------------------------------------------------


func test_can_demote_a_fresh_idle_close_tier_unit() -> void:
	var u := _make_seeded_unit()
	assert_true(TierTransition.can_demote(u), "an idle, unengaged close-tier unit can demote")


func test_cannot_demote_an_already_far_unit() -> void:
	var u := _make_seeded_unit()
	u.tier = FormationTier.FAR
	assert_false(TierTransition.can_demote(u), "a far-tier unit has nothing left to demote")


func test_cannot_demote_a_fighting_unit() -> void:
	var u := _make_seeded_unit()
	u.state = Unit.State.FIGHTING
	assert_false(TierTransition.can_demote(u), "a fighting unit never demotes")


func test_cannot_demote_while_the_engaged_linger_runs() -> void:
	var u := _make_seeded_unit()
	u._engaged_linger = 0.25   # just left melee; the engaged latch is still hot
	assert_false(TierTransition.can_demote(u), "the engaged linger blocks demotion")


func test_cannot_demote_mid_maneuver_or_reform() -> void:
	# Each in-flight per-soldier context blocks demotion on its own: the aggregate record
	# cannot carry a half-finished turn, an owned facing set, a reform hold, a parked rear
	# march, or a relief interleave.
	var u := _make_seeded_unit()
	u._conversio_target = Vector2.RIGHT
	assert_false(TierTransition.can_demote(u), "an in-flight about-face blocks demotion")
	u._conversio_target = Vector2.ZERO
	u._quarter_target = Vector2.RIGHT
	assert_false(TierTransition.can_demote(u), "an in-flight quarter-turn blocks demotion")
	u._quarter_target = Vector2.ZERO
	u._wheel_target = Vector2.RIGHT
	assert_false(TierTransition.can_demote(u), "an in-flight wheel blocks demotion")
	u._wheel_target = Vector2.ZERO
	u._engage_turn_target = Vector2.RIGHT
	assert_false(TierTransition.can_demote(u), "an in-flight engage re-face blocks demotion")
	u._engage_turn_target = Vector2.ZERO
	u._per_soldier_facing = true
	assert_false(TierTransition.can_demote(u), "maneuver-owned soldier facings block demotion")
	u._per_soldier_facing = false
	u._reform_timer = 0.5
	assert_false(TierTransition.can_demote(u), "a reform hold blocks demotion")
	u._reform_timer = 0.0
	u._has_pending_march = true
	assert_false(TierTransition.can_demote(u), "a parked rear-move march blocks demotion")
	u._has_pending_march = false
	var partner := _make_seeded_unit(8)
	u._relief_partner = partner
	assert_false(TierTransition.can_demote(u), "a mid-relief swap blocks demotion")
	u._relief_partner = null
	assert_true(TierTransition.can_demote(u), "with every blocker cleared it can demote again")


# --- demote ----------------------------------------------------------------


func test_demote_drops_every_per_soldier_array() -> void:
	var u := _make_seeded_unit()
	assert_eq(u._sim_soldier_pos.size(), 10, "precondition: the bodies were seeded")
	TierTransition.demote(u)
	assert_eq(u.tier, FormationTier.FAR)
	assert_eq(u._sim_soldier_pos.size(), 0)
	assert_eq(u._sim_body_vel.size(), 0)
	assert_eq(u._sim_steer.size(), 0)
	assert_eq(u._sim_soldier_hp.size(), 0)
	assert_eq(u._sim_prone.size(), 0)
	assert_eq(u._sim_soldier_stamina.size(), 0)
	assert_eq(u._sim_soldier_weapon_id.size(), 0)
	assert_eq(u._sim_soldier_shield_id.size(), 0)
	assert_eq(u._sim_soldier_facing.size(), 0)
	assert_false(u._per_soldier_facing)


func test_demote_leaves_the_aggregate_fields_untouched() -> void:
	var u := _make_seeded_unit()
	u.soldiers = 7
	u.morale = 61.5
	u.position = Vector2(240.0, -80.0)
	u.facing = Vector2.RIGHT
	u.formation_mode = Unit.FORMATION_TIGHT
	u.order_mode = Unit.ORDER_HOLD
	TierTransition.demote(u)
	assert_eq(u.soldiers, 7, "the living count is the aggregate state — demotion keeps it")
	assert_eq(u.morale, 61.5)
	assert_eq(u.position.x, 240.0)
	assert_eq(u.position.y, -80.0)
	assert_eq(u.facing.x, 1.0)
	assert_eq(u.facing.y, 0.0)
	assert_eq(u.formation_mode, Unit.FORMATION_TIGHT)
	assert_eq(u.order_mode, Unit.ORDER_HOLD)


# --- promotion seed ----------------------------------------------------------


func test_promotion_seed_is_stable_and_input_sensitive() -> void:
	var base: int = TierTransition.promotion_seed(3, 240, 12345)
	assert_eq(TierTransition.promotion_seed(3, 240, 12345), base,
		"the same (uid, tick, battle seed) always derives the same seed")
	assert_ne(TierTransition.promotion_seed(4, 240, 12345), base, "a different unit differs")
	assert_ne(TierTransition.promotion_seed(3, 241, 12345), base, "a different tick differs")
	assert_ne(TierTransition.promotion_seed(3, 240, 54321), base, "a different battle differs")


# --- promote ---------------------------------------------------------------


func test_promote_reconstructs_one_body_per_living_soldier_on_the_grid() -> void:
	var u := _make_unit()
	u.soldiers = 7
	u.tier = FormationTier.FAR
	TierTransition.promote(u, 100, 12345)
	assert_eq(u.tier, FormationTier.CLOSE)
	assert_eq(u._sim_soldier_pos.size(), 7, "one body per living soldier — rear ranks absorbed the losses")
	assert_eq(u._sim_body_vel.size(), 7)
	assert_eq(u._sim_steer.size(), 7)
	assert_eq(u._sim_soldier_hp.size(), 7)
	assert_eq(u._sim_prone.size(), 7)
	assert_eq(u._sim_soldier_stamina.size(), 7)
	assert_eq(u._sim_soldier_weapon_id.size(), 7)
	assert_eq(u._sim_soldier_shield_id.size(), 7)
	assert_eq(u._sim_soldier_facing.size(), 7)
	# Each body lands within the seeded scatter of its own formation slot, at rest and standing.
	var slots: PackedVector2Array = u.soldier_world_slots(7)
	var scatter_r: float = Unit.FORMATION_SPACING * u.spacing_scale * TierTransition.SCATTER_FRACTION
	var max_stamina: float = u.combat_profile()["max_stamina"]
	for i in range(7):
		assert_lte(u._sim_soldier_pos[i].distance_to(slots[i]), scatter_r + 0.001,
			"body %d sits within the scatter radius of its slot" % i)
		assert_eq(u._sim_body_vel[i].x, 0.0)
		assert_eq(u._sim_body_vel[i].y, 0.0)
		assert_eq(u._sim_prone[i], 0.0, "everyone reconstructs standing")
		assert_eq(u._sim_soldier_stamina[i], max_stamina, "everyone reconstructs rested")
		assert_eq(u._sim_soldier_weapon_id[i], u.weapon_type_id)
		assert_eq(u._sim_soldier_shield_id[i], u.shield_type_id)
		# Both components asserted: a facing of (0, epsilon) must not pass as DOWN.
		assert_eq(u._sim_soldier_facing[i].x, u.facing.x)
		assert_eq(u._sim_soldier_facing[i].y, u.facing.y)
	assert_false(u._per_soldier_facing)


func test_promote_is_deterministic_for_the_same_inputs() -> void:
	# Two separate units with the same aggregate state, promoted with the same (uid, tick,
	# battle seed), reconstruct bit-identical layouts — the phase's core determinism claim.
	var a := _make_unit(3)
	var b := _make_unit(3)
	for u in [a, b]:
		u.soldiers = 6
		u.position = Vector2(400.0, 300.0)
		u.facing = Vector2.RIGHT
		u.tier = FormationTier.FAR
	TierTransition.promote(a, 240, 987654321)
	TierTransition.promote(b, 240, 987654321)
	assert_eq(a._sim_soldier_pos, b._sim_soldier_pos, "identical reconstructed positions")
	assert_eq(a._sim_soldier_hp, b._sim_soldier_hp, "identical reconstructed health")
	assert_eq(a._sim_soldier_facing, b._sim_soldier_facing, "identical reconstructed facings")


func test_promote_varies_with_the_promotion_tick() -> void:
	# The seed feeds through: a different promotion tick reconstructs a different scatter,
	# so the hash isn't decorative.
	var a := _make_unit(3)
	var b := _make_unit(3)
	for u in [a, b]:
		u.tier = FormationTier.FAR
	TierTransition.promote(a, 240, 12345)
	TierTransition.promote(b, 241, 12345)
	assert_ne(a._sim_soldier_pos, b._sim_soldier_pos,
		"a different promotion tick derives a different seeded layout")


func test_promote_never_draws_from_the_shared_replay_rng() -> void:
	# Promotion must not perturb the one seeded stream the battle's combat rolls draw from
	# — a draw here would desync every roll after the promotion tick on replay.
	var u := _make_unit()
	u.tier = FormationTier.FAR
	Replay.rng.seed = 424242
	var stream_state: int = Replay.rng.state
	TierTransition.promote(u, 100, 12345)
	assert_eq(Replay.rng.state, stream_state, "the shared Replay.rng stream is untouched")


func test_promote_at_full_strength_reconstructs_full_health() -> void:
	var u := _make_unit()
	u.tier = FormationTier.FAR
	TierTransition.promote(u, 100, 12345)
	var max_health: float = u.combat_profile()["max_health"]
	for i in range(u._sim_soldier_hp.size()):
		assert_eq(u._sim_soldier_hp[i], max_health,
			"an untouched formation reconstructs at exactly full health")


func test_promote_after_casualties_spreads_bounded_wounds() -> void:
	var u := _make_unit()
	u.soldiers = 6   # 4 of 10 lost: casualty fraction 0.4
	u.tier = FormationTier.FAR
	TierTransition.promote(u, 100, 12345)
	var max_health: float = u.combat_profile()["max_health"]
	var wound_cap: float = TierTransition.WOUND_SPREAD * 0.4
	var floor_hp: float = max_health * (1.0 - wound_cap)
	var wounded: int = 0
	for i in range(u._sim_soldier_hp.size()):
		assert_lte(u._sim_soldier_hp[i], max_health, "no survivor exceeds the pool")
		assert_gte(u._sim_soldier_hp[i], floor_hp, "no survivor spawns below the wound floor")
		if u._sim_soldier_hp[i] < max_health:
			wounded += 1
	assert_gt(wounded, 0, "a mauled formation carries visible wounds across its survivors")


# --- far-tier rendering ------------------------------------------------------


func test_far_tier_unit_still_draws_one_mark_per_living_soldier() -> void:
	# A demoted block must stay visible: with no bodies to mirror, the flock render draws
	# its marks on the formation grid itself. Driven through the real _process path
	# (frame awaits), since MultiMesh instance data isn't directly settable/readable
	# outside the engine's own flow; instance_count reads back fine headless.
	var u := _make_seeded_unit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(u._mm_body.instance_count, 10, "close tier mirrors the seeded bodies")
	TierTransition.demote(u)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(u._sim_soldier_pos.size(), 0, "a far-tier block carries no soldier bodies")
	assert_eq(u._mm_body.instance_count, 10,
		"yet it still draws one grid mark per living aggregate soldier")
	TierTransition.promote(u, 50, 12345)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(u._mm_body.instance_count, 10, "promotion hands the marks back to the real bodies")
	assert_eq(u._sim_soldier_pos.size(), 10)


func test_demote_then_promote_round_trip_is_consistent_with_the_aggregates() -> void:
	# The round trip is deterministic but NOT lossless: it must land count bodies back on
	# the formation grid around the same centre — a plausible layout for the aggregates —
	# not the exact pre-demotion bodies.
	var u := _make_seeded_unit()
	u.soldiers = 8
	u.position = Vector2(500.0, 300.0)
	TierTransition.demote(u)
	TierTransition.promote(u, 300, 12345)
	assert_eq(u._sim_soldier_pos.size(), 8, "the aggregate living count round-trips exactly")
	var centroid := Vector2.ZERO
	for p in u._sim_soldier_pos:
		centroid += p
	centroid /= 8.0
	# The grid is centred on the unit (a partial rear rank can offset the centroid less than
	# one spacing); the scatter adds at most SCATTER_FRACTION of a spacing on top.
	assert_lt(centroid.distance_to(u.position), Unit.FORMATION_SPACING * 1.5,
		"the reconstructed bodies centre on the aggregate position")
